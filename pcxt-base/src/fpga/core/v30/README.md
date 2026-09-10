# nuV30 -- the V30 core this machine's CPU is being swapped to

Vendored from https://github.com/wickerwaka/nuV30 (GPL-2.0; see
LICENSE.nuV30). Unmodified files from `hdl/rtl/ucore/`:

    v30_core.sv       the core TOP, max mode, muxed-AD or de-muxed bus
    v30u_biu.sv       the bus-interface unit
    v30u_eu.sv        the execution unit (micro-sequencer, loader, datapath)
    v30u_eu_*.svh     the EU's per-row stage includes
    v30u_ucrom.sv     the two build-time tables ($readmemh's ucrom.hex /
                      ucdecode.hex from this directory)
    v30u_ss_pkg.sv    the save-state address map
    pla3_tables.svh   the decode PLA tables

Why: the machine's CPUs are V30s, and its ROMs use the 186-class
instructions that chip has -- the first one measured was the ITF's
`push imm16` in its CPU-reset save sequence, which an 8088-class core
dispatched to the undocumented JS alias, derailing the instruction
stream. This core runs the die's actual microcode (the VCFed extraction)
and was verified against a real V30 with a 3,125,000-case gate.

The `HEXDIR` parameter points at this directory; for simulation the hex
files are copied next to the binary the way the 8088's microcode.mem
always has been.

Local modifications: none yet. Keep it that way where possible -- carry
fixes upstream-shaped, in separate wrapper modules where not.
