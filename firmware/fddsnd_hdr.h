// fddsnd_hdr.h -- the fddsnd.bin header layout, as scripts/fddsnd_pack.py
// emits it. The loader reads the 28-byte header as seven little-endian
// 32-bit words through the auto-incrementing bridge-RAM port:
//
//   word 0    u32 magic 'FDS1' (0x31534446)
//   word 1    u16 version (low half), u16 segment count (high half)
//   words 2-6 one segment {offset,length} pair per word -- low u16 is the
//             word offset into the file, high u16 the word length
//
// Kept pure (no MMIO) like adpcma_enc.h so scripts/fddsnd_hdr_test.c can
// run the same parse on the host against packer-format bytes.

#ifndef FDDSND_HDR_H
#define FDDSND_HDR_H

#include <stdint.h>

#define FDDSND_HDR_BYTES 28u
#define FDDSND_SEGS      5u

// Returns nonzero on a bad magic, a count too small to cover the five
// mechanism segments, or a segment whose byte range runs past file_bytes
// (the bound slot's real size -- without the bound a corrupt pack makes
// the loader read out-of-range slot space and play whatever answered).
static inline int fddsnd_hdr_parse(const uint32_t *words,
                                   uint32_t file_bytes,
                                   uint16_t *off, uint16_t *len)
{
    if (words[0] != 0x31534446u)            // 'FDS1'
        return -1;
    if ((words[1] >> 16) < FDDSND_SEGS)
        return -1;
    for (uint32_t i = 0; i < FDDSND_SEGS; i++) {
        uint32_t o = words[2 + i] & 0xFFFF;
        uint32_t l = words[2 + i] >> 16;
        if (o * 2 + l * 2 > file_bytes)     // word units -> file bytes
            return -1;
        off[i] = (uint16_t)o;
        len[i] = (uint16_t)l;
    }
    return 0;
}

#endif
