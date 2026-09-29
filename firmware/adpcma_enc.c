// Streaming YM ADPCM-A encoder. See adpcma_enc.h for the API contract and
// scripts/rhythm_pack.py for the Python reference this mirrors bit for bit:
// same LUT source (adpcma_lut.h is generated from jt10_adpcma_lut.v), same
// greedy nibble pick, same step adaptation, same linear resampler, same
// silence-padded 256-byte alignment.

#include "adpcma_enc.h"
#include "adpcma_lut.h"

// Step-index adaptation per magnitude nibble -- jt10_adpcm.v's step_next.
static const int8_t STEP_ADAPT[8] = { -1, -1, -1, -1, 2, 5, 7, 9 };

// The softcore has no divider (nodiv-verify gates it), so division goes
// through the same restoring long divide gdc_service.c carries.
static uint32_t udiv32(uint32_t n, uint32_t d, uint32_t *rem)
{
    uint32_t q = 0u, r = 0u;
    if (d == 0u) {
        if (rem) {
            *rem = 0u;
        }
        return 0u;
    }
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    if (rem) {
        *rem = r;
    }
    return q;
}

void adpcm_enc_init(adpcm_enc *e, uint32_t src_rate)
{
    if (!src_rate)
        src_rate = 8000;
    // ratio = src_rate * 2^16 * 432 / 8e6, in 16.16 -- without touching the
    // 64-bit libcalls the freestanding build lacks. 2^16 * 432 / 8e6 reduces
    // to 512/62500 * src_rate, split as quotient*512 + remainder*512/62500.
    // src*432 <= 192000*432 < 2^27, so every intermediate fits in 32 bits.
    uint32_t t = src_rate * ADPCMA_RATE_DIV;
    uint32_t rem;
    e->ratio = (udiv32(t, 62500u, &rem) << 9) + udiv32(rem << 9, 62500u, 0);
    e->pos = 0;
    e->idx = 0;
    e->prev = e->cur = 0;
    e->primed = 0;
    e->x = e->step = 0;
    e->bytes = 0;
    e->half = -1;
    e->out_n = 0;
    e->last_target = 0;
    e->on_target = 0;
    e->cb_ctx = 0;
}

static void emit_nibble(adpcm_enc *e, int32_t target12)
{
    int32_t best_err = 0x7FFFFFFF, best_x = 0;
    uint32_t best = 0;
    for (uint32_t mag = 0; mag < 8; mag++) {
        int32_t inc = ADPCMA_INC[e->step * 8 + mag];
        for (uint32_t sign = 0; sign < 2; sign++) {
            int32_t cand = sign ? e->x - inc : e->x + inc;
            int32_t err = cand > target12 ? cand - target12 : target12 - cand;
            if (err < best_err) {
                best_err = err;
                best_x = cand;
                best = (sign << 3) | mag;
            }
        }
    }
    e->x = best_x;
    e->step += STEP_ADAPT[best & 7];
    if (e->step < 0)
        e->step = 0;
    else if (e->step > 48)
        e->step = 48;
    if (e->half < 0) {
        e->half = (int8_t)best;
    } else {
        e->out[e->out_n++] = (uint8_t)((e->half << 4) | best);
        e->half = -1;
        e->bytes++;
    }
}

// Encode one output sample: linear-interpolated source at e.pos dropped to
// the 12-bit sample domain, then the greedy nibble pick. `flat` replaces
// both taps with the newest sample -- the packer's pcm[-1] clamp at EOF.
static void emit_sample(adpcm_enc *e, int32_t flat)
{
    int32_t v;
    if (flat) {
        v = e->cur >> 4;
    } else {
        // lo + (hi-lo)*frac>>16 with a 32-bit magnitude multiply:
        // |hi-lo| <= 65534 and frac <= 65535, so the product still fits an
        // unsigned 32. The negative-product case needs the -1 floor step to
        // match an arithmetic >>16 exactly (the Python mirror uses one too).
        int32_t d = e->cur - e->prev;
        uint32_t ad = d < 0 ? (uint32_t)-d : (uint32_t)d;
        uint32_t p = ad * (e->pos & 0xFFFF);
        int32_t m = (int32_t)(p >> 16);
        if (d < 0) {
            m = -m;
            if (p & 0xFFFF)
                m -= 1;
        }
        v = (e->prev + m) >> 4;
    }
    if (v > 2047)
        v = 2047;
    else if (v < -2048)
        v = -2048;
    e->last_target = v;
    if (e->on_target)
        e->on_target(e->cb_ctx, v);
    emit_nibble(e, v);
    e->pos += e->ratio;
}

uint32_t adpcm_enc_push(adpcm_enc *e, int16_t s)
{
    e->out_n = 0;
    e->prev = e->cur;
    e->cur = s;
    if (e->primed) {
        e->idx++;
        // An output at pos needs source samples floor(pos) and floor(pos)+1;
        // the window holds [idx-1, idx], so it is serviceable exactly while
        // floor(pos) <= idx-1 -- which is when pos>>16 == idx-1 always.
        while ((e->pos >> 16) == e->idx - 1) {
            emit_sample(e, 0);
            if (e->out_n >= ADPCMA_OUT_MAX)
                return e->out_n;
        }
    } else {
        e->primed = 1;
    }
    return e->out_n;
}

uint32_t adpcm_enc_flush(adpcm_enc *e)
{
    e->out_n = 0;
    // First the flat tail the packer emits past the last sample (j clamped to
    // pcm[-1]), then silence until the byte stream sits on a 256-byte
    // boundary with no dangling nibble -- the accumulator decays to zero
    // inside the block rather than stepping off a cliff.
    while (e->out_n < ADPCMA_OUT_MAX && (e->pos >> 16) <= e->idx)
        emit_sample(e, 1);
    while (e->out_n < ADPCMA_OUT_MAX) {
        if (e->half < 0 && (e->bytes & 0xFF) == 0)
            break;
        emit_nibble(e, 0);
    }
    return e->out_n;
}
