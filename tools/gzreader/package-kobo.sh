#!/usr/bin/env bash
# Build GZreader (Grimmory + ZenOS + KOReader) for a Kobo, from KOReader's
# official Kobo package of the same tag (koreader-kobo-vX.zip: every Kobo
# KOReader runs on), as package-kindle.sh does for the Kindles: this branch's
# Lua over the official native binaries, trimmed, precompiled.
#
# Output, in out-dir: gzreader-kobo-<version>.zip, to unzip onto the Kobo's
# drive (its top folder):
#   GZreader/app/                   GZreader, in a folder of its own with the books
#                                   (beside KOReader's .adds/koreader, not in it)
#   .adds/nm/gzreader               NickelMenu: a "GZreader" item in Nickel's menu
#   .adds/kfmon/config/gzreader.ini KFMon: the "GZreader" book starts it…
#   gzreader.png                    …this picture, which Nickel lists as a book
# A Kobo updates itself with the same gzreader-update.zip as the Kindles
# (package-kindle.sh): it holds the Kobo's start script too.
#
# Usage: tools/gzreader/package-kobo.sh <koreader-kobo-vX.zip> [out-dir]
set -euo pipefail

SRC_ZIP=${1:?path to an official koreader-kobo-<version>.zip}
OUT_DIR=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# shellcheck source=tools/gzreader/package-common.sh
. "$REPO/tools/gzreader/package-common.sh"

mkdir -p "$STAGE/src" "$STAGE/out/.adds" "$STAGE/out/GZreader"
unzip -q "$SRC_ZIP" -d "$STAGE/src"
[ -f "$STAGE/src/koreader/koreader.sh" ] && [ -d "$STAGE/src/koreader/frontend" ] \
    || { echo "not a KOReader Kobo package: $SRC_ZIP" >&2; exit 1; }
mv "$STAGE/src/koreader" "$STAGE/out/GZreader/app"
KO="$STAGE/out/GZreader/app"
BASE_REV=$(cat "$KO/git-rev")
if ! git -C "$REPO" merge-base --is-ancestor "$BASE_REV" HEAD 2>/dev/null; then
    echo "warning: this branch is not based on $BASE_REV; frontend Lua may not match the release binaries" >&2
fi

GZ_VERSION=${GZ_VERSION:-$(tr -d ' \n' < "$REPO/GZREADER_VERSION")}

# 1. The branch's frontend, reader.lua, the Kobo's start script and the kept plugins.
gz_overlay "$KO" platform/kobo/koreader.sh
rm -f "$KO/update_once.marker" # (KOReader's own first-start update check: GZreader has its own)

# 2. Launchers: NickelMenu and KFMon (either, or both, may be installed).
mkdir -p "$STAGE/out/.adds/nm" "$STAGE/out/.adds/kfmon/config"
# (plugins/gzreader.koplugin/launchers: the move from .adds/koreader installs them too)
cp "$REPO/plugins/gzreader.koplugin/launchers/kobo/nm/gzreader" "$STAGE/out/.adds/nm/gzreader"
cp "$REPO/plugins/gzreader.koplugin/launchers/kobo/kfmon/gzreader.ini" "$STAGE/out/.adds/kfmon/config/gzreader.ini"
cp "$REPO/platform/kobo/gzreader.png" "$STAGE/out/gzreader.png"

# 3. Bundled English dictionary, trimming (the other e-readers' device code;
#    the Kindle's too) and bytecode (the Kobo's LuaJIT through qemu-arm, or
#    GZ_LUAJIT: the same LuaJIT version gives the same bytecode).
gz_dictionary "$KO"
gz_trim "$KO" android cervantes kindle nook pocketbook remarkable sony-prstux sdl
gz_bytecode "$KO"

echo "${BASE_REV}-gzreader-${GZ_VERSION}" > "$KO/git-rev"
echo "$GZ_VERSION" > "$KO/gzreader-version"

OUT="$OUT_DIR/gzreader-kobo-${GZ_VERSION}.zip"
rm -f "$OUT"
(cd "$STAGE/out" && zip -qr -9 "$OUT" GZreader .adds gzreader.png)
echo "$OUT"
du -h "$OUT"
