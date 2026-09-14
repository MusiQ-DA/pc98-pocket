#!/usr/bin/env python3
"""check_rom_pair.py -- RETRACTED. This check's premise is false.

WHAT IT CLAIMED (2026-09-14, wrong within the hour): that the ITF and the BIOS
are a mismatched pair, because the ITF switches the ROM bank at F88DB and the
BIOS image does not carry the ITF's next instruction at F88DC.

WHY THAT IS WRONG. The routine at F88D6 is not meant to run from the ROM. It is
COPIED INTO LOW RAM and run from there -- which is the only way to switch the
ROM bank at all, since a routine executing out of F8000 cannot swap the image
under its own fetches. Written at an offset that works identically in RAM, it
does the OUT and then reads the newly-selected BIOS through DS:SI while
executing from RAM. The BIOS image having different bytes at F88DC is NORMAL.

The set in ~/.pc98roms is a single-machine PC-9801UX dump -- byte-identical to
the preservation zip the machine's owner supplied -- so the pair was never in
question. The md5 pin in deploy_pc98.sh was right and this check was not.

WHAT IS ACTUALLY TRUE, and still unexplained: low RAM at 0x008D6 is thirty-two
zero bytes at the moment of the bank switch, where the copied stub should be,
and the fetch ring shows the CPU ALREADY cycling through 0x00000 before the
switch happens. The derail is upstream of the hand-over; OUT 043D,12 and the
jump to 0000:08D6 are downstream noise.

Kept, not deleted, because the ROM-identification part of it is still useful
and because docs/FRANKEN_ROM_LESSON.md's whole subject is how confidently a
wrong ROM theory can be argued. This is the second entry in that genre and the
author was the model.

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
