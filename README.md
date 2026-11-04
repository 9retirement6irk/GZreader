<p align="center">
  <img src="docs/gzreader-logo.svg" alt="GZreader logo" width="120">
</p>

<h1 align="center">GZreader</h1>

<p align="center">
  <b>Grimmory + ZenOS + KOReader for the Kindle 2, Keyboard, DX, Kindle 4, Touch and Paperwhite 3</b><br>
  Your <a href="https://grimmory.org">Grimmory</a> library on a Kindle: download books, read them,
  and keep your place, bookmarks and highlights in sync. Notes, calendars, and books
  sent from your phone too.
</p>

<p align="center">
  <a href="https://github.com/9retirement6irk/GZreader/releases/latest"><b>Download the latest release</b></a> ·
  <a href="GZREADER.md">Full guide</a> ·
  <a href="plugins/gzreader.koplugin/gzreader_changelog.lua">Changelog</a>
</p>

---

GZreader is a reading app for older Kindles, with a keyboard or without:

| Kindle | How you use it |
| --- | --- |
| **Kindle 2**, **Kindle Keyboard (3)**, **DX** / DX Graphite | the keyboard and 5-way: letter keys for everything |
| **Kindle 4** (non-touch) | the 5-way and Menu |
| **Kindle Touch** (4th gen), **Paperwhite 3** (7th gen) | touch |
| **Nook 1st Edition** (B&N, 2009) — *test build* | the colour touchscreen under the page: arrows, OK, Menu, a keyboard, reading info |
| **Nook Simple Touch** / with GlowLight (B&N, 2011–12) — *test build* | touch, like the Kindle Touch |

It is [KOReader](https://github.com/koreader/koreader) trimmed down
to reading, with the clean [ZenOS](https://github.com/xZenLabs/zen-os) interface, and
a built-in connection to a self-hosted **Grimmory** book server.

## Screenshots

<sub>Taken on GZreader's Kindle 3 emulator (the Kindle's own software, 600 × 800,
16 grey levels) with a demo library of public-domain books; the phone page in a phone-sized
browser talking to the emulated Kindle.</sub>

### Setup

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/setup-connect.png" alt="First start: Connect your phone" width="240"><br><sub>First start: Connect your phone</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/setup-qr.png" alt="The QR code opens the phone page" width="240"><br><sub>The QR code opens the phone page</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/setup-summary.png" alt="Back on the Kindle: what changed" width="240"><br><sub>Back on the Kindle: what changed</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/setup-keyboard.png" alt="The Kindle Keyboard's keys" width="240"><br><sub>The Kindle Keyboard's keys</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/home.png" alt="Home: the book you're reading" width="240"><br><sub>Home: the book you're reading</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/home-menu.png" alt="Menu key at Home: every entry has a letter key" width="240"><br><sub>Menu key at Home: every entry has a letter key</sub></td></tr>
</table>

### Your phone page

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/phone-start.png" alt="Grimmory, Notes, Calendar and books on one page" width="240"><br><sub>Grimmory, Notes, Calendar and books on one page</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/phone-connected.png" alt="Connected: disconnect or switch accounts there" width="240"><br><sub>Connected: disconnect or switch accounts there</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/phone-calendar.png" alt="Show or hide calendars; rename, replace or remove links" width="240"><br><sub>Show or hide calendars; rename, replace or remove links</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/phone-books.png" alt="Send books from your phone, no Grimmory needed" width="240"><br><sub>Send books from your phone, no Grimmory needed</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/book-received.png" alt="The Kindle notes each change and each book" width="240"><br><sub>The Kindle notes each change and each book</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/downloads-received.png" alt="The books are in the Downloads tab" width="240"><br><sub>The books are in the Downloads tab</sub></td></tr>
</table>

### Your Grimmory library and downloads

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/grimmory-tab.png" alt="The Grimmory tab" width="240"><br><sub>The Grimmory tab</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/grimmory-all-books.png" alt="All books, with reading progress" width="240"><br><sub>All books, with reading progress</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/download-confirm.png" alt="Download and open" width="240"><br><sub>Download and open</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/download-progress.png" alt="Downloading in the background" width="240"><br><sub>Downloading in the background</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/downloads-tab.png" alt="The Downloads tab" width="240"><br><sub>The Downloads tab</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/reading.png" alt="Reading" width="240"><br><sub>Reading</sub></td></tr>
</table>

### Reading menu and read aloud

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/reading-menu.png" alt="Menu key while reading" width="240"><br><sub>Menu key while reading</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/read-aloud.png" alt="Read aloud (Shift + Sym): the sentence being read is highlighted" width="240"><br><sub>Read aloud (Shift + Sym): the sentence being read is highlighted</sub></td></tr>
</table>

### Notes (Memos)

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/notes-board.png" alt="The Notes tab: Memos notes as sticky notes" width="240"><br><sub>The Notes tab: Memos notes as sticky notes</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/notes-note.png" alt="A note: tick checklist items with their letter key" width="240"><br><sub>A note: tick checklist items with their letter key</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/notes-editor.png" alt="Writing a note, with the Markdown toolbar" width="240"><br><sub>Writing a note, with the Markdown toolbar</sub></td></tr>
</table>

### Kindle Paperwhite 3 (touch)

<sub>On the emulator as a Paperwhite 3: 1072 × 1448, 300 dpi, touch.</sub>

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-launcher.png" alt="Swipe down: quick settings and the launcher (GZreader menu, Phone, Send books)" width="240"><br><sub>Swipe down: quick settings and the launcher (GZreader menu, Phone, Send books)</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-grimmory.png" alt="The Grimmory tab by touch" width="240"><br><sub>The Grimmory tab by touch</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-notes.png" alt="Notes: New note, Filter and More buttons" width="240"><br><sub>Notes: New note, Filter and More buttons</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-note.png" alt="A note: tap a checklist item to tick it" width="240"><br><sub>A note: tap a checklist item to tick it</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-note-editor.png" alt="The note editor with the on-screen keyboard" width="240"><br><sub>The note editor with the on-screen keyboard</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/pw-calendar.png" alt="Calendar: ◀ Today ▶ and More, or swipe" width="240"><br><sub>Calendar: ◀ Today ▶ and More, or swipe</sub></td></tr>
</table>

### Kindle 4 (5-way) and Kindle Touch

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/k4-notes.png" alt="Kindle 4: Notes, with the Menu key for new note, filter…" width="240"><br><sub>Kindle 4: Notes, with the Menu key for new note, filter…</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/k4-note-editor.png" alt="Kindle 4: typing with the 5-way on the on-screen keyboard" width="240"><br><sub>Kindle 4: typing with the 5-way on the on-screen keyboard</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/kt-audiobook.png" alt="Kindle Touch: the audiobook player by touch" width="240"><br><sub>Kindle Touch: the audiobook player by touch</sub></td></tr>
</table>

### Calendar and audiobooks

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/calendar-agenda.png" alt="The Calendar tab: CalDAV calendars and calendar links" width="240"><br><sub>The Calendar tab: CalDAV calendars and calendar links</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/calendar-week.png" alt="Week view" width="240"><br><sub>Week view</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/audiobook-player.png" alt="The audiobook player: chapters, sleep timer, volume keys" width="240"><br><sub>The audiobook player: chapters, sleep timer, volume keys</sub></td></tr>
</table>

## Features

### 📱 Set up from your phone
- **One QR code for everything.** The Kindle shows a code, you scan it with your
  phone, and a page served by the Kindle itself (over your Wi‑Fi) connects
  **Grimmory**, **Notes** (your Memos server) and **Calendar** (a CalDAV account or
  webcal / ICS links such as Proton Calendar's). No typing passwords on the Kindle
  keyboard. Single sign-on (OIDC: Authentik, Pocket ID, Authelia, Keycloak…) works too.
- **Manage it all there later:** disconnect or switch accounts, show or hide
  calendars, rename a calendar link or give it a new one, remove it.
- **Send books from your phone** (no Grimmory needed): pick EPUB, PDF, MOBI, AZW3,
  FB2, CBZ, TXT, DOCX… files and they go straight onto the Kindle.
- Only Grimmory's login tokens, the Memos token and the CalDAV app password are
  kept on the Kindle, never written to its log.

### 📚 Your Grimmory library
- **Search** first in the tab (title, author or series, A–Z), and inside any
  library, shelf or author's books; **browse** Continue reading, Recently added,
  All books, **Libraries**, **Authors**, **Series** (in reading order), each
  with its own search. Audiobooks are left out.
- **Background downloads** with a progress bar; keep using the Kindle while a book
  downloads. Books go to a `GZreader` folder, shown in the **Downloads** tab.

### 🔄 Sync with Grimmory
- **Reading position** syncs with Grimmory's own progress (the web reader's), not the
  KOReader sync endpoint, to the exact page (EPUB CFI). Pick up on the Kindle where you
  left off on the web, and the other way round.
- **Bookmarks** sync both ways, deletions included.
- **Remote debugging** (optional): freezes, crashes and hard reboots are reported to
  your own feed by a small watchdog process, with what the Kindle was doing.
- **Unfinished downloads** (dead battery, sleep, crash) are offered again at the next
  start: continue where it stopped, delete, or ignore.
- **Highlights and notes** in EPUBs sync both ways with Grimmory's web reader: new
  ones, colours, notes and deletions (conversion and merge from
  [Grimmory-KOReader-Client](https://github.com/ManorianOTP/Grimmory-KOReader-Client), MIT).
- **The Grimmory tab opens instantly**, even offline or while Wi‑Fi connects: lists
  show their saved copy first and refresh in the background.
- **Shelves**, and **auto-download a shelf**: put books on a Grimmory shelf and
  they land on the Kindle by themselves.
- Syncing happens in the background: the page never waits for the network.
- **Works offline:** changes are saved on the Kindle and sent when Wi‑Fi is back.
- Reading sessions feed Grimmory's reading statistics.

### 📝 Notes (Memos)
- The **Notes tab** shows your [Memos](https://usememos.com) notes as sticky notes in
  a handwriting font, six to a page. Open one with its letter key.
- **Tick checklist items**, see pictures, tags, places and attachments (PDFs open in
  the reader). Filter by tag, date, place, attachments, pinned or text.
- **Write and edit notes** on a full-page editor with a Markdown toolbar (lists,
  checklists, headings, italic, bold, tags). New notes are private.
- Works offline: notes are kept on the Kindle and changes are sent when Wi‑Fi is back.

### 📅 Calendar (CalDAV)
- The **Calendar tab** shows calendars from their shared links (webcal / ICS, e.g.
  Proton Calendar) and CalDAV accounts (Nextcloud, iCloud, Fastmail…) as an agenda,
  a day timeline, a week or a month. Paste several links at once from your phone,
  and rename, replace or hide them there later.
- Works offline; Wi‑Fi only to sync.

### ⌨️ Made for the keyboard (Kindle 2, 3, DX)
- **Reading menu** on the **Menu** key: contents, bookmarks, go to page, search, read
  aloud, fonts, sync, dictionary, book info. Every entry has a letter key.
- **GZreader menu** on the **Menu** key at Home: library, continue reading,
  audiobooks, search, Wi‑Fi, settings, updates, sleep, restart — also
  with letter keys.
- **Z, X, C, V, B** switch the bottom tabs (Home, Downloads, Grimmory, Notes,
  Calendar); **Q, W, E…** and **A, S, D…** open the books and tabs on Home.
- **Back** returns from a link, otherwise goes Home (never back to the book's start).

### 🕹️ The Kindle 4: 5-way and Menu
- The 5-way moves and Press picks everywhere; **Down** from the bottom of Home
  reaches the tabs. **Menu** opens the GZreader menu at Home, the Reading menu in a
  book, and the options (new note, filter, today, layouts…) in Notes and Calendar.
- Notes: choose a checklist item with ▲ ▼ and Press to tick it; the note editor types
  with the 5-way on the on-screen keyboard, and Menu goes to its toolbar.
- The 8-bit screen gets the same faster drawing as the Kindle 3's.

### 👆 And by touch on the Kindle Touch and Paperwhite 3
- ZenOS's **touch interface**: tabs at the bottom, tap to turn pages, swipe down from
  the top for quick settings (Wi‑Fi, brightness, sleep) and the **launcher** with the
  GZreader menu, the phone page and Send books.
- GZreader's own screens have **buttons** where the Kindle 3 has keys: New note,
  Filter and More in Notes; ◀ Today ▶ and More in Calendar; tap a checklist item to
  tick it; the note editor with the on-screen keyboard.
- Sized for each screen (the Paperwhite's 300 dpi). The Kindle Touch plays
  audiobooks with the player's buttons and reads aloud from the quick panel; the
  Paperwhite has no audio.

### 📟 The Nook 1st Edition: both screens (test build)
- The **colour touchscreen** under the e-ink page drives GZreader: ▲ ▼ ◀ ▶ and OK,
  Back, Menu (the GZreader menu, never ZenOS's touch panel), Home and page buttons;
  while reading it shows the **title, chapter, page and progress** or the **cover**,
  elsewhere a clock; when typing, a **keyboard** so the page stays uncovered.
- What it shows when, how long it stays lit and its brightness are settings
  (Settings → Interface → Colour screen); swipe on it to turn pages.
- Needs a rooted Nook; installed with adb. Checked in the emulator only so far:
  see [the Nook section](GZREADER.md#nook-1st-edition-test-build) for rooting,
  installing and what to report.

### 📖 And the Nook Simple Touch (test build)
- The same package as the 1st Edition; on the Simple Touch (and GlowLight) GZreader
  works by touch like on the Kindle Touch, with the page buttons, **n** for Home and the
  frontlight in quick settings. See [its steps](GZREADER.md#nook-simple-touch-test-build).

### 🔊 Read aloud (Kindle 2, 3, DX, Touch)
- Uses the **Kindle's own voice**. **Shift + Sym** starts and stops, like the stock
  Kindle's Text-to-Speech; on the Kindle Touch, **Listen** in the quick panel (swipe
  down from the top while reading).
- The sentence being read is **highlighted** and **pages turn by themselves**.
- Speed and volume controls; the Kindle's volume buttons work while reading
  (and everywhere else in GZreader).

### 🎧 Audiobooks (experimental: Kindle 2, 3, DX, Touch)
- Browse Grimmory's **audiobooks**, download them (M4B or MP3 tracks) and listen
  through the speaker or headphones.
- **Chapters**, ±30 seconds, **sleep timer** (15/30/60 minutes or end of chapter),
  volume (also the Kindle's volume buttons), the book's **description**;
  playback continues while you browse. The Home key goes Home from the player.
- Listening position **syncs with Grimmory's web player**.
- Plays through the Kindle 3's own hardware MP3/AAC decoders. M4B files are
  converted on the Kindle after download (no re-encoding) so they can start
  anywhere; downloads resume after a dropped connection. **Test audio playback**
  checks which player works on your firmware.

### 🔋 Battery
- **Wi‑Fi only when needed:** turned on by itself for browsing, downloads,
  updates and syncing when a book opens or closes, and off again after a minute.

### 🌙 And more
- **Sleep screen:** the book's cover while reading, a picture from the `screensavers`
  folder on Home and in menus.
- **English dictionary** built in (Open English WordNet, 128,000 words).
- **Updates from GitHub releases**, installed from Settings → General → Updates.
  Your books, settings and progress are kept.
- **Faster on a Kindle 3:** unused plugins, fonts and translations removed, slow
  Home widgets off by default.
- **Diagnostic log** you can save and share (passwords and tokens are never written).

## Usage statistics

GZreader sends anonymous usage statistics to its developer's
[Tianji](https://tianji.dev) server, so problems on real Kindles can be found
and fixed. You choose the level in the setup guide or in
**Settings → General → Usage statistics**:

| Level | What's sent |
| --- | --- |
| **Basic** (default) | GZreader's version, the Kindle model and firmware at each start; whether the previous run ended without closing normally; downloads that worked or failed; slow operations; keys the screen didn't answer |
| **Full** | Basic, plus time on Home, Downloads, Grimmory, in books and menus; menu entries used; reading sessions (format, picture book or not, minutes, pages, pages per minute, battery use per hour); read aloud; download size, speed and resumes; sync results and Grimmory's answer times; Wi‑Fi on-time |
| **Off** | Nothing is recorded or sent |

Never sent: book titles, authors, file names, your Grimmory address or account,
or anything you type. Each Kindle is counted by a random ID, not its serial
number. Statistics wait in a small file and go out in one batch at most every 15
minutes, only while Wi‑Fi is already on; GZreader never turns Wi‑Fi on for them.

## Install

You need a **jailbroken** Kindle with **KUAL** (the Kindle Unified Application
Launcher), a computer with a USB cable, and about 100 MB free on the Kindle.
(Nooks, test build: see the steps for the [1st Edition](GZREADER.md#nook-1st-edition-test-build) and the [Simple Touch](GZREADER.md#nook-simple-touch-test-build).)

### 1. Jailbreak the Kindle and install KUAL

Turn on **airplane mode** first, so the Kindle doesn't update itself to a firmware the
jailbreak can't handle.

| Kindle | Jailbreak | KUAL file |
| --- | --- | --- |
| Kindle 2, Kindle Keyboard (3), DX | the legacy jailbreak for its firmware ([MobileRead Kindle Developer's Corner](https://www.mobileread.com/forums/forumdisplay.php?f=150)) | `KUAL-KDK-1.0.azw` → `documents` folder |
| Kindle 4, Kindle Touch | the legacy jailbreak for its firmware (same forum) | `KUAL-KDK-1.0.azw2` → `documents` folder (Kindle Touch: or the KUAL booklet with MRPI) |
| Paperwhite 3 (7th gen) | [kindlemodding.org](https://kindlemodding.org/jailbreaking/): LanguageBreak for firmware 5.14.3 – 5.16.2.1.1, older methods for older firmware | `Update_KUALBooklet_HDRepack.bin` installed with MRPI |

On the Paperwhite, see your firmware in **Settings → Device Options → Device Info**.
There is no software jailbreak for firmware **5.16.3 or newer**: a Paperwhite already on
it can only be used if it was jailbroken before updating. After jailbreaking, follow
kindlemodding.org's steps to install KUAL and MRPI
([guide](https://kindlemodding.org/jailbreaking/post-jailbreak/installing-kual-mrpi/))
and its hotfix, so a firmware update doesn't undo the jailbreak.

When it works, a **KUAL** book appears in the Kindle's library.

### 2. Download GZreader

From the [latest release](https://github.com/9retirement6irk/GZreader/releases/latest),
take the package for your Kindle (the others won't start on it):

| Kindle | Package |
| --- | --- |
| Kindle 2, Kindle Keyboard (3), DX / DX Graphite | `gzreader-kindle-legacy-<version>.zip` |
| Kindle 4, Kindle Touch | `gzreader-kindle-<version>.zip` |
| Paperwhite 3, firmware **5.16.3 or newer** | `gzreader-kindlehf-<version>.zip` |
| Paperwhite 3, firmware 5.6.1 – 5.16.2.x | `gzreader-kindlepw2-<version>.zip` |

### 3. Copy it to the Kindle

1. Connect the Kindle to the computer with USB; it shows up as a drive.
2. Unzip the package on the computer. Inside are the folders `koreader`, `extensions`
   and, in the Kindle 2/3/DX package, `launchpad`.
3. Copy those folders to the **top of the Kindle's drive** (next to `documents`),
   merging with any folders of the same name already there (KUAL's own
   `extensions` folder stays; GZreader adds `extensions/koreader`). If an old
   KOReader is installed, its `koreader` folder is replaced.
4. **Eject** the Kindle safely and unplug it.

### 4. Start GZreader

- **Any Kindle:** open the **KUAL** book, then **GZreader → Start GZreader**. (*Start
  GZreader (no framework)* stops the Kindle's own software while GZreader runs: more
  free memory, and the Kindle restarts its home screen when you exit.)
- **Kindle 2, 3, DX** also: press **Shift, G, G** (the last book), **Shift, G, L** (the
  library) or **Shift, G, N** (without the Kindle's framework).
- **Kindle Touch and Paperwhite:** after the first start, a **GZreader** book with
  GZreader's logo appears on the Kindle's own home screen; tapping it starts GZreader.

### 5. The first start

A setup guide runs. Its first page, **Connect your phone**, shows a QR code: scan it
with your phone (same Wi‑Fi as the Kindle) to connect Grimmory, Notes (Memos) and
Calendar, or to send books, or pick *Skip for now*. You can come back to it any time:
Home menu → **Send books from your phone** (on a touch Kindle: swipe down from the top
→ launcher → **Phone**). The guide then asks about the library view, tabs, sleep
screen, usage statistics, clock and reading defaults.

Books you download or send go to the **GZreader** folder at the top of the Kindle's
drive; the **Downloads** tab shows them.

### Updating

GZreader checks for a new release once a day and offers it; or open **Settings →
General → Updates**. Updating keeps your books, settings, connections and reading
progress. (Installing a newer package over USB the same way also works.)

### Uninstalling

Delete the `koreader` folder, `extensions/koreader`, `launchpad/koreader.ini` (Kindle
2/3/DX) and `documents/GZreader.sh` (Kindle Touch, Paperwhite). The **GZreader** folder
with your books stays until you delete it.

### If something goes wrong

- **GZreader isn't in KUAL:** check that `extensions/koreader` is on the drive (not
  `extensions/extensions/koreader` or inside another folder).
- **It flashes and returns to the Kindle's home screen:** most likely the package for
  another Kindle or firmware; take the one from the table above. `koreader/crash.log`
  on the drive says why.
- **The phone page doesn't open:** the phone must be on the same Wi‑Fi as the Kindle,
  and the Kindle's Wi‑Fi must be on.
- **Something else:** Settings → General → **Send diagnostic log to my phone** (or
  *Save diagnostic log*, which puts it on the drive) and attach it to an issue.

## Connecting Grimmory, Notes and Calendar

Scan the setup guide's QR code, or open it later: **Home menu → Send books from
your phone**, or **Connect with QR code** in the Grimmory, Notes or Calendar tab. The
phone page has a section for each; your phone and Kindle must be on the same Wi‑Fi,
and the page stops when you press Back on the Kindle. For single sign-on, add
`https://9retirement6irk.github.io/GZreader/oauth2-callback` as an extra redirect URI
for Grimmory's client at your identity provider, once, for every Kindle (see
[Single sign-on](GZREADER.md#single-sign-on-sso--oidc)). Grimmory itself needs no changes. Connection and sync options are in **Settings → Connections** (Grimmory, and Memos for the Notes tab);
read aloud is in **Settings → Reader**, and Wi‑Fi saving and the diagnostic log are in
**Settings → General**.

## Publishing a release

1. Bump [`GZREADER_VERSION`](GZREADER_VERSION) and add an entry to
   [`gzreader_changelog.lua`](plugins/gzreader.koplugin/gzreader_changelog.lua).
2. Create a GitHub release tagged `v<version>` and publish it.

The [release workflow](.github/workflows/gzreader-release.yml) builds and attaches the
install zip and the update package. Kindles check for new releases once a day.

To build locally:

```sh
tools/gzreader/package-kindle.sh koreader-kindle-legacy-v2026.07.1.zip out/   # or koreader-kindle-…, koreader-kindlehf-…, koreader-kindlepw2-…
```

The build reuses the native binaries of the official KOReader kindle-legacy release of
the same version and overlays GZreader's Lua code, plugins and dictionary.

## Tests and keeping up with KOReader and ZenOS

- **Tests** ([workflow](.github/workflows/gzreader-tests.yml), on every push and pull
  request, and on every upstream merge): luacheck, the plugin's tests against mock
  Grimmory, Memos and CalDAV servers, the setup guide, the Nooks' screen commands; that
  GZreader's changes to KOReader's and ZenOS's files are all still there
  ([`keeps.py`](tools/gzreader/tests/keeps.py)); and GZreader running in the emulator
  on a Kindle 3, Kindle 4, Kindle Touch, Paperwhite 3, Nook 1st Edition and Nook Simple
  Touch, checking what makes it GZreader
  ([`keeps.lua`](tools/gzreader/emulator/keeps.lua)): the setup guide, Home's tabs, the
  GZreader and Reading menus and their names (and the Menu key, never ZenOS's touch panel
  without touch), Settings' Connections, the touch launcher's entries at Home and in a
  book, the Kindle Touch's Listen, the Nook's colour screen, picture books filling the
  screen, pages turning, and menu text between 2.2 and 3.8 mm tall on the real screen. Locally: `tools/gzreader/ci-test.sh koreader-kindle-legacy-vX.zip out/`
  (Linux, with qemu), or just the tests: `tools/gzreader/tests/run.sh <unzipped koreader/>`.
- **Upstream check** ([workflow](.github/workflows/gzreader-upstream.yml), Mondays, or by
  hand from the Actions tab): compares [`tools/gzreader/UPSTREAM`](tools/gzreader/UPSTREAM)
  with KOReader's newest release that has Kindle packages and ZenOS's newest release. For
  each newer one it merges what changed upstream into GZreader
  ([`upstream.sh`](tools/gzreader/upstream.sh): three-way, keeping GZreader's changes;
  what GZreader removed stays removed) and runs the tests on the result. A clean merge
  becomes a **pull request** (a draft if a test failed) with the report and test results;
  conflicts become an **issue** listing them, with the merge as a patch. Run by hand it can
  include ZenOS pre-releases, or preview a KOReader branch such as `master` (report only).
  It needs *Settings → Actions → General → Allow GitHub Actions to create and approve pull
  requests*.
- Locally: `tools/gzreader/upstream.sh latest zenos --pre`,
  `tools/gzreader/upstream.sh merge zenos v4.3.0` (then resolve any `<<<<<<<`, test).

## What's inside

| Part | Role |
| --- | --- |
| [`plugins/gzreader.koplugin`](plugins/gzreader.koplugin) | GZreader itself: Grimmory sign-in, browser, downloads, progress, bookmark and highlight sync, Reading menu, read aloud, updater |
| [`plugins/zenos.koplugin`](plugins/zenos.koplugin) | ZenOS 4.2.0 interface, adapted for GZreader and the Kindle keyboard |
| `frontend/`, `reader.lua` | KOReader v2026.07.1 with GZreader changes (branding, keyboard, sleep screen, speed fixes) |
| [`tools/grimmory`](tools/grimmory) | Packaging, dictionary builder, release script |

## Credits and license

GZreader is built on **[KOReader](https://github.com/koreader/koreader)** (AGPL-3.0) and
**[ZenOS](https://github.com/xZenLabs/zen-os)**, and connects to
**[Grimmory](https://grimmory.org)**. The dictionary is
[Open English WordNet](https://en-word.net) (CC BY 4.0).

GZreader is free software under the [GNU Affero General Public License v3](COPYING).
KOReader's original README is kept in [README.koreader.md](README.koreader.md).
