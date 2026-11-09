#!/usr/bin/env bash
# Everything CI checks, on Linux x86-64 (GitHub's ubuntu runners):
# luacheck and the tests (tools/gzreader/tests/run.sh), then GZreader started
# in the emulator (qemu) on a Kindle 3, Kindle 4, Kindle Touch, Paperwhite 3,
# Nook 1st Edition and Nook Simple Touch (GZ_CI_MODELS), with KOReader's
# official Kindle 2/3/DX binaries, checking what makes it GZreader: menus,
# names, the Menu key, Settings, launcher, picture books, the Nook's colour
# screen, menu text size (tools/gzreader/emulator/keeps.lua); and CPU
# budgets for a Kindle 3's everyday work (emulator/perf.lua, perf_check.py
# against emulator/perf_baseline.json; GZ_CI_PERF=0 skips them).
#
#   tools/gzreader/ci-test.sh <koreader-kindle-legacy-vX.zip> <out dir>
#
# GZ_CI_MODELS=none: the tests only, no emulator (CI, for a pull request that
# changes nothing the emulator runs: tools/gzreader/ci_emulator_needed.py).
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
if [ "${GZ_CI_MODELS:-}" = none ]; then
    echo "- ⏭️ skipped: this change touches only the web pages (docs/), tests, Markdown or the changelog" >> "$SUM"
    cat "$SUM"
    exit $failed
fi
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
# CPU budgets: a Kindle 3's everyday work (start, a book, page turns, the
# quick panel, Home) against tools/gzreader/emulator/perf_baseline.json
# (perf.lua, perf_check.py). GZ_CI_PERF=0 skips it.
if [ "${GZ_CI_PERF:-1}" = 1 ] && [[ " ${GZ_CI_MODELS:-k3 k4 kt pw3 nook nst} " == *" k3 "* ]]; then
    echo "### CPU budgets (emulator, Kindle 3)" >> "$SUM"
    rm -rf "$OUT/nook-home/GZreader"
    GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=k3 EMU_TIMEOUT=420 \
        bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/perf.lua" "$OUT/perf-k3" > /dev/null 2>&1
    python3 "$REPO/tools/gzreader/emulator/perf_check.py" "$OUT/perf-k3/perf.json" \
        "$REPO/tools/gzreader/emulator/perf_baseline.json" >> "$SUM" || failed=$((failed + 1))
    [ -s "$OUT/perf-k3/perf.json" ] && { echo '```'; cat "$OUT/perf-k3/perf.json"; echo '```'; } >> "$SUM"
fi
cat "$SUM"
exit $failed
