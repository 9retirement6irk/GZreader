# BookOrbit

GZreader can use [BookOrbit](https://github.com/bookorbit/bookorbit) as its book server instead of Grimmory. You pick one or the other when you sign in; a Kindle is signed in to one book server at a time.

**This is the first part.** What works with BookOrbit today:

| | |
|---|---|
| Browse the Catalog: all books, libraries, collections (as shelves), SmartScopes (as magic shelves), authors, series, search | yes |
| Covers | yes |
| Download books (EPUB, PDF and the other formats the Kindle opens) | yes |
| Auto-download a shelf (a BookOrbit collection) | yes |
| Reading progress | not yet |
| Highlights, notes, bookmarks | not yet |
| Reading statistics, read status, ratings | not yet |
| Putting books on collections from the Kindle | not yet |
| Audiobooks | not yet |
| Kindles without Wi-Fi (the sync page) | not yet |

Until the "not yet" rows are done, nothing you do on the Kindle is sent to BookOrbit: it only reads your library.

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

- The books you downloaded from the other server **stay on the Kindle** in `GZreader/books` and stay listed in the Downloads tab, and they open as before. What they lose is the tie to a book on the server: the Catalog doesn't mark them as downloaded and nothing is synced for them. Sign in to that server again and the tie is back. (Matching them to the same books on the new server, by the file's fingerprint, is planned with reading progress.)
- Covers and saved lists are kept apart for each server.
- Progress waiting to be sent to the old server is dropped.

## If it doesn't connect

- **"Wrong user name or password…"**: it wants the KOReader sync ones (above). The same message appears if the address is another server's, such as Grimmory's.
- **"BookOrbit has sync switched off…"**: switch sync on for that user in BookOrbit's Settings → KOReader.
- **"That address answered, but not as BookOrbit"**: check the address; an old BookOrbit may not have the e-reader catalog.
- Send the diagnostic log (Settings → Privacy and diagnostics) if it's something else: look for lines starting `BookOrbit`.
