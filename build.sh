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

# build_to <output dir> <base url>
build_to() {
  rm -rf "$1"
  "$zola" build --base-url "$2" --output-dir "$1"
}

build() {
  local url
  case "${1:-production}" in
    production) url="$HOST_PRODUCTION" ;;
    preview)
      url="$HOST_PREVIEW"
      if [ -n "${2:-}" ]; then
        [[ "$2" =~ ^[a-z0-9-]+$ ]] || { echo "build.sh: invalid preview prefix '$2'" >&2; exit 2; }
        url="$HOST_PREVIEW/$2"
      fi
      ;;
    *) echo "build.sh: unknown target '$1' (production or preview)" >&2; exit 2 ;;
  esac
  build_to public "${BASE_URL:-$url}"
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
}

fetch_zola
fetch_tabi
case "${1:-build}" in
  build) build "${2:-production}" "${3:-}" ;;
  check) check ;;
  serve) "$zola" serve --base-url http://127.0.0.1:1111 --interface 127.0.0.1 ;;
  *) echo "usage: $0 [build [production|preview [prefix]]|check|serve]" >&2; exit 2 ;;
esac
