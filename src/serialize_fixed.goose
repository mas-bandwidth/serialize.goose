// serialize_fixed.goose -- Q-format fixed point (STANDARD.md, fixed;
// DESIGN.md (a), (c)). integer_bits + fraction_bits equals the storage width,
// min and max are whole units; a bad Q format or min > max aborts. Card
// serialize-goose-floats fills this file. Every function is a stub with its
// final signature.

import .serialize_stream;
import .serialize_int128;

fn serialize_fixed32(s: WriteStream&, value: i32, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool { abort("serialize: serialize_fixed32 not implemented"); }
fn serialize_fixed32(s: ReadStream&, value: i32&, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool { abort("serialize: serialize_fixed32 not implemented"); }
fn serialize_fixed32(s: MeasureStream&, value: i32, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool { abort("serialize: serialize_fixed32 not implemented"); }

fn serialize_fixed64(s: WriteStream&, value: i64, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed64 not implemented"); }
fn serialize_fixed64(s: ReadStream&, value: i64&, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed64 not implemented"); }
fn serialize_fixed64(s: MeasureStream&, value: i64, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed64 not implemented"); }

fn serialize_fixed128(s: WriteStream&, value: Int128, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed128 not implemented"); }
fn serialize_fixed128(s: ReadStream&, value: Int128&, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed128 not implemented"); }
fn serialize_fixed128(s: MeasureStream&, value: Int128, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool { abort("serialize: serialize_fixed128 not implemented"); }
