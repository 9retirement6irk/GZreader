#!/bin/sh

directory=$1
size=$2
framebuffer=$3
fbink=$4
attempt=0
reason=timeout
trap 'echo "ZenOS: [kindle_restore_screen] stopped reason=$reason polls=$attempt"; rm -f "$directory/screen" "$directory/blank" "$directory/current"; rmdir "$directory"' 0
trap 'reason=signal; exit 0' HUP INT TERM
echo "ZenOS: [kindle_restore_screen] started size=$size"

# shortcut: limit monitoring to 240 polls; extend only if device logs show slower restores.
content_polls=0
next_refresh=0
while [ "$attempt" -lt 240 ]; do
    reason=sleep_failed
    usleep 250000 || break
    attempt=$((attempt + 1))
    reason=framebuffer_read
    head -c "$size" "$framebuffer" > "$directory/current" || break
    [ "$(wc -c < "$directory/current")" -eq "$size" ] || break
    if cmp -s "$directory/current" "$directory/screen"; then
        content_polls=0
    elif cmp -s "$directory/current" "$directory/blank"; then
        content_polls=0
        # Recheck before writing so a returning UI gets priority.
        if ! head -c "$size" "$framebuffer" | cmp -s - "$directory/blank"; then
            reason=timeout
            continue
        fi
        reason=framebuffer_write
        cat "$directory/screen" > "$framebuffer" || break
        next_refresh=0
    else
        content_polls=$((content_polls + 1))
    fi
    # A panel clear need not change framebuffer memory; keep the displayed image refreshed.
    if [ "$attempt" -ge "$next_refresh" ] || [ "$content_polls" -eq 1 ] || [ "$content_polls" -ge 8 ]; then
        reason=refresh_failed
        "$fbink" -q -w -W GC16 --refresh || break
        next_refresh=$((attempt + 4))
    fi
    # Startup may paint a temporary image before clearing the display again.
    if [ "$content_polls" -ge 8 ]; then
        reason=kindle_content
        break
    fi
    reason=timeout
done
