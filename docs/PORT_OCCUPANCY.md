# SDRAM port occupancy — who eats the bus, and does it starve the CPU

Branch `port-occupancy`. Question: PC-98 games/demos run slower than real
hardware and slower than NP2kai — is SDRAM arbitration starving the guest
CPU?  Answer below: **no, the arbiter is not the bottleneck** (the busiest
measured phase uses ~44% of the device); the guest's cost is per-access
serialization, and the one port that *does* hurt is the GVRAM display
fetch — which ran even when the display was off.  Both findings are
measured; two countermeasures are implemented and re-measured.

## Arbiter map

Path: `Zet CPU -> zet_cpu_bridge (8288 byte engine, CE-paced) ->
RAM.sv -> sdram_shim.sv -> sdram_mp.sv -> board SDRAM`.

`fpga/core/sdram_mp.sv` is the multiport controller (`state_t` at
sdram_mp.sv:128-131: `S_INIT_*`=0..3, `S_IDLE`=4, `S_ACT`=5, `S_RW`=6,
`S_RD_GAP`=7, `S_TAIL`=8, `S_REF_PRE`=9, `S_REF`=10, `S_PRE_MISS`=11).

- **Ports**: `PORTS=5` via the shim (the RTL default of 3 is overridden).
  Concatenation in `sdram_shim.sv` puts `req`/`b_req`/`c_req`/`d_req`/`e_req`
  on ports 0..4:

  | port | client | r/w | typical burst |
  |------|--------|-----|---------------|
  | 0 (A) | guest CPU through `RAM.sv` (all guest RAM + ROM windows, plus the gvram-seq service shares it) | rw | 1-2 words (byte→1, word→2) |
  | 1 (B) | `pc98_font_fetch` (kanji glyph rows) | ro | 16 |
  | 2 (C) | `pc98_cgwindow` | ro | 16 |
  | 3 (D) | `pc98_gvram_display` line-buffer fills | ro | 16 |
  | 4 (E) | `fdd_ramimg` RAM-image floppy server | rw | 16 |

- **Arbitration**: round-robin. `winner` = first `p_req` at-or-after
  `rr_ptr` (wrapping); `rr_ptr = winner + 1` after the grant
  (sdram_mp.sv:150-161, 376-377). One transaction in flight at a time; the
  grant quantum is the *whole transaction* — all `p_len+1` beats plus its
  row/refresh overhead. There is no preemption or time-slice.
- **Handshake**: client holds `p_req` until `p_ack` (1-cycle pulse when the
  FSM leaves `S_IDLE` for it); `p_done` pulses when the transaction drains;
  `p_rvalid`/`p_rdata`/`grant` tag each read beat to its owner
  (`mp_grant` in the bench monitor).  `p_wcnt` indexes write data beats.
- **Open-row policy**: `{row,bank,col} = a[23:11], a[10:9]^a[16:15], a[8:0]`
  (the XOR is new — see below).  Row hit → `S_RW` directly, no command
  latency.  Closed bank → `S_ACT` (ACT + `T_RCD`=2).  Wrong row open →
  `S_PRE_MISS` (PRE + `T_RP`=2, then ACT + `T_RCD`=2).  Rows stay open
  after a transaction.
- **Refresh**: `refresh_cnt >= REFRESH_INT(320)` ⇒ at next `S_IDLE` with
  `pre_guard==0`: PRECHARGE ALL + `T_RP`, then AUTO REFRESH + `T_RFC`=4
  (shim override; RTL default 7).  Requests are blocked meanwhile.
  ~2% of cycles; the part model occasionally flags "refresh interval
  exceeded" (~345 vs 335) when a transaction delays it — benign.
- **Port-0 read gap**: between beats of a *multi-word* port-0 read the FSM
  inserts `S_RD_GAP` (1 NOP) so the DQ capture lands mid-window
  (sdram_mp.sv:452-463).  Ports B–D burst at full rate.  Single-word CPU
  reads pay nothing extra.
- **Writes** finish at the last write command; `pre_guard`=`T_WR` holds off
  only a following precharge (miss or refresh), not the next access.
- **Read data**: DQ captured on the falling (device-edge) clock,
  `RD_DELAY = CAS_LATENCY+1` = 3; `p_rvalid` = `rd_pipe[RD_DELAY-1]`;
  `S_TAIL` drains the pipe so `p_done` never precedes the last beat.

Per-transaction fixed cost for a port-A byte read, row hit:
accept→`S_RW`(1 beat)→`S_TAIL`(3)→done ≈ 6-8 cycles ≈ 140-190 ns @42.95 MHz.
Measured avg req→done is 6-9 depending on load — matches.

## Instrumentation (sim only)

`sim/tb_pc98_boot.sv` under `ifdef REALMEM` taps `u_ram.u_sdram.u_mp`
hierarchically (same trick as `sim/tb_ram_dma_fill.sv`) — zero shipping
impact:

- per-port `own` (grant held while FSM busy), `wait` (req & !ack),
  `trans`/`rd`/`wr` counts, per-port ACT/PRE_MISS cycles;
- port-A req→ack and req→done latency, max and histogram;
- refresh/init cycle totals;
- D-port grant cycles split by raster phase (`vid_hb`/`vid_vb`/`de`);
- `zwb` wishbone pending/ack, RAM-FSM busy, guest-bus stall, gvram-seq busy.

The bench also now instantiates the real `pc98_video_timing` +
`pc98_gvram_display` on port D (previously tied off — every earlier port-A
latency measurement was a best case).  Plusargs: `+disp=0/1`,
`+analog4=0/1` (4th plane E), `+disppage`, `+dbl`, `+fontb=N`, `+porte=N`
(synthetic B/E pressure, default off).  OCC report prints per chunk and at
the end.

## Method

`scripts/sim_pc98_zet_boot.sh --realmem`, BIOS/ITF from `~/.pc98roms`,
`+chunks=1` = 5,000,000 chipset clocks ≈ 116 ms of guest time after SDRAM
init.  The guest reaches the ITF's GDC-init + vsync-poll loop
(PC `F8483`-`F848B`, polling port 0x60/GDC FIFO) — a steady mix of fetches,
data r/w and I/O; it does not reach DOS or an app in one chunk.  CPU is the
experimental Zet free-running at clk_chipset; its *bus cycles* are paced by
the 8288 byte engine on the cpu_ce train (default speed = 4.915 MHz mode),
so `zwb pending` includes deliberate T-state pacing, not just SDRAM time.

## Measured (1 chunk = 4,989,952 cycles post-init)

| config | A own | D own | refresh | act/pre | A wait | A req→done avg/max | guest stall | EU steps |
|---|---|---|---|---|---|---|---|---|
| baseline, 3-plane | 1,037,204 (21%) | 901,567 (18%) | 2% | 182,975 | 392,009 | 8 / 46 | 37% | 257,517 |
| baseline, 4-plane (analog) | 1,034,333 (21%) | 1,202,953 (24%) | 2% | 229,056 | 459,273 | 9 / 45 | 38% | 252,668 |
| gated, `+disp=0` | 1,054,565 (21%) | 0 | 2% | 45,945 | 153,435 | 6 / 19 | 33% | 274,858 |
| gated+bank-XOR, 3-plane | 1,039,987 (21%) | 890,475 (17%) | 2% | 172,693 | 382,505 | 8 / 46 | 37% | 258,066 |
| gated+bank-XOR, 4-plane | 1,037,717 (21%) | 1,187,891 (23%) | 2% | 215,922 | 450,918 | 9 / 46 | 38% | 253,076 |

Per-port act/pre (3-plane): A=92,168 D=90,807 → after XOR A=92,938
D=79,755.  4-plane after XOR: A=108,957 D=106,965.

Ports B/C/E: zero transactions in this phase (font fetch only fires on
kanji rows; E only while a RAM-image floppy serves).

## What the numbers say

1. **The arbiter is not starving the CPU.**  Worst case total ownership is
   ~44%; port A waits ~1.4 cycles average for a grant and finishes in ~8.
   The SDRAM has headroom.
2. **Display fetch is the only meaningful interloper**, 18% of all cycles
   in digital mode, 24% in 4-plane analog.  Its grants land ~100% in
   *visible* line time (vis=901,501 vs hb=66 vs vb=0) — fills are
   lookahead-pipelined across the whole line, like the real uPD7220's
   display-refresh reads, not confined to hblank.  Cost to the guest in
   this phase: **~6.7% EU steps** (274,858 vs 257,517 with D off), mostly
   via grant queuing (A wait 392k→153k) and bank-0 row thrash.
3. **Before the fix, D fetched even when the display was off** —
   `disp_on` gated only the pixel output (`gfx_dot`), never the fill FSM.
   On real hardware the GDC does no display-refresh DRAM cycles while
   STOPped (np21w gdc.c), and the machine spends most of boot/text time
   stopped.  `+disp=0` before the change produced identical numbers to
   `+disp=1`.
4. **Bank-0 thrash was real but second-order.**  Planes B/R/G/E and the
   BIOS mirror all map to the same bank under `a[10:9]`; ~half of all
   act/pre cycles belong to D/A row evictions.  Still only ~4% of time —
   fixing it is worth ~0.2% guest speed, not more.
5. **The real slowness is serialization upstream of the arbiter:**
   zwb avg latency ≈ 22-25 chipset cycles per access, of which ~6-9 is the
   SDRAM transaction; the rest is the 8288 byte engine's CE-paced T-states
   plus RAM-FSM turnaround (`ramfsm busy` ~51-55%).  Each guest byte/word
   pays a full round trip, never pipelined, never cached.

## Changes made (sim-verified)

### 1. Gate display fills on `disp_on` — `fpga/core/pc98_gvram_display.sv`

`disp_on` is 2FF-synced into the fetch domain and gates the fill *launch*
only; the partition/address walk keeps tracking so a mid-frame START
resumes on the right line, and an in-flight fill completes.  Faithful to
the hardware (STOP = no display-refresh accesses) and removes ~18-24% of
bus ownership during boot, text mode, and any blanked interval.

Before/after (`+disp=0`): D trans 40,538→0, A wait 392,009→153,435,
A req→done max 46→19, **EU steps 257,517→274,858 (+6.7%)**.  With
`+disp=1` the numbers are bit-identical to baseline — the gate is
transparent when the display runs.

### 2. Bank spread: `bank = a[10:9] ^ a[16:15]` — `fpga/core/sdram_mp.sv`

The two bank bits are XORed with the 32KB-pair field, so the four GVRAM
planes land in four different banks instead of all sharing bank 0 with the
BIOS window.  Injective in {row,bank,col} (a[16:15] live inside the row
field); `sim/sdram_model.sv::flat()` un-XORs to keep `poke()` guest-linear.
Display-on: act/pre 182,975→172,693 (-6%), D own -1.2%, EU +0.2%; display
off: identical.  Small but free.

## Ranked remaining countermeasures

| idea | expected gain | risk |
|---|---|---|
| RAM.sv read prefetch / sequential coalescing on port A (fill 2-4 words per fetch into a small buffer) | largest: cuts per-byte SDRAM round trips for fetch streams; the ~6-9 cycle transaction amortizes over multiple guest bytes | moderate: ordering vs writes, parked-write mechanism, MEMPATH correctness |
| Display burst 16→32 (or 2×40) — needs `p_len` widened to 5 bits | ~1-2% total ownership | low-med: buffer-write timing, len plumbing through shim |
| CPU priority over RR | <1% — A already waits ~1.4 cyc avg; only trims the 36-cyc tail | med: could push D fills past their line deadline (`late` counter) |
| Refresh tuning | none to gain (~2%, mostly idle overlap) | n/a |
| CAS latency / RD_GAP removal on port 0 | ~1 cyc on multi-word reads only | high on hardware — the gap exists for a measured DQ capture hazard |

## Limitations

- One bench phase only: ITF boot → GDC init → vsync poll.  No DOS, no app;
  the guest never escapes the poll loop within a chunk.  Absolute occupancy
  will differ in a game (port A r/w mix shifts, ports B/C/E wake up), but
  the structure — 40% peak utilisation, ~8-cycle A latency — is not
  phase-specific.
- `zwb pending` conflates CE T-state pacing with real memory latency;
  EU steps is the honest CPU-speed proxy.
- dot_clk is chipset/2 (21.5 MHz vs the part's ~21.05) — line rate is ~2%
  fast, making D pressure slightly conservative.
- SDRAM `refresh interval exceeded` warnings (~340 vs 335) are model-margin
  noise from refresh deferral behind in-flight work, not corruption.
- Bank-XOR changes the physical access pattern; functionally safe in sim
  (identical data returns), but like every change near the DQ capture path
  it deserves a hardware look before shipping — the comments in sdram_mp
  about marginal address-bus behaviour exist for a reason.
- `sim/tb_pc98_boot.sv` monitor is `ifdef REALMEM`-gated; it does not
  affect the bitstream.  `RAM.sv`'s `dbg*` pins stay unconnected in the
  bench (pre-existing PINMISSING warnings).
