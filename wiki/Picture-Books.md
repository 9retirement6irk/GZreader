Books whose pages are pictures (scanned pages, comics as EPUB) are fitted to the screen.

## Fit pictures and its options

In a book, **Fit pictures** in reader controls' **Layout** (a
swipe up from the bottom, or the quick panel's Reader tools) fits the book's
pictures to the screen when it's on, and puts the book back when it's off.
Hold it for its options:

- **Bigger when the bars are hidden** (on unless turned off): when a tap
  hides the title bar and the status bar, the pictures grow into the room
  they leave, and shrink back when they show again. KOReader otherwise keeps
  the status bar's room in an EPUB while it's hidden, and ZenOS the title
  bar's. Each time, the book is laid out again (a few seconds for a big one).
  A page keeps its shape: on a Paperwhite 3 a page made from a printed
  1359 x 2008 page goes from 919 to 965 pixels wide, as tall as the screen.
  With the status bar settings' "Hide on tap" set to the top bar alone (or the
  status bar alone), only that bar's room is used.
- **Fit picture books when they're opened** (on unless turned off): picture
  books are recognized and fitted when they're opened or downloaded.
- **Turn off for this book.**

## How it works

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
turned off (reader controls → Layout → Fit pictures, in a book). Checked with the
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
fitted before the fix is fitted again once when it opens, and one found not
to be a picture book before it is checked again (unless Fit pictures was
turned off in it). The layer's style rules are found in the book's CSS files
and in the pages' own `<style>` blocks (a converter that writes them into
every page: such a book showed each page's picture, then a page of its text).
The page's own size in the book (1700 × 2200 px on its page block, say) is
dropped from every block around the picture, not only the body: on a screen
wider than that the picture was held to that width, and on a narrower one
pushed to the right and cut off. And a fixed-layout book's pages are fitted
by the side that fills the room: a page narrower than the screen's shape is
as tall as the room, a wider one as wide as the screen. A letter-size
magazine page on a 3:4 screen (a Scribe) is in between: fitted by its height
with the bars shown, by its width once a tap hides them, changing by itself.
Its pictures aren't measured first: every one is a page
(The BOOK's 410 pictures, 264 MB, were read for 13 minutes in the background
on a Paperwhite 3, and the job then failed). A very big book is slow to open
whatever GZreader does: KOReader's EPUB engine reads the whole file each time
it opens it (to find its saved layout), about 25 s for 264 MB on a
Paperwhite 3, and fitting it opens it twice once. The invisible text
can't be searched or selected while the pictures are fitted; turn Fit
pictures off to get it back (it then shows after each picture again).
