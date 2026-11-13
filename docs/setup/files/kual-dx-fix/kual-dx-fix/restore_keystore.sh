#!/bin/sh
# Undo: unlocks and removes the fix keystore (restores the backup if there is one).
LOG=/mnt/us/kual-dx-fix/install.log
D=/var/local/java/keystore
{
  echo "=== restore $(date) ==="
  chattr -i "$D/developer.keystore" 2>/dev/null
  if [ -f /mnt/us/kual-dx-fix/developer.keystore.backup ]; then
    cp /mnt/us/kual-dx-fix/developer.keystore.backup "$D/developer.keystore" && echo "restored backup"
  else
    rm -f "$D/developer.keystore" && echo "no backup; removed fix keystore"
  fi
  sync
} >> "$LOG" 2>&1
