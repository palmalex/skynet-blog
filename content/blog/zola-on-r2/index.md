+++
title = "Why this site is Zola on Cloudflare R2"
date = 2026-10-19
description = "How I picked the generator, the theme and the store for this site, with the measurements and the things I gave up."

[taxonomies]
tags = ["meta", "infrastructure"]
+++

I wanted a site I could write in git, preview privately and publish from CI, with as few moving parts as possible. Before building anything I wrote the requirements down: Markdown with front matter, drafts kept out of the build, a feed, a sitemap, highlighting at build time, search without a server, and one pinned binary rather than a tree of dependencies.

## The generator

I built the same small site with Hugo, Zola and Eleventy. With three posts the time is the start of the program; with 500 generated posts the median of five builds was 0.38 s for Zola, 0.67 s for Hugo and 1.35 s for Eleventy. Speed did not decide it. Eleventy needed plugins for drafts, a feed, images and highlighting, and a sitemap written by hand; Astro put 141 MB in `node_modules` before the first page. Hugo is a fully valid choice with the biggest theme ecosystem, and it lost on fit: the theme closest to what I wanted did not work with the current Hugo without a fix.

Zola does everything in one static binary. I pin the version and the sha256 of the release, because Zola publishes no checksum, and the theme at a commit.

## The store

I tested R2 and Oracle's Object Storage, both behind Cloudflare on the Free plan. R2 gave me a custom domain, a rewrite rule for directory indexes and a Worker only for the 404 page. Oracle's free tier allows 50,000 requests a month in total, against 1,000,000 writes and 10,000,000 reads on R2, and the `Host` header override a custom domain needs is not available on the Free plan. On my own traffic assumptions (3,000 page views a month and twenty deploys) a month would have used about half of Oracle's allowance.

## What I gave up

Cloudflare Pages and Workers static assets would have been less work. I left them out for lock-in: the site is published with a plain S3 client, so moving it means changing an endpoint. Zola is still `0.x`, the theme ships about 6 MB of JavaScript and 1.5 MB of fonts that most pages never load, and a Worker sits in the path of every request. I accepted all three, and I have written down why.

The numbers above come from one laptop and a sample site, not from this site under load. I will report back when there are real ones.
