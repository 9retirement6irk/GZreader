#!/usr/bin/env bash
# The "updates" branch: what the sync page and GZreader's updater read from
# raw.githubusercontent.com (a web page can't read GitHub's release downloads).
# One commit, replaced each time, holding:
#   gzreader-update.zip       + latest.json        the latest release
#   gzreader-beta-update.zip  + latest-beta.json   the latest test build (beta)
#   koreader-kindle-legacy-<tag>.zip + nook-koreader.json
#                                                  KOReader's programs built
#                                                  for the Nook 1st Edition (no
#                                                  VFP), for trying elsewhere;
#                                                  devices don't read it
# Each publish keeps the other files as they are.
#
#   tools/gzreader/publish-updates.sh release|beta|nook-koreader <zip> <version> [commit]
# REMOTE: the repository to push to (default: this GitHub repository, with
# GH_TOKEN). LEGACY_BETA_BRANCH=1: also the old "beta-updates" branch (test
# builds before 1.26.6 read it there; until devices have one that reads
# "updates").
# Two workflows can publish at once (a push to beta starts both the test build
# and the Nook build): the push only replaces the commit this run started from,
# and if another run got there first, it starts again from that one.
set -euo pipefail
KIND=${1:?release|beta|nook-koreader}
ZIP=${2:?zip}
VERSION=${3:?version}
COMMIT=${4:-}
REMOTE=${REMOTE:-https://x-access-token:${GH_TOKEN:?GH_TOKEN}@github.com/${GITHUB_REPOSITORY:?owner/repo}.git}
case "$KIND" in
    release) FILE=gzreader-update.zip; JSON=latest.json ;;
    beta) FILE=gzreader-beta-update.zip; JSON=latest-beta.json ;;
    nook-koreader) FILE=$(basename "$ZIP"); JSON=nook-koreader.json
        case "$FILE" in koreader-kindle-legacy-*.zip) ;; *) echo "nook-koreader: koreader-kindle-legacy-<tag>.zip" >&2; exit 1 ;; esac ;;
    *) echo "release, beta or nook-koreader" >&2; exit 1 ;;
esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# the files this publish replaces (the Nook's KOReader: any tag's)
mine() {
    [ "$1" = "$FILE" ] || [ "$1" = "$JSON" ] && return 0
    [ "$KIND" = nook-koreader ] && case "$1" in koreader-kindle-legacy-*.zip) return 0 ;; esac
    return 1
}

NOTES='""'
if [ "$KIND" = beta ] && git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    # what's in it: the newest commits' subjects (merges left out)
    NOTES=$(git log --no-merges -8 --format='• %s' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
fi

publish() {
    rm -rf "$W/old" "$W/out"
    mkdir "$W/out"
    local base=""
    # the other files, as they are now
    if git clone -q --depth 1 -b updates "$REMOTE" "$W/old" 2>/dev/null; then
        base=$(git -C "$W/old" rev-parse HEAD)
        local f
        for f in $(git -C "$W/old" ls-files); do
            mine "$f" || cp "$W/old/$f" "$W/out/"
        done
    fi
    cp "$ZIP" "$W/out/$FILE"
    local size sha
    size=$(stat -c %s "$W/out/$FILE")
    sha=$(sha256sum "$W/out/$FILE" | cut -d' ' -f1)
    printf '{"version":"%s","size":%s,"sha256":"%s","file":"%s","commit":"%s","notes":%s}\n' \
        "$VERSION" "$size" "$sha" "$FILE" "$COMMIT" "$NOTES" > "$W/out/$JSON"
    cat "$W/out/$JSON"
    (cd "$W/out" && git init -q -b updates && git add -A \
        && git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit -qm "GZreader updates: $KIND $VERSION" \
        && git push -q --force-with-lease="updates:$base" "$REMOTE" updates)
}

tries=0
until publish; do
    tries=$((tries + 1))
    if [ "$tries" -ge 5 ]; then echo "updates: couldn't publish (the branch kept changing)" >&2; exit 1; fi
    echo "updates: changed meanwhile, again with the new files" >&2
    sleep $((tries * 5))
done

if [ "$KIND" = beta ] && [ "${LEGACY_BETA_BRANCH:-}" = 1 ]; then
    mkdir "$W/legacy"
    cp "$W/out/$FILE" "$W/legacy/gzreader-update.zip"
    sed 's/"file":"gzreader-beta-update.zip"/"file":"gzreader-update.zip"/' "$W/out/$JSON" > "$W/legacy/latest.json"
    (cd "$W/legacy" && git init -q -b beta-updates && git add -A \
        && git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            commit -qm "GZreader updates: $KIND $VERSION" && git push -q -f "$REMOTE" beta-updates)
fi
echo "updates: $KIND $VERSION published"
