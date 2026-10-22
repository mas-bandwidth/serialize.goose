// test/int -- TestSerializeInt (STANDARD.md, int, int64, int128, uint128,
// int_relative; DESIGN.md (a), (c), (e)). It runs every record of the seven
// integer conformance files, pins the bits_required edge cases, the full-range
// int64 edges and the write latch one past each bound.

import os;
import .serialize;

// ---- small slices and numbers ----------------------------------------------

fn int_hex_nibble(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    abort("conformance: invalid hex digit");
}

fn int_parse_u64(s: const u8[:]) -> u64 {
    assert(s.len > 0);
    var v: u64 = 0;
    for i in s.len {
        let c = s[i];
        assert(c >= '0' && c <= '9');
        v = v * 10 + (c - '0');
    }
    return v;
}

fn int_parse_hex_bytes(s: const u8[:], out: u8[>..]&) {
    out.clear();
    var i = 0;
    while i < s.len {
        while i < s.len && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') { i += 1; }
        if i >= s.len { break; }
        assert(i + 1 < s.len);
        out.push((int_hex_nibble(s[i]) << 4) | int_hex_nibble(s[i + 1]));
        i += 2;
    }
}

fn int_starts_with(s: const u8[:], prefix: const u8[:]) -> bool {
    if s.len < prefix.len { return false; }
    for i in prefix.len {
        if s[i] != prefix[i] { return false; }
    }
    return true;
}

fn int_equals(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        if a[i] != b[i] { return false; }
    }
    return true;
}

fn int_trim_cr(s: const u8[:]) -> const u8[:] {
    if s.len > 0 && s[s.len - 1] == '\r' { return s[0..s.len - 1]; }
    return s;
}

// ---- up to 128-bit decimal / hexadecimal parsing ---------------------------

fn int_u128_shl(v: Uint128, n: i64) -> Uint128 {
    if n == 0 { return v; }
    if n >= 64 { return Uint128 { lo: 0, hi: v.lo << ((n - 64) as u64) }; }
    return Uint128 {
        lo: v.lo << (n as u64),
        hi: (v.hi << (n as u64)) | (v.lo >> ((64 - n) as u64)),
    };
}

struct IntParsed { v: Uint128, negative: bool }

// Signed decimal or 0x hexadecimal, up to 128 bits; a negative number is
// returned in two's complement, which is the lane form every comparison uses.
fn int_parse_number(s: const u8[:]) -> IntParsed {
    var i = 0;
    var negative = false;
    if i < s.len && s[i] == '-' { negative = true; i += 1; }
    var v = Uint128 { lo: 0, hi: 0 };
    if i + 1 < s.len && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X') {
        i += 2;
        while i < s.len {
            let d = int_hex_nibble(s[i]);
            v = serialize_u128_add(int_u128_shl(v, 4), Uint128 { lo: d, hi: 0 });
            i += 1;
        }
    } else {
        while i < s.len {
            let c = s[i];
            assert(c >= '0' && c <= '9');
            let d = (c - '0') as u64;
            v = serialize_u128_add(serialize_u128_add(int_u128_shl(v, 3), int_u128_shl(v, 1)),
                                   Uint128 { lo: d, hi: 0 });
            i += 1;
        }
    }
    if negative { v = serialize_u128_sub(Uint128 { lo: 0, hi: 0 }, v); }
    return IntParsed { v: v, negative: negative };
}

// ---- the vector record -----------------------------------------------------

struct IntRecord {
    has_op: bool,
    kind: i64,
    bits: i64,
    previous: i32,
    min: Int128,
    max: Int128,
    refused: bool,
    reason: i32,
    expect: Uint128,
    consumed: i64,
    canonical: bool,
    wire: u8[>..],
}

// A refused record's stream holds the reason the record states, the first
// refusal's (STANDARD.md, Refusal reasons), and is terminal.
fn int_check_terminal(r: ReadStream&, reason: i32) {
    assert(serialize_error(r) == reason);
    let before = serialize_bits_processed(r);
    var probe = true;
    assert(!serialize_bool(r, probe));
    assert(probe);
    assert(serialize_bits_processed(r) == before);
}

fn int_check_canonical(rec: IntRecord&) {
    var buf: u8[80] = [0xAA; 80];
    var w = serialize_write_stream_init(buf);
    var ok = false;
    if rec.kind == 1 {
        ok = if rec.bits <= 32 {
            serialize_bits(w, rec.expect.lo as! u32, rec.bits)
        } else {
            serialize_bits64(w, rec.expect.lo, rec.bits)
        };
    } else if rec.kind == 2 {
        ok = serialize_bool(w, rec.expect.lo != 0);
    } else if rec.kind == 3 {
        ok = serialize_int(w, rec.expect.lo as! i32, rec.min.lo as! i32, rec.max.lo as! i32);
    } else if rec.kind == 4 {
        ok = serialize_int64(w, rec.expect.lo as! i64, rec.min.lo as! i64, rec.max.lo as! i64);
    } else if rec.kind == 5 {
        ok = serialize_int128(w,
            Int128 { lo: rec.expect.lo, hi: rec.expect.hi }, rec.min, rec.max);
    } else if rec.kind == 6 {
        ok = serialize_uint128(w, Uint128 { lo: rec.expect.lo, hi: rec.expect.hi });
    } else if rec.kind == 7 {
        ok = serialize_int_relative(w, rec.previous, rec.expect.lo as! i32);
    } else {
        abort("conformance: unknown operation in int vector file");
    }
    assert(ok);
    serialize_flush(w);
    assert(serialize_bits_processed(w) == rec.consumed);
    assert(serialize_bytes_processed(w) == rec.wire.len);
    for i in rec.wire.len {
        assert(buf[i] == rec.wire[i]);
    }
}

fn int_run_record(rec: IntRecord&) -> i64 {
    if !rec.has_op { return 0; }
    var padded: u8[64] = [0xFF; 64];
    var r = serialize_read_stream_init_padded(padded, rec.wire);

    if rec.kind == 1 {
        var got32: u32 = 0xDEADBEEF;
        var got64: u64 = 0xDEADBEEFCAFEBABE;
        let ok = if rec.bits <= 32 {
            serialize_bits(r, got32, rec.bits)
        } else {
            serialize_bits64(r, got64, rec.bits)
        };
        if rec.refused {
            assert(!ok);
            assert(got32 == 0xDEADBEEF && got64 == 0xDEADBEEFCAFEBABE);
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok);
            let v: u64 = if rec.bits <= 32 { got32 } else { got64 };
            assert(rec.expect.hi == 0 && v == rec.expect.lo);
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 2 {
        var got = true;
        let ok = serialize_bool(r, got);
        if rec.refused {
            assert(!ok && got);
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok && got == (rec.expect.lo != 0));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 3 {
        var got: i32 = 0x1234567;
        let ok = serialize_int(r, got, rec.min.lo as! i32, rec.max.lo as! i32);
        if rec.refused {
            assert(!ok && got == 0x1234567);
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok && got == (rec.expect.lo as! i32));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 4 {
        var got: i64 = 0x0123456789ABCDEF;
        let ok = serialize_int64(r, got, rec.min.lo as! i64, rec.max.lo as! i64);
        if rec.refused {
            assert(!ok && got == 0x0123456789ABCDEF);
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok && got == (rec.expect.lo as! i64));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 5 {
        var got = Int128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 };
        let ok = serialize_int128(r, got, rec.min, rec.max);
        if rec.refused {
            assert(!ok);
            assert(serialize_int128_equal(got, Int128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 }));
            int_check_terminal(r, rec.reason);
        } else {
            let want = Int128 { lo: rec.expect.lo, hi: rec.expect.hi };
            assert(ok && serialize_int128_equal(got, want));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 6 {
        var got = Uint128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 };
        let ok = serialize_uint128(r, got);
        if rec.refused {
            assert(!ok);
            assert(serialize_uint128_equal(got, Uint128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 }));
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok && serialize_uint128_equal(got, Uint128 { lo: rec.expect.lo, hi: rec.expect.hi }));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else if rec.kind == 7 {
        var got: i32 = 0x1234567;
        let ok = serialize_int_relative(r, rec.previous, got);
        if rec.refused {
            assert(!ok && got == 0x1234567);
            int_check_terminal(r, rec.reason);
        } else {
            assert(ok && got == (rec.expect.lo as! i32));
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical { int_check_canonical(rec); }
        }
    } else {
        abort("conformance: unknown operation in int vector file");
    }
    return 1;
}

fn int_count_operations(content: const u8[:]) -> i64 {
    var count = 0;
    var start = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = int_trim_cr(content[start..i]);
            start = i + 1;
            if int_starts_with(line, "operation ") { count += 1; }
        }
    }
    return count;
}

// The reason a refused record states, from the closed list (STANDARD.md,
// Refusal reasons); a missing or unknown reason is a malformed vector.
fn int_reason(name: const u8[:]) -> i32 {
    for k in 8 {
        let kind = (k + 1) as! i32;
        if int_equals(name, serialize_refusal_name(kind)) { return kind; }
    }
    abort("conformance: refused record states no known reason");
}

fn int_run_file(filename: const u8[:]) -> i64 {
    var content: u8[>..] = [];
    assert(read_file(filename, content));
    let declared = int_count_operations(content);
    var rec = IntRecord {
        has_op: false, kind: 0, bits: 0, previous: 0,
        min: Int128 { lo: 0, hi: 0 }, max: Int128 { lo: 0, hi: 0 },
        refused: false, reason: SERIALIZE_ERROR_NONE, expect: Uint128 { lo: 0, hi: 0 }, consumed: 0,
        canonical: false, wire: [],
    };
    var count = 0;
    var start = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = int_trim_cr(content[start..i]);
            start = i + 1;
            if line.len == 0 {
                count += int_run_record(rec);
                rec.has_op = false;
                rec.kind = 0;
                rec.bits = 0;
                rec.previous = 0;
                rec.min = Int128 { lo: 0, hi: 0 };
                rec.max = Int128 { lo: 0, hi: 0 };
                rec.refused = false;
                rec.reason = SERIALIZE_ERROR_NONE;
                rec.expect = Uint128 { lo: 0, hi: 0 };
                rec.consumed = 0;
                rec.canonical = false;
                rec.wire.clear();
            } else if line[0] != '#' {
                if int_starts_with(line, "operation ") {
                    rec.has_op = true;
                    let op = line[10..];
                    if int_equals(op, "bits") { rec.kind = 1; }
                    else if int_equals(op, "bool") { rec.kind = 2; }
                    else if int_equals(op, "int") { rec.kind = 3; }
                    else if int_equals(op, "int64") { rec.kind = 4; }
                    else if int_equals(op, "int128") { rec.kind = 5; }
                    else if int_equals(op, "uint128") { rec.kind = 6; }
                    else if int_equals(op, "int_relative") { rec.kind = 7; }
                    else { rec.kind = 0; }
                } else if int_starts_with(line, "param bits = ") {
                    rec.bits = int_parse_u64(line[13..]) as! i64;
                } else if int_starts_with(line, "param previous = ") {
                    rec.previous = int_parse_u64(line[17..]) as! i32;
                } else if int_starts_with(line, "param min = ") {
                    let p = int_parse_number(line[12..]);
                    rec.min = Int128 { lo: p.v.lo, hi: p.v.hi };
                } else if int_starts_with(line, "param max = ") {
                    let p = int_parse_number(line[12..]);
                    rec.max = Int128 { lo: p.v.lo, hi: p.v.hi };
                } else if int_equals(line, "bytes") {
                    rec.wire.clear();
                } else if int_starts_with(line, "bytes ") {
                    int_parse_hex_bytes(line[6..], rec.wire);
                } else if int_starts_with(line, "expect refused ") {
                    rec.refused = true;
                    rec.reason = int_reason(line[15..]);
                } else if int_starts_with(line, "expect value = ") {
                    let val = line[15..];
                    if int_equals(val, "true") {
                        rec.expect = Uint128 { lo: 1, hi: 0 };
                    } else if int_equals(val, "false") {
                        rec.expect = Uint128 { lo: 0, hi: 0 };
                    } else {
                        let p = int_parse_number(val);
                        rec.expect = p.v;
                    }
                } else if int_starts_with(line, "consumed ") {
                    rec.consumed = int_parse_u64(line[9..]) as! i64;
                } else if int_equals(line, "writer canonical") {
                    rec.canonical = true;
                }
            }
        }
    }
    assert(count == declared);
    print(filename, ": ", count, " records");
    return count;
}

// ---- edge cases ------------------------------------------------------------

fn int_bits_required_edges() {
    assert(serialize_bits_required(0, 0) == 0);
    assert(serialize_bits_required(42, 42) == 0);
    assert(serialize_bits_required(0, 1) == 1);
    assert(serialize_bits_required(0, 2) == 2);
    assert(serialize_bits_required(0, 7) == 3);
    assert(serialize_bits_required(0, 8) == 4);
    assert(serialize_bits_required(0, 0xFFFFFFFF) == 32);
    assert(serialize_bits_required(0x80000000, 0x7FFFFFFF) == 32);

    assert(serialize_bits_required64(0, 0) == 0);
    assert(serialize_bits_required64(0, 0xFFFFFFFF) == 32);
    assert(serialize_bits_required64(0, 0x100000000) == 33);
    assert(serialize_bits_required64(0, 0xFFFFFFFFFFFFFFFF) == 64);
    assert(serialize_bits_required64(0x8000000000000000, 0x7FFFFFFFFFFFFFFF) == 64);

    assert(serialize_bits_required128(Uint128 { lo: 5, hi: 7 }, Uint128 { lo: 5, hi: 7 }) == 0);
    assert(serialize_bits_required128(Uint128 { lo: 0, hi: 0 },
                                      Uint128 { lo: 0xFFFFFFFFFFFFFFFF, hi: 0 }) == 64);
    assert(serialize_bits_required128(Uint128 { lo: 0, hi: 0 },
                                      Uint128 { lo: 0, hi: 1 }) == 65);
    assert(serialize_bits_required128(Uint128 { lo: 0, hi: 0 },
                                      Uint128 { lo: 0xFFFFFFFFFFFFFFFF, hi: 0xFFFFFFFFFFFFFFFF }) == 128);
}

fn int64_round_trip(value: i64, min: i64, max: i64, want_bits: i64) {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    assert(serialize_int64(w, value, min, max));
    serialize_flush(w);
    assert(serialize_bits_processed(w) == want_bits);
    var r = serialize_read_stream_init(buf, serialize_bytes_processed(w));
    var got: i64 = 0;
    assert(serialize_int64(r, got, min, max));
    assert(got == value);
    assert(serialize_bits_processed(r) == want_bits);
    var m = serialize_measure_stream_init();
    assert(serialize_int64(m, value, min, max));
    assert(serialize_bits_processed(m) == want_bits);
}

fn int64_full_range_edges() {
    let int64_min: i64 = -9223372036854775808;
    let int64_max: i64 = 9223372036854775807;
    int64_round_trip(int64_min, int64_min, int64_max, 64);
    int64_round_trip(0, int64_min, int64_max, 64);
    int64_round_trip(int64_max, int64_min, int64_max, 64);
    // A span the signed domain cannot hold: [0, 2^32] is 33 bits.
    int64_round_trip(0, 0, 4294967296, 33);
    int64_round_trip(4294967296, 0, 4294967296, 33);
    // Cross the 32/33-bit group boundary.
    int64_round_trip(0xFFFFFFFF, 0, 0x1FFFFFFFF, 33);
}

fn int_write_latches() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    assert(!serialize_int(w, 9, 0, 8));
    assert(serialize_error(w) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w) == 0);

    var w2 = serialize_write_stream_init(buf);
    assert(!serialize_int(w2, -6, -5, 5));
    assert(serialize_error(w2) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w2) == 0);

    var w3 = serialize_write_stream_init(buf);
    assert(!serialize_int64(w3, 4294967297, 0, 4294967296));
    assert(serialize_error(w3) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w3) == 0);

    var w4 = serialize_write_stream_init(buf);
    assert(!serialize_int64(w4, -1, 0, 4294967296));
    assert(serialize_error(w4) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w4) == 0);

    let lo = serialize_int128_from_int64(-5);
    let hi = serialize_int128_from_int64(5);
    var w5 = serialize_write_stream_init(buf);
    assert(!serialize_int128(w5, serialize_int128_from_int64(6), lo, hi));
    assert(serialize_error(w5) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w5) == 0);

    var w6 = serialize_write_stream_init(buf);
    assert(!serialize_int128(w6, serialize_int128_from_int64(-6), lo, hi));
    assert(serialize_error(w6) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(serialize_bits_processed(w6) == 0);
}

fn int_relative_measure_matches_write() {
    let steps: i32[8] = [1, 2, 6, 7, 23, 280, 4377, 69914];
    for i in 8 {
        let previous: i32 = 100;
        let current: i32 = previous + steps[i];
        var buf: u8[16] = [0; 16];
        var w = serialize_write_stream_init(buf);
        assert(serialize_int_relative(w, previous, current));
        var mm = serialize_measure_stream_init();
        assert(serialize_int_relative(mm, previous, current));
        assert(serialize_bits_processed(mm) == serialize_bits_processed(w));
    }
}

// goose: --debug
fn TestSerializeInt() {
    let n_bits = int_run_file("bits.txt");
    let n_bool = int_run_file("bool.txt");
    let n_int = int_run_file("int.txt");
    let n_int64 = int_run_file("int64.txt");
    let n_int128 = int_run_file("int128.txt");
    let n_uint128 = int_run_file("uint128.txt");
    let n_relative = int_run_file("int_relative.txt");
    assert(n_bits == 26);
    assert(n_bool == 5);
    assert(n_int == 26);
    assert(n_int64 == 27);
    assert(n_int128 == 25);
    assert(n_uint128 == 13);
    assert(n_relative == 49);

    int_bits_required_edges();
    int64_full_range_edges();
    int_write_latches();
    int_relative_measure_matches_write();
}

// want-abort: serialize: min must not be greater than max
fn TestSerializeIntMinGreaterAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_int(w, 0, 10, 0);
}

// want-abort: serialize: min must not be greater than max
fn TestSerializeInt128MinGreaterAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_int128(w, serialize_int128_from_int64(0),
                     serialize_int128_from_int64(10), serialize_int128_from_int64(0));
}

// want-abort: serialize: int_relative previous must be in [0, 2147483647]
fn TestSerializeIntRelativePreviousAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_int_relative(w, -1, 0);
}

// want-abort: serialize: int_relative current must be greater than previous
fn TestSerializeIntRelativeOrderAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_int_relative(w, 5, 5);
}
