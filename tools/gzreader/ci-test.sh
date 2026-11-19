#!/usr/bin/env bash
# Everything CI checks, on Linux x86-64 (GitHub's ubuntu runners):
# luacheck and the tests (tools/gzreader/tests/run.sh), then GZreader started
# in the emulator (qemu) on a Kindle 3, Kindle 4, Kindle Touch, Paperwhite 3,
# Nook 1st Edition and Nook Simple Touch (GZ_CI_MODELS), and as a Kobo
# Clara HD and Libra 2 (GZ_CI_KOBO), with KOReader's
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
# Needs: luajit lua-socket lua-sec lua-check python3 (+ radicale) curl rsync unzip
#        qemu-user-static libc6-armel-cross libgcc-s1-armel-cross, a writable /mnt/us and /mnt/onboard.
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
python3 "$REPO/tools/gzreader/tests/make_epub.py" --big "$OUT/big.epub"
mkdir -p "$OUT/nook-home"
for model in ${GZ_CI_MODELS:-k3 k4 kt pw3 nook nst}; do
    rm -rf "$OUT/nook-home/GZreader"
    GZ_NOOK_HOME="$OUT/nook-home" GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_PICTURES="$OUT/pictures.epub" GZ_EMU_BIG="$OUT/big.epub" \
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
# Kobos: the Clara HD (a snow-protocol panel) and the Libra 2, with the same
# binaries (emulator/kobo_tour.lua): the tabs, a book, the quick panel,
# Settings, Sync with a computer. GZ_CI_KOBO=0 skips them.
if [ "${GZ_CI_KOBO:-1}" = 1 ]; then
    for model in clara libra; do
        rm -rf /mnt/onboard/GZreader
        GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=420 \
            bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/kobo_tour.lua" "$OUT/kobo-$model" > /dev/null 2>&1
        k="$OUT/kobo-$model/kobo-checks.txt"
        if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ]; then
            failed=$((failed + 1)); echo "- ❌ $model (Kobo): didn't finish (see kobo-$model.txt)" >> "$SUM"
        elif grep -q '^FAIL' "$k"; then
            failed=$((failed + 1)); echo "- ❌ $model (Kobo): $(grep -c '^ok' "$k") ok, $(grep -c '^FAIL' "$k") failed" >> "$SUM"
            sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
        else
            echo "- ✅ $model (Kobo): $(grep -c '^ok' "$k") checks" >> "$SUM"
        fi
    done
    # a Kobo with a pen (the Elipsa 2E): the pen draws with its pressure, a finger
    # doesn't, its other end rubs out (emulator/kobo_pen.lua)
    GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=condor EMU_TIMEOUT=300 \
        bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/kobo_pen.lua" "$OUT/kobo-pen" > /dev/null 2>&1
    k="$OUT/kobo-pen/kobo-pen-checks.txt"
    if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ]; then
        failed=$((failed + 1)); echo "- ❌ condor (Kobo pen): didn't finish (see kobo-pen.txt)" >> "$SUM"
    elif grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ condor (Kobo pen): $(grep -c '^FAIL' "$k") failed" >> "$SUM"
        sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ condor (Kobo pen): $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
fi
# GZreader in a folder of its own: a drive laid out as before 1.35 (GZreader
# in KOReader's place), moved at start into GZreader/app, books, music, notes
# (emulator/places_tour.lua, places-drive.sh). A Paperwhite 3, and a Clara HD.
echo "### Moving into the GZreader folder (emulator)" >> "$SUM"
for pm in pw3:kindle clara:kobo; do
    model=${pm%%:*}; kind=${pm#*:}
    [ "$kind" = kobo ] && [ "${GZ_CI_KOBO:-1}" != 1 ] && continue
    APPDIR=$(bash "$REPO/tools/gzreader/emulator/places-drive.sh" "$TREE" "$OUT/places-drive-$model" "$kind")
    GZ_EMU_KEEP=1 GZ_MOVE_HOME="$OUT/places-drive-$model" GZ_MOVE_DEVICE=$kind GZ_PLACES=moved \
        GZ_EMU_TREE="$APPDIR" GZ_EMU_MODEL=$model EMU_TIMEOUT=420 \
        bash "$REPO/tools/gzreader/emulator/run.sh" "$REPO/tools/gzreader/emulator/places_tour.lua" "$OUT/places-$model" > /dev/null 2>&1
    k="$OUT/places-$model/places-checks.txt"
    if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ] || grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model ($kind): $( [ -s "$k" ] && grep -c '^ok' "$k" || echo 0) ok (see places-$model.txt)" >> "$SUM"
        [ -s "$k" ] && sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model ($kind): $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
    cp "$OUT/places-drive-$model/GZreader/app/gzreader.log" "$OUT/places-$model/" 2>/dev/null
    rm -rf "$OUT/places-drive-$model"
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
