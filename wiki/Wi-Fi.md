How GZreader saves battery with Wi‑Fi.

On by default (Settings → General → Wi-Fi only when needed). GZreader turns
Wi-Fi on by itself when it needs the network and off again after a minute
unused, as long as nothing still needs it (an open Grimmory browser, a
download or its queue, the library index, a QR screen, an update download).

| When | Wi-Fi |
| --- | --- |
| Browsing Grimmory (a book's page and its Download too, also when the list came from the Kindle), downloading, connecting, sending the log, checking for / installing updates | turned on ("Connecting to Wi-Fi…") |
| A Grimmory book opens | turned on quietly: pull the position, send queued changes, sync bookmarks, highlights and notes |
| A book closes with unsent changes (position, session, highlights) | turned on quietly to send them |
| Wake after 15 min or more with a book open | turned on quietly to pull the position |
| Page turns, bookmarks, highlights, sleep | not turned on: changes wait for the next sync |
| Daily update check, library index refresh | only if Wi-Fi is already on |

Wi-Fi you turned on yourself is never turned off. Going to sleep turns off
Wi-Fi GZreader turned on.


Wi‑Fi you turn off yourself (the quick panel's Wi‑Fi tile or KOReader's Wi‑Fi
menu: its interactive switch) stays off for background work (syncs when a book opens
or closes, after waking, Notes, Calendar, the auto-download shelf) until you
turn it on again, also after a restart (`gzreader_wifi_kept_off`). Things you
ask for still connect.
