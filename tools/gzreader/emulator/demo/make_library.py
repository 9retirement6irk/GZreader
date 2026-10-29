#!/usr/bin/env python3
"""Build a small demo library for README screenshots: public-domain books
(Project Gutenberg texts from NLTK's corpus) as EPUBs with plain typographic
covers.

  make_library.py <gutenberg txt dir> <fonts dir> <out dir>

Writes <out>/<id>.epub, <out>/<id>.jpg and <out>/library.json.
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
