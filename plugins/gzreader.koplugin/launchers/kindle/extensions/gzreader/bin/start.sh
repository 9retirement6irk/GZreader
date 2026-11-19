#!/bin/sh
# GZreader's KUAL entry: start GZreader from its own folder (GZreader/app, beside
# KOReader). Before 1.35 GZreader was in KOReader's place (koreader/), where it
# stays until its first start moves it (gzreader_migrate.lua).
APP=/mnt/us/GZreader/app
[ -f "$APP/koreader.sh" ] || APP=/mnt/us/koreader
exec "$APP/koreader.sh" "$@"
