#!/usr/bin/env python3
"""Verify Voz/Who model files against models.lock.json, and copy them into the app bundle.

No network, stdlib only. Never downloads anything.

  verify-and-copy-models.py copy   <source models dir> <dest Models dir>
      Verify <source>/{voz,who} against the lock, then copy into <dest> (skip files whose size
      and sha256 already match). Remove files in <dest> that are not in the lock.
  verify-and-copy-models.py verify <models dir>
      Verify only (used on the built .app). Exit 1 on any mismatch, missing or extra file.
"""
import hashlib
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, "models.lock.json")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def expected():
    with open(LOCK) as f:
        lock = json.load(f)
    out = {}
    for model, entry in lock.items():
        for rel, meta in entry["files"].items():
            out[os.path.join(model, rel)] = (meta["size"], meta["sha256"])
    return out


def matches(path, size, digest):
    return os.path.isfile(path) and os.path.getsize(path) == size and sha256(path) == digest


def listed(directory):
    found = set()
    for base, dirs, files in os.walk(directory):
        for name in files:
            if name == ".DS_Store":
                continue
            found.add(os.path.relpath(os.path.join(base, name), directory))
    return found


def verify(directory, files):
    errors = []
    if os.path.isdir(os.path.join(directory, "voz", ".dal-meta")) or \
       os.path.isdir(os.path.join(directory, "who", ".dal-meta")):
        errors.append(".dal-meta folder present (the SDK would try to download)")
    for rel, (size, digest) in sorted(files.items()):
        if not matches(os.path.join(directory, rel), size, digest):
            errors.append(f"missing or wrong: {rel}")
    extra = listed(directory) - set(files)
    for rel in sorted(extra):
        errors.append(f"not in lock: {rel}")
    return errors


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("copy", "verify"):
        print(__doc__)
        return 2
    files = expected()
    total = sum(size for size, _ in files.values())
    if sys.argv[1] == "verify":
        errors = verify(sys.argv[2], files)
        for e in errors:
            print(f"error: {e}")
        if errors:
            return 1
        print(f"models OK: {len(files)} files, {total / 1e6:.0f} MB match models.lock.json")
        return 0

    src, dest = sys.argv[2], sys.argv[3]
    errors = [e for e in verify(src, files) if not e.startswith("not in lock")]
    if errors:
        for e in errors:
            print(f"error: {src}: {e}")
        print("error: models in the source folder do not match models.lock.json; the app "
              "would ship without working transcription. Fix the source folder, never download "
              "from the build.")
        return 1
    copied = 0
    for rel, (size, digest) in sorted(files.items()):
        target = os.path.join(dest, rel)
        if matches(target, size, digest):
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(os.path.join(src, rel), target)
        copied += 1
    for rel in listed(dest) - set(files):
        os.remove(os.path.join(dest, rel))
    print(f"models: {len(files)} files verified, {copied} copied into {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
