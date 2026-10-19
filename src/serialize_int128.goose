// serialize_int128.goose -- 128-bit integers as two u64 lanes (STANDARD.md,
// uint128, int128; DESIGN.md (c)). Card serialize-goose-integers fills this
// file. The types are final; every function is a stub with its final signature.

import .serialize_stream;

// bits 0..63 in lo, 64..127 in hi; Int128 is the same lanes read as two's
// complement (serialize.c serialize_uint128_t, serialize_int128_t).
struct Uint128 { lo: u64, hi: u64 }
struct Int128 { lo: u64, hi: u64 }

fn serialize_uint128_make(hi: u64, lo: u64) -> Uint128 { abort("serialize: serialize_uint128_make not implemented"); }
fn serialize_int128_make(hi: u64, lo: u64) -> Int128 { abort("serialize: serialize_int128_make not implemented"); }
// Sign-extends a 64-bit value into the 128-bit domain.
fn serialize_int128_from_int64(value: i64) -> Int128 { abort("serialize: serialize_int128_from_int64 not implemented"); }
fn serialize_uint128_equal(a: Uint128, b: Uint128) -> bool { abort("serialize: serialize_uint128_equal not implemented"); }
fn serialize_int128_equal(a: Int128, b: Int128) -> bool { abort("serialize: serialize_int128_equal not implemented"); }
// -1, 0 or 1, in the signed domain.
fn serialize_int128_compare(a: Int128, b: Int128) -> i64 { abort("serialize: serialize_int128_compare not implemented"); }

// uint128: always 128 bits, the low half first, each half as bits(half, 64).
fn serialize_uint128(s: WriteStream&, value: Uint128) -> bool { abort("serialize: serialize_uint128 not implemented"); }
fn serialize_uint128(s: ReadStream&, value: Uint128&) -> bool { abort("serialize: serialize_uint128 not implemented"); }
fn serialize_uint128(s: MeasureStream&, value: Uint128) -> bool { abort("serialize: serialize_uint128 not implemented"); }

// int128: ranged; where the range fits 64 bits the bytes equal int64 over the same bounds.
fn serialize_int128(s: WriteStream&, value: Int128, min: Int128, max: Int128) -> bool { abort("serialize: serialize_int128 not implemented"); }
fn serialize_int128(s: ReadStream&, value: Int128&, min: Int128, max: Int128) -> bool { abort("serialize: serialize_int128 not implemented"); }
fn serialize_int128(s: MeasureStream&, value: Int128, min: Int128, max: Int128) -> bool { abort("serialize: serialize_int128 not implemented"); }
