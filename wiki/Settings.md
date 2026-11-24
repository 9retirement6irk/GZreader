# Settings

Settings opens from the quick panel's **Settings** tile (or Home's menu). Its
first page is arranged as an iPhone's or a Mac's: what you switch most at the
top, then the device, then how GZreader looks and reads, then your accounts,
then privacy. It has nine rows at most, so it fits on one screen on every
Kindle. Rows with a value show it on the right (Wi‑Fi's mode, the service an
account uses). When an update is known, it shows at the top of the page.

| Row | What's in it |
|---|---|
| **Wi‑Fi** | On, Off or Auto ([Wi‑Fi](Wi-Fi)), Networks, HTTP proxy, Network info. |
| **General** | **About** (GZreader's version, what it's built on, the device), Software update (test builds, changelog), Storage, Battery, Time and date, Language; **Transfer, [Add-ons](#add-ons-and-zenpm) (ZenPM)** (copy to or from another GZreader, [sync through a computer](Sync-with-a-Computer)), Setup Guide, **Performance** (Pre-size covers, Lay out new books while charging, Keep connections open). |
| **Display and light** | Screen (e-ink refresh, flashing), Brightness and warmth (schedules), **Dark mode**, the menu font and its size, accent colour, custom icons, Blur menu background; on a Nook, its colour screen or touch orientation. |
| **Sleep and wallpaper** | Sleep (the sleep screen, automatic sleep), Home background, Pictures from Immich. |
| **Audio** | Kindles with a speaker, headphone jack or Bluetooth: [Bluetooth](Bluetooth) first (on or off, the devices), then [read aloud](Audiobooks-and-Read-Aloud), Test audiobook playback, the headphone jack. |
| **Home and tabs** | Home (widgets, edit mode, presets), Status bar, Tab bar (which tabs, their look, the default tab), Quick panel (which tiles, their order, tiles of your own), Downloads tab (layout, covers, folders, books, context menu). |
| **Reader** | Appearance (status bars), Highlight / Lookup, Gestures and controls, Table of contents, Notes and footnotes, Closing a book (end of book, where the library opens). |
| **Accounts and services** | One row per service, the server it uses on the right: Books (Grimmory: your account first, who's signed in), Audiobooks (Grimmory or Plex), Music (Plex), Notes (Memos), Calendar (CalDAV), Photos (Immich), House (Home Assistant). |
| **Privacy and diagnostics** | Diagnostic logging, Send debug reports automatically, Report a problem, sending or saving the log ([Privacy and diagnostics](Privacy-and-Diagnostics)); Advanced → KOReader settings. |

## Dark mode in one place

Settings → Display and light → **Dark mode** has everything that follows dark
mode: the night mode schedule, Reader themes (how books look in dark and light
mode), the night accent colour, and whether the Home background and custom
icons are inverted.

## Each service's page

Every page in Accounts and services has the same order: the account (who's
signed in, connect again, disconnect) first, then what the service does here,
its tab on or off, then **Storage on this Kindle** (or *Storage used*, *Downloaded
music*), and signing out last. The storage row opens Settings → General →
Storage at that service's part, which has the Free up space rows (remove kept
notes or attachments, kept events, downloaded music) that used to be on the
service's own page.

## Add-ons and ZenPM

**Settings → General → Add-ons** is for plugins and extras from outside
GZreader. They aren't part of GZreader and GZreader doesn't check them.

- **Install ZenPM** downloads [ZenPM](https://github.com/xZenLabs/zen-pm),
  ZenLabs' package manager, from its latest release (checked against the
  release's SHA-256) and installs its plugin; the screen shows how much has
  downloaded (megabytes and percent), like a software update. After the restart the row reads
  **Open ZenPM**, and ZenPM has a tile on the quick panel, under **Your
  tiles**. ZenPM has builds for Kindles and Kobos; where it has none the row
  says so.
- Plugins you install (with ZenPM or by copying a `.koplugin` folder into
  `GZreader/app/plugins/`) are kept through GZreader's updates. To open one,
  give it a tile: Settings → Home and tabs → Quick panel → **Your tiles** →
  **Add a plugin's screen**.
- **ZenPM lists GZreader's own ZenOS under Installed**, as "GZreader" by
  ZenLabs. ZenPM can't hide it, so leave it alone there. GZreader looks after
  it at each start:
  - it turns on ZenPM's **Ignore updates** for it, so ZenPM offers no update
    and its Update all skips it (from the first start after ZenPM has been
    opened once);
  - if it was **Disabled** in ZenPM, GZreader switches it back on and offers
    a restart;
  - if it was updated, changed to another version or **Uninstalled**, Home,
    the tabs and Settings stop being GZreader's. GZreader says so and offers
    **Put back**, which downloads this version of GZreader again (your
    settings, books and add-ons are kept). The same is under Add-ons as
    **Put GZreader's ZenOS back**.
- KOReader patches change KOReader's own code and can break GZreader's
  screens: remove a patch in ZenPM if something stops working after adding it.
- Progress sync, OPDS and similar plugins do what GZreader already does with
  your book server. Two of them syncing the same book can disagree.
- Icon packs change ZenOS's icons; GZreader's own screens keep theirs.
- ZenPM's own page warns against its standalone Kindle app on WinterBreak,
  SpringBreak and Sanctuary jailbreaks. That's the Kindle app, not this plugin.

## Where things moved in 1.32.x

| Was | Now |
|---|---|
| General → Wi‑Fi | Wi‑Fi (first page) |
| General → Bluetooth | Audio → Bluetooth (the first page on a Kindle with Bluetooth and nothing else for Audio) |
| General → Updates | General → Software update |
| General → Schedules | Display and light → Brightness and warmth; Night mode schedule in Dark mode |
| General → Sleep | Sleep and wallpaper → Sleep |
| General → Screen | Display and light → Screen |
| General → Audio | Audio (first page) |
| Home → Widgets, Edit mode, Presets | Home and tabs → Home |
| Home → Show top status bar | Home and tabs → Status bar → Show on Home |
| Home → Appearance, Folders, Books, Context menu | Home and tabs → Downloads tab |
| Reader → Appearance → Reader themes | Display and light → Dark mode |
| Reader → End of book, Restore library location on exit | Reader → Closing a book |
| Reader → Lay out new books while charging | General → Performance |
| Interface → Quick panel, Navbar, Status bar | Home and tabs → Quick panel, Tab bar, Status bar |
| Interface → Wallpaper | Sleep and wallpaper → Home background |
| Interface → Font, Accent color, Custom icons, Blur menu background | Display and light |
| Interface → Pre-size covers | General → Performance |
| Connections → Grimmory, Memos, Calendar, Immich, Plex, Home Assistant | Accounts and services → Books, Notes, Calendar, Photos, Music, House |
| Connections → Plex → Audiobooks | Accounts and services → Audiobooks |
| Connections → Grimmory → Keep connections open | General → Performance |
| Connections → Copy to or from another GZreader, Sync through a computer | General → Transfer |
| About | General → About |
| About → Setup Guide | General → Setup Guide |
| About → Report a bug, Send debug reports automatically, Advanced | Privacy and diagnostics (Report a bug is **Report a problem**) |

Nothing you had set changes: only where each row is.
