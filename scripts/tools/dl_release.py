#!/usr/bin/env python3
"""dl_release.py — download a release asset handling the 302 redirect manually
(each redirect host needs dig-pinned DNS since system DNS is broken)."""
import json, os, subprocess, sys, time
from urllib.parse import urlparse

TOKEN = [l.split(":", 1)[1].strip()
         for l in open(os.path.expanduser("~/.config/gh/hosts.yml"))
         if "oauth_token:" in l][0]

def resolve(host):
    for _ in range(8):
        out = subprocess.run(["dig", "+short", host, "@1.1.1.1"],
                             capture_output=True, text=True).stdout
        ips = [l.strip() for l in out.splitlines()
               if l.strip() and l.strip()[0].isdigit()]
        if ips:
            return ips[-1]
        time.sleep(2)
    sys.exit(f"dns fail: {host}")

def http_get(url, out=None):
    """Returns (code, body_or_None, location_or_None)."""
    u = urlparse(url)
    for attempt in range(4):
        ip = resolve(u.hostname)
        if not ip:
            time.sleep(3); continue
        hdrf = "/tmp/dl_hdr.txt"
        args = ["curl", "-sS", "--max-time", "600",
                "--resolve", f"{u.hostname}:443:{ip}",
                "-H", f"Authorization: Bearer {TOKEN}", "-D", hdrf]
        if out:
            args += ["-o", out]
        args += ["-X", "GET", url]
        p = subprocess.run(args, capture_output=True, text=True)
        code = 0
        loc = None
        try:
            for line in open(hdrf, errors="ignore"):
                if line.startswith("HTTP/"):
                    code = int(line.split()[1])
                if line.lower().startswith("location:"):
                    loc = line.split(":", 1)[1].strip()
        except OSError:
            pass
        if code in (200, 301, 302):
            return code, (p.stdout if not out else None), loc
        print(f"[retry {attempt+1}] code={code}", flush=True)
        time.sleep(3)
    sys.exit(f"download failed: {url}")

def main():
    ip = resolve("api.github.com")
    args = ["curl", "-sS", "--resolve", f"api.github.com:443:{ip}",
            "-H", f"Authorization: Bearer {TOKEN}",
            "https://api.github.com/repos/desaster/openfpga-PCXT/releases"]
    p = subprocess.run(args, capture_output=True, text=True)
    rels = json.loads(p.stdout)
    asset = rels[0]["assets"][0]
    print("asset:", asset["name"], asset["size"], "bytes")

    code, _, loc = http_get("GET", asset["browser_download_url"])
    if code != 302 or not loc:
        sys.exit(f"expected 302, got {code}")
    # redirect target (GitHub release CDN)
    code, _, _ = http_get("GET", loc, out="/tmp/pcxt_release.zip")
    if code != 200:
        sys.exit(f"download failed: {code}")
    sz = os.path.getsize("/tmp/pcxt_release.zip")
    print(f"downloaded: {sz} bytes (expected {asset['size']})")
    assert sz == asset["size"], "size mismatch"
    print("OK")

if __name__ == "__main__":
    main()
