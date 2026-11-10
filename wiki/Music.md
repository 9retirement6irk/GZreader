Albums and playlists from your Plex server, on Kindles with a speaker or headphone jack.

Kindles with a speaker or headphone jack (Kindle 2, 3, DX, Touch): albums and
playlists from your Plex Media Server, played while you read.

Music is the **Catalog** tab's third page: swipe left twice from Books, or
use the page-turn button ([the Catalog tab](Grimmory-Library#the-catalog-tab)).
Signed in to Plex, it's laid out like the Books page: **Search music…** at
the top, two shelves of CD cases, **Recently played** (what you played on
this Kindle, latest first, then what Plex's own players played) and
**Recently added** (Plex's newest albums, marked NEW), each ending in a
bundle that opens the whole list, then a bookcase with **Playlists**,
**Albums** and **Artists** (and *On this Kindle* and *Now playing* when
there's something to show, and your Plex account). Albums and
playlists stand on the shelves as **CD cases**, face out: the album's cover
under the lid (Plex's own small copy, fetched while the list shows and kept
with the Catalog's covers; a plain insert with the title until it's here),
**ON KINDLE** on the ones downloaded, and a tag under each with the title
and the artist and year (a playlist: its number of tracks). An artist opens
to their albums, as CD cases too. Search results stay a list (artists,
albums and tracks together).

![The Catalog's Music page](https://raw.githubusercontent.com/9retirement6irk/GZreader/main/docs/screenshots/catalog-music.png) ![An album playing in the CD player](https://raw.githubusercontent.com/9retirement6irk/GZreader/main/docs/screenshots/cd-player.png)

There is also a **Music tab**, off until you turn it on: Settings → Interface →
Navbar → Tabs → Music (or in the setup guide's tab page). The tab bar holds up
to 7 tabs. While music plays or is paused, the quick panel has a **Music**
tile (*Music ▶* while it plays), at Home and in a book: it opens Now playing.

While music plays, *Now playing* is a portable CD player with headphones: the
album's cover printed over the whole disc, the track and time on its little display, then the
track, the controls (Q previous, W play / pause, E next, A shuffle, S repeat,
D stop; ◀ ▶ change track) and the queue like the back of a CD case (▲ ▼ and
Press, or tap a track, to play it).

Sign in, either way:
- on the Kindle: *Sign in to Plex with a code*: go to **plex.tv/link** on a
  phone or computer and enter the 4 letters shown;
- on the setup page: Music → *Sign in with Plex*.

GZreader then uses your own Plex server (the one on the same Wi‑Fi first, or
another you choose). Browse **Artists**, **Albums**, **Playlists**, or
**Search**. An album or playlist: *Play*, *Shuffle*, *Download for offline*
(or *Delete the download*), and its tracks. *Play* on one that isn't
downloaded downloads it in order and starts as soon as the first track is in;
Wi‑Fi is on only while downloading. *Downloaded* lists what's on the Kindle
(`.music` in the GZreader folder); *Shuffle all downloaded* plays it all. Each
downloaded album or playlist is also in Downloads → **Music** (on the
bookshelf, the CD player), like audiobooks: open one to play it.

**Music library**: a Plex server can have several music libraries. GZreader
uses the server's first until you pick another in Settings → Connections →
Plex → **Music library** (or *Plex: you · server* in the Music tab). Artists,
Albums, Recently added and Recently played come from the one picked; with
more than one music library on the server, Playlists and Search keep to it
too. The choice is kept per server, and the sync page (Kindles without
Wi‑Fi) lists the same library's albums. A library picked for
[audiobooks](Audiobooks-and-Read-Aloud#audiobooks-from-plex) is skipped
when nothing is picked here.

Formats: the Kindle plays MP3 and AAC. MP3 is downloaded as it is, AAC (M4A)
is downloaded and repacked on the Kindle (like audiobooks), anything else
(FLAC, ALAC, Ogg, Opus) is converted to MP3 by your Plex server (128, 192 or
320 kbps: *Plex: you · server* in the Music tab). To save room, **Make bigger
MP3 and AAC smaller** (in the same place) has Plex convert MP3 and AAC tracks
of a higher quality to MP3 at that quality too (more than 15 % above it, so a
file at about that quality stays as it is); music already downloaded stays as
it is. The sync page (Kindles without Wi‑Fi) shows the same two choices with
the Plex connection and uses them; changed there, the Kindle keeps them. Converting uses Plex's
transcoder; if your server refuses it, those tracks say so.

*Now playing*: pause, next, previous, shuffle, repeat (off, all, this track),
the queue. Music, audiobooks and read aloud play one at a time: starting one
pauses the others, and sleep pauses music. The Kindle's volume keys work
everywhere. The Plex token is kept like the other sign-ins and never logged
(it's sent as a header, never in an address).
