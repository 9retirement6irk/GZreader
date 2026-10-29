#!/usr/bin/env bash
# Build the trimmed "KOReader + ZenOS + Grimmory" package for legacy Kindles
# (Kindle 2, DX, Kindle Keyboard / K3).
#
# The branch only changes Lua (frontend + plugins), so instead of rebuilding
# the native toolchain we overlay this branch onto the official
# kindle-legacy release built from the same tag, then strip what a
# read-and-sync device doesn't need.
#
# Usage: tools/grimmory/package-kindle-legacy.sh <koreader-kindle-legacy-vX.zip> [out-dir]
set -euo pipefail

SRC_ZIP=${1:?path to official koreader-kindle-legacy-<version>.zip}
OUT_DIR=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

KEEP_PLUGINS="autosuspend coverbrowser grimmory statistics zenos"

unzip -q "$SRC_ZIP" -d "$STAGE"
KO="$STAGE/koreader"
BASE_REV=$(cat "$KO/git-rev")
if ! git -C "$REPO" merge-base --is-ancestor "$BASE_REV" HEAD 2>/dev/null; then
    echo "warning: this branch is not based on $BASE_REV; frontend Lua may not match the release binaries" >&2
fi

# 1. Frontend: take the branch's Lua (menu order, Kindle OTA off).
rsync -a --delete "$REPO/frontend/" "$KO/frontend/"

# 2. Plugins: only the keep-list, from the branch.
rm -rf "$KO/plugins"
mkdir -p "$KO/plugins"
for p in $KEEP_PLUGINS; do
    cp -r "$REPO/plugins/$p.koplugin" "$KO/plugins/"
done
# ZenOS ships an updater; drop its non-English catalogs to save space.
find "$KO/plugins/zenos.koplugin/locales" -name '*.po' ! -name 'en.po' -delete

# 3. Launchers: KUAL menu and launchpad shortcuts say "Grimmory".
cp "$REPO/platform/kindle/extensions/koreader/menu.json" \
   "$REPO/platform/kindle/extensions/koreader/config.xml" "$STAGE/extensions/koreader/"
cp "$REPO/platform/kindle/launchpad/koreader.ini" "$STAGE/launchpad/"

# 4. Bundled English dictionary: Open English WordNet (CC BY 4.0) as StarDict.
OEWN_XML=${OEWN_XML:-"$REPO/tools/grimmory/cache/english-wordnet-2025.xml.gz"}
if [ ! -f "$OEWN_XML" ]; then
    mkdir -p "$(dirname "$OEWN_XML")"
    curl -fsSL -o "$OEWN_XML" \
        https://github.com/globalwordnet/english-wordnet/releases/download/2025-edition/english-wordnet-2025.xml.gz
fi
DICT="$KO/data/dict/oewn"
mkdir -p "$DICT"
python3 -I "$REPO/tools/grimmory/build-wordnet-stardict.py" "$OEWN_XML" "$DICT"
if command -v dictzip >/dev/null; then dictzip "$DICT/oewn.dict"; fi
cat > "$DICT/README.txt" <<'TXT'
Open English WordNet 2025 (https://en-word.net,
https://github.com/globalwordnet/english-wordnet), licensed under
Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/).
Converted to StarDict format (definitions, examples, synonyms and word forms)
for the Grimmory KOReader build by tools/grimmory/build-wordnet-stardict.py.
TXT

# 5. Remove what a reading + sync device doesn't use.
rm -rf "$KO/ota" "$KO/zsync2" "$KO/spinning_zsync"        # OTA (disabled; would restore stock KOReader)
rm -f  "$KO/dropbear" "$KO/scp" "$KO/sftp-server"        # SSH server
rm -f  "$KO"/fonts/noto/NotoSansCJK*                      # 16 MB CJK fallback font
find "$KO/l10n" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +   # UI translations (English UI)

echo "${BASE_REV}-grimmory" > "$KO/git-rev"

OUT="$OUT_DIR/koreader-grimmory-kindle-legacy-${BASE_REV}.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr -9 "$OUT" koreader extensions launchpad)
echo "$OUT"
du -h "$OUT"
