The **daily paper** is a small newspaper GZreader puts together for you once a
day from the news feeds you choose, and shows on Home. It's fetched over
Wi‑Fi in the morning and kept on the Kindle, so you can read it all day with
Wi‑Fi off.

It's off until you turn it on. Not on the Kindle 2 and DX yet: they have no
Wi‑Fi.

## Turning it on

**Settings → Accounts and services → Daily paper**, and tick **Daily paper**. A folded
newspaper appears on Home's bookshelf, standing on its side at the start of
the first shelf like the books beside it, nearly as tall as they are: you see
its fold with the paper's name running up it, the day's lead headline, and
the edges of its pages. It takes a thick book's room on the shelf and nothing
else on Home.

Pick it as you pick a book (tap it; with keys, move to it with the 5-way) and
it turns to show its front page: its name, the date and the day's lead
headline.

- **On Home's bookshelf** takes it off the shelf and puts it back. (The shelf
  is Home's Bookshelf view; with another view, use the row below, or **Read
  the paper** in the same Settings page.)
- **Headlines as a row on Home** adds a wider newspaper with six or so
  headlines as one of Home's widgets, above the books. It takes a widget's
  room: if Home is full, turn another widget off in **Settings → Home →
  Widgets** first. Off unless you tick it.

## Reading it

Tap the newspaper's front page on the shelf (so: a tap to turn it, a tap to
open it; with keys, move to it with the 5-way and press). It opens laid out as a newspaper: the nameplate and the date, the
lead story across the page, and the other stories in columns (two, or three
on a DX or a Scribe), each with its section, its headline, where it's from
and how it begins.

- **More pages**: swipe left, press a page-turn key, or tap the arrow at the
  foot of the page.
- **A story**: tap it (with keys: move the frame with the 5-way and press).
  It opens as text that scrolls with your finger and stays exactly where
  your finger leaves it, also when you lift while still moving; the page
  keys, or ▲ ▼ on a keyboard Kindle, move it most of a screen. At the top,
  **Aa** sets the story's text (below), **QR code** shows the story's link as
  a code for your phone, for the rest of it or its pictures, and **✕** closes
  it.
- **Story text**: **Aa** at the top of a story (**Menu** on a Kindle with
  keys) opens a box with **A−** / **A+** for the size, the typeface (Serif,
  Sans, Classic, Typewriter) and the line spacing (Tight, Normal, Wide). The
  story behind is set again at each tap, at the same place, so you can try
  them; **Done** closes the box. The choices are kept, and are also in the
  daily paper's settings under **Story text**. They set opened stories; the
  front page keeps its own type.
- **Close**: the cross in the corner, or Back.
- **The quick panel**: swipe down from the top of the paper or of a story,
  as anywhere else.

**Whole stories**: many feeds carry only a sentence or two of each story.
For those, GZreader also fetches the story's own web page with the day's
paper and takes the article out of it, as a browser's reader view does, so
you read the whole story with Wi‑Fi off. Feeds that carry whole stories are
used as they are (up to about 2,500 words a story).

- It makes the day's fetch longer: a page for each short story, in the
  background, five minutes at most; stories it didn't get to keep their
  summary.
- A story behind a paywall, or on a page built by scripts, keeps the feed's
  summary, and says so at its end.
- **Settings → Accounts and services → Daily paper → Whole stories** turns it off (a faster
  fetch, summaries only).

**Weather**: a box under the date shows now, today and the next two days,
each with a small drawing of its sky, the high and low, and the chance of
rain on a wet day. It comes with the day's paper:

- from your **Home Assistant** when the [House](House) tab's is connected (its
  first weather entity); nothing leaves your network;
- otherwise from **Open‑Meteo** (open-meteo.com: free, no account) for the
  town you set in **Settings → Accounts and services → Daily paper → Weather → Town**, or on
  the setup page's Daily paper tab. **Degrees** switches Fahrenheit and
  Celsius (it starts as the town's country uses).

With no town set and no Home Assistant there's no box; **Weather on the front
page** turns it off.

**Today's calendar events**: when you use the [Calendar](Calendar) tab, the
front page has a **TODAY** box under the date with today's events, all-day
ones first, then by time. They're the events the Calendar tab last synced,
kept on the Kindle: nothing is fetched for it and nothing about them leaves
the Kindle. Tap the box for the Calendar tab. A day without events has no
box; **Settings → Accounts and services → Daily paper → Today's calendar events** turns it off.

**Pictures**: the lead story's picture runs across the front page, a few more
stories have theirs in the columns (eight an edition at most), and the lead's
is on the newspaper's front page on the shelf. They are fetched with the
paper, kept until the next edition and shown in grey. A story opened as text
has no picture. **Settings → Accounts and services → Daily paper → Pictures** turns them off
(the paper is fetched faster without them).

## When it's fetched

Once a day, the first time Home (or the paper) is on the screen after
5 in the morning by the Kindle's clock:

- With [Wi‑Fi](Wi-Fi) on **Auto**, GZreader turns Wi‑Fi on for it and off
  again afterwards. On **On** it's fetched straight away. On **Off** nothing
  is fetched until you ask: **Fetch today's paper** at the foot of the
  paper (or **Settings → Accounts and services → Daily paper → Fetch now**), which turns
  Wi‑Fi on for that.
- If the feeds can't be reached, yesterday's paper stays (the widget says
  which day it's from) and GZreader tries again half an hour later.
- A feed that didn't answer is named at the end of the paper.

Stories older than a day and a half stay out, except from a feed that posts
seldom: its newest story is shown rather than nothing.

## Choosing feeds

A feed is a site's list of its newest stories (RSS or Atom); most news sites
and blogs have one.

**From your phone or computer** (the easy way to paste addresses):
**Settings → Accounts and services → Daily paper → Set up from a browser (QR code)** opens the
[setup page](Setup-Page-and-Connections) at its **Daily paper** tab. Scan the
code, or open the address shown on a computer on the same Wi‑Fi. There you
can turn the paper on or off, take it off the bookshelf, tick the feeds
GZreader comes with, paste your own (one per line, as in `feeds.txt` below),
and remove them. **Save**, then press Back on the Kindle.

**On the Kindle**: **Settings → Accounts and services → Daily paper → Feeds**:

- GZreader comes with a few to tick, by section: BBC News (World, Technology,
  Science), NPR, Ars Technica, NASA, Literary Hub, Atlas Obscura, NPR Strange
  News; Hacker News and NPR Science are there unticked.
- **Add a feed**: type its address, and if you like a name and a section
  (your feeds go under **Your feeds** otherwise).
- **Add from feeds.txt**: put a file `feeds.txt` in the GZreader folder (or at
  the top of the Kindle's USB drive) with one feed per line:

  ```
  https://blog.example.com/feed
  Knitting weekly | https://knitting.example.com/rss
  Crafts | Knitting weekly | https://knitting.example.com/rss
  ```

  An address alone, `Name | address`, or `Section | Name | address`. Lines
  starting with `#` are skipped.
- Hold one of your own feeds to remove it; untick it to leave it out for now.

After a change, the paper is made again the next time Home is shown.

## Privacy

Fetching a feed is a plain request to that feed's site, as opening the site
in a browser would be: the site sees the Kindle's internet address and that
GZreader asked. Nothing else is sent: no account, no cookies, nothing about
you or what you read. Nothing goes through anyone else's server. With
**Pictures** on, a story's picture is fetched the same way from wherever the
feed says it is, often a picture server on another site than the feed's.
With **Whole stories** on, each short story's own page is fetched too. It's
usually on the feed's site, but not always (Hacker News links anywhere); that
site then sees the Kindle's internet address as well. Story addresses are not
written to the log.
For the weather, Open‑Meteo is sent the town's name once (to find where it
is) and after that only its coordinates rounded to two decimals, about a
kilometre, with each day's request; it sees the Kindle's internet address
too. The town and the coordinates are never written to the log. Home
Assistant's weather stays on your network. Feed
addresses are never written to the [diagnostic log](Privacy-and-Diagnostics#diagnostic-log)
(only the site's name), as some carry a personal key.
