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
  moves around the notes. **N** new note, **F** filter, **L** layout, **S** sort, **M** connection
  (the Menu key opens the quick panel in tab views).
  Touch Kindles have buttons under the title instead: **New note**, **Filter**, **Layout**,
  **Sort**, **Connection**, and an icon for **Full screen** (an **X** while in full screen, to leave it).
  A Kindle 4 has neither letter keys nor buttons: its **Menu** key on the board
  opens New note, Filter…, Layout, Sort…, Full screen and Connection….
- **Connection** (the button, M, or Menu → Connection… on a Kindle 4): your
  Memos account only: **Refresh** (with how many changes are waiting to be
  sent), **Connect again** (a new address or access token) and
  **Disconnect** (asks first; the notes kept on the Kindle are removed, your
  notes in Memos stay).
- **Sort** (the Sort button, S, or Menu → Sort… on a Kindle 4): *Sort notes by*
  **Date created** (the default) or **Date edited**, **Reverse order**
  (oldest first) and **Pinned first** (on by default). Memos is asked for the
  notes in that order (`order_by`), and the Kindle sorts what it keeps the same
  way (notes written here and not sent yet, a sync through a computer).
- **Layouts** (as in the Memos web app): **L** on the board (Layout on a touch
  Kindle, Menu → Layout on a Kindle 4, or Settings → Connections → Memos
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
  - **Full screen: no tab bar** (also the full-screen icon on a touch Kindle,
    and Menu on a Kindle 4) hides the tab bar at the bottom of the Notes tab, for more
    notes on a page. The X where the icon was (or Layout) brings
    it back; Back or the quick panel's Home leave the tab.
- **A note:** the text in Patrick Hand, checklist items with letter keys
  (press one to tick or untick it; the change goes to Memos), pictures from
  the note shown inline, its tags and place, and its attachments (PDFs and
  other documents open in the reader, pictures in the image viewer; each is
  downloaded once into `cache/gzreader-notes`). **Alt+E** edits, **Alt+P**
  pins, page keys scroll a long note.
- **Notes from Memos' rich editor** (Memos 26.11 and newer): its empty
  paragraphs (`&nbsp;`), characters written as codes (`&amp;`, `&#124;`) and
  backslash escapes (`\*`, `\#`) show as Memos shows them: blank lines and
  the characters themselves. The editor here shows the note as it's written.
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
  book, while Memos is connected) opens the same editor in a window over
  whatever is on the screen (the page stays visible around it; on touch
  Kindles it sits above the keyboard, and a tap outside it is the same as
  Back), so you can jot something down without leaving the book, Home or
  Settings. **Save** (or Back → Save) closes it and you're back where you
  were; "Note saved" says it's on its way. It's sent in the background a
  moment later (Wi‑Fi on Auto turns on for it; on Off it waits), and only the
  note is sent: the board's list isn't fetched while you read, so the Notes
  tab syncs the next time you open it. On a Kindle syncing through a
  computer it goes with the next sync. Hide the tile in **Settings →
  Interface → Quick panel**.
- **Drawings** (touch Kindles, Memos over Wi‑Fi): in a new note, tap
  **✎ Draw** (beside who can see it) for a page to draw on, with **Thin**,
  **Medium** and **Thick**, **Eraser** (rubs out whole strokes, as in Memos),
  **Undo** and **Clear**. **Done** keeps it with the note (the button says
  **✎ Drawing**; tap it to go on drawing) and **Save** sends both. A note can
  be just a drawing. In Memos it's an attachment named
  `drawing-<date>-<time>.canvas.png`: Memos with drawings (its version after
  26.11.0) opens it as a drawing you can edit there; an older Memos shows it
  as a picture. Until it's sent, the board shows the note with the drawing.
  - **Editing a drawing** (touch Kindles): **Edit** on a note with a drawing
    opens the drawing. Draw more, rub out (strokes made in Memos too),
    Undo, Clear; **Done** goes back to the note's text and **Save** sends
    both. The new drawing goes over the old one in Memos (the same
    attachment, as Memos' Edit drawing does); an older Memos gets it added
    and the old one taken off; someone else's drawing keeps theirs and gets
    yours beside it. A drawing bigger than the screen is shrunk to fit.
    Shapes and text made in Memos stay as they are (they can't be changed
    on the Kindle). Done on an empty page takes the drawing off the note.
    Any note can get a drawing: ✎ Draw in its editor.
  - **Seeing drawings** (made on the Kindle or in Memos): on the Notes tab a
    note with a drawing shows its heading (if it has one) and the drawing
    as big as the note allows; **Layout → Full** shows it bigger, with all
    the note's text. Open the note for everything: its text, then the
    drawing as wide as the page (tap it to see it on its own). Drawings come
    down by themselves on Wi‑Fi, like the notes' other pictures.
  - **With a pen** (Kindle Scribe): only the pen draws. Fingers on the page
    draw nothing, and while the pen is near the screen, and for a moment
    after it leaves, your hand can rest anywhere on it: it's ignored (palm
    rejection). The pen's other end rubs out. With the pen away, a finger
    can tap the buttons at the top.
  - **With a finger** (every other touch Kindle): one finger draws; a second
    finger at the same time is ignored.
  - Not on Kindles syncing through a computer (the sync page doesn't send
    drawings).
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
