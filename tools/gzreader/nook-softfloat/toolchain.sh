#!/usr/bin/env bash
# The cross-compiler for GZreader on the Nook 1st Edition: KOReader's Kindle
# 2/3/DX toolchain (koxtoolchain's "kindle": crosstool-NG, glibc 2.9, Linux
# 2.6.27 headers, the triple arm-kindle-linux-gnueabi KOReader's build looks
# for) with one change: no floating-point unit. The Nook's kernel doesn't
# enable VFP (its /proc/cpuinfo has no "vfp"), so every VFP instruction
# stops a program with SIGILL (exit code 132); here gcc, glibc and
# libstdc++ do floating point in software (-mfloat-abi=soft).
#
# Usage: tools/gzreader/nook-softfloat/toolchain.sh <prefix dir>
#   -> <prefix dir>/arm-kindle-linux-gnueabi/bin/arm-kindle-linux-gnueabi-gcc
# Needs crosstool-NG's build tools (see .github/workflows/gzreader-nook.yml);
# not as root (crosstool-NG refuses).
set -euo pipefail
PREFIX=$(mkdir -p "${1:?prefix dir}" && cd "$1" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
CTNG_REPO=${CTNG_REPO:-https://github.com/benoit-pierre/crosstool-ng.git}
CTNG_REV=${CTNG_REV:-34844bc8e985ad1ba26b072a5b58264967072e19} # koxtoolchain's
WORK=${CTNG_WORK:-$(mktemp -d)}
mkdir -p "$WORK"

cd "$WORK"
[ -d CT-NG ] || git clone -q "$CTNG_REPO" CT-NG
cd CT-NG
git checkout -q "$CTNG_REV"
# the Kindle 2/3/DX sample, without the floating-point unit
cp "$HERE/crosstool.config" samples/arm-kindle-linux-gnueabi/crosstool.config
./bootstrap
./configure --prefix="$WORK/ct-ng"
make -j"$(nproc)"
make install
export PATH="$WORK/ct-ng/bin:$PATH"

mkdir -p "$WORK/build" && cd "$WORK/build"
ct-ng distclean
unset CFLAGS CXXFLAGS LDFLAGS
ct-ng arm-kindle-linux-gnueabi
yes "" | ct-ng oldconfig > /dev/null
ct-ng upgradeconfig
sed -i 's/^CT_LOG_PROGRESS_BAR=y/CT_LOG_PROGRESS_BAR=n/' .config
grep -q '^CT_ARCH_FLOAT_SW=y' .config || { echo "not a soft-float configuration" >&2; exit 1; }
# (koxtoolchain: keeps libstdc++ from needing utimensat@GLIBC_2.6)
export glibcxx_cv_utimensat=no
CT_PREFIX="$PREFIX" nice ct-ng build
GCC="$PREFIX/arm-kindle-linux-gnueabi/bin/arm-kindle-linux-gnueabi-gcc"
"$GCC" -v 2>&1 | grep -E -- '--with-float=soft' > /dev/null || { echo "the compiler isn't soft-float" >&2; exit 1; }
echo "$GCC"
