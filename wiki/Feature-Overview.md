What GZreader does, in short, with where to read more. It connects an e-reader to the servers you host yourself (Grimmory for books, Memos, Plex, Immich, your calendars, Home Assistant); each is optional, and the parts below say which one they use. It runs on e-readers from the Kindle 2 and Nook 1 to the Kindle Scribe, and on Kobos (test build). Not every feature is on every device: see [Device compatibility](Device-Compatibility).

## Reading and your library

- **Reading** — EPUB, PDF, MOBI, AZW3, FB2, CBZ, TXT and more in KOReader's reader, with the ZenOS interface, a built-in dictionary and the quick panel for layout, fonts and light. → [Using GZreader](Using-GZreader)
- **Catalog** — one tab, three pages you swipe between: Books, Audiobooks and Music. Search and browse your [Grimmory](https://grimmory.org) server laid out like a bookshop: Continue reading, Recently added, All books, Libraries, Shelves (and magic shelves), Authors, Series. Lists open at once from a saved copy. → [Grimmory library](Grimmory-Library)
- **Downloads in the background** — with a progress bar, a queue, resuming after a dropped connection or a restart, and an auto-download shelf. → [Grimmory library](Grimmory-Library#home-folder-and-downloads)
- **Sync with Grimmory** — reading position (to the exact place, as an EPUB CFI the web reader understands), bookmarks, highlights and notes (both ways, with a three-way merge), ratings and reading sessions. → [Grimmory sync](Grimmory-Sync)
- **Bookshelves** — books stand on shelves, spines out, the selected one turns to show its cover; audiobooks as a cassette walkman, music as a CD player. Also lists and tiles. → [Home and bookshelves](Home-and-Bookshelves)
- **Bookshelf theme and ornaments** — an oak, walnut or plain plank, and ornaments on the shelves' free ends (plants, a clock, a model ship…, seasonal ones in their season, or your own pictures). Choose on a screen of tiles with a preview of your shelf, or hold an ornament; in colour on colour Kindles. → [Home and bookshelves](Home-and-Bookshelves)
- **Grimmory reading stats on Home** — read this week, day streak, books finished, across all your devices. → [Home and bookshelves](Home-and-Bookshelves#reading-stats-on-home)
- **Picture books** — scanned-page EPUBs are recognized and each page fills the screen. → [Picture books](Picture-Books)
- **Sleep screen** — the book's cover while reading, your pictures from Home: from the USB drive's `screensavers` folder (send them from your phone's browser) or from an Immich album. → [Home and bookshelves](Home-and-Bookshelves#sleep-screen)
- **Immich** — an album's photos as the sleep screen and the Home wallpaper, kept on the Kindle and changed now and then on Wi‑Fi. → [Home and bookshelves](Home-and-Bookshelves#pictures-from-immich)
- **English dictionary** built in (Open English WordNet).
- **Emoji** in notes, events and titles: black on every device, in colour on colour Kindles (OpenMoji). → [What's in GZreader](Whats-in-GZreader#emoji)

## Setting up

- **Set up from your browser** — scan one QR code (or type the address and PIN) and one page connects Grimmory (password or single sign-on), Notes, calendars and Plex. → [Setup page and connections](Setup-Page-and-Connections)
- **Send books from your browser** — pick EPUBs, PDFs and other books on your phone or computer and they go straight into Downloads (no Grimmory needed); pictures become sleep screens. → [Setup page and connections](Setup-Page-and-Connections)
- **Copy connections** from another GZreader over the Wi‑Fi with a PIN (SPAKE2, encrypted). → [Setup page and connections](Setup-Page-and-Connections#copy-connections-from-another-gzreader)
- **Cloudflare** — a key or an Access service token so servers behind Cloudflare let the Kindle through. → [Setup page and connections](Setup-Page-and-Connections#access-cloudflare)
- **No Wi‑Fi?** The Kindle 2 and DX sync through a web page on a computer, over USB: reading goes to Grimmory, books, audiobooks, music, notes, calendars and updates come back. → [Sync with a computer](Sync-with-a-Computer)

## More than books

- **Notes** — your [Memos](https://usememos.com) notes as sticky notes, in a list or side by side, compact or whole; tick checklists, offline too; journal entries. On touch Kindles a **rich text editor** like Memos' web editor: the note formatted as you type, with a formatting bar for headings, bold, italic, lists, checklists and tags. → [Notes](Notes)
- **Drawing notes** — full drawing on touch and pen Kindles: with a finger, or with the Scribe's pen (pressure, the side button erases, your hand can rest on the screen). Pen, fountain pen, marker, pencil, highlighter and eraser, undo and redo, pinch zoom, pages and notepaper (ruled, Gregg, dot grid, graph, Cornell…). Drawings go to Memos as Memos' own drawings, and drawings made in Memos show and edit on the Kindle. → [Notes](Notes)
- **Calendars** — calendar links (Proton, Google, Outlook…) and CalDAV accounts: agenda, day, week, month. → [Calendar](Calendar)
- **Music** — albums and playlists from Plex, downloaded and played while you read (Kindles with a speaker or headphone jack, or with Bluetooth). → [Music](Music)
- **Audiobooks** — from Grimmory (or Plex), with your place kept in sync (Kindles with a speaker or headphone jack, or with Bluetooth). → [Audiobooks and read aloud](Audiobooks-and-Read-Aloud)
- **Read aloud** — any EPUB, MOBI, AZW3, FB2 or TXT in the Kindle's own voice, the sentence highlighted and pages turning by themselves (Kindle 2, 3, DX, Touch; on Bluetooth Kindles in Amazon's voice). → [Audiobooks and read aloud](Audiobooks-and-Read-Aloud#read-aloud-kindle-2-3-dx-text-to-speech)
- **Bluetooth** — pair and connect headphones or a speaker from Settings on the Kindles that have Bluetooth (Scribe, Paperwhite 5 and newer…). → [Bluetooth](Bluetooth)
- **House** — your [Home Assistant](https://www.home-assistant.io) rooms: lights, switches, thermostats, locks, garage doors and scenes to switch from the Kindle, straight over your Wi‑Fi (Kindles with Wi‑Fi). → [House](House)
- **Recipes** — an optional tab with the recipes of your [Mealie](https://mealie.io): search, categories, and a recipe's ingredients and steps to read while you cook; opened recipes stay readable without Wi‑Fi. Sign in with an API token or Mealie's single sign-on (Kindles with Wi‑Fi). → [Recipes](Recipes)

## Using it

- **The quick panel** — one panel of square tiles on every device (Menu, or swipe down): Wi‑Fi, night mode, sleep, updates, settings, and what fits where you are (Home or the book); choose its tiles in Settings → Home and tabs → Quick panel. → [Using GZreader](Using-GZreader#choosing-the-tiles)
- **Letter keys everywhere** on keyboard Kindles; the 5-way on the Kindle 4; touch on the others, and the pen on the Kindle Scribe; the colour touchscreen on the Nook 1st Edition; touch and page keys on Kobos. → [Using GZreader](Using-GZreader), [Kobo](Kobo)
- **First-time tour** on touch Kindles, showing the quick panel. → [Using GZreader](Using-GZreader#touch-kindles-kindle-touch-paperwhite-3-scribe)

## Looking after itself

- **Updates from GitHub** over Wi‑Fi (or the sync page), with a **What's new** screen after each; **test builds** for trying changes early. → [Updates and test builds](Updates-and-Test-Builds)
- **Wi‑Fi on, off or auto** — Auto (the default) turns it on for what needs it and off after a minute, to save battery; the quick panel's Wi‑Fi tile goes through the three. → [Wi‑Fi](Wi-Fi)
- **Faster on old Kindles** — a shadow screen for drawing, precompiled code, pre-sized covers. → [Performance](Performance)
- **Debug reports and diagnostics** — no usage statistics; debug reports go to the developer only if you choose, and the diagnostic log goes to the developer in one tap. → [Privacy and diagnostics](Privacy-and-Diagnostics)
