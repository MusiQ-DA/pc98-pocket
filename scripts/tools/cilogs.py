#!/usr/bin/env python3
"""cilogs.py <run_id> — download the latest Actions job log to /tmp/ci.txt"""
import json, os, subprocess, sys, time
from urllib.parse import urlparse

TOKEN = [l.split(":", 1)[1].strip()
         for l in open(os.path.expanduser("~/.config/gh/hosts.yml"))
         if "oauth_token:" in l][0]

def resolve(host):
    for _ in range(6):
        out = subprocess.run(["dig", "+short", host, "@1.1.1.1"],
                             capture_output=True, text=True).stdout
        ips = [l.strip() for l in out.splitlines()
               if l.strip() and l.strip()[0].isdigit()]
        if ips:
            return ips[-1]
        time.sleep(2)
    sys.exit("dns fail")

def http(method, url, out=None):
    u = urlparse(url)
    for _ in range(4):
        ip = resolve(u.hostname)
        if not ip:
            time.sleep(3); continue
        hdrf = "/tmp/hdr.txt"
        args = ["curl", "-sS", "-L", "--max-redirs", "5",
                "--resolve", f"{u.hostname}:443:{ip}",
                "-H", f"Authorization: Bearer {TOKEN}", "-D", hdrf]
        if out:
            args += ["-o", out]
        args += ["-X", method, url]
        p = subprocess.run(args, capture_output=True, text=True)
        code = 0
        for line in open(hdrf, errors="ignore"):
            if line.startswith("HTTP/"):
                code = int(line.split()[1])
        body = None if out else p.stdout
        return code, body
    sys.exit("all attempts failed")

REPO = "/repos/MusiQ-DA/pc98-pocket"
runid = sys.argv[1]

code, body = http("GET", f"{REPO}/actions/runs/{runid}/jobs")
if code != 200:
    sys.exit(f"jobs fetch failed: {code} {body[:150]}")
jid = json.loads(body)["jobs"][0]["id"]
code, _, hdr = http("GET", f"{REPO}/actions/jobs/{jid}/logs", out="/tmp/ci.txt")
if code in (200, 302):
    print("saved /tmp/ci.txt", os.path.getsize("/tmp/ci.txt"), "bytes")
else:
    sys.exit(f"log fetch failed: {code}")
