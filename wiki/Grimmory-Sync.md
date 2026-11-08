What GZreader keeps the same on the device and in Grimmory (its web reader and your other devices): reading position, ratings, reading sessions, bookmarks, highlights and notes.

## Progress sync

Native: Grimmory's own reading-progress API (the web reader's), not its
KOReader-compatible endpoint.

- Books downloaded through the Grimmory tab, matched by Grimmory book ID.
- EPUB: the exact place as an EPUB CFI (`positionData`, made from the
  page's crengine XPointer with `gzreader_cfi.lua`), plus the chapter (spine
  file) and the position in it as a fallback. Grimmory's web reader
  (foliate-js) resumes from the CFI; before 1.1.0 no CFI was sent and it
  opened at the start of the chapter. PDFs/comics: page. FB2/MOBI/AZW3:
  percentage.
- Percentage: worked out like foliate-js does it (each spine file counts by
  its uncompressed size, from the EPUB's zip directory; non-linear files
  count 0), so Grimmory's figure matches its web reader on the same page.
  KOReader's footer counts rendered height and still shows its own figure
  (e.g. 11% on the Kindle where the web reader says 15%).
- Pull: a CFI from the web reader is converted back to an XPointer and the
  Kindle goes to that exact page; ahead / behind / same page is decided on
  KOReader's positions for both, so the two percentage scales don't mix.
  Every page of Diary of a Wimpy Kid (230 pages, all pictures) round-trips
  through a CFI to the same page on the Kindle 3's crengine.
- Pulled on open and wake; pushed every 10 page turns (or 3 minutes), on
  close and on sleep. Pulls, page-turn pushes and queued updates run in a
  short-lived background process one at a time (`gzreader_async.lua`), so
  the page never waits for the network; JSON replies are gzip-compressed. Forward moves from other devices apply silently; going
  back asks. Offline updates are queued and sent when Wi‑Fi returns.
  Sync jumps are not added to the Back history.
- Ratings: the stars you give a book (its status page, the end-of-book
  page) are Grimmory's personal rating for it, and the other way round.
  Grimmory rates out of 10, so 4 stars are 8 there, and 7 there are 4 stars
  here. Whichever side changed since they last agreed wins; removing the stars
  removes Grimmory's rating. Sent when the book closes (queued while
  offline), taken from Grimmory when it opens; books rated in the file browser
  are sent the next time Wi‑Fi connects.
- Reading sessions (30 s or longer) go to Grimmory's reading statistics.
  A session whose reply never came back (timeout, dropped connection) may
  have been saved anyway; before sending it again, GZreader looks in the
  book's session history on Grimmory for one with the same start time and
  length, and doesn't send it twice.

## Bookmark sync

Page bookmarks are kept the same on the Kindle and in Grimmory (web reader,
other devices), both ways, including deletions. EPUB bookmarks are converted
between KOReader's XPointers and Grimmory's EPUB CFIs using the book's own
XHTML (paragraph precision); PDF/comic bookmarks use the page number.
Bookmarks made offline are sent later. Synced on open and with "Sync with
Grimmory" (quick panel, in a book). Switch: Settings → Connections →
Grimmory → Sync bookmarks.

crengine makes a DocFragment for every spine item, image and SVG pages
included (checked on the Kindle 3's crengine), so DocFragment[i] is the i-th
spine item. Until 1.0.29 GZreader counted only XHTML items; books with
picture pages in the spine then fell back to percentages.

## Highlight and note sync

EPUB highlights and notes are kept the same on the Kindle and in Grimmory's
web reader (and other devices), both ways: new ones, colour and style
changes, notes, deletions. The conversion and three-way merge are vendored
from [Grimmory-KOReader-Client](https://github.com/ManorianOTP/Grimmory-KOReader-Client)
(MIT; `gzreader_cfi.lua`, `gzreader_annosync.lua`, `gzreader_slaxml.lua`, see
`plugins/gzreader.koplugin/THIRD_PARTY_NOTICES.md`); the orchestration is
`gzreader_annotations.lua`.

- A highlight is two crengine XPointers in KOReader and an EPUB CFI range with
  UTF-16 offsets in Grimmory (`epubcfi(/6/2[c1]!/4/6,/2/1:7,/3:4)`), converted
  with the book's own XHTML. Checked against the Kindle 3's crengine: every
  word range of a test book (nested inline tags, accents, an emoji, a `<br/>`,
  a picture page in the spine, `%20` and `../` in hrefs) converts to a CFI and
  back to the same text.
- Each pass compares the Kindle's highlights, Grimmory's, and what both had
  after the last clean pass (kept per book). A change on one side is copied
  to the other. A highlight changed on both sides since then is a conflict:
  each side keeps its own until they agree. Grimmory can't move a highlight's
  range, so a moved range is not overwritten either.
- When the reply to a new highlight is lost, the next pass finds it on
  Grimmory by its range and links it, so it isn't made twice (a repeat send
  gets 409 "already exists", which counts as sent).
- Colours: yellow, green, cyan, pink, orange, red, purple, blue, gray, white ⇄
  Grimmory's hex colours; styles: highlight, underline, strikeout, squiggly.
  A greyscale Kindle highlights in grey, which hardly shows in the web
  reader, so a new grey highlight goes to Grimmory as the web reader's
  yellow (one already in Grimmory keeps its colour). On a greyscale screen,
  a highlight colour too light to see there (yellow, light green) is drawn
  like the grey highlight; darker colours, underlines and colour screens are
  unchanged (`gzreader_hlcolor.lua`).
- Runs a few seconds after a Grimmory EPUB opens, a few seconds after you add,
  change or delete a highlight or note (when Wi‑Fi is on), with "Sync with
  Grimmory" (quick panel), and when the book closes with changes still waiting.
- The chapter parsing, conversions and requests run in one low-priority
  background process; only the merge into the open book happens on screen.
  Highlights already linked keep their conversion, so only new ones parse
  their chapters, and chapters are parsed once per pass.
- Page bookmarks stay with bookmark sync. Switch: Settings → Connections →
  Grimmory → Sync highlights and notes.
