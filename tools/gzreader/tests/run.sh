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
# (the calendar tests' expected times are New York's, around its clock change)
export TZ=America/New_York

echo "== luacheck"
(cd "$REPO" && luacheck -q plugins/gzreader.koplugin plugins/zenos.koplugin tools/gzreader/emulator frontend/device/nook frontend/device.lua) || failed=$((failed + 1))

echo "== GZreader's changes to upstream files kept"
python3 "$T/keeps.py" || failed=$((failed + 1))

echo "== the sync page (a browser, mock servers)"
mkdir -p "$WORK/work" "$WORK/syncdump"
if python3 -c "import playwright" 2>/dev/null; then
  (cd "$T" && timeout 300 python3 sync_page_test.py $((PORT + 40)) "$WORK/syncdump") > "$WORK/page.txt" 2>&1
  rc=$?
  grep "FAIL" "$WORK/page.txt"
  tail -1 "$WORK/page.txt"
  [ $rc -eq 0 ] || { failed=$((failed + 1)); tail -30 "$WORK/page.txt"; }
  # (the Kindle side takes in what the page left: run_tests.lua)
  export GZ_SYNC_DUMP="$WORK/syncdump"
else
  echo "skipped: no Playwright (pip install playwright; playwright install chromium)"
fi

echo "== plugin (mock servers)"
export GZ_TEST_M4A="$REPO/plugins/gzreader.koplugin/audio/test.m4a"
python3 -I "$T/mock_grimmory.py" "$PORT" > "$WORK/mock.log" 2>&1 & echo $! > "$WORK/mock.pid"
sleep 1
(cd "$T" && timeout 900 luajit run_tests.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$WORK/work" "$PORT" "$KOBASE") > "$WORK/out.txt" 2>&1
rc=$?
grep "FAIL" "$WORK/out.txt"
tail -1 "$WORK/out.txt"
[ $rc -eq 0 ] || { failed=$((failed + 1)); tail -30 "$WORK/out.txt"; }

echo "== JSON (rapidjson, or LuaJSON)"
(cd "$T" && luajit json_test.lua "$REPO/plugins/gzreader.koplugin" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== memos drawings (the scene in the PNG, read as memos reads it)"
(cd "$T" && luajit drawing_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE" "$WORK/drawings") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
timeout 60 python3 -I "$T/drawing_format_test.py" "$WORK/drawings" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the drawing screen's input (finger; pen only, palm rejection)"
(cd "$T" && luajit sketch_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
echo "== pen Kindles: the pen and the touch screen kept apart (KOReader's input.lua)"
(cd "$T" && luajit peninput_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
echo "== a two-finger tap without a first event (KOReader's gesture detector)"
(cd "$T" && luajit twofinger_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the Kindle Scribe's pen mode (ink that keeps up with the pen)"
(cd "$T" && luajit penmode_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== saving a note: Saving…, and drafts kept while writing"
(cd "$T" && luajit saving_test.lua "$REPO/plugins/gzreader.koplugin" "$KOBASE" "$WORK/saving") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== mark up a PDF (its pages as drawing pages)"
(cd "$T" && luajit pdfmarkup_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$KOBASE" "$WORK/pdfmarkup") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== notes formatted (Memos' rich editor: reading and writing its Markdown; the formatted page)"
(cd "$T" && luajit blocks_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
(cd "$T" && luajit richedit_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
(cd "$T" && luajit inline_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== journal entries (written as the Memos fork's journaling mode writes them)"
(cd "$T" && luajit journal_test.lua "$REPO/plugins/gzreader.koplugin" "$T/lib") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the daily paper (feeds read, an edition a day, Home's widget and Settings)"
(cd "$T" && luajit daily_test.lua "$REPO" "$T/lib" "$WORK/daily") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== screen rotation (Auto-rotate tile, Home keeps the rotation, notes turn with the screen)"
(cd "$T" && luajit rotation_test.lua "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings → Downloads → Books: Double-tap only on touch Kindles"
(cd "$T" && luajit settings_doubletap_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the bottom status bar hides on a tap after the setup guide"
(cd "$T" && luajit footer_tap_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== ZenOS setup guide"
(cd "$T" && luajit qs_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings → General → Audio"
(cd "$T" && luajit settings_audio_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings → General → Bluetooth (Kindles with Bluetooth)"
(cd "$T" && luajit settings_bluetooth_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== ZenOS settings (sections)"
(cd "$T" && luajit zen_settings_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings → Reader in groups"
(cd "$T" && luajit settings_reader_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Kindles with Bluetooth: Wi-Fi off keeps Bluetooth on"
(cd "$T" && luajit kindle_bt_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings as GZreader trims it (Advanced, About, KOReader, tabs)"
(cd "$T" && luajit gz_settings_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Reset GZreader (settings, downloads, accounts; the setup guide)"
(cd "$T" && luajit reset_test.lua "$REPO/plugins/gzreader.koplugin" "$WORK") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Nook screens"
(cd "$T" && luajit nook_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the watchdog (its own process: freezes, waking up)"
(cd "$T" && luajit watchdog_test.lua "$REPO/plugins/gzreader.koplugin" "$WORK") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the shelves' look"
(cd "$T" && luajit shelf_look_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== single sign-on hand-off page (a browser)"
if python3 -c "import playwright" 2>/dev/null; then
  timeout 180 python3 "$T/sso_handoff_test.py" $((PORT + 95)) 2>&1 | grep -E "FAIL|passed|Error"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
else
  echo "skipped: no Playwright"
fi

echo "== Nook launcher helper"
timeout 120 python3 "$T/nook_launcher_test.py" 2>&1 | grep -E "FAIL|passed|BusyBox"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== settings and book sidecars read as data, not run"
(cd "$T" && luajit dataload_test.lua "$REPO" "$WORK/dataload") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== statistics: book-open lookups after the first page"
(cd "$T" && luajit statistics_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== a book's default font size on big screens (the Scribe)"
(cd "$T" && luajit book_font_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the symbols popup (Sym on the Kindles with a keyboard)"
(cd "$T" && luajit symbols_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== menus and text on big screens (the Scribe)"
(cd "$T" && luajit uiscale_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Downloads: audiobooks and music face out, named under them"
(cd "$T" && luajit shelf_cases_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Download speed log"
(cd "$T" && luajit xferlog_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the updater checks GitHub's certificate (real TLS servers, test certificates)"
(cd "$T" && timeout 120 luajit tls_test.lua "$REPO/plugins/gzreader.koplugin" $((PORT + 90))) 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== release notes from the changelog"
timeout 60 python3 "$T/release_notes_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
echo "== Nook: GZreader's files on the card"
timeout 120 python3 "$T/nook_app_test.py" 2>&1 | grep -E "FAIL|passed|shell"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Wi-Fi power saving off while downloading"
(cd "$T" && luajit wifips_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== beta branch (labelled pull requests combined)"
(timeout 120 python3 "$T/beta_resolve_test.py" && timeout 120 python3 "$T/beta_combine_test.py" && timeout 120 python3 "$T/publish_updates_test.py") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== CI: which changes skip the emulator"
timeout 60 python3 "$T/ci_paths_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== CI: Ubuntu packages from a mirror when Ubuntu's servers can't be reached"
timeout 120 python3 "$T/ci_apt_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== CI's CPU budgets (the emulator perf run)"
timeout 60 python3 "$T/perf_check_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the shelf ornaments stand level"
timeout 60 python3 -I "$T/ornament_level_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the wiki's links"
timeout 60 python3 "$T/wiki_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== $failed suite(s) failed"
exit $failed
