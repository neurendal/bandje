#!/usr/bin/env python3 -I
"""Bandje Help (Apple Help Book) from Resources/Help/<lang>.md.

Source format, one file per language:

    # Book title
    Intro paragraph(s) for the start page.

    ## Page title {#anchor}
    One-line summary (shown on the start page and in search results).

    Body: paragraphs, `- ` bullets, `1. ` lists, `### ` subheadings, **bold**, `code`.

Every language must have the same anchors as en.md, in the same order. A language without a file
gets the English book (CFBundleDevelopmentRegion en).

  scripts/make-help.py check            validate the sources (exit 1 on problems)
  scripts/make-help.py build <app>      write <app>/Contents/Resources/Bandje.help, index it, clear helpd's cache
  scripts/make-help.py clear            quit Tips / Help Viewer and clear helpd's cached copy of the book
  scripts/make-help.py web <outdir>     the same pages as a static site for band.je/support/help:
                                        <outdir>/<lang>/index.html and <anchor>.html, <outdir>/logo.png
"""
import html
import os
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Resources", "Help")
LANGS = ["nl", "en", "de", "fr", "es", "it", "pt", "pl", "ru", "uk"]
BOOK_ID = "com.neurendal.bandje.help"
HEAD = re.compile(r"^## (.+?) \{#([a-z0-9-]+)\}\s*$")


def parse(lang):
    path = os.path.join(SRC, lang + ".md")
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or not lines[0].startswith("# "):
        sys.exit("%s: first line must be '# Book title'" % path)
    book = {"title": lines[0][2:].strip(), "intro": [], "pages": []}
    page = None
    for line in lines[1:]:
        m = HEAD.match(line)
        if m:
            page = {"title": m.group(1), "anchor": m.group(2), "lines": []}
            book["pages"].append(page)
        elif line.startswith("## "):
            sys.exit("%s: heading without {#anchor}: %s" % (path, line))
        elif page is None:
            book["intro"].append(line)
        else:
            page["lines"].append(line)
    for p in book["pages"]:
        body = [l for l in p["lines"]]
        while body and not body[0].strip():
            body.pop(0)
        p["summary"] = body[0].strip() if body else ""
        p["body"] = body[1:]
    return book


def inline(text):
    s = html.escape(text, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\[([^\]]+)\]\(#([a-z0-9-]+)\)", r'<a href="\2.html">\1</a>', s)
    # Shortcuts as key caps, like on band.je: ⌃⌥⌘R, ⌘V, ⌘D.
    s = re.sub(r"(?<![\w>])([⌃⌥⇧⌘]+[A-Z0-9])(?!\w)", r"<kbd>\1</kbd>", s)
    return s


def blocks(lines):
    out, para, kind = [], [], None

    def close():
        nonlocal para, kind
        if para:
            out.append("<p>" + " ".join(para) + "</p>")
            para = []
        if kind:
            out.append("</%s>" % kind)
            kind = None

    for raw in lines:
        line = raw.strip()
        if not line:
            close()
            continue
        if line.startswith("### "):
            close()
            out.append("<h3>%s</h3>" % inline(line[4:]))
            continue
        m = re.match(r"^(- |\d+\. )(.*)$", line)
        if m:
            want = "ul" if m.group(1) == "- " else "ol"
            if para:
                out.append("<p>" + " ".join(para) + "</p>")
                para = []
            if kind != want:
                if kind:
                    out.append("</%s>" % kind)
                out.append("<%s>" % want)
                kind = want
            out.append("<li>%s</li>" % inline(m.group(2)))
            continue
        if kind:
            out.append("</%s>" % kind)
            kind = None
        para.append(inline(line))
    close()
    return "\n".join(out)


CSS = """
:root{--bg:#FFFFFF;--bg2:#F5F5F7;--ink:#1D1D1F;--muted:#6E6E73;--line:#E3E3E8;--accent:#C2452A;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--bg:#1C1C1E;--bg2:#232325;--ink:#F5F5F7;--muted:#98989D;--line:#38383A;--accent:#FF8A5C;color-scheme:dark}}
::selection{background:#E2553A;color:#fff}
html,body{margin:0;padding:0}
body{background:var(--bg);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,sans-serif;
  -webkit-font-smoothing:antialiased;padding:24px 32px 48px;max-width:680px;overflow-wrap:break-word}
h1,h2,h3{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","Helvetica Neue",sans-serif;margin:0}
h1{font-size:30px;font-weight:700;line-height:1.1;letter-spacing:-.025em}
h2{font-size:26px;font-weight:700;line-height:1.15;letter-spacing:-.025em;margin:0 0 8px}
h3{font-size:17px;font-weight:600;line-height:1.25;margin:28px 0 6px}
p{margin:0 0 12px;text-wrap:pretty}
ul,ol{margin:0 0 12px;padding-left:22px}li{margin:4px 0}
strong{font-weight:600}
.lead{color:var(--muted);font-size:17px;margin:0 0 24px}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline;text-underline-offset:3px}
code{font:13px ui-monospace,"SF Mono",Menlo,monospace;background:var(--bg2);border:1px solid var(--line);border-radius:5px;padding:1px 5px}
kbd{font:500 13px/1 ui-monospace,"SF Mono",Menlo,monospace;padding:3px 6px;border:1px solid var(--line);border-radius:5px;
  background:var(--bg2);box-shadow:0 1px 0 var(--line);white-space:nowrap}
ul.toc{list-style:none;padding:0;margin:24px 0 0}
ul.toc li{padding:14px 0;margin:0;border-top:1px solid var(--line)}
ul.toc a{font-weight:600;font-size:16px;color:var(--ink)}ul.toc a:hover{color:var(--accent);text-decoration:none}
ul.toc span{display:block;color:var(--muted);margin-top:2px}
nav{font-size:14px;margin-bottom:20px}nav a{color:var(--muted)}
.langs{font-size:13px;color:var(--muted);margin:0 0 16px}.langs a{color:var(--muted)}
.head{display:flex;gap:14px;align-items:center;margin-bottom:12px}.head img{width:48px;height:48px}
"""


LANGUAGE_NAMES = {"en": "English", "nl": "Nederlands", "de": "Deutsch", "fr": "Français", "es": "Español",
                  "it": "Italiano", "pt": "Português", "pl": "Polski", "ru": "Русский", "uk": "Українська"}


def web(outdir):
    """The help book as a static site (no scripts): one folder per language, the same pages as in
    the app, a language switcher, and a hook for the site's own stylesheet (/help.css)."""
    check()
    os.makedirs(outdir, exist_ok=True)
    shutil.copyfile(os.path.join(ROOT, "Resources", "Logo.png"), os.path.join(outdir, "logo.png"))
    langs = [l for l in LANGS if os.path.exists(os.path.join(SRC, l + ".md"))]
    for lang in langs:
        book = parse(lang)
        d = os.path.join(outdir, lang)
        os.makedirs(d, exist_ok=True)

        def switcher(page):
            items = []
            for other in langs:
                name = html.escape(LANGUAGE_NAMES.get(other, other))
                items.append("<strong>%s</strong>" % name if other == lang
                             else '<a href="../%s/%s" hreflang="%s" lang="%s">%s</a>' % (other, page, other, other, name))
            return '<p class="langs">%s</p>\n' % " · ".join(items)

        def write(page, title, body, description, is_index=False):
            doc = page_html(lang, title, switcher(page) + body, description, book["title"], None, is_index=is_index)
            doc = doc.replace("</style>\n", "</style>\n<link rel=\"stylesheet\" href=\"/help.css\">\n", 1)
            open(os.path.join(d, page), "w", encoding="utf-8").write(doc)

        toc = "\n".join('<li><a href="%s.html">%s</a><span>%s</span></li>' % (p["anchor"], html.escape(p["title"]), inline(p["summary"]))
                        for p in book["pages"])
        intro = blocks(book["intro"])
        write("index.html", book["title"], '<div class="head"><img src="../logo.png" alt=""><h1>%s</h1></div>\n%s\n<ul class="toc">\n%s\n</ul>'
              % (html.escape(book["title"]), intro, toc), re.sub(r"<[^>]+>", "", intro)[:200], is_index=True)
        for p in book["pages"]:
            write(p["anchor"] + ".html", p["title"], '<h2>%s</h2>\n<p class="lead">%s</p>\n%s'
                  % (html.escape(p["title"]), inline(p["summary"]), blocks(p["body"])), p["summary"])
    print("help: web pages for %d languages in %s" % (len(langs), outdir))


def page_html(lang, title, body, description, home_label, logo, is_index=False, anchor=None):
    meta = '<meta name="AppleTitle" content="%s">\n' % html.escape(title) if is_index else ""
    anchor_tag = '<a name="%s"></a>\n' % anchor if anchor else ""
    nav = "" if is_index else '<nav><a href="index.html">%s</a></nav>\n' % html.escape(home_label)
    return """<!doctype html>
<html lang="%s">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
%s<meta name="description" content="%s">
<meta name="robots" content="anchors">
<title>%s</title>
<style>%s</style>
</head>
<body>
%s%s%s
</body>
</html>
""" % (lang, meta, html.escape(description), html.escape(title), CSS, anchor_tag, nav, body)


def check():
    problems = []
    en = parse("en")
    anchors = [p["anchor"] for p in en["pages"]]
    for lang in LANGS:
        path = os.path.join(SRC, lang + ".md")
        if not os.path.exists(path):
            print("help: %s missing, falls back to English" % lang)
            continue
        book = parse(lang)
        got = [p["anchor"] for p in book["pages"]]
        if got != anchors:
            problems.append("%s: anchors %s differ from en %s" % (lang, got, anchors))
        text = open(path, encoding="utf-8").read()
        if re.search(r"https?://", text):
            problems.append("%s: contains a URL (the app has no URLs in its help)" % lang)
        for p in book["pages"]:
            if not p["summary"]:
                problems.append("%s/%s: no summary line" % (lang, p["anchor"]))
    for p in problems:
        print("help: " + p)
    if problems:
        sys.exit(1)
    print("help: %d pages, sources ok" % len(anchors))


def build(app):
    check()
    book_dir = os.path.join(app, "Contents", "Resources", "Bandje.help")
    shutil.rmtree(book_dir, ignore_errors=True)
    res = os.path.join(book_dir, "Contents", "Resources")
    os.makedirs(res)
    logo = os.path.join(ROOT, "Resources", "Logo.png")
    shutil.copyfile(logo, os.path.join(res, "logo.png"))
    for lang in LANGS:
        if not os.path.exists(os.path.join(SRC, lang + ".md")):
            continue
        book = parse(lang)
        d = os.path.join(res, lang + ".lproj")
        os.makedirs(d)
        home = book["title"]
        toc = "\n".join('<li><a href="%s.html">%s</a><span>%s</span></li>' % (p["anchor"], html.escape(p["title"]), inline(p["summary"]))
                        for p in book["pages"])
        intro = blocks(book["intro"])
        body = ('<div class="head"><img src="../logo.png" alt=""><h1>%s</h1></div>\n%s\n<ul class="toc">\n%s\n</ul>'
                % (html.escape(book["title"]), intro, toc))
        summary = re.sub(r"<[^>]+>", "", intro)[:200]
        open(os.path.join(d, "index.html"), "w", encoding="utf-8").write(
            page_html(lang, book["title"], body, summary, home, logo, is_index=True))
        for p in book["pages"]:
            body = '<h2>%s</h2>\n<p class="lead">%s</p>\n%s' % (html.escape(p["title"]), inline(p["summary"]), blocks(p["body"]))
            open(os.path.join(d, p["anchor"] + ".html"), "w", encoding="utf-8").write(
                page_html(lang, p["title"], body, p["summary"], home, logo, anchor=p["anchor"]))
        for kind, name in (("lsm", "Bandje.helpindex"), ("corespotlight", "Bandje.cshelpindex")):
            subprocess.run(["hiutil", "-I", kind, "-Caf", os.path.join(d, name), "-l", lang, d],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleIdentifier": BOOK_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Band·je Help",
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": "1",
        "CFBundleSignature": "hbwr",
        "CFBundleVersion": "1",
        "HPDBookAccessPath": "index.html",
        "HPDBookIndexPath": "Bandje.helpindex",
        "HPDBookCSIndexPath": "Bandje.cshelpindex",
        "HPDBookTitle": "Band·je Help",
        "HPDBookType": "3",
    }
    # Without the DOCTYPE line: it holds a URL, and the bundle has none.
    data = plistlib.dumps(info).decode().splitlines(keepends=True)
    with open(os.path.join(book_dir, "Contents", "Info.plist"), "w") as f:
        f.writelines(l for l in data if not l.startswith("<!DOCTYPE"))
    print("help: built %s" % book_dir)
    clear_cache()


def clear_cache():
    """helpd keeps a copy of the book per app version (`<id>*<CFBundleShortVersionString>`) and
    never refreshes it while that version stays the same, so a rebuilt book with new pages (and
    anchors) would not show. Remove our cached copy; helpd makes a new one on the next open.
    Releases bump the version, so users never hit this."""
    home = os.path.expanduser("~")
    caches = [os.path.join(home, "Library", "Group Containers", "group.com.apple.helpviewer.content", "Library", "Caches"),
              os.path.join(home, "Library", "Caches", "com.apple.helpd", "Generated")]
    removed = 0
    for d in caches:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for name in names:
            # Also books under an earlier ID (nl.celenation.bandje.help until M10).
            if BOOK_ID + "*" in name or "nl.celenation.bandje.help*" in name:
                shutil.rmtree(os.path.join(d, name), ignore_errors=True)
                removed += 1
    if removed:
        # helpd also remembers the book in memory; it restarts on demand.
        subprocess.run(["killall", "helpd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("help: cleared %d cached copies" % removed)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        check()
    elif len(sys.argv) == 2 and sys.argv[1] == "clear":
        # Also quit the app that shows help (Tips on macOS 26, Help Viewer before), which keeps pages in memory.
        for app in ("Tips", "Help Viewer"):
            subprocess.run(["osascript", "-e", 'if application "%s" is running then tell application "%s" to quit' % (app, app)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        clear_cache()
        print("help: cache cleared; open Help from the Bandje menu to load the current book")
    elif len(sys.argv) == 3 and sys.argv[1] == "web":
        web(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "build":
        build(sys.argv[2])
    else:
        sys.exit(__doc__)
