#!/usr/bin/env python3
"""getartifact.py — download a workflow run's artifact and unpack it.

Supersedes getart2.py, which had a single artifact id baked into the source and
had to be edited for every build.

    python3 scripts/tools/getartifact.py [run_number] [dest_dir]

With no run_number the newest successful run is used. Everything goes through
ghlib.http, which pins hosts to dig-resolved addresses because the machine's
system DNS is broken.
"""
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ghlib

REPO = "MusiQ-DA/pc98-pocket"


def pick_run(run_number):
    runs = ghlib.gh(f"/repos/{REPO}/actions/runs?per_page=30")["workflow_runs"]
    if run_number is None:
        for r in runs:
            if r["conclusion"] == "success":
                return r
        sys.exit("no successful run found")
    for r in runs:
        if r["run_number"] == run_number:
            return r
    sys.exit(f"run #{run_number} not in the last 30 runs")


def main():
    run_number = int(sys.argv[1]) if len(sys.argv) > 1 else None
    dest = sys.argv[2] if len(sys.argv) > 2 else "build/artifact"

    run = pick_run(run_number)
    print(f"run#{run['run_number']} {run['status']}/{run['conclusion']} "
          f"sha={run['head_sha'][:10]}")
    if run["conclusion"] != "success":
        sys.exit("that run did not succeed; refusing to unpack its artifact")

    arts = ghlib.gh(f"/repos/{REPO}/actions/runs/{run['id']}/artifacts")["artifacts"]
    if not arts:
        sys.exit("run has no artifacts (they expire after 90 days)")

    os.makedirs(dest, exist_ok=True)
    for a in arts:
        zpath = os.path.join(dest, a["name"] + ".zip")
        code, _ = ghlib.http("GET", a["archive_download_url"], out=zpath)
        if code != 200:
            sys.exit(f"download failed for {a['name']}: HTTP {code}")
        with zipfile.ZipFile(zpath) as z:
            z.extractall(dest)
            names = z.namelist()
        os.remove(zpath)
        print(f"  {a['name']}: {', '.join(names)}")
    print(f"[done] {dest}")


if __name__ == "__main__":
    main()
