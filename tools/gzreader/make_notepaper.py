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

    python3 tools/gzreader/make_notepaper.py [font.ttf] [--force]

Only papers that aren't there yet are written (--force: all of them again).

The font is for the planners' few words (times, days, numbers): NotoSans
from a KOReader folder, DejaVu Sans otherwise. The `*-plain.png` files are the margin papers as they
were before they had holes: kept as they are, for pages drawn on them. Run again only to change a
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
FONTS = [a for a in sys.argv[1:] if not a.startswith("--")] + [
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


HOLE_X, HOLE_R, HOLES_Y = 95, 19, (163, 719, 1277)  # as College ruled's were
HOLE_FILL, HOLE_EDGE = (236, 236, 236), (218, 218, 218)


def holes(d):
    """The three punched holes of notebook paper, down the left edge."""
    for y in HOLES_Y:
        d.ellipse([HOLE_X - HOLE_R, y - HOLE_R, HOLE_X + HOLE_R, y + HOLE_R], fill=HOLE_FILL, outline=HOLE_EDGE, width=2)


def ruled(step, margin=False):
    """Ruled paper; with a margin it's notebook paper: its lines from edge to
    edge, a red margin line, and three punched holes (the owner, 2026-11-17:
    the holes went when the Scribe's templates came)."""
    im, d = page()
    y = TOP
    while y <= BOTTOM:
        if margin:
            hline(d, y, 0, W)
        else:
            hline(d, y)
        y += step
    if margin:
        vline(d, MARGIN_X, 0, H, RED)
        holes(d)
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


# ---- the rest of the Scribe's templates (the owner, 2026-11-24)

YELLOW = (250, 242, 178)       # a legal pad's page
YELLOW_BAND = (236, 224, 140)  # its binding at the top
TEAL = (168, 214, 214)         # the planners' and meeting notes' bands
GREEN = (196, 222, 170)
PURPLE = (200, 190, 228)
DOT = (150, 150, 150)
BOX = (140, 140, 140)


def legal():
    """A legal pad: yellow, blue rules from edge to edge, a double red margin
    line, the binding's band across the top."""
    im = Image.new("RGB", (W, H), YELLOW)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 86], fill=YELLOW_BAND)
    y = TOP
    while y <= H - 30:
        hline(d, y, 0, W)
        y += 37
    vline(d, MARGIN_X - 6, 86, H, RED)
    vline(d, MARGIN_X, 86, H, RED)
    return im


def ruled_part(top):
    """Medium ruled on the top or the bottom half; the other half blank."""
    im, d = page()
    y0, y1 = (TOP, H // 2) if top else (H // 2 + 20, BOTTOM)
    y = y0
    while y <= y1:
        hline(d, y)
        y += 37
    return im


def graph_large():
    im, d = page()
    step = 74
    nx, ny = (RIGHT - LEFT) // step, (BOTTOM - 80) // step
    x0 = LEFT + ((RIGHT - LEFT) - nx * step) // 2
    y0 = 80 + ((BOTTOM - 80) - ny * step) // 2
    for i in range(nx + 1):
        vline(d, x0 + i * step, y0, y0 + ny * step)
    for j in range(ny + 1):
        hline(d, y0 + j * step, x0, x0 + nx * step)
    return im


def dots_part(top):
    """Dotted on the top or the bottom half."""
    im, d = page()
    step = 37
    y0, y1 = (110, H // 2) if top else (H // 2 + 20, BOTTOM)
    y = y0
    while y <= y1:
        x = LEFT
        while x <= RIGHT:
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=DOT)
            x += step
        y += step
    return im


def checklist_small():
    """A checklist with small boxes and narrow lines."""
    im, d = page()
    step, box = 37, 20
    y = 110 + step
    while y <= BOTTOM:
        d.rectangle([LEFT, y - box - 6, LEFT + box, y - 6], outline=BOX, width=2)
        hline(d, y, LEFT + box + 16, RIGHT)
        y += step
    return im


def two_column():
    im, d = page()
    gap = 50
    mid = (LEFT + RIGHT) // 2
    y = TOP
    while y <= BOTTOM:
        hline(d, y, LEFT, mid - gap // 2)
        hline(d, y, mid + gap // 2, RIGHT)
        y += 37
    return im


def weekly2():
    """A week as seven columns under a teal band with the days' names."""
    im, d = page()
    f = font(22)
    top, band = 90, 70
    d.rectangle([LEFT, top, RIGHT, top + band], fill=TEAL)
    col = (RIGHT - LEFT) / 7.0
    for i, day in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]):
        x = int(LEFT + i * col)
        d.text((x + 10, top + 22), day, font=f, fill=TEXT)
        if i:
            vline(d, x, top, BOTTOM)
    d.rectangle([LEFT, top, RIGHT, BOTTOM], outline=LINE, width=2)
    hline(d, top + band)
    return im


def meeting():
    """Meeting notes: a teal band for the title, a green one for the date and
    who's there, ruled lines for the notes, then a purple band and a
    checklist for what's to be done."""
    im, d = page()
    f = font(22)
    y = 90
    d.rectangle([LEFT, y, RIGHT, y + 64], fill=TEAL)
    d.text((LEFT + 12, y + 18), "Meeting", font=f, fill=TEXT)
    y += 64
    d.rectangle([LEFT, y, RIGHT, y + 46], fill=GREEN)
    d.text((LEFT + 12, y + 10), "Date", font=f, fill=TEXT)
    d.text(((LEFT + RIGHT) // 2 + 12, y + 10), "Attendees", font=f, fill=TEXT)
    y += 46
    notes_end = 980
    y += 37
    while y <= notes_end:
        hline(d, y)
        y += 37
    d.rectangle([LEFT, y, RIGHT, y + 46], fill=PURPLE)
    d.text((LEFT + 12, y + 10), "Action items", font=f, fill=TEXT)
    y += 46 + 37
    box = 20
    while y <= BOTTOM:
        d.rectangle([LEFT + 8, y - box - 6, LEFT + 8 + box, y - 6], outline=BOX, width=2)
        hline(d, y, LEFT + box + 24, RIGHT)
        y += 37
    d.rectangle([LEFT, 90, RIGHT, y - 37], outline=LINE, width=2)
    return im


PAPERS = [
    ("legal", legal),
    ("ruled-medium-top", lambda: ruled_part(True)),
    ("ruled-medium-bottom", lambda: ruled_part(False)),
    ("graph-large", graph_large),
    ("dots-top", lambda: dots_part(True)),
    ("dots-bottom", lambda: dots_part(False)),
    ("checklist-small", checklist_small),
    ("two-column", two_column),
    ("weekly-2", weekly2),
    ("meeting", meeting),
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


# where a tile is cut from, for the papers whose top-left corner doesn't show what they are
TILE_AT = {
    "ruled-medium-top": (40, H // 2 - 250), "ruled-medium-bottom": (40, H // 2 - 110),
    "dots-top": (40, H // 2 - 250), "dots-bottom": (40, H // 2 - 110),
    "two-column": ((LEFT + RIGHT) // 2 - CROP // 2, 80), "legal": (40, 0), "meeting": (40, 900),
}
FILLS = (YELLOW, YELLOW_BAND, TEAL, GREEN, PURPLE)


def near(c, fills, by=14):
    return any(abs(c[0] - f[0]) + abs(c[1] - f[1]) + abs(c[2] - f[2]) <= by for f in fills)


def tile(im, punched=False, at=(40, 80)):
    """The chooser's picture: a corner of the page (its top-left one unless
    TILE_AT says), its lines darker (in their colours: a colour screen shows
    the tiles so too); a page's or a band's own colour stays as it is."""
    t = im.convert("RGB").crop((at[0], at[1], at[0] + CROP, at[1] + CROP)).resize((TILE, TILE), Image.LANCZOS)
    px = t.load()
    for y in range(TILE):
        for x in range(TILE):
            r, g, b = px[x, y]
            if near((r, g, b), FILLS):
                pass
            elif punched and abs(r - g) < 4 and abs(g - b) < 4 and r >= 230:
                pass  # (a punched hole's pale fill: as it is, not a dark blot)
            elif min(r, g, b) <= 246:
                px[x, y] = (int(r * 0.5), int(g * 0.5), int(b * 0.5))
            else:
                px[x, y] = WHITE
    return t


def save(im, path):
    im.convert("RGB").quantize(24, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def main():
    os.makedirs(os.path.join(OUT, "tiles"), exist_ok=True)
    force = "--force" in sys.argv
    for name, make in PAPERS:
        # (a paper that's there stays as it is: pages drawn on it know it by its bytes)
        if os.path.exists(os.path.join(OUT, name + ".png")) and not force:
            continue
        im = make()
        save(im, os.path.join(OUT, name + ".png"))
        save(tile(im, name.endswith("-margin") and name.startswith("ruled-"), TILE_AT.get(name, (40, 80))), os.path.join(OUT, "tiles", name + ".png"))
    for name in EARLIER:
        if os.path.exists(os.path.join(OUT, "tiles", name + ".png")) and not force:
            continue
        save(tile(Image.open(os.path.join(OUT, name + ".png"))), os.path.join(OUT, "tiles", name + ".png"))
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            print("%-28s %6d bytes" % (f, os.path.getsize(os.path.join(OUT, f))))


if __name__ == "__main__":
    main()
