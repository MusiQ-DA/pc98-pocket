# Folding the PC/XT branch

A work plan, not a decision. Nothing here has been done.

## The question

`pcxt-base` is a fork of desaster/openfpga-PCXT, and the PC/XT machine it came
from is still in the tree behind `MACHINE_PC98`. Is that worth keeping?

## What it costs, measured 2026-09-15

57 `` `ifdef MACHINE_PC98 `` / `` `ifndef `` sites:

| file | sites |
|---|---|
| `KFPC-XT/HDL/Peripherals.sv` | 27 |
| `core_top.sv` | 15 |
| `pocket_video.sv` | 4 |
| `KFPC-XT/HDL/RAM.sv` | 3 |
| `post_monitor.sv` | 2 |
| `KFPC-XT/HDL/Chipset.sv` | 2 |
| `KFPC-XT/HDL/Bus_Arbiter.sv` | 2 |
| `softcpu_subsystem.sv` | 1 |
| `KFPC-XT/HDL/XT_CE_Generator.sv` | 1 |

**The PC/XT bitstream is never built.** `pcxt-base/src/fpga/config.tcl` sets
`MACHINE_PC98=1` unconditionally and the CI quartus job compiles one project.
Some Verilator benches do run both ways (`+define+CE_XT_BUILD` in
`.github/workflows/build.yml`), but nothing places or routes the PC/XT machine.

So those 57 branches are code nobody has confirmed still works. Three were
edited on 2026-09-15 alone — the IDE gate, the OPNA gate, and floppy.v's
`NOT_READY_ENDS_COMMAND` — each lint-checked both ways and none of them
actually built as a PC/XT.

## What it buys

One thing: **merging from upstream**. `floppy.v`, `ide.v`, `KF8259/`,
`KF8253/`, `KF8255/`, `common/` are upstream files. Keeping the PC/XT path
alive in them means an upstream fix can be taken without untangling it, and
means a fix of ours can go back — `NOT_READY_ENDS_COMMAND` was deliberately
written as a parameter for exactly that reason.

That argument does not extend to the integration layer. `Peripherals.sv`,
`core_top.sv` and `Chipset.sv` have diverged far enough that nothing in them is
going back upstream, and their 44 branches are the bulk of the cost.

## The recommendation, if it is done

Split the tree by provenance rather than deleting wholesale.

### Keep the branch (upstream files)

`common/floppy.v`, `common/ide.v`, `KFPC-XT/HDL/KF8259/`, `KF8253/`,
`KF8255/`, `KF8237/`, `KF8288/`, `KFSDRAM/`.

Rule: differences go in **parameters or ports**, never `` `ifdef MACHINE_PC98 ``
inside an upstream module. `floppy.v`'s `NOT_READY_ENDS_COMMAND` is the worked
example — the PC-98 passes 1, the PC/XT passes 0, the module itself knows
nothing about either machine.

### Fold the branch (our integration layer)

`Peripherals.sv` (27), `core_top.sv` (15), `Chipset.sv` (2) — 44 of the 57.

These are ours, they are not going upstream, and the `` `ifndef `` halves are
the least-read code in the repository.

### Then add CI, or do not bother

If the PC/XT path is kept anywhere, **a second quartus job has to build it**, or
the same thing happens again: a branch that lints and never places. If a second
15-minute fit is not worth it, that is the honest signal to fold the rest too.

## Order of work

1. **Do not start this while the boot is broken.** The machine currently stops
   before N88-BASIC's `Ok`, and a 44-site refactor across the files the boot
   runs through will bury whatever is actually wrong.
2. Take an ALM and LAB baseline from a good fit report first
   (`Logic utilization (in ALMs)` and the `Fitter requires N LABs` line if it
   fails), so the refactor can be shown to change nothing. The device is at
   16,551/18,480 ALMs and 1,848 LABs is the ceiling — this is not a design with
   room to absorb a surprise.
3. Fold one file at a time, lint both ways after each, and keep each file a
   separate commit so a bisect can find it.
4. `Chipset.sv` first (2 sites), then `core_top.sv` (15), then `Peripherals.sv`
   (27). Smallest first, because the pattern that works on the small ones is the
   one to repeat.

## What folding is likely to find

Both of 2026-09-15's biggest area wins came from noticing dead PC/XT code that
was instantiated anyway:

- **IDE** — `ide.v` + `XT2IDE`, 216.6 ALMs, answering an AT task file at
  0x300-0x30F that no PC-98 ROM references at all.
- **floppy.v** — 885 ALMs, its chip select decoding the PC/XT's 0x3F0-0x3F7,
  unreachable from a PC-98 guest, while the PC-98 ports were answered by
  hand-tuned constants in `fdd_stub_data`.

Neither was visible until someone read the decode. Folding the branch is partly
an area exercise: it makes the next one of those impossible to hide.
