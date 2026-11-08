Your [Memos](https://usememos.com) notes on the device.

The Notes tab (it took Favorites' place in the tab bar, V) shows your
[Memos](https://usememos.com) notes as sticky notes, six to a page, pinned
first. Written against Memos v0.31 (`/api/v1`); newer servers that moved the
API to `/api` are found too.

- **Favorites** is still in Settings → Interface → Navbar → Tabs, turned
  off; turn it on there (or on the setup guide's Navbar Tabs page, which also
  offers Notes) to have both.
- **Connect:** the first time, the tab offers *Connect with QR code* (the
  setup page, at its Notes section: the Memos address and an access token) or
  *Connect by typing*. Create the
  token in Memos → Settings → My account → Access Tokens. The Kindle keeps
  the token (never your password) in GZreader's settings; it's never written
  to the log. An address without `https://` falls back to `http://` for a
  Memos on your home network.
- **Board:** Q–Y open a note, ◀ ▶ (or the page keys) turn pages, the 5-way
  moves around the notes. **N** new note, **F** filter, **M** for refresh,
  connect again and disconnect (the Menu key opens the quick panel in tab views).
- **A note:** the text in Patrick Hand, checklist items with letter keys
  (press one to tick or untick it; the change goes to Memos), pictures from
  the note shown inline, its tags and place, and its attachments (PDFs and
  other documents open in the reader, pictures in the image viewer; each is
  downloaded once into `cache/gzreader-notes`). **Alt+E** edits, **Alt+P**
  pins, page keys scroll a long note.
- **Editor:** a full page with a toolbar at the bottom: List, Check, Num,
  Head, *I*, **B**, # Tag and Save. **Menu** jumps to the toolbar from
  anywhere in the text (on the tool used last) and the cursor stays where it
  is, so the tool applies there; Menu again (or ▲) goes back to the text. ▼
  from the last line also reaches the toolbar; ◀ ▶ choose, Press applies. Shortcuts:
  Alt+L list, Alt+C checklist, Alt+N numbered, Alt+H heading, Alt+K italic,
  Alt+B bold, Alt+G tag, Alt+S save, Alt+V who can see it. Alt + the top
  row types 1–0 here. New notes are **private** unless you change it. Back
  asks whether to save.
- **Filters:** tag, date (today, 7 days, 30 days, a year), pinned and search
  are Memos filters; place and "with attachments" are picked out on the
  Kindle (Memos v0.31 can't filter by them).
- **Settings → Connections → Memos (Notes):** the Memos connection (connect again, disconnect);
  **Sync** all notes or only notes with chosen tags (Memos has no spaces or
  notebooks, so tags are the way to pick; the list comes from Memos' tag
  counts, `users/<id>:getStats`, and the filter is `tag in [...]`);
  **Storage used** with *Free up space* (downloaded attachments, kept
  notes); **Notes kept on the Kindle** (50–500, fetched a page at a time);
  **Attachment storage limit** (10–100 MB or none; the attachments used
  longest ago go first).
- **Wi‑Fi:** only to sync (when the tab opens, at most every 5 minutes, or with
  changes waiting; M → Refresh any time), to send a change, and to open an
  attachment not on the Kindle yet. Pictures in notes are downloaded while
  syncing (up to 2 MB each, within the attachment limit).
- **Offline:** the last list of notes is kept on the Kindle
  (`settings/gzreader-notes.json`); new notes, edits, ticks and pins made
  without Wi‑Fi wait in a queue and are sent the next time the Notes tab can
  reach Memos ("not sent yet" on the note meanwhile). The Notes tab keeps
  Wi‑Fi up while it's open (Wi‑Fi only when needed).
