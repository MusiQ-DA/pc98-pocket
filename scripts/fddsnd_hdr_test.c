// fddsnd_hdr_test -- host harness for firmware/fddsnd_hdr.h. Reads an
// fddsnd.bin blob, presents its 28-byte header as the seven little-endian
// 32-bit words the bridge RAM's auto-incrementing port hands the loader,
// and prints the parsed segment table ("off len" per line). Exit 1 on a
// rejected header so negative tests are just a corrupt file.
//
//   cc -O1 -o /tmp/fddsnd_hdr_test scripts/fddsnd_hdr_test.c
//   /tmp/fddsnd_hdr_test fddsnd.bin

#include <stdio.h>
#include <stdint.h>
#include "../firmware/fddsnd_hdr.h"

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <fddsnd.bin>\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror(argv[1]);
        return 1;
    }
    uint8_t b[FDDSND_HDR_BYTES];
    if (fread(b, 1, sizeof b, f) != sizeof b) {
        fprintf(stderr, "%s: header under %d bytes\n", argv[0],
                (int)sizeof b);
        return 1;
    }
    fclose(f);

    uint32_t w[FDDSND_HDR_BYTES / 4];
    for (uint32_t i = 0; i < FDDSND_HDR_BYTES / 4; i++)
        w[i] = (uint32_t)b[i * 4] | ((uint32_t)b[i * 4 + 1] << 8)
             | ((uint32_t)b[i * 4 + 2] << 16) | ((uint32_t)b[i * 4 + 3] << 24);

    uint16_t off[FDDSND_SEGS], len[FDDSND_SEGS];
    if (fddsnd_hdr_parse(w, off, len)) {
        fprintf(stderr, "%s: bad header\n", argv[1]);
        return 1;
    }
    for (uint32_t i = 0; i < FDDSND_SEGS; i++)
        printf("%u %u\n", off[i], len[i]);
    return 0;
}
