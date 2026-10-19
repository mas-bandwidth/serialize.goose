// serialize_bytes.goose -- bytes, string and wstring (STANDARD.md, bytes,
// string, wstring; DESIGN.md (a), (d), (e)). Strings are Goose's own: UTF-8
// bytes. Writes take a const u8[:]; a string read takes any u8 builder
// (u8[>..] or u8[..k]) by reference, cleared and filled only on success.
// Card serialize-goose-strings fills this file. Every function is a stub
// with its final signature.

import .serialize_stream;
import .serialize_int;

// bytes: align, then data.len raw bytes; the count is not transmitted.
fn serialize_bytes(s: WriteStream&, data: const u8[:]) -> bool { abort("serialize: serialize_bytes not implemented"); }
fn serialize_bytes(s: ReadStream&, data: u8[:]) -> bool { abort("serialize: serialize_bytes not implemented"); }
fn serialize_bytes(s: MeasureStream&, data: const u8[:]) -> bool { abort("serialize: serialize_bytes not implemented"); }

// string: int(length, 0, buffer_size - 1), then the bytes (which align).
fn serialize_string(s: WriteStream&, value: const u8[:], buffer_size: i64) -> bool { abort("serialize: serialize_string not implemented"); }
fn serialize_string<T>(s: ReadStream&, value: T&, buffer_size: i64) -> bool { abort("serialize: serialize_string not implemented"); }
fn serialize_string(s: MeasureStream&, value: const u8[:], buffer_size: i64) -> bool { abort("serialize: serialize_string not implemented"); }

// wstring: int(units, 0, buffer_size - 1), then each UTF-16 code unit as a 32-bit group, no align.
fn serialize_wstring(s: WriteStream&, value: const u8[:], buffer_size: i64) -> bool { abort("serialize: serialize_wstring not implemented"); }
fn serialize_wstring<T>(s: ReadStream&, value: T&, buffer_size: i64) -> bool { abort("serialize: serialize_wstring not implemented"); }
fn serialize_wstring(s: MeasureStream&, value: const u8[:], buffer_size: i64) -> bool { abort("serialize: serialize_wstring not implemented"); }
