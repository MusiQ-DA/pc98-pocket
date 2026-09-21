#!/bin/bash
# restructure.sh -- rename the XT-heritage directories to the PC-98's shape.
#
# Run ONCE, from the repo root, when no other agent has uncommitted work in
# the tree (it git-mv's directories out from under any live session).
#
#   fpga     -> fpga
#   firmware -> firmware
#   third_party/credits      -> third_party/credits
#   fpga/{LICENSE,README.md} -> repo root
#   fpga/fpga    -> (already removed)
#   fpga/core/chipset      -> fpga/core/chipset
#
# Then rewrites every reference: CI workflows, scripts/, sim/ benches, the
# Quartus .qsf, .gitignore. git mv keeps history; the sed keeps builds.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== moves"
mkdir -p third_party
git mv fpga fpga
git mv firmware firmware
git mv third_party/credits third_party/credits
git mv fpga/scripts third_party/scripts
git mv fpga/LICENSE LICENSE.upstream 2>/dev/null || git mv fpga/LICENSE LICENSE
[ -f fpga/README.md ] && git mv fpga/README.md README.upstream.md
git mv fpga/core/chipset fpga/core/chipset
rmdir fpga/src fpga 2>/dev/null || true

echo "== reference rewrites"
# Order matters: the longest paths first.
FILES=$(git ls-files '*.yml' '*.sh' '*.py' '*.sv' '*.qsf' '*.qpf' '*.tcl' '*.md' 2>/dev/null;
        git ls-files '*.gitignore' .gitignore 2>/dev/null)
for f in $FILES .gitignore; do
  [ -f "$f" ] || continue
  sed -i '' \
    -e 's|fpga|fpga|g' \
    -e 's|firmware|firmware|g' \
    -e 's|third_party/credits|third_party/credits|g' \
    -e 's|chipset/HDL|chipset/HDL|g' \
    -e 's|chipset|chipset|g' \
    -e 's|/fpga":/work|/fpga":/work|g' \
    -e 's|-w /work|-w /work|g' \
    -e 's|fpga|fpga|g' \
    "$f" || true
done

echo "== sanity: the strings are gone"
! grep -rn 'fpga\|chipset' --include='*.yml' --include='*.sh' --include='*.py' \
     --include='*.qsf' .github scripts sim fpga 2>/dev/null | grep -v 'docs/'
echo "clean"
echo
echo "Next: run the firmware build, one sim bench, and push -- CI is the gate."
