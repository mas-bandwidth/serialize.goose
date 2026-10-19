# serialize.goose

A simple bitpacking serializer for [Goose](https://github.com/aardappel/goose), wire compatible with the C++ [serialize](https://github.com/mas-bandwidth/serialize) library and [serialize.c](https://github.com/mas-bandwidth/serialize.c): the same values produce the same bytes.

Status: in progress. The design, the stream and the runner are in place; the families (the bit packer, integers, floats, strings) are stubs that abort until their cards land. The wire format is serialize's STANDARD.md, format version 1.1, vendored verbatim with its conformance vectors. The pinned compiler is Goose v2026.2 (commit 7ad96d6d47f9).

```goose
import .serialize;

struct Player { id: i32, x: f32, name: u8[..16] }

// One function over every stream: write, read and measure.
fn serialize<S>(s: S&, p: Player&) -> bool {
    return serialize_int(s, p.id, 0, 1023)
        && serialize_float(s, p.x)
        && serialize_string(s, p.name, 16);
}
```

`make dist-goose` once, then `make test`. DESIGN.md is the contract.

BSD 3-Clause license.
