# serialize.goose

A simple bitpacking serializer for [Goose](https://github.com/aardappel/goose), wire compatible with the C++ [serialize](https://github.com/mas-bandwidth/serialize) library and [serialize.c](https://github.com/mas-bandwidth/serialize.c): the same values produce the same bytes.

Status: every field kind of the C++ library is implemented (bits, bool, uint8 to uint128, ranged int, int64 and int128, int_relative, fixed, float, double, compressed_float, bytes, string, align, object, end), with unit tests per family. The wire format is serialize's STANDARD.md, format version 2.0, vendored verbatim with its conformance vectors and negative controls: the wire carries only integers and bytes, and every value has exactly one encoding. Every refusal names its reason (`serialize_refusal_name(serialize_error(r))`, for example `"past_end"`). The pinned compiler is Goose v2026.2 (commit 7ad96d6d47f9).

```goose
import .serialize;

struct Player { id: i32, x: f32, name: u8[..16] }

// One function over every stream: write, read and measure.
fn serialize<S>(s: S&, p: Player&) -> bool {
    return serialize_int(s, p.id, 0, 1023)
        && serialize_float(s, p.x)
        && serialize_string(s, p.name, 16);
}

// A packet is one object and its end: the end refuses trailing bytes and set
// padding, so one value has one byte sequence.
fn read_player(packet: const u8[:], destination: u8[:], p: Player&) -> bool {
    var r = serialize_read_stream_init_padded(destination, packet);
    return serialize(r, p) && serialize_end(r);
}
```

`make dist-goose` once, then `make test`, `make witnesses`, `make controls` and `make fuzz` (the differential against serialize.c). DESIGN.md is the contract.

BSD 3-Clause license.
