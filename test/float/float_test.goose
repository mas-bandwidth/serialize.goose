// test/float -- TestSerializeFloat (STANDARD.md, float, double, fixed,
// compressed_float; DESIGN.md (a), (c), (e)). Every record of float.txt,
// double.txt, fixed.txt and compressed_float.txt is run; the runner prints the
// record count per file and fails unless it equals the file's own count.

import os;
import std;
import .serialize;

fn ff_hex_nibble(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    abort("conformance: invalid hex digit");
}

fn ff_starts_with(s: const u8[:], prefix: const u8[:]) -> bool {
    if s.len < prefix.len { return false; }
    for i in prefix.len {
        if s[i] != prefix[i] { return false; }
    }
    return true;
}

fn ff_equals(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        if a[i] != b[i] { return false; }
    }
    return true;
}

fn ff_trim_cr(s: const u8[:]) -> const u8[:] {
    if s.len > 0 && s[s.len - 1] == '\r' { return s[0..s.len - 1]; }
    return s;
}

fn ff_parse_hex_bytes(s: const u8[:], out: u8[>..]&) {
    out.clear();
    var i = 0;
    while i < s.len {
        while i < s.len && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') { i += 1; }
        if i >= s.len { break; }
        assert(i + 1 < s.len);
        let b = (ff_hex_nibble(s[i]) << 4) | ff_hex_nibble(s[i + 1]);
        out.push(b);
        i += 2;
    }
}

fn ff_parse_hex_u64(s: const u8[:]) -> u64 {
    assert(s.len > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'));
    var v: u64 = 0;
    for i in 2..s.len {
        v = (v << 4) | (ff_hex_nibble(s[i]) as u64);
    }
    return v;
}

fn ff_u128_add(a: Int128, b: Int128) -> Int128 {
    let lo = a.lo + b.lo;
    let carry: u64 = if lo < a.lo { 1 } else { 0 };
    return Int128 { lo: lo, hi: a.hi + b.hi + carry };
}

fn ff_u128_mul10_add(a: Int128, d: u64) -> Int128 {
    var v = Int128 { lo: 0, hi: 0 };
    for i in 10 { v = ff_u128_add(v, a); }
    v = ff_u128_add(v, Int128 { lo: d, hi: 0 });
    return v;
}

fn ff_u128_neg(a: Int128) -> Int128 {
    let lo = (a.lo ^ 0xffffffffffffffff) + 1;
    let carry: u64 = if lo == 0 { 1 } else { 0 };
    return Int128 { lo: lo, hi: (a.hi ^ 0xffffffffffffffff) + carry };
}

fn ff_parse_i128(s: const u8[:]) -> Int128 {
    assert(s.len > 0);
    var i = 0;
    var neg = false;
    if s[0] == '-' { neg = true; i = 1; }
    assert(i < s.len);
    var v = Int128 { lo: 0, hi: 0 };
    while i < s.len {
        let c = s[i];
        assert(c >= '0' && c <= '9');
        let d: u64 = c - '0';
        v = ff_u128_mul10_add(v, d);
        i += 1;
    }
    if neg { v = ff_u128_neg(v); }
    return v;
}

fn ff_i128_equal(a: Int128, b: Int128) -> bool { return a.lo == b.lo && a.hi == b.hi; }

struct FloatRecord {
    has_op: bool,
    op_kind: i64,          // 1 float, 2 double, 3 fixed, 4 compressed_float
    integer_bits: i64,
    fraction_bits: i64,
    min_i: i64,
    max_i: i64,
    res: f32,
    refused: bool,
    has_bits: bool,
    expect_bits: u64,
    expect_value: Int128,
    consumed: i64,
    canonical: bool,
    wire: u8[>..],
}

fn ff_reset(rec: FloatRecord&) {
    rec.has_op = false;
    rec.op_kind = 0;
    rec.integer_bits = 0;
    rec.fraction_bits = 0;
    rec.min_i = 0;
    rec.max_i = 0;
    rec.res = 1.0;
    rec.refused = false;
    rec.has_bits = false;
    rec.expect_bits = 0;
    rec.expect_value = Int128 { lo: 0, hi: 0 };
    rec.consumed = 0;
    rec.canonical = false;
    rec.wire.clear();
}

fn ff_parse_param_i64(s: const u8[:]) -> i64 {
    let v, ok = parse_int(s);
    assert(ok);
    return v;
}

fn ff_run_fixed(rec: FloatRecord&) -> bool {
    if rec.integer_bits + rec.fraction_bits <= 32 {
        var raw: i32 = 123456789;
        var padded: u8[64] = [0; 64];
        ff_fill_padded(rec, padded);
        let r = serialize_read_stream_init(padded, rec.wire.len);
        let ok = serialize_fixed32(r, raw, rec.integer_bits, rec.fraction_bits, rec.min_i as! i32, rec.max_i as! i32);
        return ff_finish_fixed32(rec, r, ok, raw);
    }
    if rec.integer_bits + rec.fraction_bits == 64 {
        var raw: i64 = 123456789;
        var padded: u8[64] = [0; 64];
        ff_fill_padded(rec, padded);
        let r = serialize_read_stream_init(padded, rec.wire.len);
        let ok = serialize_fixed64(r, raw, rec.integer_bits, rec.fraction_bits, rec.min_i, rec.max_i);
        return ff_finish_fixed64(rec, r, ok, raw);
    }
    assert(rec.integer_bits + rec.fraction_bits == 128);
    var raw = Int128 { lo: 0x1234, hi: 0x5678 };
    var padded: u8[64] = [0; 64];
    ff_fill_padded(rec, padded);
    let r = serialize_read_stream_init(padded, rec.wire.len);
    let ok = serialize_fixed128(r, raw, rec.integer_bits, rec.fraction_bits, rec.min_i, rec.max_i);
    return ff_finish_fixed128(rec, r, ok, raw);
}

fn ff_fill_padded(rec: FloatRecord&, padded: u8[:]) {
    for i in 64 { padded[i] = 0; }
    for i in rec.wire.len { padded[i] = rec.wire[i]; }
}

fn ff_check_bytes(w: WriteStream&, rec: FloatRecord&) {
    serialize_flush(w);
    assert(serialize_bits_processed(w) == rec.consumed);
    assert(serialize_bytes_processed(w) == rec.wire.len);
}

fn ff_finish_fixed32(rec: FloatRecord&, r: ReadStream&, ok: bool, raw: i32) -> bool {
    if rec.refused {
        assert(!ok);
        assert(raw == 123456789);
        return true;
    }
    assert(ok);
    let wide = Int128 { lo: raw as! u64, hi: if raw < 0 { 0xffffffffffffffff } else { 0 } };
    return ff_fixed_success(rec, r, wide, 1);
}
fn ff_finish_fixed64(rec: FloatRecord&, r: ReadStream&, ok: bool, raw: i64) -> bool {
    if rec.refused {
        assert(!ok);
        assert(raw == 123456789);
        return true;
    }
    assert(ok);
    let wide = Int128 { lo: raw as! u64, hi: if raw < 0 { 0xffffffffffffffff } else { 0 } };
    return ff_fixed_success(rec, r, wide, 2);
}
fn ff_finish_fixed128(rec: FloatRecord&, r: ReadStream&, ok: bool, raw: Int128) -> bool {
    if rec.refused {
        assert(!ok);
        assert(raw.lo == 0x1234 && raw.hi == 0x5678);
        return true;
    }
    assert(ok);
    return ff_fixed_success(rec, r, raw, 3);
}
fn ff_fixed_success(rec: FloatRecord&, r: ReadStream&, raw: Int128, width: i64) -> bool {
    assert(ff_i128_equal(raw, rec.expect_value));
    assert(serialize_bits_processed(r) == rec.consumed);
    if rec.canonical {
        var buf: u8[32] = [0xAA; 32];
        var w = serialize_write_stream_init(buf);
        if width == 1 {
            assert(serialize_fixed32(w, raw.lo as! i32, rec.integer_bits, rec.fraction_bits, rec.min_i as! i32, rec.max_i as! i32));
        } else if width == 2 {
            assert(serialize_fixed64(w, raw.lo as! i64, rec.integer_bits, rec.fraction_bits, rec.min_i, rec.max_i));
        } else {
            assert(serialize_fixed128(w, raw, rec.integer_bits, rec.fraction_bits, rec.min_i, rec.max_i));
        }
        ff_check_bytes(w, rec);
        for i in rec.wire.len { assert(buf[i] == rec.wire[i]); }
    }
    return true;
}

fn ff_run_float(rec: FloatRecord&) -> bool {
    var got: f32 = 1.0;
    var padded: u8[64] = [0; 64];
    ff_fill_padded(rec, padded);
    let r = serialize_read_stream_init(padded, rec.wire.len);
    let ok = serialize_float(r, got);
    if rec.refused {
        assert(!ok);
        assert(serialize_f32_bits(got) == 0x3F800000);
        return true;
    }
    assert(ok);
    assert(serialize_f32_bits(got) as u64 == rec.expect_bits);
    assert(serialize_bits_processed(r) == rec.consumed);
    if rec.canonical {
        var buf: u8[16] = [0xAA; 16];
        var w = serialize_write_stream_init(buf);
        assert(serialize_float(w, got));
        ff_check_bytes(w, rec);
        for i in rec.wire.len { assert(buf[i] == rec.wire[i]); }
    }
    return true;
}

fn ff_run_double(rec: FloatRecord&) -> bool {
    var got: f64 = 1.0;
    var padded: u8[64] = [0; 64];
    ff_fill_padded(rec, padded);
    let r = serialize_read_stream_init(padded, rec.wire.len);
    let ok = serialize_double(r, got);
    if rec.refused {
        assert(!ok);
        assert(serialize_f64_bits(got) == 0x3FF0000000000000);
        return true;
    }
    assert(ok);
    assert(serialize_f64_bits(got) == rec.expect_bits);
    assert(serialize_bits_processed(r) == rec.consumed);
    if rec.canonical {
        var buf: u8[16] = [0xAA; 16];
        var w = serialize_write_stream_init(buf);
        assert(serialize_double(w, got));
        ff_check_bytes(w, rec);
        for i in rec.wire.len { assert(buf[i] == rec.wire[i]); }
    }
    return true;
}

fn ff_run_compressed(rec: FloatRecord&) -> bool {
    var got: f32 = 1.0;
    var padded: u8[64] = [0; 64];
    ff_fill_padded(rec, padded);
    let r = serialize_read_stream_init(padded, rec.wire.len);
    let ok = serialize_compressed_float(r, got, rec.min_i as f32, rec.max_i as f32, rec.res);
    if rec.refused {
        assert(!ok);
        assert(serialize_f32_bits(got) == 0x3F800000);
        return true;
    }
    assert(ok);
    assert(serialize_f32_bits(got) as u64 == rec.expect_bits);
    assert(serialize_bits_processed(r) == rec.consumed);
    return true;
}

fn ff_run_record(rec: FloatRecord&) -> i64 {
    if !rec.has_op { return 0; }
    if rec.op_kind == 1 { assert(ff_run_float(rec)); }
    else if rec.op_kind == 2 { assert(ff_run_double(rec)); }
    else if rec.op_kind == 3 { assert(ff_run_fixed(rec)); }
    else if rec.op_kind == 4 { assert(ff_run_compressed(rec)); }
    else { abort("conformance: unknown operation"); }
    return 1;
}

fn ff_run_file(filename: const u8[:], kind: i64) -> i64 {
    var content: u8[>..] = [];
    assert(read_file(filename, content));
    var rec = FloatRecord {
        has_op: false, op_kind: 0, integer_bits: 0, fraction_bits: 0,
        min_i: 0, max_i: 0, res: 1.0, refused: false, has_bits: false,
        expect_bits: 0, expect_value: Int128 { lo: 0, hi: 0 }, consumed: 0,
        canonical: false, wire: [],
    };
    var count = 0;
    var start = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = ff_trim_cr(content[start..i]);
            start = i + 1;
            if line.len == 0 {
                count += ff_run_record(rec);
                ff_reset(rec);
                rec.op_kind = kind;
            } else if line[0] != '#' {
                if ff_starts_with(line, "operation ") {
                    rec.has_op = true;
                } else if ff_starts_with(line, "param integer_bits = ") {
                    rec.integer_bits = ff_parse_param_i64(line[21..]);
                } else if ff_starts_with(line, "param fraction_bits = ") {
                    rec.fraction_bits = ff_parse_param_i64(line[22..]);
                } else if ff_starts_with(line, "param min = ") {
                    rec.min_i = ff_parse_param_i64(line[12..]);
                } else if ff_starts_with(line, "param max = ") {
                    rec.max_i = ff_parse_param_i64(line[12..]);
                } else if ff_starts_with(line, "param res = ") {
                    let v, ok = parse_flt(line[12..]);
                    assert(ok);
                    rec.res = v as! f32;
                } else if ff_equals(line, "bytes") {
                    rec.wire.clear();
                } else if ff_starts_with(line, "bytes ") {
                    ff_parse_hex_bytes(line[6..], rec.wire);
                } else if ff_equals(line, "expect refused") {
                    rec.refused = true;
                } else if ff_starts_with(line, "expect bits = ") {
                    rec.expect_bits = ff_parse_hex_u64(line[14..]);
                    rec.has_bits = true;
                } else if ff_starts_with(line, "expect value = ") {
                    rec.expect_value = ff_parse_i128(line[15..]);
                } else if ff_starts_with(line, "consumed ") {
                    let v, ok = parse_int(line[9..]);
                    assert(ok);
                    rec.consumed = v;
                } else if ff_equals(line, "writer canonical") {
                    rec.canonical = true;
                }
            }
        }
    }
    return count;
}

fn ff_float_round_trip(bits: u32) {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    assert(serialize_float(w, serialize_f32_from_bits(bits)));
    serialize_flush(w);
    assert(serialize_bits_processed(w) == 32);
    let expected: u32 = bits;
    assert(buf[0] == expected as! u8);
    assert(buf[1] == (expected >> 8) as! u8);
    assert(buf[2] == (expected >> 16) as! u8);
    assert(buf[3] == (expected >> 24) as! u8);
    var r = serialize_read_stream_init(buf, 4);
    var got: f32 = 0.0;
    assert(serialize_float(r, got));
    assert(serialize_f32_bits(got) == bits);
}

fn ff_test_float_bit_transparency() {
    // every float32 NaN class (quiet, signaling, payload, negative) and both
    // zeros, plus the infinities (STANDARD.md, float: bit transparency).
    ff_float_round_trip(0x00000000);
    ff_float_round_trip(0x80000000);
    ff_float_round_trip(0x7F800000);
    ff_float_round_trip(0xFF800000);
    ff_float_round_trip(0x7FC00000);
    ff_float_round_trip(0xFFC00000);
    ff_float_round_trip(0x7F800001);
    ff_float_round_trip(0xFF800001);
    ff_float_round_trip(0x7FDEAD00);
    ff_float_round_trip(0xFFFFFFFF);
    ff_float_round_trip(0x00000001);
}

fn ff_test_compressed_boundaries() {
    var buf: u8[16] = [0; 16];
    var vals: f32[5] = [0.0, 10.0, 9.995, serialize_f32_from_bits(0x41200001), serialize_f32_from_bits(0x80000001)];
    var codes: u32[5] = [0x00000000, 0x41200000, 0x41200000, 0x41200000, 0x00000000];
    for k in 5 {
        var w = serialize_write_stream_init(buf);
        assert(serialize_compressed_float(w, vals[k], 0.0, 10.0, 0.01));
        serialize_flush(w);
        var r = serialize_read_stream_init(buf, 2);
        var got: f32 = 0.0;
        assert(serialize_compressed_float(r, got, 0.0, 10.0, 0.01));
        assert(serialize_f32_bits(got) as u64 == codes[k] as u64);
    }
}

// goose: --debug
fn TestSerializeFloat() {
    ff_test_float_bit_transparency();
    ff_test_compressed_boundaries();
    let n_float = ff_run_file("float.txt", 1);
    let n_double = ff_run_file("double.txt", 2);
    let n_fixed = ff_run_file("fixed.txt", 3);
    let n_compressed = ff_run_file("compressed_float.txt", 4);
    print("float.txt: ", n_float, " records");
    print("double.txt: ", n_double, " records");
    print("fixed.txt: ", n_fixed, " records");
    print("compressed_float.txt: ", n_compressed, " records");
    assert(n_float == 18);
    assert(n_double == 18);
    assert(n_fixed == 34);
    assert(n_compressed == 29);
}

// want-abort: serialize: compressed float min must be less than max
fn TestSerializeFloatCompressedMinAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_compressed_float(w, 0.5, 1.0, 1.0, 1.0);
}

// want-abort: serialize: compressed float res must be greater than zero
fn TestSerializeFloatCompressedResAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_compressed_float(w, 0.5, 0.0, 1.0, 0.0);
}

// want-abort: serialize: integer_bits + fraction_bits must equal the storage width
fn TestSerializeFloatBadQFormatAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_fixed32(w, 0, 8, 7, 0, 1);
}

// want-abort: serialize: min must not be greater than max
fn TestSerializeFloatFixedMinMaxAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_fixed32(w, 0, 16, 16, 1, 0);
}

// want-abort: serialize: compressed float value must be finite
fn TestSerializeFloatCompressedNonFiniteAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_compressed_float(w, serialize_f32_from_bits(0x7F800000), 0.0, 1.0, 0.01);
}

// fixed's WRITER refuses a raw value outside [min,max] in Q form, latches
// VALUE_OUT_OF_RANGE and writes nothing for that call (STANDARD.md, fixed;
// DESIGN.md (a), The latched kinds). The corpus pins only the reader's
// refusal, so this is the write side's witness, at every storage width and in
// the zero-width (min == max) case. Q16.16, Q48.16, Q112.16 over [-2,2]: the
// raw bounds are -131072 and 131072.
fn TestSerializeFixedWriteRefusesOutOfRange() {
    let lo_out = Int128 { lo: 0xFFFFFFFFFFFDFFFF, hi: 0xFFFFFFFFFFFFFFFF }; // -131073
    for k in 6 {
        var buf: u8[32] = [0; 32];
        var w = serialize_write_stream_init(buf);
        // The bounds themselves are accepted.
        if k < 2 {
            assert(serialize_fixed32(w, 131072, 16, 16, -2, 2));
            assert(serialize_fixed32(w, -131072, 16, 16, -2, 2));
        } else if k < 4 {
            assert(serialize_fixed64(w, 131072, 48, 16, -2, 2));
            assert(serialize_fixed64(w, -131072, 48, 16, -2, 2));
        } else {
            assert(serialize_fixed128(w, Int128 { lo: 131072, hi: 0 }, 112, 16, -2, 2));
            assert(serialize_fixed128(w, Int128 { lo: 0xFFFFFFFFFFFE0000, hi: 0xFFFFFFFFFFFFFFFF }, 112, 16, -2, 2));
        }
        let before = serialize_bits_processed(w);
        assert(before == 38); // two writes of 19 bits: span 262144
        // One past each bound is refused.
        var ok = true;
        if k == 0 { ok = serialize_fixed32(w, 131073, 16, 16, -2, 2); }
        if k == 1 { ok = serialize_fixed32(w, -131073, 16, 16, -2, 2); }
        if k == 2 { ok = serialize_fixed64(w, 131073, 48, 16, -2, 2); }
        if k == 3 { ok = serialize_fixed64(w, -131073, 48, 16, -2, 2); }
        if k == 4 { ok = serialize_fixed128(w, Int128 { lo: 131073, hi: 0 }, 112, 16, -2, 2); }
        if k == 5 { ok = serialize_fixed128(w, lo_out, 112, 16, -2, 2); }
        assert(!ok);
        assert(serialize_error(w) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
        assert(serialize_bits_processed(w) == before);
        // Failure is terminal: an in-range write after it is refused too.
        assert(!serialize_fixed32(w, 0, 16, 16, -2, 2));
        assert(serialize_bits_processed(w) == before);
    }
    // Zero width (min == max): only the one value is writable, in no bits.
    var zbuf: u8[8] = [0; 8];
    var z = serialize_write_stream_init(zbuf);
    assert(serialize_fixed32(z, 65536, 16, 16, 1, 1));
    assert(serialize_bits_processed(z) == 0);
    assert(!serialize_fixed32(z, 65537, 16, 16, 1, 1));
    assert(serialize_error(z) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}
