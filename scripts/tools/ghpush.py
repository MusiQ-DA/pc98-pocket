#!/usr/bin/env python3
"""ghpush.py — push the working tree to GitHub via the Git Data API
(dig-pinned curl; system DNS is broken on this machine).
Reads /tmp/pushlist.json (relative paths), creates blobs + tree + commit,
then force-updates refs/heads/main."""
import base64, json, os, subprocess, sys, time

TOKEN = [l.split(":", 1)[1].strip()
         for l in open(os.path.expanduser("~/.config/gh/hosts.yml"))
         if "oauth_token:" in l][0]
REPO = "MusiQ-DA/pc98-pocket"

def resolve(host):
    for _ in range(8):
        out = subprocess.run(["dig", "+short", host, "@1.1.1.1"],
                             capture_output=True, text=True).stdout
        ips = [l.strip() for l in out.splitlines()
               if l.strip() and l.strip()[0].isdigit()]
        if ips:
            return ips[-1]
        time.sleep(2)
    sys.exit(f"cannot resolve {host}")

IP = resolve("api.github.com")

def api(method, path, body=None):
    for attempt in range(5):
        args = ["curl", "-sS", "--resolve", f"api.github.com:443:{IP}", "-X", method,
                "-H", f"Authorization: Bearer {TOKEN}",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2022-11-28"]
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            args += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
        args.append(f"https://api.github.com{path}")
        p = subprocess.run(args, input=data, capture_output=True)
        try:
            j = json.loads(p.stdout)
        except Exception:
            print(f"  [retry {attempt+1}] bad response: {p.stdout[:80]}", flush=True)
            time.sleep(3 * (attempt + 1)); continue
        if isinstance(j, dict) and j.get("message") and "rate limit" in j["message"]:
            print("  rate limited, waiting...", flush=True); time.sleep(30); continue
        return j
    sys.exit("api failed")

def main():
    root = os.getcwd()
    files = json.load(open("/tmp/pushlist.json"))
    entries = []
    for i, rel in enumerate(files):
        data = open(os.path.join(root, rel), "rb").read()
        b = api("POST", f"/repos/{REPO}/git/blobs",
                {"content": base64.b64encode(data).decode(), "encoding": "base64"})
        if "sha" not in b:
            sys.exit(f"blob failed ({rel}): {json.dumps(b)[:200]}")
        entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": b["sha"]})
        if (i + 1) % 50 == 0:
            print(f"  blobs {i+1}/{len(files)}", flush=True)
    print(f"[blobs] {len(entries)} uploaded")

    tree = api("POST", f"/repos/{REPO}/git/trees", {"tree": entries})
    if "sha" not in tree:
        sys.exit(f"tree failed: {json.dumps(tree)[:300]}")
    commit = api("POST", f"/repos/{REPO}/git/commits",
                 {"message": "pivot: PCXT-based chassis; PC-98 machine layer (WIP); CI build",
                  "tree": tree["sha"], "parents": []})
    if "sha" not in commit:
        sys.exit(f"commit failed: {json.dumps(commit)[:300]}")
    upd = api("PATCH", f"/repos/{REPO}/git/refs/heads/main",
              {"sha": commit["sha"], "force": True})
    if not upd.get("object"):
        sys.exit(f"ref update failed: {json.dumps(upd)[:300]}")
    print(f"[push] main -> {commit['sha'][:10]}")
    print(f"[done] https://github.com/{REPO}")

if __name__ == "__main__":
    main()
