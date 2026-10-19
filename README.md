# Idle Cycle

Source of the static site at <https://blog.palmalex.cc>: [Zola](https://www.getzola.org) 0.23.6 with the
[tabi](https://github.com/welpo/tabi) theme (v5.0.0, skin `evangelion`), written in English. The decisions
behind it (generator, theme, store, repository and runner) and the measurements are recorded in
`docs/blog.md` of the infrastructure repository, `palmalex/skynet-control-plane`.

## Build and preview locally

```bash
./build.sh                  # build the production site into public/
./build.sh build preview    # the same with the preview base URL
./build.sh serve            # build and serve on http://127.0.0.1:1111
./build.sh check            # build, validate, and prove the two properties below
```

The first run downloads Zola (the sha256 of the release is checked) and clones tabi at the pinned commit,
both into git-ignored directories (`.cache/`, `themes/`). Only `x86_64` is pinned.

`./build.sh check` fails unless:

- the Atom feed is well formed, the sitemap matches the sitemaps.org schema, every published post is in both,
  no draft is in the output, and `404.html`, `robots.txt` and the favicon are there;
- **two builds of the same commit are identical**, byte for byte;
- **the preview build differs from the production one only in the hostname**: swapping the preview host for
  the production one in the preview output gives the production output.

## Layout

| Path | What |
|---|---|
| `content/` | the home page, `about.md` and the posts in `content/blog/<slug>/index.md` (`draft = true` keeps a post out of the build) |
| `static/img/favicon.png` | the favicon |
| `config.toml` | site configuration; `base_url` is the production hostname, `build.sh` overrides it |
| `build.sh`, `check_output.py` | the build and its checks |
| `.github/workflows/` | `checks.yml` (the required check, #752) and `pool-probe.yml` (a manual test that the infrastructure runners are not reachable from this repository) |

## Writing a post

Create `content/blog/<slug>/index.md` with this front matter (a draft stays out of the build and the feed):

```toml
+++
title = "..."
date = 2026-10-19
description = "..."
draft = true

[taxonomies]
tags = ["..."]
+++
```

This repository is public, so a draft committed to a branch is readable by anyone: do not push a post that
must stay private.

## Publishing

Pull requests are built and checked; the preview and production publication from GitHub Actions are tracked
in the Objective #749 of the infrastructure repository.
