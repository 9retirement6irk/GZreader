#!/usr/bin/env bash
# Everything CI checks, on Linux x86-64 (GitHub's ubuntu runners):
# luacheck and the tests (tools/gzreader/tests/run.sh), then GZreader started
# in the emulator (qemu), one model for each package GZreader ships:
#
#   kindle-legacy   k3 (Kindle Keyboard) and dxg (DX Graphite: no Wi-Fi, the big screen)
#   kindle          kt (Kindle Touch)
#   kindlepw2       pw3 (Paperwhite 3)
#   kindlehf        scribe (Kindle Scribe)
#   nook            nook (Nook 1st Edition)
#   nook-nst        nst (Nook Simple Touch)
#   kobo            condor (Kobo Elipsa 2E: the one Kobo with a pen, so its pen is checked too)
#
# with KOReader's official Kindle 2/3/DX binaries, checking what makes it
# GZreader: menus, names, the Menu key, Settings, launcher, picture books, the
# Nook's colour screen, menu text size (tools/gzreader/emulator/keeps.lua; the
# Kobo: kobo_tour.lua and kobo_pen.lua); the move into the GZreader folder on
# the Paperwhite and the Kobo (places_tour.lua); and CPU budgets for a Kindle
# 3's everyday work (emulator/perf.lua, perf_check.py against
# emulator/perf_baseline.json).
#
#   tools/gzreader/ci-test.sh <koreader-kindle-legacy-vX.zip> <out dir>
#
# GZ_CI_PART picks one part, so CI can run the parts side by side, each on its
# own machine (.github/workflows/gzreader-tests.yml); unset, everything runs
# here, one after another:
#   tests            luacheck and the test suites only
#   model:<name>     that model's emulator runs only (k3 dxg kt pw3 scribe nook nst kobo)
#   perf             the CPU budgets only
# GZ_CI_MODELS: the models when everything runs (default: all of the above);
# "none": the tests only (a change the emulator can't be affected by:
# tools/gzreader/ci_emulator_needed.py). GZ_CI_PERF=0 skips the budgets.
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
PART=${GZ_CI_PART:-all}
ALL_MODELS="k3 dxg kt pw3 scribe nook nst kobo"
KOBO=${GZ_CI_KOBO_MODEL:-condor}
EMU="$REPO/tools/gzreader/emulator"

TREE=$("$EMU/make-tree.sh" "$ZIP" "$OUT/tree")

run_tests() {
    echo "### Tests" >> "$SUM"
    if bash "$REPO/tools/gzreader/tests/run.sh" "$TREE" > "$OUT/tests.txt" 2>&1; then
        echo "- ✅ $(grep -E '^[0-9]+ passed' "$OUT/tests.txt" | head -1), luacheck, setup guide, Nook screens" >> "$SUM"
    else
        failed=$((failed + 1))
        echo "- ❌ $(tail -1 "$OUT/tests.txt")" >> "$SUM"
        echo '```' >> "$SUM"; grep -E "FAIL|^ +[^ ]+:[0-9]+:[0-9]+: |suite\(s\) failed" "$OUT/tests.txt" | head -40 >> "$SUM"; echo '```' >> "$SUM"
    fi
}

books() {
    [ -s "$OUT/book.epub" ] && return
    python3 "$REPO/tools/gzreader/tests/make_epub.py" "$OUT/book.epub"
    python3 "$REPO/tools/gzreader/tests/make_epub.py" --pictures "$OUT/pictures.epub"
    python3 "$REPO/tools/gzreader/tests/make_epub.py" --big "$OUT/big.epub"
    mkdir -p "$OUT/nook-home"
}

# what makes it GZreader, on a Kindle or a Nook (keeps.lua)
run_keeps() {
    local model=$1 k
    books
    rm -rf "$OUT/nook-home/GZreader"
    GZ_NOOK_HOME="$OUT/nook-home" GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_PICTURES="$OUT/pictures.epub" GZ_EMU_BIG="$OUT/big.epub" \
        GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=${GZ_CI_KEEPS_TIMEOUT:-420} \
        bash "$EMU/run.sh" "$EMU/keeps.lua" "$OUT/keeps-$model" > /dev/null 2>&1
    k="$OUT/keeps-$model/keeps.txt"
    if [ ! -s "$k" ]; then
        failed=$((failed + 1)); echo "- ❌ $model: didn't finish (see keeps-$model.txt)" >> "$SUM"
    elif grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model: $(grep -c '^ok' "$k") ok, $(grep -c '^FAIL' "$k") failed" >> "$SUM"
        sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model: $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
}

# the Kobo: the tabs, a book, the quick panel, Settings, Sync with a computer
# (kobo_tour.lua), and its pen: it draws with its pressure, a finger doesn't,
# its other end rubs out (kobo_pen.lua)
run_kobo() {
    local model=$KOBO k
    books
    rm -rf /mnt/onboard/GZreader
    GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=420 \
        bash "$EMU/run.sh" "$EMU/kobo_tour.lua" "$OUT/kobo-$model" > /dev/null 2>&1
    k="$OUT/kobo-$model/kobo-checks.txt"
    if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ]; then
        failed=$((failed + 1)); echo "- ❌ $model (Kobo): didn't finish (see kobo-$model.txt)" >> "$SUM"
    elif grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model (Kobo): $(grep -c '^ok' "$k") ok, $(grep -c '^FAIL' "$k") failed" >> "$SUM"
        sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model (Kobo): $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
    GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=300 \
        bash "$EMU/run.sh" "$EMU/kobo_pen.lua" "$OUT/kobo-pen" > /dev/null 2>&1
    k="$OUT/kobo-pen/kobo-pen-checks.txt"
    if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ]; then
        failed=$((failed + 1)); echo "- ❌ $model (Kobo), the pen: didn't finish (see kobo-pen.txt)" >> "$SUM"
    elif grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model (Kobo), the pen: $(grep -c '^FAIL' "$k") failed" >> "$SUM"
        sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model (Kobo), the pen: $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
}

# GZreader in a folder of its own: a drive laid out as before 1.35 (GZreader
# in KOReader's place), moved at start into GZreader/app, books, music, notes
# (places_tour.lua, places-drive.sh)
run_places() {
    local model=$1 kind=$2 k APPDIR
    APPDIR=$(bash "$EMU/places-drive.sh" "$TREE" "$OUT/places-drive-$model" "$kind")
    GZ_EMU_KEEP=1 GZ_MOVE_HOME="$OUT/places-drive-$model" GZ_MOVE_DEVICE=$kind GZ_PLACES=moved \
        GZ_EMU_TREE="$APPDIR" GZ_EMU_MODEL=$model EMU_TIMEOUT=420 \
        bash "$EMU/run.sh" "$EMU/places_tour.lua" "$OUT/places-$model" > /dev/null 2>&1
    k="$OUT/places-$model/places-checks.txt"
    if [ ! -s "$k" ] || [ "$(grep -c '^ok' "$k")" -lt 9 ] || grep -q '^FAIL' "$k"; then
        failed=$((failed + 1)); echo "- ❌ $model ($kind), moving into the GZreader folder: $( [ -s "$k" ] && grep -c '^ok' "$k" || echo 0) ok (see places-$model.txt)" >> "$SUM"
        [ -s "$k" ] && sed 's/^/  - /' "$k" | grep FAIL >> "$SUM"
    else
        echo "- ✅ $model ($kind), moving into the GZreader folder: $(grep -c '^ok' "$k") checks" >> "$SUM"
    fi
    cp "$OUT/places-drive-$model/GZreader/app/gzreader.log" "$OUT/places-$model/" 2>/dev/null
    rm -rf "$OUT/places-drive-$model"
}

# everything one model is checked for
run_model() {
    case "$1" in
        kobo) run_kobo; run_places "$KOBO" kobo ;;
        pw3) run_keeps pw3; run_places pw3 kindle ;;
        k3|dxg|kt|scribe|nook|nst|k2|dx|k4) run_keeps "$1" ;;
        *) failed=$((failed + 1)); echo "- ❌ $1: not a model CI knows" >> "$SUM" ;;
    esac
}

# CPU budgets: a Kindle 3's everyday work (start, a book, page turns, the
# quick panel, Home) against emulator/perf_baseline.json (perf.lua, perf_check.py)
run_perf() {
    echo "### CPU budgets (emulator, Kindle 3)" >> "$SUM"
    books
    rm -rf "$OUT/nook-home/GZreader"
    GZ_EMU_BOOK="$OUT/book.epub" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=k3 EMU_TIMEOUT=420 \
        bash "$EMU/run.sh" "$EMU/perf.lua" "$OUT/perf-k3" > /dev/null 2>&1
    python3 "$EMU/perf_check.py" "$OUT/perf-k3/perf.json" "$EMU/perf_baseline.json" >> "$SUM" || failed=$((failed + 1))
    [ -s "$OUT/perf-k3/perf.json" ] && { echo '```'; cat "$OUT/perf-k3/perf.json"; echo '```'; } >> "$SUM"
}

case "$PART" in
    tests)
        run_tests ;;
    model:*)
        echo "### GZreader in the emulator: ${PART#model:}" >> "$SUM"
        run_model "${PART#model:}" ;;
    perf)
        run_perf ;;
    all)
        run_tests
        echo "### GZreader in the emulator: what makes it GZreader" >> "$SUM"
        if [ "${GZ_CI_MODELS:-}" = none ]; then
            echo "- ⏭️ skipped: this change touches only the web pages (docs/), tests, Markdown or the changelog" >> "$SUM"
        else
            for model in ${GZ_CI_MODELS:-$ALL_MODELS}; do run_model "$model"; done
            if [ "${GZ_CI_PERF:-1}" = 1 ] && [[ " ${GZ_CI_MODELS:-$ALL_MODELS} " == *" k3 "* ]]; then run_perf; fi
        fi ;;
    *)
        failed=$((failed + 1)); echo "- ❌ GZ_CI_PART=$PART: not a part (tests, model:<name>, perf)" >> "$SUM" ;;
esac
cat "$SUM"
exit $failed
