#!/bin/bash
# CI: install Ubuntu packages on a GitHub runner, also when Ubuntu's own
# servers can't be reached.
#
#   bash tools/gzreader/ci-apt.sh luajit rsync ...
#
# On 2026-11-11 GitHub's runners couldn't resolve azure.archive.ubuntu.com
# or archive.ubuntu.com for hours ("Temporary failure resolving"): every
# apt-get install failed, and with it every CI run, before any test ran.
#
# 1. If the runner's Ubuntu servers resolve: apt-get update + install with
#    the runner's own sources, as before.
# 2. If they don't, or that install fails: Ubuntu's sources are set aside
#    and each mirror in GZ_APT_MIRRORS (outside ubuntu.com) is tried in
#    turn. The packages are still checked against Ubuntu's own signing key
#    (Signed-By), so a mirror can't hand over anything Ubuntu didn't sign.
#    Other sources on the runner (Microsoft's, etc.) are left as they are.
#
# Whatever installs afterwards (playwright install-deps) uses the same
# sources. Prints "::notice::" naming the mirror when one was needed.
#
# For the tests (ci_apt_test.py) every outside thing can be swapped:
# GZ_APT_SUDO, GZ_APT_GET, GZ_APT_RESOLVE, GZ_APT_ETC, GZ_APT_KEYRING,
# GZ_APT_CODENAME, GZ_APT_MIRRORS.
set -u

SUDO=${GZ_APT_SUDO-sudo}
APT=${GZ_APT_GET:-apt-get}
RESOLVE=${GZ_APT_RESOLVE:-"timeout 15 getent ahosts"}
ETC=${GZ_APT_ETC:-/etc/apt}
KEYRING=${GZ_APT_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}
CODENAME=${GZ_APT_CODENAME:-$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-noble}")}
MIRRORS=${GZ_APT_MIRRORS:-"https://mirrors.edge.kernel.org/ubuntu/ https://mirrors.mit.edu/ubuntu/ https://mirror.math.princeton.edu/pub/ubuntu/"}

[ $# -gt 0 ] || { echo "ci-apt.sh: no packages named" >&2; exit 2; }

# Ubuntu's own source files: the ones naming ubuntu.com or the runner's mirror list
ubuntu_sources() {
  local f
  for f in "$ETC/sources.list" "$ETC"/sources.list.d/*.list "$ETC"/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    grep -v '^[[:space:]]*#' "$f" | grep -qE 'ubuntu\.com|apt-mirrors\.txt' && echo "$f"
  done
}

# The host names in those files (and in the mirror list they point to)
ubuntu_hosts() {
  local files
  files=$(ubuntu_sources)
  [ -f "$ETC/apt-mirrors.txt" ] && files="$files $ETC/apt-mirrors.txt"
  [ -n "$files" ] || return 0
  # shellcheck disable=SC2086
  grep -v '^[[:space:]]*#' $files 2>/dev/null | grep -oE 'https?://[^/[:space:]]+' | sed -E 's#https?://##' | sort -u
}

resolves() {
  local h any=1
  for h in $(ubuntu_hosts); do
    if $RESOLVE "$h" >/dev/null 2>&1; then echo "ci-apt: $h resolves"; any=0; else echo "ci-apt: $h does not resolve"; fi
  done
  return $any
}

install() {
  $SUDO $APT -o Acquire::Retries=2 update -qq
  $SUDO $APT -o Acquire::Retries=2 install -y -qq "$@"
}

if resolves; then
  if install "$@"; then exit 0; fi
  echo "ci-apt: installing from the runner's own sources failed; trying other mirrors"
else
  echo "ci-apt: Ubuntu's servers can't be resolved; trying other mirrors"
fi

# Set Ubuntu's sources aside (renamed: apt reads only .list and .sources)
for f in $(ubuntu_sources); do
  $SUDO mv "$f" "$f.gz-aside"
done

for m in $MIRRORS; do
  host=$(printf '%s\n' "$m" | sed -E 's#https?://##; s#/.*##')
  if ! $RESOLVE "$host" >/dev/null 2>&1; then
    echo "ci-apt: $host does not resolve either"
    continue
  fi
  printf '%s\n' \
    "Types: deb" \
    "URIs: $m" \
    "Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security" \
    "Components: main restricted universe multiverse" \
    "Signed-By: $KEYRING" \
    | $SUDO tee "$ETC/sources.list.d/gz-mirror.sources" >/dev/null
  if install "$@"; then
    echo "::notice::Ubuntu packages came from $m (Ubuntu's own servers couldn't be reached)"
    exit 0
  fi
  echo "ci-apt: $m failed"
done

echo "::error::Ubuntu packages couldn't be installed from Ubuntu's servers or any mirror ($MIRRORS)"
exit 1
