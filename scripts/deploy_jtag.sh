#!/usr/bin/env bash
# deploy_jtag.sh [--run N | --sof path] [--no-check]
#
# The JTAG iteration loop as one command: wait for the CI quartus
# bitstream (or take a local .sof), flash it over JTAG, then read the probe
# table so the boot verdict is on screen before the SD card ever moves.
#
#   scripts/deploy_jtag.sh                 # latest build run on this branch
#   scripts/deploy_jtag.sh --run 12345     # a specific run
#   scripts/deploy_jtag.sh --sof x.sof     # skip CI entirely
#
# The Pocket must already be running a core (the MCU only lets JTAG SRAM
# programming take while configured -- jtag_flash.sh's header explains why).

set -euo pipefail
cd "$(dirname "$0")/.."

RUN=""
SOF=""
CHECK=1
while [ $# -gt 0 ]; do
    case "$1" in
        --run)      RUN="$2"; shift 2 ;;
        --sof)      SOF="$2"; shift 2 ;;
        --no-check) CHECK=0; shift ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
done

if [ -z "$SOF" ]; then
    if [ -z "$RUN" ]; then
        BRANCH="$(git branch --show-current)"
        RUN="$(gh run list --branch "$BRANCH" --workflow build.yml \
                 --limit 1 --json databaseId --jq '.[0].databaseId')"
        [ -n "$RUN" ] || { echo "no build runs on branch $BRANCH"; exit 1; }
    fi

    echo ">> waiting for build run $RUN"
    if ! gh run watch "$RUN" --exit-status --interval 30; then
        echo ">> run $RUN did not succeed -- nothing to deploy"
        exit 1
    fi

    mkdir -p fpga/output_files
    echo ">> downloading bitstream"
    gh run download "$RUN" -n bitstream \
        -D fpga/output_files --clobber
    SOF="fpga/output_files/ap_core.sof"
fi

[ -f "$SOF" ] || { echo "no such .sof: $SOF"; exit 1; }
scripts/jtag_flash.sh "$SOF"

if [ "$CHECK" -eq 1 ]; then
    echo ">> cold boot + POST settling (20 s)"
    sleep 20
    openocd -f scripts/jtag_probe.cfg -f scripts/jtag_probe_read.tcl \
        2>&1 | grep -v 'Info\|Warn\|Open On\|Licensed\|DEPRECATED' | tail -25
fi
