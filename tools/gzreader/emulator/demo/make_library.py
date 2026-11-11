#!/usr/bin/env python3
"""Build a small demo library for README screenshots: public-domain books
(Project Gutenberg texts from NLTK's corpus) as EPUBs with plain typographic
covers.

  make_library.py <gutenberg txt dir> <fonts dir> <out dir>

Writes <out>/<id>.epub, <out>/<id>.jpg and <out>/library.json; and for the
Catalog's other pages, made-up audiobooks (square covers <out>/a<id>.jpg,
audio from the test suite's tone) and Plex albums (<out>/plex-<key>.jpg) in
<out>/audio.json, read by demo_grimmory.py and demo_plex.py.
"""
import json, os, re, sys, zipfile, io
from PIL import Image, ImageDraw, ImageFont

SRC, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)

BOOKS = [
    # id, file, title, author, series, number, library, cover tone
    (1, "carroll-alice.txt", "Alice's Adventures in Wonderland", "Lewis Carroll", None, None, "Classics", 70),
    (2, "melville-moby_dick.txt", "Moby Dick", "Herman Melville", None, None, "Classics", 40),
    (3, "austen-emma.txt", "Emma", "Jane Austen", None, None, "Classics", 110),
    (4, "austen-persuasion.txt", "Persuasion", "Jane Austen", None, None, "Classics", 150),
    (5, "austen-sense.txt", "Sense and Sensibility", "Jane Austen", None, None, "Classics", 90),
    (6, "chesterton-brown.txt", "The Innocence of Father Brown", "G. K. Chesterton", "Father Brown", 1, "Mystery", 55),
    (7, "chesterton-thursday.txt", "The Man Who Was Thursday", "G. K. Chesterton", None, None, "Mystery", 30),
    (8, "chesterton-ball.txt", "The Ball and the Cross", "G. K. Chesterton", None, None, "Mystery", 125),
    (9, "bryant-stories.txt", "Stories to Tell to Children", "Sara Cone Bryant", None, None, "Children", 170),
    (10, "burgess-busterbrown.txt", "The Adventures of Buster Bear", "Thornton W. Burgess", None, None, "Children", 140),
    (11, "edgeworth-parents.txt", "The Parent's Assistant", "Maria Edgeworth", None, None, "Children", 100),
    (12, "shakespeare-hamlet.txt", "Hamlet", "William Shakespeare", None, None, "Plays", 20),
    (13, "shakespeare-macbeth.txt", "Macbeth", "William Shakespeare", None, None, "Plays", 60),
    (14, "shakespeare-caesar.txt", "Julius Caesar", "William Shakespeare", None, None, "Plays", 95),
    (15, "whitman-leaves.txt", "Leaves of Grass", "Walt Whitman", None, None, "Poetry", 135),
    (16, "blake-poems.txt", "Poems", "William Blake", None, None, "Poetry", 160),
]

# id, title, author, narrator, chapters, cover tone, in progress (%)
AUDIOBOOKS = [
    (101, "Pride and Prejudice", "Jane Austen", "Ruth Harlow", 6, 200, 42.0),
    (102, "Treasure Island", "Robert Louis Stevenson", "Tom Ashby", 5, 45, None),
    (103, "The Wind in the Willows", "Kenneth Grahame", "Clara Penn", 5, 160, 12.0),
    (104, "The Time Machine", "H. G. Wells", "Owen Marsh", 4, 25, None),
    (105, "Little Women", "Louisa May Alcott", "Ruth Harlow", 6, 130, None),
    (106, "The Hound of the Baskervilles", "Arthur Conan Doyle", "Owen Marsh", 5, 70, None),
]
# Plex albums by made-up artists: key, title, artist, year, tracks, cover tone, pattern
ALBUMS = [
    ("501", "Night Trains", "The Lantern Club", 2019, ["Platform Nine", "Sleeper Car", "Signal Box", "Last Stop"], 30, "rings"),
    ("502", "Paper Boats", "Mira Holt", 2021, ["Paper Boats", "Rainwater", "Harbour Lights"], 190, "waves"),
    ("503", "Nocturnes", "Elena Varga", 2016, ["No. 1 in B-flat minor", "No. 2 in E-flat", "No. 3 in B"], 60, "bars"),
    ("504", "Low Tide", "The Gullwings", 2022, ["Low Tide", "Sandbar", "Saltwater Radio", "Gulls"], 150, "waves"),
    ("505", "Morning Pages", "Ada Finch", 2020, ["Coffee First", "Morning Pages", "Window Seat"], 220, "sun"),
    ("506", "The Four Seasons", "Riverside Chamber Players", 2015, ["Spring", "Summer", "Autumn", "Winter"], 100, "bars"),
    ("507", "Old Roads", "The Hollow Pines", 2018, ["Old Roads", "Pinewood", "County Line"], 80, "rings"),
    ("508", "City at Dusk", "Northbound", 2023, ["Overpass", "Neon", "City at Dusk", "Home Late"], 15, "grid"),
]


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def wrap(draw, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def cover(title, author, tone):
    W, H = 600, 900
    im = Image.new("L", (W, H), tone)
    d = ImageDraw.Draw(im)
    ink = 255 if tone < 120 else 15
    d.rectangle([28, 28, W - 28, H - 28], outline=ink, width=3)
    d.rectangle([40, 40, W - 40, H - 40], outline=ink, width=1)
    tf = font("NotoSerif-Bold.ttf", 64 if len(title) < 20 else 52)
    y = 190
    for line in wrap(d, title, tf, W - 140):
        w = d.textlength(line, font=tf)
        d.text(((W - w) / 2, y), line, fill=ink, font=tf)
        y += tf.size + 14
    d.line([W / 2 - 60, y + 30, W / 2 + 60, y + 30], fill=ink, width=2)
    af = font("NotoSerif-Italic.ttf", 36)
    w = d.textlength(author, font=af)
    d.text(((W - w) / 2, H - 170), author, fill=ink, font=af)
    buf = io.BytesIO()
    im.convert("RGB").save(buf, "JPEG", quality=88)
    return buf.getvalue()


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def chapters(text):
    text = re.sub(r"^\[.*?\]\s*", "", text, flags=re.S)
    parts = re.split(r"\n(?=(?:CHAPTER|Chapter|BOOK|ACT|STORY)\b[^\n]*\n)", text)
    out = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        head, _, body = p.partition("\n")
        if len(head) > 80:
            head, body = "Opening", p
        out.append((head.strip(), body))
        if len(out) >= 8:
            break
    return out


def epub(book_id, title, author, text, jpg):
    chs = chapters(text)
    z = io.BytesIO()
    with zipfile.ZipFile(z, "w") as e:
        e.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        e.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        e.writestr("OEBPS/cover.jpg", jpg, compress_type=zipfile.ZIP_DEFLATED)
        man, spine, nav = [], [], []
        e.writestr("OEBPS/cover.xhtml", '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head><body><div><img src="cover.jpg" alt="Cover" style="height:100%"/></div></body></html>')
        man.append('<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>')
        man.append('<item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>')
        spine.append('<itemref idref="cover"/>')
        for i, (head, body) in enumerate(chs, 1):
            paras = "".join("<p>%s</p>" % esc(" ".join(p.split())) for p in re.split(r"\n\s*\n", body) if p.strip())
            e.writestr("OEBPS/c%d.xhtml" % i, '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>%s</title></head><body><h2>%s</h2>%s</body></html>' % (esc(head), esc(head), paras), compress_type=zipfile.ZIP_DEFLATED)
            man.append('<item id="c%d" href="c%d.xhtml" media-type="application/xhtml+xml"/>' % (i, i))
            spine.append('<itemref idref="c%d"/>' % i)
            nav.append('<li><a href="c%d.xhtml">%s</a></li>' % (i, esc(head)))
        e.writestr("OEBPS/nav.xhtml", '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>%s</ol></nav></body></html>' % "".join(nav))
        man.append('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')
        e.writestr("OEBPS/content.opf", '<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">gzreader-demo-%d</dc:identifier><dc:title>%s</dc:title><dc:creator>%s</dc:creator><dc:language>en</dc:language><meta name="cover" content="cover-image"/><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest>%s</manifest><spine>%s</spine></package>' % (book_id, esc(title), esc(author), "".join(man), "".join(spine)))
    return z.getvalue()


lib = []
for bid, fname, title, author, series, num, library, tone in BOOKS:
    text = open(os.path.join(SRC, fname), encoding="latin-1").read()
    jpg = cover(title, author, tone)
    data = epub(bid, title, author, text, jpg)
    open(os.path.join(OUT, "%d.epub" % bid), "wb").write(data)
    small = Image.open(io.BytesIO(jpg)).resize((250, 375))
    buf = io.BytesIO()
    small.save(buf, "JPEG", quality=85)
    open(os.path.join(OUT, "%d.jpg" % bid), "wb").write(buf.getvalue())
    lib.append({"id": bid, "title": title, "author": author, "series": series, "number": num,
                "library": library, "size": len(data)})
json.dump(lib, open(os.path.join(OUT, "library.json"), "w"), indent=1)
print(len(lib), "books in", OUT)


def square(title, by, tone, pattern=None):
    """A square cover: an audiobook's (title and author in a frame) or an
    album's (a pattern, title and artist under it)."""
    S = 600
    im = Image.new("L", (S, S), tone)
    d = ImageDraw.Draw(im)
    ink = 255 if tone < 120 else 15
    if pattern is None:
        d.rectangle([30, 30, S - 30, S - 30], outline=ink, width=3)
        d.arc([S / 2 - 49, 70, S / 2 + 49, 168], 180, 360, fill=ink, width=6)   # headphones
        d.rectangle([S / 2 - 58, 120, S / 2 - 40, 170], fill=ink)
        d.rectangle([S / 2 + 40, 120, S / 2 + 58, 170], fill=ink)
        tf = font("NotoSerif-Bold.ttf", 56 if len(title) < 18 else 46)
        y = 210
    else:
        mid = 230
        if pattern == "rings":
            for r in range(40, 200, 26):
                d.ellipse([S / 2 - r, mid - r, S / 2 + r, mid + r], outline=ink, width=5)
        elif pattern == "waves":
            for k in range(7):
                yy = 80 + k * 42
                d.arc([20, yy, 300, yy + 60], 200, 340, fill=ink, width=6)
                d.arc([300, yy, 580, yy + 60], 200, 340, fill=ink, width=6)
        elif pattern == "bars":
            for k in range(11):
                h = 60 + (k * 53) % 230
                d.rectangle([60 + k * 44, 390 - h, 88 + k * 44, 390], fill=ink)
        elif pattern == "sun":
            d.ellipse([S / 2 - 90, mid - 90, S / 2 + 90, mid + 90], fill=ink)
            for k in range(16):
                import math
                a = k * math.pi / 8
                d.line([S / 2 + 115 * math.cos(a), mid + 115 * math.sin(a), S / 2 + 170 * math.cos(a), mid + 170 * math.sin(a)], fill=ink, width=8)
        elif pattern == "grid":
            for k in range(9):
                for j in range(6):
                    if (k * 7 + j * 3) % 5:
                        d.rectangle([70 + k * 52, 80 + j * 52, 104 + k * 52, 114 + j * 52], fill=ink)
        tf = font("NotoSerif-Bold.ttf", 44)
        y = 420
    for line in wrap(d, title, tf, S - 100):
        w = d.textlength(line, font=tf)
        d.text(((S - w) / 2, y), line, fill=ink, font=tf)
        y += tf.size + 10
    af = font("NotoSerif-Italic.ttf", 32)
    w = d.textlength(by, font=af)
    d.text(((S - w) / 2, S - 90), by, fill=ink, font=af)
    small = im.convert("RGB").resize((300, 300))
    buf = io.BytesIO()
    small.save(buf, "JPEG", quality=85)
    return buf.getvalue()


audio = {"audiobooks": [], "albums": []}
for bid, title, author, narrator, chapters_n, tone, progress in AUDIOBOOKS:
    open(os.path.join(OUT, "a%d.jpg" % bid), "wb").write(square(title, author, tone))
    audio["audiobooks"].append({"id": bid, "title": title, "author": author, "narrator": narrator,
                                "chapters": chapters_n, "progress": progress})
for key, title, artist, year, tracks, tone, pattern in ALBUMS:
    open(os.path.join(OUT, "plex-%s.jpg" % key), "wb").write(square(title, artist, tone, pattern))
    audio["albums"].append({"key": key, "title": title, "artist": artist, "year": year, "tracks": tracks})
json.dump(audio, open(os.path.join(OUT, "audio.json"), "w"), indent=1)
print(len(audio["audiobooks"]), "audiobooks and", len(audio["albums"]), "albums in", OUT)
