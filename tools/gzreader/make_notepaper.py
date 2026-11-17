#!/usr/bin/env python3
"""The notepaper GZreader's drawing screen offers, as the Kindle Scribe's
notebook templates: ruled (medium, wide, narrow; each also with a margin),
vertical ruled (and with a margin), the planners (daily, weekly, monthly), a
habit tracker, a storyboard and music staves.

Writes, into plugins/gzreader.koplugin/notepaper/:
  <id>.png        the page, 1113 x 1440 (Memos' stored size for a letter
                  page), in colour as the papers made earlier are (blue
                  rules, a red margin line, grey words): shown so on a
                  colour screen and in Memos, grey on the other Kindles;
                  a few colours, small (a palette PNG)
  tiles/<id>.png  the square picture the paper chooser shows: the page's
                  top-left corner, its lines darker so they show small
                  (for every paper, the ones made earlier too)

    python3 tools/gzreader/make_notepaper.py [font.ttf]

The font is for the planners' few words (times, days, numbers): NotoSans
from a KOReader folder, DejaVu Sans otherwise. Run again only to change a
paper: a page drawn on one is known by its picture's bytes, so a changed
file is a new paper to pages already drawn on the old one.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1113, 1440
WHITE = (255, 255, 255)
LINE = (158, 184, 226)    # a ruled line: the blue of the papers made earlier
SOFT = (204, 218, 240)    # the lighter lines (half hours, the lines inside a box)
RED = (214, 125, 125)     # a margin line (as Cornell notes' was)
TEXT = (120, 120, 120)
LEFT, RIGHT, TOP, BOTTOM = 70, W - 70, 150, H - 70
MARGIN_X = 190  # the margin line of a "with margin" paper

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "plugins", "gzreader.koplugin", "notepaper"))
FONTS = [a for a in sys.argv[1:]] + [
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def font(size):
    for path in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def page():
    im = Image.new("RGB", (W, H), WHITE)
    return im, ImageDraw.Draw(im)


def hline(d, y, x0=LEFT, x1=RIGHT, grey=LINE, width=2):
    d.line([(x0, y), (x1, y)], fill=grey, width=width)


def vline(d, x, y0=TOP, y1=BOTTOM, grey=LINE, width=2):
    d.line([(x, y0), (x, y1)], fill=grey, width=width)


def dashed(d, y, x0, x1, grey=SOFT, dash=10, gap=8):
    x = x0
    while x < x1:
        d.line([(x, y), (min(x + dash, x1), y)], fill=grey, width=2)
        x += dash + gap


def ruled(step, margin=False):
    im, d = page()
    y = TOP
    while y <= BOTTOM:
        hline(d, y)
        y += step
    if margin:
        vline(d, MARGIN_X, 60, H - 40, RED)
    return im


def vertical(margin=False):
    im, d = page()
    step = 58
    n = (RIGHT - LEFT) // step
    x0 = LEFT + ((RIGHT - LEFT) - n * step) // 2
    top = TOP if margin else 80
    for i in range(n + 1):
        vline(d, x0 + i * step, top, BOTTOM)
    if margin:
        hline(d, TOP, 40, W - 40, RED)
    return im


def daily():
    im, d = page()
    f = font(22)
    row = 46
    y = 110
    label_w = 110
    hline(d, y)
    hour, half = 7, False
    while y + row <= H - 40:
        d.text((LEFT + 8, y + 10), "%d:%s" % (hour, "30" if half else "00"), font=f, fill=TEXT)
        y += row
        if half:
            hline(d, y)
            hour += 1
        else:
            dashed(d, y, LEFT + label_w, RIGHT)
        half = not half
    vline(d, LEFT + label_w, 110, y)
    return im


def weekly():
    im, d = page()
    f = font(24)
    names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Notes"]
    cols, rows = 2, 4
    gap = 24
    bw = (RIGHT - LEFT - gap) // cols
    bh = (BOTTOM - 100 - gap * (rows - 1)) // rows
    for i, name in enumerate(names):
        c, r = i % cols, i // cols
        x0 = LEFT + c * (bw + gap)
        y0 = 100 + r * (bh + gap)
        d.rectangle([x0, y0, x0 + bw, y0 + bh], outline=LINE, width=2)
        d.text((x0 + 14, y0 + 10), name, font=f, fill=TEXT)
        hline(d, y0 + 50, x0, x0 + bw)
        y = y0 + 50 + 46
        while y < y0 + bh - 10:
            hline(d, y, x0 + 14, x0 + bw - 14, SOFT)
            y += 46
    return im


def monthly():
    im, d = page()
    f = font(22)
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    hline(d, 110, LEFT, LEFT + 420)  # the month's name
    cw = (RIGHT - LEFT) // 7
    x1 = LEFT + cw * 7
    top, head, rh = 150, 44, 150
    for i, name in enumerate(days):
        tw = d.textlength(name, font=f)
        d.text((LEFT + i * cw + (cw - tw) / 2, top + 8), name, font=f, fill=TEXT)
    bottom = top + head + rh * 6
    for i in range(8):
        vline(d, LEFT + i * cw, top, bottom)
    hline(d, top, LEFT, x1)
    for r in range(7):
        hline(d, top + head + r * rh, LEFT, x1)
    y = bottom + 60
    while y <= BOTTOM:
        hline(d, y, LEFT, x1, SOFT)
        y += 46
    return im


def habit():
    im, d = page()
    f = font(20)
    num_w, cols = 60, 7
    top, head = 90, 70
    rh = (H - 50 - top - head) // 31
    cw = (RIGHT - LEFT - num_w) // cols
    x1 = LEFT + num_w + cw * cols
    bottom = top + head + rh * 31
    hline(d, top, LEFT, x1)
    for r in range(32):
        hline(d, top + head + r * rh, LEFT, x1, LINE if r in (0, 31) else SOFT)
    for r in range(31):
        s = str(r + 1)
        tw = d.textlength(s, font=f)
        d.text((LEFT + (num_w - tw) / 2, top + head + r * rh + (rh - 24) / 2), s, font=f, fill=TEXT)
    vline(d, LEFT, top, bottom)
    for c in range(cols + 1):
        vline(d, LEFT + num_w + c * cw, top, bottom)
    return im


def storyboard():
    im, d = page()
    rows = 4
    gap = 36
    bh = (BOTTOM - 90 - gap * (rows - 1)) // rows
    bw = int(bh * 16 / 10)
    for r in range(rows):
        y0 = 90 + r * (bh + gap)
        d.rectangle([LEFT, y0, LEFT + bw, y0 + bh], outline=LINE, width=2)
        y = y0 + 44
        while y <= y0 + bh:
            hline(d, y, LEFT + bw + 30, RIGHT, SOFT if y < y0 + bh else LINE)
            y += 44
    return im


def music():
    im, d = page()
    space, staves = 15, 10
    stave = space * 4
    gap = (BOTTOM - 110 - stave * staves) // (staves - 1)
    for s in range(staves):
        y0 = 110 + s * (stave + gap)
        for i in range(5):
            hline(d, y0 + i * space)
    return im


PAPERS = [
    ("ruled-medium", lambda: ruled(37)),
    ("ruled-medium-margin", lambda: ruled(37, True)),
    ("ruled-wide", lambda: ruled(46)),
    ("ruled-wide-margin", lambda: ruled(46, True)),
    ("ruled-narrow", lambda: ruled(29)),
    ("ruled-narrow-margin", lambda: ruled(29, True)),
    ("vertical", lambda: vertical()),
    ("vertical-margin", lambda: vertical(True)),
    ("daily", daily),
    ("weekly", weekly),
    ("monthly", monthly),
    ("habit", habit),
    ("storyboard", storyboard),
    ("music", music),
]
# the papers made earlier (their files stay as they are): a tile for each
EARLIER = ["college", "wide", "gregg", "dots", "graph", "checklist", "cornell"]

TILE, CROP = 200, 360


def tile(im):
    """The chooser's picture: the page's top-left corner, its lines darker
    (in their colours: a colour screen shows the tiles so too)."""
    t = im.convert("RGB").crop((40, 80, 40 + CROP, 80 + CROP)).resize((TILE, TILE), Image.LANCZOS)
    px = t.load()
    for y in range(TILE):
        for x in range(TILE):
            r, g, b = px[x, y]
            if min(r, g, b) <= 246:
                px[x, y] = (int(r * 0.5), int(g * 0.5), int(b * 0.5))
            else:
                px[x, y] = WHITE
    return t


def save(im, path):
    im.convert("RGB").quantize(24, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def main():
    os.makedirs(os.path.join(OUT, "tiles"), exist_ok=True)
    for name, make in PAPERS:
        im = make()
        save(im, os.path.join(OUT, name + ".png"))
        save(tile(im), os.path.join(OUT, "tiles", name + ".png"))
    for name in EARLIER:
        save(tile(Image.open(os.path.join(OUT, name + ".png"))), os.path.join(OUT, "tiles", name + ".png"))
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            print("%-28s %6d bytes" % (f, os.path.getsize(os.path.join(OUT, f))))


if __name__ == "__main__":
    main()
