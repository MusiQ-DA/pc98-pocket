#!/usr/bin/env python3
# hdstream.py -- pack a raw .hdm floppy image into a Tcl file of literal
# drscan commands for jtag_hdload.tcl to `source`.
#
# OpenOCD's jimtcl has no `binary scan`, so word packing happens here:
# four little-endian image bytes per 32-bit DR field, HDCHUNK bytes per
# drscan line. A short tail is zero-padded to the next word -- the pad
# lands inside the carve-out bounds and is never addressed by a sector.
#
#   python3 scripts/hdstream.py <img.hdm> <out.tcl> [chunk_bytes]
#
# The generated file sets:  hdimg_nby   (image bytes)
#                           hdimg_sent  (32-bit words actually streamed)
#                           hdimg_spot  ({offset byte} pairs for verify)

import struct
import sys

IMGBYTES = 1261568  # 77c * 8s * 2h * 1024B

def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    img_path, out_path = sys.argv[1], sys.argv[2]
    chunk = int(sys.argv[3]) if len(sys.argv) > 3 else 8192

    data = open(img_path, "rb").read()
    nby = len(data)
    if nby > IMGBYTES:
        data = data[:IMGBYTES]
        nby = IMGBYTES
    rem = nby % 4
    if rem:
        data += b"\0" * (4 - rem)

    words = struct.unpack("<%dI" % (len(data) // 4), data)
    wpc = chunk // 4

    spot = []
    for off in (0, 1, 1023, 1024, 4096, 65536, 262144, 1261564, 1261567):
        if off < nby:
            spot.append((off, data[off]))

    with open(out_path, "w") as f:
        f.write("set hdimg_nby %d\n" % nby)
        f.write("set hdimg_spot {%s}\n"
                % " ".join("%d 0x%02x" % p for p in spot))
        sent = 0
        for i in range(0, len(words), wpc):
            part = words[i:i + wpc]
            f.write("drscan fpga.tap %s -endstate idle\n"
                    % " ".join("32 0x%08X" % w for w in part))
            sent += len(part)
            if sent % 32768 == 0:
                f.write('puts "  pushed %d words (%d bytes)"\n'
                        % (sent, sent * 4))
        f.write("set hdimg_sent %d\n" % sent)
    print("hdstream: %s -> %s (%d bytes, %d words, %d drscans)"
          % (img_path, out_path, nby, len(words),
             (len(words) + wpc - 1) // wpc))
    return 0

if __name__ == "__main__":
    sys.exit(main())
