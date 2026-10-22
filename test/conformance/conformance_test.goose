// test/conformance -- TestConformanceCorpus (STANDARD.md, The vector format,
// What a runner checks, A gate nobody has seen go red; DESIGN.md (g) THE
// RUNNER). Every conformance/*.txt file is discovered, every record in it is
// run through the reader, and a writer=canonical record is re-emitted byte for
// byte. A record whose operation has no runner is a failure, never a skip.

import os;
import std;
import .serialize;

let CONF_MAX_STEPS = 64;
let CONF_MAX_BYTES = 256;
let CONF_MAX_UNITS = 128;

// Step kinds (STANDARD.md, The vector format; sequence.txt's one spelling per
// operation).
let K_BITS = 1;
let K_BOOL = 2;
let K_UINT128 = 3;
let K_ALIGN = 4;
let K_INT = 5;
let K_INT64 = 6;
let K_INT128 = 7;
let K_INT_RELATIVE = 8;
let K_FLOAT = 9;
let K_DOUBLE = 10;
let K_COMPRESSED_FLOAT = 11;
let K_BYTES = 12;
let K_STRING = 13;
let K_WSTRING = 14;
let K_FIXED = 15;
let K_OBJECT = 16;
let K_SEQUENCE = 17;

// The operations the corpus can name; any other is rejected, not skipped
// (STANDARD.md, A gate nobody has seen go red).
fn conf_operation(text: const u8[:]) -> i64 {
    if conf_equals(text, "bits") { return K_BITS; }
    if conf_equals(text, "bool") { return K_BOOL; }
    if conf_equals(text, "uint128") { return K_UINT128; }
    if conf_equals(text, "align") { return K_ALIGN; }
    if conf_equals(text, "int") { return K_INT; }
    if conf_equals(text, "int64") { return K_INT64; }
    if conf_equals(text, "int128") { return K_INT128; }
    if conf_equals(text, "int_relative") { return K_INT_RELATIVE; }
    if conf_equals(text, "float") { return K_FLOAT; }
    if conf_equals(text, "double") { return K_DOUBLE; }
    if conf_equals(text, "compressed_float") { return K_COMPRESSED_FLOAT; }
    if conf_equals(text, "bytes") { return K_BYTES; }
    if conf_equals(text, "string") { return K_STRING; }
    if conf_equals(text, "wstring") { return K_WSTRING; }
    if conf_equals(text, "fixed") { return K_FIXED; }
    if conf_equals(text, "sequence") { return K_SEQUENCE; }
    return 0;
}

fn conf_is_pattern(kind: i64) -> bool {
    return kind == K_BITS || kind == K_UINT128 || kind == K_FLOAT
        || kind == K_DOUBLE || kind == K_COMPRESSED_FLOAT;
}
fn conf_is_number(kind: i64) -> bool {
    return kind == K_INT || kind == K_INT64 || kind == K_INT128
        || kind == K_INT_RELATIVE || kind == K_FIXED;
}

// ---- text and number helpers ----------------------------------------------

fn conf_starts(s: const u8[:], p: const u8[:]) -> bool {
    if s.len < p.len { return false; }
    for i in p.len { if s[i] != p[i] { return false; } }
    return true;
}
fn conf_equals(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len { if a[i] != b[i] { return false; } }
    return true;
}
fn conf_trim_cr(s: const u8[:]) -> const u8[:] {
    if s.len > 0 && s[s.len - 1] == '\r' { return s[0..s.len - 1]; }
    return s;
}
fn conf_hex_digit(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    abort("conformance: invalid hex digit");
}
fn conf_parse_hex_u64(s: const u8[:]) -> u64 {
    var v: u64 = 0;
    var i: i64 = 0;
    if s.len > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') { i = 2; }
    while i < s.len {
        v = (v << 4) | (conf_hex_digit(s[i]) as u64);
        i += 1;
    }
    return v;
}
fn conf_parse_hex_bytes(s: const u8[:], out: u8[1024]&) -> i64 {
    var n: i64 = 0;
    var i: i64 = 0;
    while i < s.len {
        while i < s.len && (s[i] == ' ' || s[i] == '\t') { i += 1; }
        if i >= s.len { break; }
        assert(i + 1 < s.len);
        assert(n < 1024);
        out[n] = (conf_hex_digit(s[i]) << 4) | conf_hex_digit(s[i + 1]);
        n += 1;
        i += 2;
    }
    return n;
}
fn conf_u128_add(a: Int128, b: Int128) -> Int128 {
    let lo = a.lo + b.lo;
    let carry: u64 = if lo < a.lo { 1 } else { 0 };
    return Int128 { lo: lo, hi: a.hi + b.hi + carry };
}
fn conf_u128_shl1(a: Int128) -> Int128 {
    return Int128 { lo: a.lo << 1, hi: (a.hi << 1) | (a.lo >> 63) };
}
fn conf_u128_neg(a: Int128) -> Int128 {
    return conf_u128_add(Int128 { lo: (a.lo ^ 0xffffffffffffffff),
                                  hi: (a.hi ^ 0xffffffffffffffff) },
                         Int128 { lo: 1, hi: 0 });
}
fn conf_u128_mul10_add(a: Int128, d: u64) -> Int128 {
    var v = Int128 { lo: 0, hi: 0 };
    for i in 10 { v = conf_u128_add(v, a); }
    return conf_u128_add(v, Int128 { lo: d, hi: 0 });
}
// Signed decimal or 0x hexadecimal up to 128 bits; the two's complement form
// is the lane form every comparison uses (STANDARD.md, lexical rules).
fn conf_parse_number(s: const u8[:]) -> Int128 {
    assert(s.len > 0);
    var i: i64 = 0;
    var negative = false;
    if s[0] == '-' { negative = true; i = 1; }
    else if s[0] == '+' { i = 1; }
    assert(i < s.len);
    var v = Int128 { lo: 0, hi: 0 };
    if i + 1 < s.len && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X') {
        i += 2;
        while i < s.len {
            v = Int128 { lo: v.lo << 4, hi: (v.hi << 4) | (v.lo >> 60) };
            v = conf_u128_add(v, Int128 { lo: conf_hex_digit(s[i]) as u64, hi: 0 });
            i += 1;
        }
    } else {
        while i < s.len {
            assert(s[i] >= '0' && s[i] <= '9');
            v = conf_u128_mul10_add(v, (s[i] - '0') as u64);
            i += 1;
        }
    }
    if negative { v = conf_u128_neg(v); }
    return v;
}
fn conf_parse_dec(s: const u8[:]) -> i64 {
    let v, ok = parse_int(s);
    assert(ok);
    return v;
}
fn conf_parse_f32(s: const u8[:]) -> f32 {
    let v, ok = parse_flt(s);
    assert(ok);
    return v as! f32;
}
fn conf_wire_bits(wire: const u8[:], n: i64) -> u64 {
    var v: u64 = 0;
    for i in n {
        let bit = (wire[i >> 3] >> ((i & 7) as u8)) & 1;
        v = v | ((bit as u64) << (i as u64));
    }
    return v;
}

// ---- the step --------------------------------------------------------------

struct Step {
    kind: i64,
    width: i64,
    min: Int128,
    max: Int128,
    fmin: f32,
    fmax: f32,
    fres: f32,
    integer_bits: i64,
    fraction_bits: i64,
    storage: i64,
    previous: i32,
    want: Int128,
    got: Int128,
    want_bool: bool,
    got_bool: bool,
    input: u8[1024],
    input_len: i64,
    got_buf: u8[1024],
    got_len: i64,
    want_units: u32[128],
    want_unit_count: i64,
}

fn conf_empty_step() -> Step {
    return Step {
        kind: 0, width: 0, min: Int128 { lo: 0, hi: 0 }, max: Int128 { lo: 0, hi: 0 },
        fmin: 0.0, fmax: 0.0, fres: 0.0, integer_bits: 0, fraction_bits: 0, storage: 0,
        previous: 0, want: Int128 { lo: 0, hi: 0 }, got: Int128 { lo: 0, hi: 0 },
        want_bool: false, got_bool: false, input: [0; 1024], input_len: 0,
        got_buf: [0; 1024], got_len: 0, want_units: [0; 128], want_unit_count: 0,
    };
}

fn conf_step_clear(st: Step&) {
    let e = conf_empty_step();
    st.kind = e.kind;
    st.width = 0;
    st.min = e.min;
    st.max = e.max;
    st.fmin = 0.0;
    st.fmax = 0.0;
    st.fres = 0.0;
    st.integer_bits = 0;
    st.fraction_bits = 0;
    st.storage = 0;
    st.previous = 0;
    st.want = e.want;
    st.got = e.got;
    st.want_bool = false;
    st.got_bool = false;
    st.input_len = 0;
    st.got_len = 0;
    st.want_unit_count = 0;
}

fn conf_split_words(text: const u8[:], words: u8[1024]&, ends: i64[8]&) -> i64 {
    var n: i64 = 0;
    var i: i64 = 0;
    var w: i64 = 0;
    while i < text.len && n < 8 {
        while i < text.len && (text[i] == ' ' || text[i] == '\t') { i += 1; }
        if i >= text.len { break; }
        let begin = w;
        while i < text.len && text[i] != ' ' && text[i] != '\t' && w < 1023 {
            words[w] = text[i];
            w += 1;
            i += 1;
        }
        words[w] = 0;
        ends[n] = w;
        n += 1;
        w += 1;
        while i < text.len && text[i] != ' ' && text[i] != '\t' { i += 1; }
    }
    return n;
}

fn conf_word(words: u8[1024]&, ends: i64[8]&, i: i64) -> const u8[:] {
    let b = if i == 0 { 0 } else { ends[i - 1] + 1 };
    return words[b..ends[i]];
}

fn conf_fixed_decl(st: Step&, ib: i64, fb: i64, lo: Int128, hi: Int128) -> bool {
    let total = ib + fb;
    if ib < 1 || fb < 0 || total > 128 { return false; }
    st.integer_bits = ib;
    st.fraction_bits = fb;
    st.min = lo;
    st.max = hi;
    st.storage = if total <= 32 { 32 } else if total <= 64 { 64 } else { 128 };
    return true;
}

// One step spelling from sequence.txt. Every spelling the document defines is
// accepted; anything else is a runner gap and fails (STANDARD.md, The vector
// format: one spelling per operation).
fn conf_step_from_words(st: Step&, text: const u8[:]) -> bool {
    conf_step_clear(st);
    var words: u8[1024] = [0; 1024];
    var ends: i64[8] = [0; 8];
    let n = conf_split_words(text, words, ends);
    if n == 0 { return false; }
    let w0 = conf_word(words, ends, 0);
    if conf_equals(w0, "bits") && n == 2 {
        st.kind = K_BITS; st.width = conf_parse_dec(conf_word(words, ends, 1)); return true;
    }
    if conf_equals(w0, "bool") && n == 1 { st.kind = K_BOOL; return true; }
    if conf_equals(w0, "align") && n == 1 { st.kind = K_ALIGN; return true; }
    if conf_equals(w0, "float") && n == 1 { st.kind = K_FLOAT; return true; }
    if conf_equals(w0, "double") && n == 1 { st.kind = K_DOUBLE; return true; }
    if conf_equals(w0, "uint128") && n == 1 { st.kind = K_UINT128; return true; }
    if conf_equals(w0, "int_relative") && n == 2 {
        st.kind = K_INT_RELATIVE; st.previous = conf_parse_dec(conf_word(words, ends, 1)) as! i32; return true;
    }
    if conf_equals(w0, "object") && n == 2 {
        st.kind = K_OBJECT; st.width = conf_parse_dec(conf_word(words, ends, 1)); return st.width >= 0;
    }
    if conf_equals(w0, "compressed_float") && n == 4 {
        st.kind = K_COMPRESSED_FLOAT;
        st.fmin = conf_parse_f32(conf_word(words, ends, 1));
        st.fmax = conf_parse_f32(conf_word(words, ends, 2));
        st.fres = conf_parse_f32(conf_word(words, ends, 3));
        return true;
    }
    if conf_equals(w0, "bytes") && n == 2 {
        st.kind = K_BYTES; st.width = conf_parse_dec(conf_word(words, ends, 1));
        return st.width >= 0 && st.width <= CONF_MAX_BYTES;
    }
    if conf_equals(w0, "string") && n == 2 {
        st.kind = K_STRING; st.width = conf_parse_dec(conf_word(words, ends, 1));
        return st.width > 0 && st.width <= CONF_MAX_BYTES;
    }
    if conf_equals(w0, "wstring") && n == 2 {
        st.kind = K_WSTRING; st.width = conf_parse_dec(conf_word(words, ends, 1));
        return st.width > 0 && st.width <= CONF_MAX_BYTES;
    }
    if (conf_equals(w0, "int") || conf_equals(w0, "int64") || conf_equals(w0, "int128")) && n == 3 {
        st.kind = if conf_equals(w0, "int") { K_INT }
                  else if conf_equals(w0, "int64") { K_INT64 } else { K_INT128 };
        st.min = conf_parse_number(conf_word(words, ends, 1));
        st.max = conf_parse_number(conf_word(words, ends, 2));
        return true;
    }
    if conf_equals(w0, "fixed") && n == 5 {
        st.kind = K_FIXED;
        return conf_fixed_decl(st,
            conf_parse_dec(conf_word(words, ends, 1)), conf_parse_dec(conf_word(words, ends, 2)),
            conf_parse_number(conf_word(words, ends, 3)), conf_parse_number(conf_word(words, ends, 4)));
    }
    return false;
}

// ---- the reader -----------------------------------------------------------

// The sabotage switch: an argument the runner passes, never a source edit
// (STANDARD.md, A gate nobody has seen go red). Each mode deletes exactly one
// refusal rule from the reader the runner drives.
let SAB_NONE = 0;
let SAB_ALIGN = 1;      // align consumes its padding without checking it is zero
let SAB_INT_RANGE = 2;  // int accepts an offset past max - min (STANDARD.md, int)

fn conf_read_align(s: ReadStream&, sabotage: i64) -> bool {
    if sabotage != SAB_ALIGN { return serialize_align(s); }
    guard serialize_error(s) == SERIALIZE_ERROR_NONE else { return false; }
    let n = serialize_align_bits(s);
    if n == 0 { return true; }
    var ignored: u32 = 0;
    return serialize_bits(s, ignored, n);
}

fn conf_append_utf8(out: u8[1024]&, len: i64&, cp: u32) {
    if cp < 0x80 {
        out[len] = cp as! u8; len += 1;
    } else if cp < 0x800 {
        out[len] = (0xC0 | (cp >> 6)) as! u8;
        out[len + 1] = (0x80 | (cp & 0x3F)) as! u8;
        len += 2;
    } else if cp < 0x10000 {
        out[len] = (0xE0 | (cp >> 12)) as! u8;
        out[len + 1] = (0x80 | ((cp >> 6) & 0x3F)) as! u8;
        out[len + 2] = (0x80 | (cp & 0x3F)) as! u8;
        len += 3;
    } else {
        out[len] = (0xF0 | (cp >> 18)) as! u8;
        out[len + 1] = (0x80 | ((cp >> 12) & 0x3F)) as! u8;
        out[len + 2] = (0x80 | ((cp >> 6) & 0x3F)) as! u8;
        out[len + 3] = (0x80 | (cp & 0x3F)) as! u8;
        len += 4;
    }
}

// The corpus states a wstring as transmitted UTF-16 code units; this turns
// them back into the UTF-8 the Goose reader returns (STANDARD.md, wstring).
fn conf_units_to_utf8(st: Step&, out: u8[1024]&) -> i64 {
    var len: i64 = 0;
    var i: i64 = 0;
    while i < st.want_unit_count {
        let c = st.want_units[i];
        if c >= 0xD800 && c <= 0xDBFF {
            assert(i + 1 < st.want_unit_count);
            let lo = st.want_units[i + 1];
            conf_append_utf8(out, len, 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00));
            i += 2;
        } else {
            conf_append_utf8(out, len, c);
            i += 1;
        }
    }
    return len;
}

// SAB_INT_RANGE's reader: serialize_int with the range refusal deleted and
// nothing else changed (the width rule and the past-end refusal still hold).
fn conf_read_int_unchecked(s: ReadStream&, value: i32&, min: i32, max: i32) -> bool {
    let bits = serialize_bits_required(min as! u32, max as! u32);
    if bits == 0 { value = min; return serialize_error(s) == SERIALIZE_ERROR_NONE; }
    var offset: u32 = 0;
    guard serialize_bits(s, offset, bits) else { return false; }
    value = ((min as! u32) + offset) as! i32;
    return true;
}

fn conf_read_step(s: ReadStream&, st: Step&, check: bool, sabotage: i64) -> bool {
    if st.kind == K_BITS {
        if st.width <= 32 {
            var v: u32 = 0xDEADBEEF;
            guard serialize_bits(s, v, st.width) else { return false; }
            st.got = Int128 { lo: v as u64, hi: 0 };
        } else {
            var v: u64 = 0xDEADBEEFCAFEBABE;
            guard serialize_bits64(s, v, st.width) else { return false; }
            st.got = Int128 { lo: v, hi: 0 };
        }
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_BOOL {
        var v = true;
        guard serialize_bool(s, v) else { return false; }
        st.got_bool = v;
        return !check || v == st.want_bool;
    }
    if st.kind == K_UINT128 {
        var v = Uint128 { lo: 0xDEADBEEFCAFEBABE, hi: 0x0123456789ABCDEF };
        guard serialize_uint128(s, v) else { return false; }
        st.got = Int128 { lo: v.lo, hi: v.hi };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_ALIGN { return conf_read_align(s, sabotage); }
    if st.kind == K_INT {
        var v: i32 = 0x1234567;
        if sabotage == SAB_INT_RANGE {
            guard conf_read_int_unchecked(s, v, st.min.lo as! i32, st.max.lo as! i32) else { return false; }
        } else {
            guard serialize_int(s, v, st.min.lo as! i32, st.max.lo as! i32) else { return false; }
        }
        st.got = Int128 { lo: v as! u64, hi: if v < 0 { 0xffffffffffffffff } else { 0 } };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_INT64 {
        var v: i64 = 0x0123456789ABCDEF;
        guard serialize_int64(s, v, st.min.lo as! i64, st.max.lo as! i64) else { return false; }
        st.got = Int128 { lo: v as! u64, hi: if v < 0 { 0xffffffffffffffff } else { 0 } };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_INT128 {
        var v = Int128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 };
        guard serialize_int128(s, v, st.min, st.max) else { return false; }
        st.got = v;
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_INT_RELATIVE {
        var v: i32 = 0x1234567;
        guard serialize_int_relative(s, st.previous, v) else { return false; }
        st.got = Int128 { lo: v as! u64, hi: if v < 0 { 0xffffffffffffffff } else { 0 } };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_FLOAT {
        var v: f32 = 0.0;
        guard serialize_float(s, v) else { return false; }
        st.got = Int128 { lo: serialize_f32_bits(v) as u64, hi: 0 };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_DOUBLE {
        var v: f64 = 0.0;
        guard serialize_double(s, v) else { return false; }
        st.got = Int128 { lo: serialize_f64_bits(v), hi: 0 };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_COMPRESSED_FLOAT {
        var v: f32 = 0.0;
        guard serialize_compressed_float(s, v, st.fmin, st.fmax, st.fres) else { return false; }
        st.got = Int128 { lo: serialize_f32_bits(v) as u64, hi: 0 };
        return !check || conf_same(st.want, st.got);
    }
    if st.kind == K_BYTES {
        var buf: u8[256] = [0; 256];
        guard serialize_bytes(s, buf[0..st.width]) else { return false; }
        for i in st.width { st.got_buf[i] = buf[i]; }
        st.got_len = st.width;
        return !check || conf_same_bytes(st, st.input, st.input_len);
    }
    if st.kind == K_STRING {
        var out: u8[>..] = [];
        guard serialize_string(s, out, st.width) else { return false; }
        st.got_len = out.len;
        for i in out.len { st.got_buf[i] = out[i]; }
        return !check || conf_same_bytes(st, st.input, st.input_len);
    }
    if st.kind == K_WSTRING {
        var out: u8[>..] = [];
        guard serialize_wstring(s, out, st.width) else { return false; }
        st.got_len = out.len;
        for i in out.len { st.got_buf[i] = out[i]; }
        if !check { return true; }
        var want: u8[1024] = [0; 1024];
        let want_len = conf_units_to_utf8(st, want);
        return conf_same_bytes(st, want, want_len);
    }
    if st.kind == K_FIXED {
        if st.storage == 32 {
            var v: i32 = 0x1234567;
            guard serialize_fixed32(s, v, st.integer_bits, st.fraction_bits,
                                    st.min.lo as! i32, st.max.lo as! i32) else { return false; }
            st.got = Int128 { lo: v as! u64, hi: if v < 0 { 0xffffffffffffffff } else { 0 } };
        } else if st.storage == 64 {
            var v: i64 = 0x0123456789ABCDEF;
            guard serialize_fixed64(s, v, st.integer_bits, st.fraction_bits,
                                    st.min.lo as! i64, st.max.lo as! i64) else { return false; }
            st.got = Int128 { lo: v as! u64, hi: if v < 0 { 0xffffffffffffffff } else { 0 } };
        } else {
            var v = Int128 { lo: 0x0123456789ABCDEF, hi: 0xFEDCBA9876543210 };
            guard serialize_fixed128(s, v, st.integer_bits, st.fraction_bits,
                                     st.min.lo as! i64, st.max.lo as! i64) else { return false; }
            st.got = v;
        }
        return !check || conf_same(st.want, st.got);
    }
    abort("conformance: unknown operation in vector file");
}

fn conf_same(a: Int128, b: Int128) -> bool { return a.lo == b.lo && a.hi == b.hi; }

fn conf_same_bytes(st: Step&, want: u8[1024], want_len: i64) -> bool {
    if st.got_len != want_len { return false; }
    for i in want_len { if st.got_buf[i] != want[i] { return false; } }
    return true;
}

// ---- the writer -----------------------------------------------------------

fn conf_write_step(s: WriteStream&, st: Step&) -> bool {
    if st.kind == K_BITS {
        return if st.width <= 32 {
            serialize_bits(s, st.got.lo as! u32, st.width)
        } else {
            serialize_bits64(s, st.got.lo, st.width)
        };
    }
    if st.kind == K_BOOL { return serialize_bool(s, st.got_bool); }
    if st.kind == K_UINT128 { return serialize_uint128(s, Uint128 { lo: st.got.lo, hi: st.got.hi }); }
    if st.kind == K_ALIGN { return serialize_align(s); }
    if st.kind == K_INT {
        return serialize_int(s, st.got.lo as! i32, st.min.lo as! i32, st.max.lo as! i32);
    }
    if st.kind == K_INT64 {
        return serialize_int64(s, st.got.lo as! i64, st.min.lo as! i64, st.max.lo as! i64);
    }
    if st.kind == K_INT128 { return serialize_int128(s, st.got, st.min, st.max); }
    if st.kind == K_INT_RELATIVE {
        return serialize_int_relative(s, st.previous, st.got.lo as! i32);
    }
    if st.kind == K_FLOAT { return serialize_float(s, serialize_f32_from_bits(st.got.lo as! u32)); }
    if st.kind == K_DOUBLE { return serialize_double(s, serialize_f64_from_bits(st.got.lo)); }
    if st.kind == K_COMPRESSED_FLOAT {
        return serialize_compressed_float(s, serialize_f32_from_bits(st.got.lo as! u32),
                                          st.fmin, st.fmax, st.fres);
    }
    if st.kind == K_BYTES { return serialize_bytes(s, st.got_buf[0..st.got_len]); }
    if st.kind == K_STRING { return serialize_string(s, st.got_buf[0..st.got_len], st.width); }
    if st.kind == K_WSTRING { return serialize_wstring(s, st.got_buf[0..st.got_len], st.width); }
    if st.kind == K_FIXED {
        if st.storage == 32 {
            return serialize_fixed32(s, st.got.lo as! i32, st.integer_bits, st.fraction_bits,
                                     st.min.lo as! i32, st.max.lo as! i32);
        } else if st.storage == 64 {
            return serialize_fixed64(s, st.got.lo as! i64, st.integer_bits, st.fraction_bits,
                                     st.min.lo as! i64, st.max.lo as! i64);
        }
        return serialize_fixed128(s, st.got, st.integer_bits, st.fraction_bits,
                                  st.min.lo as! i64, st.max.lo as! i64);
    }
    abort("conformance: unknown operation in vector file");
}

// ---- the measure ----------------------------------------------------------

fn conf_measure_step(s: MeasureStream&, st: Step&) -> bool {
    if st.kind == K_BITS {
        return if st.width <= 32 {
            serialize_bits(s, st.got.lo as! u32, st.width)
        } else {
            serialize_bits64(s, st.got.lo, st.width)
        };
    }
    if st.kind == K_BOOL { return serialize_bool(s, st.got_bool); }
    if st.kind == K_UINT128 { return serialize_uint128(s, Uint128 { lo: st.got.lo, hi: st.got.hi }); }
    if st.kind == K_ALIGN { return serialize_align(s); }
    if st.kind == K_INT {
        return serialize_int(s, st.got.lo as! i32, st.min.lo as! i32, st.max.lo as! i32);
    }
    if st.kind == K_INT64 {
        return serialize_int64(s, st.got.lo as! i64, st.min.lo as! i64, st.max.lo as! i64);
    }
    if st.kind == K_INT128 { return serialize_int128(s, st.got, st.min, st.max); }
    if st.kind == K_INT_RELATIVE {
        return serialize_int_relative(s, st.previous, st.got.lo as! i32);
    }
    if st.kind == K_FLOAT { return serialize_float(s, serialize_f32_from_bits(st.got.lo as! u32)); }
    if st.kind == K_DOUBLE { return serialize_double(s, serialize_f64_from_bits(st.got.lo)); }
    if st.kind == K_COMPRESSED_FLOAT {
        return serialize_compressed_float(s, serialize_f32_from_bits(st.got.lo as! u32),
                                          st.fmin, st.fmax, st.fres);
    }
    if st.kind == K_BYTES { return serialize_bytes(s, st.got_buf[0..st.got_len]); }
    if st.kind == K_STRING { return serialize_string(s, st.got_buf[0..st.got_len], st.width); }
    if st.kind == K_WSTRING { return serialize_wstring(s, st.got_buf[0..st.got_len], st.width); }
    if st.kind == K_FIXED {
        if st.storage == 32 {
            return serialize_fixed32(s, st.got.lo as! i32, st.integer_bits, st.fraction_bits,
                                     st.min.lo as! i32, st.max.lo as! i32);
        } else if st.storage == 64 {
            return serialize_fixed64(s, st.got.lo as! i64, st.integer_bits, st.fraction_bits,
                                     st.min.lo as! i64, st.max.lo as! i64);
        }
        return serialize_fixed128(s, st.got, st.integer_bits, st.fraction_bits,
                                  st.min.lo as! i64, st.max.lo as! i64);
    }
    abort("conformance: unknown operation in vector file");
}

// The overload set the generic walk below resolves on the stream type.
fn conf_run_step(s: ReadStream&, st: Step&, check: bool, sabotage: i64) -> bool {
    return conf_read_step(s, st, check, sabotage);
}
fn conf_run_step(s: WriteStream&, st: Step&, check: bool, sabotage: i64) -> bool {
    return conf_write_step(s, st);
}
fn conf_run_step(s: MeasureStream&, st: Step&, check: bool, sabotage: i64) -> bool {
    return conf_measure_step(s, st);
}

// Object is composition and adds no bytes of its own: the nested steps run
// inline at exactly this position (STANDARD.md, object). Failure is terminal,
// and every later step of a refused sequence must refuse too (STANDARD.md,
// Reader Obligations).
recursive fn conf_run_steps<S>(s: S&, steps: Step[64]&, start: i64, end: i64,
                               check: bool, sabotage: i64, failed: i64&) -> bool {
    var i = start;
    while i < end {
        if steps[i].kind == K_OBJECT {
            guard conf_run_steps(s, steps, i + 1, i + 1 + steps[i].width, check, sabotage, failed) else {
                return false;
            }
            i += 1 + steps[i].width;
        } else {
            guard conf_run_step(s, steps[i], check, sabotage) else {
                failed = i;
                return false;
            }
            i += 1;
        }
    }
    return true;
}

// ---- a vector record -------------------------------------------------------

struct Rec {
    op: i64,
    has_op: bool,
    preceding: i64,
    width: i64,
    count: i64,
    buffer_size: i64,
    integer_bits: i64,
    fraction_bits: i64,
    previous: i32,
    min: Int128,
    max: Int128,
    fmin: f32,
    fmax: f32,
    fres: f32,
    refused: bool,
    canonical: bool,
    consumed: i64,
    measure_at_least: i64,
    has_expect: bool,
    expect_text: u8[1024],
    expect_len: i64,
    bad: bool,
    wire: u8[1024],
    wire_len: i64,
    steps: Step[64],
    step_count: i64,
}

fn conf_rec_reset(rec: Rec&) {
    rec.op = 0;
    rec.has_op = false;
    rec.preceding = 0;
    rec.width = 0;
    rec.count = 0;
    rec.buffer_size = 0;
    rec.integer_bits = 0;
    rec.fraction_bits = 0;
    rec.previous = 0;
    rec.min = Int128 { lo: 0, hi: 0 };
    rec.max = Int128 { lo: 0, hi: 0 };
    rec.fmin = 0.0;
    rec.fmax = 0.0;
    rec.fres = 0.0;
    rec.refused = false;
    rec.canonical = false;
    rec.consumed = 0;
    rec.measure_at_least = 0;
    rec.has_expect = false;
    rec.expect_len = 0;
    rec.bad = false;
    rec.wire_len = 0;
    rec.step_count = 0;
}

fn conf_param_takes(op: i64, name: const u8[:]) -> bool {
    if conf_equals(name, "step") { return op == K_SEQUENCE; }
    if conf_equals(name, "preceding_bits") { return op == K_ALIGN || op == K_BYTES; }
    if conf_equals(name, "bits") { return op == K_BITS; }
    if conf_equals(name, "count") { return op == K_BYTES; }
    if conf_equals(name, "buffer_size") { return op == K_STRING || op == K_WSTRING; }
    if conf_equals(name, "previous") { return op == K_INT_RELATIVE; }
    if conf_equals(name, "res") { return op == K_COMPRESSED_FLOAT; }
    if conf_equals(name, "integer_bits") || conf_equals(name, "fraction_bits") { return op == K_FIXED; }
    if conf_equals(name, "min") || conf_equals(name, "max") {
        return op == K_INT || op == K_INT64 || op == K_INT128 || op == K_FIXED
            || op == K_COMPRESSED_FLOAT;
    }
    return false;
}

fn conf_parse_param(rec: Rec&, text: const u8[:]) {
    var eq: i64 = -1;
    for i in text.len { if text[i] == '=' { eq = i; break; } }
    if eq < 0 { rec.bad = true; return; }
    var a = 0;
    var b = eq;
    while a < b && (text[a] == ' ' || text[a] == '\t') { a += 1; }
    while b > a && (text[b - 1] == ' ' || text[b - 1] == '\t') { b -= 1; }
    let name = text[a..b];
    var c = eq + 1;
    while c < text.len && (text[c] == ' ' || text[c] == '\t') { c += 1; }
    let value = text[c..];
    if !conf_param_takes(rec.op, name) { rec.bad = true; return; }
    if conf_equals(name, "step") {
        assert(rec.step_count < 64);
        if !conf_step_from_words(rec.steps[rec.step_count], value) { rec.bad = true; return; }
        rec.step_count += 1;
    } else if conf_equals(name, "preceding_bits") {
        rec.preceding = conf_parse_dec(value);
    } else if conf_equals(name, "bits") {
        rec.width = conf_parse_dec(value);
    } else if conf_equals(name, "count") {
        rec.count = conf_parse_dec(value);
    } else if conf_equals(name, "buffer_size") {
        rec.buffer_size = conf_parse_dec(value);
    } else if conf_equals(name, "previous") {
        rec.previous = conf_parse_dec(value) as! i32;
    } else if conf_equals(name, "res") {
        rec.fres = conf_parse_f32(value);
    } else if conf_equals(name, "integer_bits") {
        rec.integer_bits = conf_parse_dec(value);
    } else if conf_equals(name, "fraction_bits") {
        rec.fraction_bits = conf_parse_dec(value);
    } else if conf_equals(name, "min") {
        if rec.op == K_COMPRESSED_FLOAT { rec.fmin = conf_parse_f32(value); }
        else { rec.min = conf_parse_number(value); }
    } else if conf_equals(name, "max") {
        if rec.op == K_COMPRESSED_FLOAT { rec.fmax = conf_parse_f32(value); }
        else { rec.max = conf_parse_number(value); }
    }
}

// Builds the step list for a single-operation record: one or two steps, so the
// operation files and the sequence files share one execution path (the shape
// serialize.c's conformance runner uses).
fn conf_build_steps(rec: Rec&) -> bool {
    if rec.op == K_SEQUENCE {
        return rec.step_count > 0;
    }
    var n: i64 = 0;
    if rec.preceding > 0 {
        conf_step_clear(rec.steps[n]);
        rec.steps[n].kind = K_BITS;
        rec.steps[n].width = rec.preceding;
        rec.steps[n].got = Int128 { lo: conf_wire_bits(rec.wire[0..rec.wire_len], rec.preceding), hi: 0 };
        rec.steps[n].want = rec.steps[n].got;
        n += 1;
    }
    conf_step_clear(rec.steps[n]);
    if rec.op == K_BITS {
        if rec.width < 1 || rec.width > 64 { return false; }
        rec.steps[n].kind = K_BITS; rec.steps[n].width = rec.width;
    } else if rec.op == K_BOOL { rec.steps[n].kind = K_BOOL; }
    else if rec.op == K_UINT128 { rec.steps[n].kind = K_UINT128; }
    else if rec.op == K_ALIGN { rec.steps[n].kind = K_ALIGN; }
    else if rec.op == K_INT { rec.steps[n].kind = K_INT; rec.steps[n].min = rec.min; rec.steps[n].max = rec.max; }
    else if rec.op == K_INT64 { rec.steps[n].kind = K_INT64; rec.steps[n].min = rec.min; rec.steps[n].max = rec.max; }
    else if rec.op == K_INT128 { rec.steps[n].kind = K_INT128; rec.steps[n].min = rec.min; rec.steps[n].max = rec.max; }
    else if rec.op == K_INT_RELATIVE { rec.steps[n].kind = K_INT_RELATIVE; rec.steps[n].previous = rec.previous; }
    else if rec.op == K_FLOAT { rec.steps[n].kind = K_FLOAT; }
    else if rec.op == K_DOUBLE { rec.steps[n].kind = K_DOUBLE; }
    else if rec.op == K_COMPRESSED_FLOAT {
        rec.steps[n].kind = K_COMPRESSED_FLOAT;
        rec.steps[n].fmin = rec.fmin; rec.steps[n].fmax = rec.fmax; rec.steps[n].fres = rec.fres;
    } else if rec.op == K_BYTES {
        if rec.count < 0 || rec.count > CONF_MAX_BYTES { return false; }
        rec.steps[n].kind = K_BYTES; rec.steps[n].width = rec.count;
    } else if rec.op == K_STRING || rec.op == K_WSTRING {
        if rec.buffer_size < 1 || rec.buffer_size > CONF_MAX_BYTES { return false; }
        rec.steps[n].kind = rec.op; rec.steps[n].width = rec.buffer_size;
    } else if rec.op == K_FIXED {
        rec.steps[n].kind = K_FIXED;
        if !conf_fixed_decl(rec.steps[n], rec.integer_bits, rec.fraction_bits, rec.min, rec.max) { return false; }
    } else {
        return false;
    }
    n += 1;
    rec.step_count = n;
    return true;
}

fn conf_assign_expect(st: Step&, token: const u8[:]) {
    if conf_equals(token, "-") { return; }
    if st.kind == K_BOOL { st.want_bool = conf_equals(token, "true"); return; }
    if st.kind == K_BYTES || st.kind == K_STRING {
        st.input_len = conf_parse_hex_bytes(token, st.input);
        return;
    }
    if st.kind == K_WSTRING {
        st.want_unit_count = 0;
        var start: i64 = 0;
        var i: i64 = 0;
        while i <= token.len {
            if i == token.len || token[i] == ' ' {
                if i > start {
                    assert(i - start == 4);
                    var u: u32 = 0;
                    for k in 4 { u = (u << 4) | (conf_hex_digit(token[start + k]) as u32); }
                    assert(st.want_unit_count < CONF_MAX_UNITS);
                    st.want_units[st.want_unit_count] = u;
                    st.want_unit_count += 1;
                }
                start = i + 1;
            }
            i += 1;
        }
        return;
    }
    if st.kind == K_ALIGN || st.kind == K_OBJECT { return; }
    st.want = conf_parse_number(token);
}

fn conf_parse_expectations(rec: Rec&) {
    if !rec.has_expect || rec.refused { return; }
    // Count entries first, so a single-operation record's list can be aligned
    // to the end of its one-or-two step list.
    var count: i64 = 0;
    var k: i64 = 0;
    while k <= rec.expect_len {
        if k == rec.expect_len || rec.expect_text[k] == '|' { count += 1; }
        k += 1;
    }
    let offset = if rec.op == K_SEQUENCE { 0 } else { rec.step_count - count };
    assert(offset >= 0);
    var e: i64 = 0;
    var start: i64 = 0;
    var i: i64 = 0;
    while i <= rec.expect_len {
        if i == rec.expect_len || rec.expect_text[i] == '|' {
            var a = start;
            var b = i;
            while a < b && rec.expect_text[a] == ' ' { a += 1; }
            while b > a && rec.expect_text[b - 1] == ' ' { b -= 1; }
            conf_assign_expect(rec.steps[offset + e], rec.expect_text[a..b]);
            e += 1;
            start = i + 1;
        }
        i += 1;
    }
}

fn conf_parse_line(rec: Rec&, line: const u8[:]) {
    if line.len == 0 || line[0] == '#' { return; }
    if conf_starts(line, "operation ") {
        rec.op = conf_operation(line[10..]);
        rec.has_op = true;
        if rec.op == 0 { rec.bad = true; }
    } else if conf_starts(line, "name ") {
        return;
    } else if conf_starts(line, "param ") {
        conf_parse_param(rec, line[6..]);
    } else if conf_equals(line, "bytes") {
        rec.wire_len = 0;
    } else if conf_starts(line, "bytes ") {
        rec.wire_len = conf_parse_hex_bytes(line[6..], rec.wire);
    } else if conf_equals(line, "expect refused") {
        rec.refused = true;
    } else if conf_equals(line, "expect value =") || conf_equals(line, "expect bits =") {
        rec.has_expect = true;
        rec.expect_len = 0;
    } else if conf_starts(line, "expect value = ") {
        rec.has_expect = true;
        rec.expect_len = line.len - 15;
        for i in rec.expect_len { rec.expect_text[i] = line[15 + i]; }
    } else if conf_starts(line, "expect bits = ") {
        rec.has_expect = true;
        rec.expect_len = line.len - 14;
        for i in rec.expect_len { rec.expect_text[i] = line[14 + i]; }
    } else if conf_starts(line, "consumed ") {
        rec.consumed = conf_parse_dec(line[9..]);
    } else if conf_starts(line, "measure_at_least ") {
        rec.measure_at_least = conf_parse_dec(line[17..]);
    } else if conf_equals(line, "writer canonical") {
        rec.canonical = true;
    } else {
        rec.bad = true;
    }
}

// A refused read must leave the scalar destination alone and the stream
// terminal; terminality is checked by behavior, not an accessor (STANDARD.md,
// What a runner checks).
fn conf_check_terminal(s: ReadStream&) {
    var probe: u32 = 0xFFFFFFFF;
    assert(!serialize_bits(s, probe, 8));
    assert(probe == 0xFFFFFFFF);
    assert(serialize_error(s) != SERIALIZE_ERROR_NONE);
}

fn conf_run_record(rec: Rec&, sabotage: i64, sabotage_hits: i64&) -> i64 {
    if !rec.has_op { return 0; }
    if rec.bad { abort("conformance: no runner for this operation, parameter, or fixed declaration"); }
    if !conf_build_steps(rec) { abort("conformance: no runner for this vector"); }
    conf_parse_expectations(rec);

    var padded: u8[2048] = [0xFF; 2048];
    for i in rec.wire_len { padded[i] = rec.wire[i]; }
    var r = serialize_read_stream_init_padded(padded, rec.wire[0..rec.wire_len]);

    // Sentinels: a refused scalar read must leave its destination exactly as
    // it was (STANDARD.md, Reader Obligations).
    for i in rec.step_count {
        rec.steps[i].got = Int128 { lo: 0xCAFEF00D, hi: 0 };
        rec.steps[i].got_bool = true;
        rec.steps[i].got_len = 0;
    }

    var failed: i64 = -1;
    let ok = conf_run_steps(r, rec.steps, 0, rec.step_count, !rec.refused, sabotage, failed);

    if rec.refused {
        if sabotage != SAB_NONE {
            if ok { sabotage_hits += 1; return 1; }
            return 1;
        }
        assert(!ok);
        if failed >= 0 {
            let st = rec.steps[failed];
            if conf_is_pattern(st.kind) || conf_is_number(st.kind) {
                assert(st.got.lo == 0xCAFEF00D && st.got.hi == 0);
            } else if st.kind == K_BOOL {
                assert(st.got_bool);
            }
            // every later step must refuse too, even where bytes remain
            var j = failed + 1;
            while j < rec.step_count {
                var inner: i64 = -1;
                if rec.steps[j].kind == K_OBJECT {
                    assert(!conf_run_steps(r, rec.steps, j, j + 1 + rec.steps[j].width, false, sabotage, inner));
                    j += 1 + rec.steps[j].width;
                } else {
                    assert(!conf_run_steps(r, rec.steps, j, j + 1, false, sabotage, inner));
                    j += 1;
                }
            }
        }
        conf_check_terminal(r);
        return 1;
    }

    assert(ok);
    assert(serialize_bits_processed(r) == rec.consumed);

    if rec.canonical {
        var wbuf: u8[2048] = [0xAA; 2048];
        var w = serialize_write_stream_init(wbuf);
        var inner: i64 = -1;
        assert(conf_run_steps(w, rec.steps, 0, rec.step_count, false, sabotage, inner));
        serialize_flush(w);
        assert(serialize_bits_processed(w) == rec.consumed);
        assert(serialize_bytes_processed(w) == rec.wire_len);
        for i in rec.wire_len { assert(wbuf[i] == rec.wire[i]); }
    }

    if rec.measure_at_least > 0 {
        var m = serialize_measure_stream_init();
        var inner: i64 = -1;
        assert(conf_run_steps(m, rec.steps, 0, rec.step_count, false, sabotage, inner));
        assert(serialize_bits_processed(m) >= rec.measure_at_least);
    }
    return 1;
}

// Reads one vector file, running every record; returns the count. A blank line
// separates records (STANDARD.md, The vector format).
fn conf_run_file(filename: const u8[:], sabotage: i64, sabotage_hits: i64&) -> i64 {
    var content: u8[>..] = [];
    assert(read_file(filename, content));
    var rec = Rec {
        op: 0, has_op: false, preceding: 0, width: 0, count: 0, buffer_size: 0,
        integer_bits: 0, fraction_bits: 0, previous: 0,
        min: Int128 { lo: 0, hi: 0 }, max: Int128 { lo: 0, hi: 0 },
        fmin: 0.0, fmax: 0.0, fres: 0.0, refused: false, canonical: false,
        consumed: 0, measure_at_least: 0, has_expect: false,
        expect_text: [0; 1024], expect_len: 0, bad: false,
        wire: [0; 1024], wire_len: 0,
        steps: [conf_empty_step(); 64], step_count: 0,
    };
    var count: i64 = 0;
    var ops: i64 = 0;
    var start: i64 = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = conf_trim_cr(content[start..i]);
            start = i + 1;
            if line.len == 0 {
                count += conf_run_record(rec, sabotage, sabotage_hits);
                conf_rec_reset(rec);
            } else {
                if conf_starts(line, "operation ") { ops += 1; }
                conf_parse_line(rec, line);
            }
        }
    }
    assert(count == ops);
    return count;
}

fn conf_is_txt(name: const u8[:]) -> bool {
    return name.len > 4 && name[name.len - 4] == '.' && name[name.len - 3] == 't'
        && name[name.len - 2] == 'x' && name[name.len - 1] == 't';
}

// Discovers every *.txt in the staged corpus directory; never a fixed list,
// and an empty directory fails (STANDARD.md, The vector format; DESIGN.md (g)).
fn conf_run_corpus(sabotage: i64, sabotage_hits: i64&) -> i64 {
    var names: u8[>..] = [];
    assert(list_dir(".", names));
    var total: i64 = 0;
    var files: i64 = 0;
    var start: i64 = 0;
    for i in names.len + 1 {
        if i == names.len || names[i] == '\n' {
            let name = names[start..i];
            start = i + 1;
            if name.len > 0 && conf_is_txt(name) {
                let n = conf_run_file(name, sabotage, sabotage_hits);
                print(name, ": ", n, " records");
                total += n;
                files += 1;
            }
        }
    }
    assert(files > 0);
    assert(total > 0);
    print("corpus: ", files, " files, ", total, " records");
    return total;
}

// The unknown-operation control: a scratch copy whose operation has no runner
// must be rejected, never skipped (STANDARD.md, A gate nobody has seen go red).
fn conf_file_is_supported(filename: const u8[:]) -> bool {
    var content: u8[>..] = [];
    if !read_file(filename, content) { return false; }
    var start: i64 = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = conf_trim_cr(content[start..i]);
            start = i + 1;
            if conf_starts(line, "operation ") {
                if conf_operation(line[10..]) == 0 { return false; }
            }
        }
    }
    return true;
}

fn conf_unknown_operation_control() {
    let body: u8[>..] = "operation no_such_operation\nname control\nbytes 00\nexpect value = 0\nconsumed 0\n";
    assert(write_file("conformance_scratch.vector", body));
    assert(!conf_file_is_supported("conformance_scratch.vector"));
    assert(delete_file("conformance_scratch.vector"));
}

// goose: --debug
fn TestConformanceCorpus() {
    conf_unknown_operation_control();

    var hits: i64 = 0;
    let total = conf_run_corpus(SAB_NONE, hits);
    assert(total > 0);

    // The sabotaged reader: the align rule switched off through an argument,
    // run against the real align.txt. It must go red on exactly the vectors
    // that pin the rule -- every refused align record is accepted, and every
    // accepted record still passes (STANDARD.md, A gate nobody has seen go
    // red).
    var sabotage_hits: i64 = 0;
    let n = conf_run_file("align.txt", SAB_ALIGN, sabotage_hits);
    assert(n == 10);
    assert(sabotage_hits == 5);

    // The second sabotaged reader: int's range refusal deleted. It must go
    // red on exactly int.txt's six out-of-range refusals; the two past-end
    // refusals still refuse and every accepted record still passes.
    var int_hits: i64 = 0;
    let ni = conf_run_file("int.txt", SAB_INT_RANGE, int_hits);
    assert(ni == 26);
    assert(int_hits == 6);
}

// The unknown-operation control through the runner itself: a scratch vector
// file whose operation has no runner is REJECTED by conf_run_file, never
// skipped (STANDARD.md, A gate nobody has seen go red). Its extension is not
// .txt, so a corpus run staged beside it never discovers it.
// want-abort: conformance: no runner for this operation, parameter, or fixed declaration
fn TestConformanceUnknownOperationRejected() {
    let body: u8[>..] = "operation no_such_operation\nname control\nbytes 00\nexpect value = 0\nconsumed 0\n";
    assert(write_file("unknown_operation.vector", body));
    var hits: i64 = 0;
    conf_run_file("unknown_operation.vector", SAB_NONE, hits);
}

// The parser reads every header field whole: `measure_at_least 122` is 122
// (a slice one past the prefix once read it as 22, weakening every floor).
fn TestConformanceParsesMeasureFloor() {
    var rec = Rec {
        op: 0, has_op: false, preceding: 0, width: 0, count: 0, buffer_size: 0,
        integer_bits: 0, fraction_bits: 0, previous: 0,
        min: Int128 { lo: 0, hi: 0 }, max: Int128 { lo: 0, hi: 0 },
        fmin: 0.0, fmax: 0.0, fres: 0.0, refused: false, canonical: false,
        consumed: 0, measure_at_least: 0, has_expect: false,
        expect_text: [0; 1024], expect_len: 0, bad: false,
        wire: [0; 1024], wire_len: 0,
        steps: [conf_empty_step(); 64], step_count: 0,
    };
    conf_parse_line(rec, "measure_at_least 122");
    assert(rec.measure_at_least == 122);
    conf_parse_line(rec, "consumed 895");
    assert(rec.consumed == 895);
    assert(!rec.bad);
}
