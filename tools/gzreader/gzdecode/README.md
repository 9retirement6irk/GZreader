# gzdecode

GZreader's audio decoder for Kindles whose only sound output is Amazon's
`mixersink` (Kindles with Bluetooth: Scribe, Paperwhite 5 and newer…). Those
have GStreamer 1.20 but no MP3 or AAC decoder: Audible's `audiblesrc` only
opens Audible's own files, and `decodebin` reports "Missing decoder: MPEG-4
AAC" (checked on a Scribe, firmware 5.20.2).

`gzdecode mp3|aac` reads MP3 or ADTS AAC on stdin and writes raw PCM on
stdout: S16LE, 2 channels, 44100 Hz always (mono is doubled, other rates
resampled linearly), so `gzreader_audioengine.lua` can always end its pipeline with

    … | gzdecode mp3 | gst-launch-1.0 -q fdsrc fd=0 ! rawaudioparse use-sink-caps=false
        format=pcm pcm-format=s16le sample-rate=44100 num-channels=2
        ! audioconvert ! audioresample ! mixersink

The built program is `plugins/gzreader.koplugin/bin/gzdecode-armhf` (static,
musl, ARMv7 hard float, ~280 KB). It ships in every package and update; only
Bluetooth Kindles run it.

## Sources and licences

- `gzdecode.c`: GZreader (AGPL-3.0).
- `minimp3/`: [minimp3](https://github.com/lieff/minimp3) at a2ad968, CC0 (public domain).
- `faad2/`: [FAAD2](https://github.com/knik0/faad2) 2.11.4 at a335040 (libfaad and its headers), GPL-2.0-or-later.

## Rebuilding

    pip install ziglang            # Zig 0.17 used for the committed build
    CPU=cortex_a7 tools/gzreader/gzdecode/build.sh arm-linux-musleabihf plugins/gzreader.koplugin/bin/gzdecode-armhf

For testing on a PC: `build.sh x86_64-linux-musl /tmp/gzdecode`, then e.g.
`/tmp/gzdecode mp3 < a.mp3 > a.raw` and compare with
`ffmpeg -i a.mp3 -f s16le -ac 2 -ar 44100 b.raw`.

Checked on a Scribe (2026-11-16): GZreader's MP3 and AAC test tunes, and
three MP3s joined, played through Bluetooth; decoding took about 1.5% of
real time.
