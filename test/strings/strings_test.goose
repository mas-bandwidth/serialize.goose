// test/strings -- TestSerializeStrings (STANDARD.md, bytes, string, align,
// object, Refusal reasons; DESIGN.md (a), (d), (e)). Every record of
// bytes.txt, string.txt, align.txt and object.txt is run, every refusal is
// held to the reason its record states, and the record count per file is
// pinned to the file's count.

import os;
import .serialize;

// ---- small helpers --------------------------------------------------------

fn str_starts(s: const u8[:], p: const u8[:]) -> bool {
    if s.len < p.len { return false; }
    for i in p.len {
        if s[i] != p[i] { return false; }
    }
    return true;
}

fn str_equals(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len {
        if a[i] != b[i] { return false; }
    }
    return true;
}

fn trim_cr(s: const u8[:]) -> const u8[:] {
    if s.len > 0 && s[s.len - 1] == '\r' { return s[0..s.len - 1]; }
    return s;
}

fn hex_digit(c: u8) -> u8 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    abort("conformance: invalid hex digit");
}

fn parse_dec(s: const u8[:]) -> u64 {
    assert(s.len > 0);
    var v: u64 = 0;
    for i in s.len {
        assert(s[i] >= '0' && s[i] <= '9');
        v = v * 10 + (s[i] - '0');
    }
    return v;
}

fn parse_hex_into(s: const u8[:], out: u8[:]) -> i64 {
    var n: i64 = 0;
    var i: i64 = 0;
    while i < s.len {
        while i < s.len && (s[i] == ' ' || s[i] == '\t') { i += 1; }
        if i >= s.len { break; }
        assert(i + 1 < s.len);
        assert(n < out.len);
        out[n] = (hex_digit(s[i]) << 4) | hex_digit(s[i + 1]);
        n += 1;
        i += 2;
    }
    return n;
}

// The value of the first n wire bits, LSB-first (STANDARD.md, bits).
fn wire_bits(wire: const u8[:], n: i64) -> u32 {
    var v: u32 = 0;
    for i in n {
        let bit = (wire[i >> 3] >> ((i & 7) as u8)) & 1;
        v = v | ((bit as u32) << (i as u32));
    }
    return v;
}

// ---- records --------------------------------------------------------------

// Step kinds in an object.txt record: 1 bits, 2 bool, 3 align, 4 bytes,
// 5 object (the next n steps).
struct SStep { kind: i64, n: i64, val: u64 }

struct Seq { steps: SStep[16], start: i64, end: i64, check: bool }

// serialize is the object's own overload, which serialize_object invokes
// inline (STANDARD.md, object). It is the caller's function, in this module,
// so the library-side generic can name it.
fn serialize<S>(s: S&, seq: Seq&) -> bool {
    return run_steps(s, seq, seq.start, seq.end, seq.check);
}

struct Rec {
    op: i64, // 1 bytes, 2 string, 4 align, 5 object
    preceding: i64,
    count: i64,
    buffer_size: i64,
    refused: bool,
    reason: i32,
    canonical: bool,
    measure_at_least: i64,
    consumed: i64,
    wire: u8[128],
    wire_len: i64,
    value: u8[128],
    value_len: i64,
    steps: SStep[16],
    step_count: i64,
}

fn rec_reset(rec: Rec&) {
    rec.op = 0;
    rec.preceding = 0;
    rec.count = 0;
    rec.buffer_size = 0;
    rec.refused = false;
    rec.reason = SERIALIZE_ERROR_NONE;
    rec.canonical = false;
    rec.measure_at_least = 0;
    rec.consumed = 0;
    rec.wire_len = 0;
    rec.value_len = 0;
    rec.step_count = 0;
}

// ---- object sequences (conformance/object.txt) ----------------------------

// Runs steps [start,end) on any stream. A bits value round-trips through the
// same lvalue for write and read (DESIGN.md (a): one generic caller).
recursive fn run_steps<S>(s: S&, seq: Seq&, start: i64, end: i64, check: bool) -> bool {
    var i = start;
    while i < end {
        let st = seq.steps[i];
        if st.kind == 1 {
            var v: u32 = st.val as! u32;
            guard serialize_bits(s, v, st.n) else { return false; }
            guard !check || v == st.val as! u32 else { return false; }
            i += 1;
        } else if st.kind == 2 {
            var v = st.val != 0;
            guard serialize_bool(s, v) else { return false; }
            guard !check || v == (st.val != 0) else { return false; }
            i += 1;
        } else if st.kind == 3 {
            guard serialize_align(s) else { return false; }
            i += 1;
        } else if st.kind == 4 {
            var buf: u8[16] = [0; 16];
            for j in st.n { buf[j] = st.val as! u8; }
            guard serialize_bytes(s, buf[0..st.n]) else { return false; }
            for j in st.n {
                guard !check || buf[j] == st.val as! u8 else { return false; }
            }
            i += 1;
        } else if st.kind == 5 {
            var child = seq;
            child.start = i + 1;
            child.end = i + 1 + st.n;
            child.check = check;
            guard serialize_object(s, child) else { return false; }
            i += 1 + st.n;
        } else {
            abort("conformance: unknown object step");
        }
    }
    return true;
}

fn run_object_record(rec: Rec&) -> bool {
    var seq = Seq { steps: [SStep { kind: 0, n: 0, val: 0 }; 16], start: 0, end: rec.step_count, check: !rec.refused };
    assert(rec.step_count <= 16);
    for i in rec.step_count { seq.steps[i] = rec.steps[i]; }

    var padded: u8[256] = [0xFF; 256];
    var r = serialize_read_stream_init_padded(padded, rec.wire[0..rec.wire_len]);
    let ok = serialize_object(r, seq);
    assert(ok == !rec.refused);
    if rec.refused {
        assert(serialize_error(r) == rec.reason);
        return true;
    }
    assert(serialize_bits_processed(r) == rec.consumed);

    if rec.canonical {
        var wbuf: u8[64] = [0xAA; 64];
        var w = serialize_write_stream_init(wbuf);
        assert(serialize_object(w, seq));
        serialize_flush(w);
        assert(serialize_bits_processed(w) == rec.consumed);
        for i in rec.wire_len {
            assert(wbuf[i] == rec.wire[i]);
        }
    }

    var m = serialize_measure_stream_init();
    assert(serialize_object(m, seq));
    let least = if rec.measure_at_least > 0 { rec.measure_at_least } else { rec.consumed };
    assert(serialize_bits_processed(m) >= least);
    return true;
}

// ---- the per-operation records --------------------------------------------

fn run_bytes_record(rec: Rec&) -> bool {
    var padded: u8[256] = [0xFF; 256];
    var r = serialize_read_stream_init_padded(padded, rec.wire[0..rec.wire_len]);
    var pre: u32 = 0;
    if rec.preceding > 0 { assert(serialize_bits(r, pre, rec.preceding)); }
    var data: u8[64] = [0xAA; 64];
    let ok = serialize_bytes(r, data[0..rec.count]);
    if rec.refused {
        assert(!ok);
        assert(serialize_error(r) == rec.reason);
        return true;
    }
    assert(ok);
    assert(serialize_bits_processed(r) == rec.consumed);
    for i in rec.count { assert(data[i] == rec.value[i]); }

    if rec.canonical {
        var wbuf: u8[64] = [0xAA; 64];
        var w = serialize_write_stream_init(wbuf);
        if rec.preceding > 0 {
            assert(serialize_bits(w, wire_bits(rec.wire, rec.preceding), rec.preceding));
        }
        var wdata: u8[64] = [0; 64];
        for i in rec.count { wdata[i] = rec.value[i]; }
        assert(serialize_bytes(w, wdata[0..rec.count]));
        serialize_flush(w);
        assert(serialize_bits_processed(w) == rec.consumed);
        for i in rec.wire_len { assert(wbuf[i] == rec.wire[i]); }
    }
    return true;
}

fn run_string_record(rec: Rec&) -> bool {
    var padded: u8[256] = [0xFF; 256];
    var r = serialize_read_stream_init_padded(padded, rec.wire[0..rec.wire_len]);
    var out: u8[>..] = [];
    out.push(0x5A);
    let ok = serialize_string(r, out, rec.buffer_size);
    if rec.refused {
        assert(!ok);
        assert(serialize_error(r) == rec.reason);
        assert(out.len == 1 && out[0] == 0x5A); // destination untouched
        return true;
    }
    assert(ok);
    assert(out.len == rec.value_len);
    for i in rec.value_len { assert(out[i] == rec.value[i]); }
    assert(serialize_bits_processed(r) == rec.consumed);

    if rec.canonical {
        var wbuf: u8[64] = [0xAA; 64];
        var w = serialize_write_stream_init(wbuf);
        var wdata: u8[64] = [0; 64];
        for i in rec.value_len { wdata[i] = rec.value[i]; }
        assert(serialize_string(w, wdata[0..rec.value_len], rec.buffer_size));
        serialize_flush(w);
        assert(serialize_bits_processed(w) == rec.consumed);
        for i in rec.wire_len { assert(wbuf[i] == rec.wire[i]); }
    }
    return true;
}

fn run_align_record(rec: Rec&) -> bool {
    var padded: u8[256] = [0xFF; 256];
    var r = serialize_read_stream_init_padded(padded, rec.wire[0..rec.wire_len]);
    var pre: u32 = 0;
    if rec.preceding > 0 { assert(serialize_bits(r, pre, rec.preceding)); }
    let ok = serialize_align(r);
    if rec.refused {
        assert(!ok);
        assert(serialize_error(r) == rec.reason);
        return true;
    }
    assert(ok);
    assert(serialize_bits_processed(r) == rec.consumed);
    assert(pre == 0 || rec.preceding > 0);

    if rec.canonical {
        var wbuf: u8[64] = [0xAA; 64];
        var w = serialize_write_stream_init(wbuf);
        if rec.preceding > 0 {
            assert(serialize_bits(w, wire_bits(rec.wire, rec.preceding), rec.preceding));
        }
        assert(serialize_align(w));
        serialize_flush(w);
        assert(serialize_bits_processed(w) == rec.consumed);
        for i in rec.wire_len { assert(wbuf[i] == rec.wire[i]); }
    }
    return true;
}

fn run_record(rec: Rec&) -> i64 {
    if rec.op == 0 { return 0; }
    var ok = false;
    if rec.op == 1 { ok = run_bytes_record(rec); }
    else if rec.op == 2 { ok = run_string_record(rec); }
    else if rec.op == 4 { ok = run_align_record(rec); }
    else if rec.op == 5 { ok = run_object_record(rec); }
    else { abort("conformance: unknown operation"); }
    assert(ok);
    return 1;
}

// ---- the vector-file reader ----------------------------------------------

fn parse_step_value(st: SStep&, tok: const u8[:]) {
    if st.kind == 1 { st.val = parse_dec(tok); }
    else if st.kind == 2 { st.val = if str_equals(tok, "true") { 1 } else { 0 }; }
    else if st.kind == 4 { assert(tok.len == 2); st.val = (hex_digit(tok[0]) << 4) | hex_digit(tok[1]); }
}

// Assigns one `expect value` token to the matching step (object.txt only).
fn assign_expects(rec: Rec&, s: const u8[:]) {
    var idx: i64 = 0;
    var start: i64 = 0;
    var i: i64 = 0;
    while i <= s.len {
        if i == s.len || s[i] == '|' {
            var a = start;
            var b = i;
            while a < b && s[a] == ' ' { a += 1; }
            while b > a && s[b - 1] == ' ' { b -= 1; }
            let tok = s[a..b];
            if idx < rec.step_count && !str_equals(tok, "-") {
                parse_step_value(rec.steps[idx], tok);
            }
            idx += 1;
            start = i + 1;
        }
        i += 1;
    }
}

fn parse_value_line(rec: Rec&, s: const u8[:]) {
    if rec.op == 1 || rec.op == 2 {
        rec.value_len = parse_hex_into(s, rec.value[0..128]);
    } else if rec.op == 5 {
        assign_expects(rec, s);
    }
}

fn parse_param(rec: Rec&, s: const u8[:]) {
    if str_starts(s, "preceding_bits = ") {
        rec.preceding = parse_dec(s[17..]) as! i64;
    } else if str_starts(s, "count = ") {
        rec.count = parse_dec(s[8..]) as! i64;
    } else if str_starts(s, "buffer_size = ") {
        rec.buffer_size = parse_dec(s[14..]) as! i64;
    } else if str_starts(s, "step = ") {
        let t = s[7..];
        var st = SStep { kind: 0, n: 0, val: 0 };
        if str_equals(t, "bool") { st.kind = 2; }
        else if str_equals(t, "align") { st.kind = 3; }
        else if str_starts(t, "bits ") { st.kind = 1; st.n = parse_dec(t[5..]) as! i64; }
        else if str_starts(t, "bytes ") { st.kind = 4; st.n = parse_dec(t[6..]) as! i64; }
        else if str_starts(t, "object ") { st.kind = 5; st.n = parse_dec(t[7..]) as! i64; }
        else { abort("conformance: unknown object step in object.txt"); }
        assert(rec.step_count < 16);
        rec.steps[rec.step_count] = st;
        rec.step_count += 1;
    } else {
        abort("conformance: unknown param in strings vector file");
    }
}

// The directive-free line parser every file shares.
fn parse_line(rec: Rec&, line: const u8[:]) {
    if line.len == 0 || line[0] == '#' || str_starts(line, "name ") { return; }
    if str_starts(line, "operation ") {
        let op = line[10..];
        if str_equals(op, "bytes") { rec.op = 1; }
        else if str_equals(op, "string") { rec.op = 2; }
        else if str_equals(op, "align") { rec.op = 4; }
        else if str_equals(op, "sequence") { rec.op = 5; }
        else { abort("conformance: unknown operation in strings vector file"); }
    } else if str_starts(line, "param ") {
        parse_param(rec, line[6..]);
    } else if str_equals(line, "bytes") {
        rec.wire_len = 0;
    } else if str_starts(line, "bytes ") {
        rec.wire_len = parse_hex_into(line[6..], rec.wire[0..128]);
    } else if str_starts(line, "expect refused ") {
        rec.refused = true;
        rec.reason = reason_of(line[15..]);
    } else if str_equals(line, "expect value =") {
        parse_value_line(rec, line[14..14]);
    } else if str_starts(line, "expect value = ") {
        parse_value_line(rec, line[15..]);
    } else if str_starts(line, "consumed ") {
        rec.consumed = parse_dec(line[9..]) as! i64;
    } else if str_starts(line, "measure_at_least ") {
        rec.measure_at_least = parse_dec(line[17..]) as! i64;
    } else if str_equals(line, "writer canonical") {
        rec.canonical = true;
    } else {
        abort("conformance: unknown line in strings vector file");
    }
}

// The reason a refused record states, from the closed list (STANDARD.md,
// Refusal reasons); a missing or unknown reason is a malformed vector.
fn reason_of(name: const u8[:]) -> i32 {
    for k in 8 {
        let kind = (k + 1) as! i32;
        if str_equals(name, serialize_refusal_name(kind)) { return kind; }
    }
    abort("conformance: refused record states no known reason");
}

fn run_conformance_file(filename: const u8[:]) -> i64 {
    var content: u8[>..] = [];
    assert(read_file(filename, content));
    var rec = Rec {
        op: 0, preceding: 0, count: 0, buffer_size: 0, refused: false,
        reason: SERIALIZE_ERROR_NONE, canonical: false, measure_at_least: 0, consumed: 0,
        wire: [0; 128], wire_len: 0, value: [0; 128], value_len: 0,
        steps: [SStep { kind: 0, n: 0, val: 0 }; 16], step_count: 0,
    };
    var count = 0;
    var start: i64 = 0;
    for i in content.len + 1 {
        if i == content.len || content[i] == '\n' {
            let line = trim_cr(content[start..i]);
            start = i + 1;
            if line.len == 0 {
                count += run_record(rec);
                rec_reset(rec);
            } else {
                parse_line(rec, line);
            }
        }
    }
    return count;
}

// goose: --debug
fn TestSerializeStrings() {
    let n_bytes = run_conformance_file("bytes.txt");
    let n_string = run_conformance_file("string.txt");
    let n_align = run_conformance_file("align.txt");
    let n_object = run_conformance_file("object.txt");
    print(n_bytes, n_string, n_align, n_object);
    assert(n_bytes == 12);
    assert(n_string == 53);
    assert(n_align == 10);
    assert(n_object == 7);
}

// Allocate-before-check (PORT-BRIEF, added 2026-10-22): a length field that
// claims far more bytes than the stream holds is refused as PAST_END before
// the destination is touched or grown. buffer_size 2^20 gives a 20-bit length
// field; all ones claims 1048575 bytes over a 4-byte stream.
fn TestSerializeStringClaimedLengthCheckedFirst() {
    var wire: u8[16] = [0xFF, 0xFF, 0x0F, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = serialize_read_stream_init(wire, 4);
    var out: u8[>..] = [];
    out.push(0x5A);
    assert(!serialize_string(r, out, 1048576));
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
    assert(out.len == 1 && out[0] == 0x5A);
}

// The string writer is handed text with no zero byte, as it is handed an int
// in its range (STANDARD.md, string): a NUL is caller error and aborts.
// want-abort: serialize: string must not contain a zero byte
fn TestSerializeStringWriterNulAborts() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    let text: u8[3] = [0x41, 0x00, 0x42];
    serialize_string(w, text[0..3], 16);
}

// end (STANDARD.md, end): the writer and the measure emit and cost nothing;
// the reader accepts an exactly consumed stream and leaves the cursor at its
// end, refuses a whole byte left as TRAILING_DATA before it looks at padding,
// refuses a set padding bit as NONZERO_PADDING, and on a failed stream keeps
// the first refusal's reason.
fn TestSerializeEnd() {
    var buf: u8[16] = [0; 16];
    var w = serialize_write_stream_init(buf);
    assert(serialize_bits(w, 5, 3));
    assert(serialize_end(w));
    assert(serialize_bits_processed(w) == 3);
    var m = serialize_measure_stream_init();
    assert(serialize_bits(m, 5, 3));
    assert(serialize_end(m));
    assert(serialize_bits_processed(m) == 3);

    var exact: u8[16] = [0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = serialize_read_stream_init(exact, 1);
    var v: u32 = 0;
    assert(serialize_bits(r, v, 3) && v == 5);
    assert(serialize_end(r));
    assert(serialize_bits_processed(r) == 8);
    assert(serialize_bits_remaining(r) == 0);
    assert(serialize_error(r) == SERIALIZE_ERROR_NONE);

    // A whole byte left, with set padding too: TRAILING_DATA comes first.
    var trailing: u8[16] = [0xFD, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var t = serialize_read_stream_init(trailing, 2);
    assert(serialize_bits(t, v, 3));
    assert(!serialize_end(t));
    assert(serialize_error(t) == SERIALIZE_ERROR_TRAILING_DATA);

    var padded: u8[16] = [0x85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var p = serialize_read_stream_init(padded, 1);
    assert(serialize_bits(p, v, 3));
    assert(!serialize_end(p));
    assert(serialize_error(p) == SERIALIZE_ERROR_NONZERO_PADDING);

    // The latch first: an end on a failed stream refuses with the first reason.
    var empty: u8[8] = [0; 8];
    var e = serialize_read_stream_init(empty, 0);
    assert(!serialize_bits(e, v, 1));
    assert(!serialize_end(e));
    assert(serialize_error(e) == SERIALIZE_ERROR_PAST_END);

    // A latched write stream refuses its end too.
    var wl = serialize_write_stream_init(buf);
    assert(!serialize_fail(wl, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE));
    assert(!serialize_end(wl));
}
