#!/bin/bash
# jtag_flash.sh -- program the FPGA over the USB Blaster's JTAG, volatile.
#
#   jtag_flash.sh [bitstream.rbf]
#
# The bitstream is the CI artifact's ap_core.rbf (raw, NOT the card's
# bit-reversed rbf_r). SRAM programming only -- a power cycle or a core
# reload restores whatever the card carries. Seconds instead of a card
# swap, which is what makes hardware-in-the-loop bearable.
set -eu
RBF="${1:-build/artifact_latest/output_files/ap_core.rbf}"
[ -f "$RBF" ] || { echo "no such bitstream: $RBF" >&2; exit 1; }
openFPGALoader --cable usb-blaster "$RBF"
