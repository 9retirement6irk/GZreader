#!/bin/sh
# Builds gzdecode. Usage: build.sh <zig target> <out>   e.g. arm-linux-musleabihf gzdecode-armhf
set -e
D=$(cd "$(dirname "$0")" && pwd)
ZIG=${ZIG:-"python3 -m ziglang"}
FAAD_VERSION=$(sed -n 's/.*"PACKAGE_VERSION": *"\(.*\)".*/\1/p' "$D/faad2/properties.json")
$ZIG cc -target "$1" ${CPU:+-mcpu=$CPU} -Os -static -s -ffunction-sections -fdata-sections -Wl,--gc-sections \
  -DHAVE_INTTYPES_H=1 -DHAVE_MEMCPY=1 -DHAVE_STRING_H=1 -DHAVE_STRINGS_H=1 \
  -DHAVE_SYS_STAT_H=1 -DHAVE_SYS_TYPES_H=1 -DHAVE_LRINTF=1 -DPACKAGE_VERSION="\"$FAAD_VERSION\"" \
  -DGZ_FAAD_VERSION="\"$FAAD_VERSION\"" \
  -I"$D/faad2/include" -I"$D/faad2/libfaad" -I"$D/minimp3" \
  "$D/gzdecode.c" "$D"/faad2/libfaad/*.c -lm -o "$2"
