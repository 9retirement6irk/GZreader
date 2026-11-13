#!/bin/sh
# Installs the KUAL DX fix developer keystore and locks it so the Kindle can't wipe it.
LOG=/mnt/us/kual-dx-fix/install.log
D=/var/local/java/keystore
{
  echo "=== $(date) ==="
  echo "before:"; ls -l "$D" 2>&1
  mkdir -p "$D"
  chattr -i "$D/developer.keystore" 2>/dev/null
  if [ -f "$D/developer.keystore" ] && [ ! -f /mnt/us/kual-dx-fix/developer.keystore.backup ] && ! cmp -s "$D/developer.keystore" /mnt/us/kual-dx-fix/developer.keystore; then
    cp "$D/developer.keystore" /mnt/us/kual-dx-fix/developer.keystore.backup && echo "backed up old keystore"
  fi
  cp /mnt/us/kual-dx-fix/developer.keystore "$D/developer.keystore" && chmod 644 "$D/developer.keystore" && echo "installed keystore OK"
  chattr +i "$D/developer.keystore" && echo "locked (immutable) OK"
  sync
  echo "after:"; ls -l "$D" 2>&1; lsattr "$D/developer.keystore" 2>&1
} >> "$LOG" 2>&1
