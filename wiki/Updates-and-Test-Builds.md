How GZreader updates itself, and how to try changes before they're released. Updating by hand and uninstalling: [Updating and uninstalling](Updating-and-Uninstalling).

GZreader checks the latest release of github.com/9retirement6irk/GZreader
once a day (Settings → General → Updates, or the quick panel → Updates;
the changelog is in Settings → General → Updates too).

After an update, GZreader opens a **What's new** screen once: "Updated to
v<version>" and a short point for each change (for a test build, what it
brings; for a release after a skipped one, both). Press Get Started (or the
5-way centre) to go on; the full text of each change stays in the changelog.

**Test builds.** Settings → General → Updates → **Test builds** gets what's
waiting to be tried instead of releases, over Wi‑Fi like a release (the
version then reads like `1.26.5-beta.d6819bd`). They come from the
repository's `beta` branch: every push there builds an update package
("GZreader test builds (beta)" workflow) onto the `updates` branch, as
`gzreader-beta-update.zip` with `latest-beta.json` next to the release's
`gzreader-update.zip` and `latest.json`; GZreader and the sync page look
there. Any test build other than the installed one is
offered. Turn it off to go back to releases: the next release is offered as
usual. Kindles without Wi‑Fi get them through the sync page: tick **Test
builds** there (it follows the Kindle's setting, and tells the Kindle when
you change it). Native parts (KOReader's programs, the Nook's icon app) still come
only with a full package.

The Nook 1st Edition updates the same way, from the same `gzreader-update.zip`
(Settings → General → Updates, over the Nook's Wi‑Fi): the Lua is the same
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

The download comes over HTTPS straight from GitHub (no hashing on the
Kindle); the zip must open and have a complete GZreader layout. Settings,
books, `.sdr` folders, history and the GZreader folder are never touched; if
anything fails, the previous files are put back. Then GZreader restarts.
