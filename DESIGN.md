# serialize.goose: the design every card copies

serialize.goose ports serialize, the open-source bitpacking serializer, to
[Goose](https://github.com/aardappel/goose). It is the bottom layer under
schema's Goose leg. This page fixes every decision; each family card after it
fills one set of files and decides nothing. Sections (a) to (g) are the
contract.

**The reference.** serialize.c v2.0.0
(`e11585b0dfbf214ed37c442d5f8b6133fd8b10df`), format 2.0, is matched byte for
byte and refusal for refusal, reason for reason. (Format 1.1 was matched
against serialize.c v1.11.2, `7303fa47cada102af10c396c6dd5aa1f0e99f2ab`.) serialize.luau (branch `sprint/serialize-luau`,
`e9acef6fee5efbb1c7b33a25843dba9aa59f6b22`) is the closest worked port and
supplied the shape of this page. Both are read, never imported.

**The vendored standard.** `STANDARD.md`, `IMPLEMENTING.md`,
`conformance/*.txt` and `conformance-controls/` are copied
VERBATIM from mas-bandwidth/serialize at tag v2.1.0
(`884bc3098c9619d67308d9c6b5cdf38593d98b69`, 2026-10-27, the merge of the
`rejected` reason after the audit fixes it carries), format 2.0 still. 2.1
added the `rejected` refusal reason and the `reject` sequence step, the
uniform implementation rules U1 to U16 in IMPLEMENTING.md, sNaN-shaped float
and double neighbour vectors, a compressed_float top integer that decodes
above max, and the `object-latch-rejected` and `reject-reason` controls.
(v2.0.1, `b812b75c`, commit `3f40cb5f`, gave three refusal vectors an empty
`object 0` successor and added `object-terminal.expected`.) None of them is edited
here; a change arrives by re-vendoring from a new tag, `tools/revendor.sh
<tag>`, and the corpus job in ci.yml diffs all four against the tag.

**The pin.** Goose v2026.2 (aardappel/goose tag v2026.2, annotated tag object
`7ad96d6d47f979bb9bcc3d51f610d65efba8335e`, commit
`3ee3871502cf1c5bdc5e2ad7eb4cde6df8fa1d89`): `make dist-goose`, (g).

## (a) THE API

`import .serialize;` (src/serialize.goose) imports the whole library. Every
name is global and carries the `serialize_` prefix, as serialize.c's do; there
is no namespace, so UFCS (`s.serialize_int(v, 0, 10)`) works from any file.

**One spelling per operation.** serialize.c spells every operation three
times (`serialize_write_int`, `serialize_read_int`, `serialize_measure_int`)
because C has no overloading. Goose overloads on argument types, so each
operation is ONE name with three overloads, one per stream type:
`serialize_int(s, value, min, max)` with `s` a `WriteStream&`, `ReadStream&`
or `MeasureStream&`. That is the C++ library's spelling (`serialize_int( stream, value, min, max )`), and it gives the C++ model back: a caller writes
one generic function over every stream, monomorphized per stream with no
runtime dispatch:

```goose
struct Player { id: i32, x: f32, name: u8[..16] }

fn serialize<S>(s: S&, p: Player&) -> bool {
    return serialize_int(s, p.id, 0, 1023)
        && serialize_float(s, p.x)
        && serialize_string(s, p.name, 16);
}
```

The stream parameter of a generic function MUST be `S&` (a reference): a
stream is a fixed-size struct, and an untyped or by-value `s` is a copy whose
bit position is lost (measured: an untyped `s` wrote the byte and left the
caller's `bits_written` at 0).

**Values.** A write or measure overload takes the value BY VALUE (a literal
works); a read overload takes it BY REFERENCE (`i32&`) and assigns it only on
success. A generic caller passes the same lvalue to both. The measure
overloads take the value too, unlike serialize.c's measure functions, so that
one generic function serves all three streams, and make every check a write
makes on it, except room (U6).

### Types and constants (src/serialize_stream.goose, src/serialize_int128.goose)

| name | serialize.c | what |
|---|---|---|
| `WriteStream` | `serialize_write_stream_t` | `{ data: u8[:], num_bits, bits_written, word_index, scratch: u64, scratch_bits }`: no refusal state (U9) |
| `ReadStream` | `serialize_read_stream_t` | `{ data: const u8[:], num_bits, bits_read, error: i32 }` |
| `MeasureStream` | `serialize_measure_stream_t` | `{ bits_written }`: no refusal state (U6) |
| `Uint128`, `Int128` | `serialize_uint128_t`, `serialize_int128_t` | `{ lo: u64, hi: u64 }` (c) |
| `SERIALIZE_ERROR_NONE` .. `SERIALIZE_ERROR_REJECTED` | `serialize_refusal_t` | the latched kinds, below |
| `SERIALIZE_FORMAT_VERSION` | format version | `"2.0"` |

Counts (`bits`, `bytes`, `buffer_size`, `integer_bits`) are `i64`, Goose's
length type. Every other parameter has serialize.c's width and signedness.

### Lifecycle, latch and accounting (src/serialize_stream.goose)

| Goose | serialize.c |
|---|---|
| `serialize_write_stream_init(buffer: u8[:]) -> WriteStream` | `serialize_write_stream_init` |
| `serialize_read_stream_init(data: const u8[:], bytes: i64) -> ReadStream` | `serialize_read_stream_init` |
| `serialize_read_stream_init_padded(destination: u8[:], data: const u8[:]) -> ReadStream` | `serialize_read_stream_init_padded` |
| `serialize_measure_stream_init() -> MeasureStream` | `serialize_measure_stream_init` |
| `serialize_flush(w)` | `serialize_write_flush` |
| `serialize_error(s) -> i32` (a read's reason; NONE on a write or a measure) | `serialize_read_error` |
| `serialize_fail(s, kind = SERIALIZE_ERROR_REJECTED) -> bool` (always false, never aborts; records only on a read) | `serialize_read_fail`, C++ `serialize_fail` |
| `serialize_reject(s) -> bool` (false on a read; aborts on a write or a measure) | `serialize_read_reject`, C++ `serialize_reject` |
| `serialize_bits_processed(s)`, `serialize_bytes_processed(s)` | `*_bits_processed`, `*_bytes_processed` |
| `serialize_bits_available(w)`, `serialize_bits_remaining(r)` | `serialize_write_bits_available`, `serialize_read_bits_remaining` |
| `serialize_align_bits(s)` (write, read) | `serialize_write_align_bits`, `serialize_read_align_bits` |
| `serialize_is_writing(s)`, `serialize_is_reading(s)` | C++ `IsWriting`, `IsReading` |

Initializers return the stream (Goose builds a returned value in place, so
there is no out-pointer). `serialize_is_writing`/`serialize_is_reading` are
not in serialize.c; they are the C++ stream's, and a generic caller needs
them to branch (for example to fill a derived field only after a read).
`serialize_copy_string(dest: u8[:], source: const u8[:])` is the reference
helper (U15, 2.1.1): it zeroes `dest`, then copies the bytes of `source`
before its first zero byte; when there are more than `dest.len - 1` it keeps
the first `dest.len - 1`, then drops bytes from the end while the first byte
left out is a continuation byte (`10xxxxxx`), so the copy never ends inside a
UTF-8 sequence and `serialize_string` with `buffer_size = dest.len` accepts
it. The rule is on bytes, ill-formed source included. A `dest` of no bytes is
write misuse and aborts (U9). Flush is
required: a write buffer's contents are unspecified until `serialize_flush`
(U11). A stream is re-initialized by assigning it a fresh init, which clears
its latch (U13).

### The latched kinds

| kind | value | when |
|---|---|---|
Kinds 1 to 9 are the refusal reasons, the closed list STANDARD.md defines
under "Refusal reasons", in serialize.c's `serialize_refusal_t` order;
`serialize_refusal_name(kind) -> const u8[:]` spells each exactly as the
corpus does (`"past_end"`, `"rejected"`), `"none"` for NONE (U14).
The 2.0 alias `SERIALIZE_ERROR_FAILED` is gone from 2.1.1: U15 allows no
public name beyond the refusal list, and the reference has none.

| kind | value | name | when |
|---|---|---|---|
| `SERIALIZE_ERROR_NONE` | 0 | `none` | no error |
| `SERIALIZE_ERROR_PAST_END` | 1 | `past_end` | a read past the end of the data; a padded init whose destination is too small |
| `SERIALIZE_ERROR_VALUE_OUT_OF_RANGE` | 2 | `value_out_of_range` | a value read outside the range or domain it is serialized with: a ranged offset past its span, a string length above `buffer_size - 1`, a compressed integer above `max_integer_value`, an int_relative outside its domain or not above previous |
| `SERIALIZE_ERROR_NONZERO_PADDING` | 3 | `nonzero_padding` | nonzero padding read by an align (or the align inside bytes and string), or by an end in the final byte |
| `SERIALIZE_ERROR_TRAILING_DATA` | 4 | `trailing_data` | a whole byte or more left at an end |
| `SERIALIZE_ERROR_NON_FINITE_FLOAT` | 5 | `non_finite_float` | a float or double read whose exponent field is all ones, a compressed_float decode that is not finite |
| `SERIALIZE_ERROR_INVALID_UTF8` | 6 | `invalid_utf8` | a string payload that is not well-formed UTF-8 |
| `SERIALIZE_ERROR_EMBEDDED_NUL` | 7 | `embedded_nul` | a zero byte in a string payload (scanned before the encoding) |
| `SERIALIZE_ERROR_NON_CANONICAL` | 8 | `non_canonical` | the int_relative absolute tier carrying a difference a bounded tier carries |
| `SERIALIZE_ERROR_REJECTED` | 9 | `rejected` | the caller's own refusal of well formed bytes (2.1, U2): `serialize_reject`, `serialize_fail` with NONE or a kind outside the list, or an object's `serialize` returning false with nothing latched |

Only a read stream latches: every kind is a reader's reason, and write and
measure misuse records none (U9). The first latched kind sticks: the later refusals of a failed stream are
echoes and keep it, and `serialize_fail` with a kind on a latched stream
returns false and changes nothing. A refused read stream never reports NONE.
A latch persists until the stream is re-initialized (assigned a fresh init).
The latch is the reference's model, `tla/ReadStreamLatch.tla` in
mas-bandwidth/serialize v2.1.0, checked with TLC: refused exactly when a
reason is recorded, the reason never changes once recorded, no read succeeds
after a refusal. A write or a measure refuses nothing and latches nothing (U6,
U9): `serialize_fail` on one returns false and records nothing, a nested
object whose `serialize` returns false on one makes `serialize_object`
return false and records nothing, and `serialize_reject` on one is caller
misuse and aborts (`serialize: reject is read only`). This port has no write
error flag: only C may carry one (U15).

### The operations (one name, three overloads each)

| Goose (`s` any stream; value type on write / read) | serialize.c | file |
|---|---|---|
| `serialize_bits(s, value: u32 / u32&, bits)` bits in [1,32] | `*_bits` | stream |
| `serialize_bits64(s, value: u64 / u64&, bits)` bits in [1,64] | `*_bits64` | stream |
| `serialize_bool(s, value: bool / bool&)` | `*_bool` | stream |
| `serialize_uint8`, `16`, `32`, `64(s, value: uN / uN&)` | `*_uint8` .. `*_uint64` | stream |
| `serialize_align(s)` | `*_align` | stream |
| `serialize_int(s, value: i32 / i32&, min: i32, max: i32)` | `*_int` | int |
| `serialize_int64(s, value: i64 / i64&, min: i64, max: i64)` | `*_int64` | int |
| `serialize_int_relative(s, previous: i32, current: i32 / i32&)` | `*_int_relative` | int |
| `serialize_uint128(s, value: Uint128 / Uint128&)` | `*_uint128` | int128 |
| `serialize_int128(s, value: Int128 / Int128&, min: Int128, max: Int128)` | `*_int128` | int128 |
| `serialize_fixed32(s, value: i32 / i32&, integer_bits, fraction_bits, min: i32, max: i32)` | `*_fixed32` | fixed |
| `serialize_fixed64(s, value: i64 / i64&, integer_bits, fraction_bits, min: i64, max: i64)` | `*_fixed64` | fixed |
| `serialize_fixed128(s, value: Int128 / Int128&, integer_bits, fraction_bits, min: i64, max: i64)` | `*_fixed128` | fixed |
| `serialize_float(s, value: f32 / f32&)` | `*_float` | float |
| `serialize_double(s, value: f64 / f64&)` | `*_double` | float |
| `serialize_compressed_float(s, value: f32 / f32&, min: f32, max: f32, res: f32)` | `*_compressed_float` | compressed_float |
| `serialize_compressed_float_precomputed(s, value: f32 / f32&, max_integer_value: u32, bits, delta: f32, min: f32)` | `*_compressed_float_precomputed` | compressed_float |
| `serialize_bytes(s, data: const u8[:] / u8[:])` count = data.len | `*_bytes` | bytes |
| `serialize_string(s, value: const u8[:] / T&, buffer_size)` | `*_string` | bytes |
| `serialize_end(s)` | `*_end` | stream |
| `serialize_object<S, T>(s: S&, object: T&)` | C++ `serialize_object` | object |

Every operation returns `bool`. On a read: true on success, false on a
refusal or on a latched stream. On a write or a measure: true, or an abort on
misuse (below); only `serialize_fail` and a nested object whose `serialize`
returns false give false there. Measure overloads take the write overload's
parameters.

`serialize_end` is the end of the object (STANDARD.md, end). Its write and
measure halves emit and cost nothing. Its read half consults the latch, then
refuses a whole byte or more left as TRAILING_DATA, then reads the 0 to 7
bits left in the final byte and refuses a set one as NONZERO_PADDING. A
packet reader calls it after the top-level object, over a stream of exactly
the bytes the writer reported:

```goose
var r = serialize_read_stream_init_padded(destination, packet);
let ok = serialize(r, player) && serialize_end(r);
```

Format 2.0 removed wstring: text is UTF-8 and only UTF-8.

`serialize_object` has no serialize.c function (C has no templates); it is
the C++ library's macro, STANDARD.md object: it calls the caller's own
`serialize(s, object)` overload inline, as the example above declares one,
and contributes no bytes. On a latched stream it refuses before calling; on
a read, a false from the caller's function latches `SERIALIZE_ERROR_REJECTED`
unless something already latched (U2); on a write or a measure it returns
false and records nothing (U9).

### Helpers

| Goose | serialize.c | file |
|---|---|---|
| `serialize_bits_required(min: u32, max: u32) -> i64` | `serialize_bits_required` | int |
| `serialize_bits_required64(min: u64, max: u64) -> i64` | `serialize_bits_required64` | int |
| `serialize_float_bits_are_finite(bits: u32) -> bool`, `serialize_double_bits_are_finite(bits: u64) -> bool` | the same | float |
| `serialize_refusal_name(kind: i32) -> const u8[:]` | `serialize_refusal_name` | stream |
| `serialize_uint128_make(hi, lo)`, `serialize_int128_make(hi, lo)` | the same | int128 |
| `serialize_int128_from_int64(value: i64) -> Int128` | the same | int128 |
| `serialize_uint128_equal`, `serialize_int128_equal`, `serialize_int128_compare -> i64` | the same | int128 |
| `serialize_compressed_float_params(min, max, res) -> u32, i64, f32` (max_integer_value, bits, delta) | the same, out-pointers as results | compressed_float |
| `serialize_f32_bits`, `serialize_f32_from_bits`, `serialize_f64_bits`, `serialize_f64_from_bits` (internal, U15 below) | memcpy in the C | float |

### The public surface (U15)

IMPLEMENTING.md U15 ("Exports beyond the reference operations", 2.1.1)
limits what a port exports. Goose cannot hide a name: "All declarations are
public in v1" (the Goose spec, 11.1, Modules and globals), and namespaces
give no privacy. So this list is the promise, and every other top-level
name in src/ is INTERNAL: it may change or vanish in any release, and a
caller must not use it.

**Public:**

- the operations, (a) above, `serialize_object` and `serialize_end`
  included;
- the three streams, `WriteStream`, `ReadStream`, `MeasureStream`, their
  initializers (`serialize_write_stream_init`, `serialize_read_stream_init`,
  `serialize_read_stream_init_padded`, `serialize_measure_stream_init`) and
  `serialize_flush`;
- the stream accessors the reference streams carry: `serialize_error` (the
  refusal), `serialize_bits_processed`, `serialize_bytes_processed`,
  `serialize_bits_available`, `serialize_bits_remaining`,
  `serialize_align_bits`, `serialize_is_writing`, `serialize_is_reading`;
  and `serialize_fail`, `serialize_reject` (U2, U14);
- the refusal list `SERIALIZE_ERROR_NONE` .. `SERIALIZE_ERROR_REJECTED` and
  `serialize_refusal_name` (U14);
- `serialize_copy_string` (U15);
- the reference's own helpers, in this port's spelling:
  `serialize_bits_required`, `serialize_bits_required64`,
  `serialize_bits_required128`, `serialize_float_bits_are_finite`,
  `serialize_double_bits_are_finite`, `serialize_compressed_float_params`,
  and `serialize_valid_utf8` (the reference's `string_is_valid_utf8`);
- a language necessity, the 128-bit integer types (Goose has no 128-bit
  integer): `Uint128`, `Int128`, and the constructors and arithmetic their
  operations need, `serialize_uint128_make`, `serialize_int128_make`,
  `serialize_int128_from_int64`, `serialize_uint128_equal`,
  `serialize_int128_equal`, `serialize_uint128_compare`,
  `serialize_int128_compare`, `serialize_int128_add`, `serialize_int128_sub`.

**Internal** (no promise): everything else, among them the packer
(`serialize_packer_*`, `serialize_bitpacker_store_word`,
`serialize_bitpacker_load_word`), the gates (`serialize_read_check`,
`serialize_write_check`, `serialize_write_past_end`,
`serialize_measure_add`, `serialize_bits_count_check`,
`serialize_bits_write_check`, `serialize_string_check`), `serialize_fail_kind`,
the length field (`serialize_length_bits`, `serialize_write_length`,
`serialize_read_length`, `serialize_measure_length`),
`serialize_string_capacity`, `serialize_int_relative_bits`, the
`serialize_u128_*` lane helpers, every `cf_*` and `fixed_*` helper,
`CF_MAX_INTEGER_VALUE`, the float bit casts `serialize_f32_bits`,
`serialize_f32_from_bits`, `serialize_f64_bits`, `serialize_f64_from_bits`
(Goose has f32 and f64, so they are no necessity; the tests use them), and
`SERIALIZE_FORMAT_VERSION` (informational). The 2.0 alias
`SERIALIZE_ERROR_FAILED` is removed.

### Write misuse traps: the abort, naming the rule; read misuse is refused

Goose has no build in which a check is compiled out, so this port is an
always-checked implementation (IMPLEMENTING.md, The check model), a checked
build in every run. Its one write-misuse mechanism, the trap of U9, is the
abort (`abort("serialize: <rule>")`, which prints `goose runtime error:
serialize: <rule> (<file>:<line>)` and exits 1), at the call, before any bit
of the operation is written. It is applied to every operation on a write
stream and, except room, on a measure stream (U6). **Write misuse never
latches** (U9): no reason is recorded, no call returns false, no later call
fails. `value_out_of_range`, `non_finite_float`, `invalid_utf8`,
`embedded_nul` and `past_end` are reader reasons only. The misuse:

- declarations: a bits count outside the entry point's width (`serialize:
  bits must be in [1,32]`, `[1,64]`), `min > max` (`serialize: min must not
  be greater than max`), a bad Q format (`serialize: integer_bits +
  fraction_bits must equal the storage width`), fixed bounds outside the Q
  format (`serialize: fixed min and max must fit the Q format`), a bad
  compressed_float declaration or precomputed constants, a string
  `buffer_size` below 1, an int_relative `previous` outside [0, 2^31 - 1], a
  write buffer whose length is not a multiple of 8 (U1);
- values, on a write and a measure alike (U6): a value too wide for its bits
  (`serialize: value must fit in bits`, U8), a ranged or fixed value outside
  [min, max] (`serialize: value must be in [min, max]`), a non-finite float,
  double or compressed_float (`serialize: float must be finite`, `double`,
  `compressed float value`; never clamped), a compressed_float declaration
  whose top decode is not finite, a string that does not fit `buffer_size -
  1`, holds a zero byte or is not well-formed UTF-8 (U3, U4), an int_relative
  `current` not above `previous`;
- room, on a write only: an operation that does not fit the room left in the
  buffer (`serialize: write does not fit the buffer: <n> bits, <m> left`,
  where n is the WHOLE operation's width, checked before any of it is
  written, U10);
- `serialize_reject` on a write or a measure (`serialize: reject is read
  only`), and a `serialize_copy_string` destination of no bytes.

`serialize_fail` never aborts, on any stream (U9, U14).

On a READ the same declarations are the caller's, and a reader never traps
(U7, U16): a bits count out of range, `min > max`, a bad Q format or bounds
outside it, a bad compressed_float declaration or precomputed constants, a
string `buffer_size` below 1 or above a limited builder's capacity plus one,
an int_relative `previous` outside its domain, a negative `bytes` or read
data without its 8-byte slack (d) each refuse as `value_out_of_range` before
any bit moves, and keep a reason already latched. Either way the outcome is
decided only by the caller's own arguments, never by data (e).

The write buffer is a multiple of 8 bytes, as serialize.c's is from 2.0.2
(U1): the packer commits whole 64-bit words.

## (b) BIT ORDER AND ENDIANNESS

Exactly as serialize.c. STANDARD.md, General Conventions, quoted:

> All multi-byte quantities are **little-endian**.
>
> The stream is accumulated in a **64-bit scratch word**. Bits are packed
> **least-significant-bit first**: the first value written occupies the lowest
> bits of the first word. When the scratch fills, the 64-bit word is copied to
> the buffer in host byte order on little-endian machines, and byte-swapped on
> big-endian machines. The result is the same bytes on the wire everywhere.
>
> A value of `n` bits, written when the scratch already holds `s` bits, occupies
> bits `[s, s+n)` of the current word. A value that would cross the 64-bit
> boundary is split: the low `64-s` bits complete the current word, and the
> remainder begins the next.
>
> **Flush.** After the final value, any partially filled scratch word is written
> out. The stream therefore always occupies a whole number of 8-byte words in the
> writer's buffer, but the meaningful length is the number of bytes actually
> required, rounded up to a byte.

The rules for this library:

- The scratch is `WriteStream.scratch: u64`. Each committed word is stored as
  8 bytes, least significant first, by shifts (`(w >> 8k) as! u8`): the store
  never consults the host, so it is little-endian on every host by
  construction. (Goose itself is little-endian only: `bytes_of` and
  `from_bytes` abort on a big-endian host, its design/serialization.md.)
- A value above 32 bits goes low 32 bits first, then the high bits
  (STANDARD.md bits). Because packing is LSB-first, packing the whole value at
  once produces exactly those bits, so the packer takes [1,64] in one call.
- uint128 and the int128 offset: the low 64-bit half first, then the high,
  each as `bits(half, 64)` (STANDARD.md uint128, int128).
- `serialize_flush` writes out the partial word; `serialize_bytes_processed`
  is `(bits + 7) / 8`, the meaningful length.
- Trailing bits: the writer writes zero (the scratch above the bit index is
  zero by construction); no read looks at them (STANDARD.md, Reader
  Obligations, Trailing bits).
- `serialize_align_bits` is `(8 - bit_index % 8) % 8`; an aligned align writes
  and reads nothing.

## (c) THE NUMBER MODEL

Measured on hetzner2 and hulk, 2026-10-19, at the pin:

- **Every value of 64 bits or fewer is Goose's own integer type** (`i8..i64`,
  `u8..u64`), at serialize.c's width and signedness. Arithmetic is at the
  operands' own width, with no promotion: `u32 + i32`, and `u64` with any
  signed operand, are compile errors that need a cast. Unsigned arithmetic
  wraps in every build. Signed overflow aborts under `--debug` and wraps in
  release, so the read path computes offsets (`value - min`, the
  reconstruction in int_relative) in UNSIGNED arithmetic: no input may turn a
  refusal into a debug trap (STANDARD.md, Reader Obligations).
- **Conversions.** Widening of the same signedness is implicit; anything that
  can lose a bit takes a cast. `as` is range-checked under `--debug`; `as!`
  never is. The library uses `as!` wherever losing bits is the meaning (a
  `u64` masked to its low 8 bits becoming a `u8`, a two's complement offset).
- **Shifts are masked.** `>>` is logical on unsigned and arithmetic on signed,
  and a shift count is masked to the width: `(1 as u64) << 64` is 1 and
  `(1 << 63) >> 64` is `1 << 63` (measured). So every shift by a computed count
  is guarded for 0 and for the full width: a mask of `bits` bits is
  `if bits == 64 { u64.max } else { (1 << bits) - 1 }`, a value test is
  `bits == 32 || value >> bits == 0` (src/serialize_stream.goose, bits), and a
  split at a word boundary handles `scratch_bits == 0` and `== 64` explicitly.
- **128 bits** is a struct of two `u64` lanes, `{ lo, hi }`, bits 0..63 and
  64..127: `Uint128` and `Int128` (serialize.c's lanes; Goose has no 128-bit
  integer). Int128 is the same lanes read as two's complement.
- **Bit counting.** std's `popcount`, `clz`, `ctz` (u64, 64 for 0) are the
  runtime's, one instruction under gcc. `serialize_bits_required` is
  `64 - clz(max - min)` in the unsigned domain.
- **Float bits: `bytes_of` out, `from_bytes` in.** Goose has no
  float-to-bits cast. Two routes were built and timed (100,000,000 round
  trips f32 -> bits -> f32, a serial dependency chain, `goose build -O2` with
  gcc 13.3, hulk, 2026-10-19):

  | route | `goose build -O2` | `goose run` (TinyCC) |
  |---|---|---|
  | C sidecar: `extern fn` + a `.build` naming a memcpy `.c` | 2.73 ns | 17.95 ns |
  | pure Goose: `bytes_of([x])` out, `from_bytes<f32[>..]>` back | **2.35 ns** | 73.81 ns |

  The pure route is the faster one where it matters (the -O2 build) and needs
  no C: a C sidecar must sit beside the ROOT file of every program, so every
  consumer (the schema port, every game) would have to carry this library's
  `.build`, and `goose run` builds it into a library under `GOOSE_HOME`. So
  the route is fixed:

  ```goose
  fn serialize_f32_bits(value: f32) -> u32 {
      let a: f32[1] = [value];
      let b = bytes_of(a);                      // a read-only view, no copy
      return b[0] as u32 | (b[1] as u32 << 8) | (b[2] as u32 << 16) | (b[3] as u32 << 24);
  }
  fn serialize_f32_from_bits(bits: u32) -> f32 {
      // a Goose image: uleb128(4), then the 4 payload bytes
      let image: u8[5] = [4, bits as! u8, (bits >> 8) as! u8, (bits >> 16) as! u8, (bits >> 24) as! u8];
      let v, ok = from_bytes<f32[>..]>(image);
      assert(ok);                               // a 4-byte payload is always one f32
      return v[0];
  }
  ```

  and the f64 pair the same with 8 bytes (prefix 8). Never arithmetic. The
  floats card proves bit identity on subnormals and -0, in both builds.
- **Finite values only** (STANDARD.md, format 2.0): the finite test is on
  the BITS (`bits & 0x7F800000 != 0x7F800000`, `0x7FF0000000000000` for
  double), so no conversion can quiet a signaling NaN before the test sees
  it. A reader refuses a non-finite pattern as NON_FINITE_FLOAT before the
  destination is written; a writer or a measure handed one aborts (`serialize:
  float must be finite`) and writes nothing: write misuse, the trap (U6, U9).
- **compressed_float** is f32 arithmetic throughout, in serialize.c's order
  (`serialize_compressed_float_params`, then the precomputed write and read):
  Goose computes `f32 op f32` in f32, and a float literal adapts to f32 beside
  an f32 operand, so the source reads as the C does. Every intermediate is
  bound to an `f32` variable where C rounds to float. The read refuses a
  decode that is not finite (over `[3 * 2^103, FLT_MAX]` at res `2^104` the
  top integer decodes to +inf) as NON_FINITE_FLOAT, destination untouched;
  the write side alone (write and measure, U6) aborts on a declaration whose
  top decode, `min + delta`, is not finite, and on a non-finite value, which
  is never clamped (U9).

## (d) BYTES

- **WriteStream** holds the caller's buffer as a writable slice `u8[:]`: a
  `u8[N]` array, a `u8[>..]` grown to size, or a slice of either. Nothing is
  copied in or out: after `serialize_flush`, the message is
  `buffer[0..serialize_bytes_processed(w)]`. The length is a multiple of 8.
- **ReadStream** holds a read-only slice `const u8[:]` of the caller's data,
  plus `bytes`, the message length. **The slack contract** (STANDARD.md,
  Implementation Law, the buffer contract): `data.len >= bytes + 8`, so the
  packer may load a 64-bit window at any byte position inside the message
  without a tail case; bytes past `bytes` are loaded and never interpreted.
  Measured (hulk, 2026-10-19, `goose build -O2`, 13-bit fields over a
  1200-byte message, two rounds): the slack window read 2.09 and 2.22 ns per
  field, the exact-length read with a tail branch 2.24 and 2.51 ns, so slack
  is 7 to 12 percent faster, and the speed rule makes it the contract.
  Goose's checked indexing is a NAMED RESIDUAL here (the bench's bce line
  elided 0 of 25 index checks in that loop); the bitpacker card gives the
  analysis a length it can use (an `assert` of the window against
  `data.len`, Goose tutorial section 17) and measures again.
- A payload in an exactly sized allocation is read through
  `serialize_read_stream_init_padded(destination, data)`, which copies it once
  into a destination of at least `data.len + 8` bytes and zeroes the slack; a
  smaller destination copies nothing and the stream starts latched
  (`SERIALIZE_ERROR_PAST_END`), serialize.c's rule.
- `serialize_bytes` writes from a `const u8[:]` and reads into a caller's
  `u8[:]` whose length is the count.
- **Strings are Goose's own: UTF-8 bytes** (STANDARD.md string: real text
  round trips byte for byte, no normalization, no BOM stripping, no
  replacement). A write takes a
  `const u8[:]` (a literal, a `u8[>..]`, a `u8[..k]`); a read takes the caller's
  builder by reference, a growable `u8[>..]` or a limited `u8[..k]` (generic
  `T&`: Goose will not pass a `u8[..k]` as a `u8[>..]&`, measured), validates
  the payload IN PLACE in the stream's data first, and only then clears the
  builder and appends: a refused string read leaves the destination
  untouched. The claimed length is checked against the stream (PAST_END)
  before anything is allocated or touched. The writer is handed well-formed
  UTF-8 with no zero byte and aborts otherwise.

## (e) WRITER AND READER

**The writer is STRICT.** For every value it emits exactly the bytes
serialize.c v2.0.0 emits, byte for byte. Every write misuse the reference
asserts on aborts naming the rule (a), a value outside [min,max], a
non-finite float and a full buffer included: one mechanism, the trap (U9).
The room check covers the whole operation's width, a string's length, align
and payload together, an int_relative's whole ladder, before any bit moves
(U10). A write stream records nothing: it has no error flag (only C may carry
one, U15).

**Reads forgive nothing.** Format 2.0 gives every value exactly one
encoding: the trailing bits of the last byte, and any byte after the object,
are examined by `serialize_end`, which a packet reader must call.

**Security trumps** (STANDARD.md, Reader Obligations, Implementation Law):

- Every refusal STANDARD.md and serialize.c state is made: past the end
  (`bit_index + n > 8 * bytes`, written `n <= num_bits - bits_read` so it
  cannot overflow), a decoded value outside [min,max], an offset outside its
  range, nonzero align padding, an int_relative reconstruction outside
  [0, 2^31 - 1] or not above previous (then, in the absolute tier, one no
  more than 69914 above previous: NON_CANONICAL), a non-finite float, double
  or compressed_float decode, a string with a NUL (scanned over the whole
  payload first) or malformed UTF-8 (overlongs, surrogates, above U+10FFFF,
  truncated), and at the end trailing data (first) or set padding. Each
  latches its reason, (a).
- A refused read leaves the caller's destination untouched: check, then
  assign. This port extends that to strings (validated before the builder is
  touched); a `serialize_bytes` read checks the bounds before copying, so a
  refused one is untouched too.
- The stream is terminal after a refusal: the latch (a). Every read consults
  it first, zero-bit reads included (a degenerate range, an aligned align, a
  zero-count bytes, an object, an end). A refused read writes nothing and a
  read on a failed stream consumes nothing; a padding refusal (align, end)
  has consumed the padding it read (serialize.c instead poisons the
  cursor to `num_bits + 1`; there, as here, the counters of a failed stream
  are not data).
- Hostile bytes never abort the program: an abort is API misuse, decided by
  the caller's own arguments. The read path uses unsigned or `as!`
  arithmetic, so `--debug` cannot trap on data either.
- No read touches memory past the data's end: the gate runs before every
  load, the window loads stay inside `data` by the slack contract (d), and
  Goose bounds-checks every index besides.

### What the stream gives a family (src/serialize_stream.goose)

The stream file implements the types, the latch, accounting, and the
bit-level primitives (bits, bits64, bool, uint8..uint64, align, flush), each
of which is the latch, the gate and one packer call. A family arm uses only:

| primitive | stream | what |
|---|---|---|
| `s.error != SERIALIZE_ERROR_NONE` | read | latched |
| `serialize_fail(s, kind) -> false` | all | latch kind on a read (the first sticks; NONE or a kind outside the list records REJECTED); a write or a measure records nothing |
| `serialize_read_check(r, bits) -> bool` | read | false when latched; latches PAST_END past the end |
| `serialize_write_check(w, bits)` | write | aborts when `bits` does not fit the room left (U9, U10) |
| `serialize_measure_add(m, bits) -> bool` | measure | adds bits; always true (a measure refuses nothing, U6) |
| `serialize_packer_write(w, value: u64, bits)` | write | bits in [1,64], value < 2^bits, already checked |
| `serialize_packer_read(r, bits) -> u64` | read | bits in [1,64], already checked |
| `serialize_packer_write_bytes(w, data)`, `serialize_packer_read_bytes(r, data)` | write, read | an aligned run, already checked |
| `serialize_bits`, `serialize_bool`, `serialize_align`, `serialize_int`, ... | all | an arm may call public operations (int_relative's bool and int, string's int and bytes), as serialize.c does |

An arm does the whole operation in this order: on a write or a measure,
abort on misuse (the declaration, then the value; on a write, then the
room for the whole operation); on a read, refuse on a latched stream, refuse a bad declaration as VALUE_OUT_OF_RANGE (U16), then
the data refusals; the gate for the whole width; then the bits; a read
assigns its destination last.

## (f) THE FILE LAYOUT

| file | holds | card |
|---|---|---|
| `src/serialize.goose` | the entry: imports every file; `SERIALIZE_FORMAT_VERSION` | serialize-goose-design (this card) |
| `src/serialize_stream.goose` | the stream types, the latch and its reasons, terminality, accounting, the gates, bits/bits64/bool/uint8..64/align/end/flush | serialize-goose-design (this card) |
| `src/serialize_bitpacker.goose` | the packer: `serialize_packer_write`, `_read`, `_flush`, `_write_bytes`, `_read_bytes` | serialize-goose-bitpacker |
| `src/serialize_int.goose` | `serialize_bits_required`, `serialize_bits_required64`, `serialize_int`, `serialize_int64`, `serialize_int_relative` | serialize-goose-integers |
| `src/serialize_int128.goose` | `Uint128`, `Int128` and their helpers, `serialize_uint128`, `serialize_int128` | serialize-goose-integers |
| `src/serialize_float.goose` | `serialize_f32_bits` and its three siblings, `serialize_float`, `serialize_double` | serialize-goose-floats |
| `src/serialize_fixed.goose` | `serialize_fixed32`, `serialize_fixed64`, `serialize_fixed128` | serialize-goose-floats |
| `src/serialize_compressed_float.goose` | `serialize_compressed_float_params`, `serialize_compressed_float`, `serialize_compressed_float_precomputed` | serialize-goose-floats |
| `src/serialize_bytes.goose` | `serialize_bytes`, `serialize_string` | serialize-goose-strings |
| `src/serialize_object.goose` | `serialize_object` | serialize-goose-strings |

Each family file exists now with its final signatures as stubs that abort
`serialize: <name> not implemented`; a family card replaces the bodies of its
own files and edits no other file. A card may add helpers inside its own
files, named `serialize_<family>_<name>` so no two files collide (one global
namespace). Every import in src/ is relative to the importing file
(`import .serialize_stream;`), so the unit works wherever a program vendors
it. Each card adds its tests in its own `test/<name>/` and any make target in
its own `make/<card>.mk`. Every function that implements a rule cites the
STANDARD.md section (and this page's section) that states it.

Dependencies: every family's tests need the bitpacker at run time (the
stream packs through it). int128 and fixed use `serialize_bits_required64`
(int); fixed128 uses int128; compressed_float uses `serialize_bits_required`
(int) and the float bits (float); string uses the ranged length field and
`serialize_bytes`.

**A Goose fact every test author needs** (measured): the checker does not
typecheck the statements after a call it has proved never returns, and every
stub (and `abort`, `exit`) is such a call. A test that wants many calls
checked puts each in its own `if` (test/smoke does).

## (g) THE RUNNER

- `make dist-goose` fetches
  https://github.com/aardappel/goose/releases/download/v2026.2/goose-v2026.2-linux-x64.tar.gz,
  REFUSES by name any archive whose sha256 is not
  `f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c` before
  anything is unpacked, and untars it into `dist/`
  (`dist/goose-v2026.2-linux-x64/goose`, its `stdlib/` and `tcclib/` beside
  it). dist/ and build/ are gitignored. It is setup, run once, never from a
  test.
- `GOOSE ?= dist/goose-v2026.2-linux-x64/goose`, overridable (the fleet
  installs the same pin); `make toolchain-goose` refuses by name a `GOOSE`
  that does not resolve. `GOOSE_HOME` defaults to `build/goose-home`, so
  nothing the compiler caches leaves the job.
- `make test` runs every `test/*/`; `make test T=<name>` runs `test/<name>/`,
  both through `tools/run_tests.sh`. The Makefile ends with
  `-include make/*.mk`, where later cards add targets in their own files.
- A test file is `test/<name>/<x>_test.goose`; each `fn Test<Name>()` at the
  start of a line is one test. For each test directory the runner stages
  `build/run/<name>/` (a copy of `src/*.goose`, every `.goose` file of the
  test directory, and `conformance/*.txt`, so a test reads a vector file by
  its base name with `os::read_file`), writes a root file there that imports
  the test file and calls the one test from `main`, and runs it as
  `$GOOSE run <root>.goose` (TinyCC in-process, -O1). Each test is its own
  process, so an abort fails exactly one test. A test fails by aborting
  (`assert`, `abort`, a bounds or debug check).
- Directives, on the comment lines directly above a test's `fn` line:
  `// goose: --debug` runs it with those flags (`$GOOSE run --debug`, the
  overflow and range checks); `// want-abort: <message>` makes it pass only if
  it exits nonzero AND prints `goose runtime error: <message>` (how the
  misuse aborts are tested).
- It prints `RUN Test<Name>`, then `--- PASS Test<Name>` or `--- FAIL Test<Name>` with the run's output indented below. It exits nonzero on a
  FAIL, on a missing or empty `test/<name>/` (`FAIL test/nosuch/ is missing`), and on a test file that declares no test, naming each: never a
  skip. Its last line is `ok N test directories` or `FAIL k of N test directories`.
- Anything timed is built, never run under TinyCC:
  `$GOOSE build -O2 <file>.goose -o <exe>` with the bench's gcc 13 (and
  clang where a card compares), and lives in its card's own make target,
  never in `make test`.
- Unit tests use no real time, no sockets, no network and no outside
  services; a test clock, where one is ever needed, is an argument starting at
  1000.0.
- Conformance: `test/conformance` reads `conformance/*.txt` from the staged
  directory and checks every record, byte for byte and refusal for refusal,
  each refusal held to the reason its record states, every `writer_input`
  written and held to the record's bytes, every name unique (STANDARD.md, The
  vector format, What a runner checks). A failing vector is printed and
  collected rather than aborting the run; a malformed one (unknown operation,
  line or reason) aborts.
- A compiler warning anywhere in a test's program fails that test: zero
  warnings.
- `make witnesses` (tools/witnesses.sh): each row deletes one rule in a
  scratch copy of src/ and the whole suite must go red.
- `make controls` (tools/controls.sh): the C++ reference's negative controls,
  translated line for line. Each deletes one refusal rule in a scratch copy
  of src/ and the REAL corpus, through the runner built over that copy, must
  fail EXACTLY the vectors `conformance-controls/<rule>.expected` names
  (`conf_control_main`); the unknown-operation control must be rejected.
  A needle that does not occur exactly once fails the control, and a
  vendored `.expected` with no row fails the run.
- `make fuzz` (make/fuzz.mk; a functional test, in CI after the controls):
  the differential against serialize.c v2.0.0, the family's pattern
  (serialize.lobster). fuzz/host.c generates 2000 programs over every
  operation from a fixed seed; serialize.c and fuzz/fuzz_driver.goose (built
  with `goose build --debug`, one child per batch of 100) must write the same
  bytes, decode each other's to the same values, and on one program in four
  agree on a mutant's accept or refuse, refusing step and reason. Three
  negative controls must go red, each for its own reason: the C side writing
  one int range one bit wider, the Goose reader's range refusals deleted, and
  the string reader naming invalid_utf8 for embedded_nul. `make fuzz-extended
  FUZZ_SEED=<seed> FUZZ_DURATION=<s>` is the nightly run
  (.github/workflows/nightly-fuzz.yml), its seed varying and printed.
