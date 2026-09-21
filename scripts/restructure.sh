#!/bin/bash
# restructure.sh -- rename the XT-heritage directories to the PC-98's shape.
#
# Run ONCE, from the repo root, when no other agent has uncommitted work in
# the tree (it git-mv's directories out from under any live session).
#
#   pcxt-base/src/fpga     -> fpga
#   pcxt-base/src/firmware -> firmware
#   pcxt-base/credits      -> third_party/credits
#   pcxt-base/{LICENSE,README.md} -> repo root
#   pcxt-base/pcxt-base    -> (already removed)
#   fpga/core/KFPC-XT      -> fpga/core/chipset
#
# Then rewrites every reference: CI workflows, scripts/, sim/ benches, the
# Quartus .qsf, .gitignore. git mv keeps history; the sed keeps builds.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== moves"
mkdir -p third_party
git mv pcxt-base/src/fpga fpga
git mv pcxt-base/src/firmware firmware
git mv pcxt-base/credits third_party/credits
git mv pcxt-base/scripts third_party/scripts
git mv pcxt-base/LICENSE LICENSE.upstream 2>/dev/null || git mv pcxt-base/LICENSE LICENSE
[ -f pcxt-base/README.md ] && git mv pcxt-base/README.md README.upstream.md
git mv fpga/core/KFPC-XT fpga/core/chipset
rmdir pcxt-base/src pcxt-base 2>/dev/null || true

echo "== reference rewrites"
# Order matters: the longest paths first.
FILES=$(git ls-files '*.yml' '*.sh' '*.py' '*.sv' '*.qsf' '*.qpf' '*.tcl' '*.md' 2>/dev/null;
        git ls-files '*.gitignore' .gitignore 2>/dev/null)
for f in $FILES .gitignore; do
  [ -f "$f" ] || continue
  sed -i '' \
    -e 's|pcxt-base/src/fpga|fpga|g' \
    -e 's|pcxt-base/src/firmware|firmware|g' \
    -e 's|pcxt-base/credits|third_party/credits|g' \
    -e 's|KFPC-XT/HDL|chipset/HDL|g' \
    -e 's|KFPC-XT|chipset|g' \
    -e 's|/pcxt-base":/work|/fpga":/work|g' \
    -e 's|-w /work/src/fpga|-w /work|g' \
    -e 's|pcxt-base|fpga|g' \
    "$f" || true
done

echo "== sanity: the strings are gone"
! grep -rn 'pcxt-base\|KFPC-XT' --include='*.yml' --include='*.sh' --include='*.py' \
     --include='*.qsf' .github scripts sim fpga 2>/dev/null | grep -v 'docs/'
echo "clean"
echo
echo "Next: run the firmware build, one sim bench, and push -- CI is the gate."
