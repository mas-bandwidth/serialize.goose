// serialize_compressed_float.goose -- quantized floats (STANDARD.md,
// compressed_float; DESIGN.md (a), (c)). The arithmetic is f32 throughout, in
// serialize.c's order; a non-finite value on write aborts. Card
// serialize-goose-floats fills this file. Every function is a stub with its
// final signature.

import .serialize_stream;
import .serialize_float;

// The constants derived once (serialize.c serialize_compressed_float_params):
// max_integer_value, bits, delta.
fn serialize_compressed_float_params(min: f32, max: f32, res: f32) -> u32, i64, f32 {
    abort("serialize: serialize_compressed_float_params not implemented");
}

fn serialize_compressed_float(s: WriteStream&, value: f32, min: f32, max: f32, res: f32) -> bool { abort("serialize: serialize_compressed_float not implemented"); }
fn serialize_compressed_float(s: ReadStream&, value: f32&, min: f32, max: f32, res: f32) -> bool { abort("serialize: serialize_compressed_float not implemented"); }
fn serialize_compressed_float(s: MeasureStream&, value: f32, min: f32, max: f32, res: f32) -> bool { abort("serialize: serialize_compressed_float not implemented"); }

// The same wire from the precomputed constants (mas-bandwidth/schema#82).
fn serialize_compressed_float_precomputed(s: WriteStream&, value: f32, max_integer_value: u32, bits: i64, delta: f32, min: f32) -> bool { abort("serialize: serialize_compressed_float_precomputed not implemented"); }
fn serialize_compressed_float_precomputed(s: ReadStream&, value: f32&, max_integer_value: u32, bits: i64, delta: f32, min: f32) -> bool { abort("serialize: serialize_compressed_float_precomputed not implemented"); }
fn serialize_compressed_float_precomputed(s: MeasureStream&, value: f32, max_integer_value: u32, bits: i64, delta: f32, min: f32) -> bool { abort("serialize: serialize_compressed_float_precomputed not implemented"); }
