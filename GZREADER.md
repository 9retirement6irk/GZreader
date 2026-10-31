# GZreader — Grimmory + ZenOS + KOReader for the Kindle Keyboard

A trimmed KOReader for legacy Kindles (Kindle 2, DX, Kindle Keyboard / K3)
that reads books, pulls them from a [Grimmory](https://grimmory.org) server
and keeps reading position, bookmarks, highlights and notes in sync with it. ZenOS is the
interface. Releases and updates: <https://github.com/9retirement6irk/GZreader>.

Based on KOReader `v2026.07.1` and ZenOS `4.2.0`. Version: see `GZREADER_VERSION`.

## What's in it

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface (Home, Downloads, navbar). English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `gzreader.koplugin` | GZreader itself: QR sign-in, library browser, downloads, progress, bookmark and highlight sync, Reading menu, read aloud, updates. |

Added: an English dictionary (Open English WordNet, CC BY 4.0, 11 MB).

Removed: the other 32 bundled plugins (including KOReader's own progress
sync), SSH/SFTP binaries, KOReader's OTA updater (it would replace this
build with stock KOReader), the 16 MB CJK fallback font, UI translations and
KOReader's first-run quickstart document (ZenOS's setup guide replaces it).

## Install

1. Jailbreak the Kindle and install KUAL (see kindlemodding.org).
2. Unzip `gzreader-kindle-legacy-<version>.zip` and copy the `koreader`,
   `extensions` and `launchpad` folders to the root of the Kindle's USB
   drive, merging with anything already there.
3. Eject, open KUAL → GZreader → Start GZreader. Or the launchpad shortcuts:
   Shift, G, G (last book), Shift, G, L (library), Shift, G, N (without the
   Kindle framework, more memory). The old Shift, P, … shortcuts still work.

The first start runs the setup guide: connect to Grimmory, then the library
view, keyboard, sync, sleep screen, clock and reading defaults.

## Updates

GZreader checks the latest release of github.com/9retirement6irk/GZreader
once a day (Settings → General → Updates, or Grimmory menu → GZreader
updates; the changelog is there too). Publishing an update is just making a
GitHub release:

1. Bump `GZREADER_VERSION` and add an entry to
   `plugins/gzreader.koplugin/gzreader_changelog.lua`, push.
2. On GitHub: Releases → Draft a new release → tag `v<version>` (for
   example `v1.0.4`; `v.1.0.4` also works) → Publish.

The "GZreader release packages" workflow then builds and attaches
`gzreader-kindle-legacy-<version>.zip` (full install) and
`gzreader-update.zip` (what Kindles download, ~5 MB). If a release has no
attached files, Kindles use the release's source code zip instead (~9 MB),
taking only `frontend/`, `reader.lua`, `koreader.sh` and the installed
plugins from it.

The download comes over HTTPS straight from GitHub (no hashing on the
Kindle); the zip must open and have a complete GZreader layout. Settings,
books, `.sdr` folders, history and the GZreader folder are never touched; if
anything fails, the previous files are put back. Then GZreader restarts.

## Keyboard (Kindle 3)

| Where | Key | Does |
| --- | --- | --- |
| Home / lists | Z, X, C, V, B | Switch the bottom tabs, counted from the left: Z Home, X Downloads, C Grimmory, V Notes, B Calendar (also Alt + Q, W, E, R, T…: Alt + the top row is how the Kindle Keyboard types 1–9). Shown under each tab. |
| Home | Q, W…; A, S, D… | Q the book you're reading, W, E, R… the books in the strip, A, S, D… the strip's tabs (shown in squares). |
| Any list or menu | Q, W, E, … | Pick the entry with that letter (shown next to it), in lists, the ZenOS settings and KOReader's menus. |
| KOReader's menus | Alt + Q, W, E, … | Switch the menu's tabs. |
| Home / lists | Menu | GZreader menu: Grimmory library, continue reading, audiobooks, search, history, Wi‑Fi, Settings (the Settings page), KOReader settings, updates, send log, sleep, restart, Quick panel (ZenOS), exit. Replaces ZenOS's touch quick-settings panel (switch: Grimmory → Menu key opens the GZreader menu). |
| Home / Downloads, book highlighted | Menu | The GZreader menu starts with that book: Open, Delete from this Kindle (asks first; Grimmory keeps it), More options (ZenOS's book menu). **Sort books…** is always in it. |
| Reading | Menu | Reading menu: contents, bookmarks, bookmark this page, go to page, search, read aloud, fonts, sync, dictionary, page browser, book info, Settings, Quick panel, close book. |
| Reading | Hold Menu | ZenOS page browser. |
| Reading | AA | Fonts and layout. |
| Reading | Shift + Sym | Read aloud / stop. |
| Reading | Back | Return from a followed link or TOC jump; otherwise go to Home. |
| Settings, audiobook player, tab views | Home | Home (the default tab). The audiobook keeps playing. |
| Anywhere | Volume buttons | Speaker volume for audiobooks and read aloud (a note shows the level). |
| Note editor | Menu | To the formatting toolbar and back; the cursor stays where it is. |

## Connect to Grimmory

Open the **Grimmory** tab. Grimmory's options (connection, sync, bookmarks,
highlights, auto-download shelf) are in **Settings → Connections → Grimmory**
(also KOReader → Tools → Grimmory); Memos (the Notes tab) is in **Settings →
Connections → Memos (Notes)**. Read aloud is in Settings → Reader; Wi‑Fi only
when needed and the diagnostic log in Settings → General; updates in Settings
→ General → Updates.

- **Connect with QR code**: the Kindle shows a QR code. Scan it with your
  phone; a sign-in page opens, served by the Kindle itself over your Wi‑Fi.
  The Kindle keeps only Grimmory's login tokens (never the password). The
  page works once, expires after 10 minutes, and stops when you press Back.
- **Connect by typing**: the same, using the Kindle's keyboard.

### Single sign-on (SSO / OIDC)

If Grimmory has SSO turned on, the QR page shows **Sign in with <provider>**.
One-time setup: add `http://<kindle-ip>:8642/oauth2-callback` as an extra
redirect URI on Grimmory's client at your identity provider (shown on the QR
page and under Grimmory → Single sign-on (SSO) setup). Reserve the Kindle's
IP in your router. If `ALLOWED_ORIGINS` is set in Grimmory, add
`http://<kindle-ip>:8642` too.

## Browsing Grimmory

Continue reading, Recently added, All books (A–Z), **Libraries**, **Authors**
(with search), **Series** (in series order) and Search. Audiobooks are left
out everywhere: Authors, Series and Libraries come from a local index of the
readable books (built in the background, refreshed daily), so authors or
series with only audiobooks don't appear, and the lists open instantly.
If Grimmory's `/app/libraries` endpoint fails (HTTP 500, a server bug seen
on some installs), the web app's library list is used instead.

Saved lists (`gzreader_listcache.lua`): the first page of every list fetched
(Continue reading, Recently added, All books, a library, shelf, author or
series, the library and shelf lists, Audiobooks) is kept on the Kindle, per
server and account (`cache/grimmory-lists`, newest 60). The Grimmory tab
opens at once, without waiting for Wi‑Fi; a list with a saved copy appears
straight away (its title ends in "· saved"), Wi‑Fi comes up quietly in the
background, and the fresh list replaces it in place (same page) when it
arrives, unless you've moved on. With no Wi‑Fi the saved copies are what you
get. "Load more" and Search always ask Grimmory.

The Grimmory tab is part of ZenOS's tab bar while it's open: the bar stays
at the bottom with the Grimmory tab underlined, and the title shows ZenOS's
status bar (clock, battery, Wi‑Fi, downloads) with the list's name and, in
a sub-list, a back arrow.

## Notes (Memos)

The Notes tab (it took Favorites' place in the tab bar, V) shows your
[Memos](https://usememos.com) notes as sticky notes, six to a page, pinned
first. Written against Memos v0.31 (`/api/v1`); newer servers that moved the
API to `/api` are found too.

- **Favorites** is still in Settings → Interface → Navbar → Tabs, turned
  off; turn it on there (or on the setup guide's Navbar Tabs page, which also
  offers Notes) to have both.
- **Connect:** the first time, the tab offers *Connect with QR code* (your
  phone enters the Memos address and an access token on a one-off page served
  by the Kindle, like Grimmory pairing) or *Connect by typing*. Create the
  token in Memos → Settings → My account → Access Tokens. The Kindle keeps
  the token (never your password) in GZreader's settings; it's never written
  to the log. An address without `https://` falls back to `http://` for a
  Memos on your home network.
- **Board:** Q–Y open a note, ◀ ▶ (or the page keys) turn pages, the 5-way
  moves around the notes. **N** new note, **F** filter, **M** for refresh,
  connect again and disconnect (the Menu key opens the Home menu in tab views).
- **A note:** the text in Patrick Hand, checklist items with letter keys
  (press one to tick or untick it; the change goes to Memos), pictures from
  the note shown inline, its tags and place, and its attachments (PDFs and
  other documents open in the reader, pictures in the image viewer; each is
  downloaded once into `cache/gzreader-notes`). **Alt+E** edits, **Alt+P**
  pins, page keys scroll a long note.
- **Editor:** a full page with a toolbar at the bottom: List, Check, Num,
  Head, *I*, **B**, # Tag and Save. **Menu** jumps to the toolbar from
  anywhere in the text (on the tool used last) and the cursor stays where it
  is, so the tool applies there; Menu again (or ▲) goes back to the text. ▼
  from the last line also reaches the toolbar; ◀ ▶ choose, Press applies. Shortcuts:
  Alt+L list, Alt+C checklist, Alt+N numbered, Alt+H heading, Alt+K italic,
  Alt+B bold, Alt+G tag, Alt+S save, Alt+V who can see it. Alt + the top
  row types 1–0 here. New notes are **private** unless you change it. Back
  asks whether to save.
- **Filters:** tag, date (today, 7 days, 30 days, a year), pinned and search
  are Memos filters; place and "with attachments" are picked out on the
  Kindle (Memos v0.31 can't filter by them).
- **Settings → Connections → Memos (Notes):** the Memos connection (connect again, disconnect);
  **Sync** all notes or only notes with chosen tags (Memos has no spaces or
  notebooks, so tags are the way to pick; the list comes from Memos' tag
  counts, `users/<id>:getStats`, and the filter is `tag in [...]`);
  **Storage used** with *Free up space* (downloaded attachments, kept
  notes); **Notes kept on the Kindle** (50–500, fetched a page at a time);
  **Attachment storage limit** (10–100 MB or none; the attachments used
  longest ago go first).
- **Wi‑Fi:** only to sync (when the tab opens, at most every 5 minutes, or with
  changes waiting; M → Refresh any time), to send a change, and to open an
  attachment not on the Kindle yet. Pictures in notes are downloaded while
  syncing (up to 2 MB each, within the attachment limit).
- **Offline:** the last list of notes is kept on the Kindle
  (`settings/gzreader-notes.json`); new notes, edits, ticks and pins made
  without Wi‑Fi wait in a queue and are sent the next time the Notes tab can
  reach Memos ("not sent yet" on the note meanwhile). The Notes tab keeps
  Wi‑Fi up while it's open (Wi‑Fi only when needed).

## Calendar (calendar links and CalDAV)

The Calendar tab (B) shows calendars from their **shared links** (webcal:// or
https://….ics: Proton Calendar's Share → Share with anyone, Google's secret
iCal address, Outlook's published ICS…) and/or a **CalDAV account**, read-only.

- **Calendar links:** add several at once with the QR code page (one per line,
  `Name | link` to name one), by typing, or from `calendars.txt` (GZreader
  folder or the top of the USB drive). Each is fetched when added (named after
  its `X-WR-CALNAME`) and at every sync; `webcal://` is fetched over HTTPS,
  falling back to HTTP. Links are secret: kept in GZreader's settings, never
  logged (requests show the server only, `rawRequest`'s `log_url`). Times use
  the file's own VTIMEZONE rules; repeating events are expanded on the Kindle.
  Settings → Connections → Calendar → Calendar links: show / rename / remove.

The CalDAV account: Nextcloud
(`https://your.server/remote.php/dav`), iCloud (`https://caldav.icloud.com`),
Fastmail (`https://caldav.fastmail.com`), Google
(`https://apidata.googleusercontent.com/caldav/v2/`), Radicale, Baïkal…

- **Connect:** Connect with QR code (the phone enters the address, user name
  and password) or Connect by typing. Use an app password where the server
  has them; it's kept in GZreader's settings like the Memos token and never
  logged (the log has addresses only, and passwords are redacted from it).
  Discovery follows RFC 6764: the address → `current-user-principal` →
  `calendar-home-set` → the VEVENT calendars in it (`/.well-known/caldav` is
  tried for a bare host; a calendar's own address works too).
- **Layouts:** Agenda, Day (timeline, overlapping events side by side),
  Week (seven columns), Month (grid). Letters open an event (a day in Week);
  Press opens what the 5-way is on; a day in Week or Month opens in Day. Page
  keys (or ‹ ›): next / previous day, week, month (Agenda: the next days).
  **N** today, **M** layouts, Refresh, settings.
- **Sync:** one `calendar-query` REPORT per calendar for the sync range
  (default 14 days back, 90 ahead), asking the server to expand repeating
  events (`<C:expand>`, times in UTC). Servers that don't expand send the
  RRULE, expanded on the Kindle (DAILY / WEEKLY / MONTHLY / YEARLY with
  INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY; EXDATE; RECURRENCE-ID). TZID times
  that aren't expanded are read in GZreader's time zone.
- **Wi‑Fi:** only to sync, when the tab opens (at most every 15 minutes) and
  with M → Refresh. Events are kept on the Kindle (`settings/gzreader-calendar.json`).
- **Settings → Connections → Calendar (CalDAV):** connection, calendars shown,
  the layout it opens in, week start (Sunday / Monday), sync range, storage.

## Subtitles

Grimmory's subtitle is added to the title ("Diary of a Wimpy Kid: Old
School") in the Grimmory lists and, for downloaded books, as KOReader custom
metadata (`.sdr/custom_metadata.lua`, like Book information → edit title),
so Home, Downloads, history and the reader show it. The app API's lists have
no subtitles, so they come from the library index (Grimmory's web book list,
`/api/v1/books/page`) and from the book itself after a download. Titles you
edited yourself are left alone.

## Downloads screen and title bar

While anything downloads, **Downloads (N)** is the first entry of the GZreader
menu (Menu key on Home) and is in the Reading menu; it's always in Settings →
GZreader (`gzreader_tasks.lua`). It lists the current book download, the
queue, audiobook downloads and the audiobook preparing step: reopen a
progress bar, stop the download, take a book out of the queue, empty the
queue. ZenOS's status bar gets a `gz_downloads` item next to the clock
(added once; movable/removable in its settings): a download icon with the
percentage and the number waiting, refreshed every 10 s while active.

## Book covers when downloading

Picking a book in the Grimmory browser asks whether to download it and shows
Grimmory's cover thumbnail (250 x 350, `/api/v1/media/book/<id>/thumbnail`),
fetched in the background and kept in `koreader/cache/grimmory-thumbs/`
(renewed when the cover changes in Grimmory).

## Home folder and downloads

The GZreader folder (`documents/GZreader`) is the home folder; the
**Downloads** tab shows it. Books download in a background process with a
progress bar (percentage, MB received of the total; the Kindle stays awake
until it's done). Picking more books while one downloads queues them; they
download one after another (lists show "queued"; the download options can
empty the queue) (press any key for Stop / Continue in background / Keep
watching); a transfer that stalls for 90 s is stopped.

A backup list of downloaded books (`.gzreader-library.json`) is kept in the
GZreader folder. If KOReader's settings are lost (for example the `koreader`
folder was replaced), the books are re-linked to Grimmory from it, or by file
name from the library index, so progress sync and "on Kindle" marks keep
working.

## Shelves and auto-download

Grimmory tab → **Shelves** lists your shelves and smart (magic) shelves.
Settings → Connections → Grimmory → **Auto-download shelf** picks one: books on it that
aren't on the Kindle download in the background through the download queue
when Wi-Fi connects (at most every 30 minutes) and with "Download new books
from the shelf now". Books taken off the shelf stay on the Kindle. (Idea from
krisboho/connecto-library's Shelf Sync.)

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
Grimmory now". Switch: Grimmory menu → Sync bookmarks.

crengine makes a DocFragment for every spine item, image and SVG pages
included (checked on the Kindle 3's crengine), so DocFragment[i] is the i-th
spine item. Until 1.0.29 GZreader counted only XHTML items; books with
picture pages in the spine then fell back to percentages.

## Remote debugging

For freezes and hard reboots, where the Kindle's own log may be lost:
GZreader can report to a feed (Tianji-style `…/open/feed/<id>/send`,
`/state/upsert`, `/state/resolve`), set in Settings → General → Remote
debugging or by a `gzreader-remote.txt` file on the USB drive with the feed
address on its first line. The address is not in the code (the project is
public). `gzreader_remote.lua` queues messages as JSON files in
`koreader/gzreader-remote/spool`; `gzreader_watchdog.lua`, a separate
low-priority LuaJIT process, sends them when Wi‑Fi is on (GZreader never turns
Wi‑Fi on for them) and watches a heartbeat GZreader writes every 15 s:

| Report | When |
| --- | --- |
| GZreader started | every start: version, battery, memory, how the previous run ended |
| Previous run ended unexpectedly (important) | the last heartbeat said "running": hard reboot, battery, freeze or crash; with what it was doing, the previous run's log tail and crash.log |
| Kindle unresponsive (important) + state "GZreader unresponsive" | no heartbeat for 2 minutes while awake: memory, load, top processes, kernel messages and the log at that moment |
| Kindle responsive again + state resolved | the heartbeat is back |
| GZreader crashed (important) | the process ended without closing: crash.log and log tail |
| warnings / errors | GZreader's log warnings and errors, a minute at a time |

| GZreader slow | no heartbeat for 45 s (once per 10 min): the same snapshot |
| GZreader busy (important) | GZreader at 60% CPU or more for a minute (from the app) |
| warning "slow: …" | a keypress, repaint or round of scheduled work took 3 s or more |

Where the time goes (`gzreader_slowtrace.lua`, with remote debugging on):
LuaJIT's sampling profiler (`jit.profile`, every 50 ms of CPU time, so
nothing while idle) tallies the running code (3 frames) and whether it is
Lua, JIT code, C (e.g. crengine), garbage collection or the JIT compiler. The
tally is written to `gzreader-remote/profile` every ~5 s of CPU, also while
GZreader is stuck in one long call, and goes into the watchdog's reports,
with each GZreader process's state, CPU over 2 s, memory and wait channel.

Sleep is not a freeze (the heartbeat says "sleep", and the watchdog notices
the clock jump after waking). Log lines are redacted (no passwords or
tokens). Checked with the Kindle 3's LuaJIT against a local feed: queued
messages, the freeze alert with its snapshot, "responsive again", the crash
report, and no crash report after a normal close.

## Unfinished downloads

Every book download (running or queued) and every audiobook download and
"preparing the audio" is noted when it starts and crossed off when it ends
(`gzreader_recovery.lua`). If GZreader stops in between (battery ran out,
the Kindle slept or restarted, a crash), it asks about each one a few
seconds after the next start: **Continue** (books continue from the part
already downloaded with an HTTP Range request; audiobooks continue
downloading their tracks and preparing the ones not yet converted, after
stopping any conversion still running from before), **Delete** (removes
the part) or **Ignore** (stops asking, keeps the part: downloading it again
later still continues from there). A stalled download now also keeps its
part. Stopping a download yourself, taking it out of the queue, or a "not
found" from Grimmory clears it.

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
- Runs a few seconds after a Grimmory EPUB opens, a few seconds after you add,
  change or delete a highlight or note (when Wi‑Fi is on), with "Sync with
  Grimmory now", and when the book closes with changes still waiting.
- The chapter parsing, conversions and requests run in one low-priority
  background process; only the merge into the open book happens on screen.
  Highlights already linked keep their conversion, so only new ones parse
  their chapters, and chapters are parsed once per pass.
- Page bookmarks stay with bookmark sync. Switch: Grimmory menu → Sync
  highlights and notes.

## Read aloud (Kindle 3 text-to-speech)

Uses the Kindle's own voice (Amazon's speech service, reached over lipc
with the Kindle's `lipc-hash-prop` tool, run in the background so the screen
never waits; KOReader's lipc library doesn't load on the Kindle 3).
Shift + Sym (or Reading menu → Read aloud) starts and stops. The sentence
being read is highlighted and pages turn by themselves. EPUB/FB2/MOBI/AZW3
and text only.

Amazon never documented the request format. The speech daemon (`ttsd`)
writes which field it's missing to the system log ("unable to read id"), so
Reading menu → Read-aloud settings → Find the Kindle voice adds the missing
fields one by one until `ttsd` accepts the request, plays "Voice test" and
asks whether you heard it; the request shape is then saved. Text goes to the voice a
sentence at a time (split only when a sentence passes 30 words at a comma,
semicolon, colon or dash, or 80 words; paragraph and heading ends always end
a piece); web addresses are left out. When a sentence runs onto the next
page, the page turns part-way through, at the share of the sentence's
characters already said. The speech
service doesn't report when a sentence ends, so the next sentence starts
after a time computed from its length and the speed setting (Read-aloud
settings → Slower / Faster). The diagnostic log records every step.

## Audiobooks (experimental)

Grimmory tab → Audiobooks.
Pick one to download it to `Grimmory/Audiobooks/<id>/` (single M4B file,
converted for the Kindle, or one file per track for folder audiobooks), then the player opens:

| Key | Does |
| --- | --- |
| 5-way press / Space | Play / pause |
| Left / Right | Back / forward 30 s |
| Up / Down | Previous / next chapter |
| Q / W / E | Chapters / sleep timer (15–60 min, end of chapter) / stop |
| A / S | Quieter / louder |
| D | About this book: Grimmory's description, narrator, length |
| Menu | About, chapters, sleep timer, stop |
| Back | Close the screen (keeps playing; reopen from Home or Downloads → Audiobooks) |
| Home | Home (keeps playing) |
| Volume buttons | Volume, here and anywhere in GZreader (a note shows the level) |

Pause stops the player process and remembers the place; play starts it
again from there (MP3: to the nearest 4 KB; M4B: from the AAC frame playing
when paused). The Kindle 3's sound pipeline doesn't come back from a
suspended process, and a stopped one also frees the sound device for read
aloud. Sleep (the power switch) pauses; leaving GZreader (Exit to the
Kindle's menu, a restart) stops the audiobook and read aloud.

Position syncs with Grimmory's audiobook progress (same fields as its web
player: position in the track and track index), every minute while
playing, on pause and on stop; offline updates are queued. The Kindle
doesn't go to sleep while audio plays; pressing the power button pauses.
The book's description comes from Grimmory with the download (and, for
audiobooks downloaded before 1.6.2, the next time the player opens online);
Home's featured book shows it too.

Playback uses what the Kindle 3 has: GStreamer 0.10 (`gst-launch-0.10`)
with Freescale's hardware decoders `mfw_mp3decoder` and `mfw_aacdecoder`,
into ALSA. MP3 starts anywhere (the file is fed from the right byte offset).
There is no MP4 demuxer on the Kindle, so an M4B is converted once after
download (`gzreader_mp4.lua`: each AAC frame gets an ADTS header; no
re-encoding) into ~15-second pieces in `<file>.chunks/`; playback starts at
the piece holding the position and feeds the following ones to the AAC
decoder. **Test audio playback** tries the pipelines with a short MP3 and an
AAC tune (converted from the bundled M4A, which also tests the converter),
asks which you heard and remembers it.

Downloads use Grimmory's audiobook stream endpoints and resume with HTTP
Range after a dropped connection or timeout.

The conversion runs as a separate `luajit gzreader_mp4.lua <in> <dir>
<progress>` process at nice 19 (~8 MB for a long book; sample tables are
read in 64 KB blocks), with a progress bar fed from its progress file. A
fork of KOReader isn't used for it: the fork's copy of KOReader's heap gets
duplicated page by page as its garbage collector runs, which ran the
Kindle 3 out of memory in 1.0.21.

## Picture books

EPUBs whose chapter files are pictures with next to no text (scanned pages,
e.g. Diary of a Wimpy Kid: 385 x 625 JPEG per page) are recognized on
opening (`gzreader_picturebook.lua`: sampled spine files, ≥ 70 % pictures-only).
GZreader then adds a book style tweak (`img { height: 100%; width: auto;
max-width: 100% }`, no margins/padding), sets the book's page margins to 0
and turns on smooth image scaling, keeping the old settings for when it's
turned off (Reading menu → Fit pictures to the screen). Checked with the
Kindle's own crengine.

`100%` is the page area between the top and bottom margins (ZenOS adds its
title-bar height to the top margin), so pictures stay clear of the title bar
and footer. 1.0.28 used `100vh`, the whole screen: pages ran under the clock
and the footer (crengine also split them, adding blank pages), and a wide
picture capped at the screen width was stretched to full height. With `100%`
crengine keeps each picture's shape. The scans are only ~385 x 625, so
they're enlarged about 1.3x to fill 800 pixels; that's why they look softer
than real text. Smooth scaling makes them much less jagged.

## Sleep screen

While a book is open: its cover. From Home and menus: a random picture from
the USB drive's `screensavers` folder (created by the setup guide), falling
back to the Kindle's own sleep pictures. Chosen in the setup guide; picking
another option there, choosing a wallpaper in the sleep-screen menu, or
applying a ZenOS sleep-screen preset switches it off and uses that choice.

"Show custom image (book cover while reading)" (KOReader's "custom image or
cover"): the chosen image from Home and menus, the open book's cover while
reading. In KOReader it showed the custom image everywhere.

## Wi-Fi only when needed

On by default (Settings → General → Wi-Fi only when needed). GZreader turns
Wi-Fi on by itself when it needs the network and off again after a minute
unused, as long as nothing still needs it (an open Grimmory browser, a
download or its queue, the library index, a QR screen, an update download).

| When | Wi-Fi |
| --- | --- |
| Browsing Grimmory, downloading, connecting, sending the log, checking for / installing updates | turned on ("Connecting to Wi-Fi…") |
| A Grimmory book opens | turned on quietly: pull the position, send queued changes, sync bookmarks, highlights and notes |
| A book closes with unsent changes (position, session, highlights) | turned on quietly to send them |
| Wake after 15 min or more with a book open | turned on quietly to pull the position |
| Page turns, bookmarks, highlights, sleep | not turned on: changes wait for the next sync |
| Daily update check, library index refresh | only if Wi-Fi is already on |

Wi-Fi you turned on yourself is never turned off. Going to sleep turns off
Wi-Fi GZreader turned on.


Wi‑Fi you turn off yourself (Wi‑Fi menu, quick panel, Home menu: KOReader's
interactive switch) stays off for background work (syncs when a book opens
or closes, after waking, Notes, Calendar, the auto-download shelf) until you
turn it on again, also after a restart (`gzreader_wifi_kept_off`). Things you
ask for still connect.
## Speed on the Kindle 3

- Lua is shipped as precompiled bytecode (see Rebuild the package): no parsing
  at start (~4x faster loading overall, up to 15x for big files).

- Covers are pre-sized (Settings → Interface → Pre-size covers). ZenOS scales
  every cover to the exact size of where it's shown; on the Kindle 3 that took
  ~4 s of CPU per Home screen (the cover strip), and its memory cache starts
  empty after every restart. GZreader keeps each final-size cover as a raw
  bitmap in `koreader/cache/gz-covers/` (used only while the book file is
  unchanged), learns the sizes ZenOS uses, and a low-priority background
  process (`gzreader_coverwarm.lua`) makes them for every downloaded book a
  minute after start, after downloads and when a new size shows up. Books
  whose cover hasn't been read yet go through KOReader's cover extraction
  first.

- Night mode is off and can't be switched on (Kindle 2, DX, Keyboard, 4):
  these Kindles have no hardware screen inversion, and KOReader's software
  inversion made the Kindle 3 unusably slow.

- The removed CJK font was still listed as a fallback, so every missing
  glyph made KOReader try to load it again (dozens of errors per screen in
  the log). Missing fallbacks are now dropped at start.
- ZenOS's Home "quotes" row (about 0.5 s per Home rebuild) is off by default.
- ZenOS's icon font is no longer registered with the book renderer (it
  failed every time).
- The first open of a big EPUB is slow (crengine renders and caches it; 28 s
  seen for a large book). Later opens use the cache.

## Diagnostic log

**Send it to your phone:** Diagnostics in the Home or Reading menu, or Settings →
General → Send diagnostic log to my phone (QR code). Scan the code (same Wi-Fi), tap Download, then attach
the file wherever you need it.


`koreader/gzreader.log` (rotates at 512 KB): requests with status and timing,
pairing, SSO, downloads, sync, bookmarks, updates, read aloud. Passwords and
tokens are never written. Grimmory → Save diagnostic log copies it, the tail
of `crash.log` and a read-only audio/speech survey next to the Grimmory
folder.

## Rebuild the package

```sh
tools/gzreader/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua and shell scripts, so the script overlays it onto
the official release built from the same tag rather than rebuilding the
native toolchain.

It then precompiles every Lua file under `frontend/`, `plugins/` and
`common/` to LuaJIT bytecode with the release's own `luajit` (run through
`qemu-arm-static`; needs `qemu-user-static`, `libc6-armel-cross` and
`libgcc-s1-armel-cross`), keeping the `.lua` names and debug info (line
numbers, upvalue names, source paths), so loading skips parsing. Without
qemu it warns and ships source. `GZ_BYTECODE=0` turns it off.
