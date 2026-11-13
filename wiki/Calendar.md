Your calendars on the device, read-only.

The Calendar tab (B) shows calendars from their **shared links** (webcal:// or
https://….ics: Proton Calendar's Share → Share with anyone, Google's secret
iCal address, Outlook's published ICS…) and/or a **CalDAV account**, read-only.

- **Calendar links:** add several at once on the setup page (one per line,
  `Name | link` to name one), by typing, or from `calendars.txt` (GZreader
  folder or the top of the USB drive). Each is fetched when added (named after
  its `X-WR-CALNAME`) and at every sync; `webcal://` is fetched over HTTPS,
  falling back to HTTP. Links are secret: kept in GZreader's settings, never
  logged (requests show the server only, `rawRequest`'s `log_url`). Times use
  the file's own VTIMEZONE rules; repeating events are expanded on the Kindle.
  Settings → Connections → Calendar → Calendar links: show / rename / remove,
  or the same on the setup page (*Add or edit links with QR code*), which
  also replaces a link that changed.

The CalDAV account: Nextcloud
(`https://your.server/remote.php/dav`), iCloud (`https://caldav.icloud.com`),
Fastmail (`https://caldav.fastmail.com`), Google
(`https://apidata.googleusercontent.com/caldav/v2/`), Radicale, Baïkal…

- **Connect:** before any calendar is added, the tab lists the ways: *Add
  with QR code* (the setup page: links, or a CalDAV account's address, user
  name and password; it also shows or hides each calendar), *Type a calendar
  link*, *Add from calendars.txt*, *Type a CalDAV account*, *Copy from another
  GZreader*, and *About calendar links* for the details. Use an app password where the server
  has them; it's kept in GZreader's settings like the Memos token and never
  logged (the log has addresses only, and passwords are redacted from it).
  Discovery follows RFC 6764: the address → `current-user-principal` →
  `calendar-home-set` → the VEVENT calendars in it (`/.well-known/caldav` is
  tried for a bare host; a calendar's own address works too).
- **Layouts:** Agenda, Day (timeline, overlapping events side by side),
  Week (seven columns), Month (grid). Letters open an event (a day in Week);
  Press opens what the 5-way is on; a day in Week or Month opens in Day. Page
  keys (or ‹ ›): next / previous day, week, month (Agenda: the next days).
  **N** today, **M** layouts, Refresh, settings.
- **Sync:** one `calendar-query` REPORT per calendar for the sync range
  (default 14 days back, 90 ahead), asking the server to expand repeating
  events (`<C:expand>`, times in UTC). Servers that don't expand send the
  RRULE, expanded on the Kindle (DAILY / WEEKLY / MONTHLY / YEARLY with
  INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY; EXDATE; RECURRENCE-ID). TZID times
  that aren't expanded are read in GZreader's time zone.
- **Wi‑Fi:** only to sync, when the tab opens (at most every 15 minutes) and
  with M → Refresh. Events are kept on the Kindle (`settings/gzreader-calendar.json`).
- **Settings → Connections → Calendar (CalDAV):** connection, calendars shown,
  the layout it opens in, week start (Sunday / Monday), sync range, storage.
  M → Calendar settings in the tab opens this same Settings page; the
  calendar is drawn again when you close it.
