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
#   gzreader-<flavour>.zip    + packages.json      the latest release's full
#                                                  Kindle packages (kindle-legacy,
#                                                  kindle, kindlepw2, kindlehf),
#                                                  for the setup page (docs/setup)
# Each publish keeps the other files as they are.
#
#   tools/gzreader/publish-updates.sh release|beta|nook-koreader <zip> <version> [commit]
#   tools/gzreader/publish-updates.sh packages <dir with gzreader-<flavour>-<version>.zip> <version>
# REMOTE: the repository to push to (default: this GitHub repository, with
# GH_TOKEN). (Test builds before 1.26.6 read an older "beta-updates" branch;
# it's no longer written.)
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
    packages) FILE=""; JSON=packages.json
        [ -d "$ZIP" ] || { echo "packages: a folder with the release's gzreader-<flavour>-<version>.zip" >&2; exit 1; } ;;
    *) echo "release, beta, nook-koreader or packages" >&2; exit 1 ;;
esac
# the full Kindle packages (packages): flavour, as named in the release
FLAVOURS="kindle-legacy kindle kindlepw2 kindlehf"
pkg() { ls "$ZIP"/gzreader-"$1"-[0-9]*.zip 2>/dev/null | head -n 1; }
if [ "$KIND" = packages ]; then
    for fl in $FLAVOURS; do
        [ -n "$(pkg "$fl")" ] || { echo "packages: no gzreader-$fl-<version>.zip in $ZIP" >&2; exit 1; }
    done
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# the files this publish replaces (the Nook's KOReader: any tag's)
mine() {
    [ "$1" = "$FILE" ] || [ "$1" = "$JSON" ] && return 0
    [ "$KIND" = nook-koreader ] && case "$1" in koreader-kindle-legacy-*.zip) return 0 ;; esac
    if [ "$KIND" = packages ]; then
        local fl
        for fl in $FLAVOURS; do [ "$1" = "gzreader-$fl.zip" ] && return 0; done
    fi
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
    local size sha
    if [ "$KIND" = packages ]; then
        local fl list=""
        for fl in $FLAVOURS; do
            cp "$(pkg "$fl")" "$W/out/gzreader-$fl.zip"
            size=$(stat -c %s "$W/out/gzreader-$fl.zip")
            sha=$(sha256sum "$W/out/gzreader-$fl.zip" | cut -d' ' -f1)
            list="$list${list:+,}\"$fl\":{\"file\":\"gzreader-$fl.zip\",\"size\":$size,\"sha256\":\"$sha\"}"
        done
        printf '{"version":"%s","packages":{%s}}\n' "$VERSION" "$list" > "$W/out/$JSON"
    else
        cp "$ZIP" "$W/out/$FILE"
        size=$(stat -c %s "$W/out/$FILE")
        sha=$(sha256sum "$W/out/$FILE" | cut -d' ' -f1)
        printf '{"version":"%s","size":%s,"sha256":"%s","file":"%s","commit":"%s","notes":%s}\n' \
            "$VERSION" "$size" "$sha" "$FILE" "$COMMIT" "$NOTES" > "$W/out/$JSON"
    fi
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

echo "updates: $KIND $VERSION published"
