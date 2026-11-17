/*
 * gzdecode: GZreader's audio decoder for Kindles whose only sound output is
 * Amazon's mixersink (Bluetooth Kindles: Scribe, Paperwhite 5 and newer…),
 * which have no MP3 or AAC decoder of their own.
 *
 *   gzdecode mp3 < file.mp3 | gst-launch-1.0 fdsrc fd=0 ! rawaudioparse … ! mixersink
 *   gzdecode aac < chunks.aac | …        (ADTS AAC, as GZreader stores M4B audiobooks)
 *
 * Reads the compressed stream on stdin and writes raw PCM on stdout, always
 * signed 16-bit little-endian, 2 channels, 44100 Hz (mono is doubled, other
 * rates resampled), so the pipeline after it never changes. Starting mid-file
 * is the caller's business: MP3 and ADTS both resynchronise on the next frame.
 *
 * MP3: minimp3 (CC0, https://github.com/lieff/minimp3).
 * AAC: FAAD2 (GPL-2.0-or-later, https://github.com/knik0/faad2).
 * This file: AGPL-3.0, as GZreader.
 */
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_NO_SIMD
#include "minimp3.h"
#include "neaacdec.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define OUT_RATE 44100
#define IN_BUF (64 * 1024)

/* ------------------------------------------------------------------ output */

static short out_buf[8192 * 2];
static int out_n; /* frames in out_buf */

static void flush_out(void) {
    if (out_n == 0) return;
    size_t want = (size_t)out_n * 4, done = 0;
    const char *p = (const char *)out_buf;
    while (done < want) {
        ssize_t w = write(1, p + done, want - done);
        if (w <= 0) exit(0); /* the player is gone */
        done += (size_t)w;
    }
    out_n = 0;
}

static void put(short l, short r) {
    out_buf[out_n * 2] = l;
    out_buf[out_n * 2 + 1] = r;
    if (++out_n == 8192) flush_out();
}

/* Linear resampler to OUT_RATE, keeping its place across blocks. */
static int rs_rate;
static double rs_pos;            /* position of the next output frame, in input frames after rs_prev */
static short rs_prev_l, rs_prev_r;
static int rs_have_prev;

static void emit(const short *pcm, int frames, int channels, int rate) {
    if (frames <= 0 || channels <= 0 || rate <= 0) return;
    if (rate != rs_rate) { rs_rate = rate; rs_pos = 0; rs_have_prev = 0; }
    for (int i = 0; i < frames; i++) {
        short l = pcm[i * channels];
        short r = channels > 1 ? pcm[i * channels + 1] : l;
        if (rate == OUT_RATE) { put(l, r); continue; }
        if (!rs_have_prev) { rs_prev_l = l; rs_prev_r = r; rs_have_prev = 1; continue; }
        /* output frames between rs_prev (at 0) and this one (at 1) */
        double step = (double)rate / OUT_RATE;
        while (rs_pos < 1.0) {
            double f = rs_pos;
            put((short)(rs_prev_l + (l - rs_prev_l) * f), (short)(rs_prev_r + (r - rs_prev_r) * f));
            rs_pos += step;
        }
        rs_pos -= 1.0;
        rs_prev_l = l; rs_prev_r = r;
    }
}

/* ------------------------------------------------------------------ input */

static unsigned char in_buf[IN_BUF];
static size_t in_len;
static int in_eof;

static void fill(void) {
    while (!in_eof && in_len < IN_BUF) {
        ssize_t r = read(0, in_buf + in_len, IN_BUF - in_len);
        if (r <= 0) { in_eof = 1; break; }
        in_len += (size_t)r;
    }
}

static void consume(size_t n) {
    if (n > in_len) n = in_len;
    memmove(in_buf, in_buf + n, in_len - n);
    in_len -= n;
}

/* ------------------------------------------------------------------ MP3 */

static int decode_mp3(void) {
    static mp3dec_t dec;
    static short pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
    mp3dec_frame_info_t info;
    mp3dec_init(&dec);
    long frames = 0;
    for (;;) {
        fill();
        if (in_len == 0) break;
        int n = mp3dec_decode_frame(&dec, in_buf, (int)in_len, pcm, &info);
        if (info.frame_bytes == 0) {
            if (in_eof) break;
            /* no frame in a full buffer: drop most of it and look again */
            consume(in_len > 4096 ? in_len - 4096 : in_len);
            continue;
        }
        consume((size_t)info.frame_bytes);
        if (n > 0) { emit(pcm, n, info.channels, info.hz); frames++; }
    }
    flush_out();
    return frames > 0 ? 0 : 2;
}

/* ------------------------------------------------------------------ AAC (ADTS) */

static size_t adts_sync(void) {
    for (size_t i = 0; i + 1 < in_len; i++)
        if (in_buf[i] == 0xFF && (in_buf[i + 1] & 0xF6) == 0xF0) return i;
    return in_len > 0 ? in_len - 1 : 0;
}

static NeAACDecConfigurationPtr cfg_copy(NeAACDecHandle h) {
    NeAACDecConfigurationPtr cfg = NeAACDecGetCurrentConfiguration(h);
    cfg->outputFormat = FAAD_FMT_16BIT;
    cfg->downMatrix = 1; /* 5.1 → stereo */
    return cfg;
}

static int decode_aac(void) {
    NeAACDecHandle h = NeAACDecOpen();
    NeAACDecSetConfiguration(h, cfg_copy(h));
    int cur_key = -1;
    unsigned long rate = 0;
    unsigned char ch = 0;
    long frames = 0;
    int ready = 0;
    for (;;) {
        fill();
        if (in_len < 7) break;
        if (!ready) {
            consume(adts_sync());
            if (in_len < 7) { if (in_eof) break; continue; }
            long used = NeAACDecInit(h, in_buf, (unsigned long)in_len, &rate, &ch);
            if (used < 0) { consume(1); continue; }
            consume((size_t)used);
            ready = 1;
            continue;
        }
        /* the stream's format changed (another file joined on): start the decoder again */
        if (in_buf[0] == 0xFF && (in_buf[1] & 0xF6) == 0xF0) {
            int key = ((in_buf[2] >> 2) & 0x0F) << 3 | ((in_buf[2] & 1) << 2) | (in_buf[3] >> 6);
            if (cur_key >= 0 && key != cur_key) {
                NeAACDecClose(h);
                h = NeAACDecOpen();
                NeAACDecSetConfiguration(h, cfg_copy(h));
                ready = 0;
                cur_key = -1;
                continue;
            }
            cur_key = key;
        }
        NeAACDecFrameInfo fi;
        void *out = NeAACDecDecode(h, &fi, in_buf, (unsigned long)in_len);
        if (fi.error) {
            /* lost sync (a damaged frame, or a chunk joined mid-frame): skip a byte and find the next one */
            consume(1);
            consume(adts_sync());
            continue;
        }
        if (fi.bytesconsumed == 0) { if (in_eof) break; consume(1); continue; }
        consume(fi.bytesconsumed);
        if (out && fi.samples > 0 && fi.channels > 0) {
            emit((const short *)out, (int)(fi.samples / fi.channels), fi.channels, (int)fi.samplerate);
            frames++;
        }
    }
    flush_out();
    NeAACDecClose(h);
    return frames > 0 ? 0 : 2;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    if (argc >= 2 && strcmp(argv[1], "mp3") == 0) return decode_mp3();
    if (argc >= 2 && strcmp(argv[1], "aac") == 0) return decode_aac();
    if (argc >= 2 && strcmp(argv[1], "--version") == 0) { puts("gzdecode 1 (minimp3, FAAD2 " GZ_FAAD_VERSION ")"); return 0; }
    fprintf(stderr, "usage: gzdecode mp3|aac < in > out.s16le (stereo, 44100 Hz)\n");
    return 1;
}
