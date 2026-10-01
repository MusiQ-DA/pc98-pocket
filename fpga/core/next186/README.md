# Next186 (vendored) — 80186-compatible CPU

Experimental alternative CPU for the PC-98 Pocket core, alongside the Zet
experiment (`zet-cpu` branch) — nuV30 remains the shipping CPU. This directory
holds a pristine vendor drop; nothing here is wired into `core_top` yet. See
INTEGRATION_NOTES.md for the bus-interface study that the future
`next186_cpu_bridge.sv` will implement.

## Provenance

- Upstream project: OpenCores **next186** ("Next 80186 processor"),
  Nicolae Dumitrache, 2012-2014 — https://opencores.org/projects/next186
  (SVN: https://opencores.org/ocsvn/next186/next186/trunk)
- Vendored from the GitHub SVN mirror **freecores/next186**
  (https://github.com/freecores/next186) @ `885d60f`
  "Add A20 address line" (2014-05-13) — trunk HEAD; identical bytes to the
  fabriziotappero/ip-cores OpenCores dump, branch
  `processor_next_80186_processor` @ `15dc956`.
- `soc_ref/` is from the sibling project **next186_soc_pc**
  (https://github.com/freecores/next186_soc_pc) @ `e993c47`
  (2014-05-14, SVN rev 16) — the author's own CPU+BIU glue, kept here as
  reference ONLY: `unit186.v` shows the canonical wiring (including the
  `DIN = (IORQ|INTA) ? INPORT : ram_dout` mux), `PIC_8259.v` shows how INTA
  is served upstream, `cache_controller.v` is Xilinx-primitive code that
  will NOT synthesize for Cyclone V, `sample_system.v` is the original
  trunk's Spartan-3AN example top.
- License: LGPL-2.1-or-later per every file's header; full text in
  LICENSE.Next186. Keep the copyright headers intact in any derivative
  glue.

## Files

| file | module(s) | role |
|------|-----------|------|
| `Next186_CPU.v` | `Next186_CPU` | core: decoder (giant combinational FSM over `STAGE`+`FETCH[]`), interrupt microcode, `Next186_EA` instantiation |
| `Next186_ALU.v` | `Next186_ALU`, `Next186_EA` | ALU/flags + effective-address adder |
| `Next186_Regs.v` | `Next186_Regs` | register file + flags |
| `Next186_BIU_2T_delayread.v` | `BIU186_32bSync_2T_DelayRead` | BIU: 16-byte prefetch queue + data-access serializer over a fixed-1-cycle-latency 32-bit sync SRAM port |
| `Next186_features.doc` | — | author's per-instruction T-state table (Word doc) |
| `soc_ref/*` | — | reference glue from next186_soc_pc, NOT for synthesis |

No caches exist in the CPU trunk itself; the only cache is the SoC's
`cache_controller.v` (soc_ref), which assumes a Xilinx S3 block RAM and a
3x-clock DDR controller — irrelevant to this port.

Nothing in the core files uses `initial`, `$readmemh`, or vendor
primitives; all state is `posedge CLK` + `CE` guarded, which is what makes
the CE-stall integration model in INTEGRATION_NOTES.md legal.
