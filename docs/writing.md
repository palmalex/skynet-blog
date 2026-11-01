# Writing a post

A post is a folder in `content/blog/<slug>/` with an `index.md`. The slug becomes the URL (`/blog/<slug>/`).

## Template

```toml
+++
title = "A title that says what the post is about"
date = 2026-11-01
description = "One or two sentences: shown in the list, the feed and the search results."
draft = true

[taxonomies]
tags = ["meta"]
+++

Opening paragraph.

## A section

...
```

Remove `draft = true` when the post is ready to be published.

## Draft, preview, publication

1. Work on a branch and open a pull request. The preview of the pull request (`https://blog-preview.palmalex.cc/pr-<N>/`,
   owner login required) is built **with** the drafts, so a draft can be read there.
2. A draft is never in the production build, the feed, the sitemap or the search index.
3. To publish: remove `draft = true`, merge. The merge builds the site, shows it in the preview of `main`
   and waits for the approval of the `production` environment.

The repository is public: a draft in a branch or a pull request is readable by anyone who finds it. Do not put
anything private in it.

## Images

- Every image of the built site must be at most **200 KB** (`check` fails otherwise).
- For a photo or a screenshot, put the original in the post folder with a name like `photo.src.png` and use the
  component. It scales the image to the given width (default 800), converts it to WebP and never publishes the
  original:

  ```
  {{< resized_image src="photo.src.png" alt="What the picture shows" width="800" />}}
  ```

- Small images (icons, diagrams of a few KB) can be linked as they are: `![alt](diagram.png)`.
- Always write the `alt` text.

## Checks

`./build.sh check` runs the same checks as the `checks` job: build, feed, sitemap, reproducibility, internal links, image
budget and the proof that a draft stays out of production. `./build.sh html` validates the HTML (needs java, or docker as
a fallback). `./build.sh links` checks the external links; in CI it only warns, because a site that is down is not a reason
to block a post. `./build.sh serve` shows the site on http://127.0.0.1:1111, drafts included, and rebuilds when a file changes.
