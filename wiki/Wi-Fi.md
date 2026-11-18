How GZreader turns Wi‑Fi on and off, and saves battery.

Wi‑Fi is **On**, **Off** or **Auto** (Auto is the default):

- **The quick panel's Wi‑Fi tile** goes through them: Wi‑Fi on → Wi‑Fi off →
  Wi‑Fi auto → Wi‑Fi on. On is drawn white on black; Auto's icon has an **A**
  and still shows whether Wi‑Fi is on right now (crossed out while it's off).
  The panel stays open after a tap, so you can tap again to reach the mode you
  want.
- **Settings → Wi‑Fi** offers the same three, with **Networks**
  (choosing a network), **HTTP proxy** (tap: on or off; hold: its address)
  and **Network info** under them. The row shows the mode.
- **The status bar** (Home's and a book's top bar) shows the Wi‑Fi icon as
  before, on or off; on Auto an **A** follows it.

| Mode | What it does |
| --- | --- |
| On | Wi‑Fi stays on. If it goes off by itself (after sleep, out of range), GZreader turns it on again when something needs it, and leaves it on. |
| Off | Wi‑Fi stays off. Background work (syncs when a book opens or closes, after waking, Notes, Calendar, the auto-download shelf) waits until Wi‑Fi is on again, also after a restart. Things you ask for (browsing Grimmory, a download, checking for updates) still turn it on, then off again after a minute. |
| Auto | GZreader turns Wi‑Fi on by itself when it needs the network and off again after a minute unused, as long as nothing still needs it (an open Grimmory browser, a download or its queue, the library index, a QR screen, an update download). |

On Auto:

| When | Wi-Fi |
| --- | --- |
| Browsing Grimmory (a book's page and its Download too, also when the list came from the Kindle), downloading, connecting, sending the log, checking for / installing updates | turned on ("Connecting to Wi-Fi…") |
| A Grimmory book opens | turned on quietly: pull the position, send queued changes, sync bookmarks, highlights and notes |
| A book closes with unsent changes (position, session, highlights) | turned on quietly to send them |
| Wake after 15 min or more with a book open | turned on quietly to pull the position |
| Page turns, bookmarks, highlights, sleep | not turned on: changes wait for the next sync |
| Daily update check, library index refresh | only if Wi-Fi is already on |

**Downloads run with Wi‑Fi power saving off.** With power saving on, the
Wi‑Fi chip naps between the router's beacons and downloads crawl (about
30 KB/s on a Paperwhite 3, 5 KB/s on a Scribe). While a book, an update,
an audiobook or music downloads, while notes with drawings go to Memos and
while the phone page is open, GZreader turns power saving off, and when the
last of them ends it turns it back on (only if it was on before), so reading
with Wi‑Fi on still saves battery. The log says `wifi: power saving off while
transferring`; a Kindle whose Wi‑Fi can't be asked leaves it as it is. Not on
the Kindle 3 (with power saving switched, its update downloads crawled and
broke off), and a Kindle whose Wi‑Fi accepts "off" without taking it gets
power saving back at once (`wifi: power saving didn't turn off (driver); left
on`).

**When the scan finds nothing.** Right after GZreader or the Kindle restarted,
a Paperwhite or Touch sometimes got an empty list from the Wi‑Fi scan, so
GZreader couldn't connect while the Wi‑Fi menu still could. GZreader then
asks the Kindle to join the network it has saved, as the Wi‑Fi menu does
(the log says `wifi: the scan found no network; asked the Kindle to join its
saved one`).

Wi‑Fi that was already on when GZreader started or woke up counts as
GZreader's on Auto (off after a minute unused). Going to sleep turns off Wi‑Fi
GZreader turned on.

Turning Wi‑Fi on or off anywhere else (KOReader's Wi‑Fi menu, a gesture, the
network list) chooses On or Off, so the mode always says what you last asked
for. KOReader's own "Disable Wi‑Fi connection when inactive" isn't offered
(it turned Wi‑Fi off after five quiet minutes even on On; Auto does that job),
and a tick saved earlier is cleared when GZreader starts. The mode is kept in `gzreader_wifi_mode`; settings from before it (the
"Wi‑Fi only when needed" switch, `gzreader_wifi_on_demand`, and
`gzreader_wifi_kept_off`) become Auto, On or Off.

**Kindles with Bluetooth keep it on.** A Kindle can't turn off only its
Wi‑Fi: GZreader (like KOReader) turns Wi‑Fi off with Amazon's airplane mode,
which turns Bluetooth off too and cut off headphones and speakers. On the
Kindles with Bluetooth (2016 and newer: Kindle 8th generation and later,
Oasis, Paperwhite 4 and newer, Scribe, Colorsoft), when Bluetooth was on,
GZreader turns it on again right after and, a few seconds later, reconnects
the device that was connected (by its name in Amazon's list of paired
devices; with only one paired device, that one). Bluetooth that was off stays
off. The log says `GZreader: Bluetooth turned on again after airplane mode`,
never the device's name or address.

**While the Kindle sleeps, Bluetooth is off.** Going to sleep, GZreader turns
Bluetooth off if it's on (Wi‑Fi turned off at sleep doesn't bring it back);
waking up, it turns it on again and reconnects the device that was connected
a few seconds later — only if it was on before sleep. The log says
`GZreader: Bluetooth off for sleep` and `GZreader: Bluetooth on again after
sleep`.
