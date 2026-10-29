-- GZreader changelog, newest first. Shown in Settings → Updates → Changelog.
-- Add an entry (and bump GZREADER_VERSION) for every release.
return {
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
