The **daily paper** is a small newspaper GZreader puts together for you once a
day from the news feeds you choose, and shows on Home. It's fetched over
Wi‑Fi in the morning and kept on the Kindle, so you can read it all day with
Wi‑Fi off.

It's off until you turn it on. Not on the Kindle 2 and DX yet: they have no
Wi‑Fi.

## Turning it on

**Settings → Home → Daily paper**, and tick **Daily paper**. A folded
newspaper appears on Home's bookshelf, standing on its side at the start of
the first shelf like the books beside it: you see its fold and the edges of
its pages. It takes a thin book's room on the shelf and nothing else on Home.

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
  It opens as text, a page at a time; **QR code** shows the story's link as a
  code for your phone, for the rest of it or its pictures.
- **Close**: the cross in the corner, or Back.

The paper shows what a feed carries. Some feeds carry whole stories; many
carry only a sentence or two, and the paper says so under such a story.
There are no pictures.

## When it's fetched

Once a day, the first time Home (or the paper) is on the screen after
5 in the morning by the Kindle's clock:

- With [Wi‑Fi](Wi-Fi) on **Auto**, GZreader turns Wi‑Fi on for it and off
  again afterwards. On **On** it's fetched straight away. On **Off** nothing
  is fetched until you ask: **Fetch today's paper** at the foot of the
  paper (or **Settings → Home → Daily paper → Fetch now**), which turns
  Wi‑Fi on for that.
- If the feeds can't be reached, yesterday's paper stays (the widget says
  which day it's from) and GZreader tries again half an hour later.
- A feed that didn't answer is named at the end of the paper.

Stories older than a day and a half stay out, except from a feed that posts
seldom: its newest story is shown rather than nothing.

## Choosing feeds

A feed is a site's list of its newest stories (RSS or Atom); most news sites
and blogs have one. **Settings → Home → Daily paper → Feeds**:

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
you or what you read. Nothing goes through anyone else's server. Feed
addresses are never written to the [diagnostic log](Privacy-and-Diagnostics#diagnostic-log)
(only the site's name), as some carry a personal key.
