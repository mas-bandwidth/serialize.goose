// serialize_float.goose -- float and double as their bit patterns (STANDARD.md,
// float, double; DESIGN.md (c), the float-bits route: bytes_of over a
// one-element array out, from_bytes back in, measured on the bench). Card
// serialize-goose-floats fills this file. Every function is a stub with its
// final signature.

import .serialize_stream;

fn serialize_f32_bits(value: f32) -> u32 { abort("serialize: serialize_f32_bits not implemented"); }
fn serialize_f32_from_bits(bits: u32) -> f32 { abort("serialize: serialize_f32_from_bits not implemented"); }
fn serialize_f64_bits(value: f64) -> u64 { abort("serialize: serialize_f64_bits not implemented"); }
fn serialize_f64_from_bits(bits: u64) -> f64 { abort("serialize: serialize_f64_from_bits not implemented"); }

// float: the 32 bits of the IEEE 754 binary32 pattern.
fn serialize_float(s: WriteStream&, value: f32) -> bool { abort("serialize: serialize_float not implemented"); }
fn serialize_float(s: ReadStream&, value: f32&) -> bool { abort("serialize: serialize_float not implemented"); }
fn serialize_float(s: MeasureStream&, value: f32) -> bool { abort("serialize: serialize_float not implemented"); }

// double: the 64 bits of the binary64 pattern, low 32 first.
fn serialize_double(s: WriteStream&, value: f64) -> bool { abort("serialize: serialize_double not implemented"); }
fn serialize_double(s: ReadStream&, value: f64&) -> bool { abort("serialize: serialize_double not implemented"); }
fn serialize_double(s: MeasureStream&, value: f64) -> bool { abort("serialize: serialize_double not implemented"); }
