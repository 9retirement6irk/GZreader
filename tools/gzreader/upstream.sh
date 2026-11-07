#!/usr/bin/env bash
# GZreader's upstreams: KOReader (the whole tree; GZreader overlays its Lua on
# KOReader's official Kindle packages of the same tag) and ZenOS
# (plugins/zenos.koplugin). Which versions GZreader is on: tools/gzreader/UPSTREAM.
#
#   upstream.sh current <koreader|zenos>      the version GZreader is on
#   upstream.sh latest  <koreader|zenos> [--pre]
#       the newest usable release: KOReader's newest tag that has Kindle
#       packages; ZenOS's newest vX.Y.Z (--pre: or its newest alpha / beta)
#   upstream.sh merge   <koreader|zenos> <new tag>
#       merges what changed upstream between the current and the new tag into
#       this working tree (three-way: upstream old → upstream new, onto
#       GZreader's files), updates UPSTREAM (and the release workflow's
#       KOREADER_TAG), and writes a report (UPSTREAM_REPORT, default
#       ./upstream-report.md). Exit 0: merged cleanly; 1: conflicts, left in
#       the files with <<<<<<< markers and listed in the report.
#
# What GZreader removed from upstream stays removed (KOReader's other plugins,
# its CI, ZenOS's non-English translations): upstream changes to those are
# skipped and listed. Needs: git, curl, rsync.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
UPFILE="$REPO/tools/gzreader/UPSTREAM"
REPORT=${UPSTREAM_REPORT:-"$PWD/upstream-report.md"}
KO_URL=https://github.com/koreader/koreader.git
ZEN_URL=https://github.com/xZenLabs/zen-os.git
KEEP_PLUGINS="autosuspend coverbrowser statistics"

current() { awk -v c="$1" '$1 == c { print $2 }' "$UPFILE"; }

tags() { git ls-remote --tags --refs "$1" | sed 's|.*refs/tags/||' | sort -V; }

hasKindlePackages() {
    curl -fsIL -o /dev/null "https://github.com/koreader/koreader/releases/download/$1/koreader-kindle-legacy-$1.zip"
}

latest() {
    case "$1" in
    koreader)
        # (newest first; a tag without Kindle packages, e.g. a nightly rebuild, is skipped)
        for t in $(tags "$KO_URL" | grep -E '^v[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$' | sort -rV); do
            if hasKindlePackages "$t"; then echo "$t"; return; fi
            echo "  ($t has no Kindle packages: skipped)" >&2
        done ;;
    zenos)
        if [ "${2:-}" = "--pre" ]; then
            tags "$ZEN_URL" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)[0-9]*)?$' | sort -V | tail -1
        else
            tags "$ZEN_URL" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
        fi ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
    esac
}

# export <url> <tag> <dir>: the upstream tree at a tag
export_tree() {
    local up="$WORK/up"
    [ -d "$up" ] || git init -q "$up"
    if ! git -C "$up" fetch -q --depth 1 "$1" "refs/tags/$2:refs/tags/$2" 2>/dev/null; then
        # (not a tag: a branch, e.g. master, to preview what's coming)
        git -C "$up" fetch -q --depth 1 "$1" "$2"
        git -C "$up" tag -f "$2" FETCH_HEAD >/dev/null
    fi
    mkdir -p "$3"
    git -C "$up" archive "$2" | tar -x -C "$3"
}

# trim <component> <dir>: drop what GZreader doesn't take from upstream
trim() {
    local d=$2
    if [ "$1" = koreader ]; then
        rm -rf "$d/.github" "$d/README.md" # (GZreader's own CI and README)
        for p in "$d"/plugins/*.koplugin; do
            [ -e "$p" ] || continue
            local n; n=$(basename "$p" .koplugin)
            case " $KEEP_PLUGINS " in *" $n "*) ;; *) rm -rf "$p" ;; esac
        done
    else
        rm -rf "$d"/.github "$d"/.gitignore "$d"/.env.example "$d"/.luacheckrc "$d"/CODE_OF_CONDUCT.md \
            "$d"/CONTRIBUTING.md "$d"/README.md "$d"/SECURITY.md "$d"/_config.yml "$d"/_includes "$d"/build.sh \
            "$d"/docs "$d"/luacheck.sh "$d"/spec "$d"/translation_utils.py
        find "$d/locales" -name '*.po' ! -name 'en.po' -delete 2>/dev/null || true
    fi
}

merge() {
    local comp=$1 new=$2 old url sub
    old=$(current "$comp")
    if [ "$comp" = koreader ]; then url=$KO_URL; sub=.; else url=$ZEN_URL; sub=plugins/zenos.koplugin; fi
    [ "$old" != "$new" ] || { echo "$comp is already $new"; return 0; }
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' RETURN
    local M="$WORK/m"
    git init -q -b upstream-old "$M"
    git -C "$M" config user.email gzreader@localhost
    git -C "$M" config user.name "GZreader upstream merge"
    # 1. upstream, old
    export_tree "$url" "$old" "$M"
    trim "$comp" "$M"
    git -C "$M" add -A -f && git -C "$M" commit -q --allow-empty -m "$comp $old"
    # 2. upstream, new
    git -C "$M" checkout -q -b upstream-new
    git -C "$M" rm -rqf . && git -C "$M" clean -qfdx
    export_tree "$url" "$new" "$M"
    trim "$comp" "$M"
    git -C "$M" add -A -f && git -C "$M" commit -q --allow-empty -m "$comp $new"
    # 3. GZreader (committed state) on the old one
    git -C "$M" checkout -q -b gzreader upstream-old
    git -C "$M" rm -rqf . && git -C "$M" clean -qfdx
    git -C "$REPO" archive HEAD "$sub" | tar -x -C "$M" --strip-components=$([ "$sub" = . ] && echo 0 || echo 2)
    git -C "$M" add -A -f && git -C "$M" commit -q --allow-empty -m "GZreader"
    local ours; ours=$(git -C "$M" rev-parse HEAD)
    local changed; changed=$(git -C "$M" diff --name-only upstream-old upstream-new | wc -l)

    git -C "$M" merge -q --no-edit --no-ff upstream-new >/dev/null 2>&1 || true
    # what GZreader removed stays removed; what upstream removed and GZreader changed stays
    local skipped=() kept=() conflicts=()
    while IFS= read -r line; do
        local st=${line:0:2} f=${line:3}
        case "$st" in
            UD|DU) git -C "$M" rm -qf -- "$f"; skipped+=("$f") ;; # (one side deleted it: sorted out below)
            UU|AA|AU|UA) conflicts+=("$f") ;;
        esac
    done < <(git -C "$M" status --porcelain)
    # (GZreader removed it: stays removed; upstream removed a file GZreader changed: GZreader's stays)
    for f in "${skipped[@]:+${skipped[@]}}"; do
        if git -C "$M" cat-file -e "$ours:$f" 2>/dev/null && ! git -C "$M" cat-file -e "upstream-new:$f" 2>/dev/null; then
            git -C "$M" show "$ours:$f" > "$M/$f"; git -C "$M" add -- "$f"; kept+=("$f")
        fi
    done
    git -C "$M" add -A -f
    # apply merged − GZreader's to this working tree (conflict markers included)
    local dir=(); [ "$sub" = . ] || dir=(--directory="$sub")
    git -C "$M" diff --binary "$ours" -- . > "$WORK/merge.patch"
    if [ -s "$WORK/merge.patch" ]; then
        (cd "$REPO" && git apply --binary "${dir[@]}" --whitespace=nowarn "$WORK/merge.patch")
    fi

    # versions
    sed -i "s/^$comp .*/$comp $new/" "$UPFILE"
    if [ "$comp" = koreader ]; then
        # (the Nook 1st Edition build too: its update package comes from the release's)
        sed -i "s/KOREADER_TAG: .*/KOREADER_TAG: $new/" "$REPO/.github/workflows/gzreader-release.yml" \
            "$REPO/.github/workflows/gzreader-nook.yml"
    fi

    local pre=""; [ "$sub" = . ] || pre="$sub/"
    {
        echo "## $comp $old → $new"
        echo
        echo "Upstream changed $changed files between the two tags."
        echo
        if [ ${#conflicts[@]} -eq 0 ]; then
            echo "**Merged cleanly.**"
        else
            echo "**${#conflicts[@]} conflicts** (left in the files with \`<<<<<<<\` markers):"
            echo
            for f in "${conflicts[@]}"; do echo "- \`${pre}$f\`"; done
        fi
        local really_skipped=()
        for f in "${skipped[@]:+${skipped[@]}}"; do
            case " ${kept[*]:-} " in *" $f "*) ;; *) really_skipped+=("$f") ;; esac
        done
        if [ ${#really_skipped[@]} -gt 0 ]; then
            echo
            echo "<details><summary>${#really_skipped[@]} upstream changes to files GZreader removed (skipped)</summary>"
            echo
            for f in "${really_skipped[@]}"; do echo "- \`${pre}$f\`"; done
            echo "</details>"
        fi
        if [ ${#kept[@]} -gt 0 ]; then
            echo
            echo "Upstream deleted files GZreader changed (GZreader's kept):"
            for f in "${kept[@]}"; do echo "- \`${pre}$f\`"; done
        fi
        echo
    } >> "$REPORT"
    [ ${#conflicts[@]} -eq 0 ]
}

case "${1:-}" in
    current) current "$2" ;;
    latest) latest "$2" "${3:-}" ;;
    merge) merge "$2" "$3" ;;
    *) sed -n '2,19p' "$0"; exit 2 ;;
esac
