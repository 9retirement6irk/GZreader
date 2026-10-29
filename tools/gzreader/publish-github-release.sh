#!/usr/bin/env bash
# Publish a GZreader release on GitHub so Kindles can update themselves.
#
#   tools/gzreader/package-kindle-legacy.sh koreader-kindle-legacy-v2026.07.1.zip out/
#   tools/gzreader/publish-github-release.sh out/
#
# Needs the GitHub CLI (gh) logged in with write access to the repository.
# The tag is "v" + GZREADER_VERSION; bump that file for every release.
# Kindles look at the *latest* release (not drafts or pre-releases) and
# download its "gzreader-update.zip" asset.
set -euo pipefail
OUT_DIR=${1:?folder with the packages}
REPO_SLUG=${GZREADER_REPO:-9retirement6irk/GZreader}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VERSION=$(tr -d ' \n' < "$ROOT/GZREADER_VERSION")
FULL="$OUT_DIR/gzreader-kindle-legacy-$VERSION.zip"
UPD="$OUT_DIR/gzreader-update.zip"
for f in "$FULL" "$UPD"; do [ -f "$f" ] || { echo "missing $f (run package-kindle-legacy.sh first)" >&2; exit 1; }; done
NOTES=${NOTES:-"GZreader $VERSION. Install: unzip gzreader-kindle-legacy-$VERSION.zip to the Kindle's USB drive. Existing installs update from Settings → Updates."}
gh release create "v$VERSION" "$FULL" "$UPD" --repo "$REPO_SLUG" --title "GZreader $VERSION" --notes "$NOTES"
