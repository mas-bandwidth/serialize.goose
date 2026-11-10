# serialize.goose

A simple bitpacking serializer for [Goose](https://github.com/aardappel/goose), wire compatible with the C++ [serialize](https://github.com/mas-bandwidth/serialize) library and [serialize.c](https://github.com/mas-bandwidth/serialize.c): the same values produce the same bytes.

Status: every field kind of the C++ library is implemented (bits, bool, uint8 to uint128, ranged int, int64 and int128, int_relative, fixed, float, double, compressed_float, bytes, string, align, object, end), with unit tests per family. The wire format is serialize's STANDARD.md, format version 2.0, vendored verbatim from serialize v2.1.4 with its conformance vectors and negative controls: the wire carries only integers and bytes, and every value has exactly one encoding. Every refusal names its reason (`serialize_refusal_name(serialize_error(r))`, for example `"past_end"`); a caller refuses a well formed value on a read with `serialize_reject(r)` or by returning false from a nested object's `serialize`, which latches `"rejected"` (serialize 2.1). Only a read refuses. Write and measure misuse (a value out of range or too wide, a non-finite float, bad text, a bad declaration, a write that does not fit the buffer, `serialize_reject` on a write) has one mechanism, the trap: it aborts at the call, `goose runtime error: serialize: <rule>`, and never latches anything (IMPLEMENTING.md U9, serialize 2.1.1). The uniform implementation rules U1 to U16 of the reference's IMPLEMENTING.md are kept and proven by `test/uniform`; DESIGN.md lists the public names (U15), and every other name is internal. The pinned compiler is Goose v2026.2 (commit 7ad96d6d47f9).

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

`make dist-goose` fetches only the Linux x64 archive (`goose-v2026.2-linux-x64.tar.gz`). Per-commit CI runs tests, two witness shards, and controls plus fuzz in parallel jobs; each job fetches the pinned toolchain. Witnesses and controls default `JOBS` to the available core count, with `JOBS=<n>` available to override it. Run `make witnesses` for all rows or set `WITNESS_SHARD=1/2` / `2/2` to run a shard. DESIGN.md is the contract.

BSD 3-Clause license.
