// test/uniform -- the 2.1.1 rulings (IMPLEMENTING.md v2.1.1, "The check
// model", U6, U9 and U15): write and measure misuse has one mechanism, the
// trap, which in this always-checked port is the abort ("goose runtime
// error: serialize: <rule>", exit 1). Write misuse never latches: no reason
// recorded, no false return, no later failure. fail on a write or a measure
// returns false and records nothing; reject there is misuse and aborts; a
// nested object returning false there returns false and records nothing. A
// measure makes every check a write makes, except room (U6). And
// serialize_copy_string backs off to a whole character (U15).

import .serialize;

// ---- U9: a write that does not fit the room left aborts -------------------

// A full buffer is write misuse: never a latched past_end.
// want-abort: serialize: write does not fit the buffer: 1 bits, 0 left
fn TestU9WritePastEndAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(serialize_uint64(w, 0xFFEEDDCCBBAA9988));
    assert(serialize_bits_available(w) == 0);
    serialize_bool(w, true);
}

// want-abort: serialize: write does not fit the buffer: 128 bits, 64 left
fn TestU9WritePastEndUint128Aborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_uint128(w, Uint128 { lo: 1, hi: 2 });
}

// U10 with U9: the whole operation's room is checked first, so the trap
// names the whole width. 60 bits written: a string's 4 length bits, its align
// bits (none: 64 is aligned) and 16 payload bits (20) against the 4 left.
// want-abort: serialize: write does not fit the buffer: 20 bits, 4 left
fn TestU10StringWritePastEndAbortsOnTheWholeOperation() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(serialize_bits(w, 0, 30));
    assert(serialize_bits(w, 0, 30));
    serialize_string(w, "ab", 16);
}

// 57 bits written: 7 align bits and one byte (15) against the 7 left.
// want-abort: serialize: write does not fit the buffer: 15 bits, 7 left
fn TestU10BytesWritePastEndAbortsOnTheWholeOperation() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(serialize_bits(w, 0, 30));
    assert(serialize_bits(w, 0, 27));
    let one: u8[1] = [0x5A];
    serialize_bytes(w, one);
}

// int_relative's tiers are one operation: 63 bits written, the 2-tier
// difference costs 1 + 1 + 3 = 5 bits.
// want-abort: serialize: write does not fit the buffer: 5 bits, 1 left
fn TestU10IntRelativeWritePastEndAbortsOnTheWholeOperation() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(serialize_bits(w, 0, 32));
    assert(serialize_bits(w, 0, 31));
    serialize_int_relative(w, 10, 13);
}

// ---- U9: fail, reject and a failing object on a write ---------------------

// fail on a write returns false and records nothing: the stream keeps
// writing exactly what it would have.
fn TestU9FailOnWriteRecordsNothing() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(!serialize_fail(w, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE);
    assert(!serialize_fail(w));
    assert(!serialize_fail(w, SERIALIZE_ERROR_NONE));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE);
    assert(serialize_bits(w, 5, 3));
    assert(serialize_bool(w, true));
    assert(serialize_align(w));
    assert(serialize_uint8(w, 0xA5));
    serialize_flush(w);
    assert(serialize_bits_processed(w) == 16);
    assert(buf[0] == 0x0D && buf[1] == 0xA5);
}

// reject is read only: on a write it is caller misuse, and traps.
// want-abort: serialize: reject is read only
fn TestU9RejectOnWriteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_reject(w);
}

// want-abort: serialize: reject is read only
fn TestU9RejectOnMeasureAborts() {
    var m = serialize_measure_stream_init();
    serialize_reject(m);
}

struct RulingsRefuser { bits: u32 }

fn serialize<S>(s: S&, o: RulingsRefuser&) -> bool {
    guard serialize_bits(s, o.bits, 4) else { return false; }
    return false;
}

// A nested object whose serialize returns false on a write makes the object
// return false and records nothing.
fn TestU9ObjectFalseOnWriteRecordsNothing() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    var o = RulingsRefuser { bits: 9 };
    assert(!serialize_object(w, o));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE);
    assert(serialize_bits(w, 3, 4));
    serialize_flush(w);
    assert(serialize_bits_processed(w) == 8);
    assert(buf[0] == 0x39);
}

// The same on a measure (U6).
fn TestU6ObjectFalseOnMeasureRecordsNothing() {
    var m = serialize_measure_stream_init();
    var o = RulingsRefuser { bits: 9 };
    assert(!serialize_object(m, o));
    assert(serialize_error(m) == SERIALIZE_ERROR_NONE);
    assert(serialize_bits(m, 3, 4));
    assert(serialize_bits_processed(m) == 8);
}

// ---- U6: a measure makes every check a write makes -------------------------

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureIntOutOfRangeAborts() {
    var m = serialize_measure_stream_init();
    serialize_int(m, 11, 0, 10);
}

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureInt64OutOfRangeAborts() {
    var m = serialize_measure_stream_init();
    serialize_int64(m, -1, 0, 10);
}

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureInt128OutOfRangeAborts() {
    var m = serialize_measure_stream_init();
    serialize_int128(m, Int128 { lo: 11, hi: 0 }, Int128 { lo: 0, hi: 0 }, Int128 { lo: 10, hi: 0 });
}

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureFixed32OutOfRangeAborts() {
    var m = serialize_measure_stream_init();
    serialize_fixed32(m, 131073, 16, 16, -2, 2);
}

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureFixed64ZeroWidthOtherValueAborts() {
    var m = serialize_measure_stream_init();
    serialize_fixed64(m, 1, 48, 16, 0, 0);
}

// want-abort: serialize: value must be in [min, max]
fn TestU6MeasureFixed128OutOfRangeAborts() {
    var m = serialize_measure_stream_init();
    serialize_fixed128(m, Int128 { lo: 131073, hi: 0 }, 112, 16, -2, 2);
}

// want-abort: serialize: value must fit in bits
fn TestU6MeasureBitsOverWideAborts() {
    var m = serialize_measure_stream_init();
    serialize_bits(m, 8, 3);
}

// want-abort: serialize: value must fit in bits
fn TestU6MeasureBits64OverWideAborts() {
    var m = serialize_measure_stream_init();
    serialize_bits64(m, 0x10000000000, 40);
}

// want-abort: serialize: float must be finite
fn TestU6MeasureFloatNaNAborts() {
    var m = serialize_measure_stream_init();
    serialize_float(m, serialize_f32_from_bits(0x7FC00000));
}

// want-abort: serialize: double must be finite
fn TestU6MeasureDoubleInfinityAborts() {
    var m = serialize_measure_stream_init();
    serialize_double(m, serialize_f64_from_bits(0x7FF0000000000000));
}

// want-abort: serialize: compressed float value must be finite
fn TestU6MeasureCompressedFloatNaNAborts() {
    var m = serialize_measure_stream_init();
    serialize_compressed_float(m, serialize_f32_from_bits(0x7FC00000), 0.0, 1.0, 0.1);
}

// want-abort: serialize: compressed float value must be finite
fn TestU6MeasureCompressedFloatPrecomputedInfinityAborts() {
    var m = serialize_measure_stream_init();
    serialize_compressed_float_precomputed(m, serialize_f32_from_bits(0xFF800000), 1000, 10, 1.0, 0.0);
}

// The top decode check is a write check, so the measure makes it too.
// want-abort: serialize: compressed float declaration must decode its top to a finite value
fn TestU6MeasureCompressedFloatTopNotFiniteAborts() {
    var m = serialize_measure_stream_init();
    serialize_compressed_float_precomputed(m, 0.0, 1000, 10, 3.0e38, 3.0e38);
}

// A measure checks no room: it has no buffer.
fn TestU6MeasureHasNoRoomCheck() {
    var m = serialize_measure_stream_init();
    for i in 100 { assert(serialize_uint64(m, 0)); }
    assert(serialize_bits_processed(m) == 6400);
    assert(serialize_error(m) == SERIALIZE_ERROR_NONE);
}

// ---- U15: serialize_copy_string backs off to a whole character -------------

// dest is dest_size bytes of 0xAA; the result is `want`, and every byte after
// it is zero (the destination is NUL terminated).
fn rulings_copy(source: const u8[:], dest_size: i64, want: const u8[:]) {
    var dest: u8[16] = [0xAA; 16];
    serialize_copy_string(dest[0..dest_size], source);
    for i in want.len { assert(dest[i] == want[i]); }
    for i in dest_size - want.len { assert(dest[want.len + i] == 0); }
    for i in 16 - dest_size { assert(dest[dest_size + i] == 0xAA); }
}

// The reference's test_copy_string vectors, ill-formed ones included (goose
// strings are byte strings).
fn TestU15CopyStringBacksOffToAWholeCharacter() {
    rulings_copy("abc", 8, "abc");
    let nul: u8[4] = ['a', 0, 'b', 'c'];
    rulings_copy(nul, 8, "a");
    rulings_copy("abcdefghij", 4, "abc");
    let ee: u8[4] = [0xC3, 0xA9, 0xC3, 0xA9];
    let e: u8[2] = [0xC3, 0xA9];
    rulings_copy(ee, 4, e);
    rulings_copy(ee, 3, e);
    let grin: u8[5] = ['a', 0xF0, 0x9F, 0x98, 0x80];
    rulings_copy(grin, 3, "a");
    rulings_copy(grin, 4, "a");
    rulings_copy(grin, 5, "a");
    rulings_copy(grin, 6, grin);
    let stray: u8[4] = ['a', 'b', 0x80, 0x80];
    rulings_copy(stray, 4, "a");
    let tail: u8[4] = [0xC3, 0xA9, 0xA9, 0xA9];
    rulings_copy(tail, 4, "");
    rulings_copy("abc", 1, "");
}

// What copy_string returns, serialize_string with buffer_size = dest_size
// accepts.
fn TestU15CopyStringResultIsWritable() {
    let grin: u8[5] = ['a', 0xF0, 0x9F, 0x98, 0x80];
    var dest: u8[4] = [0; 4];
    serialize_copy_string(dest, grin);
    var n: i64 = 0;
    while n < dest.len && dest[n] != 0 { n += 1; }
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    assert(serialize_string(w, dest[0..n], 4));
}
