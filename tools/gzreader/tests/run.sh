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
# Needs: luajit, lua-socket, luacheck, python3 with radicale (pip), curl;
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

echo "== ZenOS setup guide"
(cd "$T" && luajit qs_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== ZenOS settings (sections)"
(cd "$T" && luajit zen_settings_test.lua "$REPO/plugins/zenos.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Settings as GZreader trims it (Advanced, About, KOReader, tabs)"
(cd "$T" && luajit gz_settings_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Nook screens"
(cd "$T" && luajit nook_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the shelves' look"
(cd "$T" && luajit shelf_look_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Nook launcher helper"
timeout 120 python3 "$T/nook_launcher_test.py" 2>&1 | grep -E "FAIL|passed|BusyBox"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== statistics: book-open lookups after the first page"
(cd "$T" && luajit statistics_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the symbols popup (Sym on the Kindles with a keyboard)"
(cd "$T" && luajit symbols_test.lua "$REPO") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== release notes from the changelog"
timeout 60 python3 "$T/release_notes_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))
echo "== Nook: GZreader's files on the card"
timeout 120 python3 "$T/nook_app_test.py" 2>&1 | grep -E "FAIL|passed|shell"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== beta branch (labelled pull requests combined)"
(timeout 120 python3 "$T/beta_resolve_test.py" && timeout 120 python3 "$T/beta_combine_test.py" && timeout 120 python3 "$T/publish_updates_test.py") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== CI: which changes skip the emulator"
timeout 60 python3 "$T/ci_paths_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== CI's CPU budgets (the emulator perf run)"
timeout 60 python3 "$T/perf_check_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== the wiki's links"
timeout 60 python3 "$T/wiki_test.py" 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== $failed suite(s) failed"
exit $failed
