#!/usr/bin/env bash
# GZreader's tests, on a computer (no Kindle needed): the plugin against a
# mock Grimmory / Memos / CalDAV (real LuaSocket, KOReader's UI stubbed),
# ZenOS's setup guide, the Nooks' screen commands and launcher helper; plus
# luacheck.
#
#   tools/gzreader/tests/run.sh <koreader base dir> [port]
#
# <koreader base dir>: an unzipped official KOReader package's koreader/
# folder (its ffi/ Lua is used; e.g. koreader-kindle-legacy-vX.zip).
# Needs: luajit, lua-socket, lua-sec, luacheck, python3 with radicale (pip), curl;
# for the sync page, Playwright with Chromium. Ports port … port+15, port+40 … port+62.
# Exit status: the number of failed suites.
set -u
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
T="$REPO/tools/gzreader/tests"
KOBASE=$(cd "${1:?koreader base dir (ffi/ etc.)}" && pwd)
PORT=${2:-18080}
WORK=$(mktemp -d)
# (every test server the suites started: their pid files)
trap 'for f in "$WORK"/mock.pid "$WORK"/*.pid "$WORK"/work/*.pid; do [ -f "$f" ] && kill $(cat "$f") 2>/dev/null; done; rm -rf "$WORK"' EXIT
failed=0
# (each section's name, and the ones that failed: named on the last line, for CI's summary)
SECTION=""; failed_names=""
sec() { SECTION="$*"; echo "== $*"; }
fail() { failed=$((failed + 1)); failed_names="${failed_names:+$failed_names; }$SECTION"; }
# (the calendar tests' expected times are New York's, around its clock change)
export TZ=America/New_York

sec "luacheck"
(cd "$REPO" && luacheck -q plugins/gzreader.koplugin plugins/zenos.koplugin tools/gzreader/emulator frontend/device/nook frontend/device.lua) || fail

sec "every request says GZreader/<version> (its user agent)"
(cd "$T" && luajit useragent_test.lua "$REPO" "$WORK/useragent") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "GZreader's changes to upstream files kept"
python3 "$T/keeps.py" || fail

sec "the sync page (a browser, mock servers)"
mkdir -p "$WORK/work" "$WORK/syncdump"
if python3 -c "import playwright" 2>/dev/null; then
  (cd "$T" && timeout 300 python3 sync_page_test.py $((PORT + 40)) "$WORK/syncdump") > "$WORK/page.txt" 2>&1
  rc=$?
  grep "FAIL" "$WORK/page.txt"
  tail -1 "$WORK/page.txt"
  [ $rc -eq 0 ] || { fail; tail -30 "$WORK/page.txt"; }
  # (the Kindle side takes in what the page left: run_tests.lua)
  export GZ_SYNC_DUMP="$WORK/syncdump"
else
  echo "skipped: no Playwright (pip install playwright; playwright install chromium)"
fi

sec "plugin (mock servers)"
export GZ_TEST_M4A="$REPO/plugins/gzreader.koplugin/audio/test.m4a"
python3 -I "$T/mock_grimmory.py" "$PORT" > "$WORK/mock.log" 2>&1 & echo $! > "$WORK/mock.pid"
sleep 1
(cd "$T" && timeout 900 luajit run_tests.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$WORK/work" "$PORT" "$KOBASE") > "$WORK/out.txt" 2>&1
rc=$?
grep "FAIL" "$WORK/out.txt"
tail -1 "$WORK/out.txt"
[ $rc -eq 0 ] || { fail; tail -30 "$WORK/out.txt"; }

sec "JSON (rapidjson, or LuaJSON)"
(cd "$T" && luajit json_test.lua "$REPO/plugins/gzreader.koplugin" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "memos drawings (the scene in the PNG, read as memos reads it)"
(cd "$T" && luajit drawing_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE" "$WORK/drawings") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
timeout 60 python3 -I "$T/drawing_format_test.py" "$WORK/drawings" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the drawing screen's input (finger; pen only, palm rejection)"
(cd "$T" && luajit sketch_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
sec "handwriting read on the Kindle (Ink Away's own tests, on GZreader's copies: tests/hwr/README.md)"
HWD="$WORK/hwr"; mkdir -p "$HWD/ink/data" "$HWD/tests"
for m in hwr hwrnet hwrwords; do cp "$REPO/plugins/gzreader.koplugin/gzreader_$m.lua" "$HWD/ink/$m.lua"; done
cp "$REPO/plugins/gzreader.koplugin/data/handwriting/"hwr_* "$HWD/ink/data/"
cp "$T/hwr/"*.lua "$HWD/tests/"
(cd "$HWD" && for t in hwrnet hwrwords hwr; do luajit "tests/$t.lua" || echo "FAIL: tests/$t.lua stopped"; done) > "$WORK/hwr.txt" 2>&1
grep -E "FAIL|checks" "$WORK/hwr.txt"
grep -q "FAIL" "$WORK/hwr.txt" && fail
sec "handwriting to text (on the Kindle, Claude, an OpenAI-style service)"
(cd "$T" && luajit handwriting_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
sec "a safety net under every timer (a round's budget, runaway tasks, GZreader's tasks failing alone)"
(cd "$T" && luajit tasksafe_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
sec "pen Kindles: the pen and the touch screen kept apart (KOReader's input.lua)"
(cd "$T" && luajit peninput_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
sec "a two-finger tap without a first event (KOReader's gesture detector)"
(cd "$T" && luajit twofinger_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the Kindle Scribe's pen mode (ink that keeps up with the pen)"
(cd "$T" && luajit penmode_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the display not finishing its updates (logged; pen mode off and a full refresh)"
(cd "$T" && luajit einkwatch_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "saving a note: Saving…, and drafts kept while writing"
(cd "$T" && luajit saving_test.lua "$REPO/plugins/gzreader.koplugin" "$KOBASE" "$WORK/saving") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "mark up a PDF (its pages as drawing pages)"
(cd "$T" && luajit pdfmarkup_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE" "$WORK/pdfmarkup") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings' easter egg (the version tapped seven times: the 15 puzzle)"
(cd "$T" && luajit easteregg_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "notes formatted (Memos' rich editor: reading and writing its Markdown; the formatted page)"
(cd "$T" && luajit blocks_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
(cd "$T" && luajit richedit_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
(cd "$T" && luajit inline_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "emoji (OpenMoji: black as the last fallback, in colour on colour screens)"
(cd "$T" && luajit coloremoji_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "shapes cleaned up: draw and hold (the Newton's way)"
(cd "$T" && luajit shapesnap_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "journal entries (written as the Memos fork's journaling mode writes them)"
(cd "$T" && luajit journal_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the daily paper (feeds read, an edition a day, Home's widget and Settings)"
(cd "$T" && luajit daily_test.lua "$REPO" "$T/lib" "$WORK/daily" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the game board (themed puzzles, words from books, the AI's theme, history, achievements)"
(cd "$T" && luajit gameboard_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "screen rotation (Auto-rotate tile, Home keeps the rotation, notes turn with the screen)"
(cd "$T" && luajit rotation_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings → Downloads → Books: Double-tap only on touch Kindles"
(cd "$T" && luajit settings_doubletap_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the bottom status bar hides on a tap after the setup guide"
(cd "$T" && luajit footer_tap_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "ZenOS setup guide"
(cd "$T" && luajit qs_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings → General → Audio"
(cd "$T" && luajit settings_audio_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings → General → Bluetooth (Kindles with Bluetooth)"
(cd "$T" && luajit settings_bluetooth_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "ZenOS settings (sections)"
(cd "$T" && luajit zen_settings_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings → Reader in groups"
(cd "$T" && luajit settings_reader_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Kindles with Bluetooth: Wi-Fi off keeps Bluetooth on"
(cd "$T" && luajit kindle_bt_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings as GZreader trims it (Advanced, About, KOReader, tabs)"
(cd "$T" && luajit gz_settings_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Settings kept simple (each thing in one place, few taps)"
(cd "$T" && luajit gz_settings_tidy_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Reset GZreader (settings, downloads, accounts; the setup guide)"
(cd "$T" && luajit reset_test.lua "$REPO/plugins/gzreader.koplugin" "$WORK") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Nook screens"
(cd "$T" && luajit nook_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the watchdog (its own process: freezes, waking up)"
(cd "$T" && luajit watchdog_test.lua "$REPO/plugins/gzreader.koplugin" "$WORK") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the shelves' look"
(cd "$T" && luajit shelf_look_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "single sign-on hand-off page (a browser)"
if python3 -c "import playwright" 2>/dev/null; then
  timeout 180 python3 "$T/sso_handoff_test.py" $((PORT + 95)) 2>&1 | grep -E "FAIL|passed|Error"
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail
else
  echo "skipped: no Playwright"
fi

sec "Nook launcher helper"
timeout 120 python3 "$T/nook_launcher_test.py" 2>&1 | grep -E "FAIL|passed|BusyBox"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "settings and book sidecars read as data, not run"
(cd "$T" && luajit dataload_test.lua "$REPO" "$WORK/dataload") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "statistics: book-open lookups after the first page"
(cd "$T" && luajit statistics_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "a book's default font size on big screens (the Scribe)"
(cd "$T" && luajit book_font_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the symbols popup (Sym on the Kindles with a keyboard)"
(cd "$T" && luajit symbols_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "emoji on the on-screen keyboard (the ☺ key's picker)"
(cd "$T" && luajit emoji_keyboard_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "menus and text on big screens (the Scribe)"
(cd "$T" && luajit uiscale_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Downloads: audiobooks and music face out, named under them"
(cd "$T" && luajit shelf_cases_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Download speed log"
(cd "$T" && luajit xferlog_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the updater checks GitHub's certificate (real TLS servers, test certificates)"
(cd "$T" && timeout 120 luajit tls_test.lua "$REPO/plugins/gzreader.koplugin" $((PORT + 90))) 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "release notes from the changelog"
timeout 60 python3 "$T/release_notes_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
sec "Nook: GZreader's files on the card"
timeout 120 python3 "$T/nook_app_test.py" 2>&1 | grep -E "FAIL|passed|shell"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "auto brightness (the light follows the room: Kindles with a light sensor)"
(cd "$T" && luajit autolight_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "Wi-Fi power saving off while downloading"
(cd "$T" && luajit wifips_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "GZreader in a folder of its own: the move from KOReader's folder"
MIGRATE_WORK=$(mktemp -d)
(cd "$T" && luajit migrate_test.lua "$REPO" "$KOBASE" "$MIGRATE_WORK") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail
rm -rf "$MIGRATE_WORK"

sec "beta branch (labelled pull requests combined)"
(timeout 120 python3 "$T/beta_resolve_test.py" && timeout 120 python3 "$T/beta_combine_test.py" && timeout 120 python3 "$T/publish_updates_test.py") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "CI: which changes skip the emulator"
timeout 60 python3 "$T/ci_paths_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "CI: Ubuntu packages from a mirror when Ubuntu's servers can't be reached"
timeout 120 python3 "$T/ci_apt_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "CI's CPU budgets (the emulator perf run)"
timeout 60 python3 "$T/perf_check_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the shelf ornaments stand level"
timeout 60 python3 -I "$T/ornament_level_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the Nook package, from the Kindle 2/3/DX package (GZreader/app or koreader/)"
timeout 120 bash "$T/package_nook_test.sh" "$REPO" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

sec "the wiki's links"
timeout 60 python3 "$T/wiki_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail

echo "== $failed suite(s) failed${failed_names:+: $failed_names}"
exit $failed
