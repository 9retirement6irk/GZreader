#!/usr/bin/env bash
# Everything CI checks, on Linux x86-64 (GitHub's ubuntu runners):
# luacheck and the tests (tools/gzreader/tests/run.sh), then GZreader started
# in the emulator (qemu) on a Kindle 3, a Nook 1st Edition and a Nook Simple
# Touch with KOReader's official Kindle 2/3/DX binaries: guide, Home, a book,
# a page turn, Home (tools/gzreader/emulator/smoke.lua).
#
#   tools/gzreader/ci-test.sh <koreader-kindle-legacy-vX.zip> <out dir>
#
# Writes <out dir>/summary.md and screenshots; exit status: what failed.
# Needs: luajit lua-socket lua-check python3 curl rsync unzip
#        qemu-user-static libc6-armel-cross libgcc-s1-armel-cross, a writable /mnt/us.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ZIP=$(cd "$(dirname "${1:?zip}")" && pwd)/$(basename "$1")
OUT=$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)
failed=0
SUM="$OUT/summary.md"
: > "$SUM"

TREE=$("$REPO/tools/gzreader/emulator/make-tree.sh" "$ZIP" "$OUT/tree")

echo "### Tests" >> "$SUM"
if bash "$REPO/tools/gzreader/tests/run.sh" "$TREE" > "$OUT/tests.txt" 2>&1; then
    echo "- ✅ $(grep -E '^[0-9]+ passed' "$OUT/tests.txt" | head -1), luacheck, setup guide, Nook screens" >> "$SUM"
else
    failed=$((failed + 1))
    echo "- ❌ $(tail -1 "$OUT/tests.txt")" >> "$SUM"
    echo '```' >> "$SUM"; grep -E "FAIL|^ +[^ ]+:[0-9]+:[0-9]+: |suite\(s\) failed" "$OUT/tests.txt" | head -40 >> "$SUM"; echo '```' >> "$SUM"
fi

echo "### Starting GZreader (emulator)" >> "$SUM"
python3 "$REPO/tools/gzreader/tests/make_epub.py" "$OUT/smoke.epub"
mkdir -p "$OUT/nook-home"
for model in k3 nook nst; do
    GZ_NOOK_HOME="$OUT/nook-home" GZ_EMU_BOOK="$OUT/smoke.epub" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=300 \
        bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/smoke.lua" "$OUT/smoke-$model" > /dev/null 2>&1
    result=$(cat "$OUT/smoke-$model/smoke.txt" 2>/dev/null || echo "didn't finish (see smoke-$model.txt)")
    if [ "$result" = ok ]; then
        echo "- ✅ $model" >> "$SUM"
    else
        failed=$((failed + 1))
        echo "- ❌ $model: $result" >> "$SUM"
    fi
done
cat "$SUM"
exit $failed
