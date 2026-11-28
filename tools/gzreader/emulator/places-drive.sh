#!/bin/bash
# A drive with GZreader installed in its own folder (GZreader/app, beside where
# KOReader would be), for places_tour.lua. A Kobo's drive also has Nickel's
# settings file, which GZreader adds its folders to.
#   places-drive.sh <koreader tree> <drive dir> [kindle|kobo]
# Prints the app's folder on the drive (<drive>/GZreader/app).
set -e
TREE=$(cd "${1:?koreader tree}" && pwd)
D=${2:?drive dir}
KIND=${3:-kindle}
rm -rf "$D"; mkdir -p "$D/GZreader"; D=$(cd "$D" && pwd)
APP="$D/GZreader/app"
if [ "$KIND" = kobo ]; then
    mkdir -p "$D/.adds" "$D/.kobo/Kobo"
    printf '[FeatureSettings]\nFoo=1\n' > "$D/.kobo/Kobo/Kobo eReader.conf"
fi
cp -a "$TREE" "$APP"
rm -f "$APP/settings.reader.lua" "$APP/history.lua" "$APP/settings/history.lua"
echo "$APP"
