#!/usr/bin/env python3
"""ghpush2.py — push the tracked working tree to GitHub via the Git Data API.

Supersedes ghpush.py, which built every commit with `parents: []` and
force-updated main, so the remote history was recreated from scratch on
every push and the local commit messages never arrived.

This version:
  * keeps history: the new commit's parent is the current remote main
  * uses the local HEAD commit message
  * uploads blobs only for files whose content differs from the remote tree
    (compared by git blob SHA-1, computed locally), and records deletions
  * updates the ref without force

System DNS is broken on this machine, so every request goes through
ghlib.http, which pins the host to a dig-resolved address.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ghlib

REPO = "MusiQ-DA/pc98-pocket"


def api(method, path, body=None):
    code, out = ghlib.http(method, f"https://api.github.com{path}", body)
    try:
        return code, json.loads(out)
    except Exception:
        return code, {"raw": out[:400].decode(errors="replace") if out else ""}


def blob_sha(path):
    """git's blob SHA-1, so we can tell locally what already exists remotely."""
    data = open(path, "rb").read()
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest(), data


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True, check=True).stdout.strip()
    os.chdir(root)

    message = subprocess.run(["git", "log", "-1", "--pretty=%B"],
                             capture_output=True, text=True, check=True).stdout.strip()
    local = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                           check=True).stdout.split("\n")
    local = [f for f in local if f]

    code, ref = api("GET", f"/repos/{REPO}/git/ref/heads/main")
    if code != 200 or "object" not in ref:
        sys.exit(f"cannot read remote main: {code} {json.dumps(ref)[:200]}")
    parent = ref["object"]["sha"]
    code, parent_commit = api("GET", f"/repos/{REPO}/git/commits/{parent}")
    base_tree = parent_commit["tree"]["sha"]
    print(f"[remote] main @ {parent[:10]}  tree {base_tree[:10]}")

    code, rtree = api("GET", f"/repos/{REPO}/git/trees/{base_tree}?recursive=1")
    remote = {e["path"]: e["sha"] for e in rtree.get("tree", []) if e["type"] == "blob"}
    if rtree.get("truncated"):
        sys.exit("remote tree truncated; this pusher needs the full listing")
    print(f"[remote] {len(remote)} files; local {len(local)} files")

    entries, uploaded, unchanged = [], 0, 0
    for rel in local:
        sha, data = blob_sha(rel)
        if remote.get(rel) == sha:
            unchanged += 1
            continue
        code, b = api("POST", f"/repos/{REPO}/git/blobs",
                      {"content": base64.b64encode(data).decode(), "encoding": "base64"})
        if "sha" not in b:
            sys.exit(f"blob failed ({rel}): {json.dumps(b)[:200]}")
        entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": b["sha"]})
        uploaded += 1
        print(f"  + {rel}", flush=True)

    for rel in remote:
        if rel not in set(local):
            entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": None})
            print(f"  - {rel}", flush=True)

    print(f"[blobs] {uploaded} uploaded, {unchanged} unchanged")
    if not entries:
        print("[done] nothing to push")
        return

    code, tree = api("POST", f"/repos/{REPO}/git/trees",
                     {"base_tree": base_tree, "tree": entries})
    if "sha" not in tree:
        sys.exit(f"tree failed: {json.dumps(tree)[:300]}")

    code, commit = api("POST", f"/repos/{REPO}/git/commits",
                       {"message": message, "tree": tree["sha"], "parents": [parent]})
    if "sha" not in commit:
        sys.exit(f"commit failed: {json.dumps(commit)[:300]}")

    code, upd = api("PATCH", f"/repos/{REPO}/git/refs/heads/main",
                    {"sha": commit["sha"]})
    if not upd.get("object"):
        sys.exit(f"ref update failed: {json.dumps(upd)[:300]}")
    print(f"[push] main {parent[:10]} -> {commit['sha'][:10]}")
    print(f"[done] https://github.com/{REPO}")


if __name__ == "__main__":
    main()
