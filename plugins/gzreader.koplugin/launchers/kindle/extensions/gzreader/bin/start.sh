#!/bin/sh
# GZreader's KUAL entry: start GZreader from its own folder (GZreader/app, beside
# KOReader).
APP=/mnt/us/GZreader/app
exec "$APP/koreader.sh" "$@"
