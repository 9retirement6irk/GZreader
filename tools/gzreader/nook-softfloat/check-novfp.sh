#!/usr/bin/env bash
# No floating-point unit needed: every ARM program and library in a folder
# (a koreader-kindle-legacy zip unpacked, or the Nook package) is checked
# for the ELF attributes a VFP build carries (Tag_FP_arch, VFP argument
# passing, NEON). A soft-float build has none of them.
#   tools/gzreader/nook-softfloat/check-novfp.sh <dir>
set -uo pipefail
DIR=${1:?dir}
READELF=${READELF:-readelf}
bad=0; n=0
while IFS= read -r -d '' f; do
    [ "$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
    "$READELF" -h "$f" 2>/dev/null | grep -q 'Machine:.*ARM' || continue
    n=$((n + 1))
    attrs=$("$READELF" -A "$f" 2>/dev/null | grep -E 'Tag_FP_arch|Tag_ABI_VFP_args: VFP registers|Tag_Advanced_SIMD_arch')
    if [ -n "$attrs" ]; then
        echo "VFP: ${f#"$DIR"/}: $(echo "$attrs" | tr -s ' ' | tr '\n' ';')"
        bad=$((bad + 1))
    fi
done < <(find "$DIR" -type f -print0)
echo "$n ARM files checked, $bad built for a floating-point unit"
[ "$n" -gt 0 ] && [ "$bad" -eq 0 ]
