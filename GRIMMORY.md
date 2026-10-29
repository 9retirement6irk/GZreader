# KOReader for Grimmory — Kindle Keyboard build

A trimmed KOReader for legacy Kindles (Kindle 2, DX, Kindle Keyboard / K3) that
does three things: read, pull books from a [Grimmory](https://grimmory.org)
server, and keep reading progress in sync with it. ZenOS is the default
interface.

Based on KOReader `v2026.07.1` and ZenOS `4.2.0`.

## What's in it

| Kept | Why |
| --- | --- |
| `zenos.koplugin` | The interface (Home, Library, navbar). English only. |
| `coverbrowser.koplugin` | Required by ZenOS's library views. |
| `statistics.koplugin` | Feeds ZenOS's Home reading-stats widgets. |
| `autosuspend.koplugin` | Battery. |
| `grimmory.koplugin` | New: QR pairing, library browser, downloads, native progress sync. |

Added: an English dictionary (Open English WordNet, CC BY 4.0, 11 MB).

Removed: the other 32 bundled plugins (including KOReader's own progress
sync, which this build replaces), SSH/SFTP binaries, OTA updater (it
would replace this build with stock KOReader), the 16 MB CJK fallback font,
and UI translations.

## Install

1. Jailbreak the Kindle and install KUAL (see kindlemodding.org).
2. Unzip `koreader-grimmory-kindle-legacy-*.zip` and copy the `koreader`,
   `extensions` and `launchpad` folders to the root of the Kindle's USB drive,
   merging with anything already there.
3. Eject, open KUAL → Grimmory → Start Grimmory. Or use the launchpad
   shortcuts: Shift, G, G (last book), Shift, G, L (library), Shift, G, N
   (without the Kindle framework, more memory). The old Shift, P, … shortcuts
   still work.

## Connect to Grimmory

Tap the **Grimmory** tab in the bottom bar (or Tools → Grimmory).

- **Connect with QR code** — the Kindle shows a QR code. Scan it with your
  phone; a sign-in page opens, served by the Kindle itself over your Wi‑Fi.
  Enter the Grimmory address, username and password. The Kindle logs in,
  keeps only Grimmory's login tokens (never the password), and sets up
  progress sync. The page works once, expires after 10 minutes, and stops
  when you press Back.
- **Connect by typing** — same thing using the Kindle's keyboard.

### Single sign-on (SSO / OIDC)

If Grimmory has SSO turned on, the QR page shows **Sign in with <provider>**
(and puts it first when Grimmory is SSO-only). Your phone goes to your
identity provider, signs in, and is sent back to the Kindle, which completes
the login with Grimmory. Grimmory itself needs no changes.

One-time setup: your identity provider only redirects to addresses it knows,
so add the Kindle's address as an extra redirect URI on Grimmory's client
(Authentik, Pocket ID, Authelia, Keycloak…), next to the existing
`https://<grimmory>/oauth2-callback`:

```
http://<kindle-ip>:8642/oauth2-callback
```

The exact address is shown on the QR page and under Tools → Grimmory →
Single sign-on (SSO) setup. Reserve the Kindle's IP in your router so it
stays the same. If your Grimmory admin set `ALLOWED_ORIGINS`, add
`http://<kindle-ip>:8642` there too. Some providers only accept `https`
redirect URIs for non-local addresses; check yours allows this one.

## Browsing Grimmory

The Grimmory tab lists Continue reading, Recently added, All books (A–Z),
**Libraries**, **Authors** (with author search), **Series** (books in series
order, with numbers) and Search. Audiobooks are left out. The tab next to it,
**Downloaded** (download icon), is the books on the Kindle.

## Home folder

The Grimmory folder (on a Kindle, `documents/Grimmory`, or the existing
download folder from an earlier version) is created automatically and used as
the home folder. ZenOS's setup guide no longer asks for one. Downloads go
straight into it, so they appear in the **Downloaded** tab.

## Dictionary

An English dictionary is included: **Open English WordNet 2025** (about
128,000 words and phrases with definitions, examples and synonyms; CC BY 4.0).
Inflected forms such as "books", "geese" or "ran" find their headword.
More dictionaries can be added from KOReader's dictionary settings →
Download dictionaries.

## Downloads

Books download in a background process with a progress bar, so the Kindle
never freezes. Press any key (or tap) during a download for **Stop download**,
**Continue in background** (you're told when it's ready, with an Open button)
or **Keep watching**. A download that receives nothing for 90 seconds is
stopped and reported. Books are saved to `<home folder>/Grimmory/`.

## Diagnostic log

Grimmory activity is logged to `koreader/grimmory.log` on the Kindle's USB
drive (rotates at 512 KB): every request with its status and timing, pairing,
SSO steps, downloads and sync. Passwords, tokens, SSO codes and the pairing
URL secret are never written. **Tools → Grimmory → Save diagnostic log**
copies it, plus the tail of KOReader's `crash.log`, to
`<home folder>/Grimmory/grimmory-log-<date>.txt` for sharing. Logging can be
turned off in the same menu.

## Progress sync

Sync is native: it talks to Grimmory's own reading-progress API (the one the
Grimmory web reader uses), not Grimmory's KOReader-compatible sync endpoint.
No KOReader sync account or "KOReader Sync" permission is needed.

- **Which books:** books downloaded through the Grimmory tab. They're matched
  by Grimmory book ID, not by file hash. Sideloaded books are left alone.
- **What's sent (EPUB):** the chapter (spine file), the position inside that
  chapter, and the whole-book percentage. No CFI is sent, which makes
  Grimmory's web reader resume from the chapter + in-chapter position.
  PDFs and comics send the page number; FB2/MOBI/AZW3 send the percentage.
- **From the web reader:** it saves a CFI, chapter and percentage. The Kindle
  opens that chapter and uses the percentage to pick the spot inside it, so it
  lands in the right chapter at roughly the same point (the web reader and
  KOReader measure percentages differently). Kindle-to-Kindle and
  Kindle-to-web are exact to the chapter position.
- **When:** pulled when you open a book and when the Kindle wakes; pushed every
  10 page turns (or 3 minutes), when you close the book and when it sleeps.
  Moving forward from another device is applied silently; going back asks
  first. Offline updates are queued and sent when Wi-Fi comes back.
- **Stats:** each reading session (30 s or longer) is sent to Grimmory's
  reading statistics.
- **Controls:** Tools → Grimmory → "Sync progress now" (in a book), and a
  "Sync reading progress" switch. With ZenOS's Zen Mode on, the Tools menu is
  hidden; add the "Grimmory: sync progress now" action to a ZenOS Launcher
  button or navbar tab instead.

## Rebuild the package

```sh
tools/grimmory/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
```

The branch changes only Lua, so the script overlays it onto the official
release built from the same tag rather than rebuilding the native toolchain.
