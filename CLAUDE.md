# CLAUDE.md — skynet-blog

## Overview
Source of the static blog: Zola 0.23.6 + tabi v5.0.0 (skin `evangelion`), content in English.
Published to Cloudflare R2 (a preview bucket behind Cloudflare Access, and a production bucket) from
GitHub Actions on GitHub-hosted runners. Decisions and evidence live in the infrastructure repository:
`docs/blog.md` in palmalex/skynet-control-plane (Objective #749).

This repository is PUBLIC. Never commit secrets, internal IPs, hostnames of the lab beyond the public
site, tailnet details, or a draft that must stay private (history is readable by everyone).

## Layout (target, scaffold is #754)
- `content/` posts and pages (Markdown + front matter, `draft: true` stays out of the build)
- `themes/tabi` pinned at commit 606f4b28aef052e8a716fe947c0166913731e339
- `build.sh` downloads Zola (sha256 checked), builds, and with `check` validates feed, sitemap and drafts
- `.github/workflows/` `checks.yml` (required status check `checks`), `pool-probe.yml` (manual boundary test)

## Rules
- Workflows: `pull_request` only, never `pull_request_target`; `permissions: contents: read` at the top;
  third-party actions pinned to a commit; no self-hosted runner, no label of the infrastructure pool.
- `main` is protected by a ruleset: changes go through a pull request with the `checks` check green.
- Deploy only from `main`, through the `preview` and `production` environments; each R2 token is a secret
  of its own environment, never a repository secret.
- Publish with an S3 client (rclone), not with wrangler (portability, decided in #749).

## Way of working
General rules (read-only, "ti autorizzo", Italian chat / English files) are in `~/.claude/CLAUDE.md`.
