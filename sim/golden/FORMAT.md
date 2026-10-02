# Golden op-stream format

One operation per line. `#` starts a comment; blank lines are ignored.
The np2kai recorder (`np2ops` in the NP2kai tree) emits the same format, so a
captured session replays verbatim through `sim_egc_golden.sh +stream=...`.

| Op            | Meaning                                                  |
|---------------|----------------------------------------------------------|
| `M <n>`       | engine select: 0 normal VRAM, 1 GRCG path, 2 EGC path    |
| `E <rg> <vv>` | byte write to EGC port 0x4A0+rg (dropped while EGC off)  |
| `GM <vv>`     | GRCG mode register (port 0x7C)                           |
| `GT <p> <vv>` | GRCG tile register, plane p; 16-bit form carries a word, |
|               | but hardware sets both bytes equal on port 0x7E          |
| `P <v>`       | access page (port 0xA6 bit0; golden models page 1 at     |
|               | mem[]+0x100000)                                          |
| `W8 <a> <vv>` | byte write at guest address a                            |
| `W16 <a> <v>` | word write                                               |
| `R8 <a> <vv>` | byte read, expected value vv (mismatch = diff)           |
| `R16 <a> <v>` | word read, expected value                                |
| `F <a> <vv>`  | flat poke -- seed VRAM without driving the access path   |
| `X`           | compare the whole VRAM image now                         |
| `# P <v>`     | (comment) page marker the recorder emits for readability |

## Semantics notes

- Addresses are guest CPU addresses: windows 0xA8000/0xB0000/0xB8000 (GRCG
  planes) and 0xE0000-0xE7FFF (EGC). Anything else is plain RAM on both
  sides.
- Odd word accesses split into two byte bus cycles in np21w order: lo first,
  except hi first while the EGC shift direction is down (egc.sft bit 12).
  The bench does the same on the RTL side because each byte op moves the
  shift queue.
- `M 2` alone does NOT engage the EGC in np21w: the vacctbl EGC rows need
  GRCG armed too (`GM` bit7). A recorded stream that sets mode2's EGC bit
  always carries the matching `GM` write anyway.
- The bench feeds each op to the DUT sequencer AND to np21w's own
  egc.c/memegc.c/memvram.c (built from `np21w/`), then compares readback
  values, the EGC internals it exports, and the final VRAM image.
