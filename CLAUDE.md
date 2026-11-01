# CLAUDE.md — skynet-blog

## Overview
Source of the static blog: Zola 0.23.6 + tabi v5.0.0 (skin `evangelion`), content in English.
Published to Cloudflare R2 (a preview bucket behind Cloudflare Access, and a production bucket) from
GitHub Actions on GitHub-hosted runners. Decisions and evidence live in the infrastructure repository:
`docs/blog.md` in palmalex/skynet-control-plane (Objective #749).

This repository is PUBLIC. Never commit secrets, internal IPs, hostnames of the lab beyond the public
site, tailnet details, or a draft that must stay private (history is readable by everyone).

## Layout
- `content/` home, `about.md` and posts in `content/blog/<slug>/index.md` (Markdown + TOML front matter, `draft = true` stays out of the build)
- `static/img/favicon.png`, `config.toml` (site name "Idle Cycle", base URL of production)
- `themes/tabi` is NOT committed: `build.sh` clones it at commit 606f4b28aef052e8a716fe947c0166913731e339 into a git-ignored folder, like the pinned Zola in `.cache/`
- `build.sh [build [production|preview]|check|serve]`; `check` also proves that two builds of the same commit are identical and that the preview and production builds differ only in the hostname
- `check_links.py` fails `check` on a broken internal link; `./build.sh links` checks the external ones (advisory in CI); preview builds include the drafts, production never
- `check_output.py` reads the posts and drafts from the front matter: a new post needs no change there
- `.github/workflows/` `checks.yml` (required status check `checks`), `pool-probe.yml` (manual boundary test)
- The theme is used whole (about 250 files, 8 MB): pruning it is tracked as #826 in the infrastructure repository

## Rules
- Workflows: `pull_request` only, never `pull_request_target`; `permissions: contents: read` at the top;
  third-party actions pinned to a commit; no self-hosted runner, no label of the infrastructure pool.
- `main` is protected by a ruleset: changes go through a pull request with the `checks` check green.
- Deploy only from `main`, through the `preview` and `production` environments; each R2 token is a secret
  of its own environment, never a repository secret.
- Publish with an S3 client (rclone), not with wrangler (portability, decided in #749).

## Way of working
General rules (read-only, "ti autorizzo", Italian chat / English files) are in `~/.claude/CLAUDE.md`.
