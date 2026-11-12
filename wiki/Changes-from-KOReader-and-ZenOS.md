GZreader is a fork of [KOReader](https://github.com/koreader/koreader) (currently `v2026.07.1`) with [ZenOS](https://github.com/xZenLabs/zen-os) (currently `4.3.1`) as its interface. Most of what it adds is its own plugin, `gzreader.koplugin`; where it had to change KOReader or ZenOS, the changes are marked in the code and checked by a test (`tools/gzreader/tests/keeps.py`), so an upstream update can't drop them unnoticed. Upstream updates are merged with `tools/gzreader/upstream.sh`.

## Compared with KOReader

**Left out** ([What's in GZreader](Whats-in-GZreader)): all bundled plugins except Cover browser, Statistics and Auto suspend (KOReader's own progress sync, OPDS, news downloader, SSH, terminal and the rest); KOReader's OTA updater; the CJK fallback font; UI translations; the first-run quickstart document.

**Added:**

- **Grimmory**: library browser, background downloads, sync of position, bookmarks, highlights, notes, ratings and reading sessions through Grimmory's own API (not its KOReader-compatible endpoint), audiobooks. → [Grimmory library](Grimmory-Library), [Grimmory sync](Grimmory-Sync)
- **The setup page** served by the device, copying connections between devices, sync with a computer for Kindles without Wi‑Fi. → [Setup page and connections](Setup-Page-and-Connections), [Sync with a computer](Sync-with-a-Computer)
- **Notes (Memos), Calendar (links and CalDAV), Music (Plex)**, read aloud with the Kindle's own voice.
- **Updates from GitHub** (its own updater), debug reports (only if you choose) and diagnostics. → [Updates](Updates-and-Test-Builds), [Privacy and diagnostics](Privacy-and-Diagnostics)
- **The quick panel**, replacing KOReader's top and bottom menus and ZenOS's touch menu on every device. → [Using GZreader](Using-GZreader)
- An English dictionary.

**Changed in KOReader's own code:**

| Where | What |
| --- | --- |
| Kindle 2, DX, 3, 4 drawing (`frontend/device/kindle/shadowfb.lua`, `device.lua`) | A shadow screen: KOReader draws with its fast C blitter into an 8-bit buffer that's packed into the 4-bit (or inverted 8-bit) framebuffer before each refresh; night mode is done while packing. → [Performance](Performance) |
| Kindle start script (`platform/kindle/koreader.sh`) | Restarts, stepping aside for the Kindle's USB drive and coming back after it ("Connect to computer"), the Kindle 2/DX's framework for USB drive mode |
| Nook devices (`frontend/device/nook/`) | The Nook 1st Edition's e-ink page (refreshed through the kernel without a flash) and colour touchscreen (controls, reading info, a keyboard), the Simple Touch's e-ink waveforms and touch; the Nook start script and launcher (`platform/nook/`). → [Nook 1st Edition](Nook-1st-Edition) |
| Loading (`frontend/gzbytecode.lua`, `luasettings.lua`) | A bytecode cache for source installs; settings files are only written when they changed |
| Fonts (`frontend/ui/font.lua`) | Missing fallback fonts (the removed CJK one) are dropped at start instead of failing on every glyph |
| Book layout (`frontend/document/credocument.lua`) | A bigger crengine cache (256 MB instead of 64) |
| Sleep screen (`frontend/ui/screensaver.lua`) | GZreader's own sleep screen: the book's cover while reading and a picture elsewhere, whatever sleep screen was saved before (`frontend/gzsleepmode.lua`); "Custom image or cover" shows the book's cover while reading and the image elsewhere; Scale cover to fill screen (proportions kept, edges cut off; `frontend/gzsleepfit.lua`); with an Immich album chosen, a picture comes from its pictures first, then the folders (`gzsleepmode.pictureDirs`) |
| Menus (`frontend/ui/widget/touchmenu.lua`, menu orders) | Letter keys in KOReader's menus; GZreader's items in place of removed plugins' |
| Home folder (`frontend/apps/filemanager/`) | No Home folder settings (Set, Shorten, Lock) in the file manager's menu and no "Set as HOME folder" buttons: the home folder is always the GZreader folder |
| Back key (`readerback.lua`), translations (`gettext.lua`), plugin loading | Small fixes for the trimmed build |

## Compared with ZenOS

GZreader keeps ZenOS's Home, tabs, library views, settings and setup guide, and changes:

- **Keys:** letter keys in every list and dialog (`__ZEN_DIALOG_SHORTCUTS`, the context menu), tab keys (Z, X, C, V, B) on keyboard Kindles, the 5-way on the Kindle 4. ZenOS was made for touch.
- **The quick panel** instead of ZenOS's touch menu (its Zen Mode button and tabs), on every device; ZenOS's first-run menu tour is replaced by one of the quick panel, which closes it before the page browser tip.
- **Home:** a bookshelf view (books on shelves, audiobooks as a cassette walkman, music as a CD player), Grimmory reading stats on a notebook page in place of ZenOS's local reading stats widget (no longer offered), two shelves on the DX's taller screen; font sizes in Home widgets and the end-of-book page aren't scaled twice.
- **Tabs:** Catalog (Grimmory's books and audiobooks and Plex music, a page each; the Grimmory tab before 1.27.x), Notes (in Favorites' place) and Calendar, Music and Audiobooks on request.
- **The book menu:** Add to shelf and Remove from shelf (your Grimmory shelves, kept on the Kindle, changes sent over Wi‑Fi or by the sync page) instead of Add to collection, also for several selected books; no Add to collection anywhere.
- **The setup guide:** shorter (fewer pages, GZreader's reading defaults set on a first setup), starting with *Set up from your browser*, ending with whether to send debug reports.
- **Settings → Interface → Quick panel:** which tiles the quick panel shows, in place of ZenOS's Controls and Launcher (they set up the touch menu GZreader replaces).
- **Zen mode is always on** (ZenOS's own tabs only): there's no Zen mode switch in Settings → Interface, and it's turned back on if it was off.
- **The update screen:** GZreader's version and what's new in it, after every GZreader update (ZenOS showed its own version and list, only when ZenOS changed).
- **Settings:** GZreader's sections in ZenOS's settings (Connections: Grimmory, Memos, Calendar, Plex, copying connections, sync through a computer) and its items in ZenOS's own sections (General: Wi‑Fi as On, Off or Auto in place of ZenOS's switch, Updates, diagnostics, Send debug reports automatically; Reader: read aloud, Flash on every page turn; Interface: Pre-size covers; Advanced: Flash when the screen changes). ZenOS's Library section is called Downloads; its Folders has no Home folder menu (the home folder is always the GZreader folder).
- **Covers:** pre-sized and cached on disk, made in a background process. → [Performance](Performance)
- **Not loaded:** ZenOS's own updater (GZreader's replaces it; a small stand-in answers ZenOS) and its Rakuyomi manga integration unless that plugin is installed. → [Performance](Performance)
- **The reader's top status bar** (Settings → Reader → Appearance → Top status bar: the clock, by default) stays on screen while the layout menu (the quick panel's Layout) is open and after it closes; ZenOS drew it only while nothing else was open over the book, so it went missing until the next page turn.
- **Wi‑Fi in the status bars** (Home's and a book's top bar): an **A** after the Wi‑Fi icon while Wi‑Fi is on Auto (`common/gz_wifi_icon.lua`); the icon itself still shows on or off.
- **Settings, rearranged:** every row has an icon, and Downloads has the Downloads tab's. General has Time and date (Time zone first), Language and Storage (what's on the Kindle: each part with its size, and an arrow into the biggest of each), which were in About → Device or at the top of Settings. Sleep → Wallpaper shows the sleep screens as tiles with previews, its other settings under Wallpaper options; no custom image, no sleep-screen presets. Connections has Immich (Photos), and Interface → Wallpaper has Picture from Immich (a picture from your Immich album behind Home, changed when new ones come). General → Screen refresh has every setting about when the screen flashes (Flash on every page turn and Flash on every CBZ page turn were in Reader → Appearance, Flash when the screen changes and Partial pages refresh in Advanced).
- **Fewer settings that don't apply:** Settings → About starts with GZreader's version ("Built on ZenOS … and KOReader …" under it) and its **Report a bug** sends to GZreader's developer, not ZenOS's issue tracker. General → Advanced has GZreader's diagnostic log items at the top and no Debug logging, Clear all gestures, Plugin management or Patch management. The KOReader section has no File browser menu (Downloads' own Sort and Filter set the same things), no Tools → Reading statistics (the statistics are still kept), and no Plugin management, Patch management, Developer options, file browser Display mode or Start with, Wi‑Fi actions or Restore Wi‑Fi, second Grimmory menu, or Help → Report a bug and Disable external plugins (GZreader's own plugins count as external). No Manga, News or Calibre Search tabs.
- **Nooks:** paths for a Nook's microSD card, Bluetooth stubbed out, Wi‑Fi switching adapted.
- **Settings → Reader in six rows:** Gestures and controls (Bottom swipe gesture, Reader controls, Page Browser) and Notes and footnotes (Annotation viewer, Footnotes and pinned pages) are submenus; ZenOS has the five side by side. The Settings buttons in the page browser, the annotation viewer and the footnotes drawer open their page inside the group.
- **No Extras section in Settings:** its Schedules and Sleep are in General and Custom icons in Interface (as in ZenOS); the rest (Stats tab widgets, ZenPM, Rakuyomi, Zen Search, Lockdown mode, Zen Keyboard) isn't offered, and keeps its default or what was set before.
- **GZreader's menus look like ZenOS's Settings:** the Calendar and Notes tabs' connect lists, Plex's sign-in and the Music list, Downloads, the sync queue, copying from another GZreader, the Notes filters, the font list and Add to shelf have ZenOS's rows: an icon on the left, an arrow on the right of each row that does something, ZenOS's spacing, and short labels (longer explanations behind an **About …** row). Lists of books, albums and tracks keep their own look.
- **No Metadata menu in Settings → Downloads → Books** (ZenOS's online sources for its metadata editor): a download's title, authors and series come from Grimmory. **Square cover corners in the Bookshelf view** (Rounded cover corners is greyed out there; the other views keep their setting).
- **No Double-tap to open a book on the Kindle 2, 3, DX and 4** (Settings → Downloads → Books): they open books with keys or the 5-way, so there's nothing to tap; the touch Kindles still have it.
- **Branding:** GZreader's name and logo; a "GZreader" item on the touch Kindles' home screen instead of ZenOS's.
- **Settings → KOReader without what GZreader has elsewhere:** no Language, Time and date, Sleep screen, Autosuspend timeout or Wi‑Fi connection (Settings → General), History, Favorites or Collections (tabs), End of document action (Reader → End of book, where it still is), Night mode, Rotation or Exit (Restart, Sleep, Exit: quick panel tiles), Version, About or Quickstart guide (Settings → About and its Setup Guide), and no Cloud storage.

The full list of changed upstream files is `tools/gzreader/tests/keeps.txt` in the repository.
