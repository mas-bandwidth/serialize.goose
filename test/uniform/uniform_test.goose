// test/uniform -- the uniform behaviour rules U1 to U16 (IMPLEMENTING.md,
// "Uniform behaviour: U1 to U16", reference v2.1.0) and the 2026-10-27 audit
// ledger's findings for this port. Each test names the rule it proves. None
// of these is a corpus vector: each is write-side, measure-side, API-shape or
// caller-misuse behaviour, which no stream observes.

import .serialize;

// `text` written as serialize_string(text, buffer_size), copied into `out`
// with zero slack behind it; returns the byte count.
fn uniform_string_wire(text: const u8[:], buffer_size: i64, out: u8[:]) -> i64 {
    var buf: u8[64] = [0; 64];
    var w = serialize_write_stream_init(buf);
    assert(serialize_string(w, text, buffer_size));
    serialize_flush(w);
    let n = serialize_bytes_processed(w);
    for i in n { out[i] = buf[i]; }
    return n;
}

// ---- U3, U4: string write checks, the measure included ---------------------

// U3: the measure follows the writer's rule. Text the writer refuses as
// misuse is misuse on a measure too, never a silent bound.
// want-abort: serialize: string must be valid UTF-8
fn TestU3MeasureStringInvalidUtf8Aborts() {
    var m = serialize_measure_stream_init();
    let bad: u8[2] = [0xC0, 0x80];
    serialize_string(m, bad, 16);
}

// want-abort: serialize: string must not contain a zero byte
fn TestU3MeasureStringNulAborts() {
    var m = serialize_measure_stream_init();
    let bad: u8[3] = [0x61, 0, 0x62];
    serialize_string(m, bad, 16);
}

// U4: the writer checks UTF-8 and NUL (kept since 2.0; pinned here).
// want-abort: serialize: string must be valid UTF-8
fn TestU4WriteStringInvalidUtf8Aborts() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    let bad: u8[3] = [0xED, 0xA0, 0x80];
    serialize_string(w, bad, 16);
}

// ---- U6: a measure refuses nothing ----------------------------------------

fn TestU6MeasureFailRecordsNothing() {
    var m = serialize_measure_stream_init();
    assert(!serialize_fail(m, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE));
    assert(serialize_error(m) == SERIALIZE_ERROR_NONE);
    assert(serialize_bits(m, 0, 3));
    assert(serialize_bits_processed(m) == 3);
}

// ---- U7: a reader never traps ----------------------------------------------

fn TestU7ReadNegativeBytesRefuses() {
    var data: u8[8] = [0; 8];
    var r = serialize_read_stream_init(data, -1);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var v: u32 = 7;
    assert(!serialize_bits(r, v, 1));
    assert(v == 7);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}

// The slack contract (DESIGN.md (d)) broken by the caller is misuse on read:
// refused, never an abort.
fn TestU7ReadMissingSlackRefuses() {
    var data: u8[8] = [0; 8];
    var r = serialize_read_stream_init(data, 1);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var v: u32 = 7;
    assert(!serialize_bits(r, v, 1));
}

fn TestU7StringReadBufferSizeBelowOneRefuses() {
    var data: u8[16] = [0; 16];
    var r = serialize_read_stream_init(data, 8);
    var out: u8[>..] = [];
    assert(!serialize_string(r, out, 0));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(r) == 0);
    var r2 = serialize_read_stream_init(data, 8);
    assert(!serialize_string(r2, out, -5));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}

// The failure state is checked first: a stream that already refused keeps
// its first reason through a misuse on read.
fn TestU7MisuseOnAFailedStreamKeepsTheFirstReason() {
    var data: u8[8] = [0; 8];
    var r = serialize_read_stream_init(data, 0);
    var v: u32 = 7;
    assert(!serialize_bits(r, v, 1));
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
    assert(!serialize_bits(r, v, 33));
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
}

// ---- U8: over-wide values on write are caught -----------------------------

// want-abort: serialize: value must fit in bits
fn TestU8BitsOverWideWriteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_bits(w, 8, 3);
}

// want-abort: serialize: value must fit in bits
fn TestU8Bits64OverWideWriteAborts() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    serialize_bits64(w, 0x10000000000, 40);
}

// ---- U9: one write-misuse mechanism ---------------------------------------

// Every write misuse aborts, naming its rule, exactly as compressed_float's
// non-finite value always did: a ranged value out of range...
// want-abort: serialize: value must be in [min, max]
fn TestU9IntOutOfRangeWriteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_int(w, 11, 0, 10);
}

// ...and a non-finite float, as a non-finite compressed_float.
// want-abort: serialize: float must be finite
fn TestU9FloatNonFiniteWriteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_float(w, serialize_f32_from_bits(0x7FC00000));
}

// want-abort: serialize: compressed float value must be finite
fn TestU9CompressedFloatNonFiniteWriteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_compressed_float(w, serialize_f32_from_bits(0x7F800000), 0.0, 1.0, 0.1);
}

// fail on a write or a measure returns false, never aborts and records
// nothing, the kind NONE included.
fn TestU9FailOnWriteAndMeasureNeverAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(!serialize_fail(w, SERIALIZE_ERROR_NONE));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE);
    var m = serialize_measure_stream_init();
    assert(!serialize_fail(m, SERIALIZE_ERROR_NONE));
    assert(!serialize_fail(m));
}

// ---- U10: a write checks room for the whole operation first ---------------
//
// A write that does not fit aborts (U9), so the proof is the abort's width:
// the whole operation's, never the part that fits
// (TestU10StringWritePastEndAbortsOnTheWholeOperation and its siblings in
// rulings_test.goose).

// ---- U12: end on a write or a measure is a no-op returning true ------------

fn TestU12EndOnWriteAndMeasureIsTrue() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    assert(!serialize_fail(w, SERIALIZE_ERROR_PAST_END));
    assert(serialize_error(w) == SERIALIZE_ERROR_NONE);
    assert(serialize_end(w));
    assert(serialize_bits_processed(w) == 0);
    var m = serialize_measure_stream_init();
    serialize_fail(m);
    assert(serialize_end(m));
    assert(serialize_bits_processed(m) == 0);
}

// ---- U14: the refusal names, and fail on a read ---------------------------

fn TestU14RefusalNamesAreTheFamilySpellings() {
    assert(serialize_refusal_name(0) == "none");
    assert(serialize_refusal_name(1) == "past_end");
    assert(serialize_refusal_name(2) == "value_out_of_range");
    assert(serialize_refusal_name(3) == "nonzero_padding");
    assert(serialize_refusal_name(4) == "trailing_data");
    assert(serialize_refusal_name(5) == "non_finite_float");
    assert(serialize_refusal_name(6) == "invalid_utf8");
    assert(serialize_refusal_name(7) == "embedded_nul");
    assert(serialize_refusal_name(8) == "non_canonical");
    assert(serialize_refusal_name(9) == "rejected");
}

// fail with no reason, or one outside the closed list, records rejected: no
// abort, and never none.
fn TestU14FailOnReadOutsideTheListRecordsRejected() {
    var data: u8[16] = [0; 16];
    var r = serialize_read_stream_init(data, 8);
    assert(!serialize_fail(r, SERIALIZE_ERROR_NONE));
    assert(serialize_refusal_name(serialize_error(r)) == "rejected");
    var r2 = serialize_read_stream_init(data, 8);
    assert(!serialize_fail(r2, 42));
    assert(serialize_refusal_name(serialize_error(r2)) == "rejected");
    var r3 = serialize_read_stream_init(data, 8);
    assert(!serialize_fail(r3, -1));
    assert(serialize_refusal_name(serialize_error(r3)) == "rejected");
    var r4 = serialize_read_stream_init(data, 8);
    assert(!serialize_fail(r4));
    assert(serialize_refusal_name(serialize_error(r4)) == "rejected");
}

// ---- U16: caller declarations, validated before any bits move -------------

fn uniform_wire_stream(data: u8[:]) -> ReadStream { return serialize_read_stream_init(data, 8); }

fn TestU16ReadBitsCountOutOfRangeRefuses() {
    var data: u8[16] = [0xFF; 16];
    var v: u32 = 7;
    var r = uniform_wire_stream(data);
    assert(!serialize_bits(r, v, 0));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(r) == 0);
    var r2 = uniform_wire_stream(data);
    assert(!serialize_bits(r2, v, 33));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var w: u64 = 7;
    var r3 = uniform_wire_stream(data);
    assert(!serialize_bits64(r3, w, 65));
    assert(serialize_error(r3) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(v == 7 && w == 7);
}

fn TestU16ReadRangedMinAboveMaxRefuses() {
    var data: u8[16] = [0; 16];
    var i: i32 = 7;
    var r = uniform_wire_stream(data);
    assert(!serialize_int(r, i, 5, 4));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var l: i64 = 7;
    var r2 = uniform_wire_stream(data);
    assert(!serialize_int64(r2, l, 5, 4));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var h = Int128 { lo: 7, hi: 0 };
    var r3 = uniform_wire_stream(data);
    assert(!serialize_int128(r3, h, Int128 { lo: 5, hi: 0 }, Int128 { lo: 4, hi: 0 }));
    assert(serialize_error(r3) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var f: i32 = 7;
    var r4 = uniform_wire_stream(data);
    assert(!serialize_fixed32(r4, f, 16, 16, 5, 4));
    assert(serialize_error(r4) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(i == 7 && l == 7 && h.lo == 7 && f == 7);
}

fn TestU16ReadFixedBadFormatRefuses() {
    var data: u8[16] = [0; 16];
    var f: i32 = 7;
    var r = uniform_wire_stream(data);
    assert(!serialize_fixed32(r, f, 16, 8, 0, 1));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var g: i64 = 7;
    var r2 = uniform_wire_stream(data);
    assert(!serialize_fixed64(r2, g, 0, 64, 0, 0));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}

// Ledger M (TestAuditFixedBoundsOutsideQFormat): Q16.16 holds whole units in
// [-32768, 32767], so [0, 40000] is a bad declaration. Before 2.1 the reader
// accepted an in-span offset off the wire and returned -1673527296 for a
// field whose min is 0.
fn TestU16ReadFixedBoundsOutsideQFormatRefuses() {
    var data: u8[16] = [0; 16];
    data[0] = 0x00; data[1] = 0x00; data[2] = 0x40; data[3] = 0x9C; // 2621440000, LSB first
    var r = serialize_read_stream_init(data, 4);
    var v: i32 = 7;
    assert(!serialize_fixed32(r, v, 16, 16, 0, 40000));
    assert(v == 7);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(r) == 0);

    // Ledger M (TestAuditFixed64BoundsOverflowRawWraps): Q48.16 [0, 2^50],
    // whose raw max overflows int64.
    var r2 = serialize_read_stream_init(data, 8);
    var w: i64 = 7;
    assert(!serialize_fixed64(r2, w, 48, 16, 0, 1 << 50));
    assert(w == 7);
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);

    // The edges of the format are a good declaration.
    var r3 = serialize_read_stream_init(data, 8);
    var e: i32 = 7;
    assert(serialize_fixed32(r3, e, 16, 16, -32768, 32767));
}

// want-abort: serialize: fixed min and max must fit the Q format
fn TestU16WriteFixedBoundsOutsideQFormatAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_fixed32(w, 0, 16, 16, 0, 40000);
}

// want-abort: serialize: fixed min and max must fit the Q format
fn TestU16MeasureFixedBoundsOutsideQFormatAborts() {
    var m = serialize_measure_stream_init();
    serialize_fixed64(m, 0, 48, 16, 0, 1 << 50);
}

fn TestU16ReadCompressedFloatBadDeclarationRefuses() {
    var data: u8[16] = [0; 16];
    var v: f32 = 7.0;
    var r = uniform_wire_stream(data);
    assert(!serialize_compressed_float(r, v, 1.0, 1.0, 0.1));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var r2 = uniform_wire_stream(data);
    assert(!serialize_compressed_float(r2, v, 0.0, 1.0, 0.0));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var r3 = uniform_wire_stream(data);
    assert(!serialize_compressed_float(r3, v, -3.0e38, 3.0e38, 1.0));
    assert(serialize_error(r3) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(v == 7.0);
    assert(serialize_bits_processed(r) == 0);
}

fn TestU16ReadPrecomputedBadConstantsRefuses() {
    var data: u8[16] = [0; 16];
    var v: f32 = 7.0;
    // bits not bits_required(0, max_integer_value)
    var r = uniform_wire_stream(data);
    assert(!serialize_compressed_float_precomputed(r, v, 1000, 1, 1.0, 0.0));
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    // max_integer_value outside [1, 4294967040]
    var r2 = uniform_wire_stream(data);
    assert(!serialize_compressed_float_precomputed(r2, v, 0, 0, 1.0, 0.0));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var r3 = uniform_wire_stream(data);
    assert(!serialize_compressed_float_precomputed(r3, v, 4294967295, 32, 1.0, 0.0));
    assert(serialize_error(r3) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    // delta not positive and finite
    var r4 = uniform_wire_stream(data);
    assert(!serialize_compressed_float_precomputed(r4, v, 1000, 10, 0.0, 0.0));
    assert(serialize_error(r4) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    var r5 = uniform_wire_stream(data);
    assert(!serialize_compressed_float_precomputed(r5, v, 1000, 10, serialize_f32_from_bits(0x7F800000), 0.0));
    assert(serialize_error(r5) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(v == 7.0);
    // the largest legal max_integer_value is a good declaration
    var r6 = uniform_wire_stream(data);
    assert(serialize_compressed_float_precomputed(r6, v, 4294967040, 32, 1.0, 0.0));
}

// want-abort: serialize: compressed float max_integer_value must be in [1, 4294967040]
fn TestU16WritePrecomputedMaxIntegerValueAboveLimitAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_compressed_float_precomputed(w, 0.5, 4294967295, 32, 1.0, 0.0);
}

// Ledger L (TestAuditCompressedFloatMeasureAcceptsMismatchedBits): the
// measure checked only [1,32], so a mismatched declaration measured 1 bit
// where the writer would need 10.
// want-abort: serialize: compressed float bits must match max_integer_value
fn TestU16MeasurePrecomputedMismatchedBitsAborts() {
    var m = serialize_measure_stream_init();
    serialize_compressed_float_precomputed(m, 0.5, 1000, 1, 1.0, 0.0);
}

// want-abort: serialize: compressed float delta must be positive and finite
fn TestU16MeasurePrecomputedBadDeltaAborts() {
    var m = serialize_measure_stream_init();
    serialize_compressed_float_precomputed(m, 0.5, 1000, 10, 0.0, 0.0);
}

fn TestU16ReadIntRelativePreviousOutsideDomainRefuses() {
    var data: u8[16] = [0xFF; 16];
    var r = uniform_wire_stream(data);
    var v: i32 = 7;
    assert(!serialize_int_relative(r, -1, v));
    assert(v == 7);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(r) == 0);
}

// Ledger H (TestAuditStringLimitedBuilderWireDriven): a string read into a
// limited builder whose capacity is below buffer_size - 1 let the WIRE
// choose a trap ("limited array capacity exceeded") by sending a length past
// the capacity. The declaration is checked against the destination before
// any bits move, and refused: never a trap, whatever the wire holds.
fn TestU16StringLimitedBuilderCapacityRefusesNeverTraps() {
    var wire: u8[72] = [0; 72];
    let n = uniform_string_wire("abcdefghij", 64, wire);
    var r = serialize_read_stream_init(wire, n);
    var v: u8[..4] = [];
    assert(!serialize_string(r, v, 64));
    assert(v.len == 0);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(r) == 0);

    // The same declaration with a short wire string is the same bad
    // declaration: refused, decided by the caller's arguments, not the data
    // (ledger H, TestAuditStringLimitedBuilderMisuseNotChecked).
    var short: u8[72] = [0; 72];
    let m = uniform_string_wire("ab", 64, short);
    var r2 = serialize_read_stream_init(short, m);
    var v2: u8[..4] = [];
    assert(!serialize_string(r2, v2, 64));
    assert(serialize_error(r2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}

// A builder that holds buffer_size - 1 bytes is a good declaration, at the
// limit; a growable builder has no capacity of its own.
fn TestU16StringBuilderAtCapacityAccepts() {
    var wire: u8[72] = [0; 72];
    let n = uniform_string_wire("abcd", 5, wire);
    var r = serialize_read_stream_init(wire, n);
    var v: u8[..4] = [];
    assert(serialize_string(r, v, 5));
    assert(v.len == 4 && v[3] == 'd');
    var r2 = serialize_read_stream_init(wire, n);
    var g: u8[>..] = [];
    assert(serialize_string(r2, g, 5));
    assert(g.len == 4);
}
