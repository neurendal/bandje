"""Download the Voz and Who model files for Bandje, outside the app.

Called by scripts/fetch-models.sh. Python standard library only.

Layout written (the SDK adopts a directory it did not download into, as long as
it has no `.dal-meta` folder, so none is ever created here):

  <root>/voz/{encoder,mel,decoder}.mlmodelc/..., meta.json, vocab.json, embedding.f16
  <root>/who/coreml-fp16/{encoder_6000,queries_6000,encoder_30000,queries_30000,voice_3256}.mlmodelc/...
  <root>/who/coreml-fp16/who_meta.json, who_mel_banks.f32, who_voice_banks.f32, who_embed.f16

Pinned and checked by `models.lock.json` in the repo root: the exact Hugging Face commit of each
model and the size and SHA-256 of every file. Files are downloaded from that commit and must match
the lock, so a moved tag or a changed file on Hugging Face is refused. Files that already match
are skipped, so the script is idempotent.

  fetch_models.py <root>                 download/verify against models.lock.json
  fetch_models.py <root> --update-lock   after raising desert-ant-core: resolve the revisions below
                                         to commits, verify against Hugging Face, write the lock
"""
import hashlib
import json
import os
import sys
import urllib.request

HUB = "https://huggingface.co"

LOCK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "models.lock.json")

# The revisions desert-ant-core 4.2.3 declares (VozModel.revision, WhoModel.revision in its
# Catalog.swift). Only used by --update-lock; a normal fetch uses the commits in models.lock.json.
MODELS = {
    "voz": {
        "repo": "desert-ant-labs/voz",
        "revision": "v0.5.0",
        "files": ["encoder.mlmodelc/", "mel.mlmodelc/", "decoder.mlmodelc/",
                  "meta.json", "vocab.json", "embedding.f16"],
    },
    "who": {
        "repo": "desert-ant-labs/who",
        "revision": "v0.3.4",
        "files": [f"coreml-fp16/{g}.mlmodelc/" for g in
                  ["encoder_6000", "queries_6000", "encoder_30000", "queries_30000", "voice_3256"]]
                 + [f"coreml-fp16/{s}" for s in
                    ["who_meta.json", "who_mel_banks.f32", "who_voice_banks.f32", "who_embed.f16"]],
    },
}


def tree(repo, revision):
    url = f"{HUB}/api/models/{repo}/tree/{revision}?recursive=true"
    with urllib.request.urlopen(url, timeout=60) as r:
        return [e for e in json.load(r) if e.get("type") == "file"]


def select(entries, wanted):
    out = []
    for w in wanted:
        if w.endswith("/"):
            hits = [e for e in entries if e["path"].startswith(w)]
        else:
            hits = [e for e in entries if e["path"] == w]
        if not hits:
            sys.exit(f"FOUT: {w} staat niet in de repo")
        out.extend(h for h in hits if h not in out)
    return out


def matches(path, entry):
    if not os.path.isfile(path) or os.path.getsize(path) != entry["size"]:
        return False
    lfs = entry.get("lfs")
    if lfs:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest() == lfs["oid"]
    # Small file: git blob SHA-1.
    h = hashlib.sha1()
    h.update(b"blob %d\0" % entry["size"])
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest() == entry["oid"]


def download(repo, revision, entry, dest, tmpdir):
    url = f"{HUB}/{repo}/resolve/{revision}/{entry['path']}"
    part = os.path.join(tmpdir, entry["path"].replace("/", "__") + ".part")
    with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    if not matches(part, entry):
        os.remove(part)
        sys.exit(f"FOUT: controle mislukt voor {entry['path']} (grootte of checksum)")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    os.replace(part, dest)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def commit_of(repo, revision):
    with urllib.request.urlopen(f"{HUB}/api/models/{repo}/revision/{revision}", timeout=60) as r:
        return json.load(r)["sha"]


def update_lock(root):
    """Resolve each revision to its commit, fetch and verify against Hugging Face, write the lock."""
    tmpdir = os.path.join(root, ".download-tmp")
    os.makedirs(tmpdir, exist_ok=True)
    lock = {}
    for name, m in MODELS.items():
        commit = commit_of(m["repo"], m["revision"])
        entries = select(tree(m["repo"], commit), m["files"])
        print(f"{name}: {m['repo']}@{m['revision']} = {commit}, {len(entries)} bestanden")
        files = {}
        for e in entries:
            dest = os.path.join(root, name, e["path"])
            if not matches(dest, e):
                print(f"  ophalen: {e['path']} ({e['size'] / 1e6:.1f} MB)")
                download(m["repo"], commit, e, dest, tmpdir)
            files[e["path"]] = {"size": e["size"], "sha256": sha256(dest)}
        lock[name] = {"repo": m["repo"], "revision": m["revision"], "commit": commit, "files": files}
    os.rmdir(tmpdir)
    with open(LOCK, "w") as f:
        json.dump(lock, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Geschreven: {LOCK}")


def fetch(root):
    with open(LOCK) as f:
        lock = json.load(f)
    tmpdir = os.path.join(root, ".download-tmp")
    os.makedirs(tmpdir, exist_ok=True)
    total_new = 0
    for name, m in lock.items():
        target = os.path.join(root, name)
        size = sum(v["size"] for v in m["files"].values())
        print(f"{name}: {m['repo']}@{m['commit'][:12]} ({m['revision']}), {len(m['files'])} bestanden, {size / 1e6:.0f} MB")
        for path, want in sorted(m["files"].items()):
            dest = os.path.join(target, path)
            if os.path.isfile(dest) and os.path.getsize(dest) == want["size"] and sha256(dest) == want["sha256"]:
                continue
            print(f"  ophalen: {path} ({want['size'] / 1e6:.1f} MB)")
            part = os.path.join(tmpdir, path.replace("/", "__") + ".part")
            url = f"{HUB}/{m['repo']}/resolve/{m['commit']}/{path}"
            with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as f:
                for chunk in iter(lambda: r.read(1 << 20), b""):
                    f.write(chunk)
            if os.path.getsize(part) != want["size"] or sha256(part) != want["sha256"]:
                os.remove(part)
                sys.exit(f"FOUT: {path} klopt niet met models.lock.json (grootte of SHA-256)")
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            os.replace(part, dest)
            total_new += 1
        if os.path.isdir(os.path.join(target, ".dal-meta")):
            sys.exit(f"FOUT: {target}/.dal-meta bestaat; verwijder die map (dan laadt de SDK offline)")
        print(f"  {name} compleet en gecontroleerd")
    os.rmdir(tmpdir)
    print(f"Klaar. {total_new} bestanden opgehaald, de rest was er al.")


def main():
    root = sys.argv[1]
    if "--update-lock" in sys.argv[2:]:
        update_lock(root)
    else:
        fetch(root)


if __name__ == "__main__":
    main()
