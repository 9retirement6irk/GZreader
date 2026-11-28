# Steps shared by GZreader's packages (sourced by package-kindle.sh and
# package-kobo.sh): the branch's Lua over an official KOReader package's
# koreader/ folder, the dictionary, trimming and bytecode.
# Each function takes the koreader/ folder ($KO) and uses $REPO.

GZ_KEEP_PLUGINS="autosuspend coverbrowser gzreader statistics zenos"

# The branch's frontend, reader.lua and the kept plugins (from the branch).
# $2: the device's start script in the repository (platform/<device>/koreader.sh).
gz_overlay() {
    local KO=$1 START=$2
    rsync -a --delete "$REPO/frontend/" "$KO/frontend/"
    cp "$REPO/reader.lua" "$KO/reader.lua"
    cp "$REPO/$START" "$KO/koreader.sh"
    rm -rf "$KO/plugins"
    mkdir -p "$KO/plugins"
    local p
    for p in $GZ_KEEP_PLUGINS; do
        cp -r "$REPO/plugins/$p.koplugin" "$KO/plugins/"
    done
    # ZenOS ships an updater; drop its non-English catalogs to save space.
    find "$KO/plugins/zenos.koplugin/locales" -name '*.po' ! -name 'en.po' -delete
}

# Bundled English dictionary: Open English WordNet (CC BY 4.0) as StarDict.
gz_dictionary() {
    local KO=$1
    local OEWN_XML=${OEWN_XML:-"$REPO/tools/gzreader/cache/english-wordnet-2025.xml.gz"}
    if [ ! -f "$OEWN_XML" ]; then
        mkdir -p "$(dirname "$OEWN_XML")"
        curl -fsSL -o "$OEWN_XML" \
            https://github.com/globalwordnet/english-wordnet/releases/download/2025-edition/english-wordnet-2025.xml.gz
    fi
    local DICT="$KO/data/dict/oewn"
    mkdir -p "$DICT"
    python3 -I "$REPO/tools/gzreader/build-wordnet-stardict.py" "$OEWN_XML" "$DICT"
    if command -v dictzip >/dev/null; then dictzip "$DICT/oewn.dict"; fi
    cat > "$DICT/README.txt" <<'TXT'
Open English WordNet 2025 (https://en-word.net,
https://github.com/globalwordnet/english-wordnet), licensed under
Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/).
Converted to StarDict format (definitions, examples, synonyms and word forms)
for the Grimmory KOReader build by tools/gzreader/build-wordnet-stardict.py.
TXT
}

# ZenOS's OPDS patch (the OPDS plugin isn't in the package), its own updater
# (gz_updater.lua stands in), its Controls settings page (the quick panel
# replaced it) and its bug reporter (Report a problem is GZreader's).
GZ_UNUSED_ZENOS="modules/global/patches/opds_browser.lua modules/settings/zen_updater.lua modules/settings/sections/menu_settings.lua modules/settings/zen_bugreporter.lua"

# Remove what a reading + sync device doesn't use. $2…: the other e-readers'
# device code to remove (frontend/device.lua only loads one of these after
# detecting that device).
gz_trim() {
    local KO=$1
    shift
    rm -rf "$KO/ota" "$KO/zsync2" "$KO/spinning_zsync"        # OTA (disabled; would restore stock KOReader)
    rm -f  "$KO/dropbear" "$KO/scp" "$KO/sftp-server"        # SSH server
    rm -f  "$KO"/fonts/noto/NotoSansCJK*                      # 16 MB CJK fallback font
    find "$KO/l10n" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +   # UI translations (English UI)
    local d
    for d in "$@"; do
        rm -rf "$KO/frontend/device/$d"
    done
    # ZenOS files GZreader never loads (kept in the repo as upstream has them,
    # so merges stay clean): about 6,000 lines, 250 KB. package_trim_test.py
    # fails if anything starts to load one of them.
    local f
    for f in $GZ_UNUSED_ZENOS; do
        rm -f "$KO/plugins/zenos.koplugin/$f"
    done
}

# Precompile Lua to LuaJIT bytecode with the device's own LuaJIT (run
# through qemu-arm), keeping the .lua names and debug info (line numbers,
# upvalue names, source paths relative to the koreader folder, exactly as
# when loading source). Loading bytecode skips parsing: ~4-15x faster per
# file, about a second or more off every start on a Kindle 3.
# Skipped (with a warning) when that LuaJIT can't be run here.
# GZ_LUAJIT: the command to use instead (a LuaJIT of the same version, e.g.
# another package's under qemu: the bytecode is the same).
gz_bytecode() {
    local KO=$1
    local LJ_RUN="${GZ_LUAJIT:-}" root
    if [ -n "$LJ_RUN" ] || [ "${GZ_BYTECODE:-1}" != "1" ]; then
        :
    elif "$KO/luajit" -v >/dev/null 2>&1; then
        LJ_RUN="$KO/luajit"
    elif command -v qemu-arm-static >/dev/null; then
        for root in "${QEMU_LD_PREFIX:-}" /usr/arm-linux-gnueabihf /usr/arm-linux-gnueabi; do
            if [ -n "$root" ] && qemu-arm-static -L "$root" "$KO/luajit" -v >/dev/null 2>&1; then
                LJ_RUN="qemu-arm-static -L $root $KO/luajit"
                break
            fi
        done
    fi
    if [ -n "$LJ_RUN" ] && [ "${GZ_BYTECODE:-1}" = "1" ]; then
        local n=0 f
        while IFS= read -r f; do
            # keep plain source where people may look or edit
            case "$f" in */_meta.lua|defaults.lua|setupkoenv.lua) continue ;; esac
            # shellcheck disable=SC2086
            if (cd "$KO" && LUA_PATH="$KO/?.lua;;" $LJ_RUN -b -g "$f" "$f.bc" 2>/dev/null) && [ -s "$KO/$f.bc" ]; then
                mv "$KO/$f.bc" "$KO/$f"
                n=$((n + 1))
            else
                rm -f "$KO/$f.bc"
                echo "warning: kept source for $f (bytecode failed)" >&2
            fi
        done < <(cd "$KO" && find frontend plugins common -name '*.lua')
        echo "precompiled $n Lua files to bytecode"
    else
        echo "warning: the device's LuaJIT can't run here (install qemu-user-static and libc6-armel-cross / libc6-armhf-cross); shipping Lua source" >&2
    fi
}
