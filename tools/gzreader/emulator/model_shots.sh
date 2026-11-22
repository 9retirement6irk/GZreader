#!/bin/bash
# The landing page's screenshots, model by model (docs/index.html's model
# picker): emulator/model_shots.lua on each model against the demo servers,
# the pictures scaled to at most 900 px wide and written to
# docs/screenshots/models/<model>/<shot>.png, with what was taken in
# docs/screenshots/models/<model>/shots.txt.
#
#   tools/gzreader/emulator/model_shots.sh <tree>/koreader <library dir> [out] [models…]
#
# <tree>: from make-tree.sh; <library dir>: from demo/make_library.py (its
# books, audio.json and covers). Models (default all): k3 dx k4 kt pw3 scribe
# libra condor nook nst. Needs Python with Pillow. The test suite's mock
# Grimmory uses port 18080 too: don't run this beside tests/run.sh.
set -u
TREE=${1:?tree (make-tree.sh)}
LIB=${2:?demo library (demo/make_library.py)}
OUT=${3:-/tmp/gz-model-shots}
shift 3 2>/dev/null || shift $#
MODELS=${*:-k3 dx k4 kt pw3 scribe libra condor nook nst}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
DEST="$REPO/docs/screenshots/models"
TESTS="$REPO/tools/gzreader/tests"
mkdir -p "$OUT" "$DEST"
LIB=$(cd "$LIB" && pwd)

PIDS=()
stop() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap stop EXIT
python3 -I "$HERE/demo/demo_grimmory.py" "$TESTS/mock_grimmory.py" "$LIB" 18080 > "$OUT/grimmory.log" 2>&1 & PIDS+=($!)
python3 -I "$HERE/demo/demo_plex.py" "$TESTS/mock_plex.py" "$LIB" 18090 > "$OUT/plex.log" 2>&1 & PIDS+=($!)
python3 -I "$HERE/demo/mock_memos.py" 18091 --sample > "$OUT/memos.log" 2>&1 & PIDS+=($!)
sleep 3

failed=0
for model in $MODELS; do
    echo "== $model"
    rm -rf "$OUT/nook-home" /mnt/onboard/GZreader && mkdir -p "$OUT/nook-home"
    # (the Scribe's 1860 × 2480 screen is slow under qemu)
    t=500; [ "$model" = scribe ] && t=1200
    GZ_NOOK_HOME="$OUT/nook-home" GZ_SHOTS_LIB="$LIB" GZ_EMU_TREE="$TREE" GZ_EMU_MODEL=$model EMU_TIMEOUT=$t \
        bash "$HERE/run.sh" "$HERE/model_shots.lua" "$OUT/$model" > /dev/null 2>&1
    if [ ! -s "$OUT/$model/shots.txt" ]; then
        echo "   didn't finish (see $OUT/$model.txt)"; failed=$((failed + 1)); continue
    fi
    rm -rf "${DEST:?}/$model" && mkdir -p "$DEST/$model"
    python3 - "$OUT/$model" "$DEST/$model" <<'EOF'
import os, sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
names = [n.strip() for n in open(os.path.join(src, "shots.txt")) if n.strip()]
kept = []
for n in names:
    p = os.path.join(src, n + ".png")
    if not os.path.exists(p):
        continue
    im = Image.open(p)
    im = im.convert("L") if im.mode not in ("L", "RGB") else im
    if im.width > 900:
        im = im.resize((900, round(im.height * 900 / im.width)), Image.LANCZOS)
    im.save(os.path.join(dst, n + ".png"), optimize=True)
    kept.append("%s %dx%d" % (n, im.width, im.height))
open(os.path.join(dst, "shots.txt"), "w").write("\n".join(kept) + "\n")
print("   " + ", ".join(k.split()[0] for k in kept))
EOF
done
echo "$failed model(s) didn't finish"
[ "$failed" = 0 ]
