Home, the Downloads tab's bookshelves, the reading stats on Home and the sleep screen.

## Bookshelves (the View)

Books stand on bookshelves by default, on Home and in Downloads: spines out
(title, author, number in a series, a letter key at the foot), rounded and
shaded, casting shadows, on shelves with depth. The book the 5-way is on, or
that you tap, turns to show its cover; tap it again, Press or its letter opens
it, and holding it opens Manage book (Open, Delete from this Kindle, then
the book's menu). The book you're reading (top of Home) is
drawn as a book too: its pages behind the cover and a drop shadow.
Covers have square corners in this view: Settings → Downloads → Appearance →
Covers → Rounded cover corners is greyed out while it's on, and your choice
for the tiles and lists comes back when you switch to one of them.

Home's status bar (clock, Wi‑Fi, battery) sits beside the book you're
reading. Before you've read a book (or after clearing your reading history),
it runs across the top of Home as on the other tabs, and moves back beside
the book once you open one.

- **Downloads** has as many shelves as the screen holds, a page at a time
  (on the DX four, so the books are bigger), each filled with as many books
  as their spines leave room for. On a Kindle with a keyboard the letter keys
  go from Q to L (19 books); the books after L on a page have no letter (the
  5-way reaches them), and Del isn't one of them. Folders stand as light grey
  spines with a tab on top. A book that finishes downloading while
  Downloads is on screen appears in it straight away. Its title bar says
  *Downloads* between the clock and the battery, as the other tabs name
  themselves (or the tab's own name, if you renamed it in Settings →
  Interface → Navbar); inside a folder it shows the folder's name.
- **Home** has one shelf of your most recent books; the DX's taller screen
  has two (the first filled before the second).
- **The spines** are drawn after
  [Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin), AndyHazz's
  KOReader plugin: the shelf is seen from a little above, so each book shows
  the top of its page block between its boards. The whole title runs along the
  spine: a long one takes two or three lines of smaller type instead of
  being cut off. The author comes after it in smaller type, or on a line of
  its own where there's no room after the title.
  A book's number in its series is level at the foot of the spine. The books
  cast a soft shadow on the wall behind them, and the board shows its top.

- **Audiobooks** stand on the top shelf to the right of the books as a
  cassette walkman with its headphones sitting on it, and **Music** (downloaded from Plex) as a
  CD player with headphones. In lists and tiles both folders are always first,
  whatever the sort.
- **Sort** (quick panel → Sort) orders Downloads and Home's shelf: title,
  author, series, date downloaded, reading progress, size or file name;
  *Last read* puts the most recent first.
- **View** (quick panel → View) switches between Bookshelf, List with details,
  Simple list and Tiles; Home's strip shows covers in the other views. The
  setup guide asks too.

![Downloads as bookshelves](https://raw.githubusercontent.com/9retirement6irk/GZreader/main/docs/screenshots/downloads-shelf.png)

## Reading stats on Home

Home shows **Grimmory reading stats** by default: three numbers on a notebook
page, counted over every device that reads with your Grimmory account
(GZreader on each Kindle and Grimmory's web reader send their reading
sessions; Grimmory adds them up). Choose the three in Settings → Home →
Widgets → Grimmory reading stats → Stat slot 1–3:

- Read this week (time), Books this week
- Day streak (as tally marks up to 10), Longest streak, Days read
- Sessions this month, Finished this year

They're fetched from Grimmory when Home shows them and they're over 15
minutes old (only while Wi‑Fi is on), and again after this Kindle's reading
sessions reach Grimmory; the last ones stay for when it's offline. Your
Grimmory user needs permission to see statistics (Grimmory → user settings →
permissions); without it the widget shows dashes and the diagnostic log says
why.

The earlier **Local reading stats** widget (pages and time today, this
Kindle only) is gone from Home and from Settings → Home → Widgets; a Home that
still showed it keeps its other widgets.

The book you're reading shows its progress as the book's page edges, read
pages darker, with a ribbon bookmark where you are.

## Sleep screen

While a book is open: its cover. From Home and menus: a random picture from
the USB drive's `screensavers` folder (created by the setup guide), falling
back to the Kindle's own sleep pictures. Chosen in the setup guide, or in
**Settings → General → Sleep → Wallpaper**: each sleep screen is a tile
showing what it looks like (this one, the last book's cover, a picture from
the screensavers folder, reading progress, book status, or the screen left
as it is); tap one, or press its letter on a Kindle with keys. The cover's
fill, rotation and fit, when to ignore a book's cover and the wake-up delay
are in **Wallpaper options** next to it. (There is no custom image to
choose, and no sleep-screen presets.)

To have the cover fill the whole screen with no bars at the edges, tick
**Wallpaper options → Border fill, rotation, and fit → Scale cover to fill
screen**: the cover (or picture) keeps its proportions and is scaled up until
it covers the screen; the parts that don't fit (the top and bottom of a tall
cover, the sides of a wide one) are cut off. While it's on, **Stretch cover
to fit screen** just above it, which pulls the cover out of shape instead, is
greyed out.
