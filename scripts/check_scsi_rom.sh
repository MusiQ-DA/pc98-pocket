#!/bin/bash
# check_scsi_rom.sh -- the committed fpga/core/scsi_rom.hex must be the
# assembled fpga/scsi_rom.asm, or Quartus ships a stale disk BIOS.  Same
# disease the firmware job exists for: the bitstream $readmemh's a file
# nothing rebuilds.
#
# Usage: check_scsi_rom.sh          verify committed hex == fresh assembly
#        check_scsi_rom.sh --write  regenerate the committed hex
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=$(mktemp)
trap 'rm -f "$BIN"' EXIT

nasm -f bin -o "$BIN" fpga/scsi_rom.asm

# 4096 bytes, one byte per line of hex -- the $readmemh image.
python3 - "$BIN" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
if len(data) != 4096:
    sys.exit(f"scsi_rom.asm assembled to {len(data)} bytes, expected 4096")
open('/tmp/scsi_rom_new.hex', 'w').write(''.join(f'{b:02x}\n' for b in data))
PY

if [ "${1:-}" = "--write" ]; then
    mv /tmp/scsi_rom_new.hex fpga/core/scsi_rom.hex
    echo "fpga/core/scsi_rom.hex regenerated"
else
    if cmp -s /tmp/scsi_rom_new.hex fpga/core/scsi_rom.hex; then
        echo "scsi_rom.hex matches scsi_rom.asm"
    else
        echo "scsi_rom.hex is STALE -- run scripts/check_scsi_rom.sh --write"
        exit 1
    fi
fi
