#!/usr/bin/env bash
# Build GZreader (Grimmory + ZenOS + KOReader) for a Kindle, from one of
# KOReader's official Kindle packages of the same tag:
#   koreader-kindle-legacy-vX.zip  Kindle 2, DX, Kindle Keyboard (K3)
#   koreader-kindle-vX.zip         Kindle 4 and Kindle Touch
#   koreader-kindlehf-vX.zip       touch Kindles on firmware 5.16.3 or newer
#                                  (Paperwhite 3 / 7th gen and later)
#   koreader-kindlepw2-vX.zip      touch Kindles on firmware 5.6.1 – 5.16.2
#
# Outputs, in out-dir:
#   gzreader-<platform>-<version>.zip   full install: GZreader/app (GZreader in a folder
#                                       of its own, beside KOReader), extensions/gzreader
#                                       (KUAL)[, launchpad/gzreader.ini][, documents/
#                                       GZreader.sh: firmware 5]; KOReader's own
#                                       koreader/, extensions/koreader and
#                                       launchpad/koreader.ini aren't in it
#   gzreader-update.zip                 what the in-app updater installs: Lua
#                                       only, the same for every Kindle (the
#                                       packages share one LuaJIT version, so
#                                       one bytecode), attach one of them
#
# The branch only changes Lua (frontend + plugins), so instead of rebuilding
# the native toolchain we overlay this branch onto the official release
# built from the same tag, then strip what a read-and-sync device doesn't
# need.
#
# Usage: tools/gzreader/package-kindle.sh <koreader-<platform>-vX.zip> [out-dir]
set -euo pipefail

SRC_ZIP=${1:?path to an official koreader-<kindle platform>-<version>.zip}
PLATFORM=$(basename "$SRC_ZIP" | sed -n 's/^koreader-\(kindle[a-z0-9-]*\)-v.*\.zip$/\1/p')
PLATFORM=${PLATFORM:-kindle-legacy}
OUT_DIR=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# shellcheck source=tools/gzreader/package-common.sh
. "$REPO/tools/gzreader/package-common.sh"
KEEP_PLUGINS=$GZ_KEEP_PLUGINS

unzip -q "$SRC_ZIP" -d "$STAGE"
KO="$STAGE/koreader"
BASE_REV=$(cat "$KO/git-rev")
if ! git -C "$REPO" merge-base --is-ancestor "$BASE_REV" HEAD 2>/dev/null; then
    echo "warning: this branch is not based on $BASE_REV; frontend Lua may not match the release binaries" >&2
fi

GZ_VERSION=${GZ_VERSION:-$(tr -d ' \n' < "$REPO/GZREADER_VERSION")}

# 1. Frontend and startup Lua: the branch's (menu order, OTA off, branding,
#    keyboard, read aloud, sleep screen…). 2. Plugins: only the keep-list.
gz_overlay "$KO" platform/kindle/koreader.sh

# 3. Launchers: GZreader's own (KUAL's extensions/gzreader, the launchpad's
#    gzreader.ini), to GZreader/app, beside KOReader's (plugins/gzreader.koplugin/
#    launchers: the move from koreader/ installs them too, gzreader_migrate.lua).
LAUNCH="$REPO/plugins/gzreader.koplugin/launchers/kindle"
rm -rf "$STAGE/extensions/koreader"
mkdir -p "$STAGE/extensions"
cp -r "$LAUNCH/extensions/gzreader" "$STAGE/extensions/gzreader"
chmod 755 "$STAGE/extensions/gzreader/bin/start.sh"
# (launchpad: the Kindle 2/3/DX's own launcher; firmware 5 has only KUAL)
if [ -d "$STAGE/launchpad" ]; then rm -f "$STAGE/launchpad/koreader.ini"; cp "$LAUNCH/launchpad/gzreader.ini" "$STAGE/launchpad/"; fi
# Touch Kindles (Kindle Touch, Paperwhite and newer): the "GZreader" item on
# the Kindle's own home screen (a scriptlet: documents/GZreader.sh, ZenOS's
# kindle-launcher), there from the start instead of after GZreader's first
# start (ZenOS still installs or updates it then: common/kindle_launcher.lua).
if [ "$PLATFORM" != "kindle-legacy" ]; then
    mkdir -p "$STAGE/documents"
    cp "$REPO/plugins/zenos.koplugin/kindle-launcher/GZreader.sh" "$STAGE/documents/GZreader.sh"
    chmod 755 "$STAGE/documents/GZreader.sh"
fi

# 4. Bundled English dictionary: Open English WordNet (CC BY 4.0) as StarDict.
gz_dictionary "$KO"

# 5. Remove what a reading + sync device doesn't use, and other e-readers'
#    device code. The Kobo's stays: the update package (below, the same for
#    every device) replaces the whole frontend folder on a Kobo too.
gz_trim "$KO" android cervantes pocketbook remarkable sony-prstux sdl

# 6. Precompile Lua to LuaJIT bytecode with the Kindle's own LuaJIT (run
#    through qemu-arm): package-common.sh.
gz_bytecode "$KO"

echo "${BASE_REV}-gzreader-${GZ_VERSION}" > "$KO/git-rev"
echo "$GZ_VERSION" > "$KO/gzreader-version"

OUT="$OUT_DIR/gzreader-${PLATFORM}-${GZ_VERSION}.zip"
rm -f "$OUT"
# (GZreader/app: the program, in the GZreader folder with the books: gzreader_places.lua)
mkdir -p "$STAGE/full/GZreader"
cp -a "$KO" "$STAGE/full/GZreader/app"
for d in extensions launchpad documents; do [ -d "$STAGE/$d" ] && cp -a "$STAGE/$d" "$STAGE/full/"; done
(cd "$STAGE/full" && zip -qr -9 "$OUT" GZreader extensions $( [ -d launchpad ] && echo launchpad ) $( [ -d documents ] && echo documents ))
echo "$OUT"
du -h "$OUT"

# Update package: only what the updater may replace (see gzreader_update.lua).
# The Nooks and Kobos install it too (the Lua is the same); the Nook's start
# script comes along as koreader/nook-gzreader.sh, the icon's helper as
# koreader/nook-launcher.sh (only a Nook installs them), the Kobo's start
# script as koreader/kobo-koreader.sh (a Kobo installs it as koreader.sh).
cp "$REPO/platform/nook/gzreader.sh" "$KO/nook-gzreader.sh"
cp "$REPO/platform/kobo/koreader.sh" "$KO/kobo-koreader.sh"
# (and the Nook icon's helper, once the repository has it)
NOOK_EXTRA=
if [ -f "$REPO/platform/nook/launcher.sh" ]; then cp "$REPO/platform/nook/launcher.sh" "$KO/nook-launcher.sh"; NOOK_EXTRA=koreader/nook-launcher.sh; fi
UPD="$OUT_DIR/gzreader-update.zip"
rm -f "$UPD"
(cd "$STAGE" && zip -qr -9 "$UPD" koreader/frontend koreader/reader.lua koreader/koreader.sh koreader/nook-gzreader.sh $NOOK_EXTRA koreader/kobo-koreader.sh \
    koreader/gzreader-version koreader/git-rev $(for p in $KEEP_PLUGINS; do echo "koreader/plugins/$p.koplugin"; done))
echo "$UPD"
du -h "$UPD"
