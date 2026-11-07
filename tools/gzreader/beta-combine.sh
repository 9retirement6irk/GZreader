#!/usr/bin/env bash
# The beta branch, made again from main and every open pull request labelled
# "beta" (oldest first), for test builds over Wi-Fi (gzreader-beta.yml).
# Runs in GitHub Actions (gzreader-beta-combine.yml) whenever such a pull
# request changes, is labelled or unlabelled or closed, and when main moves.
#
# A pull request that can't be merged in (a conflict beta_resolve.py can't
# settle: anything but the changelog's "next" lines and keeps.txt counts) is
# left out, and gets a comment saying which files clash (once per commit).
# Nothing is pushed when beta would be the same as it is. After a push, the
# test build, the Nook package and the tests are started on beta (a push made
# with the workflow's own token starts no workflows by itself).
#
#   GH_TOKEN=… GITHUB_REPOSITORY=owner/repo tools/gzreader/beta-combine.sh [--dry-run]
set -euo pipefail
REPO=${GITHUB_REPOSITORY:?owner/repo}
DRY=${1:-}
HERE=$(cd "$(dirname "$0")" && pwd)
RESOLVE="$HERE/beta_resolve.py"
cp "$RESOLVE" "${RUNNER_TEMP:-/tmp}/beta_resolve.py" && RESOLVE="${RUNNER_TEMP:-/tmp}/beta_resolve.py"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
git checkout -q -B beta origin/main

prs=$(gh api "repos/$REPO/pulls?state=open&per_page=100" --jq \
  '[.[] | select(any(.labels[]; .name == "beta")) | select(.head.repo.full_name == "'"$REPO"'")] | sort_by(.number) | .[] | "\(.number) \(.head.ref) \(.head.sha)"')

included=() left_out=()
while read -r n ref sha; do
    [ -n "${n:-}" ] || continue
    if git merge -q --no-ff --no-edit -m "beta: #$n ($ref)" "origin/$ref" >/dev/null 2>&1; then
        included+=("#$n"); continue
    fi
    mapfile -t clash < <(git diff --name-only --diff-filter=U)
    if [ "${#clash[@]}" -gt 0 ] && python3 "$RESOLVE" "${clash[@]}" && git add -- "${clash[@]}" \
            && git -c core.editor=true commit -q --no-edit; then
        included+=("#$n"); continue
    fi
    git merge --abort 2>/dev/null || git reset -q --hard HEAD
    left_out+=("#$n")
    echo "#$n left out: ${clash[*]:-merge failed}"
    marker="<!-- beta-combine:$sha -->"
    if [ -z "$DRY" ] && ! gh api "repos/$REPO/issues/$n/comments?per_page=100" --jq '.[].body' | grep -qF "$marker"; then
        body=$(printf '%s\nThis pull request is labelled `beta` but couldn'"'"'t be combined into the `beta` branch (with main and the other `beta` pull requests before it): these files clash:\n\n%s\n\nIt stays out of the test builds until that is settled (rebase onto main, or onto the pull request it clashes with).' \
            "$marker" "$(printf -- '- `%s`\n' "${clash[@]:-?}")")
        gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$body" >/dev/null
    fi
done <<< "$prs"

echo "beta = main + ${included[*]:-nothing}${left_out[*]:+ (left out: ${left_out[*]})}"
if git rev-parse -q --verify origin/beta >/dev/null && [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse 'origin/beta^{tree}')" ]; then
    echo "beta unchanged: nothing pushed"
    exit 0
fi
[ -n "$DRY" ] && { echo "(dry run: not pushed)"; exit 0; }
git push -q -f origin beta
for wf in gzreader-beta.yml gzreader-nook.yml gzreader-tests.yml; do
    gh workflow run "$wf" --repo "$REPO" --ref beta || echo "couldn't start $wf"
done
