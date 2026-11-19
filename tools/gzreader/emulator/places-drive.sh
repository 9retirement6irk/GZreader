#!/bin/bash
# A drive laid out as before 1.35, for places_tour.lua (GZ_PLACES=moved):
# GZreader in KOReader's place, a book with its saved position, its reading
# history, music in GZreader/.music and a drawing waiting in its settings.
#   places-drive.sh <koreader tree> <drive dir> [kindle|kobo]
# Prints the app's folder on the drive (koreader, or .adds/koreader on a Kobo).
set -e
TREE=$(cd "${1:?koreader tree}" && pwd)
D=${2:?drive dir}
KIND=${3:-kindle}
rm -rf "$D"; mkdir -p "$D"; D=$(cd "$D" && pwd)
APP="$D/koreader"
if [ "$KIND" = kobo ]; then
    APP="$D/.adds/koreader"
    mkdir -p "$D/.adds" "$D/.kobo/Kobo"
    printf '[FeatureSettings]\nFoo=1\n' > "$D/.kobo/Kobo/Kobo eReader.conf"
fi
cp -a "$TREE" "$APP"
rm -f "$APP/settings.reader.lua" "$APP/history.lua" "$APP/settings/history.lua"
mkdir -p "$D/GZreader/Moved Book.sdr" "$D/GZreader/.music/album-1" "$APP/settings/gzreader-drawings"
python3 "$(dirname "$0")/../tests/make_epub.py" "$D/GZreader/Moved Book.epub" > /dev/null
cat > "$D/GZreader/Moved Book.sdr/metadata.epub.lua" <<L
return {
    ["doc_path"] = "$D/GZreader/Moved Book.epub",
    ["last_xpointer"] = "/body/DocFragment[3]",
}
L
head -c 2048 /dev/zero > "$D/GZreader/.music/album-1/01.mp3"
head -c 100 /dev/zero > "$APP/settings/gzreader-drawings/waiting.png"
cat > "$APP/history.lua" <<L
return {
    [1] = {
        ["file"] = "$D/GZreader/Moved Book.epub",
        ["time"] = 1795000000,
    },
}
L
cat > "$APP/settings.reader.lua" <<L
return {
    ["home_dir"] = "$D/GZreader",
}
L
echo "$APP"
