#!/usr/bin/env python3
"""check_unconnected.py -- find module inputs left dangling in core_top.

Quartus passes an unconnected input as a warning, so a signal that was never
wired reads as zero and looks exactly like a real measurement. That has now
happened twice in this project: once when a whole commit of RTL never landed,
and once when ten POST-monitor signals reached post_monitor but not
softcpu_subsystem -- three hardware runs reported zeros that were nothing but
missing wires.

Checks that every input port of the modules named below is connected by name in
core_top's instantiation of them.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import re
import sys

CORE_TOP = "pcxt-base/src/fpga/core/core_top.sv"
MODULES = {
    "softcpu_subsystem": "pcxt-base/src/fpga/core/softcpu_subsystem.sv",
    "post_monitor": "pcxt-base/src/fpga/core/post_monitor.sv",
    "sdram_selftest_master": "pcxt-base/src/fpga/core/sdram_selftest_master.sv",
}


def port_list(path, module):
    src = open(path).read()
    m = re.search(r"\bmodule\s+" + module + r"\b(.*?)\);", src, re.S)
    if not m:
        sys.exit(f"{module}: module header not found in {path}")
    body = m.group(1)
    body = re.sub(r"//[^\n]*", "", body)          # strip comments
    names = []
    for line in body.splitlines():
        d = re.match(r"\s*(input|output)\b(.*)", line)
        if not d:
            continue
        rest = re.sub(r"\[[^\]]*\]", " ", d.group(2))   # drop widths
        rest = rest.replace("wire", " ").replace("logic", " ").replace("reg", " ")
        for name in re.findall(r"[A-Za-z_]\w*", rest):
            names.append((name, d.group(1)))
    return names


def connected(core_src, module):
    m = re.search(r"\b" + module + r"\s+\w+\s*\((.*?)\n\s*\);", core_src, re.S)
    if not m:
        sys.exit(f"{module}: not instantiated in core_top")
    return set(re.findall(r"\.(\w+)\s*\(", m.group(1)))


def main():
    core_src = open(CORE_TOP).read()
    bad = 0
    for module, path in MODULES.items():
        wired = connected(core_src, module)
        missing = [n for n, d in port_list(path, module)
                   if d == "input" and n not in wired]
        if missing:
            bad += 1
            print(f"{module}: {len(missing)} input(s) never connected in core_top:")
            for n in missing:
                print(f"    {n}")
        else:
            print(f"{module}: all inputs connected")
    if bad:
        print("\nAn unconnected input reads as zero and is indistinguishable "
              "from a real measurement of zero.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
