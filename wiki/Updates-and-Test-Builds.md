How GZreader updates itself, and how to try changes before they're released. Updating by hand and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).

GZreader checks the latest release of github.com/9retirement6irk/GZreader
once a day (Settings → General → Software update, or the quick panel → Updates;
the changelog is in Settings → General → Software update too). When a check has
found a newer version, the quick panel's **Updates** tile reads **Update
available** and is drawn white on black (also after a restart, until it's
installed); tap it to see the update and install it.

**Only from GitHub.** Every update check and download is made over HTTPS
to GitHub's own addresses, and GZreader checks GitHub's certificate first
(against KOReader's list of certificate authorities, `data/ca-bundle.crt`):
on a Wi‑Fi network where someone else answers in GitHub's place, the check
says the certificate isn't trusted and nothing is downloaded. A Nook or DX
whose clock has run back to 2000 or 1970 can still check (a certificate's
dates are only ignored while the clock is before 2026).

After an update, GZreader opens a **What's new** screen once: "Updated to
v<version>" and a short point for each change (for a test build, what it
brings; for a release after a skipped one, both). Press Get Started (or the
5-way centre) to go on; the full text of each change stays in the changelog.

**Test builds.** Settings → General → Software update → **Test builds** gets what's
waiting to be tried instead of releases, over Wi‑Fi like a release (the
version then reads like `1.26.5-beta.d6819bd`). They come from the
repository's `beta` branch: every push there builds an update package
("GZreader test builds (beta)" workflow) onto the `updates` branch, as
`gzreader-beta-update.zip` with `latest-beta.json` next to the release's
`gzreader-update.zip` and `latest.json`; GZreader and the sync page look
there. Any test build other than the installed one is
offered. Turn it off to go back to releases: the next release is offered as
usual, and so is the release a test build was made towards (1.27.0 counts
as newer than 1.27.0-beta.5995ce3, on the Kindle and on the sync page).
Kindles without Wi‑Fi get them through the sync page: tick **Test
builds** there (it follows the Kindle's setting, and tells the Kindle when
you change it). Native parts (KOReader's programs, the Nook's icon app) still come
only with a full package.

The Nook 1st Edition updates the same way, from the same `gzreader-update.zip`
(Settings → General → Software update, over the Nook's Wi‑Fi): the Lua is the same
on every device, and the Nook's own programs (built without floating point)
stay as installed. Its start script (`/data/gzreader/gzreader.sh`) comes
in the update too and takes effect the next time GZreader starts. A new
KOReader version still needs the full Nook package installed again.
GZreader shares the Nook's 242 MB internal disk with Android, which can be
full. When there isn't room there for an update (the download and what it
unpacks to, about three times its size), it's downloaded and unpacked on
the microSD card (`GZreader/.gzreader-update`, removed afterwards) and
copied in part by part, with a copy of each part kept on the card to put
back if one fails.

A book open when the update is installed is closed first, as the Home
button closes it (its page, bookmarks and highlights written to its file,
its place sent to Grimmory), and then GZreader restarts at Home. Until the
fix listed under "next" in the changelog, the restart left the book
without saving it: it reopened at an earlier page.

The download comes over HTTPS straight from GitHub (no hashing on the
Kindle); the zip must open and have a complete GZreader layout. Settings,
books, `.sdr` folders, history and the GZreader folder are never touched; if
anything fails, the previous files are put back. Then GZreader restarts.
The Kindle doesn't go to sleep while an update downloads and installs
(the download window takes every tap, so the Kindle would otherwise think
nobody was there).
