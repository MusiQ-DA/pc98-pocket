#!/usr/bin/env python3
"""build_vm_bios.py -- assemble a PC-9801VM BIOS from its four ROM chips.

The VM is a V30 machine: no 286, no 386, so its firmware is 8086 throughout.
That matters more than anything else about it. The ITF images we had are not --
docs/PC98_ITF_TRACE.md shows the retrobios one printing "Processor is 80386" and
running two of its memory tests in protected mode, and a later 1993 image dies
on a 66-prefixed instruction after eighty-eight of them. Neither can reach its
hand-over on an 8088 core. This BIOS can.

The dumps are per chip, and the bus is sixteen bits wide, so each pair
interleaves even and odd bytes. Which chip is which was settled by evidence, not
by the labels:

  4a even / 1a odd -> F8000-FFFFF, because the last bytes are EA 00 00 80 FD,
                      the PC-98 reset vector, and no other pairing gives one
  3a even / 2a odd -> E8000-F7FFF, because it is the pairing whose strings read
                      (ABCDEFGHIJKLMNOPQRSTUVWXYZ, HALF, LPTon, KBCRT); the
                      other produces CBEDGFIHKJMLONQPSRUTWVYX

Together, 96 KB at E8000-FFFFF, which is the size and place the loader expects.
"""
import os, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/Backup 4TB/Downloads/pc9801vm"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.pc98roms/bios.rom")

def interleave(even, odd):
    out = bytearray()
    for i in range(len(even)):
        out.append(even[i])
        out.append(odd[i])
    return bytes(out)

def chip(name):
    return open(os.path.join(SRC, name), "rb").read()

lo = interleave(chip("cpu_board_3a_23c256e.bin"),  chip("cpu_board_2a_d23c256ec.bin"))
hi = interleave(chip("cpu_board_4a_d23128ec.bin"), chip("cpu_board_1a_23128e.bin"))
bios = lo + hi

if len(bios) != 0x18000:
    sys.exit("expected 96 KB, got %d" % len(bios))
if bios[0x17FF0:0x17FF5] != bytes([0xEA, 0x00, 0x00, 0x80, 0xFD]):
    sys.exit("reset vector is %s, want EA 00 00 80 FD -- check the chip pairing"
             % " ".join("%02X" % b for b in bios[0x17FF0:0x17FF5]))

open(OUT, "wb").write(bios)
print("%s: %d bytes, reset vector EA 00 00 80 FD, entry at FD800 is %s"
      % (OUT, len(bios),
         " ".join("%02X" % b for b in bios[0xFD800 - 0xE8000:][:8])))
