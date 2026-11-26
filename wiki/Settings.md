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
| **General** | **About** (GZreader's version, what it's built on, the device), Software update (test builds, changelog), Storage, Battery, Time and date, Language; **Transfer** (copy to or from another GZreader, [sync through a computer](Sync-with-a-Computer)), Setup Guide, **Performance** (Pre-size covers, Lay out new books while charging, Keep connections open). |
| **Display and light** | Screen (e-ink refresh, flashing), Brightness and warmth (schedules), **Dark mode**, the menu font and its size, accent colour, custom icons, Blur menu background; on a Nook, its colour screen or touch orientation. |
| **Sleep and wallpaper** | The sleep screen (wallpaper, its options, the sleep message), automatic sleep, then the Home background. Pictures from Immich are chosen in each of them; the Immich connection is Accounts and services → Photos. |
| **Audio** | Kindles with a speaker, headphone jack or Bluetooth: [Bluetooth](Bluetooth) first (on or off, the devices), then [read aloud](Audiobooks-and-Read-Aloud), Test audiobook playback, the headphone jack. |
| **Home and tabs** | Home (widgets, edit mode, presets), Status bar, Tab bar (which tabs, their look, the default tab), Quick panel (which tiles), Downloads tab (layout, covers, folders, books, context menu). |
| **Reader** | Appearance (status bars), Highlight / Lookup, Gestures and controls, Table of contents, Notes and footnotes, Closing a book (end of book, where the library opens). |
| **Accounts and services** | One row per service, the server it uses on the right: Books (Grimmory: your account first, who's signed in), Audiobooks (Grimmory or Plex), Music (Plex), Notes (Memos), Calendar (CalDAV), Photos (Immich), House (Home Assistant). |
| **Privacy and diagnostics** | Diagnostic logging, Send debug reports automatically, Report a problem, sending or saving the log ([Privacy and diagnostics](Privacy-and-Diagnostics)); Advanced → KOReader settings. |

## Kept simple (November 2026)

Each thing has one place, and as few taps as it takes. Where rows moved:

| Was | Now |
|---|---|
| Sleep and wallpaper → Pictures from Immich | Accounts and services → Photos (the sleep screen and Home background still choose Immich pictures) |
| Notes → Handwriting to text → AI key and service (the whole AI page again) | One row, **AI service**, that opens Accounts and services → AI |
| Sleep and wallpaper → Sleep → Wallpaper, Wallpaper options, Sleep screen message, Automatic suspend | Sleep and wallpaper → the same rows, one tap less |
| Display and light → Font, Size of menus and text | Display and light → **Menu text** (the size of everything first, then the font) |
| Notes → Pen's shortcut button, Handwriting to text (a Kindle with a pen) | General → **Pen** (Kindles without a pen keep Handwriting to text in Notes) |
| Notes → Pen's eraser removes highlights | Reader → Highlight / Lookup (it acts in books) |
| General → Transfer | General → **Transfer or reset** |
| Privacy and diagnostics → Advanced → Reset GZreader | General → Transfer or reset → Reset GZreader (last) |
| General → Performance | Privacy and diagnostics → Advanced → Performance |
| Display and light → Screen → Notifications | Privacy and diagnostics → Advanced → Notifications |
| Accounts and services → Daily paper | Home and tabs → Daily paper (it has no account and is read on Home) |
| Home and tabs → Status bar | Home and tabs → **Home's status bar** (the reader's are in Reader → Appearance) |
| Reader: Zen quick lookup, Zen highlight menu, Zen page browser, Zen end of book, Zen Presets | Quick lookup, Highlight menu, Page browser, End-of-book page, Presets |

Also: **Tab bar → Default tab** lists only the tabs in your tab bar, by
their own names (the Downloads tab was "Library" there). Accounts and
services' rows say **Not connected** on the right until their service is;
Daily paper says On or Off. The reader's status bar's custom text starts
as "GZreader".

**Every service's page starts as Books' does**: a first row saying what it's
connected to ("Connected to Immich as Will", "Connected to Claude
(claude-haiku-5-5)", or **Not connected**). The ways to connect (QR code,
typing, keys, models, Try it), disconnecting or removing the keys, and About
are on that row's own page; the page itself keeps what the service does here.
That's AI, Photos, House, Recipes and Music; Notes' Memos row reads
"Connected to Memos as …". Calendar keeps its CalDAV account and calendar
links rows.

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

## Where things moved in 1.32.x

| Was | Now |
|---|---|
| General → Wi‑Fi | Wi‑Fi (first page) |
| General → Bluetooth | Audio → Bluetooth (the first page on a Kindle with Bluetooth and nothing else for Audio) |
| General → Updates | General → Software update |
| General → Schedules | Display and light → Brightness and warmth; Night mode schedule in Dark mode |
| General → Sleep | Sleep and wallpaper |
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
