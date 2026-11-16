// rhythm_enc_test -- host harness for firmware/adpcma_enc.c. Usage:
//   cc -O1 -o /tmp/enc_test scripts/rhythm_enc_test.c
//   /tmp/enc_test <16-bit mono|stereo wav>        # raw int16 samples in
//   /tmp/enc_test --raw <raw s16le pcm file>      # bypass resampler entirely
//
// Streams the source through the firmware encoder and writes the encoded
// ADPCM-A bytes to stdout. scripts/rhythm_enc_test.py drives the comparison
// against scripts/rhythm_pack.py (raw path must be bit-identical; the
// resampled path is compared after decode).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../firmware/adpcma_enc.c"

static int16_t rd16(const uint8_t *p) { return (int16_t)(p[0] | (p[1] << 8)); }
static uint32_t rd32(const uint8_t *p)
{ return p[0] | (p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static int g_targets_only;
static void drain(adpcm_enc *e)
{
    if (!g_targets_only)
        fwrite(e->out, 1, e->out_n, stdout);
}

static void dump_target(void *ctx, int32_t t12)
{
    (void)ctx;
    uint8_t b[2] = { (uint8_t)(t12 & 0xFF), (uint8_t)((t12 >> 8) & 0xFF) };
    fwrite(b, 1, 2, stdout);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s [--raw] <file>\n", argv[0]);
        return 2;
    }
    int want_targets = !strcmp(argv[1], "--targets");
    int want_raw = !strcmp(argv[1], "--raw");
    adpcm_enc e;
    adpcm_enc_init(&e, 44100);
    if (want_targets) {
        e.on_target = dump_target;
        e.cb_ctx = 0;
        g_targets_only = 1;
    }

    FILE *f = fopen(argv[argc - 1], "rb");
    if (!f) {
        perror(argv[argc - 1]);
        return 1;
    }
    if (want_raw) {
        // --raw: s16le samples at the output rate; pretend the source rate
        // matches so the resampler degenerates to passthrough.
        e.ratio = 0x10000;
        int c;
        while ((c = getc(f)) != EOF) {
            int c2 = getc(f);
            if (c2 == EOF)
                break;
            if (adpcm_enc_push(&e, (int16_t)(c | (c2 << 8))))
                drain(&e);
        }
    } else {
        // WAV: RIFF walk for fmt + data, int16 mono/stereo.
        uint8_t hdr[12];
        if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "RIFF", 4) ||
            memcmp(hdr + 8, "WAVE", 4)) {
            fprintf(stderr, "not a RIFF/WAVE file\n");
            return 1;
        }
        uint32_t rate = 0, dlen = 0;
        uint16_t ch = 0, bits = 0;
        for (;;) {
            uint8_t chdr[8];
            if (fread(chdr, 1, 8, f) != 8)
                break;
            uint32_t sz = rd32(chdr + 4);
            if (!memcmp(chdr, "fmt ", 4)) {
                uint8_t fmt[16];
                if (fread(fmt, 1, 16, f) != 16)
                    return 1;
                ch = (uint16_t)rd16(fmt + 2);
                rate = rd32(fmt + 4);
                bits = (uint16_t)rd16(fmt + 14);
                if (sz > 16)
                    fseek(f, sz - 16, SEEK_CUR);
            } else if (!memcmp(chdr, "data", 4)) {
                dlen = sz;
                break;
            } else {
                fseek(f, sz, SEEK_CUR);
            }
        }
        if (!rate || !dlen || bits != 16 || (ch != 1 && ch != 2)) {
            fprintf(stderr, "need 16-bit PCM mono/stereo, got ch=%d bits=%d\n",
                    ch, bits);
            return 1;
        }
        adpcm_enc_init(&e, rate);
        if (want_targets) {
            e.on_target = dump_target;
            e.cb_ctx = 0;
        }
        uint8_t buf[4096];
        while (dlen) {
            uint32_t n = dlen > sizeof buf ? sizeof buf : dlen;
            n -= n % (2 * ch);
            if (fread(buf, 1, n, f) != n)
                return 1;
            dlen -= n;
            for (uint32_t i = 0; i + 2 * ch <= n; i += 2 * ch) {
                int32_t s = rd16(buf + i);
                if (ch == 2)
                    s = (s + rd16(buf + i + 2)) / 2;
                if (adpcm_enc_push(&e, (int16_t)s))
                    drain(&e);
            }
        }
    }
    fclose(f);
    while (adpcm_enc_flush(&e))
        drain(&e);
    return 0;
}
