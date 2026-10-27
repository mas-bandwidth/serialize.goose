// test/smoke -- TestSmoke (DESIGN.md (a), (e), (f), (g)): the entry compiles,
// every API name DESIGN.md (a) lists resolves on all three streams, API misuse
// aborts naming its rule, and the latch holds (STANDARD.md, Reader
// Obligations, Failure is terminal).

import .serialize;

// A caller's own type, for serialize_object: one generic serialize function
// over every stream, the C++ model (DESIGN.md (a), object).
struct SmokePair { a: i32, b: i32 }

fn serialize<S>(s: S&, p: SmokePair&) -> bool {
    return serialize_int(s, p.a, 0, 10) && serialize_int(s, p.b, 0, 10);
}

// Names every stream operation DESIGN.md (a) lists, on stream S, each call in
// its own `if never` so that it is typechecked (Goose does not typecheck the
// statements after a call it has proved never returns, and every stub is
// such a call) and never run: TestSmoke passes a never that is false.
fn touch_every_operation<S>(s: S&, never: bool) {
    var u: u32 = 1;
    var u64v: u64 = 1;
    var flag = true;
    var u8v: u8 = 1;
    var u16v: u16 = 1;
    var i: i32 = 1;
    var i64v: i64 = 1;
    var wide = Uint128 { lo: 1, hi: 0 };
    var signed = Int128 { lo: 1, hi: 0 };
    let lo = Int128 { lo: 0xfffffffffffffffb, hi: 0xffffffffffffffff };
    let hi = Int128 { lo: 5, hi: 0 };
    var f: f32 = 1.0;
    var d: f64 = 1.0;
    var blob: u8[4] = [0; 4];
    var text: u8[>..] = [];
    var limited: u8[..16] = [];
    var pair = SmokePair { a: 1, b: 2 };
    if never { serialize_bits(s, u, 3); }
    if never { serialize_bits64(s, u64v, 40); }
    if never { serialize_bool(s, flag); }
    if never { serialize_uint8(s, u8v); }
    if never { serialize_uint16(s, u16v); }
    if never { serialize_uint32(s, u); }
    if never { serialize_uint64(s, u64v); }
    if never { serialize_align(s); }
    if never { serialize_int(s, i, -5, 5); }
    if never { serialize_int64(s, i64v, -5, 5); }
    if never { serialize_int_relative(s, 0, i); }
    if never { serialize_uint128(s, wide); }
    if never { serialize_int128(s, signed, lo, hi); }
    if never { serialize_fixed32(s, i, 16, 16, -5, 5); }
    if never { serialize_fixed64(s, i64v, 32, 32, -5, 5); }
    if never { serialize_fixed128(s, signed, 64, 64, -5, 5); }
    if never { serialize_float(s, f); }
    if never { serialize_double(s, d); }
    if never { serialize_compressed_float(s, f, -1.0, 1.0, 0.01); }
    if never { serialize_compressed_float_precomputed(s, f, 200, 8, 2.0, -1.0); }
    if never { serialize_bytes(s, blob); }
    if never { serialize_string(s, text, 32); }
    if never { serialize_string(s, limited, 16); }
    if never { serialize_object(s, pair); }
    if never { serialize_end(s); }
    if never { serialize_bits_processed(s); }
    if never { serialize_bytes_processed(s); }
    if never { serialize_error(s); }
    if never { serialize_fail(s); }
    if never { serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE); }
    if never { serialize_is_writing(s); }
    if never { serialize_is_reading(s); }
}

fn touch_every_helper(never: bool) {
    if never { serialize_bits_required(0, 7); }
    if never { serialize_bits_required64(0, 7); }
    if never { let max_integer_value, bits, delta = serialize_compressed_float_params(-1.0, 1.0, 0.01); print(max_integer_value, bits, delta); }
    if never { serialize_uint128_equal(serialize_uint128_make(0, 1), serialize_uint128_make(0, 1)); }
    if never { serialize_int128_equal(serialize_int128_make(0, 1), serialize_int128_make(0, 1)); }
    if never { serialize_int128_from_int64(-5); }
    if never { serialize_int128_compare(serialize_int128_make(0, 1), serialize_int128_make(0, 1)); }
    if never { serialize_f32_bits(1.0); }
    if never { serialize_f32_from_bits(0); }
    if never { serialize_f64_bits(1.0); }
    if never { serialize_f64_from_bits(0); }
    if never { serialize_float_bits_are_finite(0); }
    if never { serialize_double_bits_are_finite(0); }
    if never { print(serialize_refusal_name(SERIALIZE_ERROR_PAST_END)); }
    if never { print(SERIALIZE_FORMAT_VERSION); }
}

fn TestSmoke() {
    // The entry compiled to get here. Every name resolves: instantiate the
    // operations on the three streams, each behind a condition the compiler
    // cannot fold and that is false when the test runs.
    var buffer: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buffer);
    var r = serialize_read_stream_init(buffer, 8);
    var m = serialize_measure_stream_init();
    let never = serialize_bits_available(w) < 0 || serialize_bits_remaining(r) < 0;
    touch_every_operation(w, never);
    touch_every_operation(r, never);
    touch_every_operation(m, never);
    touch_every_helper(never);
    if never { serialize_flush(w); }
    assert(serialize_bits_available(w) == 128);
    assert(serialize_bits_remaining(r) == 64);
    assert(serialize_is_writing(w) && !serialize_is_reading(w));
    assert(serialize_is_reading(r) && !serialize_is_writing(r));
    assert(!serialize_is_writing(m) && !serialize_is_reading(m));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE && serialize_error(r) == SERIALIZE_ERROR_NONE);

    // The latch: a read stream over empty data (0 bytes, the 8-byte slack
    // only). A failing call latches PAST_END and leaves its destination
    // unchanged; every later call fails, zero-bit reads included, consumes
    // nothing and leaves its destination unchanged.
    var slack: u8[8] = [0; 8];
    var empty = serialize_read_stream_init(slack, 0);
    assert(serialize_bits_remaining(empty) == 0);
    var v: u8 = 7;
    assert(!serialize_uint8(empty, v));
    assert(v == 7);
    assert(serialize_error(empty) == SERIALIZE_ERROR_PAST_END);
    var b = true;
    assert(!serialize_bool(empty, b));
    assert(b);
    var u: u32 = 9;
    assert(!serialize_bits(empty, u, 1));
    assert(u == 9);
    assert(!serialize_align(empty));
    assert(serialize_error(empty) == SERIALIZE_ERROR_PAST_END);
    assert(serialize_bits_processed(empty) == 0);

    // The first error sticks: a later serialize_fail does not replace it.
    assert(!serialize_fail(empty, SERIALIZE_ERROR_NONZERO_PADDING));
    assert(serialize_error(empty) == SERIALIZE_ERROR_PAST_END);

    // A padded init whose destination cannot hold bytes + 8 starts latched.
    var small: u8[8] = [0; 8];
    var refused = serialize_read_stream_init_padded(small, buffer[0..1]);
    assert(serialize_error(refused) == SERIALIZE_ERROR_PAST_END);
    var w8: u8 = 3;
    assert(!serialize_uint8(refused, w8));
    assert(w8 == 3);

    // The measure stream counts without data: align charges its worst case.
    var measure = serialize_measure_stream_init();
    var one: u32 = 1;
    assert(serialize_bits(measure, one, 8));
    assert(serialize_align(measure));
    assert(serialize_bits(measure, one, 8));
    assert(serialize_bits_processed(measure) == 23);
    assert(serialize_bytes_processed(measure) == 3);
}

// Objects for TestSmokeObjectTerminal: one that reads nothing, and one that
// swallows its own refusal and returns true.
struct SmokeEmpty { called: bool }

fn serialize<S>(s: S&, o: SmokeEmpty&) -> bool {
    o.called = true;
    return true;
}

struct SmokeSwallow { v: i32 }

fn serialize<S>(s: S&, o: SmokeSwallow&) -> bool {
    serialize_int(s, o.v, 0, 10);
    return true;
}

// serialize_object refuses on entry and on exit (serialize 2.0.1, object read
// terminality): a refused stream refuses an empty object without calling its
// serialize, a refusal the object swallowed still refuses the object with
// the inner reason kept, and a healthy empty object at the exact end of the
// data is accepted.
fn TestSmokeObjectTerminal() {
    var slack: u8[8] = [0; 8];
    var latched = serialize_read_stream_init(slack, 0);
    var v: u8 = 7;
    assert(!serialize_uint8(latched, v));
    var empty = SmokeEmpty { called: false };
    assert(!serialize_object(latched, empty));
    assert(!empty.called);
    assert(serialize_error(latched) == SERIALIZE_ERROR_PAST_END);

    // 0xFF: the swallowed int reads 4 bits, 15, out of [0, 10].
    var data: u8[9] = [0xFF, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = serialize_read_stream_init(data, 1);
    var swallow = SmokeSwallow { v: -77 };
    assert(!serialize_object(r, swallow));
    assert(swallow.v == -77);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var after = SmokeEmpty { called: false };
    assert(!serialize_object(r, after));
    assert(!after.called);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);

    var exact = serialize_read_stream_init(data, 1);
    var byte: u32 = 0;
    assert(serialize_bits(exact, byte, 8));
    var at_end = SmokeEmpty { called: false };
    assert(serialize_object(exact, at_end));
    assert(at_end.called);
    assert(serialize_error(exact) == SERIALIZE_ERROR_NONE);
    assert(serialize_end(exact));
}

// API misuse aborts naming its rule (DESIGN.md (e)): proved through the
// runner by its exit and its message. Every family is implemented now, so the
// probe submits an out-of-range bit count rather than a family stub.
// want-abort: serialize: bits must be in [1,32]
fn TestSmokeMisuseAborts() {
    var buffer: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buffer);
    var value: u32 = 5;
    serialize_bits(w, value, 33);
}
