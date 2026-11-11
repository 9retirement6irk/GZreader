For the Kindle 2 and DX (no Wi‑Fi), and any Kindle that prefers it.

The Kindle 2 and the Kindle DX have no Wi‑Fi. GZreader notices (from the
model) and syncs through a web page on a computer instead, with the Kindle
plugged in over USB: <https://9retirement6irk.github.io/GZreader/sync/>
(Chrome or Edge, on Windows, Mac, Linux or a Chromebook; other browsers can't
write to a USB drive). Any other Kindle can sync this way too: Settings →
Connections → Sync through a computer.

1. On the Kindle: Menu (the quick panel) → **Sync** → **Connect to computer (USB drive)**. KOReader turns the
   Kindle's USB drive off while it runs, so GZreader steps aside and waits;
   after you eject the Kindle it starts again by itself. (Or Menu → Exit to
   the Kindle.)
2. Plug the Kindle into the computer (unplug and plug it again if it was
   already plugged in), open the page and choose the Kindle's
   drive (or its `documents/GZreader` folder). Nothing else can be set up
   before a Kindle is chosen.
3. Enter the Kindle's **PIN**. The first time, you choose one: the sign-ins
   (Grimmory, Memos, Plex, calendars) are kept on the Kindle, encrypted with
   it, so any computer can sync the Kindle with just the PIN. (Or "Don't keep
   sign-ins on the Kindle": they last until the tab is closed.)
4. Three tabs:
   - **Connections**: Grimmory (password or single sign-on), Notes (a Memos
     access token), calendars, Plex.
   - **Content**: what to bring, browsed as in the Kindle's Catalog tab:
     Books and Audiobooks (Recently added, A–Z, Libraries, Shelves, Authors,
     Series, search) and Music (Plex albums A–Z, playlists, search). With
     audiobooks from Plex on the Kindle (Settings → Connections → Plex →
     Audiobooks), Audiobooks lists that Plex library (Recently added, A–Z,
     Authors, search); *Audiobooks from…* switches between Grimmory and the
     server's libraries on the page. Each is
     marked when it's on the Kindle or in its queue already; "Coming with the
     next sync" lists the Kindle's queue and what was chosen here.
   - **Sync**: how much room is left on the Kindle and what takes it (books,
     audiobooks, music, the library copy, notes' pictures), how much the next
     sync brings, and **Sync**.
5. Eject the Kindle and unplug it; GZreader starts again (or start it) and
   takes in what was brought ("Synced with your computer"). Books and
   audiobooks open at their place on Grimmory the first time, and Home's
   Grimmory reading stats show Grimmory's numbers as of the sync.

Sleep screen pictures: the Content tab's **Sleep screen pictures** adds your
own (made to fit the Kindle's screen, in grey) to the drive's `screensavers`
folder with the sync, takes off ones that are there, and chooses when they
show: the book's cover while reading and a picture from Home and menus, or a
picture always. Any picture the browser can open works, and iPhone photos
(HEIC/HEIF) too in every browser: the page converts them itself, in the
browser (the photo isn't sent anywhere), with
[libheif](https://github.com/strukturag/libheif) (LGPL 3.0), which it loads
only when you add one (about 2 MB, once).

GZreader sends no usage statistics. If an older GZreader (up to 1.28.1) left
some in `.gzsync/usage/`, the page deletes them without sending them.

## Sending diagnostics to the developer

A Kindle without Wi‑Fi sends its diagnostic log through the page, the same
report a Wi‑Fi Kindle sends with **Send to the developer**:

- **On the Kindle:** Diagnostics (quick panel) → **Send to the developer (at
  the next sync)**, or Settings → General → Advanced → Send diagnostic log to the
  developer. A box asks what you were doing and what went wrong; the log and
  what you typed are saved in `.gzsync/reports/` (the newest three). At your
  next sync the page sends them and deletes them; if it can't reach the
  developer, they wait for the next sync.
- **On the page:** the Sync tab's **Diagnostics** box. Type what happened and
  press **Send to the developer**: the page sends the Kindle's log with it
  (and any reports the Kindle saved). With diagnostic logging on, pressing
  **Sync** in the Kindle's quick panel exports a fresh, complete log first
  (`.gzsync/reports/latest.txt`), and the page sends that one; otherwise it
  reads `koreader/gzreader.log` and the tail of `crash.log` from the drive.
  Use this when the Kindle can't get as far as its menus.

Passwords and tokens are never in the log; it can name books and files.
Reports go to the developer's report feed, like a Wi‑Fi Kindle's, tagged
`sync-page` ([Privacy and diagnostics](Privacy-and-Diagnostics#diagnostic-log)).

**Test mode**: <https://9retirement6irk.github.io/GZreader/sync/?test> works
with a pretend Kindle kept in the browser, to try the page (and your
connections) without a Kindle.

The PIN: the sign-ins file (`.gzsync/keys.json`) is encrypted with AES-256-GCM
under a key made from the PIN (PBKDF2-SHA-256, 600 000 rounds). Grimmory's
password is never kept, only its sign-in token. Someone who has the Kindle and
time could try every short PIN, so a longer one is safer. GZreader on the
Kindle never reads the file. Forgot the PIN: "Start over" deletes the file;
connect again.

Updates: when a newer GZreader is out, the page offers it ("Update GZreader
on the Kindle to …", on by default) and brings it with the sync; GZreader
installs it as it starts, restarts, then takes in the rest. The page fetches
the update from the repository's `updates` branch, which the release workflow
fills (GitHub's release downloads can't be read by a web page). If it isn't
there yet, download `gzreader-update.zip` from the latest release and add it
with **Use a downloaded update file…**. The page checks the file is a GZreader
update, and its size and SHA-256 when it fetched it itself.

What a sync does:

| | Kindle → computer | Computer → Kindle |
| --- | --- | --- |
| Grimmory | Reading positions (with their exact place for the web reader), reading time, ratings, bookmarks, highlights and notes made, changed or deleted, books put on or taken off your shelves | A copy of your library for the Grimmory tab: every book and audiobook, libraries, shelves (which are yours, and the books on them: the book menu's [Add to shelf](Grimmory-Library#putting-a-book-on-a-shelf)), Continue reading, Recently added, small covers, book descriptions, where you are in the books on the Kindle elsewhere, and their bookmarks and highlights |
| Downloads | The **sync queue**: in the Catalog tab, Download (or an audiobook's Add to sync queue) puts a book there | The books and audiobooks in the queue or chosen on the page, and new books on the auto-download shelf (up to 20 a sync) |
| GZreader | Its version | A newer GZreader, installed at the next start |
| Notes | Notes written, edited, ticked or pinned on the Kindle | Your notes (the synced tags, as many as Settings → Notes keeps) and their pictures |
| Calendars | | Calendar links, CalDAV calendars and `.ics` files, as the Calendar tab's events |
| Music | | The Plex albums and playlists chosen on the page, and Plex audiobooks (Kindles with a speaker or headphone jack) |

What's already on the Kindle is never brought again: the page shows it as **On the Kindle**, and a pick that reached the Kindle another way (a sync from another computer, a download over Wi‑Fi) comes off the page's list, so it doesn't come back after you delete it from the Kindle.

The Catalog tab works from the copy: browse, search, Libraries, Shelves,
Authors and Series, a book's page with its description. Download puts the
book in the sync queue (a book's page says "Add to sync queue"; selecting a
queued book offers to take it off; Settings → Connections → Sync through a
computer → Sync queue lists them). The quick panel's **Sync** tile shows the
steps, what's waiting to be sent and the queue, with **Exit GZreader now**.

Bookmarks and highlights sync as with Wi-Fi, a sync later: what you add,
change or delete on the Kindle is kept in a journal (`.gzsync/journal.jsonl`,
in order) that the page sends to Grimmory; something made on the Kindle gets
a temporary id until then, and Grimmory's own after the next start. The page
brings each downloaded book's bookmarks and highlights, which GZreader
compares and merges when the book opens (a highlight changed in both places
since the last sync is left as it is in each, as with Wi-Fi).

Covers: Grimmory doesn't let other web pages read its covers (only show
them), so the page takes an EPUB's cover from the book itself and an
audiobook's from its audio cover; PDFs and comics have no cover in the copy.

Calendars: many calendar servers (Google, Proton) don't let a web page read
their links, and most CalDAV servers don't either. The page says so; then
save the calendar as an `.ics` file and add the file instead (the page
remembers it and reads it again at each sync: keep it up to date where it is).

How it works: GZreader writes `documents/GZreader/.gzsync/outbox.json`
whenever it saves its settings (the requests to send to Grimmory, ready-made,
the queue, what's on the Kindle, the notes written here). The page writes the
library copy (`library.json`, `covers/`, `details/`, and `marks/`: each
book's bookmarks and highlights in a file of its own), the books and audio
under `in/`, and `inbox.json` last; at the next start GZreader takes them in,
moves the books into the GZreader folder, prepares M4B/M4A audio (as for a
download) and deletes the inbox. The page prepares M4B/M4A audiobooks and
music itself, on the computer (the same pieces GZreader would make), so the
Kindle has nothing to convert; only if that fails does the file go to the
Kindle as it is, for GZreader to prepare. The download waits in the
browser's own storage meanwhile, so leave some room on the computer (as much
as the biggest audiobook). Syncing twice before starting GZreader adds
to the same inbox. On the Kindle, the library copy is read into memory only
while it's used (browsing the Grimmory tab, a book's sync) and let go a minute
after, and as soon as a book starts to open, so a DX keeps that memory for
the book. Nothing is sent anywhere but your own servers (and
plex.tv for the Plex sign-in). The page is plain HTML and JavaScript in
`docs/sync/` and can be hosted anywhere on HTTPS.
