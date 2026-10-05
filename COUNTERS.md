# SDRAM arbiter counters (perf-sdram-counters)

Instrumentation build of zet-cpu (base 1211ab4) that counts what the
`sdram_mp` arbiter does, readable over the existing JTAG probe. The point:
quantify which port the Zet fetch path loses arbitration to before
changing the fetch geometry.

The counters are `PC98_JTAG`-gated (`fpga/config.tcl` already defines it,
so they ship in the normal bitstream) and saturate at `0xFFFFFFFF`.

## Slot map

Read slots (probe `addr` byte). All below 0x80 on purpose -- a probe scan
whose address byte has bit 7 set is a **write** to `addr[6:0]`, so reads
anywhere in 0x80-0xFE alias onto live write slots (0x87 would eject the
RAM image through fdd_ramimg's ctl word, 0x89 clears a JTAG clock
override, etc). 0x01-0x0B is untouched and side-effect free.

| slot | contents                       |
|------|--------------------------------|
| 0x01 | port A grants (accepted txns)  |
| 0x02 | port A stalls                  |
| 0x03 | port B grants                  |
| 0x04 | port B stalls                  |
| 0x05 | port C grants                  |
| 0x06 | port C stalls                  |
| 0x07 | port D grants                  |
| 0x08 | port D stalls                  |
| 0x09 | port E grants                  |
| 0x0A | port E stalls                  |
| 0x0B | total controller cycles        |

A **stall** is a `sdram_clock` (= clk_chipset, ~42.95 MHz) cycle where the
port's `req` was up and the arbiter did not take it -- the wait that port
actually felt (arbiter busy elsewhere or refreshing). `stalls/cycles` is
that port's lost-arbitration occupancy.

Port letters follow `RAM.sv`'s `u_sdram` hookup:

| port | user                                  |
|------|---------------------------------------|
| A    | guest path (CPU fetch/data via RAM)   |
| B    | font fetch (`font_rd_req`)            |
| C    | CG window (`cg_rd_req`)               |
| D    | graphics display read (`gv_rd_req`)   |
| E    | fdd_ramimg image carve-out            |

## Clear semantics

- **Write slot 0x8C** (any data): pulses `perf_clear`, re-zeroing all 11
  tallies on the next `sdram_clock` edge. Clear, run the workload, read.
- Counters also reset with `sdram_reset`.
- Reading never clears; grab snapshots freely.

## Deviations from the original sketch (0de5a0d)

- Readout moved 0xA0-0xAA -> **0x01-0x0B**: 0xA0-0xBF is the post-reset
  trail at zet-cpu HEAD (first case item wins, so the counters would have
  been unreachable), and every 0x80+ slot write-aliases anyway.
- Clear stays on write slot **0x8C** (internal `wr_addr` 7'h0c, unused).
- **Debug swap**: the device was at 95% and the first fit attempt failed
  at 1855/1848 LABs. This build drops the four snapshot banks --
  `rst_snap`, `post_snap`, `f0_snap`, `pc_snap` (~2.5k registers of trail
  copies plus their copy/merge logic) -- to pay for the counters.
  Consequences:
  - Read slots **0x60-0x80, 0xA0-0xE0, 0xC0** now return `DEAD00xx`.
  - Read slots **0x40-0x5F** still work and always show the live
    `pc_hist` ring (`{frozen, w[4:0], entry}` -- the snap branch is gone).
  - Write slots 0x85 (pc_rearm) and 0x86 (trig) still work on the live
    ring; trig bit27 (f0_snap writes-only mode) is a no-op.
  - Result: 16,905/18,480 ALMs (91%).

## Procedure

1. Flash the CI bitstream: `scripts/jtag_flash.sh ap_core_counters.sof`
   (a core must be RUNNING on the Pocket for the bitstream to take).
2. Boot the guest as usual (JTAG-mounted RAM image works unchanged --
   the counters build has no FDC/ramimg changes).
3. While the workload runs (gameplay, membench, boot):

       WAIT_S=10 openocd -f scripts/jtag_probe.cfg -f measure_counters.tcl

   The script clears, waits `WAIT_S`, then prints per-port
   grants/stalls + stall-occupancy and the cycle count.
