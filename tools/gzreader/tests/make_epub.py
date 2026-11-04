#!/usr/bin/env python3
"""A small EPUB (a few chapters of filler text) for the start-up checks."""
import sys, zipfile

out = sys.argv[1]
chapters = []
for n in range(1, 4):
    paras = "".join(f"<p>Chapter {n}, paragraph {p}. " + "The quick brown fox jumps over the lazy dog. " * 12 + "</p>" for p in range(1, 25))
    chapters.append(f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter {n}</title></head><body><h1>Chapter {n}</h1>{paras}</body></html>')
with zipfile.ZipFile(out, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
    z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    items = "".join(f'<item id="c{n}" href="c{n}.xhtml" media-type="application/xhtml+xml"/>' for n in range(1, 4))
    spine = "".join(f'<itemref idref="c{n}"/>' for n in range(1, 4))
    z.writestr("OEBPS/content.opf", f'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Smoke Test</dc:title><dc:creator>GZreader</dc:creator><dc:identifier id="id">smoke-1</dc:identifier><dc:language>en</dc:language></metadata><manifest>{items}<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx">{spine}</spine></package>')
    navpoints = "".join(f'<navPoint id="n{n}" playOrder="{n}"><navLabel><text>Chapter {n}</text></navLabel><content src="c{n}.xhtml"/></navPoint>' for n in range(1, 4))
    z.writestr("OEBPS/toc.ncx", f'<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="smoke-1"/></head><docTitle><text>Smoke Test</text></docTitle><navMap>{navpoints}</navMap></ncx>')
    for n, c in enumerate(chapters, 1):
        z.writestr(f"OEBPS/c{n}.xhtml", c)
