#!/usr/bin/env bash
# GZreader's tests, on a computer (no Kindle needed): the plugin against a
# mock Grimmory / Memos / CalDAV (real LuaSocket, KOReader's UI stubbed),
# ZenOS's setup guide, the Nooks' screen commands; plus luacheck.
#
#   tools/gzreader/tests/run.sh <koreader base dir> [port]
#
# <koreader base dir>: an unzipped official KOReader package's koreader/
# folder (its ffi/ Lua is used; e.g. koreader-kindle-legacy-vX.zip).
# Needs: luajit, lua-socket, luacheck, python3 with radicale (pip), curl. Ports port … port+15.
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

echo "== plugin (mock servers)"
mkdir -p "$WORK/work"
export GZ_TEST_M4A="$REPO/plugins/gzreader.koplugin/audio/test.m4a"
python3 -I "$T/mock_grimmory.py" "$PORT" > "$WORK/mock.log" 2>&1 & echo $! > "$WORK/mock.pid"
sleep 1
(cd "$T" && timeout 900 luajit run_tests.lua "$REPO/plugins/gzreader.koplugin" "$T/lib" "$WORK/work" "$PORT" "$KOBASE") > "$WORK/out.txt" 2>&1
rc=$?
grep "FAIL" "$WORK/out.txt"
tail -1 "$WORK/out.txt"
[ $rc -eq 0 ] || { failed=$((failed + 1)); tail -30 "$WORK/out.txt"; }

echo "== ZenOS setup guide"
(cd "$T" && luajit qs_test.lua "$REPO/plugins/zenos.koplugin" "$REPO/plugins/gzreader.koplugin") 2>&1 | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== Nook screens"
(cd "$T" && luajit nook_test.lua "$REPO" "$KOBASE") 2>&1 | grep -E "FAIL|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed=$((failed + 1))

echo "== $failed suite(s) failed"
exit $failed
