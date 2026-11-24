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
| Reading time (the pages you read, from KOReader's statistics) | yes |
| Ratings, both ways | yes |
| Setting a book's read status from the Kindle | not yet (BookOrbit works it out from your progress) |
| Putting books on your collections and taking them off, from a book's menu (needs an API key, below) | yes |
| Audiobooks: list, covers, download with resume, chapters, listening position both ways (needs an API key, below) | yes |
| Genres on the Catalog's Books and Audiobooks pages (BookOrbit's genres; needs an API key, below: its e-reader catalog has none) | yes |
| A magazine library: the Catalog's Magazines page, drawn as a magazine stand, and kept off the Books page ([Magazines](Grimmory-Library#magazines)) | yes |
| Requesting a book or audiobook BookOrbit doesn't have, and seeing what became of it (needs an API key, below) | yes |
| Home's reading stats widget and the reading stats page, from BookOrbit's numbers ([Home and bookshelves](Home-and-Bookshelves#reading-stats-on-home)) | yes |
| Home's recently read from every device, also what isn't on this Kindle ([Home and bookshelves](Home-and-Bookshelves#recently-read-on-every-device)) | yes (audiobooks: with an API key) |
| Kindles without Wi-Fi (the sync page) | not yet; the server side can be set up now, see [below](#kindles-without-wi-fi-letting-the-sync-page-in) |

In the Catalog, BookOrbit's collections are on the **Collections** card (Grimmory's shelves are on a card called Shelves): it lists your collections and, marked *SmartScope*, your SmartScopes.

Only the "yes" rows send anything to BookOrbit. The Kindle shows up in BookOrbit's Settings → Devices → KOReader → Devices as "GZreader" and its model.

## What you need in BookOrbit

BookOrbit gives e-readers their own sign-in, separate from the one for its website:

1. In BookOrbit, open **Settings → Devices → KOReader**.
2. Make a KOReader sync user name and password, and leave sync switched on.

That user name and password are what GZreader asks for. Your website user name, password or single sign-on won't work here.

## Signing in

Any of these:

- **The setup guide** (on the first start, or Settings → General → Setup Guide): answer **With BookOrbit, my book server** to *How will you use GZreader?*, then *Set up from a browser* or *Type my BookOrbit login here*.
- **The setup page** (Settings → Accounts and services → Books → the first row → Connect from your browser, then scan the code): on its **Books** tab, under **Book server**, choose **BookOrbit** (the heading changes to BookOrbit and the form to BookOrbit's). Enter BookOrbit's address, then either paste an **API key** and press **Connect with the API key** (the easy way: see [Signing in with just an API key](#signing-in-with-just-an-api-key)), or open **Use the KOReader sync user name and password instead**. There is no single sign-on for BookOrbit: its e-reader sign-in doesn't have one.
- **On the Kindle**: Settings → Accounts and services → Books → **Connect to BookOrbit by typing**.
- **In the Catalog**, when you aren't signed in: the server tile at the bottom → **Connect to BookOrbit by typing**.

GZreader keeps the server's address, the user name and a fingerprint (MD5) of the password, which is what BookOrbit's e-reader sign-in uses. The password itself is never stored, and nothing of the sign-in is written to the log. On a Kindle or Kobo the fingerprint is kept on the device's own disk, not on the USB drive.

## Moving from Grimmory, or back

Signing in to BookOrbit signs this Kindle out of Grimmory (and the other way round). Each server numbers its books differently, so:

- The books you downloaded from the other server **stay on the Kindle** in `GZreader/books` and stay listed in the Downloads tab, and they open as before.
- **Signing in to BookOrbit matches them to its books** by each file's fingerprint (the same one KOReader's own sync uses). It happens a couple of seconds after you sign in and again whenever Wi-Fi comes on; until then the Catalog still offers Download for them. Only the very same file matches: if BookOrbit holds a different copy of the book (another edition, or a file its import rewrote), download it from BookOrbit once. A book BookOrbit has becomes its download: marked in the Catalog, its progress synced, whatever the file is called. It happens in the background after sign-in and whenever the library list is refreshed. A file that differs from BookOrbit's copy (some servers write the cover or details into the file when you download it) doesn't match: it stays a plain book on the Kindle, and downloading it again from BookOrbit gives you the synced one.
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

## Reading time and ratings

- **Reading time:** the pages you read and how long each took (KOReader's own reading statistics) are sent to BookOrbit a few seconds after a book closes, and at most every ten minutes otherwise. BookOrbit builds its reading sessions and activity from them. Rows it already has are ignored, so nothing counts twice. Only books that are BookOrbit's are sent, and only if reading statistics are on (the default).
- **Ratings:** the stars you give a book on the Kindle are set in BookOrbit; a rating made in BookOrbit is taken on the Kindle when you haven't rated the book here.
- The Home screen's Grimmory statistics widget stays empty with BookOrbit: it reads Grimmory's own numbers.

## The API key: what to tick

One key covers everything GZreader uses a key for. In BookOrbit: **Settings → You → API keys → Create API key**.

| On BookOrbit's page | Choose | Why |
|---|---|---|
| Name | anything that says where it's used, such as "Kindle" | so you know which key to delete if the Kindle is lost |
| Expires after | your choice. With **Never** there's nothing to redo; with a date, audiobooks, collections and requests stop on that day until you enter a new key (books and their syncing carry on) | |
| Access | **Read and write** | saving where you stopped listening, changing collections, requesting books, and making a sync sign-in all change something. **Read only** is enough just to list and download audiobooks |
| Libraries | **All my libraries**, or at least the ones with your audiobooks | the key sees only the libraries it's given |
| Administrator access | **off** | GZreader never needs it |
| Extra permissions → Devices & Access → **KOReader sync** | tick it to [sign in with just the key](#signing-in-with-just-an-api-key) | lets the key read (or make) your KOReader sync sign-in |
| Extra permissions → Book Requests → **Request books** | tick it to [request books](#book-requests) from the Kindle | |
| Every other extra permission | leave unticked | GZreader doesn't use them. Audiobook files download without **Download books**; **Auto-approve requests**, **Download books directly** and **Manage book requests** change what your requests may do in BookOrbit, not what the Kindle can ask |

Which feature needs what:

| On the Kindle | Access | Extra permission |
|---|---|---|
| Audiobooks: listing and downloading | Read only | none |
| Genres | Read only | none |
| Audiobooks: where you stopped listening | Read and write | none |
| Adding books to collections and taking them off | Read and write | none |
| Requesting books, My book requests | Read and write | Request books |
| Signing in with just the key | Read only when you already have a sync sign-in; Read and write to have one made | KOReader sync |

A key never gets more than your own account has: if your account can't request books, ticking the box doesn't change that. This is from BookOrbit 3.9's source; if a later BookOrbit refuses something, the Kindle's message says which.

## BookOrbit's KOReader settings

In BookOrbit's **Settings → Devices → KOReader**, for the sync sign-in the Kindle uses:

| Setting | For GZreader | Why |
|---|---|---|
| **Progress sync** | **on** | off, the Kindle can't sign in at all |
| **Hide audiobook-only books** | either | GZreader leaves audiobook-only books out of its book lists anyway and lists audiobooks through the API key. On (BookOrbit's default) makes the book lists a little quicker to fetch |
| **Read-aloud EPUB delivery** | **Automatic** (BookOrbit's default) or **Text-only EPUB** | a Kindle can't play an EPUB's narration, and the original files with narration are much bigger. Automatic sends the text-only copy when it can and the original otherwise; Text-only refuses a book it can't make a safe copy of. With **Original EPUB with narration** every such book arrives at full size |

When the Kindle makes the sync sign-in itself (signing in with just an API key, on an account with none), it sends only a user name and a password, so these stay on BookOrbit's defaults: Progress sync on, audiobook-only books hidden, delivery Automatic. It never changes a sign-in that exists: those settings are shared with your other e-readers. If the key can see the sign-in and delivery is set to Original, the setup page says so and where to change it.

## Signing in with just an API key

Instead of the KOReader sync user name and password, the Kindle can be given only BookOrbit's address and an **API key**:

1. In BookOrbit: **Settings → You → API keys → Create API key**, filled in as in [The API key](#the-api-key-what-to-tick) below (it needs **KOReader sync** ticked). BookOrbit shows it once.
2. On the Kindle, open the setup page (Settings → Accounts and services → Books → Connect with QR code) and scan the code with your phone.
3. On the **Books** tab choose **BookOrbit** as the book server, enter its address, paste the key into **BookOrbit API key** and press **Connect with the API key**. The page then says *Connected to BookOrbit as …*.

What the Kindle does with the key:

- It asks BookOrbit for your KOReader sync sign-in (the same one BookOrbit puts in its own "preconfigured plugin" download) and signs in with that. Your other e-readers aren't affected.
- If your account has no KOReader sync sign-in yet, the Kindle makes one, named after your account, with a long random password. You never need that password; if you want to use the sign-in on another device, set a password of your own in BookOrbit (Settings → KOReader), then sign the Kindle in again.
- The key is kept for audiobooks, collections and book requests, so there's nothing more to enter.

If BookOrbit says the key can't see the sync sign-in, the key was made without **KOReader sync**. If it says the sync password must be saved once more, your sync sign-in is older than BookOrbit's preconfigured download: set the sync password again in BookOrbit (the same one is fine), or sign in with the user name and password.

## Audiobooks

BookOrbit keeps its audiobook routes apart from the e-reader sign-in, so audiobooks need a second credential: an **API key**.

1. In BookOrbit: **Settings → You → API keys → Create API key**, filled in as in [The API key](#the-api-key-what-to-tick) below. BookOrbit shows it once (it starts with `bok_`).
2. Give it to the Kindle, either on the setup page (under the BookOrbit connection: *API key (audiobooks, collections, book requests)*) or on the Kindle: Settings → Accounts and services → Books → **Connected to BookOrbit as …** → **BookOrbit API key**.

Then the Catalog's Audiobooks page lists BookOrbit's audiobooks. Downloading, chapters and playing work as with Grimmory's; an interrupted download continues where it stopped. Where you stopped listening is sent to BookOrbit and, when you start an audiobook, taken from it if BookOrbit's place is more than a minute from the Kindle's.

Which books count as audiobooks: every book with at least one audio file (M4B, MP3, M4A, FLAC, OGG or Opus), in any library the API key may see. A book with both an EPUB and audio files is on the Books pages as an ebook and on the Audiobooks page as an audiobook. A read-aloud EPUB on its own (narration inside the EPUB, no separate audio files) isn't an audiobook here: the Kindle can't play that narration, so it's a book, and BookOrbit sends it text-only unless you chose "Original EPUB with narration".

The same key lets the Kindle change your **collections**: a book's menu gets *Add to shelf* and *Remove from shelf*, listing the collections that are yours (not ones shared with you). A change shows on the Kindle at once and is sent to BookOrbit when there's Wi-Fi. Without the key, collections can still be browsed and auto-downloaded; the menu says where to enter the key.

## Book requests

If your BookOrbit has requests set up, the Kindle can ask for a book it doesn't have. This uses the API key, which needs **Request books** ticked when you make it (and your account allowed to request books).

Signed in to BookOrbit, the Catalog has a **Requests** page, the last of its
pages (swipe past Books, or Music on Kindles that play audio).

1. Catalog → **Requests** → **Request a book…**.
2. Type the title and, if you like, the author, then choose **Book** or **Audiobook**.

In the Bookshelf view the page is the shop's **order desk**:

- **On order**: each request still on its way is an order slip clipped to a rail, with its title, author, book or audiobook, four dots for how far it is (asked, approved, being found, in the library) and its state stamped below.
- **Arrived**: what came in stands on the shelf, a book as its cover and an audiobook as a cassette.
- **The counter**: the order pad is **Request a book…**; the **Didn't arrive** drawer holds what was declined, cancelled or failed.
- When there are more than fit, a **+N more** tag (or the row's sign) opens that group as a list.
- On a colour Kindle the stamps' frames are in colour: amber waiting, blue on its way, green arrived.
- On Kindles with keys, the 5-way moves between the slips, the shelf and the counter, and the letters open them.

In the other views the page is a list of what you asked for with its state (waiting for approval, approved, searching, downloading, in the library, declined…). Either way, tap one for its details and any note from whoever decided; one that isn't finished can be cancelled there. If someone already asked for the same book, you're added to their request. When a request arrives it's in the Catalog like any other book (use **Rebuild library** if it isn't showing yet). The list is BookOrbit's each time: nothing about requests is kept on the Kindle.

- When you save a key on the setup page, the page says BookOrbit accepted it and what the key can do: whether it may request books and whether it could sign in by itself. A box left unticked in BookOrbit shows there at once.
- The key is checked when you enter it, kept on the Kindle's own disk, never shown again and never written to the log.
- BookOrbit's keys expire (90 days unless you choose otherwise). When one does, the Audiobooks page says BookOrbit didn't accept the key: make a new one and enter it.
- A read-only key lists and downloads, but your place isn't saved.
- To remove the key from the Kindle, save the box empty. Signing out removes it too.
- Audiobooks from Plex are separate and still work alongside.

## Kindles without Wi-Fi: letting the sync page in

The Kindle 2 and DX have no Wi-Fi, so they sync through GZreader's sync page: a web page, open in a browser on your computer, that talks to your book server and writes to the Kindle over USB. **The sync page doesn't work with BookOrbit yet.** This section is the part you do on your server, and it can be done ahead of time.

The page is served from `https://9retirement6irk.github.io`. A browser only lets a page from one site call a server on another when that server says so in its answers, and BookOrbit doesn't say so: it's built to be used from its own address. So the reverse proxy in front of BookOrbit has to add the headers for that one site, and answer the browser's question-before-the-request (an `OPTIONS` request) itself. The same thing is needed for [Immich from the sync page](Home-and-Bookshelves#immich-from-the-sync-page).

What the rule does and doesn't do:

- It lets pages from `https://9retirement6irk.github.io`, and no other site, make requests to BookOrbit from a browser.
- It gives nobody access. Every request still needs your KOReader sync sign-in or your API key, which only you type into the page.
- The Kindles with Wi-Fi don't need it: they aren't browsers.
- BookOrbit has to be on `https://` for the page to reach it (the page itself is on `https://`, and browsers don't let such a page call plain `http://`).

In both examples, replace `books.example.com` with your BookOrbit address and `bookorbit:3000` with where BookOrbit listens.

### Caddy

    books.example.com {
        @gzsync header Origin https://9retirement6irk.github.io
        header @gzsync Access-Control-Allow-Origin "https://9retirement6irk.github.io"
        header @gzsync Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header @gzsync Access-Control-Allow-Headers "x-auth-user, x-auth-key, authorization, content-type, range, if-none-match"
        header @gzsync Access-Control-Expose-Headers "content-length, content-range, content-disposition, etag"
        header @gzsync Access-Control-Max-Age "86400"
        header @gzsync +Vary "Origin"

        @gzsync_preflight {
            method OPTIONS
            header Origin https://9retirement6irk.github.io
        }
        respond @gzsync_preflight 204

        reverse_proxy bookorbit:3000
    }

Then `caddy reload` (or restart the container).

### nginx

The first block goes in the `http { }` part (in most setups, the top of the site's file in `conf.d` or `sites-available`, outside `server { }`). It turns the page's address into a value that is empty for every other site, and nginx leaves a header out when its value is empty.

    map $http_origin $gzsync_origin {
        default "";
        "https://9retirement6irk.github.io" $http_origin;
    }

    server {
        server_name books.example.com;
        # … your listen and certificate lines, as they are …

        location / {
            # the browser's question before a request
            if ($request_method = OPTIONS) {
                add_header Access-Control-Allow-Origin $gzsync_origin always;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
                add_header Access-Control-Allow-Headers "x-auth-user, x-auth-key, authorization, content-type, range, if-none-match" always;
                add_header Access-Control-Max-Age 86400 always;
                add_header Vary Origin always;
                return 204;
            }

            # the requests themselves
            add_header Access-Control-Allow-Origin $gzsync_origin always;
            add_header Access-Control-Expose-Headers "content-length, content-range, content-disposition, etag" always;
            add_header Vary Origin always;

            proxy_pass http://bookorbit:3000;
            # … your other proxy_set_header lines, as they are …
        }
    }

Then `nginx -t` to check the file, and `nginx -s reload`.

Two things to know with nginx:

- `add_header` lines in a `location` replace the ones in the `server` block above it for that location, they don't add to them. If your `server` block has `add_header` lines (security headers, for instance), repeat them inside `location /`.
- **Nginx Proxy Manager**: the `map` block can't go in a proxy host's *Advanced* box. Use this there instead, which needs no `map`:

      location / {
          set $gzsync_origin "";
          if ($http_origin = "https://9retirement6irk.github.io") {
              set $gzsync_origin $http_origin;
          }
          if ($request_method = OPTIONS) {
              add_header Access-Control-Allow-Origin $gzsync_origin always;
              add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
              add_header Access-Control-Allow-Headers "x-auth-user, x-auth-key, authorization, content-type, range, if-none-match" always;
              add_header Access-Control-Max-Age 86400 always;
              add_header Vary Origin always;
              return 204;
          }
          add_header Access-Control-Allow-Origin $gzsync_origin always;
          add_header Access-Control-Expose-Headers "content-length, content-range, content-disposition, etag" always;
          add_header Vary Origin always;
          proxy_pass $forward_scheme://$server:$port;
      }

### Other proxies, and anything in front

Whatever the proxy (Traefik, HAProxy, a tunnel), the rule is the same six headers for requests whose `Origin` is `https://9retirement6irk.github.io`, and a `204` answer to `OPTIONS` requests from it. If something else sits in front of the proxy (a tunnel or a login wall such as Cloudflare Access or Authelia), it has to let these requests through without its own sign-in page, or the browser gets that page instead of BookOrbit's answer.

### Checking it

On a computer, run GZreader's check (it sends no changes, and prints status codes and field names only):

    python3 tools/gzreader/bookorbit-probe.py

Before the rule, its last *sync page* line says `no`. After it, the three lines should read:

    sync page: preflight (OPTIONS)               204  allowed origin: the sync page; headers allowed: all GZreader sends
    sync page: a signed-in request               200  allowed origin: the sync page
        Kindles without Wi-Fi (the sync page) could use this server: yes

If the first line is still `404`, the `OPTIONS` rule isn't being reached (in nginx, check it's in the `location` that serves BookOrbit). If it's `204` but the allowed origin is `none`, the page's address in the rule doesn't match exactly: `https://`, no slash at the end.

## BookOrbit and GZreader

BookOrbit is its own project, under the GNU AGPL version 3 with additional terms. GZreader isn't part of BookOrbit and isn't endorsed by it. GZreader talks to your BookOrbit server over its API and contains none of BookOrbit's code, pictures or plugin; the reading stats page's charts are GZreader's own drawings of the numbers your server sends.

## If it doesn't connect

- **"Wrong user name or password…"**: it wants the KOReader sync ones (above). The same message appears if the address is another server's, such as Grimmory's.
- **"BookOrbit has sync switched off…"**: switch **Progress sync** on in BookOrbit's Settings → Devices → KOReader.
- **"That address answered, but not as BookOrbit"**: check the address; an old BookOrbit may not have the e-reader catalog.
- Send the diagnostic log (Settings → Privacy and diagnostics) if it's something else: look for lines starting `BookOrbit`.
