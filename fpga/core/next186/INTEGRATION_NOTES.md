# Next186 -> i8288 byte bus — integration notes

For whoever writes `next186_cpu_bridge.sv` (next session). Everything below
was read off the vendored RTL at `885d60f`; line refs are to the files in
this directory. The downstream contract the bridge must produce is the one
`../v30_cpu_bridge.sv` and `../../pc98-pocket-zet/fpga/core/zet_cpu_bridge.sv`
(on the zet worktree) already drive: `processor_status` S2-S0 codes,
byte-wide `ad_out`/`cpu_data_bus`/`data_bus`, `word_access`/`data_bus_hi`
for the SDRAM two-lane burst, `io_term` word-I/O termination, INTA byte
pairs (BS_INTA), `processor_ready`+`address_enable_n` pacing, `biu_done`
reload pulse, `pause_core`, `reset_cpu`.

## 0. Unit shape

Upstream wires the two pieces together as `unit186`
(soc_ref/unit186.v, soc_ref/sample_system.v):

    Next186_CPU + BIU186_32bSync_2T_DelayRead
    share CLK and a single enable CE;
    CPU.CE = CE186 & CE        (CE186 is a BIU *output*, comb off its FSM)
    CPU.DIN = (IORQ | INTA) ? PORT_DIN : BIU.DOUT   // the INPORT mux!

Vendor them as one unit inside the bridge. All CPU and BIU outputs are
combinational functions of CE-ticked registers — there is NO handshake/
ready/ack anywhere. The ONLY stall mechanism is withholding CE ticks,
which freezes the entire unit mid-state with all comb outputs (requests
included) held stable. That is the legal stall, and it is the whole trick.

## 1. Instruction-fetch port (CPU <-> BIU, internal to the unit)

CPU side: `IADDR[20:0]` = full physical fetch address (CS<<4+IP, comb),
`INSTR[47:0]` = up to 6 queue bytes at the fetch cursor, `IFETCH`=1 on the
last micro-stage of each instruction, `ISIZE[2:0]` = bytes consumed
(0..6), `FLUSH` = `~IPWSEL || ISIZE==0` — i.e. any taken jump/call/ret/
interrupt/reset (Next186_CPU.v:158, `IPIN`=`ALUOUT` case) or a stage that
explicitly zeroes ISIZE.

BIU side (Next186_BIU_2T_delayread.v): queue = `queue[4] x 32b` +
`qpos`/`qsize`/`rpos`/`piaddr`. `INSTR` is a *combinational* 6-byte window
`{q2,q1,queue[nqpos>>2]} >> nqpos[1:0]` with a live bypass from `RAM_DIN`
while `rdi` says the in-flight dword is the one on display (lines 119-131).

- Normal consume: tick where `CE186 && IFETCH && ~FLUSH` → `qpos += ISIZE`,
  `qsize -= ISIZE`.
- Flush consume: `FLUSH && IFETCH` → `nqpos = {0, IADDR[1:0]}`, BIU sets
  `sflush`: `qsize = -IADDR[1:0]` (i.e. 4-offset usable bytes for the first
  dword), `piaddr = IADDR[20:2]`, `rpos = 0`, and issues a dword fetch at
  `RAM_ADDR = IADDR[20:2]` immediately. Then it keeps prefetching
  (`iread`) until `qsize > 11` before letting `CE186` tick the CPU again —
  so a jump costs ~3 dword fills before the first instruction executes
  (BIU state 1, lines 153-179).
- Prefetch runs whenever the BIU is otherwise idle and `qsize < 13`.
- Discards are the BIU's problem, not ours: `sflush` resets `rpos`/`qsize`
  at a CE tick. Any dword the bridge fetched for the OLD stream has either
  already been latched (harmless — queue indices were reset) or is being
  requested under the OLD `RAM_ADDR`; because our service is demand-driven
  per observed `RAM_ADDR` (see §4), a mid-service flush cannot happen —
  `FLUSH` is a CPU comb output and the CPU cannot advance while CE is
  held. The rule for the bridge: **never prefetch ahead of what the BIU
  is currently asking for on `RAM_ADDR`** and there is nothing to discard.

## 2. Data port (CPU <-> BIU <-> memory)

CPU side: `MREQ` (this stage does a data memory access), `WR`, `WORD`
(16-bit), `ADDR[20:0]` physical byte address, `DOUT[15:0]` write data,
`DIN[15:0]` read data sampled at the stage-ending `CE186` tick.

BIU presents it to memory as a 32-bit fixed-latency SRAM port:

    RAM_MREQ = iread | RAM_RD | RAM_WR   (any request this interval)
    RAM_RD       = data read pending     (1-tick-latency read)
    RAM_WR       = data write pending    (commits at the interval-ending tick)
    iread        = prefetch/flush fetch  (NOT exported; = RAM_MREQ &
                                            ~RAM_RD & ~RAM_WR)
    RAM_ADDR[18:0]  dword address (byte addr >> 2)
    RAM_WMASK[3:0]  write byte lanes ({00,WORD&WR,WR} << ADDR[1:0])
    RAM_DOUT[31:0]  write data, both halves = {DSWAP,DSWAP}
    RAM_DIN[31:0]   read data IN — MUST be valid during the interval
                    *after* the request interval, held to its ending tick.

Request/response pipeline (this is the part the bridge lives in):

- interval I: request signals asserted (comb). SRAM would latch addr at
  the tick ending I; data appears during interval I+1.
- interval I+1: `rdi`=1 → `queue[rpos] <= RAM_DIN` at the ending tick
  (prefetch), or `CE186`=1 in STATE3 → CPU samples `DOUT` (comb off
  `RAM_DIN`) for a data read.
- So EVERY request consumes two unit ticks: one to take the request, one
  to deliver/ latch the data, and `RAM_DIN` must be held stable across the
  whole response interval.
- Split access: `split = (&ADDR[1:0]) && WORD` — an odd word. BIU does it
  as TWO dword requests: STATE1 (addr A) then STATE2 with `data_bound=1`
  → `RAM_ADDR = A[20:2]+1`; `exdata` latches `RAM_DIN[31:24]` (the odd
  byte) at that tick; `DOUT = {RAM_DIN[7:0], exdata}` in STATE3. Writes
  likewise re-strobe `RAM_WR` in STATE3. Bridge: just serve each request
  independently — RAM_ADDR already carries the +1.
- `WSEL[1:0]` input: upstream leaves it DANGLING in unit186 (a real bug —
  it drives `DSWAP`, the odd-byte swap for writes). Wire it
  `{~cpu_addr[0], cpu_addr[0]}` in our wrapper or odd-byte writes land in
  the wrong lane.

## 3. The stall model over the 8-bit bus

Per CE tick the unit wants one of: (a) nothing bus-related — free tick,
(b) a dword in (prefetch or data read), (c) a dword out (write), or
(d) an I/O or INTA access — which the BIU does NOT service at all
(`MREQ=0`; the tick just retires the CPU stage). The bridge therefore:

1. Lets CE run at the `cpu_ce_posedge` train rate when no request is
   pending — same pacing the 8288 logic and the speed-select generator
   already assume. (Do NOT tick at raw clk — effective CPU speed would be
   ~20MHz internally while the bus is ~5-10MHz, breaking every software
   timing loop.)
2. On `RAM_MREQ`/`RAM_RD`/`RAM_WR` (read off the live comb outputs while
   CE is held): keep CE low, run the dword as byte cycles down the 8288
   — 4× byte, or 2× `word_1cyc` where `pc98_sdram_hits` (and honor
   `RAM_WMASK` on writes — only the masked lanes). For a read, park the
   assembled dword on `RAM_DIN`, then emit ONE CE tick (request interval
   ends: `rdi`/`qsize`/`piaddr`/STATE advance), hold `RAM_DIN` through the
   NEXT interval, and allow its ending tick to latch it. If that interval
   asserts a new request, stall again after the latch — i.e. requests
   chain one-per-interval with the response always one interval behind.
   For a write: capture `{RAM_ADDR,RAM_DOUT,RAM_WMASK}` during the stall,
   run the lanes, then one tick commits it (posted-write semantics
   upstream; ours is serialized — slower, correct).
3. On `IORQ` or `INTA` while the BIU's `CE186` output is high — i.e. the
   tick about to land retires a CPU stage that needs a port byte/vector —
   hold CE, run the access, drive the INPORT side of the DIN mux, then
   release. `IORQ = &EAC` covers IN/OUT; `PORT_ADDR = ADDR[15:0]`;
   `NULLSEG` forces segment 0. I/O reads want the byte in DIN[7:0] for
   AL (CPU always loads the low lane: Next186_CPU.v `WE[1:0]={WORD,1}`),
   so mirror the v30 bridge's convention: byte → {b,b}, word → {hi,lo}
   with `io_term` classes for the second byte (TERM_WORD/ACTIVE/PLUS/
   MINUS/EXT08 — same table as both existing bridges).
4. `INTA`: single comb pulse inside the CPU's interrupt micro-stage
   (`{FETCH[5][1],STAGE[2:0]}==4'b1000`, INTA=1, MREQ=0, IFETCH=0 —
   Next186_CPU.v:1562-1567). The vector is sampled from `DIN` into
   `FETCH[3:2]` at the tick ending that stage. Our i8259 needs the metal's
   DOUBLE-INTA: freeze exactly like zet bridge does for `wb_tgc_o`, run
   two BS_INTA byte cycles (ACK1 sets ISR, ACK2 returns the vector), then
   release with `{8'h00, vector}` on the INPORT path. NMI needs no bus
   cycle: the CPU edge-detects `NMI` internally (`SNMI`/`FNMI`) and takes
   the fixed vector 2 — upstream wires `INTA` low-visible only for INTR.
   `INTR` is a level input sampled every tick (`SINTR<=INTR`) — drive it
   from `interrupt_to_cpu` like the V30's INT pin.
5. `HALT` (CPU output): halted CPU still takes CE186 ticks but issues no
   requests — bus free, arbiter can grant DMA. An interrupt entry drops
   HALT via the `IACK & (... | HALT | ...)` path (Next186_CPU.v:281).
   Present `BS_PASV` (or BS_HALT; for the arbiter they are equivalent —
   S1=S0=1). `LOCK` = CPUStatus[5]; the V30 bridge ties `lock_n` high —
   do the same (a real LOCK prefix on a frozen bus would deadlock DMA
   anyway; PC-98 doesn't need it).
6. `biu_done`: pulse once per served request interval — the CE generator
   reloads `clk_select` on it. `pause_core`: withhold all CE ticks.
   `reset_cpu`: RST is sampled into `SRST` on a CE tick
   (Next186_CPU.v:310) — the reset microcode then needs ~8 CE186 ticks to
   write segs/flags before the first flush/fetch. The CE generator does
   not emit the train during reset, so OR `reset` into the tick gate the
   way `zet_clk = clk & (ce_arm | reset)` does.
7. A20: `ADDR`/`IADDR` are 21 bits (the "Add A20" head commit). The PC-98
   bus is 20-bit; `ad_out[19:0]` drops bit 20 → 1MB wrap, matching the
   V30's view. Confirm against np21w A20-gate behavior when wiring
   (np21w mem/... — the i8088 world has no A20 pin anyway).
8. AEN/`bus_ours`: identical rules to zet bridge — don't start bytes while
   granted away; a hold mid-service just stretches the stall (the unit is
   already frozen, nothing else to save).

## 4. Where this differs from the v30/zet integrations

- **No handshake.** v30 is parked by CE-gating mid-cycle, zet by a
  withheld Wishbone ack. Next186 has neither — the bridge throttles the
  unit's CE and *time*, not a signal, does the sequencing. Simpler
  upstream-facing logic, but the service granularity is a whole request
  interval rather than a bus cycle.
- **Prefetch is real work here.** v30/zet fetch opcodes through the same
  per-access path as data; Next186 wants a dword every idle interval to
  keep its 16B queue full. On this bus each dword ≈ 4 byte cycles ≈ 8-14
  CE ticks. Every taken jump additionally throws the queue away and
  refills ~3 dwords before the next instruction. Expect effective CPU
  throughput far below the V30's — this core earns its keep only if the
  RTL-area saving vs nuV30 (~7,800 ALM) matters more than speed.
- **The 2x-clock assumption dissolves into the CE rate.** Upstream: BIU at
  80MHz, CPU at 40. Ours: one shared enable train at `cpu_ce` rate; CE186
  still gives the CPU ~every other free tick. No 2x PLL needed.
- **Flush is not a bus transaction.** FLUSH+IFETCH arrives inside the
  unit; the only external effect is the BIU re-aiming `RAM_ADDR` at
  `IADDR[20:2]`. The bridge never sees "a flush", only a new dword request
  (and a burst of discarded read latency it already paid for the old
  stream — acceptable).
- **Instruction bytes are not fetchable lazily.** If anyone considers
  dropping the BIU and hand-feeding `INSTR`: `INSTR` must be
  combinationally valid every CE186 tick — that means keeping a queue
  replica in the bridge anyway, plus reproducing `nqpos`/`sflush`
  semantics. Vendored-BIU + CE-stall is strictly less work; only revisit
  if fit forces it.

## 5. Suggested port skeleton for `next186_cpu_bridge`

Wrap `next186_unit` (CPU+BIU+DIN-mux, see `sim/next186_unit.v`):

    unit CE   = cpu_ce_posedge gated by bridge FSM (| reset)
    watch     = {RAM_MREQ, RAM_RD, RAM_WR, RAM_ADDR, RAM_DOUT, RAM_WMASK,
                 CE186, IORQ, INTA, cpu ADDR[15:0] (port), cpu DOUT, WORD}
    drive     = RAM_DIN (assembled dword, held through response interval)
              = PORT_DIN (io/inta read word, {b,b} byte / {hi,lo} word)
    downstream = identical to zet_cpu_bridge's B_IDLE/B_CMD/B_GAP byte
                 engine: BS_* status, ad_out, cpu_data_bus(+_hi),
                 word_access, io_term, processor_ready/address_enable_n
                 gating, bs_inta pair for INTA.

Byte-engine rule changes vs zet: prefetch/data reads are DWORDS (4 bytes
or 2 word_1cyc bursts, lanes per WMASK); data writes use WMASK lanes; the
response must stay parked for the drain tick after the request tick.

## 6. Known risks / open questions

- Fit (measured, `scripts/measure_core.sh` quartus_map on Cyclone V
  5CEBA4F23C8, this worktree): `next186_unit` = CPU+BIU+DIN-mux =
  **1,535 ALMs / 496 regs / 0 RAM bits**; `Next186_CPU` alone =
  **1,265 ALMs / 326 regs**. The BIU costs ~270 ALMs and is all flops —
  no reason to drop it. References: Zet ~2,178, nuV30 ~7,790, MCL86 ~785.
  Verilator `--lint-only` is clean (19 benign upstream warnings:
  width/case-coverage style, no latches/undriven).
- Speed: dominated by prefetch refill on an 8-bit bus (§4). If it boots
  but lands ~half of zet's speed, that's expected, not a bug.
- The `(FLUSH&&IFETCH&&qsize>5)||(qsize>11)` gate in BIU STATE1 delays CPU
  ticks while the queue is short — under permanent queue starvation the
  CPU can livelock in "prefetch forever". The `qsize>11` path still ticks
  the CPU whenever the queue is full-ish, so as long as dword service
  eventually completes this is only a slowdown, but watch it on the bench.
- INTA freeze must be *before* the first CE186 tick of the stage where
  INTA is high — detect INTA combinationally and gate that tick, not the
  one after (same failure shape as the zet `wb_tgc_o` one-edge-slip bug
  its header describes).
- `in/out` byte at ODD port address: CPU always takes DIN[7:0] into AL
  regardless of ADDR[0]; upstream INPORT semantics are "the addressed byte
  in the low lane". Mirror {b,b} on the port word — matches the v30
  bridge's byte-read assembly.
- Unit tick `CE` must tick during `reset` (`SRST<=RST` is synchronous) —
  `| reset` on the gate, or the core never leaves reset.
