// fuzz/differential_test.goose -- TestDifferentialAgainstSerializeC.
//
// One process runs serialize.c v1.11.2 (through fuzz/host.c) and this port
// over the same generated programs: the bytes a write produces must be equal,
// each reader must decode the other's bytes to the program's values, and on a
// mutated message both readers must agree on accept/refuse, the refusing
// step, and every value decoded before it (JOB.md, THE TASK; DESIGN.md (e)).
//
// A program is a sequence of 1..24 operations encoded in fixed 96-byte
// records (fuzz/host.c reads the same shape): kind u32 at 0, payload length
// u32 at 4, six u64 words at 8..56, and 40 payload bytes at 56.

import .serialize;

// ---- operation kinds (the order fuzz/host.c uses) --------------------------

let D_BITS = 0;
let D_BITS64 = 1;
let D_BOOL = 2;
let D_UINT8 = 3;
let D_UINT16 = 4;
let D_UINT32 = 5;
let D_UINT64 = 6;
let D_UINT128 = 7;
let D_INT = 8;
let D_INT64 = 9;
let D_INT128 = 10;
let D_INT_RELATIVE = 11;
let D_FIXED32 = 12;
let D_FIXED64 = 13;
let D_FIXED128 = 14;
let D_FLOAT = 15;
let D_DOUBLE = 16;
let D_COMPRESSED = 17;
let D_BYTES = 18;
let D_STRING = 19;
let D_WSTRING = 20;
let D_ALIGN = 21;
let D_OBJECT = 22;
let D_KINDS = 23;

let D_REC = 96;
let D_OPS = 24;
let D_DATA_OFF = 56;
let D_BUF = 4096;

struct DOp {
    kind: i64,
    a: u64,
    b: u64,
    c: u64,
    d: u64,
    e: u64,
    f: u64,
    len: i64,
    data: u8[40],
}

struct DProgram { ops: DOp[24], n: i64 }

struct DObj { x: i32 }

fn serialize<S>(s: S&, o: DObj&) -> bool {
    return serialize_int(s, o.x, 0, 1000);
}

struct DRng { state: u64 }

fn d_rng_next(r: DRng&) -> u64 {
    r.state = r.state * 6364136223846793005 + 1442695040888963407;
    return r.state;
}

fn d_below(r: DRng&, n: u64) -> u64 { return d_rng_next(r) % n; }

fn d_mask(bits: i64) -> u64 {
    if bits >= 64 { return 0xFFFFFFFFFFFFFFFF; }
    return ((1 as u64) << (bits as u64)) - 1;
}

fn d_zero_op() -> DOp {
    return DOp { kind: 0, a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, len: 0, data: [0; 40] };
}

fn d_clear_op(op: DOp&) {
    op.kind = 0;
    op.a = 0; op.b = 0; op.c = 0; op.d = 0; op.e = 0; op.f = 0;
    op.len = 0;
    for i in 40 { op.data[i] = 0; }
}

fn d_store32(buf: u8[:], off: i64, v: u32) {
    for i in 4 { buf[off + i] = ((v >> ((i * 8) as u32)) & 0xFF) as! u8; }
}

fn d_store64(buf: u8[:], off: i64, v: u64) {
    for i in 8 { buf[off + i] = ((v >> ((i * 8) as u64)) & 0xFF) as! u8; }
}

fn d_load32(buf: const u8[:], off: i64) -> u32 {
    var v: u32 = 0;
    for i in 4 { v = v | ((buf[off + i] as u32) << ((i * 8) as u32)); }
    return v;
}

fn d_load64(buf: const u8[:], off: i64) -> u64 {
    var v: u64 = 0;
    for i in 8 { v = v | ((buf[off + i] as u64) << ((i * 8) as u64)); }
    return v;
}

fn d_encode_op(buf: u8[:], idx: i64, op: DOp&) {
    let off = idx * D_REC;
    d_store32(buf, off, op.kind as! u32);
    d_store32(buf, off + 4, op.len as! u32);
    d_store64(buf, off + 8, op.a);
    d_store64(buf, off + 16, op.b);
    d_store64(buf, off + 24, op.c);
    d_store64(buf, off + 32, op.d);
    d_store64(buf, off + 40, op.e);
    d_store64(buf, off + 48, op.f);
    for i in 40 { buf[off + D_DATA_OFF + i] = op.data[i]; }
}

fn d_encode_program(prog: DProgram&, buf: u8[:]) {
    for i in D_OPS * D_REC { buf[i] = 0; }
    for i in prog.n { d_encode_op(buf, i, prog.ops[i]); }
}

// The record a successful read of `op` produces: only the fields that carry
// the decoded value (fuzz/host.c writes exactly these).
fn d_encode_expected_op(buf: u8[:], idx: i64, op: DOp&) {
    let off = idx * D_REC;
    for i in D_REC { buf[off + i] = 0; }
    d_store32(buf, off, op.kind as! u32);
    if op.kind == D_INT_RELATIVE {
        d_store32(buf, off + 4, 0);
        d_store64(buf, off + 8, op.b);
        return;
    }
    if op.kind == D_BYTES || op.kind == D_STRING || op.kind == D_WSTRING {
        d_store32(buf, off + 4, op.len as! u32);
        for i in op.len { buf[off + D_DATA_OFF + i] = op.data[i]; }
        return;
    }
    d_store32(buf, off + 4, 0);
    if op.kind == D_FIXED32 {
        d_store64(buf, off + 8, ((op.a as! u32) as! i32 as i64) as! u64);
    } else {
        d_store64(buf, off + 8, op.a);
    }
    if op.kind == D_UINT128 || op.kind == D_INT128 || op.kind == D_FIXED128 {
        d_store64(buf, off + 16, op.b);
    }
}

fn d_encode_expected(prog: DProgram&, buf: u8[:]) {
    for i in prog.n { d_encode_expected_op(buf, i, prog.ops[i]); }
}

// ---- the generator (fixed seed; no clock) ---------------------------------

fn d_gen_int(r: DRng&, op: DOp&) {
    let mode = d_below(r, 5);
    var mn: i32 = 0;
    var mx: i32 = 0;
    var v: i32 = 0;
    if mode == 0 {
        mn = (d_below(r, 201) as! i32) - 100;
        mx = mn;
        v = mn;
    } else if mode == 1 {
        mn = -2147483647 - 1;
        mx = 2147483647;
        v = d_rng_next(r) as! i32;
    } else if mode == 2 {
        mn = -2147483647 - 1;
        mx = (d_below(r, 4001) as! i32) - 2000;
        let span = (mx as i64) - (mn as i64);
        v = (mn as i64 + (d_below(r, span as u64 + 1) as i64)) as! i32;
    } else if mode == 3 {
        mx = 2147483647;
        mn = 2147483647 - (d_below(r, 4000) as! i32);
        let span = (mx as i64) - (mn as i64);
        v = (mn as i64 + (d_below(r, span as u64 + 1) as i64)) as! i32;
    } else {
        mn = (d_below(r, 2001) as! i32) - 1000;
        mx = mn + (d_below(r, 2000) as! i32);
        let span = (mx as i64) - (mn as i64);
        v = (mn as i64 + (d_below(r, span as u64 + 1) as i64)) as! i32;
    }
    op.a = (v as i64) as! u64;
    op.b = (mn as i64) as! u64;
    op.c = (mx as i64) as! u64;
}

fn d_gen_int64(r: DRng&, op: DOp&) {
    let mode = d_below(r, 4);
    var mn: i64 = 0;
    var mx: i64 = 0;
    var v: i64 = 0;
    if mode == 0 {
        mn = (d_below(r, 201) as! i64) - 100;
        mx = mn;
        v = mn;
    } else if mode == 1 {
        mn = -9223372036854775808;
        mx = 9223372036854775807;
        v = d_rng_next(r) as! i64;
    } else if mode == 2 {
        mn = -9223372036854775808;
        mx = (d_below(r, 8001) as! i64) - 4000;
        v = mn + (d_rng_next(r) % ((mx - mn) as u64 + 1)) as! i64;
    } else {
        mn = (d_below(r, 2000001) as! i64) - 1000000;
        mx = mn + (d_below(r, 1000000) as! i64);
        v = mn + (d_rng_next(r) % ((mx - mn) as u64 + 1)) as! i64;
    }
    op.a = v as! u64;
    op.b = mn as! u64;
    op.c = mx as! u64;
}

fn d_gen_int128(r: DRng&, op: DOp&) {
    if d_below(r, 4) == 0 {
        op.a = d_rng_next(r);
        op.b = d_rng_next(r);
        op.c = 0;
        op.d = 0x8000000000000000;
        op.e = 0xFFFFFFFFFFFFFFFF;
        op.f = 0x7FFFFFFFFFFFFFFF;
        return;
    }
    let mn = (d_below(r, 2001) as! i64) - 1000;
    let mx = mn + (d_below(r, 2000) as! i64);
    let v = mn + (d_rng_next(r) % ((mx - mn) as u64 + 1)) as! i64;
    let a = serialize_int128_from_int64(v);
    let lo = serialize_int128_from_int64(mn);
    let hi = serialize_int128_from_int64(mx);
    op.a = a.lo; op.b = a.hi;
    op.c = lo.lo; op.d = lo.hi;
    op.e = hi.lo; op.f = hi.hi;
}

fn d_shift128(v: i64, n: i64) -> Int128 {
    let base = serialize_int128_from_int64(v);
    var lo = base.lo;
    var hi = base.hi;
    for i in n {
        let carry = lo >> 63;
        lo = lo << 1;
        hi = (hi << 1) | carry;
    }
    return Int128 { lo: lo, hi: hi };
}

fn d_gen_op(r: DRng&, op: DOp&, first: bool) {
    d_clear_op(op);
    op.kind = if first { D_INT } else { (d_below(r, D_KINDS as u64)) as! i64 };
    let k = op.kind;
    if k == D_BITS {
        let bits = (d_below(r, 32) + 1) as! i64;
        op.a = d_rng_next(r) & d_mask(bits);
        op.b = bits as! u64;
    } else if k == D_BITS64 {
        let bits = (d_below(r, 64) + 1) as! i64;
        op.a = d_rng_next(r) & d_mask(bits);
        op.b = bits as! u64;
    } else if k == D_BOOL {
        op.a = d_below(r, 2);
    } else if k == D_UINT8 {
        op.a = d_below(r, 256);
    } else if k == D_UINT16 {
        op.a = d_below(r, 65536);
    } else if k == D_UINT32 {
        op.a = d_rng_next(r) & 0xFFFFFFFF;
    } else if k == D_UINT64 {
        op.a = d_rng_next(r);
    } else if k == D_UINT128 {
        op.a = d_rng_next(r);
        op.b = d_rng_next(r);
    } else if k == D_INT {
        d_gen_int(r, op);
    } else if k == D_INT64 {
        d_gen_int64(r, op);
    } else if k == D_INT128 {
        d_gen_int128(r, op);
    } else if k == D_INT_RELATIVE {
        var previous = (d_below(r, 2147483646) as! i32);
        if d_below(r, 8) == 0 { previous = 0; }
        if d_below(r, 8) == 0 { previous = 2147483645; }
        let room = 2147483647 - previous;
        let cap = if room < 100000 { room } else { 100000 };
        let step = 1 + (d_below(r, cap as u64) as! i32);
        op.a = (previous as i64) as! u64;
        op.b = ((previous + step) as i64) as! u64;
    } else if k == D_FIXED32 {
        let total = if d_below(r, 3) == 0 { 8 } else if d_below(r, 2) == 0 { 16 } else { 32 };
        let maxfrac = if total > 9 { 8 } else { total - 1 };
        let frac = (d_below(r, (maxfrac + 1) as u64)) as! i64;
        let integer = total - frac;
        let mn = ((d_below(r, 2001) as! i32) - 1000);
        let mx = mn + (d_below(r, 1000) as! i32);
        let span = (mx as i64) - (mn as i64);
        let v = (mn as i64 + (d_below(r, span as u64 + 1) as i64)) as! i32;
        op.a = ((v as! u64) << (frac as u64)) & 0xFFFFFFFF;
        op.b = integer as! u64;
        op.c = frac as! u64;
        op.d = (mn as i64) as! u64;
        op.e = (mx as i64) as! u64;
    } else if k == D_FIXED64 {
        let frac = (d_below(r, 17)) as! i64;
        let integer = 64 - frac;
        let mn = ((d_below(r, 2001) as! i64) - 1000);
        let mx = mn + (d_below(r, 1000) as! i64);
        let span = mx - mn;
        let v = mn + (d_below(r, span as u64 + 1) as! i64);
        op.a = (v as! u64) << (frac as u64);
        op.b = integer as! u64;
        op.c = frac as! u64;
        op.d = mn as! u64;
        op.e = mx as! u64;
    } else if k == D_FIXED128 {
        let frac = (d_below(r, 101)) as! i64;
        let integer = 128 - frac;
        let mn = ((d_below(r, 2001) as! i64) - 1000);
        let mx = mn + (d_below(r, 1000) as! i64);
        let span = mx - mn;
        let whole = mn + (d_below(r, span as u64 + 1) as! i64);
        let v = d_shift128(whole, frac);
        op.a = v.lo; op.b = v.hi;
        op.c = integer as! u64;
        op.d = frac as! u64;
        op.e = mn as! u64;
        op.f = mx as! u64;
    } else if k == D_FLOAT {
        let choice = d_below(r, 8);
        if choice == 0 { op.a = 0x7FC00001; }        // quiet NaN, payload
        else if choice == 1 { op.a = 0x7F800001; }   // signalling NaN
        else if choice == 2 { op.a = 0x7F800000; }   // +inf
        else if choice == 3 { op.a = 0xFF800000; }   // -inf
        else if choice == 4 { op.a = 0x80000000; }   // -0
        else if choice == 5 { op.a = 0x00000001; }   // subnormal
        else { op.a = d_rng_next(r) & 0xFFFFFFFF; }
    } else if k == D_DOUBLE {
        let choice = d_below(r, 8);
        if choice == 0 { op.a = 0x7FF8000000000001; }
        else if choice == 1 { op.a = 0x7FF0000000000001; }
        else if choice == 2 { op.a = 0x7FF0000000000000; }
        else if choice == 3 { op.a = 0xFFF0000000000000; }
        else if choice == 4 { op.a = 0x8000000000000000; }
        else if choice == 5 { op.a = 0x0000000000000001; }
        else { op.a = d_rng_next(r); }
    } else if k == D_COMPRESSED {
        let mn: f32 = (d_below(r, 100) as! f32) - 50.0;
        let mx: f32 = mn + (1.0 + (d_below(r, 100) as! f32));
        let res: f32 = 0.01 + (d_below(r, 100) as! f32) * 0.01;
        op.a = serialize_f32_bits(mn);
        op.b = serialize_f32_bits(mn);
        op.c = serialize_f32_bits(mx);
        op.d = serialize_f32_bits(res);
    } else if k == D_BYTES {
        op.len = (d_below(r, 16) + 1) as! i64;
        for i in op.len { op.data[i] = d_rng_next(r) as! u8; }
    } else if k == D_STRING {
        op.len = (d_below(r, 12) + 1) as! i64;
        for i in op.len { op.data[i] = ('a' + (d_below(r, 26) as! u8)); }
        op.d = 16;
    } else if k == D_WSTRING {
        op.len = (d_below(r, 8) + 1) as! i64;
        for i in op.len { op.data[i] = ('A' + (d_below(r, 26) as! u8)); }
        op.d = 16;
    } else if k == D_ALIGN {
    } else if k == D_OBJECT {
        op.a = d_below(r, 1001);
        op.b = 0;
        op.c = 1000;
    }
}

fn d_gen_program(r: DRng&, prog: DProgram&) {
    prog.n = (d_below(r, 24) + 1) as! i64;
    for i in prog.n { d_gen_op(r, prog.ops[i], i == 0); }
}

// ---- the Goose side --------------------------------------------------------

fn d_goose_write(prog: DProgram&, buf: u8[:]) -> i64 {
    var w = serialize_write_stream_init(buf);
    for i in prog.n {
        let op = prog.ops[i];
        let k = op.kind;
        if k == D_BITS {
            serialize_bits(w, op.a as! u32, op.b as! i64);
        } else if k == D_BITS64 {
            serialize_bits64(w, op.a, op.b as! i64);
        } else if k == D_BOOL {
            serialize_bool(w, op.a != 0);
        } else if k == D_UINT8 {
            serialize_uint8(w, op.a as! u8);
        } else if k == D_UINT16 {
            serialize_uint16(w, op.a as! u16);
        } else if k == D_UINT32 {
            serialize_uint32(w, op.a as! u32);
        } else if k == D_UINT64 {
            serialize_uint64(w, op.a);
        } else if k == D_UINT128 {
            serialize_uint128(w, serialize_uint128_make(op.b, op.a));
        } else if k == D_INT {
            serialize_int(w, op.a as! i32, op.b as! i32, op.c as! i32);
        } else if k == D_INT64 {
            serialize_int64(w, op.a as! i64, op.b as! i64, op.c as! i64);
        } else if k == D_INT128 {
            serialize_int128(w, serialize_int128_make(op.b, op.a),
                             serialize_int128_make(op.d, op.c), serialize_int128_make(op.f, op.e));
        } else if k == D_INT_RELATIVE {
            serialize_int_relative(w, op.a as! i32, op.b as! i32);
        } else if k == D_FIXED32 {
            serialize_fixed32(w, op.a as! i32, op.b as! i64, op.c as! i64, op.d as! i32, op.e as! i32);
        } else if k == D_FIXED64 {
            serialize_fixed64(w, op.a as! i64, op.b as! i64, op.c as! i64, op.d as! i64, op.e as! i64);
        } else if k == D_FIXED128 {
            serialize_fixed128(w, serialize_int128_make(op.b, op.a), op.c as! i64, op.d as! i64,
                               op.e as! i64, op.f as! i64);
        } else if k == D_FLOAT {
            serialize_float(w, serialize_f32_from_bits(op.a as! u32));
        } else if k == D_DOUBLE {
            serialize_double(w, serialize_f64_from_bits(op.a));
        } else if k == D_COMPRESSED {
            serialize_compressed_float(w, serialize_f32_from_bits(op.a as! u32),
                serialize_f32_from_bits(op.b as! u32), serialize_f32_from_bits(op.c as! u32),
                serialize_f32_from_bits(op.d as! u32));
        } else if k == D_BYTES {
            serialize_bytes(w, op.data[0..op.len]);
        } else if k == D_STRING {
            serialize_string(w, op.data[0..op.len], op.d as! i64);
        } else if k == D_WSTRING {
            serialize_wstring(w, op.data[0..op.len], op.d as! i64);
        } else if k == D_ALIGN {
            serialize_align(w);
        } else if k == D_OBJECT {
            var obj = DObj { x: op.a as! i32 };
            serialize_object(w, obj);
        }
    }
    serialize_flush(w);
    return serialize_bytes_processed(w);
}

fn d_goose_read(prog: DProgram&, data: const u8[:], bytes: i64, out: u8[:]) -> i64 {
    var r = serialize_read_stream_init(data, bytes);
    var steps: i64 = 0;
    for i in prog.n {
        let op = prog.ops[i];
        let off = steps * D_REC;
        for j in D_REC { out[off + j] = 0; }
        d_store32(out, off, op.kind as! u32);
        var ok = false;
        let k = op.kind;
        if k == D_BITS {
            var v: u32 = 0;
            ok = serialize_bits(r, v, op.b as! i64);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_BITS64 {
            var v: u64 = 0;
            ok = serialize_bits64(r, v, op.b as! i64);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_BOOL {
            var v = false;
            ok = serialize_bool(r, v);
            if ok { d_store64(out, off + 8, if v { 1 } else { 0 }); }
        } else if k == D_UINT8 {
            var v: u8 = 0;
            ok = serialize_uint8(r, v);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_UINT16 {
            var v: u16 = 0;
            ok = serialize_uint16(r, v);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_UINT32 {
            var v: u32 = 0;
            ok = serialize_uint32(r, v);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_UINT64 {
            var v: u64 = 0;
            ok = serialize_uint64(r, v);
            if ok { d_store64(out, off + 8, v); }
        } else if k == D_UINT128 {
            var v = Uint128 { lo: 0, hi: 0 };
            ok = serialize_uint128(r, v);
            if ok { d_store64(out, off + 8, v.lo); d_store64(out, off + 16, v.hi); }
        } else if k == D_INT {
            var v: i32 = 0;
            ok = serialize_int(r, v, op.b as! i32, op.c as! i32);
            if ok { d_store64(out, off + 8, (v as i64) as! u64); }
        } else if k == D_INT64 {
            var v: i64 = 0;
            ok = serialize_int64(r, v, op.b as! i64, op.c as! i64);
            if ok { d_store64(out, off + 8, v as! u64); }
        } else if k == D_INT128 {
            var v = Int128 { lo: 0, hi: 0 };
            ok = serialize_int128(r, v, serialize_int128_make(op.d, op.c), serialize_int128_make(op.f, op.e));
            if ok { d_store64(out, off + 8, v.lo); d_store64(out, off + 16, v.hi); }
        } else if k == D_INT_RELATIVE {
            var v: i32 = 0;
            ok = serialize_int_relative(r, op.a as! i32, v);
            if ok { d_store64(out, off + 8, (v as i64) as! u64); }
        } else if k == D_FIXED32 {
            var v: i32 = 0;
            ok = serialize_fixed32(r, v, op.b as! i64, op.c as! i64, op.d as! i32, op.e as! i32);
            if ok { d_store64(out, off + 8, (v as i64) as! u64); }
        } else if k == D_FIXED64 {
            var v: i64 = 0;
            ok = serialize_fixed64(r, v, op.b as! i64, op.c as! i64, op.d as! i64, op.e as! i64);
            if ok { d_store64(out, off + 8, v as! u64); }
        } else if k == D_FIXED128 {
            var v = Int128 { lo: 0, hi: 0 };
            ok = serialize_fixed128(r, v, op.c as! i64, op.d as! i64, op.e as! i64, op.f as! i64);
            if ok { d_store64(out, off + 8, v.lo); d_store64(out, off + 16, v.hi); }
        } else if k == D_FLOAT {
            var v: f32 = 0.0;
            ok = serialize_float(r, v);
            if ok { d_store64(out, off + 8, serialize_f32_bits(v)); }
        } else if k == D_DOUBLE {
            var v: f64 = 0.0;
            ok = serialize_double(r, v);
            if ok { d_store64(out, off + 8, serialize_f64_bits(v)); }
        } else if k == D_COMPRESSED {
            var v: f32 = 0.0;
            ok = serialize_compressed_float(r, v, serialize_f32_from_bits(op.b as! u32),
                serialize_f32_from_bits(op.c as! u32), serialize_f32_from_bits(op.d as! u32));
            if ok { d_store64(out, off + 8, serialize_f32_bits(v)); }
        } else if k == D_BYTES {
            var dst: u8[40] = [0; 40];
            ok = serialize_bytes(r, dst[0..op.len]);
            if ok {
                d_store32(out, off + 4, op.len as! u32);
                for j in op.len { out[off + D_DATA_OFF + j] = dst[j]; }
            }
        } else if k == D_STRING {
            var dst: u8[>..] = [];
            ok = serialize_string(r, dst, op.d as! i64);
            if ok {
                d_store32(out, off + 4, dst.len as! u32);
                for j in dst.len { out[off + D_DATA_OFF + j] = dst[j]; }
            }
        } else if k == D_WSTRING {
            var dst: u8[>..] = [];
            ok = serialize_wstring(r, dst, op.d as! i64);
            if ok {
                d_store32(out, off + 4, dst.len as! u32);
                for j in dst.len { out[off + D_DATA_OFF + j] = dst[j]; }
            }
        } else if k == D_ALIGN {
            ok = serialize_align(r);
        } else if k == D_OBJECT {
            var obj = DObj { x: 0 };
            ok = serialize_object(r, obj);
            if ok { d_store64(out, off + 8, (obj.x as i64) as! u64); }
        }
        if !ok { break; }
        steps += 1;
    }
    return steps;
}

// ---- bytes, mutation, reporting -------------------------------------------

fn d_bytes_equal(a: const u8[:], b: const u8[:], n: i64) -> bool {
    for i in n { if a[i] != b[i] { return false; } }
    return true;
}

fn d_first_diff(a: const u8[:], b: const u8[:], n: i64) -> i64 {
    for i in n { if a[i] != b[i] { return i; } }
    return n;
}

fn d_dump_prog(prog: DProgram&) {
    print("program: ", prog.n, " ops");
    for i in prog.n {
        let op = prog.ops[i];
        print("  op ", i, " kind=", op.kind, " a=", op.a, " b=", op.b, " c=", op.c,
              " d=", op.d, " e=", op.e, " f=", op.f, " len=", op.len);
        if op.len > 0 {
            var line: u8[>..] = [];
            for j in op.len { format(line, op.data[j], " "); }
            print("    data: ", line);
        }
    }
}

fn d_dump_bytes(name: const u8[:], buf: const u8[:], n: i64) {
    var line: u8[>..] = [];
    for i in n { format(line, buf[i], " "); }
    print(name, " (", n, "): ", line);
}

fn d_mutate(r: DRng&, src: const u8[:], n0: i64, dst: u8[:]) -> i64 {
    var n = n0;
    for i in D_BUF { dst[i] = 0; }
    for i in n { dst[i] = src[i]; }
    let count = d_below(r, 4) + 1;
    for m in count {
        let t = d_below(r, 3);
        if t == 0 && n > 0 {
            let idx = d_below(r, n as u64) as! i64;
            let bit = (d_below(r, 8) as! u8);
            dst[idx] = dst[idx] ^ ((1 as u8) << bit);
        } else if t == 1 {
            n = d_below(r, (n + 1) as u64) as! i64;
        } else {
            let extra = d_below(r, 8) + 1;
            for e in extra {
                if n < 4000 {
                    dst[n] = d_rng_next(r) as! u8;
                    n += 1;
                }
            }
        }
    }
    return n;
}

// ---- extern: the serialize.c side (fuzz/host.c) ---------------------------

extern fn c_write(prog: const u8[:], out: u8[:]) -> i64;
extern fn c_read(out: u8[:], prog: const u8[:], data: const u8[:], bytes: i64) -> i64;
extern fn c_negative_control();

fn d_check(cond: bool, what: const u8[:]) {
    if !cond {
        print("FAILED: ", what);
        abort("differential: mismatch");
    }
}

fn TestDifferentialAgainstSerializeC(negative: bool) {
    var r = DRng { state: 0x5EED1234C0FFEE01 };
    var prog = DProgram { ops: [d_zero_op(); 24], n: 0 };
    var prog_buf: u8[D_BUF] = [0; D_BUF];
    var cbuf: u8[D_BUF] = [0; D_BUF];
    var gbuf: u8[D_BUF] = [0; D_BUF];
    var expected: u8[D_BUF] = [0; D_BUF];
    var rbuf_c: u8[D_BUF] = [0; D_BUF];
    var rbuf_g: u8[D_BUF] = [0; D_BUF];
    var data: u8[D_BUF] = [0; D_BUF];
    var mutants: i64 = 0;
    let total = 2000;
    for p in total {
        d_gen_program(r, prog);
        d_encode_program(prog, prog_buf);
        let plen = prog.n * D_REC;

        let clen = c_write(prog_buf[0..plen], cbuf);
        let glen = d_goose_write(prog, gbuf);
        if clen != glen || !d_bytes_equal(cbuf, gbuf, glen) {
            print("program ", p, " write mismatch: c=", clen, " goose=", glen,
                  " first diff=", d_first_diff(cbuf, gbuf, if clen < glen { clen } else { glen }));
            d_dump_prog(prog);
            d_dump_bytes("c bytes", cbuf, clen);
            d_dump_bytes("goose bytes", gbuf, glen);
            abort("differential: write bytes differ");
        }

        // Each reader reads both writers' bytes (they are equal, so one read).
        let csteps = c_read(rbuf_c, prog_buf[0..plen], cbuf, clen);
        let gsteps = d_goose_read(prog, cbuf, clen, rbuf_g);
        if csteps != prog.n || gsteps != prog.n {
            print("program ", p, " clean read: c=", csteps, " goose=", gsteps, " ops=", prog.n);
            d_dump_prog(prog);
            d_dump_bytes("bytes", cbuf, clen);
            abort("differential: clean read refused");
        }
        d_encode_expected(prog, expected);
        if !d_bytes_equal(rbuf_c, expected, prog.n * D_REC)
            || !d_bytes_equal(rbuf_g, expected, prog.n * D_REC) {
            let dc = d_first_diff(rbuf_c, expected, prog.n * D_REC);
            let dg = d_first_diff(rbuf_g, expected, prog.n * D_REC);
            print("program ", p, " decoded value mismatch: c diff byte ", dc, " record ", dc / D_REC,
                  " goose diff byte ", dg, " record ", dg / D_REC);
            d_dump_prog(prog);
            d_dump_bytes("c decoded", rbuf_c, prog.n * D_REC);
            d_dump_bytes("goose decoded", rbuf_g, prog.n * D_REC);
            abort("differential: wrong decoded value");
        }

        if d_below(r, 4) == 0 {
            mutants += 1;
            let mlen = d_mutate(r, cbuf, clen, data);
            let mc = c_read(rbuf_c, prog_buf[0..plen], data, mlen);
            let mg = d_goose_read(prog, data, mlen, rbuf_g);
            if mc != mg {
                print("program ", p, " mutant: c accepted ", mc, " goose accepted ", mg);
                d_dump_prog(prog);
                d_dump_bytes("original", cbuf, clen);
                d_dump_bytes("mutant", data, mlen);
                abort("differential: mutant accept/refuse differs");
            }
            let common = if mc < 0 { 0 } else { mc };
            for j in common * D_REC {
                if rbuf_c[j] != rbuf_g[j] {
                    print("program ", p, " mutant: first differing step ", j / D_REC,
                          " byte ", j);
                    d_dump_prog(prog);
                    d_dump_bytes("original", cbuf, clen);
                    d_dump_bytes("mutant", data, mlen);
                    d_dump_bytes("c decoded", rbuf_c, common * D_REC);
                    d_dump_bytes("goose decoded", rbuf_g, common * D_REC);
                    abort("differential: mutant decoded value differs");
                }
            }
        }
    }
    print("differential: ", total, " programs, ", mutants, " mutants");
    if negative { print("differential: negative control mode"); }
}

fn d_enable_negative() { c_negative_control(); }
