-- GZreader changelog, newest first. Shown in Settings → Updates → Changelog.
-- Add an entry (and bump GZREADER_VERSION) for every release.
-- A line is { short = "…", text = "…" }: `short`, a few words, on the screen
-- after an update (gzreader_whatsnew.lua); `text`, the full explanation, here
-- in Settings → Updates → Changelog and in the release notes. Keep each line
-- on one line (the beta branch combines "next" lines). A plain string is the
-- text alone (the screen shows its first sentence).
return {
    {
        version = "next",
        changes = {
            { short = "New books are laid out while the Kindle charges, so their first open is quick", text = "While the Kindle charges and Home is on screen, GZreader lays out downloaded books you haven't opened yet in the background (Settings → Reader → Lay out new books while charging, on by default), so the first time you open one it opens like a book you've read before instead of taking 10–30 seconds on a Kindle 3. It waits while books download or other background work runs, and for a new book's picture-book check (a picture book is laid out the way it will be fitted), stops as soon as you unplug, open a book or start a download, and the books don't show as opened. Not on the Kindle 2 and DX (not enough memory)." },
        },
    },
    {
        version = "1.28.1",
        changes = {
            { short = "Catalog: the Shelves card's label on one line on the Paperwhite", text = "Catalog → Books: the little cover on the Shelves card (and a shelf's name there) no longer breaks a word in two, as \"Shelve / s\" on the Paperwhite 3: its label gets smaller until every word fits." },
            { short = "The Catalog opens without Grimmory; Grimmory and Plex cards instead of On this Kindle", text = "The Catalog tab opens even when you aren't signed in to Grimmory: the Music page, and audiobooks from Plex, work as usual, and the Books page (and the Audiobooks page, for Grimmory's audiobooks) has empty shelves and says \"Sign in to Grimmory to browse the catalog\"; tap it for the ways to sign in, and the page fills in once you are. The Books and Audiobooks pages' bottom-right compartment is now a Grimmory card filling it (who you're signed in as, and where; it opens Rebuild library and reconnecting); the Music page's Plex card fills its compartment there too, and with audiobooks from Plex the Audiobooks page has the Plex card instead. The On this Kindle cards are gone from the Books, Audiobooks and Music pages: what's on the Kindle is in the Downloads tab. Also fixed: in the Bookshelf view, tapping the Audiobooks and Music pages' search slip did nothing, and back from a change in the Plex card's list showed an empty list." },
            { short = "Kindle 2, 3, DX: Sym opens a symbols menu, like the Kindle's own", text = "On the Kindles with a keyboard, pressing Sym in a text box (search, Wi-Fi password, server address, notes...) opens a small menu of symbols, as the Kindle's own software does, instead of the whole on-screen keyboard: the 5-way picks a symbol and pressing it types it; the menu stays up for more symbols (letters can be typed too) until you press Sym again (or Back). It opens on the symbol you used last. Shift + Home still shows the whole on-screen keyboard, and Sym + a letter still types its symbol." },
            { short = "Sleep screen: a picture at Home again with \"Book cover while reading, a picture elsewhere\"", text = "Settings → General → Sleep → Wallpaper → Book cover while reading, a picture elsewhere showed whatever sleep screen had been saved before instead: a picture while reading, or (after choosing Book cover once and then this tile again) the book's cover at Home too. It now shows the open book's cover while reading and a picture from the screensavers folder from Home and menus, whatever was chosen before it." },
            { short = "Wi-Fi is On, Off or Auto: the quick panel's Wi-Fi tile goes through them, and the status bar shows an A on Auto", text = "Wi-Fi now has three modes instead of a Wi-Fi switch plus a separate \"Wi-Fi only when needed\" setting. On: Wi-Fi stays on (GZreader turns it back on if it went off by itself). Off: it stays off and syncing waits; things you ask for still turn it on for a minute. Auto (the default, what \"Wi-Fi only when needed\" did): on when something needs it, off after a minute unused. The quick panel's Wi-Fi tile goes on → off → auto; Settings → General → Wi-Fi offers the same three, with Networks under them. On Auto the status bar's Wi-Fi icon has an A after it and still shows whether Wi-Fi is on right now; the tile's icon does the same. Turning Wi-Fi on or off anywhere else chooses On or Off. Your earlier settings carry over." },
            { short = "Usage statistics: time in each part of GZreader, and what plays", text = "Usage statistics now report how long you spend in books, on the Catalog's Books, Audiobooks and Music pages, in the Audiobooks and Music tabs, in Notes and in Calendar, and how long read aloud, audiobooks and music play, each with GZreader's version, the Kindle model and firmware. Basic and Full send the same statistics; Full also sends the debug reports. No more events for each menu entry chosen or for each start (how the previous run ended is in the debug reports). Still no titles, file names or account." },
            { short = "Menus look like ZenOS's: an icon, an arrow, short labels", text = "GZreader's menus look like ZenOS's Settings: the Calendar and Notes tabs' connect lists, Plex's sign-in and the Music list, Downloads, the sync queue, copying from another GZreader, the Notes filters, the font list and Add to shelf now have an icon on the left of each row, an arrow on the right of each row that does something and ZenOS's spacing. Labels are shorter so none is cut off at the edge of the screen; the longer explanations moved behind an About row (About calendar links, About Memos, About Plex music). Downloads shows each title with where it's at on the right (38% of 77.0 MB, waiting), and copying from another GZreader has a switch per connection." },
            { short = "Catalog: the pages go round (before Books: Music; after Music: Books)", text = "The Catalog's pages go round: turning back from Books (a swipe right, the page-back button, or ‹ Music on the strip) goes to Music, and turning on from Music goes to Books. The strip under the title now always shows a page on each side." },
            { short = "Quick panel: the Updates tile says when an update is available", text = "When the daily update check (or a check from Settings → General → Updates) has found a newer version, the quick panel's Updates tile reads \"Update available\" and is drawn white on black, also after a restart. Nothing is downloaded to draw it; tap it to see the update and install it, as before." },
        },
    },
    {
        version = "1.28.0",
        changes = {
            { short = "Fewer writes to the Kindle's storage: the log and the remote-debugging heartbeat", text = "GZreader's diagnostic log writes ordinary lines a few at a time (at most 5 seconds late; warnings, errors, sleep, exit and saving or sending the log write at once) instead of opening the file for every line. With Full usage statistics, the 15-second heartbeat goes to /tmp (memory) instead of the Kindle's storage, which is now written only when GZreader starts, sleeps, wakes or exits and every 10 minutes: about 150 writes a day instead of 5,760." },
            { short = "Sleep screens shown as tiles with previews", text = "Settings → General → Sleep → Wallpaper shows each sleep screen as a tile with a preview of what it shows (GZreader's own, the last book's cover, a picture from the screensavers folder, reading progress, book status, the screen as it is): tap one, or press its letter on a Kindle with keys. The cover's fill and fit, when to ignore a cover and the wake-up delay are in Wallpaper options. Sleep no longer has Presets, and there is no custom image to choose." },
            { short = "Every Settings entry has an icon", text = "Every entry in Settings has an icon, also the choices inside submenus and KOReader's own menus, which showed an empty space." },
            { short = "Storage, Language, and Time and date are in General", text = "Settings → General now has Time and date (with Time zone first), Language and Storage. Storage is a menu like the others: free space, then books, audiobooks, music, notes, the calendar and covers, each with its size, an icon and an arrow into the biggest of each. The Storage section at the top of Settings is gone." },
            { short = "Downloads in Settings has the Downloads tab's icon", text = "Settings → Downloads now has the same icon as the Downloads tab on Home." },
            { short = "Report a bug sends to GZreader's developer", text = "Settings → About → Report a bug asks what happened and sends it with the diagnostic log to GZreader's developer (as Send to the developer does). It used to be ZenOS's reporter, which filed the report and crash.log as an issue for the ZenOS project." },
            { short = "About shows GZreader's version first", text = "Settings → About starts with GZreader's version, then \"Built on ZenOS … and KOReader …\"." },
            { short = "Diagnostic log settings moved to General → Advanced", text = "Diagnostic logging, Send diagnostic log to the developer, Send diagnostic log to a browser and Save diagnostic log moved from Settings → General to the top of General → Advanced. Usage statistics stays in General." },
            { short = "Fewer settings that did nothing or could break GZreader", text = "Settings → General → Advanced no longer has Debug logging (KOReader's verbose log; turned off once if it was on), Clear all gestures (nothing in GZreader reads the gestures it set), Plugin management or Patch management (turning off GZreader's own plugins broke it). The KOReader section leaves out its File browser menu (sorting and filtering are in the Downloads tab's own menus; its other settings repeat Downloads'), Tools → Reading statistics (the statistics themselves stay: time left, book details, the end-of-book page), Plugin management, Patch management, Developer options, the file browser's Display mode and Start with, the Wi-Fi actions and Restore Wi-Fi (Wi-Fi only when needed does this), its second copy of the Grimmory menu, and in Help, KOReader's Report a bug and Disable external plugins (which turned GZreader itself off)." },
            { short = "No Manga, News or Calibre Search tabs", text = "Settings → Interface → Navbar no longer offers the Manga, News and Calibre Search tabs, whose apps (Rakuyomi, QuickRSS, calibre) aren't part of GZreader, and the bar leaves them out if they were on." },
            { short = "Downloads screen: only the changed lines refresh", text = "The Downloads screen kept its percentages current by redrawing the whole screen every 5 seconds, and went back to its first page each time. Now only the lines that changed are refreshed, on the page you're on, and nothing at all when nothing changed; the whole list is redrawn only when a download finishes or one is added." },
            { short = "A book's page and Download turn Wi-Fi on first", text = "The Grimmory tab's lists open from what's saved on the Kindle, so with Wi-Fi only when needed Wi-Fi was often off when you opened a book's page: its description and cover didn't come, and Download failed at once (\"temporary failure in name resolution\"). Both now turn Wi-Fi on first, like the rest of the Grimmory tab." },
            { short = "Audiobooks on the bookshelf: the walkman wears its headphones, like the CD player", text = "Downloads, on the bookshelf: the Audiobooks walkman now has its headphones sitting on it (the band over its top, a pad resting on each side), as the Music CD player does, instead of standing beside it." },
            { short = "Browsing Grimmory while a book downloads", text = "While a book downloaded, it took the Kindle's Wi-Fi and processor, so the Grimmory tab's descriptions and covers took 10 to 40 seconds or didn't come at all. Now the download waits while the tab (or anything else) asks Grimmory for something, 20 seconds at most each time, and carries on as soon as that's answered." },
            { short = "Sleep screen: covers can fill the whole screen", text = "Settings → General → Sleep → Wallpaper options → Border fill, rotation, and fit → Scale cover to fill screen scales the book cover (or sleep picture) up until it covers the whole screen, keeping its proportions: no bars at the edges, and the parts that don't fit are cut off. It replaces Stretch cover to fit screen while it's on, which pulls the cover out of shape." },
            { short = "Settings → Connections → Grimmory → Rebuild library", text = "Loads the list of your books from Grimmory again and forgets the saved lists, so books removed from Grimmory disappear from the Kindle's lists (and their missing covers stop being asked for) and new ones show. Until now that was only Refresh list from Grimmory, inside Authors or Series." },
            { short = "Kindle 2/3/DX/4: no flash for what changes by itself; download status every 3 s", text = "On the Kindles without REAGL, GZreader flashes the screen when most of it changes, to clear the grey traces. It did that also for changes nobody asked for: a book finishing its download flashed the whole Downloads tab. Now only what follows a key or a tap (in the last 10 seconds) flashes. The download status in the status bar is updated every 3 seconds instead of 10 (only that item is refreshed)." },
            { short = "Downloads shelves take as many books as fit; letters Q to L", text = "In the bookshelf view, a page of Downloads held as many books as the widest spines would fit, so shelves of narrower books ended with room for two or three more. Now each page takes as many as its books' spines leave room for. On Kindles with a keyboard the letter keys go from Q to L: the books after L have none (the 5-way reaches them) and Del is no longer a book's key." },
            { short = "Downloads shelves: the CD player lies on the shelf", text = "Music's CD player on the top shelf (bookshelf view) was drawn tilted towards you, so it seemed to float above the board next to the standing walkman. It now lies flat on the shelf, seen from the front, with its headphones resting on it." },
            { short = "Music's CD player: the album's cover fills the disc", text = "Music's Now playing: the CD in the player now fills the lid's window, with the album's cover printed over the whole disc (a thin silver rim and the clear ring round the hole left), instead of a small round cover in the middle of a bare disc. A cover that isn't square fills the disc too (its sides are cut off rather than leaving grey bands)." },
            { short = "Audiobooks from a Plex library instead of Grimmory", text = "Audiobooks can come from a library on your Plex server instead of Grimmory: Settings → Connections → Plex → Audiobooks (or Plex in the Music tab) lists Grimmory and the server's music libraries. With a Plex library picked, the Catalog's Audiobooks page shows it (search, Continue listening, Recently added, All audiobooks, Authors, On this Kindle), with Plex's covers. A Plex audiobook downloads and plays like Grimmory's (an album is a book, its tracks its files or chapters); its place goes to Plex and comes back from any Plex player. The sync page lists the same library for Kindles that sync through a computer, and can switch between Grimmory and Plex there." },
            { short = "Plex: choose which music library to use", text = "A Plex server with more than one music library: pick the one GZreader uses in Settings → Connections → Plex → Music library (or Plex in the Music tab). Artists, Albums, Recently added and Recently played come from it, and with several music libraries Playlists and Search keep to it too. Until you pick one it's the server's first, as before; the choice is kept per server, and the sync page lists the same library's albums." },
            { short = "Catalog → Music: Recently played, Recently added, Playlists, Albums, Artists; albums as CD cases", text = "The Catalog's Music page is laid out like the Books page: Search music at the top, Recently played (this Kindle's, then Plex's) and Recently added shelves, then Playlists, Albums and Artists (with On this Kindle, Now playing and your Plex account when there's something to show). In the Bookshelf view albums and playlists stand on the shelves as CD cases with their covers from Plex, marked ON KINDLE when they're downloaded, with the title, artist and year under each." },
            { short = "Catalog → Audiobooks: Continue listening, Recently added, Authors, Shelves, Series and search", text = "The Catalog's Audiobooks page is laid out like the Books page: Search audiobooks at the top (titles, authors and series, audiobooks only), Continue listening (what you've listened to on the Kindle, then what Grimmory has in progress) and Recently added shelves with covers, then a bookcase with All audiobooks, Authors, Shelves, Series and On this Kindle. Authors and Series list only those with audiobooks, with how many; Shelves leaves out your shelves with no audiobook on them. An author's, series' or shelf's list has its own search." },
            { short = "Quick panel: Music and Audiobook tiles only while one plays", text = "The quick panel's Music tile is there only while music plays or is paused (it opens Now playing), and the Audiobook tile only while an audiobook plays or is paused (it opens its player), now in a book too. Browsing and downloading music and audiobooks is the Catalog tab's; what's on the Kindle is in Downloads." },
            { short = "An Audiobooks tab, if you want one", text = "A new Audiobooks tab (off until you turn it on in Settings → Interface → Navbar → Tabs, or in the setup guide's tab page; Kindles with a speaker or headphone jack) opens the Catalog's Audiobooks page on its own, with that tab underlined. The Music tab stays as it was." },
            { short = "Catalog → Books: Downloaded is now On this Kindle (On this Nook)", text = "The Books page's last compartment and list, Downloaded books, is now called On this Kindle (On this Nook on a Nook), as on the Audiobooks and Music pages; its card counts the books there (\"none yet\" when there are none)." },
            { short = "The Grimmory tab is now the Catalog: Books, Audiobooks and Music pages", text = "The Grimmory tab is renamed Catalog and has pages: Books (as before), Audiobooks (Grimmory's audiobooks) and Music (Plex), on Kindles with a speaker or headphone jack. Swipe left or right, tap the next page's name under the title, or use the page-turn buttons; the title says which page you're on, and dots under it show where you are and what's next. The tab always opens on Books. On the Books page the bookcase's last compartment is now Downloaded books on every Kindle (Audiobooks have their own page). A tab you had renamed keeps its name." },
            { short = "ZenOS 4.3.1: invert highlight colours at night, more highlight options, footnote fonts", text = "Updated to ZenOS 4.3.1. Settings → Reader → Highlight / Lookup → Highlight has \"Invert colors in night mode\" (KOReader's own inversion instead of keeping a highlight's day colour) and \"Show other items\": other KOReader and plugin highlight options behind a More button in the highlight menu (Highlight / Lookup → Lookup has its own \"Show other items\" now). Footnotes and references use all of the book's font settings. Fixed: a rare crash when tapping in the page browser." },
            { short = "Picture books: Fit pictures works while another book is being measured", text = "A picture book is fitted after GZreader measures its pictures in the background. When a second picture book was opened (or Fit pictures to the screen was tapped in it) while the first one was still being measured, nothing happened: the book was never fitted. Now it's fitted as soon as the first one is done, and a note says the pages will be fitted in a moment." },
            { short = "Music's CD player: the headphones' band reaches both ear pads", text = "On the Now playing screen's CD player, the headphones' band stopped short of the right ear pad, and the slider sat off to one side of it. The band now runs into the pad, with the slider on it, as on the left." },
            { short = "Closing a book no longer pokes the Kindle's voice when it wasn't reading", text = "Closing a book sent the Kindle's voice a stop request every time, even when read aloud hadn't been used. On a Kindle 2 or DX that meant starting a small program at each close, and one of its two requests failed (the property doesn't exist on that firmware), a line in the system log each time. Now it's only sent when read aloud was on, and only what this Kindle's voice has." },
            { short = "Sync page: turning test builds off offers the release again", text = "On the sync page (Kindles without Wi-Fi), a Kindle on a test build such as 1.27.0-beta.5995ce3 with Test builds turned off was offered nothing, because the page compared only the version numbers and the release (1.27.0) has the same one. A release now counts as newer than a test build of its number, as GZreader itself counts it, so the release is offered." },
        },
    },
    {
        version = "1.27.0",
        changes = {
            { short = "Saving is quicker with a big library: small changes no longer rewrite the download list", text = "Most of GZreader's saves (a reading position queued, something sent) changed only a few small things, but rewrote its whole settings file, download list and audiobooks included: about a quarter of a second of a Kindle 3's time per save with 500 books. Those saves now write only the small part, to a small file of its own; the whole file is written when a download or the sign-in changes, when the Kindle goes to sleep, on exit and at least every hour, so it stays complete for an older GZreader." },
            { short = "Kindle 2/DX: Send to the developer, through the sync page", text = "Kindle 2 and DX (no Wi-Fi): Diagnostics → Send to the developer asks what happened, as on a Wi-Fi Kindle, and saves the log with it; the sync page sends it to the developer at your next sync. The page's Sync tab also has a Diagnostics box to send the Kindle's log with a note of your own. With diagnostic logging on, pressing Sync on the Kindle first exports a fresh log for it." },
            { short = "Less processor time for GZreader's data: the library, lists, sync and the outbox", text = "GZreader now reads and writes its data (Grimmory's lists, the library index, the library copy on Kindles without Wi-Fi, the outbox, background results, saved lists) with KOReader's built-in C library for JSON instead of its Lua one, which was 5 to 10 times slower on a library's worth of books. Nothing changes in what's stored or sent." },
            { short = "Bookmarks from Grimmory no longer wipe the Kindle's bookmarks", text = "Bookmark sync took every bookmark Grimmory sent for an audiobook bookmark (Grimmory marks the audio time as empty, and GZreader read empty as set): opening a book again removed the bookmarks already synced from the Kindle and brought none in, not even ones added in the web reader. Now they're all kept on both sides; the ones that went missing come back from Grimmory the next time the book opens. A bookmark deleted from the bookmark list is now deleted in Grimmory too." },
            { short = "Your notes now show in Grimmory's Notes tab, both ways", text = "Grimmory's web reader doesn't show a highlight's note, only the notes in its Notes tab, so notes made on the Kindle seemed not to sync. Each note is now also kept there (at its highlight, with the words and colour), and notes made, changed or deleted in the web reader come to the Kindle. An edited note is sent when the book closes." },
            { short = "Choose the quick panel's tiles: Settings → Interface → Quick panel", text = "Settings → Interface → Quick panel lists the tiles of the quick panel's Controls, Home and This book groups: untick a tile to take it off the panel, or Show every tile to bring them all back. Home, Settings and Exit to Kindle always stay. It replaces Interface's Controls and Launcher, which set up ZenOS's touch menu (the quick panel took its place); Blur menu background is still in Interface." },
            { short = "The quick panel's Layout tile works on touch Kindles", text = "In a book, the quick panel's Layout tile (font size, margins, spacing) did nothing on touch Kindles such as the Paperwhite: Zen mode blocked it. It opens the layout menu again." },
            { short = "Zen mode is always on", text = "Zen mode (ZenOS's own tabs only) is always on: its switch is gone from Settings → Interface, and it's turned back on if it was off." },
            { short = "Headphone check while playing: no program started every second", text = "While music, an audiobook or read aloud plays, the check for unplugged headphones reads the Kindle's audio service in GZreader itself (KOReader's lipc library) instead of starting lipc-get-prop every second; where that library can't be used, it starts it every 4 seconds instead of every second. Less CPU and battery while listening." },
            { short = "A quicker start: ZenOS's unused updater and manga plugin code aren't loaded", text = "GZreader no longer loads ZenOS's own updater at every start (about 1,900 lines that GZreader's updater replaces), nor ZenOS's integration for the Rakuyomi manga plugin, which GZreader doesn't ship. GZreader's updater itself is loaded when it's first needed. Less to load and less memory used from the start, most noticeable on the Kindle 2, DX and Keyboard." },
            { short = "Background syncing reuses one connection to Grimmory instead of a new one per request", text = "Requests GZreader makes in the background (a book's sync, the library index, automatic shelves) now keep their connection to the server open between requests instead of opening a new secure connection for each, which on a Kindle 3 was most of the time a request took. Indexing a 2,000-book library goes from 40 secure connections to one. A connection the server closed meanwhile is opened again." },
            { short = "Opening a book syncs in one background process instead of four", text = "When a Grimmory book opens, its place, queued updates, bookmarks and highlights are now synced together a moment after the first page, in one background process, instead of four started at 1, 2, 4 and 6 seconds. On a Kindle 3 each one was a copy of GZreader and a secure connection: seconds of processor time while you turned the first pages. Sync now and syncing after Wi-Fi comes on work the same way." },
            { short = "Smoother page turns while GZreader syncs in the background", text = "Syncing, downloads, the library index, update checks and usage statistics now run their background processes at a lower priority than the screen. Each request's secure connection takes seconds of processor time on a Kindle 3, and opening a book starts several; page turns no longer wait for them." },
            { short = "Kindle 2, DX, 3 and 4: the clock in a book updates with the page, not every minute", text = "On the Kindles without REAGL, the clock and battery at the top of a book are updated when you turn a page instead of with a refresh of their own every minute while nobody's reading (the clock shows the time of the last page turn). GZreader's own timers (usage statistics, the remote-debugging heartbeat, the Wi-Fi idle check) now fire together on the quarter minutes, so the Kindle wakes less often, and the Kindle 2, 3 and DX pack the screen four pixels at a time (about a third less time per refresh)." },
            { short = "Experimental, in Settings: keep connections to your servers open while Wi-Fi is on", text = "Experimental, off by default (Settings → Connections → Grimmory → Keep connections open): while Wi-Fi is on, a small separate process keeps the connections to Grimmory (and your other servers) open between GZreader's background requests, so browsing the Grimmory tab doesn't open a new secure connection for every page. If it isn't running or doesn't answer, requests go directly as before." },
            { short = "Diagnostics: a line in the log for each start", text = "The diagnostic log has a line for each start, like the one for each book opened: how long until Home (or a book) was on the screen, the processor time, when GZreader's own part started and how long it took, modules loaded, memory used and free. Send the log after a few starts to show where a slow start goes." },
            { short = "Books open sooner: reading statistics are looked up after the first page", text = "Opening a book: the reading statistics' lookups (the book's record and its reading time so far, slower the more you've read it) now run just after the first page is on the screen instead of before it. The time-left estimate uses the totals saved with the book until then." },
            { short = "Swiping down for the quick panel in a book no longer changes the light", text = "Touch Kindles with a frontlight: opening the quick panel in a book by swiping down from the top changed the light to wherever the finger crossed the light slider. The slider now only moves when you tap it or put your finger down on it and drag." },
            { short = "The clock at the top of a book no longer disappears after Layout", text = "The reader's top status bar (Settings → Reader → Appearance → Top status bar: the clock, by default) no longer disappears while the layout menu (the quick panel's Layout tile) is open or after it closes. It was drawn only while nothing else was open over the book, so it stayed missing until the next page turn or the next minute." },
            { short = "Square cover corners in the Bookshelf view", text = "In the Bookshelf view covers have square corners: Settings → Downloads → Appearance → Covers → Rounded cover corners is off and greyed out there. Your choice for the other views (Tiles, the lists) is kept and comes back when you pick one of them in the quick panel's View." },
            { short = "Settings: Library is now called Downloads", text = "Settings: the Library section is now called Downloads, like the tab it sets up (Appearance, Folders, Books, Context menu: unchanged inside)." },
            { short = "Settings: no Metadata menu (book details come from Grimmory)", text = "Settings → Downloads → Books no longer has a Metadata menu (ZenOS's online sources, Hardcover and Google Books keys, match selection, EPUB backup): your downloads' title, authors and series come from Grimmory. Saved values still apply to ZenOS's Edit metadata (a book's Edit menu outside Downloads), which looks books up on Open Library (and on Hardcover or Google Books only if a key was saved before)." },
            { short = "Diagnostic log files no longer pile up on the Kindle", text = "Send to a browser (and the setup page's Diagnostics tab) left a copy of the log (about 700 KB) next to the GZreader folder every time. The log is now built in the cache and deleted once it's sent, as Send to the developer already did. Save to the Kindle keeps only the newest three saved logs there; older ones (also the ones earlier versions left) are deleted." },
            { short = "The diagnostic log is ready in seconds instead of half a minute", text = "Diagnostics (Send to the developer, Send to a browser, Save to the Kindle) put the log together in a second or two instead of about 25 seconds on a Kindle 3. Most of that time went on a survey of the Kindle's audio and speech system, whose answers only change with the Kindle's firmware: they are now kept after the first time and reused, also across GZreader updates. The log also notes how long it took." },
            { short = "Highlights show on both sides: web reader yellow is visible on the Kindle, Kindle highlights are yellow on the web", text = "Highlights made in Grimmory's web reader are yellow by default, which on a Kindle's grey screen came out almost white. On a greyscale Kindle a highlight colour too light to see is now drawn like the Kindle's own grey highlight (darker colours and underlines are unchanged). The other way, the Kindle's grey highlights were a dark smudge in the web reader: new ones now go to Grimmory as the web reader's yellow. Highlights already in Grimmory keep their colour there; change one in the web reader to yellow if you want it to match." },
            { short = "Refresh list from Grimmory works when Wi-Fi has gone off", text = "Authors and Series open from the list saved on the Kindle, without Wi-Fi, so with Wi-Fi only when needed it was often off again by the time you chose Refresh list from Grimmory, which then said it couldn't reach the server. Refresh now turns Wi-Fi on first, like the rest of the Grimmory tab. (The diagnostic log also now says why Check for updates turned Wi-Fi on, instead of a question mark.)" },
            { short = "Calendar: the bar beside each event lines up with it", text = "The short bar in an event's row (its calendar's shade) started halfway down the title and hung below it. It's now centred on the event, as it was meant to be." },
            { short = "Books open quicker while something syncs in the background", text = "When you open a book, GZreader's background work now waits: a sync that's already running (the calendar, Notes, Grimmory) is paused until the first page is up, and nothing new starts before then (30 s at most). On a Kindle 3 a calendar sync running at the same time made a book take 23.5 s to open instead of 6." },
            { short = "Notes and Calendar icons show again (pin, file, picture, tag)", text = "The icons on notes (pinned, place, file, picture, tag) and the Calendar's come from ZenOS's icon font, which GZreader asked for by the wrong path: it was never found (an error in the log at every size), and the pin, file, picture and tag icons were missing. It's found now." },
            { short = "Kindle 3: pausing when headphones are unplugged can work", text = "Find the headphone jack (Settings → Reader) found nothing on a Kindle 3: it shows headphones in none of the places GZreader looked. It also listens now for the message the Kindle's hardware service sends when headphones go in and out (audioHS), and when that's what changed, music, audiobooks and read aloud pause on it, with one listener while something plays." },
        },
    },
    {
        version = "1.26.10",
        changes = {
            { short = "Manage book no longer shows the Edit menu", text = "Manage book (the quick panel's Manage tile, or holding a book at Home) no longer shows ZenOS's Edit submenu: its Delete is already at the top as Delete from this Kindle." },
            { short = "Holding a book in Downloads opens Manage book, as on Home", text = "Holding a book in the Downloads tab opens Manage book (Open, Delete from this Kindle, then the book's menu), as holding a book on Home does. Other folders keep the book's own menu." },
            { short = "With diagnostic logging off, book openings aren't timed", text = "With diagnostic logging off (Settings → General), GZreader no longer times each book as it opens (the \"book open:\" line in the log, which was then thrown away), so opening a book does no work for the log at all." },
            { short = "Home shows the status bar (clock, battery, Wi-Fi) even before you've read a book", text = "Home shows the status bar across the top, like the other tabs, when there's no recently read book to show (a new Kindle, or after clearing your reading history): it used to have none, because Home's status bar sits beside the book you're reading. Once you open a book, it moves back beside it." },
            { short = "Add to shelf / Remove from shelf (your Grimmory shelves) replace Add to collection, also on the Kindle 2 and DX", text = "The book menu's Add to collection is now Add to shelf, also for several selected books: it lists your own Grimmory shelves (not smart shelves, not other people's) and puts the book on the one you pick. A book on one or more of your shelves also has Remove from shelf (or Remove from shelves: one of them, or all). Your shelves and the books on them are kept on the Kindle, so this works without a network: with Wi-Fi a change goes to Grimmory straight away (or when Wi-Fi connects), and on the Kindle 2 and DX the sync page sends it at the next sync. Changes made in Grimmory come to the Kindle when Wi-Fi connects, when a book opens, or with the sync page's library copy. Not signed in, Add to shelf says to sign in to Grimmory first." },
            { short = "No more home folder settings: the home folder is always the GZreader folder", text = "Settings → Library → Folders no longer has a Home folder menu (Lock home folder, Additional home folders), KOReader's menu no longer has Home folder settings (Set, Shorten, Lock home folder), and holding a folder or the + menu in KOReader's file manager no longer offers Set as HOME folder. GZreader relies on the home folder being the GZreader folder, where downloads and books sent from your browser go, and set it back at every start anyway, so these did nothing lasting." },
            { short = "Home: no Local reading stats widget (Grimmory's reading stats stay)", text = "The Local reading stats widget (pages and time today, this Kindle only) is no longer on Home or in Settings → Home → Widgets; Grimmory's reading stats are the ones on Home. If your Home still showed it, it goes and your other widgets stay where they were." },
            { short = "Settings has no Extras section any more: less to wade through", text = "Settings no longer has an Extras section. Its Schedules and Sleep were already in General and Custom icons in Interface, and they stay there. The rest (Stats tab widgets, ZenPM, Rakuyomi, Zen Search, Lockdown mode, Zen Keyboard) is no longer offered: GZreader doesn't use them or works best with their defaults. Anything you had changed there keeps your choice." },
            { short = "A Grimmory search that finds nothing shows empty shelves with cobwebs", text = "A search in the Grimmory tab that finds nothing now says \"No books found containing “…”\" with what you searched for. In the Bookshelf view it's the same shelves a search's books stand on, empty, with cobwebs on them and the message on a card; Search again… stays at the top." },
            { short = "The Downloads tab says Downloads in its title bar", text = "The Downloads tab names itself in the title bar (between the clock and the battery), as History, Collections, Grimmory and the other tabs do; a tab you renamed in Settings → Interface → Navbar shows that name. Inside a folder the title is still the folder's name." },
        },
    },
    {
        version = "1.26.9",
        changes = {
            { short = "Send to the developer asks what happened, and sends it with the log", text = "Diagnostics → Send to the developer (quick panel, or Settings → General) first asks what you were doing and what went wrong; what you type goes with the diagnostic log, at the top, so the developer knows what to look for. Leaving it empty still sends the log. Reports from releases and test builds now go to the same place." },
        },
    },
    {
        version = "1.26.8",
        changes = {
            { short = "Updated to ZenOS 4.3.0: quicker, new reading controls on touch Kindles, a new end-of-book screen", text = "Updated to ZenOS 4.3.0 (was 4.2.0): quicker (its parts load when they're first used); on touch Kindles, new reading controls (a page browser, a viewer for highlights, notes and pinned pages); better reading themes; coloured underlines and strikethrough; a new end-of-book screen. ZenOS sets the top and bottom page margins to its default (15) once, if you use its reading preset. GZreader's own changes to ZenOS are kept: letter keys in menus, the tab keys, the bookshelf, Grimmory's stats, text sizes as before." },
            { short = "After an update, a screen shows what's new in GZreader (it showed ZenOS's version)", text = "After every update, GZreader shows its version and a short list of what changed (the full text stays in Settings → Updates → Changelog). With ZenOS 4.3 that screen showed ZenOS's version and ZenOS's own list, and only when ZenOS itself changed." },
            { short = "Touch Kindles: the first-time tour now shows GZreader's quick panel and closes it when it's done", text = "Touch Kindles: the first-time tour after the setup guide now shows GZreader's quick panel (how to open and close it, Settings, the Home or This book tiles) instead of pointing at ZenOS's menu, which GZreader replaces. It closes the panel when it ends, so the page browser tip on the first book is no longer hidden under it." },
            { short = "Flash on every page turn is its own setting (Reader → Appearance), on by default on the Kindle 2, DX, 3 and 4", text = "Flash on every page turn is its own setting now: Settings → Reader → Appearance. On by default on the Kindle 2, DX, 3 and 4 (no grey trace of the last pages, as before), off elsewhere, and it can be turned on on any device. It used to go with Settings → Advanced → Flash when the screen changes, which is now only for menus, tabs and opening a book (if you had turned that off, page turns stay as they were). Ticking or unticking it replaces a full refresh rate chosen in a book's menu." },
            { short = "Diagnostics: Send to the developer sends your log straight to GZreader's developer", text = "Diagnostics (quick panel, and Settings → General) has Send to the developer: GZreader's diagnostic log goes straight to the developer over Wi‑Fi (no QR code or USB cable). Passwords and tokens are never in the log. Test builds send to a separate feed." },
            { short = "Full usage statistics now include debug reports; the Remote debugging settings are gone", text = "Usage statistics set to Full now also send debug reports to the developer: GZreader's starts, warnings and errors from its log, freezes and crashes (what Remote debugging sent to a feed you set yourself). Settings → General → Remote debugging is gone, and a feed set there before is forgotten. Basic and Off send no debug reports." },
            { short = "Nook: most of GZreader moves to the microSD card, freeing about 55 MB of the Nook's small app disk", text = "Nook 1st Edition and Simple Touch: most of GZreader moves to the microSD card (or, without one, the Nook's own storage), leaving the Nook's small app disk, shared with Android, with room to spare. Its Lua code, fonts, hyphenation, translations and cache (about 55 MB) are moved at the first start (a minute or two) and mounted back into its folder while it runs; its programs, libraries and settings stay on the Nook (about 30 MB). Leave the card in: without it GZreader asks for it. Updates write each part where it lives." },
        },
    },
    {
        version = "1.26.7",
        changes = {
            "Nook 1st Edition: Wi‑Fi much more reliable. The start script left the Wi‑Fi chip's power saving on, so it napped between packets: 2 pings in 5 were lost and sign-ins to Grimmory timed out. It's now turned off while GZreader runs (Android manages it itself).",
            "How long something kept the e-reader awake is timed on a clock that doesn't jump (the log said 26 years after a run-down clock was set).",
            "Test builds: the update and its data are read from the same commit of the updates branch. Right after a new test build, GitHub's file server could still hand out the last one's data with the new zip, and the update said it was incomplete.",
            "Nook 1st Edition: no flash when the selection moves, a menu opens or the clock changes. GZreader now refreshes the e-ink page the way Android does on this Nook, just the part that changed, without a flash; a full refresh with a flash comes only when one is asked for (every few page turns, against ghosting). If the screen doesn't keep up, `touch /data/gzreader/eink-flash` over adb brings back a full refresh every time (see GZREADER.md).",
            "Sync page (Kindles without Wi‑Fi): sleep screen pictures can be iPhone photos (HEIC). Browsers other than Safari can't open them (\"this browser can't open that kind of file\"), so the page now converts them itself, in the browser.",
            "Sync page: a book, audiobook or album chosen on the page that reached the Kindle another way (a sync from another computer, a download over Wi‑Fi) comes off the page's list. It stayed listed as coming with the next sync, and was brought again after you deleted it from the Kindle.",
            "Sync page (Kindles without Wi‑Fi): M4B audiobooks and M4A music are prepared for the Kindle on the computer, during the sync. The Kindle no longer spends minutes after the sync converting them (8 minutes and more on a Kindle DX): they play straight away.",
            "Nook 1st Edition: updates install when the Nook's internal disk is full. GZreader shares its 242 MB with Android, and an update unpacked next to GZreader needs room for a second copy of it (\"Update failed, nothing was changed: could not unpack\"). Then it's downloaded and unpacked on the microSD card and copied in part by part; if a part can't be copied, every part is put back.",
            "Music (Plex): Make bigger MP3 and AAC smaller (Music tab → Plex: you · server). MP3 and AAC tracks of a higher quality than “Quality when converting” are converted to MP3 at that quality by Plex too, to save room on the Kindle.",
            "Sync page: music is converted at the Kindle's “Quality when converting” (it was always 192 kbps), and both choices can be changed on the page, with the Plex connection; the Kindle keeps what's chosen there.",
        },
    },
    {
        version = "1.26.6",
        changes = {
            "Nook 1st Edition: far fewer flashes. Each e-ink refresh on this Nook is of the whole page, so GZreader now waits until the screen has stopped changing after a tap or button and refreshes once: a tap, the menu it opens and the status bar are one flash instead of three. A popup that opens by itself (a download's progress) shows at once and updates every few seconds. The clock and battery no longer flash the page on their own; they show with the next refresh (five minutes at most).",
            "Nook 1st Edition: updates over Wi‑Fi like the Kindles (Settings → General → Updates). The update also brings the Nook's start script, used from the next start.",
            "Test builds: Settings → General → Updates → Test builds installs what's waiting to be tried over Wi‑Fi, before it's released (no cable for each try). Turn it off to go back to releases. Kindles without Wi‑Fi: the same choice on the sync page.",
            "Nook 1st Edition: a GZreader icon in the Nook's app list. The Nook's su only works for adb, so a small helper set up once over adb (launcher.sh install) runs as root from the Nook's start-up and starts GZreader when you tap the icon. See GZREADER.md.",
            "Nook 1st Edition: the Downloads tab opens GZreader's folder on the microSD card (it showed the root folder: ZenOS took /sdcard for a modern Android's /storage/emulated/0, which the Nook doesn't have).",
            "A clock that ran down (a Nook in the year 2000, a Kindle in 1970) is set from Grimmory's the first time it answers. Grimmory's reading statistics on Home were asked for the year 2000, so only the day streak showed.",
            "Grimmory tab: a book's page shows the book's cover. It looked for the cover in a cache of its own and showed none when its own download of it didn't come back (Wi‑Fi still coming up, say); it now uses the cover the list already shows.",
            "Grimmory tab: the selection stays on the book you moved to. Moving down while the tab was still loading, covers coming in, or downloading a book put it back on the top-left book; now it stays put when the page is drawn again.",
            "Downloads tab: a book that finishes downloading while you're looking at Downloads appears in it straight away (before, only after leaving the tab and coming back).",
            "Kindle DX: Home has two shelves of recent books to fill the taller screen, and Downloads four shelves to a page instead of six, so the books are bigger.",
        },
    },
    {
        version = "1.26.5",
        changes = {
            "Kindle 2 and DX: Read aloud works. Their speech service refused the text file GZreader handed it (\"wrong file\"); Find the Kindle voice now first uses the Kindle's own speech pipe (/var/tmp/ttsUSFifo, the way the Kindle's own reader feeds it), and each sentence is written into it. If that fails too, the diagnostic log lists the files and paths the speech service knows about.",
            "Picture books whose pages are all in one or two big files (a cover, one file with every page, a contents page) are recognized and fitted to the screen. GZreader skipped a book's first and last files when checking, and with only three files there was nothing left to check.",
        },
    },
    {
        version = "1.26.4",
        changes = {
            "Nook 1st Edition: a build of its own, gzreader-nook-1st-edition-<version>.zip, that runs on a real Nook. Its kernel has the floating-point unit switched off and stops programs that read unaligned memory, so KOReader's programs are built for that (the Kindle build stopped at once).",
            "Nook 1st Edition: the colour screen and its touch panel are woken and drawn directly (Android leaves them asleep; this Nook's kernel has no 2D engine to copy the picture), touches land where you tap, and B&N's Home strip on the panel is off while GZreader runs.",
            "Nook 1st Edition: Wi‑Fi comes on by itself with the networks saved on the Nook (Android switches it off when its screen goes off), and goes off again when you exit GZreader.",
            "Nook: books go to the microSD card when there is one; GZreader won't start while the Nook is a USB drive on a computer (it explains why).",
            "Nook 1st Edition: e-ink updates go through the Nook's own refresh (every update a full refresh for now); sending them straight to the e-ink controller froze a Nook.",
        },
    },
    {
        version = "1.26.3",
        changes = {
            "Sync with a computer: your own sleep screen pictures. On the sync page (Content), add pictures: they're made to fit the Kindle's screen, in grey, and put in its screensavers folder with the sync. Take off ones that are there, and choose when they show: the book's cover while reading and a picture elsewhere, or a picture always.",
            "No \"Sleeping\" message over the sleep screen by default (KOReader turned it on by itself on a first start). Turned off once on every Kindle; Settings → Sleep screen → Message turns it back on.",
            "The sleep screen chosen in the setup guide shows as chosen: Settings → Sleep screen listed \"Leave screen as-is\" (and ZenOS's sleep screen presets nothing) for GZreader's own \"Cover or screensavers\", which is now an entry of its own in both.",
        },
    },
    {
        version = "1.26.2",
        changes = {
            "Kindle 2 and DX: Read aloud finds the Kindle's voice. Their older firmware has no lipc-hash-prop and reads text from a file (com.lab126.tts playFile): Find the Kindle voice now tries that, and reading hands it one sentence at a time.",
            "Picture books (Diary of a Wimpy Kid…) brought by the computer or downloaded for later are recognized and fitted in the background before they're first opened, so the first opening doesn't measure every picture and then open the book a second time (on a Kindle DX: 22 s, then 8 s more).",
            "Sync with a computer: the Kindle's clock is set from the computer's when it's behind (a Kindle DX whose battery ran down starts at 1970), and reading time recorded while it said 1970 isn't sent to Grimmory.",
        },
    },
    {
        version = "1.26.1",
        changes = {
            "Sync with a computer: Home's Grimmory reading stats widget (streak, this week, this month, books finished this year) gets Grimmory's numbers from the sync page, counted after the Kindle's reading time reached Grimmory.",
        },
    },
    {
        version = "1.26.0",
        changes = {
            "Sync with a computer: Menu → Sync → Connect to computer. GZreader saves everything and steps aside so the Kindle can share its USB drive (KOReader turns the drive off while it runs); after you eject the Kindle, GZreader starts again by itself. (If the Kindle was already plugged in, unplug it and plug it in again.)",
            "Books and audiobooks just downloaded open at their place on Grimmory, also without Wi-Fi: the sync page brings each one's progress with it, and a book downloaded for later (Download on its page) keeps Grimmory's progress for when it's opened offline. An audiobook not listened to on the Kindle yet starts at Grimmory's place without asking.",
            "Kindles without Wi-Fi: usage statistics are sent by the sync page from the computer (at the level chosen on the Kindle; Off sends nothing).",
            "Kindles without Wi-Fi: no more Send diagnostic log to a browser (QR code), Remote debugging or Wi-Fi in Settings and Diagnostics; Save diagnostic log (USB) is there.",
        },
    },
    {
        version = "1.25.1",
        changes = {
            "Sync with a computer: the sync page stopped with an error (\"reduce/some is not a function\") and Sync stayed greyed out when the Kindle had nothing waiting in a list: GZreader wrote empty lists the way the page didn't expect. Fixed on both sides (the page already handles Kindles that haven't updated).",
        },
    },
    {
        version = "1.25.0",
        changes = {
            "Sync with a computer: bookmarks, highlights and notes made, changed or deleted on the Kindle go to Grimmory with the next sync, and Grimmory's come back to be merged when the book opens, as with Wi-Fi.",
            "The sync page: choose the Kindle first, then enter its PIN; the sign-ins are kept on the Kindle, encrypted with the PIN, so any computer can sync it. Then three tabs: Connections; Content, browsed like the Grimmory tab (Recently added, A–Z, Libraries, Shelves, Authors, Series, search; Plex albums and playlists); Sync, with how much room is left on the Kindle and what the sync brings. Add ?test to the address to try it with a pretend Kindle.",
            "The sync page's covers work with Grimmory (it doesn't let web pages read its covers): the page shows them, and for the Kindle's Grimmory tab it takes an EPUB's cover from the book and an audiobook's from its audio cover.",
            "GZreader tells the page how much room is left on the Kindle.",
        },
    },
    {
        version = "1.24.0",
        changes = {
            "Kindles without Wi-Fi (Kindle 2, Kindle DX): sync with a computer. Exit GZreader, plug the Kindle in and open 9retirement6irk.github.io/GZreader/sync in Chrome or Edge: your reading positions, reading time and ratings go to Grimmory; books and audiobooks from the sync queue, your notes (and the ones written on the Kindle go to Memos), calendars and Plex albums come back, with a copy of your library. GZreader recognises these Kindles by itself; any Kindle can choose it in Settings → Connections → Sync through a computer.",
            "Without Wi-Fi, the Grimmory tab browses that copy of your library: lists, search, shelves, authors, series, small covers and book descriptions. Download (and an audiobook's Add to sync queue) puts a book in the sync queue; the next sync brings it. Menu → Sync with computer shows how, what's waiting and the queue.",
            "The sync page lets you choose books, audiobooks and Plex albums and playlists for the Kindle (each marked when it's on the Kindle or queued already), and brings a newer GZreader, which installs when GZreader starts.",
            "The setup guide starts with how to sync with a computer on these Kindles; their Menu (quick panel and Home menu) has Sync instead of Wi-Fi, the QR code and Updates.",
        },
    },
    {
        version = "1.23.13",
        changes = {
            "A shorter setup guide: less text on every page; a bookshelf preview for the Bookshelf view, the keys' and Grimmory's pictures; the sleep screen chosen from pictures of what each one looks like; usage statistics asked last. The Zen mode, Reader, While reading and Settings & Updates pages are gone (GZreader's reading defaults are still set on a first setup).",
        },
    },
    {
        version = "1.23.12",
        changes = {
            "Touch Kindles (Kindle Touch, Paperwhite and newer): the install packages now include GZreader's launcher (documents/GZreader.sh), so the GZreader item is on the Kindle's own home screen right after copying, before GZreader has ever been started from KUAL.",
        },
    },
    {
        version = "1.23.11",
        changes = {
            "Settings → Storage: how much room books, audiobooks, music, notes, the calendar and covers take on the Kindle, and how much is free. Books, audiobooks, music and notes open on their largest ones.",
            "Downloads, with no books yet: \"No books yet\" on the top shelf, and where books come from. The \"Set home folder\" button is gone (it went over the tab bar), and so is Settings → Library → Folders → Home folder → Set home folder: the home folder is always the GZreader folder (set back at the next start if it was changed).",
            "Kindle 3 (and the other Kindles without REAGL): typing a note no longer flashes the whole screen at every key; the note editor flashes only when it opens and closes.",
        },
    },
    {
        version = "1.23.10",
        changes = {
            "Kindles with keys (Kindle 2, DX, 3, 4): a Grimmory book's page can be used again. Its Download and Download & open buttons couldn't be pressed (the 5-way's Press and arrows did nothing there since 1.22.3, only Back worked), so books couldn't be downloaded from it.",
        },
    },
    {
        version = "1.23.9",
        changes = {
            "Diagnostic log: a sent log ends with what keeps the Kindle from sleeping right then (a download, the audiobook or music playing, the Kindle's own screensaver block), and the log notes when the audiobook is paused.",
        },
    },
    {
        version = "1.23.8",
        changes = {
            "The Kindle sleeps again when nothing is going on. What keeps it awake (a download, the audiobook or music playing, the phone page) is now checked every minute, and anything that has ended is let go of: a player that couldn't start again after a skip or a track change kept a Kindle 3 awake for good. GZreader also lifts the Kindle's screensaver block when it starts, in case an earlier run left it on (closed or crashed mid-download). The diagnostic log says what keeps the Kindle awake, and for how long.",
            "Audiobook player, Go to: type the time without colons, as on a clock: 5000 is 50:00, 13000 is 1:30:00 (colons still work, and so do percentages). A plain number was minutes before.",
        },
    },
    {
        version = "1.23.7",
        changes = {
            "Grimmory: a slow request right after GZreader renewed your login no longer signs you out. When such a request was stopped (it took too long), the new login it got was thrown away, and Grimmory had already cancelled the old one; it is now kept.",
            "Downloads: a book that couldn't be saved under its name (a full or read-only folder) no longer stops the rest of the queue, or keeps Wi-Fi on.",
            "Wi-Fi: turning Wi-Fi on a second time soon after a failed try is no longer given up on early by the first try's 90-second limit.",
            "Sync: a book that isn't in Grimmory any more (deleted there) has its position sent once, not every minute (an audiobook playing kept sending it).",
            "Faster: returning to the file browser (after every book you close) no longer redoes the music folder, the library's links and subtitles, and the backup check; they're done when something changed. The settings file is written once every few seconds while you read, not at every queued change (and always on sleep and when closing a book or GZreader).",
            "Faster on the Kindle 3: moving along the shelves with the 5-way updates only the shelves that changed, not the whole screen, and a book's title and author on the spine are read once, not at every move. The shop's front page, the saved lists' tidying and background work's lower priority cost less too.",
            "Diagnostic log: a slow moment caused by scheduled work names the task that took the longest.",
        },
    },
    {
        version = "1.23.6",
        changes = {
            "Audiobook player: skipping no longer freezes the Kindle. Each start of the player left the old feeder of audio running through every chunk left in the book (thousands, each a small program), so every skip made the Kindle slower (up to 12 s a press). The feeder now stops with the player, and ones left by earlier versions are stopped once. 30 s presses close together are added up and the player started once.",
            "Audiobook player: the audiobook is a cassette tape with its title, author and running time on the label (and the cover); the tape winds from reel to reel through the book. The walkman stays on the shelf.",
            "Audiobook player: every control has a letter: Z previous chapter, X back 30 s, C play / pause, V on 30 s, B next chapter, Q chapters, W sleep, E stop, R go to, A / S volume, D about the book.",
            "Audiobook player: Go to (R): a time (1:23:45 or 23:45), minutes (90) or a percentage (50%).",
        },
    },
    {
        version = "1.23.5",
        changes = {
            "Music: tracks Plex has to convert (anything not MP3 or AAC: FLAC, ALAC, Opus…) failed to download, every one (\"transcode http_400\": 92 of your playlist's 93 tracks). Plex picks how to convert by the kind of app asking, and didn't know \"Kindle\"; GZreader now asks as Plex's web app does (and falls back to other ways if a server refuses, keeping AAC as it comes).",
            "Music: playing an album or playlist with tracks not on the Kindle goes straight to the next track that is, instead of waiting 2 s for each missing one; if none are, it says so at once.",
            "After an update that changes GZreader's startup script, GZreader no longer asks you to quit (Quit took you to the Kindle's home screen); the new script runs the next time you start GZreader from the Kindle.",
            "Paperwhite: Forget in the Wi-Fi networks page names the network as the Kindle's Wi-Fi service expects.",
        },
    },
    {
        version = "1.23.4",
        changes = {
            "Kindle 3: the book you're reading on Home (title, author, description) is as big as on the Paperwhite; it was sized by the cover's height in pixels, so the Kindle 3's smaller pixels made it a third smaller.",
            "Kindle 3 audiobook player: the 5-way moves between the player's keys (a black ring shows which; it starts on play / pause) and Press uses it, instead of skipping 30 s and changing chapters. The letter keys still work.",
        },
    },
    {
        version = "1.23.3",
        changes = {
            "Music downloads show their progress: track n of m and how far along, kept current in the album's list (in the music player's library too), on the Downloads screen and in the status bar.",
            "A music download can be stopped: select its progress line, or from the Downloads screen. The tracks that came stay on the Kindle.",
            "When tracks fail or a download is stopped, the message says how many of how many made it; the album then offers \"Download the n missing tracks\", which fetches only those. Half-written files are cleared, and a track that finished downloading just as GZreader stopped or restarted is kept instead of being fetched again.",
        },
    },
    {
        version = "1.23.2",
        changes = {
            "Kindle 3: the audiobook and music players no longer flash at every change inside them (the library, the lists, a download, the chapter list); the screen flashes only when a player opens and when it closes.",
        },
    },
    {
        version = "1.23.1",
        changes = {
            "Kindle 3: moving the 5-way along the tab bar or around the quick panel no longer flashes the screen at every step (1.23.0 did, because those moves redraw the whole screen). Opening and closing things still flashes.",
        },
    },
    {
        version = "1.23.0",
        changes = {
            "Less ghosting on the Kindle 3 (and Kindle 2, DX, 4): switching tabs, opening or closing a menu, the quick panel or a book, and a list's next page now flash the screen clean, and every page turn flashes, as the Kindle's own reader does. Small changes (moving the 5-way, the clock) stay quick. Turn it off in Settings → Advanced → Flash when the screen changes; the book menu's full refresh rate still applies if you set one.",
            "Wi-Fi networks (Settings → Wi-Fi) works on Kindles: it couldn't reach the Kindle's Wi-Fi service (the library it looked for isn't in KOReader's Kindle packages), so the list never appeared. Networks the Kindle already knows show as Saved and join without asking for the password.",
            "Kindle 3: if the Kindle can't list networks here, it says to add them in the Kindle's own Wi-Fi settings; GZreader then turns Wi-Fi on and joins them by itself.",
            "After connecting, the \"no default route\" warning waits a few seconds for the Kindle to finish connecting before it shows.",
            "Diagnostics: the log now says how GZreader exited and whether the Kindle's own interface was started again, and lists the Wi-Fi service's settings (no network names or passwords).",
        },
    },
    {
        version = "1.22.6",
        changes = {
            "Bigger titles and authors on book spines (Home and Downloads): the spines are a little wider and their type is as big as each spine allows; a long title is set a little smaller so more of it shows. On Kindles without a keyboard, titles run closer to the foot of the spine.",
            "Downloads, Bookshelf view: when everything fits on one page, the shelves fill the screen and the bottom one stands on the tab bar, as on Home.",
            "Grimmory tab, Bookshelf view: bigger, darker type on the tags under each book (three books a row, so titles fit).",
        },
    },
    {
        version = "1.22.5",
        changes = {
            "Grimmory tab: Continue reading shows the books the Grimmory website shows. Grimmory's app list only has books marked Reading; books marked Paused (or without a last-read time) are now included too, most recently read first.",
        },
    },
    {
        version = "1.22.4",
        changes = {
            "Downloads, Bookshelf view: every book of a series stands on the shelf (in its order, its number on the spine): grouping series into folders is off in the Bookshelf view; the other views keep the setting.",
            "Every spine shows its author: narrower spines left it off; they now use smaller type.",
            "A book whose file has no author (or only in its KOReader custom metadata) shows the author Grimmory has. Books downloaded before this update get theirs from Grimmory once, in the background, when Wi-Fi is on.",
        },
    },
    {
        version = "1.22.3",
        changes = {
            "Grimmory tab, Bookshelf view: each book on the display ledges has a tag on the ledge under it with its letter, title and author (and your stars or how far you are); four books a row so titles fit.",
            "A book's page (tap a book that isn't on the Kindle): a small cover beside its title, subtitle, authors, series, Goodreads rating, genres, pages, year, publisher, format and size; its description below (page keys scroll it); and Download next to Download & open. Download fetches it in the background and says when it's done, without opening it.",
            "Sorting works on the Grimmory tab: Sort (its menu or the quick panel) offers what Grimmory can sort by (title, date added, last read, series, your rating, Goodreads rating, publication date, page count, reverse), and the list on screen is opened again in that order. A series keeps its own order.",
            "Authors, libraries and shelves: each compartment's card is as wide as its name, so long names aren't cut off.",
        },
    },
    {
        version = "1.22.2",
        changes = {
            "The Grimmory tab's Series leaves out series with only one book (the book is still under All books, its author and its library), and the bookshop's Series card counts only the others.",
            "Music and audiobooks start at your volume: the Kindle's own (often full) volume was used until the volume rocker was pressed. GZreader sets the speaker to your level as the player starts, and again once it's playing.",
        },
    },
    {
        version = "1.22.1",
        changes = {
            "Fixed: a Kindle could be signed out of Grimmory after an update (or after GZreader was closed in the middle of a request). Grimmory gives a new login each time the old one is renewed and the old one stops working; if GZreader restarted before saving the new one, it was lost. The new one is now written to disk the moment it arrives and picked up at the next start, and an update waits for requests to finish before restarting.",
            "A background request that failed to renew the login no longer signs the Kindle out when it already has a newer one.",
            "When Grimmory signed the Kindle out, the Grimmory tab says so (and that your books and progress are still there) instead of \"isn't connected yet\".",
        },
    },
    {
        version = "1.22.0",
        changes = {
            "All of music happens in the CD player: the Music tab, the quick panel's Music and Downloads → Music open it. Under its controls, the CD case insert shows the queue or the library (F, or a tap on its tabs): Downloaded, Shuffle all, Artists, Albums, Playlists, Search and your Plex account; an album or playlist's Play, Shuffle, Download or Delete and its tracks. ▲ ▼ choose, Press opens or plays, ◀ ▶ turn its pages, Back goes back up.",
            "The Home button works in the CD player.",
            "Downloads, on the bookshelf: the CD player is drawn to the same scale as the walkman (it was much bigger). In Audiobooks each audiobook is a cassette (its case's spine, turned to show the tape with its label and reels); in Music each album or playlist is a CD (its jewel case's spine, turned to show its cover with the disc peeking out).",
            "A series on the bookshelf turns to show its first book's cover, its other books behind it, like a book does.",
        },
    },
    {
        version = "1.21.1",
        changes = {
            "The Grimmory tab's lists look like its bookshop too (in the Bookshelf view): books face out on display ledges with a label under each (its letter, your stars or how far you are), a ribbon in the ones you're reading, a tick on the finished ones, ON KINDLE on the downloaded ones; libraries, shelves and authors in bookcase compartments with cards; series as piles of books lying flat; audiobooks as a rack of cassette spines. Search and Refresh are a slip and a sign at the top.",
            "On Kindles without a speaker the bookshop's sixth compartment is empty, with cobwebs.",
            "Home: the book strip's controls are off by default, and their room goes to the book you're reading (a bigger cover, more of its description). Settings → Home → Widgets → Book strip → Controls brings them back, and they stay as you set them.",
            "Fixed: an audiobook whose book was removed from Grimmory asked Grimmory for it about once a second while its player was open, and could start playing after the Kindle went to sleep.",
            "Fixed: music went round and round its track list (every 2 s) when none of the tracks had been downloaded; it now stops and says so.",
            "Fixed: Settings → End of book's preview closed KOReader when Grimmory reading stats were on that page.",
            "Send the diagnostic log: like setup's page, its address is just the Kindle's IP (with the PIN on the screen), besides the QR code.",
        },
    },
    {
        version = "1.21.0",
        changes = {
            "The Grimmory tab is a bookshop in the Bookshelf view: a search slip pinned at the top, Continue reading and Recently added as covers on display ledges (a ribbon and how far you are, or a NEW tag), each ending in a tied bundle of spines that opens the whole list, and a bookcase below with a compartment for All books, Libraries, Shelves, Authors, Series and Audiobooks (Downloaded books on Kindles without a speaker).",
            "Each compartment has a card clipped to it with its name, how many (from what GZreader already keeps, nothing extra is fetched) and its letter key. Magic shelves are counted; their rules are never shown.",
            "The letter keys are the ones the list had: Q search, W Continue reading, E Recently added, R All books, T Libraries, Y Shelves, U Authors, I Series, P Audiobooks. The 5-way moves between the slip, the covers and the compartments; back from a list, it's on what you opened. List with details, Simple list and Tiles keep the list.",
        },
    },
    {
        version = "1.20.1",
        changes = {
            "Quick panel, in a book: Font (the list of fonts, the one in use ticked) and Layout (size, margins, spacing) tiles, so every Kindle reaches them now that More is gone, the Kindle 4 too.",
        },
    },
    {
        version = "1.20.0",
        changes = {
            "Home's reading stats come from Grimmory: reading time and books this week, day streak, longest streak, days read, sessions this month, books finished this year, counted over every device that reads with your account. Pick any three in Settings → Home → Widgets → Grimmory reading stats. The earlier widget is now Local reading stats (this Kindle only) and can be turned back on there.",
            "The book you're reading shows its progress as its page edges, the pages read darker, with a ribbon bookmark where you are.",
            "The audiobook player is a cassette walkman with headphones: the book's title, chapter and cover on the cassette's label, the tape moving from reel to reel through the chapter, a counter, and the page-edge progress for the book.",
            "Now playing (music) is a portable CD player with headphones: the album's cover on the disc, track and time on its display, the controls with letter keys, and the queue like the back of a CD case.",
            "The players' buttons look like hardware: the walkman's chunky keys (play stays down while playing) and a volume dial; the CD player's pill buttons, with the queue on a CD case insert between its spines.",
            "The walkman and CD player on the bookshelf are redrawn to match, a little bigger, with their letter keys; the CD player's headphones lie around it, the cords running behind.",
            "Quick panel: the light's slider can be dragged; the More tile is gone. Opening Settings, History or Diagnostics from it on a touch Kindle no longer leaves part of the panel on the screen.",
            "The README lists every Kindle, marking the ones not tested yet.",
        },
    },
    {
        version = "1.19.0",
        changes = {
            "Bookshelves are a View, and the default: Home's shelf and Downloads (several shelves, a page at a time) show books standing with their spines out. The book you pick turns to show its cover; tap it again, Press or its letter opens it. View in the quick panel switches between Bookshelf, List with details, Simple list and Tiles.",
            "The books look solid: rounded, shaded spines that cast shadows, shelves with depth, wider spines with bigger titles and authors, and the letter key in the middle at the foot of each spine. The book you're reading has its pages showing behind the cover and a drop shadow. Home's shelf is a little shorter.",
            "Sort orders the bookshelves too: Downloads, and Home's shelf (Last read: the most recent first).",
            "Audiobooks stand on the top shelf to the right of the books as a cassette walkman with headphones; downloaded music as a CD player. In lists and tiles they're always first, whatever the sort.",
            "Downloaded music is in Downloads → Music, like audiobooks: open an album or playlist there to play it.",
            "Ratings sync with Grimmory: the stars you give a book on the Kindle become its personal rating in Grimmory (4 stars are 8 out of 10), and a rating made in Grimmory comes to the Kindle when the book opens.",
        },
    },
    {
        version = "1.18.0",
        changes = {
            "Set up from your browser: besides the QR code, the Kindle shows its address and a PIN. Type the address into any browser on the same Wi-Fi (a computer too), enter the PIN, and the same setup page opens. After 5 wrong PINs the PIN stops working (the QR code still works; opening setup again makes a new one).",
            "The setup page fits any screen: tabs along the top on a phone, down the side on a computer.",
            "A Diagnostics tab on the setup page (while diagnostic logging is on) downloads the diagnostic log.",
        },
    },
    {
        version = "1.17.0",
        changes = {
            "One quick panel on every Kindle and Nook: square tiles for Wi-Fi, night mode, rotate, restart, sleep, Home, updates, Settings, diagnostics and Exit, then Home's (manage the highlighted book, continue, send books, search, history, view, sort, music) or, in a book, the book's (sync, contents, bookmark, bookmarks, go to page, search, fit pictures, read aloud, music). Menu opens it (on a touch Kindle, swipe down from the top); every tile has a letter. It replaces the GZreader menu and ZenOS's quick settings; More in it has the full menus.",
            "Touch Kindles: the panel has a light slider, a tap below it closes it, and holding a book at Home opens its options (Open, Delete, More options).",
        },
    },
    {
        version = "1.16.2",
        changes = {
            "Settings: opening the end-of-book page's settings could make GZreader crash and restart (1.16.0 gave that page the bookshelf by mistake). It has its own look back.",
            "Wi-Fi: on the Paperwhite the first requests after connecting could fail (\"Network is unreachable\": calendar links, the update check) because it said it was connected a moment too soon. GZreader now waits until the connection really works (a few seconds at most).",
        },
    },
    {
        version = "1.16.1",
        changes = {
            "Covers: the book you're reading (top left) and the book turned on the shelf could show a blank cover, on a Kindle that had shown its covers before at the old sizes. A cover not yet made at a new size is now made then (once; it's kept, and the other books get theirs made in the background).",
        },
    },
    {
        version = "1.16.0",
        changes = {
            "Home is a bookshelf: your recent books stand on one shelf with their spines out (title, author, number in the series), right on the tab bar. The one you move to, or tap, turns to show its cover; tap it again, Press or its letter (at the foot of the spine) opens it. An empty shelf has cobwebs. Settings → Home → the book strip → Bookshelf turns it off.",
            "The book you're reading is smaller at the top, so the shelf is taller.",
            "The reading stats are handwritten on a notebook page taped up (pages today, read today, and the streak as tally marks). Settings → Home → Reading stats → Stat separators has the old looks.",
        },
    },
    {
        version = "1.15.0",
        changes = {
            "The Calendar tab looks like paper, like the Notes tab, in the same handwriting: Month is a wall calendar on its hook with a spiral binding and today circled; Week and Day are pages of a spiral planner (a ruled row per day, today highlighted); Agenda is a tear-off day pad, the day in big with its events beside it, the next days below.",
            "An event opens on an index card with a paper clip: when, where, which calendar, the notes. \u{25C0} \u{25B6} (or a swipe) go through the other events that day; if the notes don't fit, Press (or hold) shows all of them.",
        },
    },
    {
        version = "1.14.3",
        changes = {
            "Copying connections: after one copy the sending GZreader shows a new PIN and keeps waiting, so you can copy Notes after the calendars (or to another device) without starting again. Before, it stopped answering, and typing its address on the other one then froze that one for a minute.",
            "Typing the other GZreader's address shows \"Connecting…\" and gives up after a few seconds if nothing answers.",
            "Settings → Connections → Plex (Music), on the Kindles with audio: sign in, the Plex server, the quality when converting, downloaded music (and removing it), sign out.",
        },
    },
    {
        version = "1.14.2",
        changes = {
            "The QR code screens say less: \"Scan this code with your phone to set up GZreader connections and send books.\", with the address underneath for a phone without a camera.",
        },
    },
    {
        version = "1.14.1",
        changes = {
            "Kindle Touch and Paperwhite: when GZreader turns the Wi-Fi on by itself (syncing, checking for updates…) it no longer shows \"Scanning for networks…\" and \"Connecting to network…\" messages; it connects in the background like on the Kindle 3. Turning the Wi-Fi on yourself still shows them.",
            "The README mentions read aloud.",
        },
    },
    {
        version = "1.14.0",
        changes = {
            "Music from Plex (Kindle 2, 3, DX and Touch): a Music tab (off until you turn it on: Settings → Navbar → Tabs → Music) with your Plex server's artists, albums, playlists and search. Download albums and playlists for offline, or press Play: it downloads in order and starts with the first track. It keeps playing while you read; Now playing has pause, next, previous, shuffle and repeat.",
            "Sign in to Plex on the Kindle with a code (enter it at plex.tv/link on your phone or computer), or on the phone page with Plex's own sign-in.",
            "Music is also in the Home menu and the Reading menu (what's playing), and on the Kindle Touch in the quick panel's launcher (Music, Play / pause). The Kindle plays MP3 and AAC; Plex converts FLAC and others to MP3.",
            "Headphones: music, audiobooks and read aloud pause when headphones are unplugged (Settings → Reader). If your Kindle doesn't say where it shows the jack, Settings → Reader → Find the headphone jack finds it.",
            "The phone page has tabs (Grimmory, Notes, Calendar, Music, Send books, Access) instead of one long page.",
            "Access (phone page): GZreader can send a secret key to your own servers, for a Cloudflare rule that lets the Kindle past bot checks (the page shows the rule to paste); and a Cloudflare Access service token.",
            "A shorter README; the details are in the full guide.",
        },
    },
    {
        version = "1.13.0",
        changes = {
            "Copy connections from another GZreader over the Wi-Fi: on the one that has them choose Send connections (Settings → Connections → Copy to or from another GZreader, or its setup guide); it shows a PIN. On the new one choose Copy from another GZreader (its setup guide, the same place in Settings, or the Notes or Calendar tab), pick the other from the list and enter the PIN, then tick what to copy: Notes (Memos), the CalDAV account, calendar links, Grimmory.",
            "Grimmory gives each device its own sign-in, so for Grimmory the address and account are copied and the new one then signs in (the password, or the phone page for single sign-on), with everything else filled in.",
            "The devices find each other with mDNS; if a router blocks it, type the address shown on the sending one. The PIN protects the copy (SPAKE2 and AES-256-GCM: nothing readable crosses the Wi-Fi, and wrong PINs can't be tried offline; 5 tries); it's good for one copy.",
        },
    },
    {
        version = "1.12.3",
        changes = {
            "Kindle Touch and Paperwhite: tapping the back arrow at the top of the Grimmory tab inside a list (All books, a library, Authors…) made GZreader crash and restart, which looked like the Kindle rebooting. It now goes back one list.",
            "Search is now first in the Grimmory tab: books whose title, author or series has the words, A–Z, with \"Load more\" like All books (it showed only the first 40 before). A library, shelf or author's books have \"Search in …\" at the top to search only there, and Series has its own search like Authors.",
            "Big libraries use less memory: a book list keeps up to 200 books (\"Load more\" past that lets the first ones go, and \"Earlier books\" at the top brings them back), keeps only what GZreader uses of each book, and \"Load more\" no longer freezes the screen while it loads. A cover still on the screen is never let go of (with covers drawn quickly, that could also crash GZreader).",
        },
    },
    {
        version = "1.12.2",
        changes = {
            "Touch Kindles and the Nook Simple Touch: GZreader in the launcher (swipe down from the top) opens the Reading menu while you're reading, instead of always the Home menu.",
            "The launcher has more of the GZreader menu, and shows what fits where you are: at Home and in the library Continue, Grimmory, Search, History, Phone, Send books and Updates; in a book Contents, Bookmark, Bookmarks, Go to page, Search book, Sync and Fit pictures. GZreader is in both.",
            "Kindle DX and DX Graphite: text, menus and buttons are now the same size on the screen as on the 6\" Kindles (they were half as big again: KOReader sized them by the screen's width, not its sharpness), with more on each page (22 to a list's page). Not if you've set your own screen DPI.",
        },
    },
    {
        version = "1.12.1",
        changes = {
            "New, as a test build: the Nook Simple Touch and Simple Touch with GlowLight, in the same gzreader-nook package as the 1st Edition (1.12.0's package was built just before it). By touch like the Kindle Touch, with the page buttons, n for Home, the frontlight in quick settings and each refresh's waveform chosen by GZreader. Settings → Interface → Touch orientation if the touch lands on the wrong side.",
        },
    },
    {
        version = "1.12.0",
        changes = {
            "Kindles without a touch screen: Menu now always opens the GZreader menu (at Home) or the Reading menu (in a book), never ZenOS's quick panel, which is made for touch. Its \"Quick panel\" entries and the setting to switch back are gone; everything the quick panel did there is in the GZreader menu or Settings.",
            "New, as a test build: GZreader on the Barnes & Noble Nook 1st Edition (gzreader-nook-1.12.0.zip; needs a rooted Nook, installed with adb: see GZREADER.md). The colour touchscreen under the page has the arrows, OK, Back, Menu, Home and page buttons; while reading it shows the title, chapter, page and progress or the cover, elsewhere a clock, and a keyboard for typing so the page stays uncovered. What it shows when, how long it stays lit and its brightness are in Settings → Interface → Colour screen. Not yet: audiobooks and read aloud. Tried in the emulator only so far: reports welcome. On a Nook, GZreader and the phone page say \"Nook\" wherever they'd say \"Kindle\".",
        },
    },
    {
        version = "1.11.0",
        changes = {
            "Single sign-on works for readers on other networks: the identity provider now sends the phone to GZreader's sign-in page (https://9retirement6irk.github.io/GZreader/oauth2-callback), which hands the sign-in to the Kindle. Register that one address at your identity provider for every Kindle, instead of each Kindle's IP; Grimmory and the provider can be on the internet (e.g. through Cloudflare). The phone still needs to be on the Kindle's Wi-Fi while signing in.",
            "Settings → Connections → Grimmory → Single sign-on (SSO): how to set it up, and where the provider sends the phone back: GZreader's page, your own copy of it (e.g. next to Grimmory), or this Kindle's own address as before. Kindles that signed in with their own address keep it; if you set SSO up before 1.11 and haven't signed in yet, add the new address at your provider or pick \"this Kindle's own address\".",
        },
    },
    {
        version = "1.10.0",
        changes = {
            "Read aloud on the Kindle Touch: in a book, swipe down from the top and tap Listen in the quick panel (again to stop). The first time, a short test finds the Kindle's voice. The keyboard Kindles get the same button besides Shift + Sym.",
            "Paperwhite 3: Home's text was nearly twice the size it is on a Kindle 3 (the reading stats, the strip's tabs, the \"start reading a book\" lines, the badges on covers, the clock and quote widgets): ZenOS scaled those fonts for the bigger screen twice. They're now the size they are on a Kindle 3. Nothing changes on the 600 × 800 Kindles.",
            "On the Kindle's own home screen (firmware 5: Kindle Touch, Paperwhite), GZreader showed up as \"ZenOS\". It is now \"GZreader\" with GZreader's logo; the old ZenOS entry is removed.",
        },
    },
    {
        version = "1.9.0",
        changes = {
            "GZreader now runs on the Kindle 4 and the Kindle Touch too: install gzreader-kindle-1.9.0.zip (the Kindle 2, Keyboard and DX keep gzreader-kindle-legacy, the Paperwhite 3 gzreader-kindlehf or -kindlepw2).",
            "Kindle 4 (5-way, no keyboard): Down from the bottom of Home reaches the tabs; Menu opens the GZreader menu at Home, the Reading menu in a book, and the options in Notes (new note, filter, refresh) and Calendar (today, layouts, refresh). In a note, ▲ ▼ choose a checklist item and Press ticks it. The note editor types with the 5-way on the on-screen keyboard; Menu goes to its toolbar, which also sets who can see the note. The setup guide explains the 5-way instead of the keyboard.",
            "Kindle 4: its screen gets the same faster drawing as the Kindle 3's (KOReader's fast drawing code can't draw on its inverted screen either), about a sixth less processor time per key press, and night mode costs nothing.",
            "Kindle Touch: the touch interface as on the Paperwhite 3, and audiobooks, with buttons in the player for chapters, ±30 seconds, play / pause and close.",
            "Read aloud and its settings only appear on the Kindles with a keyboard (Shift + Sym); audiobooks only on the Kindles with a speaker (Kindle 2, 3, DX, Touch).",
        },
    },
    {
        version = "1.8.0",
        changes = {
            "GZreader now runs on the Kindle Paperwhite 3 (7th generation) and other touch Kindles on firmware 5. Install gzreader-kindlehf-1.8.0.zip on firmware 5.16.3 or newer, or gzreader-kindlepw2-1.8.0.zip on firmware 5.6.1 to 5.16.2 (with KUAL, like the Kindle 3). Updates afterwards come from Settings → Updates as usual.",
            "On a touch Kindle, ZenOS's touch interface: tabs at the bottom, tap to turn pages, swipe down from the top for quick settings and the launcher. The launcher starts with GZreader (the GZreader menu), Phone (the phone page) and Send books.",
            "GZreader's own screens have buttons there: New note, Filter and More in Notes; tap a checklist item to tick it; Edit, Pin, More and Close on a note; the note editor with the on-screen keyboard and its toolbar on top; ◀, Today, ▶ and More in the Calendar; Done on the phone page's QR code screen.",
            "The setup guide explains the touch screen instead of the keyboard on a touch Kindle. Read aloud and audiobooks aren't offered on the Paperwhites (they have no speaker or headphone jack).",
        },
    },
    {
        version = "1.7.0",
        changes = {
            "One phone page for everything: scan the QR code and a page on your phone connects (or disconnects) Grimmory, Notes (your Memos server) and Calendar (a CalDAV account, or webcal / ICS links such as Proton Calendar's), all from the same page. It stays open while you set things up, shows what happened after each step, and the Kindle shows a short note each time. Press Back on the Kindle when you're done: a summary shows what changed.",
            "Edit your calendars from your phone: show or hide each CalDAV calendar, rename a calendar link, give it a new link (Proton's links change when you share again) or remove it (Calendar → Settings → Calendar links → Add or edit links with QR code).",
            "Send books from your phone, no Grimmory needed: Home menu → Send books from your phone (also on the phone page from the setup guide). Pick EPUB, PDF, MOBI, AZW3, FB2, CBZ, TXT, DOCX… files on your phone and they go into the GZreader folder (the Downloads tab). Each book is saved under a new name if one is already there, nothing half-copied is left if the Wi-Fi drops, and a book that doesn't fit is refused.",
            "The setup guide's first page is now \"Connect your phone\" and says what the QR code sets up: Grimmory, Notes (Memos), Calendar (CalDAV or webcal / ICS links) and sending books.",
            "As before, passwords stay on your phone's page: the Kindle keeps only Grimmory's login tokens, the Memos access token and the CalDAV app password, and never writes them, or calendar links, to the log.",
        },
    },
    {
        version = "1.6.5",
        changes = {
            "Fixed: Notes stopped loading (\"Memos answered HTTP 410\") after updating Memos to 26.10 or newer. Those versions moved Memos' API from /api/v1 to /api and answer the old address with 410 Gone; GZreader remembered the old address from when you connected. It now switches to the new one by itself (and back, for a server on an older version), and reads tag counts in the new format.",
            "Memos 26.10 also stopped accepting access tokens made before the update. If Notes then says the access token doesn't work, make a new one in Memos (Settings → Access Tokens) and connect again (Settings → Connections → Memos).",
        },
    },
    {
        version = "1.6.4",
        changes = {
            "Opening a book: a book that has been opened before should open faster. KOReader keeps each book's laid-out pages so it doesn't lay the book out again, but kept at most 64 MB of them and dropped the oldest; a dropped book was laid out again from scratch when opened (10–30 seconds for a big book on a Kindle 3). Now up to 256 MB are kept.",
            "Opening a book wrote the same settings file twice (each write waits for the Kindle's storage); now once. Settings files are no longer rewritten when nothing in them changed.",
            "The log now has a line for each book opened, showing where the time went: closing Home, loading the book, laying it out, each part of GZreader and KOReader getting ready, screen refreshes, and free memory. On the emulator a book opens in about a second, so most of the 10 seconds on a Kindle 3 is waiting (on storage, memory or the screen); after opening a few books, send the log (Menu → Diagnostics) and the cause will show.",
        },
    },
    {
        version = "1.6.3",
        changes = {
            "Faster everywhere on the Kindle 3 (and Kindle 2 / DX): KOReader's fast drawing code couldn't draw on these Kindles' 16-shade (4-bit) screen, so every letter, icon and cover was drawn one pixel at a time in slow script code, which was most of the work behind every key press. GZreader now draws into an ordinary screen buffer with the fast code and copies just the changed area to the e-ink screen before each refresh. What you see is exactly the same, pixel for pixel; in testing, everyday keys (moving around Home, opening tabs, Settings and menus) took about a third less processor time, and GZreader starts faster.",
            "Night mode works again on the Kindle 3, Kindle 2 and DX, and costs nothing: the screen is inverted while it's copied, instead of inverting every drawing (which made these Kindles unusably slow, so it had been switched off). Pictures are inverted as before.",
            "If anything looks wrong on the screen after this update, connect the Kindle to a computer and put an empty file named gz-no-shadow-screen in the koreader folder, then restart GZreader: it goes back to the old way of drawing (and please send the log).",
            "Installs from source (an update from GitHub's source archive, or a development copy) now keep a compiled copy of each code file the first time it's used, so later starts and screens load about four times faster. Release packages are already compiled, so nothing changes there.",
        },
    },
    {
        version = "1.6.2",
        changes = {
            "Fixed: an audiobook wouldn't play again after being paused. Pausing used to freeze the player, which the Kindle 3's sound system doesn't come back from; now pausing stops it and remembers the place, and play starts again from there (MP3 to within a fraction of a second; M4B from the exact AAC frame, instead of the start of its 15-second piece). A paused audiobook no longer holds the sound device, so read aloud can speak.",
            "The Kindle's volume buttons now work everywhere in GZreader: in the audiobook player, while reading aloud, on Home and in lists (a note shows the level, 0–15). On the Kindle 3 they were never passed to KOReader, which left them to the paused Kindle software; the audiobook player could stop when they were pressed.",
            "Leaving GZreader (Exit to the Kindle's menu, or a restart) now stops the audiobook and read aloud, with the place saved (sent to Grimmory at the next start). The player used to go on playing on the Kindle's own home screen. Sleep (the power switch) pauses it, as before, and now also frees the sound device.",
            "Audiobook descriptions: Grimmory's description of the book is downloaded with the audiobook. D in the player (or Menu → About this book) shows it with the narrator, length and number of chapters, and Home's featured book shows it like an ebook's. Audiobooks downloaded before get it the next time the player opens with Wi-Fi on.",
            "The Home key now works in the audiobook player (Home; the audio keeps playing) and in Settings (Home).",
            "Note editor: the Menu key jumps to the formatting toolbar from anywhere in the text, on the tool used last, with the cursor kept where it is (and visible), so the tool applies there; Menu again goes back to the text. ▼ from the last line still works. Moving to the toolbar and back no longer redraws the text box (a long note jumped back to its top).",
            "Faster on Home: moving the 5-way between books and tabs now refreshes only the old and the new focus box, with the quick e-ink mode KOReader's own menus use, instead of the whole screen.",
        },
    },
    {
        version = "1.6.1",
        changes = {
            "Calendar links: the Calendar tab now shows calendars from their shared links (webcal:// or https://….ics), such as Proton Calendar's (Settings → Calendars → Share → Share with anyone), Google's secret iCal address or an Outlook published calendar. Add as many as you like; they sync together, and with a CalDAV account if you also have one (neither is needed for the other).",
            "Adding links: open the Calendar tab (or Settings → Connections → Calendar → Calendar links) and choose Add calendar links with QR code: paste one or more links on your phone, one per line (\"Work | link\" gives one a name). Or type a link, or put them in calendars.txt in the GZreader folder or at the top of the Kindle's USB drive and choose Add links from calendars.txt. Each link is checked when it's added and named after its calendar. Each can be hidden, renamed or removed.",
            "Calendar links are secret (Proton's carries the keys to the calendar), so they're never written to the log: it shows the server only. Request addresses in the log can now be hidden this way for anything secret.",
            "Times in other time zones are now exact: an event at 4 PM in Berlin shows at the right New York time on both sides of each daylight-saving change, using the time zone rules in the calendar itself. Repeating events from links (which servers don't expand) are expanded on the Kindle, with cancelled and moved occurrences.",
            "Fixed: M → Calendar settings in the Calendar tab closed GZreader.",
        },
    },
    {
        version = "1.6.0",
        changes = {
            "New: the Calendar tab, for CalDAV calendars (Nextcloud, iCloud, Fastmail, Google, Radicale, Baïkal…), read-only. Four layouts: Agenda (the coming days' events), Day (a timeline), Week (seven columns) and Month (a grid). Letters open an event (or a day in Week); the 5-way and Press work too, and a day in Week or Month opens in Day. The page keys go to the next or previous day, week or month. N goes to today; M has the layouts, Refresh and the calendar settings. Repeating events, moved and cancelled occurrences, all-day and multi-day events are shown. Calendars are told apart by shade.",
            "Connecting a calendar: open the Calendar tab and choose Connect with QR code (enter the address, user name and password on your phone) or Connect by typing. Use an app password where your server has them: the Kindle keeps it to sync (like the Memos token) and never writes it to the log. Settings → Connections → Calendar (CalDAV): which calendars to show, the layout it opens in, the first day of the week, how far ahead and back to sync, storage, disconnect.",
            "The tab bar is now Home, Downloads, Grimmory, Notes and Calendar. Continue is still in Settings → Interface → Navbar → Tabs (turned off), with Favorites. The setup guide's Navbar Tabs page offers Calendar too.",
            "The bottom tabs have their own keys: Z, X, C, V and B, the keyboard's bottom row, shown under each tab. Alt + Q, W, E… still work. No list or tab used those keys (only KOReader's classic list mode with more than 20 items per page had letters for items 21–25).",
            "Home has letter keys, shown in small squares: Q opens the book you're reading, W, E, R… the books in the strip, and A, S, D… the strip's tabs (Recent, Search, Series).",
            "Notes: M opens the Notes menu (Refresh, Filter, connect, disconnect). The Menu key opened the Home menu there. In a note, M works too.",
            "Notes don't need Wi-Fi to browse: Wi-Fi is turned on only to sync (when the tab opens, at most every 5 minutes, or with changes waiting; M → Refresh any time), to send a new note, edit, tick or pin right away, and to open an attachment that isn't on the Kindle yet. Before, the Notes tab kept Wi-Fi on the whole time it was open, and changes waited for Wi-Fi to be on already. Pictures in your notes are downloaded while syncing, so they show offline.",
            "Wi-Fi you turn off yourself (the Wi-Fi menu, the quick panel or the Home menu) now stays off: background work (syncing when a book opens or closes, after waking, Notes, Calendar, the auto-download shelf) waits until you turn Wi-Fi on again, also after a restart. Things you ask for (browsing Grimmory, a download, opening an attachment, checking for updates, connecting) still turn it on, and it goes off again after a minute.",
        },
    },
    {
        version = "1.5.2",
        changes = {
            "Settings: Grimmory is now Settings → Connections, with Grimmory and Memos (Notes) in it.",
            "New: Settings → Connections → Memos (Notes). Memos connection (who and which server; connect again with a QR code or by typing; disconnect), Sync (all notes, or only notes with the tags you choose), Storage used (notes and attachments kept on the Kindle, with Free up space to remove downloaded attachments or the kept notes), Notes kept on the Kindle (50, 100, 200 or 500) and Attachment storage limit (10, 25, 50 or 100 MB, or no limit; past it, the attachments used longest ago are removed).",
            "Memos has no spaces or notebooks: tags are how it groups notes, so choosing tags under Sync is how to keep part of your notes on the Kindle. The tag list shows all your tags with how many notes have each, including notes that aren't on the Kindle.",
            "The Grimmory and Notes tabs now have ZenOS's status bar at the top (clock, Wi-Fi, battery) like Home and Downloads, and no close button.",
            "Fixed: on Home, pressing ▼ on the 5-way from the reading stats framed the whole Recent section before reaching the books. It now goes to the Recent / Search / Series tabs, then the books, the same way ▲ comes back.",
        },
    },
    {
        version = "1.5.1",
        changes = {
            "Fixed: the Notes tab stayed empty for a Memos account with more than a few notes. Memos answered within seconds, but the notes were handed back from GZreader's background process through a pipe that holds about 64 KB, and a bigger list got stuck until it timed out after two minutes. Big results are now read as they arrive (this also covers the update check and cover pre-sizing, which could hit the same limit).",
            "When the notes can't load, the Notes tab now says why (and that Menu → Refresh tries again) instead of \"No notes yet\", and shows \"Loading your notes…\" the first time.",
            "Favorites is back in Settings → Interface → Navbar → Tabs, turned off, so you can turn it on again next to Notes (or instead of it). 1.5.0 had taken it out of the list.",
            "The setup guide's Navbar Tabs page now offers Notes (on) and Favorites (off). A tab you turn on there is added to the bar even if it wasn't in it before (History, Authors…), and the page leaves room for Downloads and Grimmory so the bar never goes over 7 tabs.",
        },
    },
    {
        version = "1.5.0",
        changes = {
            "New: the Notes tab, for your Memos notes (usememos.com, version 0.31 or newer). It takes the place of Favorites in the tab bar (Alt+T). Your notes show as sticky notes in a handwriting font (Patrick Hand), six to a page, each at a slight angle, pinned notes first. Q–Y open a note; ◀ ▶ turn pages.",
            "Connecting: the first time you open the Notes tab, choose Connect with QR code (enter your Memos address and an access token on your phone) or Connect by typing. Create the token in Memos → Settings → Access Tokens. The Kindle keeps the token, never your password, and never writes it to the log.",
            "A note shows its whole text, its pictures, tags, place and attachments. Tick or untick checklist items with their letter key; the change is saved to Memos. PDFs and other attachments open in the reader, pictures in the image viewer. Alt+E edits the note, Alt+P pins it.",
            "Writing notes: N on the board opens a full-page editor. The toolbar at the bottom adds Markdown for you: bulleted list, checklist, numbered list, heading, italic, bold, and # Tag (pick one of your tags or type a new one; the keyboard has no # key). ▼ from the last line moves to the toolbar, ◀ ▶ choose, Press applies, ▲ goes back. Shortcuts: Alt+L, Alt+C, Alt+N, Alt+H, Alt+K, Alt+B, Alt+G and Alt+S to save. New notes are private; Alt+V changes who can see one. Alt + the top row types numbers in the editor.",
            "Filters (F): tag, date, place, with attachments, pinned, or search the text.",
            "Works offline: the notes you last saw stay on the Kindle, and new notes, edits and ticks made without Wi-Fi are sent the next time the Notes tab reaches Memos.",
        },
    },
    {
        version = "1.4.3",
        changes = {
            "Fixed: read aloud said \"The Kindle voice didn't respond\" after an audiobook had been paused or left playing. A paused audiobook's player still holds the Kindle's only sound device. Opening a book now stops the audiobook (its place is saved), and starting read aloud also stops any audio player GZreader left running.",
            "The audiobook's percentage and progress bar on Home now update as you listen: each time the position is saved (every minute while playing) and when you close the player.",
            "Smoother screen while an audiobook plays: the listening position goes to Grimmory every 5 minutes instead of every minute, and when you pause, stop or close the player. Each send is an HTTPS request that keeps a Kindle 3's processor busy for several seconds. Your place is still saved on the Kindle every minute.",
        },
    },
    {
        version = "1.4.2",
        changes = {
            "New audiobook player. It shows the cover, title and author, the chapter playing (\"Chapter 4: On the Trail · 4 of 12\"), a progress bar for the chapter with time in it, and the time and percent through the whole book. Controls are on screen with letter keys: Q Chapters, W Sleep timer (15, 30, 45 or 60 minutes, or the end of the chapter), E Stop, and A / S for quieter and louder, with the current volume between them. The Kindle's volume buttons work too. ◀ ▶ skip 30 s, ▲ ▼ change chapter, Press plays or pauses.",
            "The chapter list marks the chapter playing and shows each chapter's start time and length.",
            "Fixed: Stop and Close in the audiobook player didn't bring back the screen behind it, so the player stayed on screen.",
            "Audiobook covers: Grimmory's square audiobook cover is fetched once and kept with the audiobook. It's shown in the player and on the audiobook's tile on Home, in Recent and in Downloads. A cover already seen in the Grimmory tab is reused without downloading it again.",
            "Menu wording: \"Sort books…\" is now \"Sort\", and \"Check for GZreader updates\" is now \"Check for updates\".",
            "Fixed: pressing Menu while the Home menu, the Reading menu or the chapter list was open sometimes did nothing. It now closes the menu.",
        },
    },
    {
        version = "1.4.1",
        changes = {
            "The Grimmory tab shows covers. Book lists (All books, Continue reading, Recently added, a library, author, series or shelf, search results, Audiobooks) follow the same Menu → Display choice as Downloads: List with details (cover, title, author, format and progress), Tiles (3 × 3 covers) or Simple list. Letter keys work in all three.",
            "Covers stay fast on a Kindle 3. Only the page you're looking at is fetched, in the background, and the list shows straight away with placeholders. Each cover is downloaded once and kept on the Kindle, so pages you've seen before appear immediately, even offline. Grimmory has no smaller size than its standard thumbnail (10–20 KB), so GZreader shrinks them on the Kindle and keeps the result while you browse. Covers are only fetched when Wi-Fi is already on.",
            "Audiobooks use Grimmory's square audiobook cover, in the Grimmory tab and on their tiles.",
        },
    },
    {
        version = "1.4.0",
        changes = {
            "Audiobooks show like books: each downloaded audiobook gets a tile in Downloads → Audiobooks with its Grimmory cover, title, author, length and narrator. Opening the tile starts the player.",
            "Played audiobooks go into Recent and History, and onto Home as the current book, with how far you've listened. Opening one from there starts the player too.",
            "To delete an audiobook, highlight its tile, press Menu and choose Manage → Delete from this Kindle. Grimmory keeps it and your listening position.",
            "New: Menu → Display chooses how Downloads and the other book folders show books: List with details, Simple list or Tiles. Downloads switches to List with details once, which shows covers, titles, authors and a letter key for each book. The Sort books dialog has letter keys too.",
        },
    },
    {
        version = "1.3.9",
        changes = {
            "Fixed: after GZreader restarted (for example to install an update) while an audiobook was playing or paused, its audio player kept running in the background. The Kindle 3 can only play one thing at a time, so audiobooks and Test audiobook playback then failed with \"no working player found\". GZreader now stops a leftover player when it starts, and again before playing or testing.",
            "Test audiobook playback no longer erases a player that worked before when it can't find one this time.",
        },
    },
    {
        version = "1.3.8",
        changes = {
            "Fixed: when the audio player quit as soon as it started, an audiobook resumed partway through showed \"The end of the audiobook\" and its listening position went back to the start. Now GZreader says the audio didn't play, keeps your place and writes what the player said to the diagnostic log.",
            "If the player stops on its own well before the end of a track, GZreader keeps your place and says it stopped unexpectedly, instead of treating it as the end of the book.",
        },
    },
    {
        version = "1.3.7",
        changes = {
            "\"Send diagnostic log to my phone\" in the Home menu is now \"Diagnostics\". It asks whether to send the log to your phone (QR code) or save it on the Kindle to copy over USB. The choices have letter keys (Q, W, E).",
            "Diagnostics is in the Reading menu too, so you can send or save the log without closing the book.",
        },
    },
    {
        version = "1.3.6",
        changes = {
            "Downloads → Audiobooks now lists your downloaded audiobooks by title, with how far you've listened. Choose one to open the player. Before, it showed GZreader's storage instead: a folder named after the book's number holding thousands of 15-second audio pieces, which froze the Kindle when opened.",
            "Audiobooks are now kept in a hidden folder, so file lists, folder covers and Search books on this Kindle no longer go through those audio pieces. Audiobooks you've already downloaded are moved there once when GZreader starts. Nothing is downloaded again and your listening position is kept.",
            "You can now delete a downloaded audiobook: Downloads → Audiobooks → Delete an audiobook from this Kindle. Grimmory keeps it and your listening position.",
            "Fixed: deleting an unfinished audiobook (after a restart) didn't stop its conversion still running in the background.",
        },
    },
    {
        version = "1.3.5",
        changes = {
            "While an audiobook is playing or paused, the Home menu shows \"Now playing: title\" (or \"Audiobook paused: title\"). It brings back the player, so you can pause or stop it without going through the Grimmory tab.",
        },
    },
    {
        version = "1.3.4",
        changes = {
            "Settings pages show each entry's letter key in a box, like the Home and Reading menus, so you can see which letter opens what.",
            "General → Updates is now the first entry in General.",
            "Test audiobook playback (Settings → Reader) runs over the Settings page, and you're back in Settings when it's done. Before, it closed Settings and went back to Home.",
            "Shorter Home menu: Grimmory library and Audiobooks are gone (both are in the Grimmory tab, Alt+R). The Audiobooks entry in Settings → Grimmory is gone too. Grimmory tab → Audiobooks lists them, and a downloaded or playing audiobook opens straight away from there.",
        },
    },
    {
        version = "1.3.3",
        changes = {
            "Fixed: in Read aloud settings, pressing Louder (or Faster) more than once went the wrong way. The dialog reopened after each press with the 5-way back on Quieter (or Slower). Now the number changes in place and the selection stays where it was.",
            "Settings are where you'd look for them. The GZreader section is now called Grimmory and holds the connection, sync and audiobook options. General has Wi-Fi only when needed (under Wi-Fi), Diagnostic logging, Remote debugging, Usage statistics, and sending or saving the diagnostic log. Reader has Read aloud and Test audiobook playback (from the Audiobooks menu). Interface has Pre-size covers and Menu key opens the GZreader menu.",
            "Removed duplicates: Browse library and Downloads from the Grimmory settings (the library is on Home, and Downloads shows in the Menu while something downloads), GZreader updates (in General → Updates) and KOReader settings from the Home menu (in Settings).",
        },
    },
    {
        version = "1.3.2",
        changes = {
            "Highlighting a book and pressing Menu now shows one entry, Manage \"book title\", instead of separate Open, Delete and More options entries. It opens the book's options with Open and Delete from this Kindle added at the top.",
            "Book option menus have letter shortcuts on the Kindle Keyboard: Q, W, E and so on, shown in a box in front of each option, like the Home and Reading menus. This includes their sub-menus, such as Add to collection, Read status and Edit.",
        },
    },
    {
        version = "1.3.1",
        changes = {
            "The update download can't be closed any more. Keys and taps are ignored until it's installed and GZreader restarts, so an update can't be left half done.",
            "Leaner ZenOS for Kindle. Bluetooth support is gone: the Kindle 3 has no Bluetooth, but ZenOS still started a lipc-get-prop process each time it checked the status. Also removed: the Kobo Bluetooth fix, Kobo and PocketBook adapters, the OPDS and cloud-storage add-ons (and the Dropbox, FTP and WebDAV code they loaded), and the Zen OPDS setting. Warmth and brightness schedules only load on Kindles with a front light.",
            "The download is smaller: device code for Kobo, PocketBook, reMarkable, Android and other e-readers is no longer included.",
        },
    },
    {
        version = "1.3.0",
        changes = {
            "Usage statistics, sent to the developer's Tianji server to find problems on real Kindles. Basic is on by default: version, Kindle model and firmware at start, restarts after a freeze or crash, downloads that worked or failed, slow operations, and keys the screen didn't answer. Full also sends time on each screen, menu entries used, reading sessions (minutes, pages, pages per minute, battery use per hour), read aloud, download speed, sync results and Wi-Fi on-time. Off sends nothing.",
            "Change the level in the setup guide or in Settings → GZreader → Usage statistics. No book titles, file names, account or anything you type is ever sent. Statistics go out in one batch at most every 15 minutes, only while Wi-Fi is already on.",
        },
    },
    {
        version = "1.2.9",
        changes = {
            "The Downloaded tab is now called Downloads, and its icon's lines are thinner, to match the other tab icons.",
            "Home is easier to read. Bigger text for the current book's author, series, progress percent and page count. The Pages today, Read today and Day streak labels are bigger, and so are the Recent, Search and Series buttons. Sizes you never changed are updated once.",
            "Fixed: turning off remote debugging left its watchdog running. The next restart (an update, for example) was then reported as a crash, even though reporting was off. Now turning it off stops the watchdog and drops any reports still waiting to be sent.",
        },
    },
    {
        version = "1.2.8",
        changes = {
            "Fixed: \"Wi-Fi only when needed\" never turned off Wi-Fi that was already on, for example when the Kindle connected at startup or reconnected after waking. GZreader only turned off Wi-Fi it had switched on itself, so on most Kindles Wi-Fi stayed on the whole time. Now Wi-Fi that's on goes off a minute after nothing uses it. Wi-Fi you turn on yourself from the menu or quick panel is still left on until you turn it off.",
        },
    },
    {
        version = "1.2.7",
        changes = {
            "Picture books: the top of the page is no longer under the clock when the status bar is set to overlap the page. In that mode ZenOS doesn't make room for its title bar, and 1.2.6 assumed it did. Books fitted by 1.2.6 are fitted again once.",
            "Home: the current book's title, author and series are bigger (20, 15 and 13 instead of 11, 9 and 7), so they're readable on a Kindle 3. Sizes you never changed are updated once.",
        },
    },
    {
        version = "1.2.6",
        changes = {
            "Picture books no longer refresh at random or ask \"Styles have changed…\". Fitting a book used to lay the open book out three times, and KOReader then laid it out again in the background and reloaded it. Now GZreader reads the picture sizes first, saves the layout with the book, and reopens it once. Books fitted by 1.2.x are fitted again once when you next open them.",
            "Picture books: pages no longer run under the status bar at the bottom. There's now a small gap above it, and room for the whole bar when it's set to overlap the page. Pictures are slightly smaller (99% of the page instead of 99.5%).",
            "Picture books: no more empty page after a picture inside a heading, such as Diary of a Wimpy Kid's title page.",
            "The download progress line (percent, size, speed, time left) is centred under the bar.",
            "Emulator: a live mode you can drive from a page in Claude (tools/gzreader/emulator/live.lua, relay.py).",
        },
    },
    {
        version = "1.2.5",
        changes = {
            "Fixed: after the setup guide, ZenOS started its tour of the touch menus. On a Kindle Keyboard it opened GZreader's Menu over the Home screen instead (and tried again at every start), and on the first book it opened the page browser with \"Swipe up to open the Page Browser\". Both tours are touch-only and are now skipped on keyboard Kindles.",
            "Fixed: turning a picture book on made KOReader ask \"Styles have changed in such a way that fully reloading the document may be needed…\". Only Press or Back answer that box, so the page keys looked frozen. The book is now reloaded once, without asking.",
            "Picture books: the picture sizes (used to find wide pictures such as a publisher's logo) are read in a low-priority background process. 1.2.0 read them on the screen's thread when the book opened, which took about a minute for Diary of a Wimpy Kid. That process is separate from syncing, so syncing doesn't wait for it.",
            "Remote debugging is lighter. The CPU profiler (timer signals all the time) is off unless you turn on Settings → GZreader → Remote debugging → Detailed timing. Slow-operation timing no longer catches and re-raises errors, so crash.log keeps the full traceback again. The watchdog closes a file it left open every 5 seconds.",
            "Remote debugging tells freezes apart. The heartbeat and the \"previous run ended unexpectedly\" report now say how many keys reached GZreader, when the last key arrived, when the screen last changed, and what's on screen. A \"Screen not answering keys\" report is sent when keys arrive for 45 seconds without any screen change.",
            "New for development: tools/gzreader/emulator runs GZreader's real code as a Kindle 3 under qemu. It uses the Kindle's own binaries, scripted keys, and screenshots of what the e-ink panel shows, at about a Kindle 3's speed. The setup and picture-book problems above were found with it.",
        },
    },
    {
        version = "1.2.4",
        changes = {
            "Removed the one-time moves from older versions: renaming the old Grimmory books folder and GZreader's old files, the plugins/grimmory.koplugin placeholder in the packages, and restyling picture books fitted by older versions. Fresh installs only.",
        },
    },
    {
        version = "1.2.3",
        changes = {
            "Much less freezing: GZreader no longer talks to Grimmory on the screen's thread. Closing a book, going to sleep, page sync, bookmarks, the login refresh, search, audiobook position and the first file lookup all ran there and froze the Kindle while they waited, for many seconds when Wi-Fi was weak (your reports showed 7 to 10 seconds when closing and opening books). They now run in the background, and positions and reading sessions are saved first and sent right after, so nothing is lost if the Kindle sleeps or restarts meanwhile.",
            "Working out the exact page for Grimmory's web reader (reading the chapter's XHTML) also moved to the background; it took seconds on the screen's thread when a book closed.",
        },
    },
    {
        version = "1.2.2",
        changes = {
            "Remote debugging: slow reports show 6 levels of code instead of 3, and GZreader warns when a book's layout is redone 6 or more times in a minute (margins, styles, fonts…), naming the code that asked each time: on a Kindle 3 every layout of a whole book takes seconds.",
        },
    },
    {
        version = "1.2.1",
        changes = {
            "Remote debugging finds what makes the Kindle slow: GZreader now notes where its CPU time goes (a light sampling profiler) and reports a keypress, repaint or piece of work that takes more than 3 seconds, with the code that used the time. When it uses most of the CPU for a minute it sends a \"GZreader busy\" report, and the watchdog sends \"GZreader slow\" after 45 seconds without an answer (\"unresponsive\" after 2 minutes), each with GZreader's processes (running or waiting, CPU, memory) and that profile.",
            "Fixed: the remote-debugging watchdog left a finished process behind every 5 seconds (89 after 8 minutes); it no longer starts any for its regular checks.",
            "ZenOS's clock bar at the top of a book no longer covers the text when the footer is hidden (its space was taken from the footer's height, 0 when hidden). Picture books use it too, so the clock sits above the page.",
        },
    },
    {
        version = "1.2.0",
        changes = {
            "Remote debugging: GZreader can report to your own feed when it starts, when the previous run ended without closing normally (hard reboot, battery ran out, freeze or crash, with what it was doing and the end of its log), when the Kindle stops responding for 2 minutes (with memory, load and running processes at that moment), when it responds again, when GZreader crashes, and its warnings and errors. A small separate watchdog process does the watching and sending, so it works while GZreader's screen is stuck; messages wait while Wi-Fi is off. Set the feed address in Settings → GZreader → Remote debugging, or put it on the first line of a file gzreader-remote.txt on the Kindle's USB drive.",
            "Picture books fill the space between the clock and the footer: the clock no longer sits on the page, and pages are no longer shown at their small original size (1.0.30's sizing was ignored by the Kindle). Wide pictures such as the publisher's logo keep their own size.",
            "GZreader's files are named GZreader: the books folder is now documents/GZreader (renamed from Grimmory on the first start, with history, collections, the home folder, last book and reading positions following along), and the plugin, settings, log and caches are gzreader too.",
        },
    },
    {
        version = "1.1.0",
        changes = {
            "Unfinished downloads are picked up again: if a book download (or one waiting in the queue), an audiobook download or preparing an audiobook for the Kindle is cut short (the battery ran out, the Kindle went to sleep or restarted, GZreader crashed or was closed), GZreader asks a few seconds after it next starts: Continue, Delete what was downloaded, or Ignore. Books continue from where they stopped instead of starting over; audiobooks keep the tracks already downloaded or prepared.",
            "Page sync with Grimmory's web reader is exact: the Kindle now sends the exact place on the page (an EPUB CFI), so the web reader opens on the same page instead of at the start of the chapter, and a place set in the web reader opens on the same page on the Kindle.",
            "The percentage sent to Grimmory is counted the way its web reader counts it, so Grimmory shows the same figure on that page (the Kindle's own footer still counts its own way, so 11% on the Kindle can be 15% in Grimmory). Whether Grimmory is ahead of or behind the Kindle is now judged on the actual page, not by comparing the two kinds of percentage.",
            "Sleep screen “Show custom image (book cover while reading)”: shows your image from Home and menus, and the cover of the book you're reading while a book is open (it used to show the image everywhere). Choosing a sleep screen in that menu, or a ZenOS sleep-screen preset, now always takes effect.",
            "The Grimmory tab shows ZenOS's status bar (clock, battery, Wi-Fi, downloads) at the top and keeps the tab bar at the bottom with the Grimmory tab underlined, like the other tabs. In a list inside it, the title shows the list's name and a back arrow.",
            "Menus: “ZenOS quick panel” is now “Quick panel”; in the Reading menu “All settings (full menu)” is now “Quick panel”, and there's a new “Settings” entry that opens the same Settings page as on Home.",
        },
    },
    {
        version = "1.0.30",
        changes = {
            "Picture books: each page now fills the space between the title bar and the footer instead of the whole screen, so the clock no longer sits on top of the page and the bottom line isn't cut off. Pictures keep their shape: a small or wide picture such as the publisher's logo is no longer stretched.",
            "Picture books use smooth image scaling: the pages are small scans enlarged to the screen, and the handwriting now looks much less jagged. Turning “Fit pictures to the screen” off puts your previous setting back.",
            "Books already fitted by 1.0.28 are updated the next time they open.",
        },
    },
    {
        version = "1.0.29",
        changes = {
            "Highlights and notes sync with Grimmory: EPUB highlights and notes made on the Kindle appear in Grimmory's web reader and on your other devices, and theirs appear here, at the same words. New ones, colour and style changes, notes and deletions go both ways. A highlight changed in both places since the last sync is left as it is in each, so nothing is overwritten. Syncs a few seconds after a book opens, a few seconds after you highlight or write a note (with Wi-Fi on), with Sync now, and when you close the book. The work runs in the background at low priority, so the page doesn't wait. Settings → GZreader → Sync highlights and notes turns it off. (Conversion and merge from Grimmory-KOReader-Client, MIT.)",
            "The Grimmory tab opens at once, also offline or while Wi-Fi is still connecting. Each list (Continue reading, Recently added, All books, libraries, shelves, an author's or a series' books, audiobooks) is kept on the Kindle when it's loaded, shown straight away next time with “· saved” in its title, and replaced by the fresh list when it arrives.",
            "Reading sessions aren't counted twice: when Grimmory's reply to a reading session got lost, GZreader checks the book's session history on Grimmory before sending it again.",
            "Books with picture or SVG pages in their spine: position, bookmark and highlight sync now find the right chapter (they fell back to percentages before).",
        },
    },
    {
        version = "1.0.28",
        changes = {
            "Picture books (for example Diary of a Wimpy Kid, where every page is a picture of the printed page): recognized when they open, and each page then fills the screen top to bottom, keeping its shape, with no margins and nothing cut off. Done once per book; Reading menu → “Fit pictures to the screen” turns it on or off (your previous margins come back when off).",
        },
    },
    {
        version = "1.0.27",
        changes = {
            "Opening a book: the “Opening” strip and its text are about twice as big on the Kindle Keyboard.",
            "Read aloud follows sentences: each piece is a whole sentence (it used to be cut every 40 words, so pieces started and stopped mid-sentence). Only very long sentences are split, at a comma, semicolon, colon or dash; a paragraph or heading always ends a piece.",
            "Read aloud turns the page while a sentence that runs onto the next page is being said, at about the point the voice gets there, instead of after the whole sentence.",
            "Read aloud skips web addresses (anything starting with http://, https:// or www.).",
        },
    },
    {
        version = "1.0.26",
        changes = {
            "Managing downloaded books: highlight a book on Home or in the Downloaded tab (with the 5-way) and press Menu. The GZreader menu then starts with Open, Delete from this Kindle and More options for that book. Delete asks first; it removes the file with its reading position and bookmarks on the Kindle, and Grimmory keeps the book and your progress.",
            "Sort books… in the GZreader menu: last read, title, author, series, date downloaded, reading progress, file size or file name, and reverse order. It sorts the Downloaded tab and the other book lists.",
        },
    },
    {
        version = "1.0.25",
        changes = {
            "Downloads screen: while anything downloads, “Downloads (N)” is the first entry of the GZreader menu (Menu key on Home) and is in the Reading menu; it's always in Settings → GZreader. It lists the current download with its progress, the books waiting in the queue, and audiobook downloads and preparing. Pick one to reopen its progress bar, stop it, or take it out of the queue; or empty the whole queue.",
            "The title bar on Home and in the library shows a download icon with the current percentage and how many books are waiting (for example “42% +2”), updated every 10 seconds, and nothing when no download is running. It sits next to the clock and can be moved or removed in the status bar settings.",
        },
    },
    {
        version = "1.0.24",
        changes = {
            "Choosing a book to download shows its cover from Grimmory (and its authors) in the Download question. The dialog opens at once and the cover appears a moment later; covers are kept on the Kindle, so next time it's there straight away.",
        },
    },
    {
        version = "1.0.23",
        changes = {
            "Audiobooks: fixed the Kindle restarting while preparing an M4B. The conversion now runs as its own small, lowest-priority process (about 8 MB of memory for a long book) instead of a copy of GZreader, and reads the book's sample tables bit by bit instead of all at once.",
            "Audiobooks: the preparing step has its own progress bar (percentage, MB done of the total, speed, time left). M4Bs downloaded earlier are prepared, with the same bar, the first time you press play.",
            "Syncing no longer freezes the page: progress sent while reading, Grimmory's position fetched when a book opens or wakes, and queued updates now go in a background process.",
            "Grimmory's JSON replies are now requested gzip-compressed: lists and the library index arrive 5-10x smaller (less to receive and decrypt on the Kindle 3).",
            "Shelves: Grimmory tab → Shelves lists your shelves and smart shelves.",
            "Auto-download a shelf (Settings → GZreader): books you put on a Grimmory shelf, for example “Kindle”, download by themselves in the background when Wi-Fi is on (at most every 30 minutes), or right away with “Download new books from the shelf now”.",
            "Download progress also shows the speed and time left.",
        },
    },
    {
        version = "1.0.22",
        changes = {
            "Faster start: all of GZreader's Lua code (KOReader, ZenOS, the plugins) now ships precompiled for the Kindle's LuaJIT, so it isn't parsed on every start. Loading is about 4 times faster across the board and up to 15 times for the big ZenOS files.",
            "Home: books whose covers are pre-sized no longer have their full cover unpacked on every Home rebuild; the ready-made cover is loaded instead.",
            "The cover pre-sizing job now does all its file checks in its background process, so the screen never waits for it.",
            "Less background work: the audiobook player checks in every 2 seconds instead of every second and redraws its clock every 30 seconds; diagnostic logging opens the log file once per line instead of twice and skips the secret filter on lines that can't contain secrets; UI text branding is worked out once per string.",
            "Pairing, the Grimmory browser, downloads and read aloud load when first used instead of at start.",
        },
    },
    {
        version = "1.0.21",
        changes = {
            "Covers are pre-sized: each downloaded book's cover is made once at the exact sizes Home, the cover strip and the library show it, kept on the Kindle, and just loaded after that. No scaling or unpacking while you wait, also after a restart. This runs in a low-priority background process a minute after start, after each download, and when a view shows covers at a new size. Switch: Settings → GZreader → Pre-size covers.",
            "The Home cover strip is back on (1.0.20 turned it off because of the slow scaling).",
        },
    },
    {
        version = "1.0.20",
        changes = {
            "Wi-Fi only when needed (on by default; Settings → GZreader): Wi-Fi turns on by itself for browsing Grimmory, downloads, connecting, sending the log, updates, and to sync when a book opens or closes (and on wake after 15 minutes or more), then off again after a minute unused. Changes in between wait for the next sync. Wi-Fi you turn on yourself stays on.",
            "Speed: the Home cover strip is turned off on the Kindle Keyboard. Each Home screen spent about 4 seconds of CPU drawing it, which is what made Home feel frozen. Settings → Home brings it back.",
            "KOReader's version label (About, crash log) is now correct after updating from a release's source zip.",
        },
    },
    {
        version = "1.0.19",
        changes = {
            "Subtitles: books show their subtitle from Grimmory, e.g. \"Diary of a Wimpy Kid: Old School\", in the Grimmory lists, the Downloaded tab, Home and the reader. Books already on the Kindle get theirs after the next library index (a minute or so after starting with Wi-Fi). A title you changed yourself in Book information is left alone; resetting it there brings back the original.",
            "Download queue: picking another book while one downloads adds it to the queue (\"Add to queue\") instead of refusing. Queued books download one after another; lists show \"queued\", a short notice says when each is done, and the download options can empty the queue. \"Continue in background\" keeps the rest of the queue in the background too.",
        },
    },
    {
        version = "1.0.18",
        changes = {
            "Downloads (books and audiobooks) keep the Kindle awake until they finish, even in the background: no screensaver, no sleep.",
            "The download progress shows the percentage and how much has arrived out of the total, e.g. \"42% · 116.0 MB of 276.0 MB\".",
            "The Reading menu and the GZreader menu also do a full screen refresh when they close (Back, Menu or picking an entry).",
        },
    },
    {
        version = "1.0.17",
        changes = {
            "The Reading menu and the GZreader menu open with a full screen refresh, so the page behind no longer ghosts through.",
        },
    },
    {
        version = "1.0.16",
        changes = {
            "Reading: the AA key and Reading menu → Font, size and layout open the font and layout menu again. ZenOS's \"no bottom swipe\" setting was also blocking them on the Kindle Keyboard, which has no swipe.",
        },
    },
    {
        version = "1.0.15",
        changes = {
            "The Grimmory settings are now Settings → GZreader, on the main Settings page (they were under Settings → General → Grimmory).",
        },
    },
    {
        version = "1.0.14",
        changes = {
            "Night mode is switched off and can't be turned on on the Kindle 2, DX, Keyboard and 4: they can't invert the screen in hardware, and inverting in software made the Kindle unusably slow (and frozen at every start, because the setting was saved).",
            "GZreader menu: Settings opens the Settings page (Home, Library, Reader, Interface, Extras, General, KOReader); new KOReader settings entry opens its KOReader section. \"All settings\" (which reopened ZenOS's quick panel) is now labelled ZenOS quick panel.",
        },
    },
    {
        version = "1.0.13",
        changes = {
            "Kindle Keyboard: the Menu key on Home and in the lists now opens the GZreader menu, a list with letter keys like the Reading menu (Grimmory library, continue reading, audiobooks, search, history, Wi-Fi, night mode, settings, updates, send log, sleep, restart, all settings, exit), instead of ZenOS's touch quick-settings panel. Switch: Settings → GZreader → Menu key opens the GZreader menu.",
            "Audiobooks: playback fixed. The Kindle's player doesn't take the option GZreader passed, and its MP3/AAC decoders are the Freescale hardware ones (mfw_mp3decoder, mfw_aacdecoder); the players now use them. Run Test audio playback again once.",
            "M4B: the Kindle 3 can't open MP4 files, so after download GZreader converts the audio (no re-encoding, seconds to a few minutes) into small AAC pieces the Kindle can play, and can start anywhere in the book. M4Bs downloaded with 1.0.12 are converted the first time you press play.",
            "Audiobook downloads resume where they stopped after a dropped connection or timeout (they used to start over and could never finish a large book), and the login is refreshed during long downloads.",
            "If the player stops at once, the listening position is kept (it used to jump ahead).",
        },
    },
    {
        version = "1.0.12",
        changes = {
            "Keyboard: every entry in the ZenOS settings and in KOReader's menus shows a letter (Q, W, E …); press it to pick the entry. In KOReader's menus, Alt + Q, W, E … switch the tabs.",
            "The bottom tabs show their key (Alt+Q, Alt+W …) under the label on a Kindle Keyboard.",
        },
    },
    {
        version = "1.0.11",
        changes = {
            "Read aloud: fixed skipped sections and a highlight that didn't match the voice. Sentences now go to the Kindle voice one request at a time, in order, all through its queue (1.0.8 sent two at once; the second could arrive first and was then thrown away).",
        },
    },
    {
        version = "1.0.10",
        changes = {
            "Time zone: Settings → General → Time zone (the Kindle 3 has none and keeps its clock in UTC, so clocks showed UTC).",
        },
    },
    {
        version = "1.0.9",
        changes = {
            "Audiobooks (experimental): browse Grimmory's audiobooks, download them (M4B or MP3 tracks) and listen with chapters, ±30 s, a sleep timer and volume; listening position syncs with Grimmory's web player.",
            "Test audio playback finds which of the Kindle's players can play MP3 and M4B (AAC) audio.",
        },
    },
    {
        version = "1.0.8",
        changes = {
            "Read aloud no longer skips words or sentences: the next sentence is queued behind the one being spoken instead of replacing it, and reading follows the Kindle voice's own start/finish signals (estimates only as a fallback).",
            "Send the diagnostic log to your phone over Wi-Fi: Settings → General → Grimmory → Send diagnostic log to my phone (QR code).",
        },
    },
    {
        version = "1.0.7",
        changes = {
            "Updates: fixed \"Download failed: err 415\" when a release had no attached packages yet (GitHub refused the source code zip request).",
        },
    },
    {
        version = "1.0.6",
        changes = {
            "Grimmory settings are in Settings → General → Grimmory (no more digging through KOReader → Tools).",
        },
    },
    {
        version = "1.0.5",
        changes = {
            "Read aloud speaks whole sentences at normal speed (it was sending one word at a time), and the last word of each sentence is no longer held back.",
            "Read aloud volume: Quieter / Louder in Read-aloud settings, or the Kindle's volume buttons while reading.",
            "Settings: the entry that opens KOReader's own settings is called KOReader again.",
            "Downloaded tab: books show on the first visit (no more \"Set home folder\" until Home was opened).",
        },
    },
    {
        version = "1.0.4",
        changes = {
            "Read aloud: \"Find the Kindle voice\" now learns the request the Kindle's speech service (ttsd) expects from its own error messages (it asked for an id), instead of guessing numbered variants.",
            "Starting the voice test twice no longer runs two tests at once.",
            "Diagnostic log: lists the speech service's request fields.",
        },
    },
    {
        version = "1.0.3",
        changes = {
            "Updates work with any GitHub release: the Kindle uses the attached gzreader-update.zip, or else the release's source code zip (nothing to upload). Tags like v.1.0.2 are understood.",
            "Settings → Updates is GZreader's updater, with this changelog (no more ZenOS updater or ZenOS changelog).",
            "New GZreader logo (setup guide, settings, sleep fallback).",
            "Read aloud on the Kindle 3 through the Kindle's own lipc-hash-prop tool; the voice test only offers ways the speech service accepted.",
            "Bottom tabs: Alt + Q, W, E, R, T (the Kindle Keyboard has no number row).",
            "Setup guide: sleep-screen option no longer cut off.",
        },
    },
    {
        version = "1.0.0",
        changes = {
            "First GZreader release: Grimmory + ZenOS + KOReader for the Kindle Keyboard.",
            "QR / SSO sign-in, Grimmory library browser (Libraries, Authors, Series, no audiobooks), background downloads.",
            "Native progress sync and two-way bookmark sync with Grimmory, offline queue.",
            "Reading menu on the Menu key, read aloud with Shift + Sym, book-cover / screensavers-folder sleep screen.",
            "Speed fixes for the Kindle 3, English dictionary, diagnostic log.",
        },
    },
}
