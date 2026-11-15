Books whose pages are pictures (scanned pages, comics as EPUB) are fitted to the screen.

EPUBs whose chapter files are pictures with next to no text (scanned pages,
e.g. Diary of a Wimpy Kid: 385 x 625 JPEG per page) are recognized on
opening (`gzreader_picturebook.lua`: sampled spine files, ≥ 70 % pictures-only;
a book in fewer than 6 files, such as one big file between a cover and a
contents page, is cut into 12 parts and the middle 10 are sampled instead).
An EPUB converted from a PDF, whose pages are pictures with the text as
separate lines between them, isn't one: fitting its pictures can't put the
text back on the page.
GZreader then adds a book style tweak (`img { height: 100%; width: auto;
max-width: 100% }`, no margins/padding), sets the book's page margins to 0
and turns on smooth image scaling, keeping the old settings for when it's
turned off (the quick panel → Fit pictures, in a book). Checked with the
Kindle's own crengine.

`100%` is the page area between the top and bottom margins (ZenOS adds its
title-bar height to the top margin), so pictures stay clear of the title bar
and footer. 1.0.28 used `100vh`, the whole screen: pages ran under the clock
and the footer (crengine also split them, adding blank pages), and a wide
picture capped at the screen width was stretched to full height. With `100%`
crengine keeps each picture's shape. The scans are only ~385 x 625, so
they're enlarged about 1.3x to fill 800 pixels; that's why they look softer
than real text. Smooth scaling makes them much less jagged.

Before fitting a book, GZreader measures its pictures once, in the
background, to find the wide ones (a publisher's logo) and keep them at
their own size; books recognized before their first open had this done
then. Only one book is measured at a time: a second picture book opened (or
**Fit pictures** tapped in it) while the first one is still being measured
is fitted right after it. Until 2026-11-09's fix it was left as it was, and
Fit pictures seemed to do nothing. When fitting has to wait for the
measuring, a note says the pages will be fitted in a moment.

**Fixed-layout EPUBs made from a PDF** (`rendition:layout` pre-paginated:
each page is one picture of the printed page with an invisible text layer
positioned over it, and the page's own size, e.g. 1359 x 2008 px, set on it)
are picture books too. KOReader's EPUB engine can't position that text
layer over the picture, so it laid it out after it: every page was followed
by a blank one, and Fit pictures left the pages at the left of the screen,
cut off on the right. Since the 2026-11-15 fix the invisible layer (a style
that is positioned absolutely and whose text is transparent) is hidden while
the pictures are fitted, its text doesn't count when the book is recognized
(so such a book is fitted by itself when it opens), and each page's own
width is dropped so the picture is centred and fills the screen. A book
fitted before the fix is fitted again once when it opens. The invisible text
can't be searched or selected while the pictures are fitted; turn Fit
pictures off to get it back (it then shows after each picture again).
