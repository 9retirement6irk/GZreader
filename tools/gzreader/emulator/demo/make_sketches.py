#!/usr/bin/env python3
"""The demo drawings for screenshots: two pages of a hand-drawn shelf plan,
as a drawing made on the Kindle would look (black strokes on white). The
Memos mock (mock_memos.py --drawings) attaches them to its "Shelf sketch"
note when they're here.

  python3 make_sketches.py <PatrickHand-Regular.ttf> <out dir>
writes sketch-front.png and sketch-side.png (600 x 776). Needs Pillow.
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFont

FONT, OUT = sys.argv[1], sys.argv[2]
W, H = 600, 776
random.seed(7)


def wobble(points, amount=1.2):
    """A hand's line: the straight segments split into short wavy ones."""
    out = []
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        n = max(2, int(math.hypot(x2 - x1, y2 - y1) / 12))
        for i in range(n):
            t = i / n
            out.append((x1 + (x2 - x1) * t + random.uniform(-amount, amount),
                        y1 + (y2 - y1) * t + random.uniform(-amount, amount)))
    out.append(points[-1])
    return out


def line(d, pts, width=4):
    d.line(wobble(pts), fill=0, width=width, joint="curve")


def box(d, x, y, w, h, width=4):
    line(d, [(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)], width)


def arrow(d, x1, y1, x2, y2, label, font, vertical=False):
    """A measurement: a thin line with ticks at both ends and its size."""
    line(d, [(x1, y1), (x2, y2)], 2)
    for (x, y) in ((x1, y1), (x2, y2)):
        if vertical:
            line(d, [(x - 8, y), (x + 8, y)], 2)
        else:
            line(d, [(x, y - 8), (x, y + 8)], 2)
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    tw = d.textlength(label, font=font)
    if vertical:
        d.rectangle([mx - tw / 2 - 4, my - 16, mx + tw / 2 + 4, my + 18], fill=255)
        d.text((mx - tw / 2, my - 16), label, font=font, fill=0)
    else:
        d.rectangle([mx - tw / 2 - 4, my - 18, mx + tw / 2 + 4, my + 14], fill=255)
        d.text((mx - tw / 2, my - 18), label, font=font, fill=0)


def front():
    im = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(im)
    big, small = ImageFont.truetype(FONT, 44), ImageFont.truetype(FONT, 28)
    d.text((40, 24), "Shelf for the hall", font=big, fill=0)
    x, y, w, h = 110, 150, 380, 500
    box(d, x, y, w, h, 5)
    for k in (1, 2):                      # two shelves inside
        sy = y + k * h // 3
        line(d, [(x, sy), (x + w, sy)], 5)
    # books on the shelves, and a plant on the middle one
    random.seed(3)
    for row in range(3):
        base = y + (row + 1) * h // 3 - 4
        bx = x + 14
        for _i in range(5 if row != 1 else 3):
            bw, bh = random.randint(22, 34), random.randint(100, 140)
            box(d, bx, base - bh, bw, bh, 3)
            bx += bw + random.randint(2, 6)
    px, pb = x + 270, y + 2 * h // 3 - 4      # the plant's pot and leaves
    line(d, [(px, pb - 50), (px + 60, pb - 50), (px + 50, pb), (px + 10, pb), (px, pb - 50)], 3)
    for a in (-60, -25, 10, 45):
        r = math.radians(a - 90)
        line(d, [(px + 30, pb - 50), (px + 30 + 70 * math.cos(r), pb - 50 + 70 * math.sin(r))], 3)
    arrow(d, x, y + h + 40, x + w, y + h + 40, "36 in", small)
    arrow(d, x - 50, y, x - 50, y + h, "48 in", small, vertical=True)
    d.text((40, 712), "pine, 3/4 in boards", font=small, fill=0)
    return im


def side():
    im = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(im)
    big, small = ImageFont.truetype(FONT, 44), ImageFont.truetype(FONT, 28)
    d.text((40, 24), "Side, and the back", font=big, fill=0)
    x, y, w, h = 220, 150, 150, 500
    box(d, x, y, w, h, 5)
    for k in (1, 2):
        sy = y + k * h // 3
        line(d, [(x, sy), (x + w, sy)], 5)
    arrow(d, x, y + h + 40, x + w, y + h + 40, "11 in", small)
    arrow(d, x + w + 50, y, x + w + 50, y + h // 3, "16 in", small, vertical=True)
    line(d, [(x - 60, y + 60), (x - 8, y + 60)], 3)          # a pointer to the back panel
    line(d, [(x - 22, y + 50), (x - 8, y + 60), (x - 22, y + 70)], 3)
    d.text((40, y + 74), "1/4 in", font=small, fill=0)
    d.text((40, y + 104), "back", font=small, fill=0)
    d.text((40, 712), "2 brackets into studs", font=small, fill=0)
    return im


front().save(OUT + "/sketch-front.png", optimize=True)
side().save(OUT + "/sketch-side.png", optimize=True)
print("wrote", OUT + "/sketch-front.png", OUT + "/sketch-side.png")
