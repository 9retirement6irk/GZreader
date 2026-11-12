Your [Memos](https://usememos.com) notes on the device.

The Notes tab (it took Favorites' place in the tab bar, V) shows your
[Memos](https://usememos.com) notes as sticky notes, pinned first (six to a
page in the usual layout: see Layouts below). Written against Memos v0.31 (`/api/v1`); newer servers that moved the
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
- **Board:** the letter on a note (Q, W, E…) opens it, ◀ ▶ (or the page keys) turn pages, the 5-way
  moves around the notes. **N** new note, **F** filter, **L** layout, **M** for refresh,
  connect again and disconnect (the Menu key opens the quick panel in tab views).
  Touch Kindles have New note, Filter, Layout and More buttons instead.
- **Layouts** (as in the Memos web app): **L** on the board (Layout on a touch
  Kindle, More → Layout on a Kindle 4, or Settings → Connections → Memos
  (Notes) → Layout) chooses how many notes side by side, and how long each is:
  - **List** (one note under another), **Two side by side** (the default),
    **Three side by side**, or **Auto**: as many side by side as fit the
    screen with room for about 22 characters a line (two upright, three
    sideways; at most four).
  - **Compact** (the default): every note the same size, three rows to a
    page (two sideways); a long note is cut off with "…" (open it to read it
    all). **Full:** each note as long as it needs, with all its pictures,
    nothing cut off, as many to a page as fit (each in the column with the
    most room, like Memos' masonry view). A note too long for the page goes
    on at the top of the empty column to its right, or on the next page,
    marked *continued*; its parts share one letter.
  - On the Kindles with keys a page holds at most ten notes, one per letter
    Q–P. After a change, the board shows the page with the note that was
    first on screen. The choice is kept.
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
  Alt+B bold, Alt+G tag, Alt+S save, Alt+V who can see it, Alt+A its space.
  Alt + the top row types 1–0 here. New notes are **private** unless you
  change it. Back asks whether to save.
- **Spaces** (Memos v0.31 and newer): beside who can see the note, the editor
  shows its **space** (tap it, Alt+A, or on a Kindle 4 Menu → ◀ ▶ to it).
  Choose **No space** or one of the spaces you're a member of. A new note
  starts in the space the board is showing (Filter → Space…). In a space,
  who can see it also offers **Space members** (only that space's members);
  taking a note out of its space turns Space members into Private, as Memos
  does. The note's page says which space it's in. With an older Memos (no
  spaces) none of this shows.
- **Quick note:** the quick panel's **Quick note** tile (at Home and in a
  book, while Memos is connected) opens the same editor over whatever is on
  the screen, so you can jot something down without leaving the book, Home or
  Settings. **Save** (or Back → Save) closes it and you're back where you
  were; "Note saved" says it's on its way. It's sent in the background a
  moment later (Wi‑Fi on Auto turns on for it; on Off it waits), and only the
  note is sent: the board's list isn't fetched while you read, so the Notes
  tab syncs the next time you open it. On a Kindle syncing through a
  computer it goes with the next sync. Hide the tile in **Settings →
  Interface → Quick panel**.
- **Filters:** tag, date (today, 7 days, 30 days, a year), pinned and search
  are Memos filters; place and "with attachments" are picked out on the
  Kindle (Memos v0.31 can't filter by them).
  **Space…** (when your Memos has spaces): **No space** or one of your
  spaces, with how many notes each has; the board's title says which.
- **Settings → Connections → Memos (Notes):** the Memos connection (connect again, disconnect);
  **Sync** all notes or only notes with chosen tags (Memos has no notebooks,
  so tags are the way to pick, and Filter → Space… for spaces; the list comes from Memos' tag
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
  Wi‑Fi up while it's open (Wi‑Fi on Auto).
