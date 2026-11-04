#!/usr/bin/env bash
# A tree to run GZreader in the emulator (run.sh): an official KOReader
# Kindle 2/3/DX package's native binaries with this branch's Lua on top (as
# package-kindle.sh does, without the trimming and bytecode).
#   tools/gzreader/emulator/make-tree.sh <koreader-kindle-legacy-vX.zip> <out dir>
# GZ_EMU_TREE=<out dir>/koreader for run.sh.
set -euo pipefail
ZIP=${1:?koreader-kindle-legacy-vX.zip}
OUT=$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
rm -rf "$OUT/koreader"
unzip -q "$ZIP" 'koreader/*' -d "$OUT"
KO="$OUT/koreader"
rsync -a --delete "$REPO/frontend/" "$KO/frontend/"
cp "$REPO/reader.lua" "$KO/reader.lua"
cp "$REPO/platform/kindle/koreader.sh" "$KO/koreader.sh"
rm -rf "$KO/plugins"
mkdir -p "$KO/plugins"
for p in autosuspend coverbrowser gzreader statistics zenos; do cp -r "$REPO/plugins/$p.koplugin" "$KO/plugins/"; done
echo "$KO"
