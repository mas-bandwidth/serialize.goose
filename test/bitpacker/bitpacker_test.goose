// test/bitpacker -- TestBitpacker (STANDARD.md, General Conventions,
// Bit-Level Primitives, Reader Obligations; DESIGN.md (a), (b), (c), (d), (e)).

import os;
import .serialize;

fn bitpacker_patterned_value(w: i64, o: i64) -> u64 {
    let base: u64 = 0xD6E8FEB86659FD93 ^ ((o as u64) * 0x9E3779B97F4A7C15) ^ (w as u64);
    let mask: u64 = if w == 64 { 0xffffffffffffffff } else { ((1 as u64) << (w as u64)) - 1 };
    let v = base & mask;
    let top_bit: u64 = (1 as u64) << ((w - 1) as u64);
    return (v | 1) | top_bit;
}

fn bitpacker_oracle_set_bit(buf: u8[:], bit_index: i64, bit_val: u64) {
    if (bit_val & 1) != 0 {
        let byte_idx = bit_index >> 3;
        let shift = (bit_index & 7) as u8;
        buf[byte_idx] = buf[byte_idx] | ((1 as u8) << shift);
    }
}

fn test_golden_sequence() {
    var buf: u8[256] = [0; 256];
    var w = serialize_write_stream_init(buf);
    assert(serialize_bits_processed(w) == 0);
    assert(serialize_bytes_processed(w) == 0);
    assert(serialize_bits_available(w) == 256 * 8);

    assert(serialize_bits(w, 0, 1));
    assert(serialize_bits(w, 1, 1));
    assert(serialize_bits(w, 10, 8));
    assert(serialize_bits(w, 255, 8));
    assert(serialize_bits(w, 1000, 10));
    assert(serialize_bits(w, 50000, 16));
    assert(serialize_bits(w, 9999999, 32));
    serialize_flush(w);

    let expected_bits = 1 + 1 + 8 + 8 + 10 + 16 + 32;
    assert(serialize_bits_processed(w) == expected_bits);
    assert(serialize_bytes_processed(w) == 10);
    assert(serialize_bits_available(w) == 256 * 8 - expected_bits);

    let golden: u8[10] = [0x2A, 0xFC, 0xA3, 0x0F, 0x35, 0xFC, 0x67, 0x89, 0x09, 0x00];
    for i in 10 {
        assert(buf[i] == golden[i]);
    }

    var r = serialize_read_stream_init(buf, 10);
    assert(serialize_bits_processed(r) == 0);
    assert(serialize_bits_remaining(r) == 80);

    var a: u32 = 99;
    var b: u32 = 99;
    var c: u32 = 99;
    var d: u32 = 99;
    var e: u32 = 99;
    var f: u32 = 99;
    var g: u32 = 99;
    assert(serialize_bits(r, a, 1) && a == 0);
    assert(serialize_bits(r, b, 1) && b == 1);
    assert(serialize_bits(r, c, 8) && c == 10);
    assert(serialize_bits(r, d, 8) && d == 255);
    assert(serialize_bits(r, e, 10) && e == 1000);
    assert(serialize_bits(r, f, 16) && f == 50000);
    assert(serialize_bits(r, g, 32) && g == 9999999);
    assert(serialize_bits_processed(r) == expected_bits);
    assert(serialize_bytes_processed(r) == 10);
    assert(serialize_bits_remaining(r) == 4);

    // 4 trailing bits remain in the 10-byte stream; reading 4 bits succeeds,
    // reading 1 more refuses with PAST_END.
    var tail: u32 = 99;
    assert(serialize_bits(r, tail, 4) && tail == 0);
    assert(serialize_bits_remaining(r) == 0);
    var past: u32 = 77;
    assert(!serialize_bits(r, past, 1));
    assert(past == 77);
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
}

fn test_oracle_and_round_trip() {
    for o in 64 {
        for w in 1..65 {
            var buf: u8[32] = [0; 32];
            var oracle: u8[32] = [0; 32];
            var ws = serialize_write_stream_init(buf);

            var bit_pos = 0;
            for k in o {
                let bit = (k & 1) as u32;
                assert(serialize_bits(ws, bit, 1));
                bitpacker_oracle_set_bit(oracle, bit_pos, bit);
                bit_pos += 1;
            }

            let val = bitpacker_patterned_value(w, o);
            if w <= 32 {
                assert(serialize_bits(ws, val as! u32, w));
            } else {
                assert(serialize_bits64(ws, val, w));
            }
            for b in w {
                bitpacker_oracle_set_bit(oracle, bit_pos, (val >> (b as u64)) & 1);
                bit_pos += 1;
            }

            // Follow with 3 extra bits to verify scratch state after the width-w write.
            assert(serialize_bits(ws, 5, 3));
            bitpacker_oracle_set_bit(oracle, bit_pos, 1);
            bitpacker_oracle_set_bit(oracle, bit_pos + 1, 0);
            bitpacker_oracle_set_bit(oracle, bit_pos + 2, 1);
            bit_pos += 3;

            serialize_flush(ws);
            let nbytes = serialize_bytes_processed(ws);
            assert(nbytes == (bit_pos + 7) / 8);
            for i in nbytes {
                assert(buf[i] == oracle[i]);
            }

            // Poison the slack bytes past nbytes with 0xFF to prove the reader
            // never interprets slack bytes (STANDARD.md, Reader Obligations).
            var poisoned: u8[32] = [0xFF; 32];
            for i in nbytes {
                poisoned[i] = buf[i];
            }

            var rs = serialize_read_stream_init(poisoned, nbytes);
            for k in o {
                var bit: u32 = 9;
                assert(serialize_bits(rs, bit, 1));
                assert(bit == ((k & 1) as u32));
            }
            if w <= 32 {
                var got32: u32 = 0;
                assert(serialize_bits(rs, got32, w));
                let got32_u64: u64 = got32;
                assert(got32_u64 == val);
            } else {
                var got64: u64 = 0;
                assert(serialize_bits64(rs, got64, w));
                assert(got64 == val);
            }
            var post: u32 = 0;
            assert(serialize_bits(rs, post, 3) && post == 5);
            assert(serialize_bits_processed(rs) == bit_pos);

            // Also verify via serialize_read_stream_init_padded.
            var padded_dst: u8[32] = [0xAA; 32];
            var rp = serialize_read_stream_init_padded(padded_dst, buf[0..nbytes]);
            for k in o {
                var bit: u32 = 9;
                assert(serialize_bits(rp, bit, 1));
                assert(bit == ((k & 1) as u32));
            }
            var got_p: u64 = 0;
            assert(serialize_bits64(rp, got_p, w));
            assert(got_p == val);
            var post_p: u32 = 0;
            assert(serialize_bits(rp, post_p, 3) && post_p == 5);
        }
    }
}

fn test_fixed_width_and_align() {
    for shift in 8 {
        var buf: u8[32] = [0; 32];
        var w = serialize_write_stream_init(buf);
        var m = serialize_measure_stream_init();

        for i in shift {
            assert(serialize_bool(w, (i & 1) == 0));
            assert(serialize_bool(m, (i & 1) == 0));
        }
        assert(serialize_uint8(w, 0xA5));
        assert(serialize_uint16(w, 0xBEEF));
        assert(serialize_uint32(w, 0xCAFEBABE));
        assert(serialize_uint64(w, 0x0123456789ABCDEF));
        assert(serialize_align(w));
        assert(serialize_uint8(w, 0x5A));
        serialize_flush(w);

        assert(serialize_uint8(m, 0xA5));
        assert(serialize_uint16(m, 0xBEEF));
        assert(serialize_uint32(m, 0xCAFEBABE));
        assert(serialize_uint64(m, 0x0123456789ABCDEF));
        assert(serialize_align(m));
        assert(serialize_uint8(m, 0x5A));
        assert(serialize_bits_processed(m) >= serialize_bits_processed(w));

        var r = serialize_read_stream_init(buf, serialize_bytes_processed(w));
        for i in shift {
            var b = false;
            assert(serialize_bool(r, b));
            assert(b == ((i & 1) == 0));
        }
        var u8v: u8 = 0;
        var u16v: u16 = 0;
        var u32v: u32 = 0;
        var u64v: u64 = 0;
        var tail8: u8 = 0;
        assert(serialize_uint8(r, u8v) && u8v == 0xA5);
        assert(serialize_uint16(r, u16v) && u16v == 0xBEEF);
        assert(serialize_uint32(r, u32v) && u32v == 0xCAFEBABE);
        assert(serialize_uint64(r, u64v) && u64v == 0x0123456789ABCDEF);
        assert(serialize_align(r));
        assert(serialize_align_bits(r) == 0);
        assert(serialize_uint8(r, tail8) && tail8 == 0x5A);
        assert(serialize_bits_remaining(r) == 0);
    }
}

fn test_packer_bytes() {
    for head_bytes in 10 {
        for count in 20 {
            var buf1: u8[64] = [0xCC; 64];
            var buf2: u8[64] = [0xCC; 64];
            var w1 = serialize_write_stream_init(buf1);
            var w2 = serialize_write_stream_init(buf2);

            // Write 3 bits then align so scratch_bits is a multiple of 8 when head_bytes > 0.
            assert(serialize_bits(w1, 5, 3));
            assert(serialize_align(w1));
            assert(serialize_bits(w2, 5, 3));
            assert(serialize_align(w2));

            for i in head_bytes {
                let b = ((i * 17 + 5) & 0xFF) as! u8;
                assert(serialize_uint8(w1, b));
                assert(serialize_uint8(w2, b));
            }

            var payload: u8[20] = [0; 20];
            for i in count {
                payload[i] = ((i * 31 + 9) & 0xFF) as! u8;
                assert(serialize_uint8(w2, payload[i]));
            }
            serialize_packer_write_bytes(w1, payload[0..count]);

            // Write trailing bits after the byte block to verify scratch reload.
            assert(serialize_bits(w1, 0x12345, 19));
            assert(serialize_bits(w2, 0x12345, 19));
            serialize_flush(w1);
            serialize_flush(w2);

            assert(serialize_bits_processed(w1) == serialize_bits_processed(w2));
            let nbytes = serialize_bytes_processed(w1);
            for i in nbytes {
                assert(buf1[i] == buf2[i]);
            }

            // Read back using serialize_packer_read_bytes.
            var r = serialize_read_stream_init(buf1, nbytes);
            var lead: u32 = 0;
            assert(serialize_bits(r, lead, 3) && lead == 5);
            assert(serialize_align(r));
            for i in head_bytes {
                var hb: u8 = 0;
                assert(serialize_uint8(r, hb));
                assert(hb == (((i * 17 + 5) & 0xFF) as! u8));
            }
            var got_payload: u8[20] = [0xEE; 20];
            serialize_packer_read_bytes(r, got_payload[0..count]);
            for i in count {
                assert(got_payload[i] == payload[i]);
            }
            var trail: u32 = 0;
            assert(serialize_bits(r, trail, 19) && trail == 0x12345);
        }
    }
}

// Rowan's mandatory check: feed VALID data with plenty of remaining bits after
// a forced read error (both via serialize_fail and via a data-triggered refusal
// in byte 0) and prove every subsequent read stays refused, leaves its
// destination untouched, and consumes 0 bits. Removing the latch guard in
// serialize_read_check turns this test red because bits <= num_bits - bits_read
// holds over the remaining valid data.
fn test_read_latch_over_valid_data() {
    var valid_data: u8[24] = [
        0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x00,
        0, 0, 0, 0, 0, 0, 0, 0
    ];

    // Case 1: explicit serialize_fail(r) when 128 valid bits remain.
    var r1 = serialize_read_stream_init(valid_data, 16);
    assert(serialize_bits_remaining(r1) == 128);
    assert(!serialize_fail(r1));
    assert(serialize_error(r1) == SERIALIZE_ERROR_REJECTED);
    assert(serialize_bits_remaining(r1) == 128);

    var b1 = false;
    var u32_1: u32 = 0x13572468;
    var u64_1: u64 = 0x1122334455667788;
    var u8_1: u8 = 0x42;
    var u16_1: u16 = 0x4242;
    assert(!serialize_bool(r1, b1) && !b1);
    assert(!serialize_bits(r1, u32_1, 8) && u32_1 == 0x13572468);
    assert(!serialize_bits64(r1, u64_1, 16) && u64_1 == 0x1122334455667788);
    assert(!serialize_uint8(r1, u8_1) && u8_1 == 0x42);
    assert(!serialize_uint16(r1, u16_1) && u16_1 == 0x4242);
    assert(!serialize_uint32(r1, u32_1) && u32_1 == 0x13572468);
    assert(!serialize_uint64(r1, u64_1) && u64_1 == 0x1122334455667788);
    assert(!serialize_align(r1));
    assert(serialize_bits_processed(r1) == 0);
    assert(serialize_error(r1) == SERIALIZE_ERROR_REJECTED);

    // Case 2: data-triggered refusal (nonzero align padding in byte 0) when
    // 127 valid bits remain in the stream.
    var r2 = serialize_read_stream_init(valid_data, 16);
    var first_bit = false;
    assert(serialize_bool(r2, first_bit) && first_bit);
    assert(serialize_bits_processed(r2) == 1);
    assert(serialize_bits_remaining(r2) == 127);

    // Byte 0 is 0xFF, so bits 1..7 are 1s -> serialize_align refuses with NONZERO_PADDING
    // while 120 valid bits (bytes 1..15) remain in the stream.
    assert(!serialize_align(r2));
    assert(serialize_error(r2) == SERIALIZE_ERROR_NONZERO_PADDING);
    assert(serialize_bits_processed(r2) == 8);
    assert(serialize_bits_remaining(r2) == 120);

    // Every subsequent read over the remaining 120 valid bits MUST be refused.
    assert(!serialize_bool(r2, b1) && !b1);
    assert(!serialize_bits(r2, u32_1, 8) && u32_1 == 0x13572468);
    assert(!serialize_bits64(r2, u64_1, 16) && u64_1 == 0x1122334455667788);
    assert(!serialize_uint8(r2, u8_1) && u8_1 == 0x42);
    assert(!serialize_uint16(r2, u16_1) && u16_1 == 0x4242);
    assert(!serialize_uint32(r2, u32_1) && u32_1 == 0x13572468);
    assert(!serialize_uint64(r2, u64_1) && u64_1 == 0x1122334455667788);
    assert(!serialize_align(r2));
    assert(serialize_bits_processed(r2) == 8);
    assert(serialize_bits_remaining(r2) == 120);
    assert(serialize_error(r2) == SERIALIZE_ERROR_NONZERO_PADDING);
}

fn test_write_refusals_and_latch() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);

    // A value >= 2^bits is write misuse and aborts (U8, U9; TestU8*). A
    // write stream latched by the caller's fail writes nothing after it.
    assert(!serialize_fail(w, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE));
    assert(serialize_error(w) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    assert(!serialize_bits(w, 1, 3));
    assert(!serialize_bool(w, true));
    assert(!serialize_uint8(w, 1));
    assert(!serialize_align(w));
    assert(serialize_bits_processed(w) == 0);

    // Write overflow latches PAST_END and writes nothing for the overflowing call.
    var w_ovf = serialize_write_stream_init(buf);
    assert(serialize_uint64(w_ovf, 0xFFEEDDCCBBAA9988));
    assert(serialize_bits_available(w_ovf) == 0);
    assert(!serialize_bool(w_ovf, true));
    assert(serialize_error(w_ovf) == SERIALIZE_ERROR_PAST_END);
    assert(serialize_bits_processed(w_ovf) == 64);
}

// ---- Conformance vector parser for bits.txt, bool.txt, align.txt -----------

fn hex_nibble(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    abort("conformance: invalid hex digit");
}

fn parse_u64_decimal(s: const u8[:]) -> u64 {
    assert(s.len > 0);
    var v: u64 = 0;
    for i in s.len {
        let c = s[i];
        assert(c >= '0' && c <= '9');
        let digit: u64 = c - '0';
        v = v * 10 + digit;
    }
    return v;
}

fn parse_hex_bytes(s: const u8[:], out: u8[>..]&) {
    out.clear();
    var i = 0;
    while i < s.len {
        while i < s.len && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') {
            i += 1;
        }
        if i >= s.len { break; }
        assert(i + 1 < s.len);
        let b = (hex_nibble(s[i]) << 4) | hex_nibble(s[i + 1]);
        out.push(b);
        i += 2;
    }
}

fn slice_starts_with(s: const u8[:], prefix: const u8[:]) -> bool {
    if s.len < prefix.len { return false; }
    for i in prefix.len {
        if s[i] != prefix[i] { return false; }
    }
    return true;
}

fn slice_equals(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        if a[i] != b[i] { return false; }
    }
    return true;
}

fn trim_cr(s: const u8[:]) -> const u8[:] {
    if s.len > 0 && s[s.len - 1] == '\r' {
        return s[0..s.len - 1];
    }
    return s;
}

struct VectorRecord {
    has_op: bool,
    op_kind: i64,
    param_bits: i64,
    param_preceding_bits: i64,
    refused: bool,
    reason: i32,
    expect_u64: u64,
    expect_bool: bool,
    consumed: i64,
    canonical: bool,
    wire: u8[>..],
}

fn run_vector_record(rec: VectorRecord&) -> i64 {
    if !rec.has_op { return 0; }
    var padded: u8[64] = [0xFF; 64];
    var r = serialize_read_stream_init_padded(padded, rec.wire);

    if rec.op_kind == 1 {
        var got: u64 = 0xDEADBEEFCAFEBABE;
        var got32: u32 = 0xDEADBEEF;
        let ok = if rec.param_bits <= 32 {
            serialize_bits(r, got32, rec.param_bits)
        } else {
            serialize_bits64(r, got, rec.param_bits)
        };
        if rec.refused {
            assert(!ok);
            assert(serialize_error(r) == rec.reason);
            if rec.param_bits <= 32 {
                assert(got32 == 0xDEADBEEF);
            } else {
                assert(got == 0xDEADBEEFCAFEBABE);
            }
        } else {
            assert(ok);
            let got32_wide: u64 = got32;
            let val: u64 = if rec.param_bits <= 32 { got32_wide } else { got };
            assert(val == rec.expect_u64);
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical {
                var wbuf: u8[64] = [0xAA; 64];
                var w = serialize_write_stream_init(wbuf);
                if rec.param_bits <= 32 {
                    assert(serialize_bits(w, rec.expect_u64 as! u32, rec.param_bits));
                } else {
                    assert(serialize_bits64(w, rec.expect_u64, rec.param_bits));
                }
                serialize_flush(w);
                assert(serialize_bits_processed(w) == rec.consumed);
                assert(serialize_bytes_processed(w) == rec.wire.len);
                for i in rec.wire.len {
                    assert(wbuf[i] == rec.wire[i]);
                }
            }
        }
        return 1;
    }

    if rec.op_kind == 2 {
        var got = !rec.expect_bool;
        let ok = serialize_bool(r, got);
        if rec.refused {
            assert(!ok);
            assert(got == !rec.expect_bool);
            assert(serialize_error(r) == rec.reason);
        } else {
            assert(ok);
            assert(got == rec.expect_bool);
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical {
                var wbuf: u8[16] = [0xAA; 16];
                var w = serialize_write_stream_init(wbuf);
                assert(serialize_bool(w, rec.expect_bool));
                serialize_flush(w);
                assert(serialize_bits_processed(w) == rec.consumed);
                assert(serialize_bytes_processed(w) == rec.wire.len);
                for i in rec.wire.len {
                    assert(wbuf[i] == rec.wire[i]);
                }
            }
        }
        return 1;
    }

    if rec.op_kind == 3 {
        var pre: u32 = 0;
        if rec.param_preceding_bits > 0 {
            assert(serialize_bits(r, pre, rec.param_preceding_bits));
        }
        let ok = serialize_align(r);
        if rec.refused {
            assert(!ok);
            assert(serialize_error(r) == rec.reason);
        } else {
            assert(ok);
            assert(serialize_bits_processed(r) == rec.consumed);
            if rec.canonical {
                var wbuf: u8[16] = [0xAA; 16];
                var w = serialize_write_stream_init(wbuf);
                if rec.param_preceding_bits > 0 {
                    assert(serialize_bits(w, pre, rec.param_preceding_bits));
                }
                assert(serialize_align(w));
                serialize_flush(w);
                assert(serialize_bits_processed(w) == rec.consumed);
                assert(serialize_bytes_processed(w) == rec.wire.len);
                for i in rec.wire.len {
                    assert(wbuf[i] == rec.wire[i]);
                }
            }
        }
        return 1;
    }

    abort("conformance: unknown operation in bitpacker vector file");
}

// The reason a refused record states, from the closed list (STANDARD.md,
// Refusal reasons); a missing or unknown reason is a malformed vector.
fn vector_reason(name: const u8[:]) -> i32 {
    for k in 8 {
        let kind = (k + 1) as! i32;
        if slice_equals(name, serialize_refusal_name(kind)) { return kind; }
    }
    abort("conformance: refused record states no known reason");
}

fn run_conformance_file(filename: const u8[:]) -> i64 {
    var content: u8[>..] = [];
    assert(read_file(filename, content));
    var rec = VectorRecord {
        has_op: false,
        op_kind: 0,
        param_bits: 0,
        param_preceding_bits: 0,
        refused: false,
        reason: SERIALIZE_ERROR_NONE,
        expect_u64: 0,
        expect_bool: false,
        consumed: 0,
        canonical: false,
        wire: [],
    };
    var count = 0;
    var start = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = trim_cr(content[start..i]);
            start = i + 1;
            if line.len == 0 {
                count += run_vector_record(rec);
                rec.has_op = false;
                rec.op_kind = 0;
                rec.param_bits = 0;
                rec.param_preceding_bits = 0;
                rec.wire.clear();
                rec.refused = false;
                rec.reason = SERIALIZE_ERROR_NONE;
                rec.expect_u64 = 0;
                rec.expect_bool = false;
                rec.consumed = 0;
                rec.canonical = false;
            } else if line[0] != '#' {
                if slice_starts_with(line, "operation ") {
                    rec.has_op = true;
                    let op_s = line[10..];
                    if slice_equals(op_s, "bits") {
                        rec.op_kind = 1;
                    } else if slice_equals(op_s, "bool") {
                        rec.op_kind = 2;
                    } else if slice_equals(op_s, "align") {
                        rec.op_kind = 3;
                    } else {
                        rec.op_kind = 0;
                    }
                } else if slice_starts_with(line, "param bits = ") {
                    rec.param_bits = parse_u64_decimal(line[13..]) as! i64;
                } else if slice_starts_with(line, "param preceding_bits = ") {
                    rec.param_preceding_bits = parse_u64_decimal(line[23..]) as! i64;
                } else if slice_equals(line, "bytes") {
                    rec.wire.clear();
                } else if slice_starts_with(line, "bytes ") {
                    parse_hex_bytes(line[6..], rec.wire);
                } else if slice_starts_with(line, "expect refused ") {
                    rec.refused = true;
                    rec.reason = vector_reason(line[15..]);
                } else if slice_starts_with(line, "expect value = ") {
                    let val_str = line[15..];
                    if slice_equals(val_str, "true") {
                        rec.expect_bool = true;
                    } else if slice_equals(val_str, "false") {
                        rec.expect_bool = false;
                    } else {
                        rec.expect_u64 = parse_u64_decimal(val_str);
                    }
                } else if slice_starts_with(line, "consumed ") {
                    rec.consumed = parse_u64_decimal(line[9..]) as! i64;
                } else if slice_equals(line, "writer canonical") {
                    rec.canonical = true;
                }
            }
        }
    }
    return count;
}

// goose: --debug
fn TestBitpacker() {
    test_golden_sequence();
    test_oracle_and_round_trip();
    test_fixed_width_and_align();
    test_packer_bytes();
    test_read_latch_over_valid_data();
    test_write_refusals_and_latch();

    let n_bits = run_conformance_file("bits.txt");
    let n_bool = run_conformance_file("bool.txt");
    let n_align = run_conformance_file("align.txt");
    assert(n_bits == 26);
    assert(n_bool == 5);
    assert(n_align == 10);
}

// want-abort: serialize: bits must be in [1,32]
fn TestBitpackerBitsZeroAborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_bits(w, 0, 0);
}

// want-abort: serialize: bits must be in [1,32]
fn TestBitpackerBits33Aborts() {
    var buf: u8[8] = [0; 8];
    var w = serialize_write_stream_init(buf);
    serialize_bits(w, 0, 33);
}

// want-abort: serialize: bits must be in [1,64]
fn TestBitpackerBits64ZeroAborts() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    serialize_bits64(w, 0, 0);
}

// want-abort: serialize: bits must be in [1,64]
fn TestBitpackerBits64TooWideAborts() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    serialize_bits64(w, 0, 65);
}

// want-abort: serialize: write buffer bytes must be a multiple of 8
fn TestBitpackerWriteBufferMisalignedAborts() {
    var buf: u8[12] = [0; 12];
    serialize_write_stream_init(buf);
}

// Read data without its 8 bytes of slack is caller misuse on a read: the
// stream starts refused as value_out_of_range, never an abort (U7).
fn TestBitpackerReadSlackMissingRefuses() {
    var buf: u8[8] = [0; 8];
    var r = serialize_read_stream_init(buf, 1);
    assert(serialize_error(r) == SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
}
