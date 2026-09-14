#!/usr/bin/env python3
"""check_rom_pair.py -- are the ITF and the BIOS a matched pair?

THE FAILURE THIS CATCHES, measured 2026-09-14. The ITF switches the ROM bank
from itself to the BIOS *in the middle of a routine*:

    F88D6  BA 3D 04   mov dx,043D
    F88D9  B0 12      mov al,12
    F88DB  EE         out dx,al     <- from here the fetches come from the BIOS
    F88DC  FC         cld           <- and the ITF expects THIS to still be here
    F88DD  B8 00 F8   mov ax,F800
           ...                         its own ROM-checksum routine

On a matched set that is transparent, because the BIOS image carries the same
continuation at the same address. On a mismatched one the instruction stream
changes under the CPU: it runs unrelated BIOS code, derails into zeros, and the
ITF restarts -- which on hardware looks like "MEMORY 000KB OK, then reboot",
and cost this project half a day of hunting an RTL bug that was not there.

It is the SECOND time a spliced image has manufactured a phantom hardware bug
here; docs/FRANKEN_ROM_LESSON.md is the first. That note asked for a check that
runs in minutes. This is it.

    scripts/check_rom_pair.py [rom_dir]      default ~/.pc98roms
"""
import sys, os

BANK_SWITCH = bytes([0xBA, 0x3D, 0x04, 0xB0, 0x12, 0xEE])   # mov dx,043D; mov al,12; out dx,al
CONT_LEN    = 16       # how much of the continuation to demand
ITF_BASE    = 0xF8000  # where itf.rom is mapped
BIOS_BASE   = 0xE8000  # where bios.rom is mapped


def main(romdir):
    itf  = open(os.path.join(romdir, "itf.rom"),  "rb").read()
    bios = open(os.path.join(romdir, "bios.rom"), "rb").read()
    print("itf.rom  %6d bytes -> %05X" % (len(itf),  ITF_BASE))
    print("bios.rom %6d bytes -> %05X" % (len(bios), BIOS_BASE))

    sites = [i for i in range(len(itf) - len(BANK_SWITCH))
             if itf[i:i+len(BANK_SWITCH)] == BANK_SWITCH]
    if not sites:
        print("\nno in-place bank switch found in the ITF -- this check does not")
        print("apply to this image, which is itself worth knowing.")
        return 0

    bad = 0
    for off in sites:
        guest = ITF_BASE + off
        after = off + len(BANK_SWITCH)
        cont  = itf[after:after + CONT_LEN]
        # where that guest address lands in the BIOS image
        bios_off = (guest + len(BANK_SWITCH)) - BIOS_BASE
        have = bios[bios_off:bios_off + CONT_LEN] if 0 <= bios_off < len(bios) else b""

        print("\nbank switch at %05X (itf.rom+%04X)" % (guest, off))
        print("  the ITF continues with : " + " ".join("%02X" % b for b in cont))
        print("  the BIOS has there     : " + " ".join("%02X" % b for b in have))
        if have == cont:
            print("  MATCHED -- the switch is transparent here")
        else:
            bad += 1
            print("  *** MISMATCHED ***")
            # is it anywhere else in the BIOS at all?
            for n in (CONT_LEN, 12, 8):
                if cont[:n] in bios:
                    print("      (the first %d bytes do appear at BIOS+%05X)"
                          % (n, bios.index(cont[:n])))
                    break
            else:
                print("      the continuation is nowhere in the BIOS image")

    if bad:
        print("\nFAIL: %d of %d bank switches land on foreign code." % (bad, len(sites)))
        print("The ITF and the BIOS are not a matched pair. The machine will run")
        print("the memory test, hand over, derail and restart -- MEMORY 000KB OK")
        print("followed by a reboot. No amount of RTL work fixes this; the fix is")
        print("a matched ITF + BIOS dumped from one machine.")
        return 1

    print("\nPASS: every bank switch has its continuation in the BIOS.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else
                  os.path.expanduser("~/.pc98roms")))
