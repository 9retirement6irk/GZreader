#!/usr/bin/env python3
"""A small narrated EPUB 3 (media overlays) for the narration checks.

  make_narrated_epub.py <narration.mp3> <out.epub>

Two chapters of four sentences each; each sentence is a <span id> that a
SMIL file ties to three seconds of the MP3 (24 s: chapter 1 the first half,
chapter 2 the second).
The OPF marks the chapters' media-overlay and the total duration, as a
narrated EPUB from BookOrbit (or any EPUB 3 read-along book) does.
"""
import sys, zipfile

mp3, out = sys.argv[1], sys.argv[2]
SENTENCES = [
    ["April is the cruellest month.", "Lilacs grow out of the dead land.",
     "Memory and desire are mixed.", "Dull roots stir with spring rain."],
    ["Winter kept us warm.", "Earth was covered in forgetful snow.",
     "A little life was fed with dried tubers.", "Summer surprised us."],
]


def xhtml(n, sentences):
    spans = " ".join('<span id="c%ds%d">%s</span>' % (n, i + 1, s) for i, s in enumerate(sentences))
    filler = "".join("<p>Some more of the chapter, read without narration, line %d.</p>" % k for k in range(3))
    return ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Chapter %d</title></head><body>'
            '<h1 id="c%dh">Chapter %d</h1><p id="c%dp">%s</p>%s</body></html>' % (n, n, n, n, spans, filler))


def smil(n, count):
    pars = "".join(
        '<par id="p%d"><text src="../text/ch%d.xhtml#c%ds%d"/>'
        '<audio src="../audio/narration.mp3" clipBegin="%s" clipEnd="%s"/></par>'
        % (i + 1, n, n, i + 1, "0:00:%02d.000" % (12 * (n - 1) + 3 * i), "%ds" % (12 * (n - 1) + 3 * (i + 1)))
        for i in range(count))
    return ('<?xml version="1.0" encoding="utf-8"?>\n<smil xmlns="http://www.w3.org/ns/SMIL" '
            'xmlns:epub="http://www.idpf.org/2007/ops" version="3.0"><body>'
            '<seq id="s%d" epub:textref="../text/ch%d.xhtml">%s</seq></body></smil>' % (n, n, pars))


OPF = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">gz-narrated-test</dc:identifier><dc:title>Narrated test</dc:title><dc:language>en</dc:language>
<meta property="dcterms:modified">2026-11-26T00:00:00Z</meta>
<meta property="media:duration" refines="#ch1_overlay">0:00:12</meta>
<meta property="media:duration" refines="#ch2_overlay">0:00:12</meta>
<meta property="media:duration">0:00:24</meta>
<meta property="media:active-class">-epub-media-overlay-active</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml" media-overlay="ch1_overlay"/>
<item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml" media-overlay="ch2_overlay"/>
<item id="ch1_overlay" href="smil/ch1.smil" media-type="application/smil+xml"/>
<item id="ch2_overlay" href="smil/ch2.smil" media-type="application/smil+xml"/>
<item id="audio" href="audio/narration.mp3" media-type="audio/mpeg"/>
</manifest>
<spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
</package>
'''
NAV = ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml" '
       'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body>'
       '<nav epub:type="toc"><ol><li><a href="text/ch1.xhtml">Chapter 1</a></li>'
       '<li><a href="text/ch2.xhtml">Chapter 2</a></li></ol></nav></body></html>')
with zipfile.ZipFile(out, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
    z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" '
               'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
               '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
               '</rootfiles></container>', zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/content.opf", OPF, zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/nav.xhtml", NAV, zipfile.ZIP_DEFLATED)
    for n, sents in enumerate(SENTENCES, 1):
        z.writestr("OEBPS/text/ch%d.xhtml" % n, xhtml(n, sents), zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/smil/ch%d.smil" % n, smil(n, len(sents)), zipfile.ZIP_DEFLATED)
    z.write(mp3, "OEBPS/audio/narration.mp3", zipfile.ZIP_STORED)
