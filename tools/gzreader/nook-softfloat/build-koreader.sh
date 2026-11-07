#!/usr/bin/env bash
# KOReader's Kindle 2/3/DX package (koreader-kindle-legacy-<tag>.zip), built
# from source with the soft-float toolchain (toolchain.sh): the same as the
# official one, without a single VFP instruction, for the Nook 1st Edition.
# GZreader's own packaging then takes it like the official package
# (package-kindle.sh, package-nook.sh).
#
# Usage: tools/gzreader/nook-softfloat/build-koreader.sh <toolchain prefix> <koreader tag> <out dir>
# Runs in KOReader's build image (koreader/kobase): see gzreader-nook.yml.
set -euo pipefail
TC=$(cd "${1:?toolchain prefix}" && pwd)
TAG=${2:?KOReader tag, e.g. v2026.07.1}
OUT=$(mkdir -p "${3:?out dir}" && cd "$3" && pwd)
SRC=${KO_SRC:-$PWD/koreader-src}

export PATH="$TC/arm-kindle-linux-gnueabi/bin:$PATH"
arm-kindle-linux-gnueabi-gcc -v 2>&1 | grep -q -- '--with-float=soft' || { echo "not the soft-float toolchain" >&2; exit 1; }

[ -d "$SRC/.git" ] || git clone -q --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules \
    https://github.com/koreader/koreader.git "$SRC"
cd "$SRC"

# kindle-legacy's compiler flags without the floating-point unit:
#   ARMV6_1136_ARCH:=-march=armv6j -mtune=arm1136jf-s -mfpu=vfp -marm
#   (kindle-legacy) TARGET_CFLAGS+=-mfloat-abi=softfp
python3 - base/Makefile.defs <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
old = "ARMV6_1136_ARCH:=-march=armv6j -mtune=arm1136jf-s -mfpu=vfp -marm"
if old in s:
    s = s.replace(old, "ARMV6_1136_ARCH:=-march=armv6j -mtune=arm1136j-s -marm")
assert "ARMV6_1136_ARCH:=-march=armv6j -mtune=arm1136j-s -marm" in s, "ARMV6_1136_ARCH changed upstream"
blocks = [m.start() for m in re.finditer(r"else ifeq \(\$\(TARGET\), kindle-legacy\)", s)]
assert len(blocks) == 2, "kindle-legacy blocks changed upstream"
i = blocks[1]
j = s.find("TARGET_CFLAGS+=-mfloat-abi=softfp", i)
if j != -1 and j - i < 200:
    s = s[:j] + "TARGET_CFLAGS+=-mfloat-abi=soft" + s[j + len("TARGET_CFLAGS+=-mfloat-abi=softfp"):]
assert "TARGET_CFLAGS+=-mfloat-abi=soft\n" in s[i:i + 200], "kindle-legacy float ABI line moved"
open(p, "w").write(s)
print("Makefile.defs: kindle-legacy without VFP")
PY

# Tesseract (OCR, in k2pdfopt) decides on NEON by whether the compiler
# takes -mfpu=neon; with soft float it does, but its NEON code then compiles
# to nothing and libk2pdfopt is left needing DotProductNEON (so PDFs and the
# statistics plugin don't load). No NEON: as if the check had said no.
python3 - base/thirdparty/tesseract/CMakeLists.txt <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if "-DHAVE_NEON=FALSE" not in s:
    old = "    -DGRAPHICS_DISABLED=TRUE\n"
    assert s.count(old) == 1, "tesseract's CMakeLists changed upstream"
    s = s.replace(old, old + "    -DHAVE_NEON=FALSE\n")
    open(p, "w").write(s)
print("tesseract: no NEON")
PY

make TARGET=kindle-legacy PARALLEL_JOBS="$(nproc)" update-zip
ZIP=$(ls -t koreader-kindle-legacy-*.zip | head -1)
cp "$ZIP" "$OUT/"
echo "$OUT/$(basename "$ZIP")"
