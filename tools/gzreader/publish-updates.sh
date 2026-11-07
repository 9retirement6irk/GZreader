#!/usr/bin/env bash
# The "updates" branch: what the sync page and GZreader's updater read from
# raw.githubusercontent.com (a web page can't read GitHub's release downloads).
# One commit, replaced each time, holding both:
#   gzreader-update.zip       + latest.json        the latest release
#   gzreader-beta-update.zip  + latest-beta.json   the latest test build (beta)
# Each publish keeps the other kind as it is.
#
#   tools/gzreader/publish-updates.sh release|beta <update zip> <version> [commit]
# REMOTE: the repository to push to (default: this GitHub repository, with
# GH_TOKEN). LEGACY_BETA_BRANCH=1: also the old "beta-updates" branch (test
# builds before 1.26.6 read it there; until devices have one that reads
# "updates").
set -euo pipefail
KIND=${1:?release|beta}
ZIP=${2:?update zip}
VERSION=${3:?version}
COMMIT=${4:-}
REMOTE=${REMOTE:-https://x-access-token:${GH_TOKEN:?GH_TOKEN}@github.com/${GITHUB_REPOSITORY:?owner/repo}.git}
case "$KIND" in
    release) FILE=gzreader-update.zip; JSON=latest.json; KEEP="gzreader-beta-update.zip latest-beta.json" ;;
    beta) FILE=gzreader-beta-update.zip; JSON=latest-beta.json; KEEP="gzreader-update.zip latest.json" ;;
    *) echo "release or beta" >&2; exit 1 ;;
esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/out"
# the other kind's files, as they are now
if git clone -q --depth 1 -b updates "$REMOTE" "$W/old" 2>/dev/null; then
    for f in $KEEP; do [ -f "$W/old/$f" ] && cp "$W/old/$f" "$W/out/"; done
fi
cp "$ZIP" "$W/out/$FILE"
SIZE=$(stat -c %s "$W/out/$FILE")
SHA=$(sha256sum "$W/out/$FILE" | cut -d' ' -f1)
NOTES='""'
if [ "$KIND" = beta ] && git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    # what's in it: the newest commits' subjects (merges left out)
    NOTES=$(git log --no-merges -8 --format='• %s' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
fi
printf '{"version":"%s","size":%s,"sha256":"%s","file":"%s","commit":"%s","notes":%s}\n' \
    "$VERSION" "$SIZE" "$SHA" "$FILE" "$COMMIT" "$NOTES" > "$W/out/$JSON"
cat "$W/out/$JSON"
commit_push() { # <dir> <branch>
    (cd "$1" && git init -q -b "$2" && git add -A \
        && git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit -qm "GZreader updates: $KIND $VERSION" && git push -q -f "$REMOTE" "$2")
}
commit_push "$W/out" updates
if [ "$KIND" = beta ] && [ "${LEGACY_BETA_BRANCH:-}" = 1 ]; then
    mkdir "$W/legacy"
    cp "$W/out/$FILE" "$W/legacy/gzreader-update.zip"
    sed 's/"file":"gzreader-beta-update.zip"/"file":"gzreader-update.zip"/' "$W/out/$JSON" > "$W/legacy/latest.json"
    commit_push "$W/legacy" beta-updates
fi
echo "updates: $KIND $VERSION published"
