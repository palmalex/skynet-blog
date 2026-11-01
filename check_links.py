"""Checks the internal links of a built site (run by `build.sh check`): every link, image and script that points
to the site itself must name a file of the output.

Usage: check_links.py <output dir> <base url>
Zola already fails the build on a broken `@/...` link; this catches the rest (a plain `/blog/typo/` link, a
missing image, a renamed page). It reads the HTML of the output, so it also covers what the theme generates.
Not checked: external links (`./build.sh links`, advisory) and `#fragments`.
"""
import os
import sys
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

out, base = sys.argv[1], sys.argv[2].rstrip("/")
base_parts = urlsplit(base)
ATTRS = {"a": "href", "link": "href", "img": "src", "script": "src", "source": "src"}
SKIPPED = ("#", "mailto:", "tel:", "javascript:", "data:")


class Collector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attr = ATTRS.get(tag)
        if attr:
            value = dict(attrs).get(attr)
            if value:
                self.links.append(value.strip())


def target_of(page_url_path, link):
    """The path inside the output that `link` points to, or None when it is not a link to this site."""
    if link.startswith(SKIPPED):
        return None
    parts = urlsplit(link)
    if parts.scheme or parts.netloc:
        if (parts.scheme, parts.netloc) != (base_parts.scheme, base_parts.netloc):
            return None
        path = parts.path
    elif link.startswith("/"):
        path = parts.path
    else:
        path = os.path.normpath(os.path.join(os.path.dirname(page_url_path), parts.path))
        path = "/" + path.lstrip("/") + ("/" if parts.path.endswith("/") else "")
    if base_parts.path and path.startswith(base_parts.path):
        path = path[len(base_parts.path):] or "/"
    return unquote(path)


def exists(path):
    full = os.path.join(out, path.lstrip("/"))
    if path.endswith("/") or os.path.isdir(full):
        return os.path.isfile(os.path.join(full, "index.html"))
    return os.path.isfile(full)


failures, checked = [], 0
for root, _, names in os.walk(out):
    for name in sorted(names):
        if not name.endswith(".html"):
            continue
        page = os.path.join(root, name)
        page_url = "/" + os.path.relpath(page, out)
        collector = Collector()
        with open(page, encoding="utf-8") as handle:
            collector.feed(handle.read())
        for link in collector.links:
            path = target_of(page_url, link)
            if path is None:
                continue
            checked += 1
            if not exists(path):
                failures.append("%s -> %s" % (page_url, link))

print("internal links: %d checked" % checked)
if checked == 0:
    # A checker that looks at nothing must not pass (wrong directory, wrong base URL).
    failures.append("no internal link found: wrong output directory or base URL?")
if failures:
    print("BROKEN LINKS:\n  " + "\n  ".join(sorted(set(failures))))
    sys.exit(1)
print("OK")
