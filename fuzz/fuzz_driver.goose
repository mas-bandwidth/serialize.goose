// fuzz/fuzz_driver.goose -- the Goose half of TestDifferentialAgainstSerializeC.
//
// fuzz/host.c writes one batch of programs; this driver (built once with
// goose build, run as `fuzz_driver <batch> <output>`) replays every program on
// the port's write stream, then reads the C writer's bytes and, where present,
// the mutant bytes. It prints one W line per program (the port's bytes), one
// M line with the measure stream's bit count, and R/V lines with the
// accept/refuse verdict, the refusing step, the refusal reason ("none" on an
// accepted read; STANDARD.md, Refusal reasons), the reader's consumed bit
// count, a terminal flag (on a refused read, whether one further read is
// also refused; -1 on an accepted read) and every value decoded before it.
// The host compares these against serialize.c's own results. The same source
// is also built optimized (goose build -O2, no --debug) by make/fuzz.mk, and
// the host requires the two builds' outputs to be identical. The line format
// is serialize.lobster's fuzz driver's, so the host is the family's.

import .serialize;
import std;
import os;

// ---- text ------------------------------------------------------------------

fn fz_die(what: const u8[:], text: const u8[:]) {
    write_stderr(str("fuzz driver: ", what, " ", text, "\n"));
    exit(2);
}

fn fz_dec(text: const u8[:]) -> i64 {
    let v, ok = parse_int(text, 10);
    if !ok { fz_die("bad integer", text); }
    return v;
}

fn fz_nibble(c: u8) -> u64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return (c - 'a') + 10; }
    if c >= 'A' && c <= 'F' { return (c - 'A') + 10; }
    fz_die("bad hex digit in", "token");
    return 0;
}

fn fz_hex(text: const u8[:]) -> u64 {
    if text.len == 0 || text.len > 16 { fz_die("bad hex", text); }
    var v: u64 = 0;
    for i in text.len { v = (v << 4) | fz_nibble(text[i]); }
    return v;
}

// Hex text ("-" for none) into out; returns the byte count.
fn fz_unhex(text: const u8[:], out: u8[:]) -> i64 {
    if text.len == 1 && text[0] == '-' { return 0; }
    let n = text.len / 2;
    if n * 2 != text.len || n > out.len { fz_die("bad hex bytes", text); }
    for i in n {
        out[i] = ((fz_nibble(text[2 * i]) << 4) | fz_nibble(text[2 * i + 1])) as! u8;
    }
    return n;
}

fn fz_put_hex(out: u8[>..]&, v: u64, digits: i64) { format_uint(out, v, 16, digits, '0'); }

fn fz_put_bytes(out: u8[>..]&, data: const u8[:]) {
    if data.len == 0 { out.push('-'); return; }
    for i in data.len { format_uint(out, data[i], 16, 2, '0'); }
}

fn fz_put_tok64(out: u8[>..]&, v: u64) {
    out.push(' ');
    fz_put_hex(out, v, 16);
}

fn fz_put_tok128(out: u8[>..]&, hi: u64, lo: u64) {
    out.push(' ');
    fz_put_hex(out, hi, 16);
    fz_put_hex(out, lo, 16);
}

fn fz_f32(text: const u8[:]) -> f32 { return serialize_f32_from_bits(fz_hex(text) as! u32); }

// ---- object: the caller's own serialize (STANDARD.md, object; DESIGN.md (a)) --

struct FzObject { b: bool, i: i32, u: u16 }

fn serialize<S>(s: S&, o: FzObject&) -> bool {
    return serialize_bool(s, o.b) && serialize_int(s, o.i, 0, 7) && serialize_uint16(s, o.u);
}

// ---- write ------------------------------------------------------------------

fn fz_write(w: WriteStream&, line: const u8[:]) -> bool {
    let t = split(line, ' ');
    let kind = t[0];
    if kind == "bits" { return serialize_bits(w, fz_dec(t[2]) as! u32, fz_dec(t[1])); }
    if kind == "bits64" { return serialize_bits64(w, fz_hex(t[2]), fz_dec(t[1])); }
    if kind == "bool" { return serialize_bool(w, fz_dec(t[1]) != 0); }
    if kind == "uint8" { return serialize_uint8(w, fz_dec(t[1]) as! u8); }
    if kind == "uint16" { return serialize_uint16(w, fz_dec(t[1]) as! u16); }
    if kind == "uint32" { return serialize_uint32(w, fz_dec(t[1]) as! u32); }
    if kind == "uint64" { return serialize_uint64(w, fz_hex(t[1])); }
    if kind == "int" {
        return serialize_int(w, fz_dec(t[3]) as! i32, fz_dec(t[1]) as! i32, fz_dec(t[2]) as! i32);
    }
    if kind == "int64" { return serialize_int64(w, fz_dec(t[3]), fz_dec(t[1]), fz_dec(t[2])); }
    if kind == "int_rel" { return serialize_int_relative(w, fz_dec(t[1]) as! i32, fz_dec(t[2]) as! i32); }
    if kind == "uint128" { return serialize_uint128(w, Uint128 { lo: fz_hex(t[1]), hi: fz_hex(t[2]) }); }
    if kind == "int128" {
        return serialize_int128(w, Int128 { lo: fz_hex(t[5]), hi: fz_hex(t[6]) },
            Int128 { lo: fz_hex(t[1]), hi: fz_hex(t[2]) }, Int128 { lo: fz_hex(t[3]), hi: fz_hex(t[4]) });
    }
    if kind == "float" { return serialize_float(w, fz_f32(t[1])); }
    if kind == "double" { return serialize_double(w, serialize_f64_from_bits(fz_hex(t[1]))); }
    if kind == "fixed32" {
        return serialize_fixed32(w, fz_dec(t[5]) as! i32, fz_dec(t[1]), fz_dec(t[2]),
            fz_dec(t[3]) as! i32, fz_dec(t[4]) as! i32);
    }
    if kind == "fixed64" {
        return serialize_fixed64(w, fz_dec(t[5]), fz_dec(t[1]), fz_dec(t[2]), fz_dec(t[3]), fz_dec(t[4]));
    }
    if kind == "fixed128" {
        return serialize_fixed128(w, Int128 { lo: fz_hex(t[5]), hi: fz_hex(t[6]) }, fz_dec(t[1]), fz_dec(t[2]),
            fz_dec(t[3]), fz_dec(t[4]));
    }
    if kind == "cfloat" { return serialize_compressed_float(w, fz_f32(t[4]), fz_f32(t[1]), fz_f32(t[2]), fz_f32(t[3])); }
    if kind == "cfloat_pre" {
        return serialize_compressed_float_precomputed(w, fz_f32(t[5]), fz_dec(t[1]) as! u32, fz_dec(t[2]),
            fz_f32(t[3]), fz_f32(t[4]));
    }
    if kind == "bytes" {
        var data: u8[64] = [0; 64];
        let n = fz_unhex(t[2], data);
        if n != fz_dec(t[1]) { fz_die("bytes length mismatch", line); }
        return serialize_bytes(w, data[0..n]);
    }
    if kind == "string" {
        var data: u8[64] = [0; 64];
        let n = fz_unhex(t[2], data);
        return serialize_string(w, data[0..n], fz_dec(t[1]));
    }
    if kind == "align" { return serialize_align(w); }
    if kind == "end" { return serialize_end(w); }
    if kind == "object" {
        var o = FzObject { b: true, i: 3, u: 42 };
        return serialize_object(w, o);
    }
    fz_die("unknown op", line);
    return false;
}

fn fz_run_write(out: u8[>..]&, id: i64, ops: const u8[:][:]) {
    var buffer: u8[1024] = [0; 1024];
    var w = serialize_write_stream_init(buffer);
    var ok = true;
    for line in ops {
        if !ok { break; }
        ok = fz_write(w, line);
    }
    serialize_flush(w);
    format(out, "W ", id, " ");
    fz_put_bytes(out, buffer[0..serialize_bytes_processed(w)]);
    format(out, if ok && serialize_error(w) == SERIALIZE_ERROR_NONE { " 1\n" } else { " 0\n" });
}

// ---- measure (the same dispatch on a MeasureStream) -------------------------

fn fz_measure(m: MeasureStream&, line: const u8[:]) -> bool {
    let t = split(line, ' ');
    let kind = t[0];
    if kind == "bits" { return serialize_bits(m, fz_dec(t[2]) as! u32, fz_dec(t[1])); }
    if kind == "bits64" { return serialize_bits64(m, fz_hex(t[2]), fz_dec(t[1])); }
    if kind == "bool" { return serialize_bool(m, fz_dec(t[1]) != 0); }
    if kind == "uint8" { return serialize_uint8(m, fz_dec(t[1]) as! u8); }
    if kind == "uint16" { return serialize_uint16(m, fz_dec(t[1]) as! u16); }
    if kind == "uint32" { return serialize_uint32(m, fz_dec(t[1]) as! u32); }
    if kind == "uint64" { return serialize_uint64(m, fz_hex(t[1])); }
    if kind == "int" {
        return serialize_int(m, fz_dec(t[3]) as! i32, fz_dec(t[1]) as! i32, fz_dec(t[2]) as! i32);
    }
    if kind == "int64" { return serialize_int64(m, fz_dec(t[3]), fz_dec(t[1]), fz_dec(t[2])); }
    if kind == "int_rel" { return serialize_int_relative(m, fz_dec(t[1]) as! i32, fz_dec(t[2]) as! i32); }
    if kind == "uint128" { return serialize_uint128(m, Uint128 { lo: fz_hex(t[1]), hi: fz_hex(t[2]) }); }
    if kind == "int128" {
        return serialize_int128(m, Int128 { lo: fz_hex(t[5]), hi: fz_hex(t[6]) },
            Int128 { lo: fz_hex(t[1]), hi: fz_hex(t[2]) }, Int128 { lo: fz_hex(t[3]), hi: fz_hex(t[4]) });
    }
    if kind == "float" { return serialize_float(m, fz_f32(t[1])); }
    if kind == "double" { return serialize_double(m, serialize_f64_from_bits(fz_hex(t[1]))); }
    if kind == "fixed32" {
        return serialize_fixed32(m, fz_dec(t[5]) as! i32, fz_dec(t[1]), fz_dec(t[2]),
            fz_dec(t[3]) as! i32, fz_dec(t[4]) as! i32);
    }
    if kind == "fixed64" {
        return serialize_fixed64(m, fz_dec(t[5]), fz_dec(t[1]), fz_dec(t[2]), fz_dec(t[3]), fz_dec(t[4]));
    }
    if kind == "fixed128" {
        return serialize_fixed128(m, Int128 { lo: fz_hex(t[5]), hi: fz_hex(t[6]) }, fz_dec(t[1]), fz_dec(t[2]),
            fz_dec(t[3]), fz_dec(t[4]));
    }
    if kind == "cfloat" { return serialize_compressed_float(m, fz_f32(t[4]), fz_f32(t[1]), fz_f32(t[2]), fz_f32(t[3])); }
    if kind == "cfloat_pre" {
        return serialize_compressed_float_precomputed(m, fz_f32(t[5]), fz_dec(t[1]) as! u32, fz_dec(t[2]),
            fz_f32(t[3]), fz_f32(t[4]));
    }
    if kind == "bytes" {
        var data: u8[64] = [0; 64];
        let n = fz_unhex(t[2], data);
        if n != fz_dec(t[1]) { fz_die("bytes length mismatch", line); }
        return serialize_bytes(m, data[0..n]);
    }
    if kind == "string" {
        var data: u8[64] = [0; 64];
        let n = fz_unhex(t[2], data);
        return serialize_string(m, data[0..n], fz_dec(t[1]));
    }
    if kind == "align" { return serialize_align(m); }
    if kind == "end" { return serialize_end(m); }
    if kind == "object" {
        var o = FzObject { b: true, i: 3, u: 42 };
        return serialize_object(m, o);
    }
    fz_die("unknown op", line);
    return false;
}

fn fz_run_measure(out: u8[>..]&, id: i64, ops: const u8[:][:]) {
    var m = serialize_measure_stream_init();
    var ok = true;
    for line in ops {
        if !ok { break; }
        ok = fz_measure(m, line);
    }
    format(out, "M ", id, " ", serialize_bits_processed(m),
        if ok && serialize_error(m) == SERIALIZE_ERROR_NONE { " 1\n" } else { " 0\n" });
}

// ---- read -------------------------------------------------------------------

// Reads one operation; on success appends its value tokens (each with a
// leading space) to toks, in the host's spelling (fuzz/host.c, read_program).
fn fz_read(r: ReadStream&, line: const u8[:], toks: u8[>..]&) -> bool {
    let t = split(line, ' ');
    let kind = t[0];
    if kind == "bits" {
        var v: u32 = 0;
        guard serialize_bits(r, v, fz_dec(t[1])) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "bits64" {
        var v: u64 = 0;
        guard serialize_bits64(r, v, fz_dec(t[1])) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "bool" {
        var v = false;
        guard serialize_bool(r, v) else { return false; }
        toks.append(if v { " 1" } else { " 0" });
        return true;
    }
    if kind == "uint8" {
        var v: u8 = 0;
        guard serialize_uint8(r, v) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "uint16" {
        var v: u16 = 0;
        guard serialize_uint16(r, v) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "uint32" {
        var v: u32 = 0;
        guard serialize_uint32(r, v) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "uint64" {
        var v: u64 = 0;
        guard serialize_uint64(r, v) else { return false; }
        fz_put_tok64(toks, v);
        return true;
    }
    if kind == "int" {
        var v: i32 = 0;
        guard serialize_int(r, v, fz_dec(t[1]) as! i32, fz_dec(t[2]) as! i32) else { return false; }
        fz_put_tok64(toks, v as! u64);
        return true;
    }
    if kind == "int64" {
        var v: i64 = 0;
        guard serialize_int64(r, v, fz_dec(t[1]), fz_dec(t[2])) else { return false; }
        fz_put_tok64(toks, v as! u64);
        return true;
    }
    if kind == "int_rel" {
        var v: i32 = 0;
        guard serialize_int_relative(r, fz_dec(t[1]) as! i32, v) else { return false; }
        fz_put_tok64(toks, v as! u64);
        return true;
    }
    if kind == "uint128" {
        var v = Uint128 { lo: 0, hi: 0 };
        guard serialize_uint128(r, v) else { return false; }
        fz_put_tok128(toks, v.hi, v.lo);
        return true;
    }
    if kind == "int128" {
        var v = Int128 { lo: 0, hi: 0 };
        guard serialize_int128(r, v, Int128 { lo: fz_hex(t[1]), hi: fz_hex(t[2]) },
            Int128 { lo: fz_hex(t[3]), hi: fz_hex(t[4]) }) else { return false; }
        fz_put_tok128(toks, v.hi, v.lo);
        return true;
    }
    if kind == "float" {
        var v: f32 = 0.0;
        guard serialize_float(r, v) else { return false; }
        toks.push(' ');
        fz_put_hex(toks, serialize_f32_bits(v), 8);
        return true;
    }
    if kind == "double" {
        var v: f64 = 0.0;
        guard serialize_double(r, v) else { return false; }
        fz_put_tok64(toks, serialize_f64_bits(v));
        return true;
    }
    if kind == "fixed32" {
        var v: i32 = 0;
        guard serialize_fixed32(r, v, fz_dec(t[1]), fz_dec(t[2]), fz_dec(t[3]) as! i32, fz_dec(t[4]) as! i32)
            else { return false; }
        fz_put_tok64(toks, v as! u64);
        return true;
    }
    if kind == "fixed64" {
        var v: i64 = 0;
        guard serialize_fixed64(r, v, fz_dec(t[1]), fz_dec(t[2]), fz_dec(t[3]), fz_dec(t[4])) else { return false; }
        fz_put_tok64(toks, v as! u64);
        return true;
    }
    if kind == "fixed128" {
        var v = Int128 { lo: 0, hi: 0 };
        guard serialize_fixed128(r, v, fz_dec(t[1]), fz_dec(t[2]), fz_dec(t[3]), fz_dec(t[4])) else { return false; }
        fz_put_tok128(toks, v.hi, v.lo);
        return true;
    }
    if kind == "cfloat" {
        var v: f32 = 0.0;
        guard serialize_compressed_float(r, v, fz_f32(t[1]), fz_f32(t[2]), fz_f32(t[3])) else { return false; }
        toks.push(' ');
        fz_put_hex(toks, serialize_f32_bits(v), 8);
        return true;
    }
    if kind == "cfloat_pre" {
        var v: f32 = 0.0;
        guard serialize_compressed_float_precomputed(r, v, fz_dec(t[1]) as! u32, fz_dec(t[2]), fz_f32(t[3]),
            fz_f32(t[4])) else { return false; }
        toks.push(' ');
        fz_put_hex(toks, serialize_f32_bits(v), 8);
        return true;
    }
    if kind == "bytes" {
        var data: u8[64] = [0; 64];
        let n = fz_dec(t[1]);
        guard serialize_bytes(r, data[0..n]) else { return false; }
        toks.push(' ');
        fz_put_bytes(toks, data[0..n]);
        return true;
    }
    if kind == "string" {
        var v: u8[>..] = [];
        guard serialize_string(r, v, fz_dec(t[1])) else { return false; }
        toks.push(' ');
        fz_put_bytes(toks, v);
        return true;
    }
    if kind == "align" { return serialize_align(r); }
    if kind == "end" { return serialize_end(r); }
    if kind == "object" {
        var o = FzObject { b: false, i: 0, u: 0 };
        guard serialize_object(r, o) else { return false; }
        toks.append(if o.b { " 1" } else { " 0" });
        fz_put_tok64(toks, o.i as! u64);
        fz_put_tok64(toks, o.u);
        return true;
    }
    fz_die("unknown op", line);
    return false;
}

fn fz_run_read(out: u8[>..]&, bytes_hex: const u8[:], ops: const u8[:][:], id: i64, src: const u8[:]) {
    // A mutant may append up to 8 bytes to the host's 1024-byte buffer.
    var bytes: u8[1040] = [0; 1040];
    let n = fz_unhex(bytes_hex, bytes);
    var padded: u8[1048] = [0; 1048];
    var r = serialize_read_stream_init_padded(padded, bytes[0..n]);
    var accept = true;
    var step = ops.len;
    var body: u8[>..] = [];
    for line, i in ops {
        var toks: u8[>..] = [];
        if !fz_read(r, line, toks) {
            accept = false;
            step = i;
            break;
        }
        if toks.len > 0 { format(body, "V ", id, " ", src, " ", i, toks, "\n"); }
    }
    let consumed = serialize_bits_processed(r);
    var terminal: i64 = -1;
    if !accept {
        var extra = false;
        terminal = if serialize_bool(r, extra) { 0 } else { 1 };
    }
    format(out, "R ", id, " ", src, if accept { " 1 " } else { " 0 " }, step, " ",
        serialize_refusal_name(serialize_error(r)), " ", consumed, " ", terminal, "\n", body);
}

// ---- main -------------------------------------------------------------------

fn main() {
    let a = args();
    if a.len < 3 {
        write_stderr("fuzz driver: usage fuzz_driver <batch> <output>\n");
        exit(2);
    }
    var text: u8[>..] = [];
    if !read_file(a[1], text) { fz_die("cannot read", a[1]); }
    let lines = split(text, '\n');
    var out: u8[>..] = [];
    var i = 0;
    while i < lines.len {
        let line = lines[i];
        if line.len == 0 {
            i += 1;
            continue;
        }
        let t = split(line, ' ');
        if t.len != 6 || t[0] != "P" { fz_die("expected a P line:", line); }
        let id = fz_dec(t[1]);
        let nops = fz_dec(t[2]);
        let has_mutant = fz_dec(t[3]) != 0;
        if nops < 1 || i + 1 + nops > lines.len { fz_die("short program", line); }
        let ops = lines[i + 1..i + 1 + nops];
        fz_run_write(out, id, ops);
        fz_run_measure(out, id, ops);
        fz_run_read(out, t[4], ops, id, "c");
        if has_mutant { fz_run_read(out, t[5], ops, id, "m"); }
        i += 1 + nops;
    }
    if !write_file(a[2], out) { fz_die("cannot write", a[2]); }
}
