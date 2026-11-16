// Streaming YM ADPCM-A encoder -- the C twin of scripts/rhythm_pack.py's
// adpcm_encode(), written for the softcore: constant state, no allocation,
// input samples pushed one at a time, output bytes drained a few at a time.
//
// Pure C with no MMIO access so it compiles and runs on the host too --
// scripts/rhythm_enc_test.c byte-compares it against the Python packer.
//
//   adpcm_enc e; adpcm_enc_init(&e, 44100);
//   for each int16 source sample:
//       int n = adpcm_enc_push(&e, s);
//       ...write e.out[0..n) to the store...
//   while (adpcm_enc_flush(&e))  // drain the 256-byte-boundary silence tail
//       ...write e.out[0..e.out_n)...
//   e.bytes is the encoded length (bytes/2 == ADPCM samples).

#ifndef ADPCMA_ENC_H
#define ADPCMA_ENC_H

#include <stdint.h>

// phi_M/432: the fixed ADPCM-A voice rate on the YM2608 (~18.5 kHz).
#define ADPCMA_RATE_NUM 8000000u
#define ADPCMA_RATE_DIV 432u

// push() can emit at most one byte per output sample; at the lowest sane
// source rate (4 kHz) a push yields ~5 output samples. 8 is generous.
#define ADPCMA_OUT_MAX 8

typedef struct {
    uint32_t ratio;   // source rate / output rate, 16.16 fixed point
    uint32_t pos;     // next output position in source samples, 16.16
    uint32_t idx;     // source index of `cur` (pushes minus one)
    int16_t  prev;    // source sample at index idx-1
    int16_t  cur;     // newest source sample
    uint8_t  primed;  // a real cur sample has been pushed
    int32_t  x;       // decoder-model accumulator (12-bit domain)
    int32_t  step;    // decoder-model step index, 0..48
    int32_t  last_target; // most recent emit_sample target (host-test hook)
    // NULL on the softcore; the host harness uses it to capture every target.
    void   (*on_target)(void *ctx, int32_t target12);
    void    *cb_ctx;
    uint32_t bytes;   // encoded bytes emitted so far
    int8_t   half;    // pending high nibble (-1 none, else 0..15)
    uint8_t  out[ADPCMA_OUT_MAX];
    uint8_t  out_n;
} adpcm_enc;

void     adpcm_enc_init(adpcm_enc *e, uint32_t src_rate);
uint32_t adpcm_enc_push(adpcm_enc *e, int16_t s);     // -> e.out_n bytes in e.out
uint32_t adpcm_enc_flush(adpcm_enc *e);               // ditto; 0 == fully padded

#endif
