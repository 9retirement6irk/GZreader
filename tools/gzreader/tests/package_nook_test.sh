#!/bin/bash
# package-nook.sh takes GZreader from the Kindle 2/3/DX package, whichever
# layout it has: GZreader/app (since GZreader has a folder of its own) or
# koreader/ (before). The Nook keeps it in gzreader/koreader.
#   package_nook_test.sh <repo>
REPO=$(cd "${1:?repo}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
check() { if [ "$1" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $2"; fi; }
mkdir -p "$W/rt/lib"; printf '#!/bin/sh\n' > "$W/rt/busybox"; chmod +x "$W/rt/busybox"; touch "$W/rt/lib/ld-linux.so.3"
for layout in GZreader/app koreader; do
    S="$W/src-${layout%%/*}"; mkdir -p "$S/$layout/frontend/device/kindle" "$W/out-${layout%%/*}"
    echo "-- reader" > "$S/$layout/reader.lua"; echo x > "$S/$layout/luajit"; echo x > "$S/$layout/koreader.sh"
    mkdir -p "$S/extensions/gzreader"; echo '{}' > "$S/extensions/gzreader/menu.json"
    (cd "$S" && zip -qr "$W/kindle-${layout%%/*}.zip" .)
    out=$(GZ_VERSION=0.0.1 bash "$REPO/tools/gzreader/package-nook.sh" "$W/kindle-${layout%%/*}.zip" "$W/rt" "$W/out-${layout%%/*}" 2>&1 | head -1)
    list=$(unzip -l "$out" 2>/dev/null)
    echo "$list" | grep -q " gzreader/koreader/reader.lua$" && ! echo "$list" | grep -qE " gzreader/koreader/(koreader.sh|frontend/device/kindle/)$"
    check $? "a Kindle package with $layout: GZreader in gzreader/koreader, without the Kindle's parts ($out)"
    ! echo "$list" | grep -q "extensions/"
    check $? "…and nothing else from the Kindle package (KUAL's entry)"
done
echo "the Nook package: $pass passed, $fail failed"
[ "$fail" = 0 ]
