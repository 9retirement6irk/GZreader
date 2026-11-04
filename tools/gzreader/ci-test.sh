#!/usr/bin/env bash
# Everything CI checks, on Linux x86-64 (GitHub's ubuntu runners):
# luacheck and the tests (tools/gzreader/tests/run.sh), then GZreader started
# in the emulator (qemu) on a Kindle 3, Kindle 4, Kindle Touch, Paperwhite 3,
# Nook 1st Edition and Nook Simple Touch (GZ_CI_MODELS), with KOReader's
# official Kindle 2/3/DX binaries, checking what makes it GZreader: menus,
# names, the Menu key, Settings, launcher, picture books, the Nook's colour
# screen, menu text size (tools/gzreader/emulator/keeps.lua).
#
#   tools/gzreader/ci-test.sh <koreader-kindle-legacy-vX.zip> <out dir>
#
# Writes <out dir>/summary.md and screenshots; exit status: what failed.
# Needs: luajit lua-socket lua-check python3 (+ radicale) curl rsync unzip
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

echo "### GZreader in the emulator: what makes it GZreader" >> "$SUM"
python3 "$REPO/tools/gzreader/tests/make_epub.py" "$OUT/book.epub"
python3 "$REPO/tools/gzreader/tests/make_epub.py" --pictures "$OUT/pictures.epub"
mkdir -p "$OUT/nook-home"
for model in ${GZ_CI_MODELS:-k3 k4 kt pw3 nook nst}; do
    rm -rf "$OUT/nook-home/GZreader"
    GZ_NOOK_HOME="$OUT/nook-home" GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_PICTURES="$OUT/pictures.epub" \
        GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=420 \
        bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/keeps.lua" "$OUT/keeps-$model" > /dev/null 2>&1
    k="$OUT/keeps-$model/keeps.txt"
    if [ ! -s "$k" ]; then
        failed=$((failed + 1)); echo "- ❌ $model: didn't finish (see keeps-$model.txt)" >> "$SUM"
    elif grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model: $(grep -c '^ok' "$k") ok, $(grep -c '^FAIL' "$k") failed" >> "$SUM"
        sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model: $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
done
cat "$SUM"
exit $failed
