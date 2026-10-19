"""Checks the output of the site (run by `build.sh check`): feed, sitemap, 404 page, favicon, drafts.

Usage: check_output.py <output dir> <sitemap.xsd> <content dir>
The posts that must be published and the drafts that must not are read from the front matter of
content/blog, so adding a post needs no change here. The feed is parsed with feedparser (it must be well
formed and complete) and the sitemap is validated against the sitemaps.org schema. This is a local check,
not the W3C Feed Validation Service, which would need the feed to be sent to a third party.
"""
import os
import sys
import tomllib

import feedparser
from lxml import etree

out, xsd_path, content = sys.argv[1], sys.argv[2], sys.argv[3]
failures = []


def front_matter(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return tomllib.loads(text.split("+++", 2)[1]) if text.startswith("+++") else {}


published, drafts = [], []
blog = os.path.join(content, "blog")
for name in sorted(os.listdir(blog)):
    if name.startswith("_"):
        continue
    path = os.path.join(blog, name)
    page = os.path.join(path, "index.md") if os.path.isdir(path) else path
    if not page.endswith(".md") or not os.path.exists(page):
        continue
    slug = name[:-3] if name.endswith(".md") else name
    (drafts if front_matter(page).get("draft") else published).append(slug)

feed = feedparser.parse(os.path.join(out, "atom.xml"))
if feed.bozo:
    failures.append("feed is not well formed: %s" % feed.bozo_exception)
if not feed.version.startswith("atom"):
    failures.append("feed is not Atom: %r" % feed.version)
if len(feed.entries) != len(published):
    failures.append("feed has %d entries, expected %d" % (len(feed.entries), len(published)))
for entry in feed.entries:
    for field in ("title", "link", "id", "updated"):
        if field not in entry:
            failures.append("feed entry without %s: %s" % (field, entry.get("title", "?")))

sitemap = etree.parse(os.path.join(out, "sitemap.xml"))
schema = etree.XMLSchema(etree.parse(xsd_path))
sitemap_valid = schema.validate(sitemap)
if not sitemap_valid:
    failures.append("sitemap does not match the schema: %s" % schema.error_log)
urls = [e.text for e in sitemap.getroot().iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
for slug in published:
    if not any("/blog/%s/" % slug in u for u in urls):
        failures.append("published post missing from the sitemap: %s" % slug)

for slug in drafts:
    if os.path.exists(os.path.join(out, "blog", slug)) or any(slug in u for u in urls):
        failures.append("the draft is in the output: %s" % slug)

if not os.path.getsize(os.path.join(out, "404.html")):
    failures.append("404.html is empty")
if not os.path.exists(os.path.join(out, "robots.txt")):
    failures.append("robots.txt is missing")
if not os.path.exists(os.path.join(out, "img", "favicon.png")):
    failures.append("img/favicon.png is missing")
with open(os.path.join(out, "index.html"), encoding="utf-8") as handle:
    if "img/favicon.png" not in handle.read():
        failures.append("the home page does not link the favicon")

print("feed: %s, %d entries | sitemap: %d urls, schema %s | posts: %d, drafts excluded: %d" % (
    feed.version, len(feed.entries), len(urls), "valid" if sitemap_valid else "INVALID", len(published), len(drafts)))
if failures:
    print("FAILED:\n  " + "\n  ".join(failures))
    sys.exit(1)
print("OK")
