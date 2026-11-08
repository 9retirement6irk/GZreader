What GZreader sends to its developer (you choose), and how to send a diagnostic log when something goes wrong. Passwords and tokens stay on the device and are never written to its log.

## Usage statistics

GZreader sends anonymous usage statistics to its developer's
[Tianji](https://tianji.dev) server, so problems on real Kindles can be found
and fixed. You choose the level in the setup guide or in
**Settings → General → Usage statistics**:

| Level | What's sent |
| --- | --- |
| **Basic** (default) | GZreader's version, the Kindle model and firmware at each start; whether the previous run ended without closing normally; downloads that worked or failed; slow operations; keys the screen didn't answer |
| **Full** | Basic, plus time on Home, Downloads, Grimmory, in books and menus; menu entries used; reading sessions (format, picture book or not, minutes, pages, pages per minute, battery use per hour); read aloud; download size, speed and resumes; sync results and Grimmory's answer times; Wi‑Fi on-time; and **debug reports** (see [Remote debugging](Privacy-and-Diagnostics#remote-debugging)): starts, warnings and errors from GZreader's log, freezes and crashes |
| **Off** | Nothing is recorded or sent |

Never sent in the statistics: book titles, authors, file names, your Grimmory
address or account, or anything you type. Full's debug reports carry lines of
GZreader's log, which can name the book or file it was working on (never
passwords or tokens). Each Kindle is counted by a random ID, not its serial
number. Statistics wait in a small file and go out in one batch at most every 15
minutes, only while Wi‑Fi is already on; GZreader never turns Wi‑Fi on for them.

## Diagnostic log

`koreader/gzreader.log` (rotates at 512 KB): requests with status and timing,
pairing, SSO, downloads, sync, bookmarks, updates, read aloud. Passwords and
tokens are never written. Diagnostic logging is on by default (Settings →
General → Diagnostic logging); while it's on, the quick panel has
**Diagnostics**, which bundles the log, the tail of `crash.log`, what keeps
the Kindle awake and a read-only audio/speech survey into one
`gzreader-log-<date>.txt`, and:

- **Send to the developer:** first a box asks what you were doing and what
  went wrong (type as much as helps, or nothing), then that and the log go
  straight to GZreader's developer over Wi‑Fi (see [Remote debugging](#remote-debugging)). Also
  Settings → General → Send diagnostic log to the developer. On the
  Kindle 2 and DX (no Wi‑Fi) it says **(at the next sync)**: the same box,
  then the log and what you typed wait in `.gzsync/reports/` and the
  [sync page](Sync-with-a-Computer#sending-diagnostics-to-the-developer) sends them at your next sync.
- **Send to a browser (QR code):** scan the code (same Wi‑Fi), tap
  Download, then attach the file wherever you need it. Also the setup
  page's Diagnostics tab and Settings → General.
- **Save to the Kindle:** next to the GZreader folder, to copy over USB.
  Also Settings → General → Save diagnostic log (USB).

With diagnostic logging **off**, GZreader writes nothing to `gzreader.log`
and doesn't time book openings either (the `book open:` line), so it spends
no time on its log. The diagnostic bundle is only put together when you send
or save it. KOReader's own `crash.log` is separate: KOReader always writes
it, and the start script trims it to 500 KB.

## Remote debugging

For freezes and hard reboots, where the Kindle's own log may be lost:
with **usage statistics set to Full** (Settings → General → Usage
statistics, or the setup guide), GZreader reports to the developer's feed
(Tianji `…/open/feed/<id>/send`, `/state/upsert`, `/state/resolve`);
releases to one feed, test builds to another (`gzreader_remote.lua`
`R.FEED`, `R.TEST_FEED`). Basic and Off send none of this, and Kindles
without Wi‑Fi never do. (Up to 1.26.7 it was set by hand in Settings →
General → Remote debugging, with your own feed; that setting is gone.)
`gzreader_remote.lua` queues messages as JSON files in
`koreader/gzreader-remote/spool`; `gzreader_watchdog.lua`, a separate
low-priority LuaJIT process, sends them when Wi‑Fi is on (GZreader never turns
Wi‑Fi on for them) and watches a heartbeat GZreader writes every 15 s:

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
General → Send diagnostic log to the developer)
asks what you were doing and what went wrong, then sends that with the
whole diagnostic log (the same file "Save to the Kindle" writes) to a feed
of its own (`R.REPORT_FEED`, the same for releases and test builds), at
any usage level: in parts of 60 KB, at most the newest 480 KB, each an
event "Debug report from <model>-<id> (n/m)"; the first is named after
what you typed and starts with it ("What happened: …"; a password or token
typed there is redacted like the log's). `<id>` is the start of usage
statistics' random ID (not the serial number).

Sleep is not a freeze (the heartbeat says "sleep", and the watchdog notices
the clock jump after waking). Log lines are redacted (no passwords or
tokens). Checked with the Kindle 3's LuaJIT against a local feed: queued
messages, the freeze alert with its snapshot, "responsive again", the crash
report, and no crash report after a normal close.
