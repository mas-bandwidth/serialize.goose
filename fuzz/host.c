/*
    fuzz/host.c -- TestDifferentialAgainstSerializeC (the family pattern of
    serialize.lobster's fuzz/host.c, driving a Goose child instead).

    A seeded generator writes random programs over every operation
    serialize.c v2.0.0 has (bits, bits64, bool, uint8..uint64, int, int64,
    int_relative, uint128, int128, float, double, fixed32/64/128,
    compressed_float and its precomputed form, bytes, string, align, object,
    end).  serialize.c (the oracle, compiled from .ref/serialize.c-v2.0.0)
    writes and reads each one, and the Goose port is driven as a child process
    (fuzz/fuzz_driver.goose, built once by goose build) over files in this
    test's own temporary directory, one process per batch of 100 programs.
    Every program ends with an end (STANDARD.md, end), and every float and
    double it writes is finite (STANDARD.md, "Finite values only").

    For every program the two writers' bytes must be equal; each side reads the
    other's bytes and every decoded value (floats by bit pattern) must match;
    one in four programs is mutated and both readers must agree on accept or
    refuse, on the refusing step, on the refusal REASON (STANDARD.md, Refusal
    reasons), and on every value decoded before it.  A mutant appending bytes
    reaches the end's trailing_data; targeted mutants write a ranged offset one
    past its span, an all-ones exponent into a float or double field, or a
    zero or 0xFF byte into a string payload.

    The CI smoke is 2000 programs from the FIXED default seed (no clock).
    --seed picks another seed and --duration <seconds> keeps generating
    batches until that much time has passed (the nightly extended run; a
    functional test, so real time is allowed there).  The seed is printed
    first, so any red run is replayed with --seed.  A failing batch's
    temporary directory (batch.txt, result.txt) is kept and its path printed.

    Fixed point (fixed32/64/128) is generated from rotating declaration
    tables, not only fraction_bits = 0: zero and nonzero fractions, signed
    whole bounds, degenerate ranges, raw values at raw_min/raw_max and one
    raw step inside them, values clamped at the storage type's extremes,
    and encoded widths (bit length of the raw span) immediately below, at
    and above the 32-bit group boundaries (31/32/33, 63/64/65, 95/96/97,
    127/128 bits).  The run counts this coverage and fails by name if any
    required part of it stops being emitted, so the evidence cannot
    silently narrow again.

    Beyond the writers' bytes and the decoded values, the two sides also
    compare the measure stream's bit count for every program, the reader's
    consumed bit count on every accepted read, and terminal behaviour on
    every refused read (one further read, which both latches must refuse).
    A refused stream's bit counter is not compared: the counters of a
    failed stream are not data (DESIGN.md (e)).

    --driver-opt names a second build of the same driver, compiled
    optimized (goose build -O2, no --debug).  Every batch is then run
    through both drivers and their result files must be identical byte
    for byte, in addition to the debug driver's comparison against
    serialize.c: a debug/optimized divergence is a failure of this test,
    named "optimized driver output differs".

    --negative-control makes the C side write one int range one bit wider,
    which must make the comparison red (make fuzz proves it does).
*/

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>

#include "serialize.h"

#define BATCH 100
#define MAXOPS 24
#define BUFCAP 1024
#define MAXTOK 4
#define TOKLEN 192

enum {
    OP_BITS, OP_BITS64, OP_BOOL, OP_U8, OP_U16, OP_U32, OP_U64,
    OP_INT, OP_INT64, OP_INT_REL, OP_U128, OP_I128, OP_FLOAT, OP_DOUBLE,
    OP_FIXED32, OP_FIXED64, OP_FIXED128, OP_CFLOAT, OP_CFLOAT_PRE,
    OP_BYTES, OP_STRING, OP_ALIGN, OP_OBJECT, OP_KINDS,
    OP_END = OP_KINDS
};

typedef struct {
    int kind;
    int bits;
    int frac;
    uint64_t u, u2, u3;
    int64_t s, min, max;
    int32_t i1, i2, i3;
    float f1, f2, f3, f4;
    uint32_t cmax;
    int cbits;
    float cdelta;
    int len, bufsize;
    unsigned char buf[64];
} Op;

typedef struct {
    int id;
    int nops;
    Op ops[MAXOPS + 1];
    unsigned char bytes[BUFCAP];
    int nbytes;
    unsigned char mutant[BUFCAP + 8];
    int nmutant;
    int has_mutant;
    /* One entry per ranged field the writer emitted: where its offset bits
       live and an offset one past its span, which serialize.c's reader
       refuses (STANDARD.md, int; DESIGN.md (c)).  The targeted mutant writes
       that offset so the mutant leg reaches the range refusal itself. */
    int nranged;
    int rkind[MAXOPS + 1];
    int rstart[MAXOPS + 1];
    int rwidth[MAXOPS + 1];
    uint64_t rtarget[MAXOPS + 1];
    uint64_t rtarget_hi[MAXOPS + 1];
} Program;

/* ---------------------------------------------------------------- RNG --- */

static uint64_t rng_state = 0x9e3779b97f4a7c15ULL;
static uint64_t rng_next(void) {
    uint64_t z = (rng_state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}
static uint32_t rnd(uint32_t n) { return (uint32_t)(rng_next() % n); }
static int32_t rnd_i32_range(int32_t lo, int32_t hi) {
    uint64_t span = (uint64_t)((int64_t)hi - (int64_t)lo) + 1;
    return (int32_t)((int64_t)lo + (int64_t)(rng_next() % span));
}
static int64_t rnd_i64_range(int64_t lo, int64_t hi) {
    uint64_t span = (uint64_t)hi - (uint64_t)lo + 1;
    if (span == 0) return (int64_t)rng_next();
    return (int64_t)((uint64_t)lo + rng_next() % span);
}
static void rnd_bytes(unsigned char *p, int n) { for (int i = 0; i < n; i++) p[i] = (unsigned char)rng_next(); }
static float f32_from_bits(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t f32_bits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static double f64_from_bits(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }

/* ------------------------------------------------------- 128-bit raw --- */
/* The fixed point raw domain (STANDARD.md, fixed): a raw bound is a whole
   bound shifted by fraction_bits in the 128-bit two's-complement domain,
   exactly as serialize.c's serialize_raw_bound computes it. */

typedef struct { uint64_t lo, hi; } U128;

static int bl64(uint64_t v) { int b = 0; while (v) { b++; v >>= 1; } return b; }
static U128 u128_from_i64(int64_t v) { U128 r; r.lo = (uint64_t)v; r.hi = v < 0 ? ~0ULL : 0; return r; }
static U128 u128_shl(U128 a, int n) {
    if (n <= 0) return a;
    if (n >= 64) { U128 r; r.lo = 0; r.hi = a.lo << (n - 64); return r; }
    { U128 r; r.hi = (a.hi << n) | (a.lo >> (64 - n)); r.lo = a.lo << n; return r; }
}
static U128 u128_add(U128 a, U128 b) {
    U128 r; r.lo = a.lo + b.lo;
    r.hi = a.hi + b.hi + (r.lo < a.lo ? 1 : 0);
    return r;
}
static U128 u128_sub(U128 a, U128 b) {
    U128 r; r.lo = a.lo - b.lo;
    r.hi = a.hi - b.hi - (a.lo < b.lo ? 1 : 0);
    return r;
}
static int u128_cmp(U128 a, U128 b) {
    if (a.hi != b.hi) return a.hi < b.hi ? -1 : 1;
    if (a.lo != b.lo) return a.lo < b.lo ? -1 : 1;
    return 0;
}
static int u128_bitlen(U128 a) { return a.hi ? 64 + bl64(a.hi) : bl64(a.lo); }
static U128 u128_shr1(U128 a) { U128 r; r.lo = (a.lo >> 1) | (a.hi << 63); r.hi = a.hi >> 1; return r; }
static U128 fixed_raw_bound(int64_t whole, int fraction_bits) {
    return u128_shl(u128_from_i64(whole), fraction_bits);
}

/* Fixed coverage the run must emit (counted in gen_fixed, checked in main):
   per fixed kind, fraction zero and nonzero and a degenerate range; exact
   encoded widths at the group boundaries; raw edge values; a value clamped
   at a storage extreme. */
static long cov_frac_zero[3], cov_frac_nonzero[3], cov_degenerate[3];
static long cov_width[129];
static long cov_edge_min, cov_edge_min_plus, cov_edge_max_minus, cov_edge_max, cov_storage_extreme;

typedef struct { int integer_bits, fraction_bits; int64_t mn, mx; } FixedDecl;

/* fraction_bits -1 is the pre-existing random declaration (fraction 0).
   Every declaration fits its Q format: whole units in [-2^(integer_bits-1),
   2^(integer_bits-1) - 1], any int64 from 64 integer bits up (IMPLEMENTING.md
   U16; the C++ reference's compile error). The encoded widths above 32 and 64
   bits come from the wider storage that can hold them. */
static const FixedDecl fixed32_decls[] = {
    { 32, -1, 0, 0 },
    { 8, 8, -100, 100 },
    { 16, 16, -32768, 32767 },
    { 16, 16, -16384, 16383 },
    { 17, 15, -65536, 65535 },
    { 24, 8, -100000, 100000 },
    { 31, 1, -1000000000, 1000000000 },
    { 1, 31, -1, 0 },
    { 16, 16, 7, 7 },
    { 8, 8, -9, -9 },
    { 32, 0, -2147483647 - 1, 2147483647 },
    { 30, 2, -268435456, 268435455 },
};
static const FixedDecl fixed64_decls[] = {
    { 64, -1, 0, 0 },
    { 48, 16, 0, 131072 },
    { 32, 32, -100000, 100000 },
    { 48, 16, -35184372088832LL, 35184372088832LL },
    { 48, 16, -70368744177664LL, 70368744177664LL },
    { 48, 16, -32768, 32768 },
    { 32, 32, -2147483647LL - 1, 2147483647LL },
    { 32, 32, -1073741824LL, 1073741823LL },
    { 1, 63, -1, 0 },
    { 63, 1, -4611686018427387904LL, 4611686018427387903LL },
    { 32, 32, -9, -9 },
    { 64, 0, -9223372036854775807LL - 1, 9223372036854775807LL },
    { 16, 48, -1000, 1000 },
};
static const FixedDecl fixed128_decls[] = {
    { 128, -1, 0, 0 },
    { 112, 16, -144115188075855872LL, 144115188075855872LL },
    { 64, 64, 0, 9223372036854775807LL },
    { 64, 64, 3, 3 },
    { 112, 16, -9, -9 },
    { 96, 32, -2305843009213693952LL, 2305843009213693952LL },
    { 96, 32, -4611686018427387904LL, 4611686018427387904LL },
    { 64, 64, 0, 4294967296LL },
    { 64, 64, -4611686018427387904LL, 4611686018427387904LL },
    { 1, 127, -1, 0 },
    { 112, 16, 0, 281474976710656LL },
    { 112, 16, -2000, 2000 },
    { 120, 8, -1000000, 1000000 },
};
static unsigned fixed_seq[3];

/* Generate one fixed operation: o->bits is integer_bits, o->frac is
   fraction_bits, o->min/o->max are whole bounds, and the raw value is in
   o->s (fixed32/64) or o->u/o->u2 as lo/hi lanes (fixed128).  The raw value
   always lies in [raw_min, raw_max] and in the storage type, so neither
   writer is handed a value its own contract refuses. */
static void gen_fixed(Op *o, int which) {
    const FixedDecl *table;
    int ndecl, storage_bits;
    int64_t storage_min, storage_max;
    if (which == 0) { table = fixed32_decls; ndecl = (int)(sizeof(fixed32_decls) / sizeof(fixed32_decls[0])); storage_bits = 32; storage_min = -2147483647LL - 1; storage_max = 2147483647LL; }
    else if (which == 1) { table = fixed64_decls; ndecl = (int)(sizeof(fixed64_decls) / sizeof(fixed64_decls[0])); storage_bits = 64; storage_min = -9223372036854775807LL - 1; storage_max = 9223372036854775807LL; }
    else { table = fixed128_decls; ndecl = (int)(sizeof(fixed128_decls) / sizeof(fixed128_decls[0])); storage_bits = 128; storage_min = 0; storage_max = 0; }
    unsigned seq = fixed_seq[which]++;
    const FixedDecl *d = &table[seq % (unsigned)ndecl];
    int edge = (int)((seq / (unsigned)ndecl) % 6);
    (void)storage_bits;
    if (d->fraction_bits < 0) {
        /* the legacy random declaration, fraction 0 */
        o->frac = 0;
        if (which == 0) {
            int32_t r = (int32_t)(1 + rnd(10000));
            o->bits = 32;
            o->min = rnd(3) == 0 ? 5 : -r;
            o->max = rnd(3) == 0 ? 5 : r;
            if (o->min > o->max) { int64_t t = o->min; o->min = o->max; o->max = t; }
            o->s = rnd_i32_range((int32_t)o->min, (int32_t)o->max);
        } else if (which == 1) {
            int64_t r = (int64_t)(1 + rnd(1000000));
            o->bits = 64;
            o->min = rnd(3) == 0 ? -3 : -r;
            o->max = rnd(3) == 0 ? -3 : r;
            if (o->min > o->max) { int64_t t = o->min; o->min = o->max; o->max = t; }
            o->s = rnd_i64_range(o->min, o->max);
        } else {
            int c = (int)rnd(5);
            int64_t r = (int64_t)(1 + rnd(1000000));
            o->bits = 128;
            if (c == 0) { o->min = o->max = rnd_i64_range(-1000, 1000); }
            else if (c == 1) { o->min = -r; o->max = r; }
            else if (c == 2) { o->min = -9223372036854775807LL - 1; o->max = 9223372036854775807LL; }
            else if (c == 3) { o->min = (-9223372036854775807LL - 1) / 2; o->max = 9223372036854775807LL / 2; }
            else { o->min = -r; o->max = r; }
            o->s = rnd_i64_range(o->min, o->max);
            { U128 rv = u128_from_i64(o->s); o->u = rv.lo; o->u2 = rv.hi; }
        }
        cov_frac_zero[which]++;
        {
            U128 span = u128_sub(fixed_raw_bound(o->max, 0), fixed_raw_bound(o->min, 0));
            int bits = u128_bitlen(span);
            if (bits == 0) cov_degenerate[which]++;
            else if (bits <= 128) cov_width[bits]++;
        }
        return;
    }
    o->bits = d->integer_bits;
    o->frac = d->fraction_bits;
    o->min = d->mn;
    o->max = d->mx;
    {
        U128 raw_min = fixed_raw_bound(o->min, o->frac);
        U128 raw_max = fixed_raw_bound(o->max, o->frac);
        U128 span = u128_sub(raw_max, raw_min);
        int bits = u128_bitlen(span);
        U128 one = { 1, 0 };
        U128 offset;
        if (bits == 0) offset.lo = 0, offset.hi = 0;
        else if (edge == 0) offset = u128_from_i64(0);
        else if (edge == 1) offset = one;
        else if (edge == 2) offset = u128_sub(span, one);
        else if (edge == 3) offset = span;
        else if (edge == 4) offset = u128_shr1(span);
        else {
            offset.lo = rng_next(); offset.hi = rng_next();
            /* mask to the span's bit length; an overshoot takes the middle */
            if (bits < 128) {
                U128 mask;
                if (bits == 64) { mask.lo = ~0ULL; mask.hi = 0; }
                else if (bits < 64) { mask.lo = (1ULL << bits) - 1; mask.hi = 0; }
                else { mask.lo = ~0ULL; mask.hi = (1ULL << (bits - 64)) - 1; }
                offset.lo &= mask.lo; offset.hi &= mask.hi;
            }
            if (u128_cmp(offset, span) > 0) offset = u128_shr1(span);
        }
        {
            U128 rv = u128_add(raw_min, offset);
            if (offset.lo == 0 && offset.hi == 0) cov_edge_min++;
            if (u128_cmp(offset, span) == 0 && bits > 0) cov_edge_max++;
            if (bits > 0 && offset.lo == 1 && offset.hi == 0) cov_edge_min_plus++;
            if (bits > 0 && u128_cmp(u128_add(offset, one), span) == 0) cov_edge_max_minus++;
            if (which < 2) {
                /* clamp at the storage type's extremes: the clamped value is
                   one raw step inside a raw bound past the storage range */
                U128 smin = u128_from_i64(storage_min), smax = u128_from_i64(storage_max);
                /* signed comparison: compare hi as signed, then lo */
                int below = ((int64_t)rv.hi < (int64_t)smin.hi) ||
                    ((int64_t)rv.hi == (int64_t)smin.hi && rv.lo < smin.lo);
                int above = ((int64_t)rv.hi > (int64_t)smax.hi) ||
                    ((int64_t)rv.hi == (int64_t)smax.hi && rv.lo > smax.lo);
                if (below) rv = smin;
                if (above) rv = smax;
                if ((rv.lo == smin.lo && rv.hi == smin.hi) || (rv.lo == smax.lo && rv.hi == smax.hi))
                    cov_storage_extreme++;
                if (u128_cmp(u128_sub(rv, raw_min), span) > 0) rv = raw_min;
                o->s = (int64_t)rv.lo;
            } else {
                o->u = rv.lo; o->u2 = rv.hi; o->s = (int64_t)rv.lo;
            }
            if (o->frac == 0) cov_frac_zero[which]++; else cov_frac_nonzero[which]++;
            if (bits == 0) cov_degenerate[which]++;
            else if (bits <= 128) cov_width[bits]++;
        }
    }
}

/* ---------------------------------------------------------- generator --- */

static void gen_op(Op *o) {
    memset(o, 0, sizeof(*o));
    o->kind = (int)rnd(OP_KINDS);
    switch (o->kind) {
    case OP_BITS:
        o->bits = 1 + (int)rnd(32);
        o->u = rng_next() & (o->bits == 32 ? 0xFFFFFFFFULL : ((1ULL << o->bits) - 1));
        break;
    case OP_BITS64:
        o->bits = 1 + (int)rnd(64);
        o->u = rng_next() & (o->bits == 64 ? ~0ULL : ((1ULL << o->bits) - 1));
        break;
    case OP_BOOL: o->u = rnd(2); break;
    case OP_U8: o->u = rnd(256); break;
    case OP_U16: o->u = rnd(65536); break;
    case OP_U32: o->u = (uint32_t)rng_next(); break;
    case OP_U64: o->u = rng_next(); break;
    case OP_INT: {
        int c = (int)rnd(5);
        if (c == 0) { o->min = o->max = rnd_i32_range(-100, 100); }
        else if (c == 1) { int32_t r = (int32_t)(1 + rnd(1000)); o->min = -r; o->max = r; }
        else if (c == 2) { o->min = INT32_MIN; o->max = INT32_MAX; }
        else if (c == 3) { o->min = 0; o->max = 7; }
        else { o->min = rnd_i32_range(-100000, 0); o->max = rnd_i32_range(1, 100000); }
        o->s = rnd_i32_range((int32_t)o->min, (int32_t)o->max);
        break;
    }
    case OP_INT64: {
        int c = (int)rnd(5);
        if (c == 0) { o->min = o->max = rnd_i64_range(-1000000, 1000000); }
        else if (c == 1) { int64_t r = (int64_t)(1 + rnd(1000000)); o->min = -r; o->max = r; }
        else if (c == 2) { o->min = INT64_MIN; o->max = INT64_MAX; }
        else if (c == 3) { o->min = 0; o->max = 7; }
        else { o->min = rnd_i64_range(-INT64_MAX / 2, 0); o->max = rnd_i64_range(1, INT64_MAX / 2); }
        o->s = rnd_i64_range(o->min, o->max);
        break;
    }
    case OP_INT_REL: {
        int64_t prev = rnd(5) == 0 ? (int64_t)(INT32_MAX - 1 - rnd(1000)) : (int64_t)rnd(1000000);
        int64_t cur = prev + 1 + (int64_t)rnd(200000);
        if (cur > INT32_MAX) cur = INT32_MAX;
        o->i1 = (int32_t)prev;
        o->i2 = (int32_t)cur;
        break;
    }
    case OP_U128:
        o->u = rng_next(); o->u2 = rng_next();
        if (rnd(4) == 0) o->u = (rnd(2) ? 0 : ~0ULL);
        if (rnd(4) == 0) o->u2 = (rnd(2) ? 0 : ~0ULL);
        break;
    case OP_I128: {
        int c = (int)rnd(5);
        int64_t lo, hi, v;
        if (c == 0) { lo = hi = rnd_i64_range(-1000, 1000); v = lo; }
        else if (c == 1) { int64_t r = (int64_t)(1 + rnd(1000000)); lo = -r; hi = r; v = rnd_i64_range(lo, hi); }
        else if (c == 2) { lo = INT64_MIN; hi = INT64_MAX; v = (int64_t)rng_next(); }
        else if (c == 3) { lo = INT64_MIN / 2; hi = INT64_MAX / 2; v = rnd_i64_range(lo, hi); }
        else { int64_t r = (int64_t)(1 + rnd(1000000)); lo = -r; hi = r; v = (rnd(2) ? lo : hi); }
        o->min = lo; o->max = hi;
        o->u = (uint64_t)v; o->u2 = (uint64_t)(v < 0 ? -1 : 0);
        break;
    }
    case OP_FLOAT: {
        /* finite patterns only: a writer is handed finite values, and
           serialize.c asserts it.  Random bits whose exponent is all ones
           have its top bit cleared. */
        int c = (int)rnd(6);
        uint32_t b;
        if (c == 0) b = (uint32_t)rng_next();
        else if (c == 1) b = (uint32_t)rng_next() & 0x807FFFFFu;
        else if (c == 2) b = 0x7f7fffffu - (uint32_t)rnd(4);
        else if (c == 3) b = 0xff7fffffu - (uint32_t)rnd(4);
        else if (c == 4) b = 0x80000000u;
        else b = f32_bits((float)rng_next() / (float)UINT32_MAX * 100.0f - 50.0f);
        if ((b & 0x7f800000u) == 0x7f800000u) b ^= 0x40000000u;
        o->u = b;
        break;
    }
    case OP_DOUBLE: {
        int c = (int)rnd(5);
        uint64_t b;
        if (c == 0) b = rng_next();
        else if (c == 1) b = rng_next() & 0x800FFFFFFFFFFFFFULL;
        else if (c == 2) b = 0x7fefffffffffffffULL - (rng_next() & 0xFFFFFFFFULL);
        else if (c == 3) b = 0x8000000000000000ULL;
        else b = (uint64_t)rng_next();
        if ((b & 0x7ff0000000000000ULL) == 0x7ff0000000000000ULL) b ^= 0x4000000000000000ULL;
        o->u = b;
        break;
    }
    case OP_FIXED32: gen_fixed(o, 0); break;
    case OP_FIXED64: gen_fixed(o, 1); break;
    case OP_FIXED128: gen_fixed(o, 2); break;
    case OP_CFLOAT: {
        if (rnd(2) == 0) { o->f1 = -2.0f; o->f2 = 2.0f; o->f3 = 0.01f; }
        else { o->f1 = 0.0f; o->f2 = 100.0f; o->f3 = 0.5f; }
        o->f4 = o->f1 + (o->f2 - o->f1) * ((float)rnd(10000) / 10000.0f);
        break;
    }
    case OP_CFLOAT_PRE: {
        uint32_t mi; int bits; float delta;
        if (rnd(2) == 0) { o->f1 = -2.0f; o->f2 = 2.0f; o->f3 = 0.01f; }
        else { o->f1 = 0.0f; o->f2 = 100.0f; o->f3 = 0.5f; }
        serialize_compressed_float_params(o->f1, o->f2, o->f3, &mi, &bits, &delta);
        o->cmax = mi; o->cbits = bits; o->cdelta = delta;
        o->f4 = o->f1 + (o->f2 - o->f1) * ((float)rnd(10000) / 10000.0f);
        break;
    }
    case OP_BYTES:
        o->len = (int)rnd(17);
        rnd_bytes(o->buf, o->len);
        break;
    case OP_STRING:
        o->bufsize = 64;
        o->len = (int)rnd(21);
        for (int i = 0; i < o->len; i++) o->buf[i] = (unsigned char)('A' + rnd(26));
        break;
    case OP_ALIGN: break;
    case OP_OBJECT: break;
    }
}

static void gen_program(Program *p, int id) {
    memset(p, 0, sizeof(*p));
    p->id = id;
    p->nops = 1 + (int)rnd(MAXOPS - 1);
    for (int i = 0; i < p->nops; i++) gen_op(&p->ops[i]);
    /* a packet is one object and its end (STANDARD.md, Compatibility Notes) */
    memset(&p->ops[p->nops], 0, sizeof(Op));
    p->ops[p->nops].kind = OP_END;
    p->nops++;
    p->has_mutant = (rnd(4) == 0);
}

/* ------------------------------------------------------------- writer --- */

/* Record a ranged field: its offset starts at bit bstart and spans width
   bits.  Only fields with a representable out-of-range offset are recorded
   (a full-width or degenerate span has none).  The span is the RAW span:
   for fixed point, (max - min) << fraction_bits, in the 128-bit domain. */
static void record_ranged(Program *p, int kind, U128 span, int64_t bstart) {
    int bits = u128_bitlen(span);
    if (bits == 0) return;
    if (kind != OP_FIXED32 && kind != OP_FIXED64 && kind != OP_FIXED128 && bits >= 64) return;
    if (bits > 128) return;
    {
        U128 top; /* 2^bits - 1: a span of all ones has no one-past offset */
        if (bits == 128) { top.lo = ~0ULL; top.hi = ~0ULL; }
        else if (bits == 64) { top.lo = ~0ULL; top.hi = 0; }
        else if (bits < 64) { top.lo = (1ULL << bits) - 1; top.hi = 0; }
        else { top.lo = ~0ULL; top.hi = (1ULL << (bits - 64)) - 1; }
        if (u128_cmp(span, top) == 0) return;
    }
    if (p->nranged >= MAXOPS) return;
    {
        U128 target = u128_add(span, u128_from_i64(1));
        p->rkind[p->nranged] = kind;
        p->rstart[p->nranged] = (int)bstart;
        p->rwidth[p->nranged] = bits;
        p->rtarget[p->nranged] = target.lo;
        p->rtarget_hi[p->nranged] = target.hi;
        p->nranged++;
    }
}

/* Record a field a targeted mutant rewrites to a value every reader refuses:
   a float or double exponent set all ones (non_finite_float, STANDARD.md,
   "Finite values only"), or a string payload byte set to 0x00 (embedded_nul)
   or 0xFF (invalid_utf8, STANDARD.md, string). */
static void record_field(Program *p, int kind, int64_t bstart, int width, uint64_t target) {
    if (p->nranged >= MAXOPS) return;
    p->rkind[p->nranged] = kind;
    p->rstart[p->nranged] = (int)bstart;
    p->rwidth[p->nranged] = width;
    p->rtarget[p->nranged] = target;
    p->rtarget_hi[p->nranged] = 0;
    p->nranged++;
}

static int write_program(Program *p, unsigned char *buf, int cap, int widen, int *widen_done) {
    serialize_write_stream_t w;
    serialize_write_stream_init(&w, buf, cap);
    p->nranged = 0;
    for (int i = 0; i < p->nops; i++) {
        Op *o = &p->ops[i];
        int64_t bstart = serialize_write_bits_processed(&w);
        switch (o->kind) {
        case OP_BITS: serialize_write_bits(&w, (uint32_t)o->u, o->bits); break;
        case OP_BITS64: serialize_write_bits64(&w, (uint64_t)o->u, o->bits); break;
        case OP_BOOL: serialize_write_bool(&w, (int)o->u); break;
        case OP_U8: serialize_write_uint8(&w, (uint8_t)o->u); break;
        case OP_U16: serialize_write_uint16(&w, (uint16_t)o->u); break;
        case OP_U32: serialize_write_uint32(&w, (uint32_t)o->u); break;
        case OP_U64: serialize_write_uint64(&w, (uint64_t)o->u); break;
        case OP_INT: {
            int32_t mx = (int32_t)o->max;
            if (widen && !*widen_done) {
                int wid = serialize_bits_required((int32_t)o->min, (int32_t)o->max);
                if (wid >= 1 && wid < 31 && o->max <= (int64_t)INT32_MAX - (1LL << wid)) {
                    mx = (int32_t)(o->max + (1LL << wid));
                    *widen_done = 1;
                }
            }
            serialize_write_int(&w, (int32_t)o->s, (int32_t)o->min, mx);
            break;
        }
        case OP_INT64: serialize_write_int64(&w, (int64_t)o->s, o->min, o->max); break;
        case OP_INT_REL: serialize_write_int_relative(&w, o->i1, o->i2); break;
        case OP_U128: serialize_write_uint128(&w, serialize_uint128_make(o->u2, o->u)); break;
        case OP_I128:
            serialize_write_int128(&w,
                serialize_int128_make((serialize_uint64_t)o->u2, (serialize_uint64_t)o->u),
                serialize_int128_make((serialize_uint64_t)(o->min < 0 ? ~0ULL : 0), (serialize_uint64_t)o->min),
                serialize_int128_make((serialize_uint64_t)(o->max < 0 ? ~0ULL : 0), (serialize_uint64_t)o->max));
            break;
        case OP_FLOAT: serialize_write_float(&w, f32_from_bits((uint32_t)o->u)); break;
        case OP_DOUBLE: serialize_write_double(&w, f64_from_bits(o->u)); break;
        case OP_FIXED32: serialize_write_fixed32(&w, (int32_t)o->s, o->bits, o->frac, (int32_t)o->min, (int32_t)o->max); break;
        case OP_FIXED64: serialize_write_fixed64(&w, (int64_t)o->s, o->bits, o->frac, o->min, o->max); break;
        case OP_FIXED128:
            serialize_write_fixed128(&w,
                serialize_int128_make((serialize_uint64_t)o->u2, (serialize_uint64_t)o->u),
                o->bits, o->frac, o->min, o->max);
            break;
        case OP_CFLOAT: serialize_write_compressed_float(&w, o->f4, o->f1, o->f2, o->f3); break;
        case OP_CFLOAT_PRE: serialize_write_compressed_float_precomputed(&w, o->f4, o->cmax, o->cbits, o->cdelta, o->f1); break;
        case OP_BYTES: serialize_write_bytes(&w, o->buf, o->len); break;
        case OP_STRING: serialize_write_string(&w, (const char *)o->buf, o->bufsize); break;
        case OP_ALIGN: serialize_write_align(&w); break;
        case OP_END: serialize_write_end(&w); break;
        case OP_OBJECT:
            serialize_write_bool(&w, 1);
            serialize_write_int(&w, 3, 0, 7);
            serialize_write_uint16(&w, 42);
            break;
        }
        switch (o->kind) {
        case OP_INT: {
            U128 span; span.lo = (uint32_t)o->max - (uint32_t)o->min; span.hi = 0;
            record_ranged(p, o->kind, span, bstart);
            break;
        }
        case OP_INT64:
        case OP_I128: {
            U128 span; span.lo = (uint64_t)o->max - (uint64_t)o->min; span.hi = 0;
            record_ranged(p, o->kind, span, bstart);
            break;
        }
        case OP_FIXED32:
        case OP_FIXED64:
        case OP_FIXED128: {
            U128 span = u128_sub(fixed_raw_bound(o->max, o->frac), fixed_raw_bound(o->min, o->frac));
            record_ranged(p, o->kind, span, bstart);
            break;
        }
        case OP_FLOAT:
            record_field(p, o->kind, bstart + 23, 8, 0xFF);
            break;
        case OP_DOUBLE:
            record_field(p, o->kind, bstart + 52, 11, 0x7FF);
            break;
        case OP_STRING:
            if (o->len > 0) {
                /* the payload starts at the byte boundary after the length */
                int64_t payload = (bstart + serialize_bits_required(0, o->bufsize - 1) + 7) / 8 * 8;
                record_field(p, o->kind, payload + 8 * (p->id % o->len), 8, (p->id & 1) ? 0xFF : 0x00);
            }
            break;
        }
    }
    serialize_write_flush(&w);
    if (serialize_write_error(&w)) return -1;
    return (int)serialize_write_bytes_processed(&w);
}

/* ------------------------------------------------------------- reader --- */

typedef struct {
    int accept;
    int refstep;
    char reason[32];
    int64_t consumed;
    int terminal;
    int ntok[MAXOPS + 1];
    char tok[MAXOPS + 1][MAXTOK][TOKLEN];
} ReadResult;

static void tok_u64(char *out, uint64_t v) { snprintf(out, TOKLEN, "%016" PRIx64, v); }
static void tok_i64(char *out, int64_t v) { tok_u64(out, (uint64_t)v); }
static void tok_u128(char *out, uint64_t hi, uint64_t lo) {
    snprintf(out, TOKLEN, "%016" PRIx64 "%016" PRIx64, hi, lo);
}
static void tok_hexbytes(char *out, const unsigned char *p, int n) {
    if (n == 0) { strcpy(out, "-"); return; }
    for (int i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
    out[2 * n] = 0;
}

static int read_program(const unsigned char *bytes, int nbytes, Program *p, ReadResult *r) {
    unsigned char data[BUFCAP + 8];
    memset(data, 0, sizeof(data));
    if (nbytes > BUFCAP) return -1;
    memcpy(data, bytes, (size_t)nbytes);
    serialize_read_stream_t rd;
    serialize_read_stream_init_padded(&rd, data, (int)sizeof(data), data, nbytes);
    memset(r, 0, sizeof(*r));
    r->refstep = p->nops;
    for (int i = 0; i < p->nops; i++) {
        Op *o = &p->ops[i];
        int ok = 0;
        switch (o->kind) {
        case OP_BITS: { uint32_t v = 0; ok = serialize_read_bits(&rd, &v, o->bits); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_BITS64: { uint64_t v = 0; ok = serialize_read_bits64(&rd, &v, o->bits); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_BOOL: { int v = 0; ok = serialize_read_bool(&rd, &v); if (ok) strcpy(r->tok[i][0], v ? "1" : "0"); break; }
        case OP_U8: { uint8_t v = 0; ok = serialize_read_uint8(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U16: { uint16_t v = 0; ok = serialize_read_uint16(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U32: { uint32_t v = 0; ok = serialize_read_uint32(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U64: { uint64_t v = 0; ok = serialize_read_uint64(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_INT: { int32_t v = 0; ok = serialize_read_int(&rd, &v, (int32_t)o->min, (int32_t)o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_INT64: { int64_t v = 0; ok = serialize_read_int64(&rd, &v, o->min, o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_INT_REL: { int32_t v = 0; ok = serialize_read_int_relative(&rd, o->i1, &v); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_U128: { serialize_uint128_t v; ok = serialize_read_uint128(&rd, &v); if (ok) tok_u128(r->tok[i][0], v.hi, v.lo); break; }
        case OP_I128: {
            serialize_int128_t v;
            serialize_int128_t mn = serialize_int128_make((serialize_uint64_t)(o->min < 0 ? ~0ULL : 0), (serialize_uint64_t)o->min);
            serialize_int128_t mx = serialize_int128_make((serialize_uint64_t)(o->max < 0 ? ~0ULL : 0), (serialize_uint64_t)o->max);
            ok = serialize_read_int128(&rd, &v, mn, mx);
            if (ok) tok_u128(r->tok[i][0], v.hi, v.lo);
            break;
        }
        case OP_FLOAT: { float v = 0; ok = serialize_read_float(&rd, &v); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_DOUBLE: { double v = 0; ok = serialize_read_double(&rd, &v); if (ok) { uint64_t b; memcpy(&b, &v, 8); tok_u64(r->tok[i][0], b); } break; }
        case OP_FIXED32: { int32_t v = 0; ok = serialize_read_fixed32(&rd, &v, o->bits, o->frac, (int32_t)o->min, (int32_t)o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_FIXED64: { int64_t v = 0; ok = serialize_read_fixed64(&rd, &v, o->bits, o->frac, o->min, o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_FIXED128: {
            serialize_int128_t v;
            ok = serialize_read_fixed128(&rd, &v, o->bits, o->frac, o->min, o->max);
            if (ok) tok_u128(r->tok[i][0], v.hi, v.lo);
            break;
        }
        case OP_CFLOAT: { float v = 0; ok = serialize_read_compressed_float(&rd, &v, o->f1, o->f2, o->f3); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_CFLOAT_PRE: { float v = 0; ok = serialize_read_compressed_float_precomputed(&rd, &v, o->cmax, o->cbits, o->cdelta, o->f1); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_BYTES: {
            unsigned char tmp[64];
            memset(tmp, 0, sizeof(tmp));
            ok = serialize_read_bytes(&rd, tmp, o->len);
            if (ok) tok_hexbytes(r->tok[i][0], tmp, o->len);
            break;
        }
        case OP_STRING: {
            char tmp[128];
            memset(tmp, 0, sizeof(tmp));
            ok = serialize_read_string(&rd, tmp, o->bufsize);
            if (ok) tok_hexbytes(r->tok[i][0], (unsigned char *)tmp, (int)strlen(tmp));
            break;
        }
        case OP_ALIGN: ok = serialize_read_align(&rd); if (ok) r->ntok[i] = 0; break;
        case OP_END: ok = serialize_read_end(&rd); if (ok) r->ntok[i] = 0; break;
        case OP_OBJECT: {
            int b = 0, iv = 0; uint16_t uv = 0;
            ok = serialize_read_bool(&rd, &b);
            if (ok) ok = serialize_read_int(&rd, &iv, 0, 7);
            if (ok) ok = serialize_read_uint16(&rd, &uv);
            if (ok) {
                strcpy(r->tok[i][0], b ? "1" : "0");
                tok_i64(r->tok[i][1], iv);
                tok_u64(r->tok[i][2], uv);
            }
            break;
        }
        }
        if (!ok) {
            r->accept = 0;
            r->refstep = i;
            snprintf(r->reason, sizeof(r->reason), "%s", serialize_refusal_name(serialize_read_refusal(&rd)));
            r->consumed = (int64_t)serialize_read_bits_processed(&rd);
            {
                int extra = 0;
                r->terminal = serialize_read_bool(&rd, &extra) ? 0 : 1;
            }
            return 1;
        }
        if (o->kind != OP_ALIGN && o->kind != OP_END) {
            r->ntok[i] = o->kind == OP_OBJECT ? 3 : 1;
        }
    }
    r->accept = 1;
    r->refstep = p->nops;
    snprintf(r->reason, sizeof(r->reason), "none");
    r->consumed = (int64_t)serialize_read_bits_processed(&rd);
    r->terminal = -1;
    return 1;
}

/* The measure stream's bit count for one program (serialize.c measure
   half).  Align charges its worst case on both sides, so the counts are
   comparable even though they need not equal the written bit count. */
static int64_t measure_program(Program *p) {
    serialize_measure_stream_t m;
    serialize_measure_stream_init(&m);
    for (int i = 0; i < p->nops; i++) {
        Op *o = &p->ops[i];
        switch (o->kind) {
        case OP_BITS: serialize_measure_bits(&m, o->bits); break;
        case OP_BITS64: serialize_measure_bits64(&m, o->bits); break;
        case OP_BOOL: serialize_measure_bool(&m); break;
        case OP_U8: serialize_measure_uint8(&m); break;
        case OP_U16: serialize_measure_uint16(&m); break;
        case OP_U32: serialize_measure_uint32(&m); break;
        case OP_U64: serialize_measure_uint64(&m); break;
        case OP_INT: serialize_measure_int(&m, (int32_t)o->min, (int32_t)o->max); break;
        case OP_INT64: serialize_measure_int64(&m, o->min, o->max); break;
        case OP_INT_REL: serialize_measure_int_relative(&m, o->i1, o->i2); break;
        case OP_U128: serialize_measure_uint128(&m); break;
        case OP_I128:
            serialize_measure_int128(&m,
                serialize_int128_make((serialize_uint64_t)(o->min < 0 ? ~0ULL : 0), (serialize_uint64_t)o->min),
                serialize_int128_make((serialize_uint64_t)(o->max < 0 ? ~0ULL : 0), (serialize_uint64_t)o->max));
            break;
        case OP_FLOAT: serialize_measure_float(&m); break;
        case OP_DOUBLE: serialize_measure_double(&m); break;
        case OP_FIXED32: serialize_measure_fixed32(&m, o->bits, o->frac, (int32_t)o->min, (int32_t)o->max); break;
        case OP_FIXED64: serialize_measure_fixed64(&m, o->bits, o->frac, o->min, o->max); break;
        case OP_FIXED128: serialize_measure_fixed128(&m, o->bits, o->frac, o->min, o->max); break;
        case OP_CFLOAT: serialize_measure_compressed_float(&m, o->f1, o->f2, o->f3); break;
        case OP_CFLOAT_PRE: serialize_measure_compressed_float_precomputed(&m, o->cbits); break;
        case OP_BYTES: serialize_measure_bytes(&m, o->len); break;
        case OP_STRING: serialize_measure_string(&m, (const char *)o->buf, o->bufsize); break;
        case OP_ALIGN: serialize_measure_align(&m); break;
        case OP_END: serialize_measure_end(&m); break;
        case OP_OBJECT:
            serialize_measure_bool(&m);
            serialize_measure_int(&m, 0, 7);
            serialize_measure_uint16(&m);
            break;
        }
    }
    return (int64_t)serialize_measure_bits_processed(&m);
}

/* ---------------------------------------------------------- mutations --- */

/* Targets are chosen independently of the base generator's stream, so adding
   them does not perturb the programs and mutants it already covers. */
static int targeted_kind[OP_KINDS + 1];

static void set_bits_le(unsigned char *buf, int bit, int width, uint64_t value, uint64_t value_hi) {
    for (int k = 0; k < width; k++) {
        int b = bit + k;
        unsigned char mask = (unsigned char)(1u << (b & 7));
        uint64_t bit_value = k < 64 ? ((value >> k) & 1) : ((value_hi >> (k - 64)) & 1);
        if (bit_value) buf[b >> 3] |= mask;
        else buf[b >> 3] &= (unsigned char)~mask;
    }
}

/* Rewrite one ranged field's offset one past its span: serialize.c's reader
   refuses there, so the mutant exercises the reader's range check rather than
   only truncation and string framing (STANDARD.md, int; DESIGN.md (c)).
   Kinds are visited least-used first so every ranged kind is reached. */
static int make_targeted_mutant(Program *p) {
    int best = -1;
    for (int k = 0; k < p->nranged; k++) {
        if (best < 0 || targeted_kind[p->rkind[k]] < targeted_kind[p->rkind[best]])
            best = k;
    }
    if (best < 0) return 0;
    memcpy(p->mutant, p->bytes, (size_t)p->nbytes);
    p->nmutant = p->nbytes;
    set_bits_le(p->mutant, p->rstart[best], p->rwidth[best], p->rtarget[best], p->rtarget_hi[best]);
    targeted_kind[p->rkind[best]]++;
    return 1;
}

static int make_mutant(Program *p) {
    p->nmutant = p->nbytes;
    memcpy(p->mutant, p->bytes, (size_t)p->nbytes);
    int kind = (int)rnd(3);
    if (kind == 0) {
        int flips = 1 + (int)rnd(4);
        for (int k = 0; k < flips && p->nbytes > 0; k++) {
            int bit = (int)rnd((uint32_t)(p->nbytes * 8));
            p->mutant[bit >> 3] ^= (unsigned char)(1u << (bit & 7));
        }
    } else if (kind == 1) {
        p->nmutant = (int)rnd((uint32_t)(p->nbytes + 1));
    } else {
        int extra = 1 + (int)rnd(4);
        for (int k = 0; k < extra; k++) p->mutant[p->nmutant++] = (unsigned char)rng_next();
    }
    /* Half the mutants keep their random mutation (bit flips, truncation, or
       appended bytes that reach the end's trailing_data); the other half are
       targeted.  The split is by id, so the generator stream is untouched. */
    if (p->id & 2) return 0;
    return make_targeted_mutant(p);
}

/* ----------------------------------------------------------- encoding --- */

static void hex_encode(char *out, const unsigned char *p, int n) {
    if (n == 0) { strcpy(out, "-"); return; }
    for (int i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
    out[2 * n] = 0;
}


static void write_op_line(FILE *f, const Op *o) {
    switch (o->kind) {
    case OP_BITS: fprintf(f, "bits %d %" PRIu64 "\n", o->bits, o->u); break;
    case OP_BITS64: fprintf(f, "bits64 %d %016" PRIx64 "\n", o->bits, o->u); break;
    case OP_BOOL: fprintf(f, "bool %" PRIu64 "\n", o->u); break;
    case OP_U8: fprintf(f, "uint8 %" PRIu64 "\n", o->u); break;
    case OP_U16: fprintf(f, "uint16 %" PRIu64 "\n", o->u); break;
    case OP_U32: fprintf(f, "uint32 %" PRIu64 "\n", o->u); break;
    case OP_U64: fprintf(f, "uint64 %016" PRIx64 "\n", o->u); break;
    case OP_INT: fprintf(f, "int %" PRId64 " %" PRId64 " %" PRId64 "\n", o->min, o->max, o->s); break;
    case OP_INT64: fprintf(f, "int64 %" PRId64 " %" PRId64 " %" PRId64 "\n", o->min, o->max, o->s); break;
    case OP_INT_REL: fprintf(f, "int_rel %d %d\n", o->i1, o->i2); break;
    case OP_U128: fprintf(f, "uint128 %016" PRIx64 " %016" PRIx64 "\n", o->u, o->u2); break;
    case OP_I128:
        fprintf(f, "int128 %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 "\n",
            (uint64_t)o->min, (uint64_t)(o->min < 0 ? ~0ULL : 0),
            (uint64_t)o->max, (uint64_t)(o->max < 0 ? ~0ULL : 0),
            o->u, o->u2);
        break;
    case OP_FLOAT: fprintf(f, "float %08" PRIx32 "\n", (uint32_t)o->u); break;
    case OP_DOUBLE: fprintf(f, "double %016" PRIx64 "\n", o->u); break;
    case OP_FIXED32: fprintf(f, "fixed32 %d %d %" PRId64 " %" PRId64 " %" PRId64 "\n", o->bits, o->frac, o->min, o->max, o->s); break;
    case OP_FIXED64: fprintf(f, "fixed64 %d %d %" PRId64 " %" PRId64 " %" PRId64 "\n", o->bits, o->frac, o->min, o->max, o->s); break;
    case OP_FIXED128:
        fprintf(f, "fixed128 %d %d %" PRId64 " %" PRId64 " %016" PRIx64 " %016" PRIx64 "\n",
            o->bits, o->frac, o->min, o->max, o->u, o->u2);
        break;
    case OP_CFLOAT: fprintf(f, "cfloat %08" PRIx32 " %08" PRIx32 " %08" PRIx32 " %08" PRIx32 "\n",
        f32_bits(o->f1), f32_bits(o->f2), f32_bits(o->f3), f32_bits(o->f4)); break;
    case OP_CFLOAT_PRE: fprintf(f, "cfloat_pre %" PRIu32 " %d %08" PRIx32 " %08" PRIx32 " %08" PRIx32 "\n",
        o->cmax, o->cbits, f32_bits(o->cdelta), f32_bits(o->f1), f32_bits(o->f4)); break;
    case OP_BYTES: {
        char hx[256]; hex_encode(hx, o->buf, o->len);
        fprintf(f, "bytes %d %s\n", o->len, hx);
        break;
    }
    case OP_STRING: {
        char hx[256]; hex_encode(hx, o->buf, o->len);
        fprintf(f, "string %d %s\n", o->bufsize, hx);
        break;
    }
    case OP_ALIGN: fprintf(f, "align\n"); break;
    case OP_END: fprintf(f, "end\n"); break;
    case OP_OBJECT: fprintf(f, "object\n"); break;
    }
}

/* -------------------------------------------------- child process I/O --- */

/* The driver is an executable goose build made from fuzz/fuzz_driver.goose:
   driver <batch> <output>.  Its stdout and stderr pass through, so a Goose
   runtime error (an abort, or a --debug overflow or bounds check) names its
   line in the log and fails the batch. */
static int run_driver(const char *driver, const char *batch, const char *out) {
    fflush(stdout);
    fflush(stderr);
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return -1; }
    if (pid == 0) {
        execl(driver, driver, batch, out, (char *)NULL);
        perror("execl goose driver");
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) { perror("waitpid"); return -1; }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "goose driver child failed (status %d)\n", status);
        return -1;
    }
    return 0;
}

typedef struct {
    int seen;
    unsigned char wbytes[BUFCAP + 8];
    int nw;
    int wok;
    int64_t measure;
    int measure_ok;
    ReadResult c, m;
} GooseOut;

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int hex_decode(const char *s, unsigned char *out, int cap) {
    if (strcmp(s, "-") == 0) return 0;
    int n = (int)strlen(s) / 2;
    if (n > cap) return -1;
    for (int i = 0; i < n; i++) {
        int hi = hex_digit(s[2 * i]), lo = hex_digit(s[2 * i + 1]);
        if (hi < 0 || lo < 0) return -1;
        out[i] = (unsigned char)((hi << 4) | lo);
    }
    return n;
}

static int parse_out(const char *path, GooseOut *outs, int nprog, int base) {
    FILE *f = fopen(path, "r");
    if (!f) { perror("open goose driver output"); return -1; }
    char line[8192];
    int rc = 0;
    while (fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = 0;
        char *save = NULL;
        char *tag = strtok_r(line, " ", &save);
        if (!tag) continue;
        if (strcmp(tag, "W") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *hex = strtok_r(NULL, " ", &save);
            char *ok = strtok_r(NULL, " ", &save);
            if (!ids || !hex || !ok) { rc = -1; break; }
            int id = atoi(ids) - base;
            if (id < 0 || id >= nprog) { rc = -1; break; }
            int n = hex_decode(hex, outs[id].wbytes, BUFCAP);
            if (n < 0) { rc = -1; break; }
            outs[id].nw = n;
            outs[id].wok = atoi(ok);
            outs[id].seen |= 1;
        } else if (strcmp(tag, "M") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *bits = strtok_r(NULL, " ", &save);
            char *ok = strtok_r(NULL, " ", &save);
            if (!ids || !bits || !ok) { rc = -1; break; }
            int id = atoi(ids) - base;
            if (id < 0 || id >= nprog) { rc = -1; break; }
            outs[id].measure = strtoll(bits, NULL, 10);
            outs[id].measure_ok = atoi(ok);
            outs[id].seen |= 8;
        } else if (strcmp(tag, "R") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *src = strtok_r(NULL, " ", &save);
            char *acc = strtok_r(NULL, " ", &save);
            char *st = strtok_r(NULL, " ", &save);
            char *why = strtok_r(NULL, " ", &save);
            char *cons = strtok_r(NULL, " ", &save);
            char *term = strtok_r(NULL, " ", &save);
            if (!ids || !src || !acc || !st || !why || !cons || !term) { rc = -1; break; }
            int id = atoi(ids) - base;
            if (id < 0 || id >= nprog) { rc = -1; break; }
            ReadResult *r = (src[0] == 'c') ? &outs[id].c : &outs[id].m;
            r->accept = atoi(acc);
            r->refstep = atoi(st);
            snprintf(r->reason, sizeof(r->reason), "%s", why);
            r->consumed = strtoll(cons, NULL, 10);
            r->terminal = atoi(term);
            if (src[0] == 'c') outs[id].seen |= 2; else outs[id].seen |= 4;
        } else if (strcmp(tag, "V") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *src = strtok_r(NULL, " ", &save);
            char *idx = strtok_r(NULL, " ", &save);
            if (!ids || !src || !idx) { rc = -1; break; }
            int id = atoi(ids) - base;
            int i = atoi(idx);
            if (id < 0 || id >= nprog || i < 0 || i > MAXOPS) { rc = -1; break; }
            ReadResult *r = (src[0] == 'c') ? &outs[id].c : &outs[id].m;
            int k = 0;
            char *tok;
            while ((tok = strtok_r(NULL, " ", &save)) != NULL && k < MAXTOK) {
                snprintf(r->tok[i][k], TOKLEN, "%s", tok);
                k++;
            }
            r->ntok[i] = k;
        }
    }
    fclose(f);
    return rc;
}

/* ----------------------------------------------------------- compare --- */

static void print_program(FILE *f, Program *p, int widen) {
    (void)widen;
    fprintf(f, "program %d (%d ops)\n", p->id, p->nops);
    for (int i = 0; i < p->nops; i++) {
        /* write_op_line writes against a FILE; reuse via tmpfile-free approach */
        fprintf(f, "  op %d ", i);
        switch (p->ops[i].kind) {
        case OP_BITS: fprintf(f, "bits %d %" PRIu64, p->ops[i].bits, p->ops[i].u); break;
        case OP_BITS64: fprintf(f, "bits64 %d %016" PRIx64, p->ops[i].bits, p->ops[i].u); break;
        case OP_BOOL: fprintf(f, "bool %" PRIu64, p->ops[i].u); break;
        case OP_U8: fprintf(f, "uint8 %" PRIu64, p->ops[i].u); break;
        case OP_U16: fprintf(f, "uint16 %" PRIu64, p->ops[i].u); break;
        case OP_U32: fprintf(f, "uint32 %" PRIu64, p->ops[i].u); break;
        case OP_U64: fprintf(f, "uint64 %016" PRIx64, p->ops[i].u); break;
        case OP_INT: fprintf(f, "int %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_INT64: fprintf(f, "int64 %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_INT_REL: fprintf(f, "int_rel %d %d", p->ops[i].i1, p->ops[i].i2); break;
        case OP_U128: fprintf(f, "uint128 %016" PRIx64 " %016" PRIx64, p->ops[i].u, p->ops[i].u2); break;
        case OP_I128: fprintf(f, "int128 %" PRId64 " %" PRId64 " %" PRId64 " %016" PRIx64, p->ops[i].min, p->ops[i].max, p->ops[i].s, p->ops[i].u); break;
        case OP_FLOAT: fprintf(f, "float %08" PRIx32, (uint32_t)p->ops[i].u); break;
        case OP_DOUBLE: fprintf(f, "double %016" PRIx64, p->ops[i].u); break;
        case OP_FIXED32: fprintf(f, "fixed32 %d %d %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].bits, p->ops[i].frac, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_FIXED64: fprintf(f, "fixed64 %d %d %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].bits, p->ops[i].frac, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_FIXED128: fprintf(f, "fixed128 %d %d %" PRId64 " %" PRId64 " %016" PRIx64 " %016" PRIx64, p->ops[i].bits, p->ops[i].frac, p->ops[i].min, p->ops[i].max, p->ops[i].u, p->ops[i].u2); break;
        case OP_CFLOAT: fprintf(f, "cfloat %08" PRIx32 " %08" PRIx32 " %08" PRIx32 " %08" PRIx32, f32_bits(p->ops[i].f1), f32_bits(p->ops[i].f2), f32_bits(p->ops[i].f3), f32_bits(p->ops[i].f4)); break;
        case OP_CFLOAT_PRE: fprintf(f, "cfloat_pre %" PRIu32 " %d", p->ops[i].cmax, p->ops[i].cbits); break;
        case OP_BYTES: { char hx[256]; hex_encode(hx, p->ops[i].buf, p->ops[i].len); fprintf(f, "bytes %d %s", p->ops[i].len, hx); break; }
        case OP_STRING: { char hx[256]; hex_encode(hx, p->ops[i].buf, p->ops[i].len); fprintf(f, "string %d %s", p->ops[i].bufsize, hx); break; }
        case OP_ALIGN: fprintf(f, "align"); break;
        case OP_END: fprintf(f, "end"); break;
        case OP_OBJECT: fprintf(f, "object"); break;
        }
        fprintf(f, "\n");
    }
}

static int compare_read(const char *what, Program *p, ReadResult *exp, ReadResult *got, int *failed) {
    if (exp->accept != got->accept) {
        fprintf(stderr, "%s: accept mismatch (C %d, Goose %d)\n", what, exp->accept, got->accept);
        *failed = 1;
        return 0;
    }
    if (!exp->accept && exp->refstep != got->refstep) {
        fprintf(stderr, "%s: refusal step mismatch (C %d, Goose %d)\n", what, exp->refstep, got->refstep);
        *failed = 1;
        return 0;
    }
    if (strcmp(exp->reason, got->reason) != 0) {
        fprintf(stderr, "%s: refusal reason mismatch (C %s, Goose %s)\n", what, exp->reason, got->reason);
        *failed = 1;
        return 0;
    }
    if (exp->accept && exp->consumed != got->consumed) {
        fprintf(stderr, "%s: consumed bits mismatch (C %" PRId64 ", Goose %" PRId64 ")\n", what, exp->consumed, got->consumed);
        *failed = 1;
        return 0;
    }
    if (!exp->accept && exp->terminal != got->terminal) {
        fprintf(stderr, "%s: terminal mismatch (C %d, Goose %d)\n", what, exp->terminal, got->terminal);
        *failed = 1;
        return 0;
    }
    int upto = exp->accept ? p->nops : exp->refstep;
    for (int i = 0; i < upto; i++) {
        if (exp->ntok[i] != got->ntok[i]) {
            fprintf(stderr, "%s: op %d token count mismatch (C %d, Goose %d)\n", what, i, exp->ntok[i], got->ntok[i]);
            *failed = 1;
            return 0;
        }
        for (int k = 0; k < exp->ntok[i]; k++) {
            if (strcmp(exp->tok[i][k], got->tok[i][k]) != 0) {
                fprintf(stderr, "%s: op %d value %d mismatch (C %s, Goose %s)\n",
                    what, i, k, exp->tok[i][k], got->tok[i][k]);
                *failed = 1;
                return 0;
            }
        }
    }
    return 1;
}

/* How many mutants the oracle refused, per reason: the PASS line prints them,
   so a run that stops reaching a rule shows it. */
static int refused_by_reason[SERIALIZE_REFUSAL_NON_CANONICAL + 1];

static void count_reason(const char *reason) {
    for (int k = 1; k <= (int)SERIALIZE_REFUSAL_NON_CANONICAL; k++) {
        if (strcmp(reason, serialize_refusal_name((serialize_refusal_t)k)) == 0) refused_by_reason[k]++;
    }
}

/* Returns 0 when two result files are byte-identical, else the 1-based
   number of the first differing line. */
static int files_first_diff(const char *a, const char *b) {
    FILE *fa = fopen(a, "rb"), *fb = fopen(b, "rb");
    if (!fa || !fb) { if (fa) fclose(fa); if (fb) fclose(fb); return 1; }
    char la[8192], lb[8192];
    int line = 0, diff = 0;
    for (;;) {
        char *ra = fgets(la, sizeof(la), fa);
        char *rb = fgets(lb, sizeof(lb), fb);
        if (!ra && !rb) break;
        line++;
        if (!ra || !rb || strcmp(la, lb) != 0) { diff = line; break; }
    }
    fclose(fa);
    fclose(fb);
    return diff;
}

static int run_batch(const char *driver, const char *driver_opt, const char *tmpdir,
                     Program *progs, int nprog, int widen, int *widen_done,
                     int *targeted) {
    char batch[4096], out[4096], hex[BUFCAP * 2 + 8];
    snprintf(batch, sizeof(batch), "%s/batch.txt", tmpdir);
    snprintf(out, sizeof(out), "%s/result.txt", tmpdir);

    FILE *f = fopen(batch, "w");
    if (!f) { perror("fopen batch"); return -1; }
    int total_mutants = 0;
    for (int i = 0; i < nprog; i++) {
        Program *p = &progs[i];
        p->nbytes = write_program(p, p->bytes, BUFCAP, widen, widen_done);
        if (p->nbytes < 0) {
            fprintf(stderr, "C writer failed on program %d (a generated program is invalid)\n", p->id);
            fclose(f);
            return -1;
        }
        if (p->has_mutant) { if (make_mutant(p)) (*targeted)++; total_mutants++; }
        hex_encode(hex, p->bytes, p->nbytes);
        char mh[BUFCAP * 2 + 8];
        hex_encode(mh, p->mutant, p->nmutant);
        fprintf(f, "P %d %d %d %s %s\n", p->id, p->nops, p->has_mutant ? 1 : 0, hex, p->has_mutant ? mh : "-");
        for (int k = 0; k < p->nops; k++) write_op_line(f, &p->ops[k]);
    }
    fclose(f);

    if (run_driver(driver, batch, out) != 0) return -1;

    if (driver_opt) {
        char out_opt[4096];
        snprintf(out_opt, sizeof(out_opt), "%s/result-opt.txt", tmpdir);
        if (run_driver(driver_opt, batch, out_opt) != 0) return -1;
        int diff = files_first_diff(out, out_opt);
        if (diff != 0) {
            fprintf(stderr, "optimized driver output differs from debug driver output (first differing line %d)\n", diff);
            return -1;
        }
    }

    GooseOut *outs = calloc((size_t)nprog, sizeof(GooseOut));
    if (!outs) { fprintf(stderr, "out of memory\n"); return -1; }
    if (parse_out(out, outs, nprog, progs[0].id) != 0) {
        fprintf(stderr, "could not parse Goose output\n");
        return -1;
    }

    int failed = 0;
    for (int i = 0; i < nprog; i++) {
        Program *p = &progs[i];
        GooseOut *lo = &outs[i];
        if (!(lo->seen & 1) || !(lo->seen & 2) || !(lo->seen & 8) || (p->has_mutant && !(lo->seen & 4))) {
            fprintf(stderr, "program %d: missing Goose output (seen %d)\n", p->id, lo->seen);
            failed = 1;
            continue;
        }
        {
            int64_t want_measure = measure_program(p);
            if (!lo->measure_ok || lo->measure != want_measure) {
                fprintf(stderr, "program %d: measure mismatch (C %" PRId64 ", Goose %" PRId64 ")\n", p->id, want_measure, lo->measure);
                print_program(stderr, p, widen);
                failed = 1;
                continue;
            }
        }
        if (lo->nw != p->nbytes || memcmp(lo->wbytes, p->bytes, (size_t)p->nbytes) != 0) {
            fprintf(stderr, "program %d: write bytes differ\n", p->id);
            print_program(stderr, p, widen);
            char a[BUFCAP * 2 + 8], b[BUFCAP * 2 + 8];
            hex_encode(a, p->bytes, p->nbytes);
            hex_encode(b, lo->wbytes, lo->nw);
            fprintf(stderr, "  C:       %s\n  Goose: %s\n", a, b);
            failed = 1;
            continue;
        }
        ReadResult expc, expm;
        if (read_program(p->bytes, p->nbytes, p, &expc) != 1) { failed = 1; continue; }
        if (!compare_read("own bytes", p, &expc, &lo->c, &failed)) {
            print_program(stderr, p, widen);
        }
        if (p->has_mutant) {
            if (read_program(p->mutant, p->nmutant, p, &expm) != 1) { failed = 1; continue; }
            if (!expm.accept) count_reason(expm.reason);
            if (!compare_read("mutant", p, &expm, &lo->m, &failed)) {
                print_program(stderr, p, widen);
                char a[BUFCAP * 2 + 8];
                hex_encode(a, p->mutant, p->nmutant);
                fprintf(stderr, "  mutant: %s\n", a);
            }
        }
        if (failed) break;
    }
    free(outs);
    return failed ? -1 : total_mutants;
}

/* --------------------------------------------------------------- main --- */

int main(int argc, char **argv) {
    const char *driver = NULL, *driver_opt = NULL, *tmpbase = NULL;
    int negative = 0;
    int programs = 2000;
    long duration = 0;
    uint64_t seed = 0x9e3779b97f4a7c15ULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--driver") == 0 && i + 1 < argc) driver = argv[++i];
        else if (strcmp(argv[i], "--driver-opt") == 0 && i + 1 < argc) driver_opt = argv[++i];
        else if (strcmp(argv[i], "--tmp") == 0 && i + 1 < argc) tmpbase = argv[++i];
        else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) seed = strtoull(argv[++i], NULL, 0);
        else if (strcmp(argv[i], "--programs") == 0 && i + 1 < argc) programs = atoi(argv[++i]);
        else if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) duration = atol(argv[++i]);
        else if (strcmp(argv[i], "--negative-control") == 0) negative = 1;
        else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 2; }
    }
    if (!driver || !tmpbase || programs <= 0 || duration < 0) {
        fprintf(stderr, "usage: host --driver <goose driver executable> [--driver-opt <optimized driver>] --tmp <dir> [--seed N] [--programs N | --duration SECONDS] [--negative-control]\n");
        return 2;
    }
    char tmpl[4096];
    snprintf(tmpl, sizeof(tmpl), "%s/workXXXXXX", tmpbase);
    if (!mkdtemp(tmpl)) { perror("mkdtemp"); return 1; }

    rng_state = seed;
    printf("RUN TestDifferentialAgainstSerializeC (seed 0x%016" PRIx64 ", %s %ld)\n", seed,
        duration > 0 ? "seconds" : "programs", duration > 0 ? duration : (long)programs);
    fflush(stdout);

    time_t started = time(NULL);
    int widen_done = 0;
    int mutant_count = 0, targeted_count = 0, fail = 0, total = 0;
    static Program progs[BATCH];
    for (int start = 0; ; start += BATCH) {
        int n = BATCH;
        if (duration > 0) {
            if (start > 0 && (long)(time(NULL) - started) >= duration) break;
            if (start > INT32_MAX - 2 * BATCH) break;
        } else {
            if (start >= programs) break;
            if (n > programs - start) n = programs - start;
        }
        for (int i = 0; i < n; i++) gen_program(&progs[i], start + i);
        int m = run_batch(driver, driver_opt, tmpl, progs, n, negative, &widen_done, &targeted_count);
        if (m < 0) { fail = 1; break; }
        mutant_count += m;
        total += n;
    }

    if (fail) {
        printf("failing batch kept in %s (batch.txt, result.txt); replay with --seed 0x%016" PRIx64 "\n", tmpl, seed);
        printf("--- FAIL TestDifferentialAgainstSerializeC\n");
        return 1;
    }
    if (total >= 2000) {
        int missing = 0;
        static const int want_widths[] = { 31, 32, 33, 63, 64, 65, 95, 96, 97, 127, 128 };
        for (int k = 0; k < 3; k++) {
            if (cov_frac_zero[k] == 0) { printf("fixed coverage missing: fixed kind %d fraction zero\n", k); missing = 1; }
            if (cov_frac_nonzero[k] == 0) { printf("fixed coverage missing: fixed kind %d fraction nonzero\n", k); missing = 1; }
            if (cov_degenerate[k] == 0) { printf("fixed coverage missing: fixed kind %d degenerate range\n", k); missing = 1; }
        }
        for (size_t k = 0; k < sizeof(want_widths) / sizeof(want_widths[0]); k++) {
            if (cov_width[want_widths[k]] == 0) { printf("fixed coverage missing: encoded width %d bits\n", want_widths[k]); missing = 1; }
        }
        if (cov_edge_min == 0) { printf("fixed coverage missing: raw value at raw_min\n"); missing = 1; }
        if (cov_edge_min_plus == 0) { printf("fixed coverage missing: raw value one step above raw_min\n"); missing = 1; }
        if (cov_edge_max_minus == 0) { printf("fixed coverage missing: raw value one step below raw_max\n"); missing = 1; }
        if (cov_edge_max == 0) { printf("fixed coverage missing: raw value at raw_max\n"); missing = 1; }
        if (cov_storage_extreme == 0) { printf("fixed coverage missing: raw value at a storage extreme\n"); missing = 1; }
        if (missing) {
            printf("--- FAIL TestDifferentialAgainstSerializeC\n");
            return 1;
        }
    }
    printf("fixed coverage: fixed32 f0=%ld fnz=%ld deg=%ld; fixed64 f0=%ld fnz=%ld deg=%ld; fixed128 f0=%ld fnz=%ld deg=%ld; widths 31=%ld 32=%ld 33=%ld 63=%ld 64=%ld 65=%ld 95=%ld 96=%ld 97=%ld 127=%ld 128=%ld; edges min=%ld min+1=%ld max-1=%ld max=%ld storage-extreme=%ld\n",
        cov_frac_zero[0], cov_frac_nonzero[0], cov_degenerate[0],
        cov_frac_zero[1], cov_frac_nonzero[1], cov_degenerate[1],
        cov_frac_zero[2], cov_frac_nonzero[2], cov_degenerate[2],
        cov_width[31], cov_width[32], cov_width[33], cov_width[63], cov_width[64], cov_width[65],
        cov_width[95], cov_width[96], cov_width[97], cov_width[127], cov_width[128],
        cov_edge_min, cov_edge_min_plus, cov_edge_max_minus, cov_edge_max, cov_storage_extreme);
    char rmcmd[4200];
    snprintf(rmcmd, sizeof(rmcmd), "%s/batch.txt", tmpl);
    remove(rmcmd);
    snprintf(rmcmd, sizeof(rmcmd), "%s/result.txt", tmpl);
    remove(rmcmd);
    snprintf(rmcmd, sizeof(rmcmd), "%s/result-opt.txt", tmpl);
    remove(rmcmd);
    rmdir(tmpl);
    printf("--- PASS TestDifferentialAgainstSerializeC: seed 0x%016" PRIx64 ", %d programs, %d mutants (%d targeted at ranged offsets, float exponents and string bytes); mutants refused by reason:", seed, total, mutant_count, targeted_count);
    for (int k = 1; k <= (int)SERIALIZE_REFUSAL_NON_CANONICAL; k++) {
        if (refused_by_reason[k] > 0) printf(" %s %d", serialize_refusal_name((serialize_refusal_t)k), refused_by_reason[k]);
    }
    printf("\n");
    return 0;
}
