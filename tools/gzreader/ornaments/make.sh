#!/bin/bash
# The shelves' ornaments: the drawings here (SVG, with gradients for their
# shading) made into the pictures GZreader ships
# (plugins/gzreader.koplugin/icons/shelf/ornament-*.png: greys with
# transparency). The Kindle's own SVG renderer draws gradients far too dark,
# so they're rendered here. Needs rsvg-convert and python3 with Pillow.
#   tools/gzreader/ornaments/make.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/../../../plugins/gzreader.koplugin/icons/shelf"
for f in "$HERE"/ornament-*.svg; do
    n=$(basename "$f" .svg)
    rsvg-convert -h 320 "$f" -o "/tmp/$n.rgba.png"
    python3 -I - "/tmp/$n.rgba.png" "$OUT/$n.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
la = Image.merge("LA", (im.convert("L"), im.split()[3]))
la.save(sys.argv[2], optimize=True)
PY
    rm -f "/tmp/$n.rgba.png"
done
ls -la "$OUT"/ornament-*.png
