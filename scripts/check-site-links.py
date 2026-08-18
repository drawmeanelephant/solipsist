#!/usr/bin/env python3
"""Check the built Solipsist site for broken internal links and sitemap gaps.

Validates the static `dist/` tree produced by Boris:

- every internal `href`/`src` resolves to an existing file (or, for
  fragments, an existing `id` in the target page),
- every `sitemap.xml` entry maps to a published file.

External URLs are reported for awareness but never fail the build.

Usage:
    python3 scripts/check-site-links.py [--root site/dist] [--base-url https://solipsist.filed.fyi]
"""

import argparse
import html.parser
import os
import sys
import urllib.parse
import xml.etree.ElementTree as ET


class LinkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []      # (attr, value)
        self.ids = set()    # id="..." attributes for anchor checks

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if value is None:
                continue
            if key in ("href", "src"):
                self.refs.append((key, value))
            elif key == "id":
                self.ids.add(value)


def walk(root):
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            yield os.path.join(dirpath, name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="site/dist", help="built site root")
    parser.add_argument("--base-url", default="https://solipsist.filed.fyi")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        sys.exit(f"error: build root not found: {root}")

    html_files = sorted(
        p for p in walk(root)
        if p.endswith(".html") and ".boris-cache" not in p
    )

    # Map relative url -> absolute file path for every published file, and
    # collect heading ids for every HTML page.
    url_to_file = {}
    ids_by_file = {}
    for path in sorted(p for p in walk(root) if ".boris-cache" not in p):
        rel = os.path.relpath(path, root)
        url_to_file[rel.replace(os.sep, "/")] = path
    for path in html_files:
        ids_by_file[path] = set()
        try:
            with open(path, encoding="utf-8") as fh:
                data = fh.read()
        except OSError as exc:
            sys.exit(f"error: cannot read {path}: {exc}")
        p = LinkParser()
        p.feed(data)
        ids_by_file[path].update(p.ids)

    base = urllib.parse.urlparse(args.base_url)
    errors = []
    external = 0
    total_refs = 0

    for path in html_files:
        page_url = os.path.relpath(path, root).replace(os.sep, "/")
        page_dir = os.path.dirname(page_url)
        with open(path, encoding="utf-8") as fh:
            data = fh.read()
        p = LinkParser()
        p.feed(data)
        for attr, raw in p.refs:
            total_refs += 1
            value = raw.strip()
            parsed = urllib.parse.urlparse(value)
            if parsed.scheme or value.startswith("//"):
                external += 1
                continue  # external link: awareness only
            if value.startswith("#"):
                # Same-page anchor.
                if value[1:] and value[1:] not in p.ids:
                    errors.append(f"{page_url}: missing anchor {value!r}")
                continue
            # Split off any fragment.
            target_url, _, fragment = value.partition("#")
            target_url = urllib.parse.unquote(target_url)
            resolved = urllib.parse.urljoin(page_dir + "/", target_url)
            resolved = urllib.parse.unquote(resolved)
            if resolved.startswith("/"):
                resolved = resolved.lstrip("/")
            target_file = url_to_file.get(resolved)
            if target_file is None:
                errors.append(f"{page_url}: broken link {value!r} (no file at {resolved!r})")
                continue
            if fragment and target_file.endswith(".html") and fragment not in ids_by_file[target_file]:
                errors.append(f"{page_url}: missing anchor {value!r} in {resolved}")

    # Sitemap entries.
    sitemap_path = os.path.join(root, "sitemap.xml")
    sitemap_ok = True
    if os.path.exists(sitemap_path):
        try:
            tree = ET.parse(sitemap_path)
        except ET.ParseError as exc:
            errors.append(f"sitemap.xml: parse error: {exc}")
            sitemap_ok = False
        else:
            for loc in tree.iter():
                if "loc" not in loc.tag:
                    continue
                url = loc.text.strip()
                path_part = urllib.parse.urlparse(url).path.lstrip("/")
                if path_part not in url_to_file:
                    errors.append(f"sitemap.xml: entry {url!r} has no published file")
                    sitemap_ok = False
    else:
        errors.append("sitemap.xml not found in build root")
        sitemap_ok = False

    print(f"checked {len(html_files)} pages, {total_refs} references "
          f"({external} off-site, not validated), sitemap ok={sitemap_ok}")
    for err in errors:
        print(f"  FAIL {err}")

    if errors:
        sys.exit(1)
    print("ok: all internal links and sitemap entries resolve")


if __name__ == "__main__":
    main()
