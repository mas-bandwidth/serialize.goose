// serialize_fixed.goose -- Q-format fixed point (STANDARD.md, fixed;
// DESIGN.md (a), (c)). integer_bits + fraction_bits equals the storage width,
// min and max are whole units that fit the Q format, min <= max. A bad
// declaration, or a value outside [min, max], aborts on a write or a measure (the C++ reference makes it a
// compile error) and is refused as VALUE_OUT_OF_RANGE on a read, before any
// bit moves (U16): never wrong data.

import .serialize_stream;
import .serialize_int128;

// ---- 128-bit unsigned arithmetic over the Int128 lanes ---------------------
// STANDARD.md, fixed: the raw range lives in the unsigned domain of the
// storage width, exactly as int128's bounds do.

fn serialize_fixed_u128_from_i64(value: i64) -> Int128 {
    return serialize_int128_from_int64(value);
}

fn serialize_fixed_u128_sub(a: Int128, b: Int128) -> Int128 {
    let r = serialize_u128_sub(Uint128 { lo: a.lo, hi: a.hi }, Uint128 { lo: b.lo, hi: b.hi });
    return Int128 { lo: r.lo, hi: r.hi };
}

fn serialize_fixed_u128_add(a: Int128, b: Int128) -> Int128 {
    let r = serialize_u128_add(Uint128 { lo: a.lo, hi: a.hi }, Uint128 { lo: b.lo, hi: b.hi });
    return Int128 { lo: r.lo, hi: r.hi };
}

fn serialize_fixed_u128_compare(a: Int128, b: Int128) -> i64 {
    // These lanes hold unsigned offsets and spans, even for signed Q formats.
    let ua = Uint128 { lo: a.lo, hi: a.hi };
    let ub = Uint128 { lo: b.lo, hi: b.hi };
    return serialize_u128_compare(ua, ub);
}

fn serialize_fixed_u128_bit_length(value: Int128) -> i64 {
    return serialize_u128_bit_length(Uint128 { lo: value.lo, hi: value.hi });
}

// min << fraction_bits in the 128-bit domain (serialize.c serialize_raw_bound).
fn serialize_fixed_raw_bound(whole: i64, fraction_bits: i64) -> Int128 {
    let u = serialize_fixed_u128_from_i64(whole);
    let shifted = serialize_u128_shl(Uint128 { lo: u.lo, hi: u.hi }, fraction_bits);
    return Int128 { lo: shifted.lo, hi: shifted.hi };
}

fn serialize_fixed_u128_group32(value: Int128, group: i64) -> u32 {
    return serialize_u128_group32(Uint128 { lo: value.lo, hi: value.hi }, group);
}

fn serialize_fixed_u128_set_group32(value: Int128&, group: i64, g: u32) {
    var u = Uint128 { lo: value.lo, hi: value.hi };
    serialize_u128_set_group32(u, group, g);
    value = Int128 { lo: u.lo, hi: u.hi };
}

// STANDARD.md, fixed: raw_value - raw_min in `bits` bits, split into 32-bit
// groups from least significant upward exactly as serialize_bits splits wide
// values.
fn serialize_fixed_write_bits(s: WriteStream&, value: Int128, bits: i64) -> bool {
    var written: i64 = 0;
    var group: i64 = 0;
    while written < bits {
        var chunk = bits - written;
        if chunk > 32 { chunk = 32; }
        guard serialize_bits(s, serialize_fixed_u128_group32(value, group), chunk) else { return false; }
        written += chunk;
        group += 1;
    }
    return true;
}

fn serialize_fixed_read_bits(s: ReadStream&, value: Int128&, bits: i64) -> bool {
    var read: i64 = 0;
    var group: i64 = 0;
    value = Int128 { lo: 0, hi: 0 };
    while read < bits {
        var chunk = bits - read;
        if chunk > 32 { chunk = 32; }
        var g: u32 = 0;
        guard serialize_bits(s, g, chunk) else { return false; }
        serialize_fixed_u128_set_group32(value, group, g);
        read += chunk;
        group += 1;
    }
    return true;
}

// The Q format: fixed32 carries the 8-, 16- and 32-bit storage widths
// (STANDARD.md, fixed), fixed64 and fixed128 their own width.
fn serialize_fixed_format_ok(integer_bits: i64, fraction_bits: i64, width: i64) -> bool {
    if integer_bits < 1 || fraction_bits < 0 { return false; }
    let total = integer_bits + fraction_bits;
    if width == 32 { return total == 8 || total == 16 || total == 32; }
    return total == width;
}

// The whole units a signed Q format holds: [-2^(integer_bits-1),
// 2^(integer_bits-1) - 1], every int64 from 64 integer bits up (the C++
// reference's min_representable_units and max_representable_units).
fn serialize_fixed_bounds_fit(integer_bits: i64, min: i64, max: i64) -> bool {
    if integer_bits >= 64 { return true; }
    let half: i64 = 1 << (integer_bits - 1);
    return min >= -half && max <= half - 1;
}

fn serialize_fixed_declaration_ok(integer_bits: i64, fraction_bits: i64, width: i64, min: i64, max: i64) -> bool {
    return serialize_fixed_format_ok(integer_bits, fraction_bits, width) && min <= max
        && serialize_fixed_bounds_fit(integer_bits, min, max);
}

// A write's or a measure's declaration: misuse aborts, naming the rule.
fn serialize_fixed_check_declaration(integer_bits: i64, fraction_bits: i64, width: i64, min: i64, max: i64) {
    if !serialize_fixed_format_ok(integer_bits, fraction_bits, width) {
        abort("serialize: integer_bits + fraction_bits must equal the storage width");
    }
    if min > max { abort("serialize: min must not be greater than max"); }
    if !serialize_fixed_bounds_fit(integer_bits, min, max) { abort("serialize: fixed min and max must fit the Q format"); }
}

// A write's or a measure's value check (U6, U9): raw_value in
// [raw_min, raw_max], judged in the unsigned domain as the offset against the
// span. Returns the width.
fn serialize_fixed_check_value(raw_value: Int128, raw_min: Int128, raw_max: Int128) -> i64 {
    let span = serialize_fixed_u128_sub(raw_max, raw_min);
    let bits = serialize_fixed_u128_bit_length(span);
    if bits == 0 {
        guard serialize_fixed_u128_compare(raw_value, raw_min) == 0
            else { abort("serialize: value must be in [min, max]"); }
        return 0;
    }
    if serialize_fixed_u128_compare(serialize_fixed_u128_sub(raw_value, raw_min), span) > 0 {
        abort("serialize: value must be in [min, max]");
    }
    return bits;
}

fn serialize_fixed_write_core(s: WriteStream&, raw_value: Int128, raw_min: Int128, raw_max: Int128) -> bool {
    let bits = serialize_fixed_check_value(raw_value, raw_min, raw_max);
    if bits == 0 { return true; }
    serialize_write_check(s, bits);
    return serialize_fixed_write_bits(s, serialize_fixed_u128_sub(raw_value, raw_min), bits);
}

fn serialize_fixed_read_core(s: ReadStream&, raw_value: Int128&, raw_min: Int128, raw_max: Int128) -> bool {
    guard s.error == SERIALIZE_ERROR_NONE else { return false; } // the latch first, zero-bit reads included
    let span = serialize_fixed_u128_sub(raw_max, raw_min);
    let bits = serialize_fixed_u128_bit_length(span);
    if bits == 0 {
        raw_value = raw_min;
        return true;
    }
    guard serialize_read_check(s, bits) else { return false; }
    let start = s.bits_read;
    var offset = Int128 { lo: 0, hi: 0 };
    guard serialize_fixed_read_bits(s, offset, bits) else { return false; }
    if serialize_fixed_u128_compare(offset, span) > 0 {
        s.bits_read = start;
        return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    }
    raw_value = serialize_fixed_u128_add(raw_min, offset);
    return true;
}

fn serialize_fixed_measure_core(s: MeasureStream&, raw_value: Int128, raw_min: Int128, raw_max: Int128) -> bool {
    return serialize_measure_add(s, serialize_fixed_check_value(raw_value, raw_min, raw_max));
}

// ---- fixed32 ---------------------------------------------------------------

fn serialize_fixed32(s: WriteStream&, value: i32, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 32, min, max);
    return serialize_fixed_write_core(s, serialize_fixed_u128_from_i64(value), serialize_fixed_raw_bound(min, fraction_bits),
                            serialize_fixed_raw_bound(max, fraction_bits));
}
fn serialize_fixed32(s: ReadStream&, value: i32&, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool {
    guard serialize_fixed_declaration_ok(integer_bits, fraction_bits, 32, min, max) else {
        return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    }
    var raw = Int128 { lo: 0, hi: 0 };
    guard serialize_fixed_read_core(s, raw, serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits)) else { return false; }
    value = raw.lo as! i32;
    return true;
}
fn serialize_fixed32(s: MeasureStream&, value: i32, integer_bits: i64, fraction_bits: i64, min: i32, max: i32) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 32, min, max);
    return serialize_fixed_measure_core(s, serialize_fixed_u128_from_i64(value), serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits));
}

// ---- fixed64 ---------------------------------------------------------------

fn serialize_fixed64(s: WriteStream&, value: i64, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 64, min, max);
    return serialize_fixed_write_core(s, serialize_fixed_u128_from_i64(value), serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits));
}
fn serialize_fixed64(s: ReadStream&, value: i64&, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    guard serialize_fixed_declaration_ok(integer_bits, fraction_bits, 64, min, max) else {
        return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    }
    var raw = Int128 { lo: 0, hi: 0 };
    guard serialize_fixed_read_core(s, raw, serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits)) else { return false; }
    value = raw.lo as! i64;
    return true;
}
fn serialize_fixed64(s: MeasureStream&, value: i64, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 64, min, max);
    return serialize_fixed_measure_core(s, serialize_fixed_u128_from_i64(value), serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits));
}

// ---- fixed128 --------------------------------------------------------------
// The value is a raw 128-bit two's-complement integer; min and max are i64
// whole units, scaled to their 128-bit raw bounds (STANDARD.md, fixed).

fn serialize_fixed128(s: WriteStream&, value: Int128, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 128, min, max);
    return serialize_fixed_write_core(s, value, serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits));
}
fn serialize_fixed128(s: ReadStream&, value: Int128&, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    guard serialize_fixed_declaration_ok(integer_bits, fraction_bits, 128, min, max) else {
        return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE);
    }
    var raw = Int128 { lo: 0, hi: 0 };
    guard serialize_fixed_read_core(s, raw, serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits)) else { return false; }
    value = raw;
    return true;
}
fn serialize_fixed128(s: MeasureStream&, value: Int128, integer_bits: i64, fraction_bits: i64, min: i64, max: i64) -> bool {
    serialize_fixed_check_declaration(integer_bits, fraction_bits, 128, min, max);
    return serialize_fixed_measure_core(s, value, serialize_fixed_raw_bound(min, fraction_bits), serialize_fixed_raw_bound(max, fraction_bits));
}
