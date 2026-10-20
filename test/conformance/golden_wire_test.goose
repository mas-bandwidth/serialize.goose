// test/conformance -- TestGoldenWireFormat (STANDARD.md, Worked Example, The
// whole message; DESIGN.md (g) THE RUNNER). The golden message bytes are
// serialize.c's, copied as literals from the corpus record in
// conformance/message.txt:94 (the same bytes STANDARD.md prints at The whole
// message). The test reads the message field by field, re-writes it byte for
// byte, and flips every one of the 891 consumed bits: each flipped stream must
// either be refused or decode a different message.

import std;
import .serialize;
import .conformance_test;

fn golden_steps(steps: Step[64]&) -> i64 {
    // The 27 step spellings of message.txt's message-golden-whole, in order.
    assert(conf_step_from_words(steps[0], "bits 4"));
    assert(conf_step_from_words(steps[1], "bits 11"));
    assert(conf_step_from_words(steps[2], "bits 24"));
    assert(conf_step_from_words(steps[3], "bits 32"));
    assert(conf_step_from_words(steps[4], "int -100 100"));
    assert(conf_step_from_words(steps[5], "int -2147483648 2147483647"));
    assert(conf_step_from_words(steps[6], "bool"));
    assert(conf_step_from_words(steps[7], "float"));
    assert(conf_step_from_words(steps[8], "compressed_float 0 10 0.01"));
    assert(conf_step_from_words(steps[9], "double"));
    assert(conf_step_from_words(steps[10], "bits 8"));
    assert(conf_step_from_words(steps[11], "bits 16"));
    assert(conf_step_from_words(steps[12], "bits 32"));
    assert(conf_step_from_words(steps[13], "bits 64"));
    assert(conf_step_from_words(steps[14], "int_relative 100"));
    assert(conf_step_from_words(steps[15], "int_relative 100"));
    assert(conf_step_from_words(steps[16], "align"));
    assert(conf_step_from_words(steps[17], "bytes 7"));
    assert(conf_step_from_words(steps[18], "string 16"));
    assert(conf_step_from_words(steps[19], "wstring 8"));
    assert(conf_step_from_words(steps[20], "align"));
    assert(conf_step_from_words(steps[21], "fixed 8 8 -100 100"));
    assert(conf_step_from_words(steps[22], "fixed 16 16 -2000 2000"));
    assert(conf_step_from_words(steps[23], "fixed 48 16 -100000 100000"));
    assert(conf_step_from_words(steps[24], "fixed 16 16 0 30000"));
    assert(conf_step_from_words(steps[25], "align"));
    assert(conf_step_from_words(steps[26], "fixed 112 16 -144115188075855872 144115188075855872"));
    assert(conf_step_from_words(steps[27], "fixed 64 64 -9223372036854775808 9223372036854775807"));
    return 28;
}

// serialize.c test/vectors.h SEQUENCE_GOLDEN / the record at
// conformance/message.txt:94. 112 bytes, 891 bits consumed.
fn golden_wire() -> u8[112] {
    var w: u8[112] = [
        0x5D, 0xDA, 0xF7, 0xE6, 0xD5, 0x77, 0xDF, 0x56,
        0xEF, 0x9F, 0x75, 0x19, 0x52, 0xBC, 0xDA, 0x0F,
        0x49, 0x40, 0xF4, 0x55, 0x55, 0x55, 0x55, 0x55,
        0x55, 0x55, 0xFF, 0xFC, 0xD1, 0x48, 0xE0, 0x59,
        0xD1, 0x48, 0xC0, 0x7B, 0xF3, 0x6A, 0xE2, 0x59,
        0xD1, 0x48, 0x84, 0xB7, 0x06, 0xDE, 0xAD, 0xBE,
        0xEF, 0xCA, 0xFE, 0x01, 0x06, 0x67, 0x6F, 0x6C,
        0x64, 0x65, 0x6E, 0xE3, 0x21, 0x00, 0x00, 0xC0,
        0x21, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00,
        0xC0, 0x60, 0x00, 0x80, 0xA2, 0x7C, 0xFC, 0xEC,
        0x26, 0xCB, 0xFF, 0xFF, 0x4B, 0x1D, 0x1F, 0xEF,
        0xD2, 0x1A, 0x1F, 0x01, 0xE9, 0xFF, 0xFF, 0x09,
        0x19, 0x2A, 0x3B, 0x4C, 0x5D, 0x6E, 0x7F, 0x78,
        0x6F, 0x5E, 0x4D, 0x3C, 0x2B, 0x1A, 0x09, 0x04,
    ];
    return w;
}

fn golden_read(wire: const u8[:], steps: Step[64]&) -> bool {
    var padded: u8[256] = [0; 256];
    for i in wire.len { padded[i] = wire[i]; }
    var r = serialize_read_stream_init(padded, wire.len);
    var failed: i64 = -1;
    return conf_run_steps(r, steps, 0, 28, false, false, failed);
}

fn golden_same(a: Step[64], b: Step[64]) -> bool {
    for i in 28 {
        if a[i].kind != b[i].kind { return false; }
        if conf_is_pattern(a[i].kind) || conf_is_number(a[i].kind) {
            if !conf_same(a[i].got, b[i].got) { return false; }
        } else if a[i].kind == K_BOOL {
            if a[i].got_bool != b[i].got_bool { return false; }
        } else if a[i].kind == K_BYTES || a[i].kind == K_STRING || a[i].kind == K_WSTRING {
            if a[i].got_len != b[i].got_len { return false; }
            for k in a[i].got_len {
                if a[i].got_buf[k] != b[i].got_buf[k] { return false; }
            }
        }
    }
    return true;
}

// goose: --debug
fn TestGoldenWireFormat() {
    let wire = golden_wire();
    var base: Step[64] = [conf_empty_step(); 64];
    assert(golden_steps(base) == 28);
    assert(golden_read(wire[0..112], base));

    // Read and re-write byte for byte, flush included: the trailing bits of
    // the final byte are zero (STANDARD.md, Trailing bits).
    var wbuf: u8[256] = [0xAA; 256];
    var w = serialize_write_stream_init(wbuf);
    var failed: i64 = -1;
    assert(conf_run_steps(w, base, 0, 28, false, false, failed));
    serialize_flush(w);
    assert(serialize_bits_processed(w) == 891);
    assert(serialize_bytes_processed(w) == 112);
    for i in 112 { assert(wbuf[i] == wire[i]); }

    // Every single-bit flip of a consumed bit must be refused or decode a
    // different message; a reader that ignores a field or a refusal rule shows
    // up as an identical decode.
    var baseline = base;
    for bit in 891 {
        var flipped: u8[112] = [0; 112];
        for i in 112 { flipped[i] = wire[i]; }
        flipped[bit >> 3] = flipped[bit >> 3] ^ ((1 as u8) << ((bit & 7) as u8));
        var trial = baseline;
        if golden_read(flipped[0..112], trial) {
            assert(!golden_same(trial, baseline));
        }
    }
}
