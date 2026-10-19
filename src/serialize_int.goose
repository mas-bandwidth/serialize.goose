// serialize_int.goose -- ranged integers and int_relative (STANDARD.md, int,
// int64, int_relative; DESIGN.md (a), (c), (e)). Card serialize-goose-integers
// fills this file. Every function below is a stub with its final signature.

import .serialize_stream;

// Bits needed for a value in [min,max] in the unsigned domain; 0 when
// min == max (STANDARD.md, int).
fn serialize_bits_required(min: u32, max: u32) -> i64 { abort("serialize: serialize_bits_required not implemented"); }
fn serialize_bits_required64(min: u64, max: u64) -> i64 { abort("serialize: serialize_bits_required64 not implemented"); }

// int: the offset value - min in bits_required(min, max) bits; min > max aborts.
fn serialize_int(s: WriteStream&, value: i32, min: i32, max: i32) -> bool { abort("serialize: serialize_int not implemented"); }
fn serialize_int(s: ReadStream&, value: i32&, min: i32, max: i32) -> bool { abort("serialize: serialize_int not implemented"); }
fn serialize_int(s: MeasureStream&, value: i32, min: i32, max: i32) -> bool { abort("serialize: serialize_int not implemented"); }

// int64: the same over 64 bits, low 32 first above 32 bits (STANDARD.md, int64).
fn serialize_int64(s: WriteStream&, value: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_int64 not implemented"); }
fn serialize_int64(s: ReadStream&, value: i64&, min: i64, max: i64) -> bool { abort("serialize: serialize_int64 not implemented"); }
fn serialize_int64(s: MeasureStream&, value: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_int64 not implemented"); }

// int_relative: the tier ladder over [0, 2^31 - 1], current > previous (STANDARD.md, int_relative).
fn serialize_int_relative(s: WriteStream&, previous: i32, current: i32) -> bool { abort("serialize: serialize_int_relative not implemented"); }
fn serialize_int_relative(s: ReadStream&, previous: i32, current: i32&) -> bool { abort("serialize: serialize_int_relative not implemented"); }
fn serialize_int_relative(s: MeasureStream&, previous: i32, current: i32) -> bool { abort("serialize: serialize_int_relative not implemented"); }
