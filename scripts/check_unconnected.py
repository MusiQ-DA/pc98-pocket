#!/usr/bin/env python3
"""check_unconnected.py -- find wires that go nowhere.

Two checks, from two bugs of the same family:

  1. module inputs left dangling in core_top (below);
  2. a net that touches EXACTLY ONE instance port and nothing else -- an
     output nobody reads, or an input nobody drives.

(2) came out of the FDC: pc98_fdc_glue's fd_wdata -- the SYNTHESISED DOR it
hands floppy.v on a 0x94 write -- landed on a wire named fdc_glue_wdata that
no other line in Peripherals.sv mentioned, because floppy.v's io_writedata
was still hardwired to the raw guest byte. The glue computed the right value
and it went in the bin; floppy.v latched a DOR with bit 2 clear and sat in
reset, so the MSR never raised RQM and the BIOS polled 0x90 forever. Nothing
warns: the wire has a driver, and Verilator's lint sees a legal design.

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

CORE_TOP = "fpga/core/core_top.sv"
MODULES = {
    "softcpu_subsystem": "fpga/core/softcpu_subsystem.sv",
    "post_monitor": "fpga/core/post_monitor.sv",
    "sdram_selftest_master": "fpga/core/sdram_selftest_master.sv",
    # The CPU-side swap of 2026-09: the bridge carries every pin the V30
    # sees, so a dangling input there reads as a dead machine, not a zero.
    "v30_cpu_bridge": "fpga/core/v30_cpu_bridge.sv",
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


# (2) The dangling-net scan. A net mentioned in exactly one .port(net)
# connection and nowhere else in the file is connected to one side only.
SCAN = [
    "fpga/core/chipset/HDL/Peripherals.sv",
    "fpga/core/chipset/HDL/Chipset.sv",
    "fpga/core/core_top.sv",
]
# Nets that are one-sided ON PURPOSE (a port left open for a reason, a debug
# tap kept for the next build). Name them here with the reason.
DANGLE_OK = {
    # Baselined 2026-09-16, when the check was written. Every one of these is
    # a submodule OUTPUT nobody reads yet -- GDC state the display path does
    # not need, OPNA's ADPCM pins with no RAM behind them, the UART's modem
    # lines, the V30's save-state returns, the old FDC stub's FIFO select,
    # and the master 8259's cascade bus. They are recorded rather than fixed
    # so that a NEW one-sided net -- the shape the DOR bug had -- fails.
    "fdc_fifo_select", "interrupt_cascade_io",
    "gdc_m_cur_addr", "gdc_m_cur_bl", "gdc_m_cur_bot", "gdc_m_cur_dot",
    "gdc_m_cur_en", "gdc_m_cur_rate", "gdc_m_cur_top", "gdc_m_len",
    "gdc_m_zoom",
    "gdc_s_cur_addr", "gdc_s_cur_bl", "gdc_s_cur_bot", "gdc_s_cur_dot",
    "gdc_s_cur_en", "gdc_s_cur_rate", "gdc_s_cur_top", "gdc_s_disp_on",
    "gdc_s_len", "gdc_s_pitch", "gdc_s_sad", "gdc_s_unk_cmd",
    "gdc_s_unk_count", "gdc_s_zoom",
    "opna_adpcmb_addr", "opna_adpcmb_roe_n",
    "pc98_fill_busy", "pc98_kanji_seen",
    "uart_dtr", "uart_rts", "uart_tx",
    "v30_ss_err_unused", "v30_ss_quiet_unused", "v30_ss_rdata_unused",
    # Orphaned by the XT hardware's removal (2026-09-22), kept deliberately:
    # the mouse stream is generated and paced with no PC-98 consumer until
    # the board's serial mouse port is written, and the display page bit
    # (port 0xA4) waits for the graphics display fetch's reader to land --
    # pc98_gvram_display.sv is committed but not yet instantiated.
    "mouse_rd", "mouse_rts_n", "gvram_disp_page_w",
}


def dangling_nets(path):
    src = open(path).read()
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    declared = set()
    for m in re.finditer(r"^\s*(?:wire|logic|reg)\b([^;]*);", src, re.M):
        body = re.sub(r"\[[^\]]*\]", " ", m.group(1))
        # "wire x = expr;" is driven by that very line, not one-sided.
        if "=" in body:
            continue
        declared.update(re.findall(r"\b([a-z_]\w*)\b", body))
    declared -= {"signed", "unsigned", "automatic", "const"}
    ports = re.findall(r"\.\w+\s*\(\s*([A-Za-z_]\w*)\s*\)", src)
    out = []
    for net in sorted(declared):
        if net in DANGLE_OK:
            continue
        uses = len(re.findall(r"\b" + re.escape(net) + r"\b", src))
        in_ports = ports.count(net)
        # one declaration + one port connection = it touches nothing else
        if in_ports == 1 and uses == 2:
            out.append(net)
    return out


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
    for path in SCAN:
        nets = dangling_nets(path)
        if nets:
            bad += 1
            print(f"{path}: {len(nets)} net(s) connected on one side only:")
            for n in nets:
                print(f"    {n}")
        else:
            print(f"{path}: no one-sided nets")
    if bad:
        print("\nAn unconnected input reads as zero and is indistinguishable "
              "from a real measurement of zero; a one-sided net throws away "
              "whatever drives it just as quietly.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
