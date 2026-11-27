Your calendars on the device, read-only.

The Calendar tab (B) shows calendars from their **shared links** (webcal:// or
https://….ics: Proton Calendar's Share → Share with anyone, Google's secret
iCal address, Outlook's published ICS…) and/or a **CalDAV account**, read-only.

- **Calendar links:** add several at once on the setup page (a **Name** and a
  **Calendar link** field for each, three to start with and *Add another link*
  for more; empty rows are skipped), by typing, or from `calendars.txt` (GZreader
  folder or the top of the USB drive). Each is fetched when added (named after
  its `X-WR-CALNAME`) and at every sync; `webcal://` is fetched over HTTPS,
  falling back to HTTP. Links are secret: kept in GZreader's settings, never
  logged (requests show the server only, `rawRequest`'s `log_url`). Times use
  the file's own VTIMEZONE rules; repeating events are expanded on the Kindle.
  Dates are worked out without the Kindle's clock (which reaches only 1901 to
  2037), so iCloud's shared links (their time zones start in 1883), birthdays
  from before 1901 and events repeating past 2037 are read too.
  Settings → Accounts and services → Calendar → Calendar links: show / rename / remove,
  or the same on the setup page (*Add or edit links with QR code*), which
  also replaces a link that changed.

- **Holidays:** a calendar of their own, worked out on the Kindle (no link,
  account or Wi‑Fi: the Kindle 2 and DX have them too), off until turned on:
  Settings → Accounts and services → Calendar → **Holidays** (*Show holidays*, and the
  country: United States, Canada or United Kingdom), *Show holidays* on the
  tab's first screen, or the setup page's **Holidays** box. They show all day
  in every layout, as "Holidays (United States)"; Calendars shown hides them
  too. The United States: New Year's Day, Martin Luther King Jr. Day,
  Valentine's Day, Presidents' Day, St. Patrick's Day, Easter, Mother's Day,
  Memorial Day, Father's Day, Juneteenth, Independence Day, Labor Day,
  Columbus Day / Indigenous Peoples' Day, Halloween, Veterans Day,
  Thanksgiving, Christmas Eve, Christmas Day and New Year's Eve. Canada and the
  United Kingdom have their own (Victoria Day, Canada Day, Thanksgiving in
  October, Boxing Day; the bank holidays, Mothering Sunday, Bonfire Night…).
- **Colours** (Colorsoft, Scribe Colorsoft): each event's bar is in its
  calendar's colour, the one your calendar app gave it (CalDAV's calendar
  colour, or an Apple-style link's), else one of six colours in turn; holidays
  in red. Other Kindles tell the calendars apart by shades of grey.

The CalDAV account: Nextcloud
(`https://your.server/remote.php/dav`), iCloud (`https://caldav.icloud.com`),
Fastmail (`https://caldav.fastmail.com`), Google
(`https://apidata.googleusercontent.com/caldav/v2/`), Radicale, Baïkal…

- **Connect:** before any calendar is added, the tab lists the ways: *Add
  with QR code* (the setup page: links, or a CalDAV account's address, user
  name and password; it also shows or hides each calendar), *Type a calendar
  link*, *Add from calendars.txt*, *Type a CalDAV account*, *Copy from another
  GZreader*, *Show holidays*, and *About calendar links* for the details. Use an app password where the server
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
  INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY, BYMONTH, BYSETPOS, WKST; EXDATE;
  RECURRENCE-ID): Outlook's and Apple's "first Monday" or "last weekday" of
  the month show on that one day. TZID times that aren't expanded are read in
  GZreader's time zone.
- **Wi‑Fi:** only to sync, when the tab opens (at most every 15 minutes) and
  with M → Refresh. Events are kept on the Kindle (`settings/gzreader-calendar.json`).
- **Settings → Accounts and services → Calendar:** connection, calendars shown,
  the layout it opens in, week start (Sunday / Monday), sync range, storage.
  M → Calendar settings in the tab opens this same Settings page; the
  calendar is drawn again when you close it.

## On the sleep screen

Your calendar can be what the Kindle shows while it sleeps. In
**Settings → Sleep and wallpaper → Sleep → Wallpaper**, with a calendar set
up, tap one of two tiles:

- **Today's calendar**: today in big, with its events beside it, then the
  next days that have events, as many as fit.
- **This week's calendar**: the week, a day a row, today shaded.

The page is drawn from the events kept on the Kindle, so going to sleep never
waits for Wi‑Fi. It stays fresh by itself: when Wi‑Fi connects and the last
sync is more than an hour old, the calendar syncs again (and whenever the
Calendar tab opens, as before). The page says when it last synced, in small
grey type. To go back, tap another tile.

### A calendar card over your wallpaper

To keep your own wallpaper (a picture, the book's cover) and still see what's
coming up, put a small calendar card on top of it, the way the sleep screen
message sits on top. In **Settings → Sleep and wallpaper → Sleep**, tap
**Calendar on the wallpaper** and choose **At the top** or **At the bottom**
(or **Off**). The card shows the day and date, then up to five events from
today and the next seven days ("12:00 PM", "Tomorrow", "Sat 7:00 PM"), and
when it last synced. It works with any wallpaper and with a sleep screen
message at the same time; it isn't drawn over the calendar sleep screens,
which show the calendar already. It's drawn from the events kept on the
Kindle and synced when Wi‑Fi connects, as above.
