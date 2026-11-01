#!/usr/bin/env bash
# Builds the site with the pinned Zola and tabi (#750, #754; decisions in docs/blog.md of the
# infrastructure repository).
#
#   ./build.sh                 build the production site into public/
#   ./build.sh build preview   build with the preview base URL
#   ./build.sh build preview pr-7
#                              build for one pull request: the preview URL plus a path prefix (#755)
#   ./build.sh check           build, validate the output, then prove the two properties the publish relies on:
#                              two builds of the same commit are identical, and the preview and production
#                              builds differ only in the hostname
#   ./build.sh links           check the external links (needs the network; advisory in CI, not part of `check`)
#   ./build.sh html            validate the production HTML with the Nu Html Checker (needs java or docker)
#   ./build.sh serve           build and serve on http://127.0.0.1:1111
#
# Everything it downloads goes under .cache/ and themes/ (git-ignored). BASE_URL overrides the base URL of `build`.
set -euo pipefail

ZOLA_VERSION=0.23.6
ZOLA_TARBALL="zola-v${ZOLA_VERSION}-x86_64-unknown-linux-musl.tar.gz"
# Zola publishes no checksum file: this is the sha256 of the release asset when it was pinned (2026-10-18).
ZOLA_SHA256=7d77a4220a4f699cba2fc0e0c7859f780e887e269159ad4fab90e11ea16c906f
TABI_TAG=v5.0.0
# The commit the tag pointed to when it was pinned: a moved tag fails the build instead of changing it.
TABI_COMMIT=606f4b28aef052e8a716fe947c0166913731e339
# Pinned for the `check` step only.
FEEDPARSER_VERSION=6.0.14
LXML_VERSION=6.1.3
SITEMAP_XSD_URL=https://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd

# Size budget of every image of the output (#758).
IMAGE_BUDGET_BYTES=204800
# The HTML validator (Nu Html Checker, the engine of validator.w3.org/nu) from the immutable npm release; sha256
# computed when it was pinned (2026-11-01), the npm registry also publishes sha512 Zg67G1zM...
VNU_VERSION=26.10.12
VNU_SHA256=3925f07364f5e5a111cef54a7baefa575b22d05c70f8ced048f0616d4579b7ab
# Errors of the theme (tabi v5.0.0) that are known and not ours: a duplicated 'self' in its Content-Security-Policy
# meta tag and a <span> inside the <ul class="meta"> of a post. Anything else fails; pruning or fixing the theme
# is #826.
VNU_KNOWN_THEME_ERRORS="Duplicate source-expression|Element .span. not allowed as child of element .ul."

HOST_PRODUCTION=https://blog.palmalex.cc
HOST_PREVIEW=https://blog-preview.palmalex.cc

cd "$(dirname "$0")"
cache=.cache
zola="$cache/zola-$ZOLA_VERSION/zola"

fetch_zola() {
  [ -x "$zola" ] && return 0
  [ "$(uname -m)" = x86_64 ] || { echo "build.sh: only x86_64 is pinned, found $(uname -m)" >&2; exit 1; }
  mkdir -p "$cache/zola-$ZOLA_VERSION"
  echo "downloading Zola $ZOLA_VERSION"
  curl -fsSL --retry 3 -o "$cache/$ZOLA_TARBALL" \
    "https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/${ZOLA_TARBALL}"
  (cd "$cache" && echo "$ZOLA_SHA256  $ZOLA_TARBALL" | sha256sum -c -)
  tar -xzf "$cache/$ZOLA_TARBALL" -C "$cache/zola-$ZOLA_VERSION" zola
  [ "$("$zola" --version)" = "zola $ZOLA_VERSION" ] || { echo "build.sh: unexpected Zola version" >&2; exit 1; }
}

fetch_tabi() {
  if [ ! -d themes/tabi ]; then
    echo "cloning tabi $TABI_TAG"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TABI_TAG" https://github.com/welpo/tabi themes/tabi
  fi
  [ "$(git -C themes/tabi rev-parse HEAD)" = "$TABI_COMMIT" ] \
    || { echo "build.sh: themes/tabi is not at the pinned commit $TABI_COMMIT" >&2; exit 1; }
}

# build_to <output dir> <base url> [extra zola build flags]
build_to() {
  local out=$1 url=$2
  shift 2
  # Zola writes the images it processes into static/: start from none, so no leftover of an earlier build is published
  rm -rf "$out" static/processed_images
  "$zola" build --base-url "$url" --output-dir "$out" "$@"
}

build() {
  local url
  local flags=()
  case "${1:-production}" in
    production) url="$HOST_PRODUCTION" ;;
    preview)
      url="$HOST_PREVIEW"
      # The preview shows the drafts; production never does (#758).
      flags=(--drafts)
      if [ -n "${2:-}" ]; then
        [[ "$2" =~ ^[a-z0-9-]+$ ]] || { echo "build.sh: invalid preview prefix '$2'" >&2; exit 2; }
        url="$HOST_PREVIEW/$2"
      fi
      ;;
    *) echo "build.sh: unknown target '$1' (production or preview)" >&2; exit 2 ;;
  esac
  build_to public "${BASE_URL:-$url}" ${flags[@]+"${flags[@]}"}
  echo "built: $(find public -type f | wc -l) files, $(du -sb public | cut -f1) bytes"
}

check() {
  if [ ! -x "$cache/venv/bin/python" ]; then
    python3 -m venv "$cache/venv"
    "$cache/venv/bin/pip" install --quiet "feedparser==$FEEDPARSER_VERSION" "lxml==$LXML_VERSION"
  fi
  [ -f "$cache/sitemap.xsd" ] || curl -fsSL --retry 3 -o "$cache/sitemap.xsd" "$SITEMAP_XSD_URL"

  build production
  "$cache/venv/bin/python" check_output.py public "$cache/sitemap.xsd" content
  "$cache/venv/bin/python" -I check_links.py public "$HOST_PRODUCTION"
  "$cache/venv/bin/python" -I check_images.py public "$IMAGE_BUDGET_BYTES"

  # Two builds of the same commit must be identical, byte for byte.
  build_to "$cache/out-a" "$HOST_PRODUCTION" >/dev/null
  build_to "$cache/out-b" "$HOST_PRODUCTION" >/dev/null
  diff -r "$cache/out-a" "$cache/out-b" >/dev/null \
    || { echo "build.sh: two builds of the same commit differ:" >&2; diff -rq "$cache/out-a" "$cache/out-b" >&2; exit 1; }
  echo "reproducible: two builds of the same commit are identical"

  # The preview build must differ from the production one only in the hostname: swap it back and compare.
  build_to "$cache/out-preview" "$HOST_PREVIEW" >/dev/null
  rm -rf "$cache/out-swapped"
  cp -r "$cache/out-preview" "$cache/out-swapped"
  grep -rlI "$HOST_PREVIEW" "$cache/out-swapped" | xargs -r sed -i "s#$HOST_PREVIEW#$HOST_PRODUCTION#g"
  diff -r "$cache/out-a" "$cache/out-swapped" >/dev/null \
    || { echo "build.sh: the preview build differs from production beyond the hostname:" >&2; diff -rq "$cache/out-a" "$cache/out-swapped" >&2; exit 1; }
  echo "base URL: preview and production differ only in the hostname"

  # A pull request preview lives under a path prefix of the preview host: swapping host and prefix back must
  # also give the production output, so no link is lost or hard-coded outside the base URL.
  build_to "$cache/out-pr" "$HOST_PREVIEW/pr-0" >/dev/null
  grep -rlI "$HOST_PREVIEW/pr-0" "$cache/out-pr" | xargs -r sed -i "s#$HOST_PREVIEW/pr-0#$HOST_PRODUCTION#g"
  diff -r "$cache/out-a" "$cache/out-pr" >/dev/null \
    || { echo "build.sh: the pull request preview differs from production beyond host and prefix:" >&2; diff -rq "$cache/out-a" "$cache/out-pr" >&2; exit 1; }
  echo "base URL: a pull request preview differs only in host and prefix"

  # A draft is built in the preview and leaves no trace in production. Proved with a throw-away draft added to
  # content/ (removed by the trap, whatever happens): without --drafts the output must be identical to the real
  # one; with --drafts the page and its entry in the blog list must exist, so the first half is not true only
  # because the draft was never read.
  local fx_draft=content/blog/draft-fixture fx_link=content/blog/link-fixture
  trap 'rm -rf content/blog/draft-fixture content/blog/link-fixture content/blog/image-big-fixture content/blog/image-resize-fixture content/blog/draft-checks-fixture static/processed_images' EXIT
  rm -rf "$fx_draft" "$fx_link"
  mkdir -p "$fx_draft"
  printf '+++\ntitle = "Draft fixture"\ndate = 2026-11-01\ndraft = true\n+++\n\nA draft.\n' > "$fx_draft/index.md"
  build_to "$cache/out-fx-prod" "$HOST_PRODUCTION" >/dev/null
  diff -r "$cache/out-a" "$cache/out-fx-prod" >/dev/null \
    || { echo "build.sh: a draft changed the production output:" >&2; diff -rq "$cache/out-a" "$cache/out-fx-prod" >&2; exit 1; }
  build_to "$cache/out-fx-draft" "$HOST_PREVIEW" --drafts >/dev/null
  [ -f "$cache/out-fx-draft/blog/draft-fixture/index.html" ] \
    && grep -q "draft-fixture" "$cache/out-fx-draft/blog/index.html" \
    || { echo "build.sh: the draft is missing from the build with --drafts" >&2; exit 1; }
  echo "drafts: built with --drafts, absent from the production output (pages, list, feed, sitemap, search index)"
  rm -rf "$fx_draft"

  # The drafts are published in the preview, so the link and image checks also run on the build that includes them:
  # the real content first, then a draft with a broken link and an oversized image, which both checks must refuse
  # (production does not build it, so the checks above would never see it).
  build_to "$cache/out-drafts" "$HOST_PREVIEW" --drafts >/dev/null
  "$cache/venv/bin/python" -I check_links.py "$cache/out-drafts" "$HOST_PREVIEW" \
    && "$cache/venv/bin/python" -I check_images.py "$cache/out-drafts" "$IMAGE_BUDGET_BYTES" \
    || { echo "build.sh: the build with the drafts fails the link or image check (see above)" >&2; exit 1; }
  local fx_dc=content/blog/draft-checks-fixture
  mkdir -p "$fx_dc"
  printf '+++\ntitle = "Draft checks fixture"\ndate = 2026-11-01\ndraft = true\n+++\n\n[broken](/blog/does-not-exist/)\n\n![big](big.png)\n' > "$fx_dc/index.md"
  "$cache/venv/bin/python" -I check_images.py fixture "$fx_dc/big.png" 1600 1200
  build_to "$cache/out-fx-dc" "$HOST_PREVIEW" --drafts >/dev/null
  build_to "$cache/out-fx-dc-prod" "$HOST_PRODUCTION" >/dev/null
  rm -rf "$fx_dc"
  if "$cache/venv/bin/python" -I check_links.py "$cache/out-fx-dc" "$HOST_PREVIEW" > "$cache/fx-dc-links.log" 2>&1 \
    || ! grep -q "does-not-exist" "$cache/fx-dc-links.log"; then
    echo "build.sh: the link check did not refuse a broken link in a draft" >&2; exit 1
  fi
  if "$cache/venv/bin/python" -I check_images.py "$cache/out-fx-dc" "$IMAGE_BUDGET_BYTES" > "$cache/fx-dc-images.log" 2>&1 \
    || ! grep -q "big.png" "$cache/fx-dc-images.log"; then
    echo "build.sh: the image check did not refuse an oversized image in a draft" >&2; exit 1
  fi
  "$cache/venv/bin/python" -I check_images.py "$cache/out-fx-dc-prod" "$IMAGE_BUDGET_BYTES" >/dev/null \
    || { echo "build.sh: the draft reached the production build" >&2; exit 1; }
  echo "drafts: the build with the drafts is checked too (broken link and oversized image refused; production does not build them)"

  # A broken internal link must fail the link check (the real site passed it above).
  mkdir -p "$fx_link"
  printf '+++\ntitle = "Link fixture"\ndate = 2026-11-01\n+++\n\n[broken](/blog/does-not-exist/)\n' > "$fx_link/index.md"
  build_to "$cache/out-fx-link" "$HOST_PRODUCTION" >/dev/null
  rm -rf "$fx_link"
  if "$cache/venv/bin/python" -I check_links.py "$cache/out-fx-link" "$HOST_PRODUCTION" > "$cache/fx-link.log" 2>&1; then
    echo "build.sh: the link check accepted a broken internal link" >&2; exit 1
  fi
  grep -q "does-not-exist" "$cache/fx-link.log" \
    || { echo "build.sh: the link check failed, but not on the broken link:" >&2; cat "$cache/fx-link.log" >&2; exit 1; }
  echo "links: a broken internal link is caught"

  # An image over the budget fails the check; the same image through the resized_image component (scaled, WebP,
  # source not published) passes.
  local fx_big=content/blog/image-big-fixture fx_resize=content/blog/image-resize-fixture
  mkdir -p "$fx_big"
  printf '+++\ntitle = "Image fixture"\ndate = 2026-11-01\n+++\n\n![big](big.png)\n' > "$fx_big/index.md"
  "$cache/venv/bin/python" -I check_images.py fixture "$fx_big/big.png" 1600 1200
  build_to "$cache/out-fx-big" "$HOST_PRODUCTION" >/dev/null
  rm -rf "$fx_big"
  if "$cache/venv/bin/python" -I check_images.py "$cache/out-fx-big" "$IMAGE_BUDGET_BYTES" > "$cache/fx-img.log" 2>&1; then
    echo "build.sh: the image check accepted an image over the budget" >&2; exit 1
  fi
  grep -q "big.png" "$cache/fx-img.log" \
    || { echo "build.sh: the image check failed, but not on the big image:" >&2; cat "$cache/fx-img.log" >&2; exit 1; }
  mkdir -p "$fx_resize"
  printf '+++\ntitle = "Resize fixture"\ndate = 2026-11-01\n+++\n\n{{< resized_image src="photo.src.png" alt="noise" width="600" />}}\n' > "$fx_resize/index.md"
  "$cache/venv/bin/python" -I check_images.py fixture "$fx_resize/photo.src.png" 1600 1200
  build_to "$cache/out-fx-resize" "$HOST_PRODUCTION" >/dev/null
  rm -rf "$fx_resize"
  [ -z "$(find "$cache/out-fx-resize" -name '*.src.png')" ] && [ -n "$(find "$cache/out-fx-resize/processed_images" -name '*.webp')" ] \
    || { echo "build.sh: the resized image is missing or its source was published" >&2; exit 1; }
  "$cache/venv/bin/python" -I check_images.py "$cache/out-fx-resize" "$IMAGE_BUDGET_BYTES" >/dev/null \
    || { echo "build.sh: the resized image is over the budget" >&2; exit 1; }
  echo "images: an image over the budget is caught, a scaled WebP of it passes"
}

fetch_vnu() {
  [ -f "$cache/vnu/vnu.jar" ] && return 0
  mkdir -p "$cache/vnu"
  echo "downloading the HTML validator $VNU_VERSION"
  curl -fsSL --retry 3 -o "$cache/vnu-jar-$VNU_VERSION.tgz" "https://registry.npmjs.org/vnu-jar/-/vnu-jar-$VNU_VERSION.tgz"
  (cd "$cache" && echo "$VNU_SHA256  vnu-jar-$VNU_VERSION.tgz" | sha256sum -c -)
  tar -xzf "$cache/vnu-jar-$VNU_VERSION.tgz" -C "$cache/vnu" --strip-components=3 package/build/dist/vnu.jar
}

# run_vnu <vnu arguments>: java if there is one (CI), else a Java container (a laptop without Java)
run_vnu() {
  if command -v java >/dev/null; then
    java -jar "$cache/vnu/vnu.jar" "$@"
  elif command -v docker >/dev/null; then
    docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jre java -jar "$cache/vnu/vnu.jar" "$@"
  else
    echo "build.sh: html needs java or docker" >&2; exit 1
  fi
}

# vnu_errors <dir>: the errors of the validator for <dir> that are not a known error of the theme, one per line. The
# known ones are dropped here, on the full line, because --filterpattern only sees the first sentence of a message.
# Fails (and prints the output) when the validator stops with an error but reports none, e.g. a crash.
vnu_errors() {
  local log="$cache/vnu.log" status=0
  run_vnu --skip-non-html --errors-only "$1" > "$log" 2>&1 || status=$?
  if [ "$status" -ne 0 ] && ! grep -q ': error: ' "$log"; then
    echo "build.sh: the HTML validator failed without reporting an error:" >&2; cat "$log" >&2; return 1
  fi
  grep ': error: ' "$log" | grep -vE "$VNU_KNOWN_THEME_ERRORS" || true
}

# html: the production build must be valid HTML, apart from the known errors of the theme. A page that is not valid
# must be reported first, otherwise a validator that reports nothing would pass.
html() {
  fetch_vnu
  local bad="$cache/vnu-bad" errors
  rm -rf "$bad"; mkdir -p "$bad"
  printf '<!doctype html><html lang=en><head><meta charset=utf-8><title>t</title></head><body><ul><div>x</div></ul></body></html>' > "$bad/index.html"
  [ -n "$(vnu_errors "$bad")" ] \
    || { echo "build.sh: the HTML validator did not report a page that is not valid" >&2; exit 1; }
  build production
  errors=$(vnu_errors public)
  if [ -n "$errors" ]; then
    echo "build.sh: the HTML is not valid:" >&2; printf '%s\n' "$errors" >&2; exit 1
  fi
  echo "html: valid, apart from the known errors of the theme ($VNU_KNOWN_THEME_ERRORS)"
}

fetch_zola
fetch_tabi
case "${1:-build}" in
  build) build "${2:-production}" "${3:-}" ;;
  check) check ;;
  links) "$zola" check ;;
  html) html ;;
  serve) "$zola" serve --drafts --base-url http://127.0.0.1:1111 --interface 127.0.0.1 ;;
  *) echo "usage: $0 [build [production|preview [prefix]]|check|links|html|serve]" >&2; exit 2 ;;
esac
