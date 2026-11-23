# BookOrbit

GZreader can use [BookOrbit](https://github.com/bookorbit/bookorbit) as its book server instead of Grimmory. You pick one or the other when you sign in; a Kindle is signed in to one book server at a time.

What works with BookOrbit today:

| | |
|---|---|
| Browse the Catalog: all books, libraries, collections (as shelves), SmartScopes (as magic shelves), authors, series, search | yes |
| Covers | yes |
| Download books (EPUB, PDF and the other formats the Kindle opens) | yes |
| Auto-download a shelf (a BookOrbit collection) | yes |
| Reading progress, both ways (the exact page; BookOrbit converts it for its web reader) | yes |
| Books already on the Kindle matched to BookOrbit's (by the file's fingerprint) | yes |
| Highlights and the notes on them, both ways (EPUB and other reflowable books) | yes |
| Page bookmarks (dog-ears), both ways (EPUB and other reflowable books) | yes |
| Reading statistics, read status, ratings | not yet |
| Putting books on collections from the Kindle | not yet |
| Audiobooks: list, covers, download with resume, chapters, listening position both ways (needs an API key, below) | yes |
| Kindles without Wi-Fi (the sync page) | not yet |

Only the "yes" rows send anything to BookOrbit. The Kindle shows up in BookOrbit's Settings → KOReader → Devices as "GZreader" and its model.

## What you need in BookOrbit

BookOrbit gives e-readers their own sign-in, separate from the one for its website:

1. In BookOrbit, open **Settings → KOReader**.
2. Make a KOReader sync user name and password, and leave sync switched on.

That user name and password are what GZreader asks for. Your website user name, password or single sign-on won't work here.

## Signing in

Any of these:

- **The setup guide** (on the first start, or Settings → General → Setup Guide): answer **With BookOrbit, my book server** to *How will you use GZreader?*, then *Set up from a browser* or *Type my BookOrbit login here*.
- **The setup page** (Settings → Accounts and services → Books → Connect from your browser, then scan the code): under **Book server**, choose **BookOrbit**, then enter BookOrbit's address and the KOReader sync user name and password.
- **On the Kindle**: Settings → Accounts and services → Books → **Connect to BookOrbit by typing**.
- **In the Catalog**, when you aren't signed in: the server tile at the bottom → **Connect to BookOrbit by typing**.

GZreader keeps the server's address, the user name and a fingerprint (MD5) of the password, which is what BookOrbit's e-reader sign-in uses. The password itself is never stored, and nothing of the sign-in is written to the log. On a Kindle or Kobo the fingerprint is kept on the device's own disk, not on the USB drive.

## Moving from Grimmory, or back

Signing in to BookOrbit signs this Kindle out of Grimmory (and the other way round). Each server numbers its books differently, so:

- The books you downloaded from the other server **stay on the Kindle** in `GZreader/books` and stay listed in the Downloads tab, and they open as before.
- **Signing in to BookOrbit matches them to its books** by each file's fingerprint (the same one KOReader's own sync uses). A book BookOrbit has becomes its download: marked in the Catalog, its progress synced, whatever the file is called. It happens in the background after sign-in and whenever the library list is refreshed. A file that differs from BookOrbit's copy (some servers write the cover or details into the file when you download it) doesn't match: it stays a plain book on the Kindle, and downloading it again from BookOrbit gives you the synced one.
- Going back to Grimmory, its own list of downloads returns as it was.
- Covers and saved lists are kept apart for each server.
- Progress waiting to be sent to the old server is dropped.

## Reading progress

- Sent while you read (every few pages), when you close the book and when the Kindle sleeps; kept and sent later if Wi-Fi is off.
- When you open a book, GZreader looks at where BookOrbit has it. Further on: it goes there. Earlier (another device went back): it asks.
- Sync now, in the book's quick panel, does the same on request.
- BookOrbit shows the percentage KOReader shows in its footer.

## Highlights and notes

- A highlight made on the Kindle, with its colour, style and note, appears in BookOrbit's web reader. One made, changed or removed in BookOrbit appears, changes or goes on the Kindle.
- When: a few seconds after a book opens, a few seconds after you change a highlight (with Wi-Fi on), on Sync now, and when the book closes if something is waiting.
- Reflowable books only (EPUB, and the others the Kindle lays out itself). Highlights in PDFs stay on the Kindle.
- If BookOrbit can't place a highlight in your copy of the book, it is skipped; the log line `BookOrbit highlights … couldn't be placed` counts them.
- To switch it off: Settings → Accounts and services → Books → Sync highlights and notes.

## Bookmarks

- A page you dog-ear on the Kindle appears among the book's bookmarks in BookOrbit; one made on another device dog-ears its page here; removing one on either side removes it on the other.
- When: as a book opens, a few seconds after you add or remove a bookmark, and on Sync now.
- Reflowable books only, and only if your BookOrbit offers bookmark sync (GZreader asks at sign-in; sign in again after updating BookOrbit).
- The same switch as for Grimmory's bookmarks, in Settings → Accounts and services → Books.

## Audiobooks

BookOrbit keeps its audiobook routes apart from the e-reader sign-in, so audiobooks need a second credential: an **API key**.

1. In BookOrbit: **Settings → API keys**, make a key with **read and write** access. BookOrbit shows it once (it starts with `bok_`).
2. Give it to the Kindle, either on the setup page (under the BookOrbit connection: *API key for audiobooks*) or on the Kindle: Settings → Accounts and services → Books → **BookOrbit API key (audiobooks)**.

Then the Catalog's Audiobooks page lists BookOrbit's audiobooks. Downloading, chapters and playing work as with Grimmory's; an interrupted download continues where it stopped. Where you stopped listening is sent to BookOrbit and, when you start an audiobook, taken from it if BookOrbit's place is more than a minute from the Kindle's.

- The key is checked when you enter it, kept on the Kindle's own disk, never shown again and never written to the log.
- BookOrbit's keys expire (90 days unless you choose otherwise). When one does, the Audiobooks page says BookOrbit didn't accept the key: make a new one and enter it.
- A read-only key lists and downloads, but your place isn't saved.
- To remove the key from the Kindle, save the box empty. Signing out removes it too.
- Audiobooks from Plex are separate and still work alongside.

## If it doesn't connect

- **"Wrong user name or password…"**: it wants the KOReader sync ones (above). The same message appears if the address is another server's, such as Grimmory's.
- **"BookOrbit has sync switched off…"**: switch sync on for that user in BookOrbit's Settings → KOReader.
- **"That address answered, but not as BookOrbit"**: check the address; an old BookOrbit may not have the e-reader catalog.
- Send the diagnostic log (Settings → Privacy and diagnostics) if it's something else: look for lines starting `BookOrbit`.
