#!/usr/bin/env python3 -I
"""Bandje translations.

Source of truth for Dutch: the `tr("key", "Dutch text", ...)` calls in Sources/ and the usage
descriptions in Resources/Info.plist. Translations: Resources/Localization/<lang>.lproj/.

  scripts/strings.py extract           writes nl.lproj from the code (run after changing texts)
  scripts/strings.py check             every language has every key, same placeholders (exit 1 if not)
  scripts/strings.py export out.csv    one row per text, one column per language (for review)
  scripts/strings.py import in.csv     writes the .strings files back from a reviewed CSV
  scripts/strings.py import-json xx f  writes language xx from a JSON object {key: text}
"""
import csv
import glob
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(ROOT, "Resources", "Localization")
LANGS = ["nl", "en", "de", "fr", "es", "it", "pt", "pl", "ru", "uk"]
TABLES = ["Localizable", "InfoPlist"]
PLIST_KEYS = ["NSMicrophoneUsageDescription", "NSAudioCaptureUsageDescription"]
TR = re.compile(r'\btr\(\s*"([^"]+)",\s*"((?:[^"\\]|\\.)*)"')
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?@|%%')


def source_texts():
    """{table: {key: (dutch, context)}} from the code and Info.plist."""
    texts = {"Localizable": {}, "InfoPlist": {}}
    for path in sorted(glob.glob(os.path.join(ROOT, "Sources", "Bandje", "*.swift"))):
        name = os.path.basename(path)
        for line_no, line in enumerate(open(path, encoding="utf-8"), 1):
            for key, text in TR.findall(line):
                if "\\(" in text:
                    sys.exit("%s:%d: string interpolation inside tr(); use %%@" % (name, line_no))
                old = texts["Localizable"].get(key)
                if old and old[0] != text:
                    sys.exit("%s:%d: key %s has two different Dutch texts" % (name, line_no, key))
                if not old:
                    texts["Localizable"][key] = (text, name)
    with open(os.path.join(ROOT, "Resources", "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    for key in PLIST_KEYS:
        texts["InfoPlist"][key] = (escape(info[key]), "Info.plist (macOS permission dialog)")
    return texts


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def read_table(lang, table):
    path = os.path.join(LOC, lang + ".lproj", table + ".strings")
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            m = ENTRY.match(line.strip())
            if m:
                out[m.group(1)] = m.group(2)
    return out


def write_table(lang, table, values, texts):
    os.makedirs(os.path.join(LOC, lang + ".lproj"), exist_ok=True)
    path = os.path.join(LOC, lang + ".lproj", table + ".strings")
    with open(path, "w", encoding="utf-8") as f:
        f.write("/* Bandje, %s, %s. Generated order; edit values only. Placeholders %%@ / %%1$@ must stay. */\n\n" % (lang, table))
        for key in sorted(texts[table]):
            if key in values:
                dutch, context = texts[table][key]
                f.write("/* %s | NL: %s */\n\"%s\" = \"%s\";\n\n" % (context, dutch.replace("*/", "* /"), key, values[key]))


def extract():
    texts = source_texts()
    for table in TABLES:
        write_table("nl", table, {k: v[0] for k, v in texts[table].items()}, texts)
        # Keep other languages in sync with the key order and context comments.
        for lang in LANGS[1:]:
            existing = read_table(lang, table)
            if existing:
                write_table(lang, table, existing, texts)
    print("nl: %d texts" % sum(len(t) for t in texts.values()))


def check():
    texts = source_texts()
    problems = []
    for lang in LANGS:
        for table in TABLES:
            values = read_table(lang, table)
            for key, (dutch, _) in texts[table].items():
                if key not in values:
                    problems.append("%s/%s: missing %s" % (lang, table, key))
                elif sorted(PLACEHOLDER.findall(values[key])) != sorted(PLACEHOLDER.findall(dutch)):
                    problems.append("%s/%s: placeholders differ in %s" % (lang, table, key))
                elif re.search(r"https?://|Analytics", values[key]):
                    problems.append("%s/%s: forbidden text (URL) in %s" % (lang, table, key))
            for key in values:
                if key not in texts[table]:
                    problems.append("%s/%s: unused key %s" % (lang, table, key))
    print("\n".join(problems) or "strings: %d languages complete" % len(LANGS))
    sys.exit(1 if problems else 0)


def export(path):
    texts = source_texts()
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["table", "key", "context"] + LANGS)
        for table in TABLES:
            tables = {lang: read_table(lang, table) for lang in LANGS}
            for key in sorted(texts[table]):
                w.writerow([table, key, texts[table][key][1]] +
                           [tables[lang].get(key, "").replace("\\n", "\n").replace('\\"', '"') for lang in LANGS])
    print("wrote " + path)


def import_csv(path):
    texts = source_texts()
    values = {(lang, table): {} for lang in LANGS for table in TABLES}
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            for lang in LANGS:
                if row.get(lang):
                    values[(lang, row["table"])][row["key"]] = escape(row[lang].replace("\r\n", "\n"))
    for (lang, table), v in values.items():
        if lang != "nl" and v:
            merged = read_table(lang, table)  # keep texts the CSV does not have (newer keys)
            merged.update({k: x for k, x in v.items() if k in texts[table]})
            write_table(lang, table, merged, texts)
    print("imported; Dutch changes must be made in the code (tr calls), then run extract")


def import_json(lang, path):
    import json
    texts = source_texts()
    values = json.load(open(path, encoding="utf-8"))
    for table in TABLES:
        merged = read_table(lang, table)  # add to / replace existing texts, keep the rest
        merged.update({k: escape(v) for k, v in values.items() if k in texts[table]})
        write_table(lang, table, merged, texts)
    print("imported %s: %d texts" % (lang, len(values)))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    {"extract": extract, "check": check}.get(cmd, lambda: None)()
    if cmd == "export":
        export(sys.argv[2])
    elif cmd == "import":
        import_csv(sys.argv[2])
    elif cmd == "import-json":
        import_json(sys.argv[2], sys.argv[3])
