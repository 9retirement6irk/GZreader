#!/usr/bin/env python3
"""Small EPUBs for the emulator checks.

  make_epub.py <out.epub>             a few chapters of text
  make_epub.py --pictures <out.epub>  a "picture book": every page a scanned
                                       picture (385 x 625 PNG), no text
  make_epub.py --big <out.epub>       30 chapters of text (~430 KB: big
                                       enough for crengine to keep a layout cache)
"""
import struct, sys, zipfile, zlib


def png(w, h, seed):
    """A grey picture with a few bands (stdlib only)."""
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        band = ((y // 40) + seed) % 2
        for x in range(w):
            rows.append(0xF0 if band else (0x30 + (x * 0x90 // w)))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


pictures = sys.argv[1] == "--pictures"
big = sys.argv[1] == "--big"
out = sys.argv[-1]
n_ch = 6 if pictures else (30 if big else 3)
title = "Picture Book" if pictures else ("Big Book" if big else "Smoke Test")
with zipfile.ZipFile(out, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
    z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    items, spine, nav = [], [], []
    for n in range(1, n_ch + 1):
        if pictures:
            body = f'<div><img src="p{n}.png" alt=""/></div>'
            z.writestr(f"OEBPS/p{n}.png", png(385, 625, n))
            items.append(f'<item id="i{n}" href="p{n}.png" media-type="image/png"/>')
        else:
            body = f"<h1>Chapter {n}</h1>" + "".join(
                f"<p>Chapter {n}, paragraph {p}. " + "The quick brown fox jumps over the lazy dog. " * 12 + "</p>" for p in range(1, 25))
        z.writestr(f"OEBPS/c{n}.xhtml", f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page {n}</title></head><body>{body}</body></html>')
        items.append(f'<item id="c{n}" href="c{n}.xhtml" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="c{n}"/>')
        nav.append(f'<navPoint id="n{n}" playOrder="{n}"><navLabel><text>Page {n}</text></navLabel><content src="c{n}.xhtml"/></navPoint>')
    z.writestr("OEBPS/content.opf", f'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>{title}</dc:title><dc:creator>GZreader</dc:creator><dc:identifier id="id">{title.lower().replace(" ", "-")}-1</dc:identifier><dc:language>en</dc:language></metadata><manifest>{"".join(items)}<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx">{"".join(spine)}</spine></package>')
    z.writestr("OEBPS/toc.ncx", f'<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="x"/></head><docTitle><text>{title}</text></docTitle><navMap>{"".join(nav)}</navMap></ncx>')
