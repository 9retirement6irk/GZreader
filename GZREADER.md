# GZreader — Grimmory + ZenOS + KOReader for the Kindle Keyboard

A trimmed KOReader for legacy Kindles (Kindle 2, DX, Kindle Keyboard / K3)
that reads books, pulls them from a [Grimmory](https://grimmory.org) server
and keeps reading position and bookmarks in sync with it. ZenOS is the
interface. Releases and updates: <https://github.com/9retirement6irk/GZreader>.

Based on KOReader `v2026.07.1` and ZenOS `4.2.0`. Version: see `GZREADER_VERSION`.

## What's in it

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface (Home, Downloaded, navbar). English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `grimmory.koplugin` | GZreader itself: QR sign-in, library browser, downloads, progress + bookmark sync, Reading menu, read aloud, updates. |

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
   `plugins/grimmory.koplugin/grimmory_changelog.lua`, push.
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
books, `.sdr` folders, history and the Grimmory folder are never touched; if
anything fails, the previous files are put back. Then GZreader restarts.

## Keyboard (Kindle 3)

| Where | Key | Does |
| --- | --- | --- |
| Home / lists | Alt + Q, W, E, R, T | Switch the bottom tabs, counted from the left: Alt+Q Home, Alt+W Downloaded, Alt+E Continue, Alt+R Grimmory, Alt+T Favorites (Alt + the top row is how the Kindle Keyboard types 1–9). Also works from the Grimmory browser. |
| Any list or menu | Q, W, E, … | Pick the entry with that letter (shown next to it), in lists, the ZenOS settings and KOReader's menus. |
| KOReader's menus | Alt + Q, W, E, … | Switch the menu's tabs. |
| Home / lists | Menu | GZreader menu: Grimmory library, continue reading, audiobooks, search, history, Wi‑Fi, Settings (the Settings page), KOReader settings, updates, send log, sleep, restart, ZenOS quick panel, exit. Replaces ZenOS's touch quick-settings panel (switch: Grimmory → Menu key opens the GZreader menu). |
| Reading | Menu | Reading menu: contents, bookmarks, bookmark this page, go to page, search, read aloud, fonts, sync, dictionary, page browser, book info, all settings, close book. |
| Reading | Hold Menu | ZenOS page browser. |
| Reading | AA | Fonts and layout. |
| Reading | Shift + Sym | Read aloud / stop. |
| Reading | Back | Return from a followed link or TOC jump; otherwise go to Home. |

## Connect to Grimmory

Open the **Grimmory** tab. All Grimmory options (connection, sync, bookmarks,
read aloud, diagnostic log, updates) are in **Settings → GZreader**
(also KOReader → Tools → Grimmory).

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

## Subtitles

Grimmory's subtitle is added to the title ("Diary of a Wimpy Kid: Old
School") in the Grimmory lists and, for downloaded books, as KOReader custom
metadata (`.sdr/custom_metadata.lua`, like Book information → edit title),
so Home, Downloaded, history and the reader show it. The app API's lists have
no subtitles, so they come from the library index (Grimmory's web book list,
`/api/v1/books/page`) and from the book itself after a download. Titles you
edited yourself are left alone.

## Home folder and downloads

The Grimmory folder (`documents/Grimmory`) is the home folder; the
**Downloaded** tab shows it. Books download in a background process with a
progress bar (percentage, MB received of the total; the Kindle stays awake
until it's done). Picking more books while one downloads queues them; they
download one after another (lists show "queued"; the download options can
empty the queue) (press any key for Stop / Continue in background / Keep
watching); a transfer that stalls for 90 s is stopped.

A backup list of downloaded books (`.gzreader-library.json`) is kept in the
Grimmory folder. If KOReader's settings are lost (for example the `koreader`
folder was replaced), the books are re-linked to Grimmory from it, or by file
name from the library index, so progress sync and "on Kindle" marks keep
working.

## Progress sync

Native: Grimmory's own reading-progress API (the web reader's), not its
KOReader-compatible endpoint.

- Books downloaded through the Grimmory tab, matched by Grimmory book ID.
- EPUB: chapter (spine file), position in the chapter and whole-book
  percentage. PDFs/comics: page. FB2/MOBI/AZW3: percentage.
- Pulled on open and wake; pushed every 10 page turns (or 3 minutes), on
  close and on sleep. Forward moves from other devices apply silently; going
  back asks. Offline updates are queued and sent when Wi‑Fi returns.
  Sync jumps are not added to the Back history.
- Reading sessions (30 s or longer) go to Grimmory's reading statistics.

## Bookmark sync

Page bookmarks are kept the same on the Kindle and in Grimmory (web reader,
other devices), both ways, including deletions. EPUB bookmarks are converted
between KOReader's XPointers and Grimmory's EPUB CFIs using the book's own
XHTML (paragraph precision); PDF/comic bookmarks use the page number.
Bookmarks made offline are sent later. Synced on open and with "Sync with
Grimmory now". Highlights and notes are not synced. Switch: Grimmory menu →
Sync bookmarks.

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
asks whether you heard it; the request shape is then saved. The speech
service doesn't report when a sentence ends, so the next sentence starts
after a time computed from its length and the speed setting (Read-aloud
settings → Slower / Faster). The diagnostic log records every step.

## Audiobooks (experimental)

Grimmory tab → Audiobooks, or Settings → GZreader → Audiobooks.
Pick one to download it to `Grimmory/Audiobooks/<id>/` (single M4B file,
converted for the Kindle, or one file per track for folder audiobooks), then the player opens:

| Key | Does |
| --- | --- |
| 5-way press / Space | Play / pause |
| Left / Right | Back / forward 30 s |
| Up / Down | Previous / next chapter |
| Menu | Chapters, sleep timer (15/30/60 min, end of chapter), volume, stop |
| Back | Close the screen (keeps playing; reopen from Grimmory → Audiobooks → Now playing) |
| Volume buttons | Volume |

Position syncs with Grimmory's audiobook progress (same fields as its web
player: position in the track and track index), every minute while
playing, on pause and on stop; offline updates are queued. The Kindle
doesn't go to sleep while audio plays; pressing the power button pauses.

Playback uses what the Kindle 3 has: GStreamer 0.10 (`gst-launch-0.10`)
with Freescale's hardware decoders `mfw_mp3decoder` and `mfw_aacdecoder`,
into ALSA. MP3 starts anywhere (the file is fed from the right byte offset).
There is no MP4 demuxer on the Kindle, so an M4B is converted once after
download (`grimmory_mp4.lua`: each AAC frame gets an ADTS header; no
re-encoding) into ~15-second pieces in `<file>.chunks/`; playback starts at
the piece holding the position and feeds the following ones to the AAC
decoder. **Test audio playback** tries the pipelines with a short MP3 and an
AAC tune (converted from the bundled M4A, which also tests the converter),
asks which you heard and remembers it.

Downloads use Grimmory's audiobook stream endpoints and resume with HTTP
Range after a dropped connection or timeout.

## Sleep screen

While a book is open: its cover. From Home and menus: a random picture from
the USB drive's `screensavers` folder (created by the setup guide), falling
back to the Kindle's own sleep pictures. Chosen in the setup guide; picking
another option there restores KOReader/ZenOS's own sleep-screen settings.

## Wi-Fi only when needed

On by default (Settings → GZreader → Wi-Fi only when needed). GZreader turns
Wi-Fi on by itself when it needs the network and off again after a minute
unused, as long as nothing still needs it (an open Grimmory browser, a
download or its queue, the library index, a QR screen, an update download).

| When | Wi-Fi |
| --- | --- |
| Browsing Grimmory, downloading, connecting, sending the log, checking for / installing updates | turned on ("Connecting to Wi-Fi…") |
| A Grimmory book opens | turned on quietly: pull the position, send queued changes, sync bookmarks |
| A book closes with unsent changes | turned on quietly to send them |
| Wake after 15 min or more with a book open | turned on quietly to pull the position |
| Page turns, bookmarks, sleep | not turned on: changes wait for the next sync |
| Daily update check, library index refresh | only if Wi-Fi is already on |

Wi-Fi you turned on yourself is never turned off. Going to sleep turns off
Wi-Fi GZreader turned on.

## Speed on the Kindle 3

- Covers are pre-sized (Settings → GZreader → Pre-size covers). ZenOS scales
  every cover to the exact size of where it's shown; on the Kindle 3 that took
  ~4 s of CPU per Home screen (the cover strip), and its memory cache starts
  empty after every restart. GZreader keeps each final-size cover as a raw
  bitmap in `koreader/cache/gz-covers/` (used only while the book file is
  unchanged), learns the sizes ZenOS uses, and a low-priority background
  process (`grimmory_coverwarm.lua`) makes them for every downloaded book a
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

**Send it to your phone:** Settings → GZreader → Send diagnostic log
to my phone (QR code). Scan the code (same Wi-Fi), tap Download, then attach
the file wherever you need it.


`koreader/grimmory.log` (rotates at 512 KB): requests with status and timing,
pairing, SSO, downloads, sync, bookmarks, updates, read aloud. Passwords and
tokens are never written. Grimmory → Save diagnostic log copies it, the tail
of `crash.log` and a read-only audio/speech survey next to the Grimmory
folder.

## Rebuild the package

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua and shell scripts, so the script overlays it onto
the official release built from the same tag rather than rebuilding the
native toolchain.
