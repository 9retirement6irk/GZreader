What GZreader sends to its developer (you choose), and how to send a diagnostic log when something goes wrong. Passwords and tokens stay on the device and are never written to its log, and neither is the name of your Wi-Fi network.

## Debug reports

GZreader sends no usage statistics (up to 1.28.1 it sent anonymous ones,
Basic by default; that's gone, and what was waiting on the Kindle is
deleted). What it can still send its developer is **debug reports**, so
problems on real Kindles can be found and fixed:

- **Send debug reports automatically** (the setup guide's **Debug Reports**
  page, or **Settings → About → Send debug reports automatically**), off
  unless you choose it: when GZreader starts, how the previous run ended,
  warnings and errors from its log, freezes and crashes. They go out only
  while Wi‑Fi is already on; GZreader never turns Wi‑Fi on for them. See
  [Remote debugging](#remote-debugging) for what each report has. If you had
  usage statistics set to **Full**, which included these, they stay on;
  **Basic** or **Off**: they're off.
- **Send to the developer** (see [Diagnostic log](#diagnostic-log)): the
  whole diagnostic log, once, with what you type about what went wrong,
  whether automatic reports are on or not.

Reports carry GZreader's version, the Kindle model and lines of GZreader's
log, which can name the book or file it was working on. Never passwords,
tokens, your Wi-Fi network's name (it's written as `<network>`, also in
the end of KOReader's crash.log) or anything you type (except what you type for Send to the
developer). Each Kindle is named by a random ID, not its serial number, so
reports from two Kindles can be told apart. The Kindle 2 and DX have no
Wi‑Fi, so they never send reports by themselves (Send to the developer
works there, at the next sync).

## Diagnostic log

`koreader/gzreader.log` (rotates at 512 KB): requests with status and timing,
pairing, SSO, downloads, sync, bookmarks, updates, read aloud. Passwords and
tokens are never written. Diagnostic logging is on by default (Settings →
About → Advanced → Diagnostic logging, at the top of Advanced with
sending and saving the log); while it's on, the quick panel has
**Diagnostics**, which bundles the log, the tail of `crash.log`, what keeps
the Kindle awake and a read-only audio/speech survey into one
`gzreader-log-<date>.txt`, and:

- **Send to the developer:** first a box asks what you were doing and what
  went wrong (type as much as helps, or nothing), then that and the log go
  straight to GZreader's developer over Wi‑Fi (see [Remote debugging](#remote-debugging)).
  It's sent in the background: you can carry on reading, and a message
  says when it's sent. Also
  Settings → About → Advanced → Send diagnostic log to the developer. On the
  Kindle 2 and DX (no Wi‑Fi) it says **(at the next sync)**: the same box,
  then the log and what you typed wait in `.gzsync/reports/` and the
  [sync page](Sync-with-a-Computer#sending-diagnostics-to-the-developer) sends them at your next sync.
- **Send to a browser (QR code):** scan the code (same Wi‑Fi), tap
  Download, then attach the file wherever you need it. Also the setup
  page's Diagnostics tab and Settings → About → Advanced.
- **Save to the Kindle:** next to the GZreader folder, to copy over USB.
  Also Settings → About → Advanced → Save diagnostic log (USB).

With diagnostic logging **off**, GZreader writes nothing to `gzreader.log`
and doesn't time book openings either (the `book open:` line), so it spends
no time on its log. The diagnostic bundle is only put together when you send
or save it. KOReader's own `crash.log` is separate: KOReader always writes
it, and the start script trims it to 500 KB.

Ordinary log lines are written a few at a time (at most 5 seconds late;
warnings and errors at once, and everything waiting when the Kindle goes to
sleep, on exit and when you save or send the log), so a burst of sync
logging is one write to the Kindle's storage, not one per line.

**If the Kindle freezes around a book**, three lines say how much memory
there was: `book open starting: <file>` (before anything of the book is
read), `book closed` and `Home on screen … after the book closed`. Each has
the free memory, the file cache, GZreader's own size, its Lua memory and, on
a Kindle, whether GZreader was started with the Kindle's own interface
stopped or kept in memory. These three are written at once, not a few
seconds late, and on Kindles with 128 MB or less (Kindle 2, DX) they are
forced onto the storage, so the last one is still there after you had to
restart a frozen Kindle with its power switch. Save or send the log after
the restart: the last of these lines says how far it got.

**A slow download** (a book or an update) leaves its own lines, starting
`transfer`: one at the start with what can hold a download back on this
Kindle (Wi‑Fi power saving on or off, the network's receive buffer, the
processor's speed setting and load), one every 15 seconds with the speed,
how busy GZreader's download and the whole processor were and the longest
wait for data, and a summary at the end. If downloads crawl, download
something, then send the log (Diagnostics → Send to the developer) and say
so in the box. No Wi‑Fi network name is written, only whether power saving
is on.

Putting the bundle together is quick after the first time: the audio/speech
survey runs about thirty system commands (around 25 s on a Kindle 3), so
the answers that only change with the Kindle's firmware are kept in
`koreader/cache/gz-device-probe.lua` and reused; the few that change while
the Kindle runs (memory, running programs, Wi‑Fi state, GZreader's own
files) are run each time.

No log files pile up on the Kindle: Send to the developer and Send to a
browser (and the setup page's Diagnostics tab) build the file in
`koreader/cache` and delete it once it's sent, and Save to the Kindle keeps
only the newest three `gzreader-log-<date>.txt` next to the GZreader folder
(the one just saved always stays).

## Where sign-ins are kept

On a Kindle, KOReader's settings are on the USB drive (`koreader/settings`),
which any computer the Kindle is plugged into can read. GZreader keeps its
sign-ins somewhere else: the CalDAV password, the Grimmory, Memos, Plex and
Home Assistant tokens, the Immich key, the Access key and Cloudflare token,
and calendar links (their keys are in the address) are kept in
`/var/local/gzreader/secrets.lua` on the Kindle's own disk, which isn't
shared over USB; GZreader's settings on the drive hold everything else.
Sign-ins saved by an earlier version move there by themselves a few seconds
after GZreader starts (the settings' backup copy is cleaned too). Going
back to an earlier version afterwards means connecting again. On a Nook,
GZreader's settings are already on its own disk (`/data/gzreader`).
Kindles without Wi‑Fi keep none on the Kindle in readable form: the sync page
keeps them in `.gzsync/keys.json`, locked with your PIN
([Sync with a computer](Sync-with-a-Computer)).

## Sites the daily paper asks

With the [daily paper](Daily-Paper) on (it's off unless you turn it on), the
Kindle fetches the feeds you ticked once a day, straight from their sites
(BBC, NPR and the others listed there, or the ones you added). Each site sees
the Kindle's internet address and that GZreader asked, as with any web page;
no account, cookie or anything about you is sent, and feed addresses are
never written to the log.

Its weather box asks your own Home Assistant when that's connected;
otherwise [Open‑Meteo](https://open-meteo.com), with the town you set (its
name once, then its coordinates rounded to about a kilometre). See
[Daily paper](Daily-Paper#privacy).

## Remote debugging

For freezes and hard reboots, where the Kindle's own log may be lost:
with **Send debug reports automatically** on (Settings → About, or the
setup guide), GZreader reports to the developer's feed
(Tianji `…/open/feed/<id>/send`, `/state/upsert`, `/state/resolve`);
releases to one feed, test builds to another (`gzreader_remote.lua`
`R.FEED`, `R.TEST_FEED`). Off (the default) sends none of this, and Kindles
without Wi‑Fi never do. (Up to 1.28.1 it came with Full usage statistics; up to 1.26.7 it was set by hand in Settings →
General → Remote debugging, with your own feed; that setting is gone.)
`gzreader_remote.lua` queues messages as JSON files in
`koreader/gzreader-remote/spool`; `gzreader_watchdog.lua`, a separate
low-priority LuaJIT process, sends them when Wi‑Fi is on (GZreader never turns
Wi‑Fi on for them), as `GZreader/<version>` like GZreader's other requests. A
message the feed answers with a server error is tried again later and later (up
to 10 minutes apart); after 6 such answers it's set aside
(`spool/*.failed`, the newest 5 kept) so the ones after it still go. It also watches a heartbeat GZreader writes every 15 s (to
`/tmp`, which is in memory, so it doesn't wear the Kindle's storage; the copy
in `gzreader-remote/heartbeat` is updated when GZreader starts, sleeps, wakes
or exits, and every 10 minutes):

| Report | When |
| --- | --- |
| GZreader started | every start: version, battery, memory, how the previous run ended |
| Previous run ended unexpectedly (important) | the last heartbeat said "running": hard reboot, battery, freeze or crash; with what it was doing, the previous run's log tail and crash.log |
| Kindle unresponsive (important) + state "GZreader unresponsive" | no heartbeat for 2 minutes while awake: memory, load, top processes, kernel messages and the log at that moment |
| Kindle responsive again + state resolved | the heartbeat is back |
| GZreader crashed (important) | the process ended without closing: crash.log and log tail |
| warnings / errors | GZreader's log warnings and errors, a minute at a time |

| GZreader slow | no heartbeat for 45 s (once per 10 min): the same snapshot |
| GZreader busy (important) | GZreader at 60% CPU or more for a minute (from the app) |
| warning "slow: …" | a keypress, repaint or round of scheduled work took 3 s or more |

Where the time goes (`gzreader_slowtrace.lua`, with remote debugging on; the
profiler below is off since the setting for it went with Remote debugging):
LuaJIT's sampling profiler (`jit.profile`, every 50 ms of CPU time, so
nothing while idle) tallies the running code (3 frames) and whether it is
Lua, JIT code, C (e.g. crengine), garbage collection or the JIT compiler. The
tally is written to `gzreader-remote/profile` every ~5 s of CPU, also while
GZreader is stuck in one long call, and goes into the watchdog's reports,
with each GZreader process's state, CPU over 2 s, memory and wait channel.

**Send to the developer** (Diagnostics in the quick panel; Settings →
About → Advanced → Send diagnostic log to the developer; Settings →
About → Report a bug)
asks what you were doing and what went wrong, then sends that with the
whole diagnostic log (the same file "Save to the Kindle" writes) to a feed
of its own (`R.REPORT_FEED`, the same for releases and test builds),
whether automatic reports are on or not: in parts of 60 KB, at most the newest 480 KB, each an
event "Debug report from <model>-<id> (n/m)"; the first is named after
what you typed and starts with it ("What happened: …"; a password or token
typed there is redacted like the log's). `<id>` is the start of the
Kindle's random ID (not the serial number).

Sleep is not a freeze (the heartbeat says "sleep", and the watchdog notices
the clock jump after waking). Log lines are redacted (no passwords,
tokens or Wi-Fi network names). Checked with the Kindle 3's LuaJIT against a local feed: queued
messages, the freeze alert with its snapshot, "responsive again", the crash
report, and no crash report after a normal close.

The heartbeat says "sleep" from the moment the screensaver shows until the
Kindle wakes, and after waking the watchdog counts from then, so a long
sleep (or the seconds a Kindle takes to wake) is never reported as a freeze.
