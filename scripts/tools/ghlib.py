#!/usr/bin/env python3
"""ghlib.py — robust GitHub API helper with cached dig-pinned DNS."""
import json, os, subprocess, sys, time
from urllib.parse import urlparse

TOKEN = [l.split(":", 1)[1].strip()
         for l in open(os.path.expanduser("~/.config/gh/hosts.yml"))
         if "oauth_token:" in l][0]

_ipcache = {}

def resolve(host):
    if host in _ipcache:
        return _ipcache[host]
    for _ in range(10):
        out = subprocess.run(["dig", "+short", host, "@1.1.1.1"],
                             capture_output=True, text=True).stdout
        ips = [l.strip() for l in out.splitlines()
               if l.strip() and l.strip()[0].isdigit()]
        if ips:
            _ipcache[host] = ips[-1]
            return ips[-1]
        time.sleep(2)
    sys.exit(f"dns fail: {host}")

def http(method, url, body=None, out=None):
    u = urlparse(url)
    ip = resolve(u.hostname)
    hdrf = "/tmp/ghlib_hdr.txt"
    args = ["curl", "-sS", "-L", "--max-redirs", "5", "--max-time", "120",
            "--resolve", f"{u.hostname}:443:{ip}",
            "-H", f"Authorization: Bearer {TOKEN}",
            "-H", "Accept: application/vnd.github+json",
            "-D", hdrf]
    data = None
    if body is not None:
        data = json.dumps(body).encode() if not isinstance(body, bytes) else body
        args += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    if out:
        args += ["-o", out]
    args += ["-X", method, url]
    p = subprocess.run(args, input=data, capture_output=True)
    code = 0
    hdr = open(hdrf, errors="ignore").read() if os.path.exists(hdrf) else ""
    for line in hdr.splitlines():
        if line.startswith("HTTP/"):
            code = int(line.split()[1])
    body_out = None if out else p.stdout
    return code, body_out

def gh(path):
    for _ in range(5):
        code, body = http("GET", f"https://api.github.com{path}")
        if code == 200:
            return json.loads(body)
        time.sleep(3)
    sys.exit(f"gh get failed: {path} code={code}")

if __name__ == "__main__":
    d = gh(sys.argv[1])
    print(json.dumps(d, ensure_ascii=False, indent=1)[:2000])
