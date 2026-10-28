// test/uniform -- U2, the caller's refusal (STANDARD.md 2.1, "Refusal
// reasons", `rejected`; IMPLEMENTING.md, "The caller's refusal (U2)"), and
// U15's serialize_copy_string. The latch's three properties are the
// reference's tla/ReadStreamLatch.tla: refused exactly when a reason is
// recorded, the reason never changes once recorded, no read succeeds after a
// refusal.

import .serialize;

struct RejectProbe { bits: u32, reject: bool, called: bool }

// The caller's own serialize: four bits, then its own decision.
fn serialize<S>(s: S&, p: RejectProbe&) -> bool {
    p.called = true;
    guard serialize_bits(s, p.bits, 4) else { return false; }
    return !p.reject;
}

struct RejectEmpty { called: bool }

fn serialize<S>(s: S&, e: RejectEmpty&) -> bool {
    e.called = true;
    return true;
}

fn reject_stream(data: u8[:], bytes: i64) -> ReadStream { return serialize_read_stream_init(data, bytes); }

fn TestU2RejectedIsTheNinthReason() {
    assert(SERIALIZE_ERROR_REJECTED == 9);
    assert(serialize_refusal_name(SERIALIZE_ERROR_REJECTED) == "rejected");
}

// The public reject on a read: refused as rejected, terminal.
fn TestU2RejectLatchesRejectedAndIsTerminal() {
    var data: u8[16] = [0x05, 0xAB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = reject_stream(data, 2);
    var v: u32 = 0;
    assert(serialize_bits(r, v, 4));
    assert(v == 5);
    assert(!serialize_reject(r));
    assert(serialize_error(r) == SERIALIZE_ERROR_REJECTED);
    let before = serialize_bits_processed(r);
    var after: u32 = 0xFFFFFFFF;
    assert(!serialize_bits(r, after, 8));
    assert(after == 0xFFFFFFFF);
    assert(serialize_bits_processed(r) == before);
    var empty = RejectEmpty { called: false };
    assert(!serialize_object(r, empty));
    assert(!empty.called);
    assert(serialize_error(r) == SERIALIZE_ERROR_REJECTED);
}

// The first reason wins: a reject on a stream the wire already refused is an
// echo, and keeps the wire's reason.
fn TestU2RejectAfterAWireRefusalKeepsTheWireReason() {
    var data: u8[16] = [0; 16];
    var r = reject_stream(data, 0);
    var v: u32 = 0;
    assert(!serialize_bits(r, v, 1));
    assert(!serialize_reject(r));
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
}

// A nested object whose serialize returns false with nothing latched
// latches rejected.
fn TestU2ObjectCallbackFalseLatchesRejected() {
    var data: u8[16] = [0x05, 0xAB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = reject_stream(data, 2);
    var p = RejectProbe { bits: 0, reject: true, called: false };
    assert(!serialize_object(r, p));
    assert(p.called && p.bits == 5);
    assert(serialize_error(r) == SERIALIZE_ERROR_REJECTED);
    var after: u32 = 0xFFFFFFFF;
    assert(!serialize_bits(r, after, 8));
    assert(after == 0xFFFFFFFF);
    assert(serialize_error(r) == SERIALIZE_ERROR_REJECTED);
}

// A wire refusal inside the object, then the callback returns false: the
// wire's reason is kept.
fn TestU2ObjectInnerWireRefusalKeepsItsReason() {
    var data: u8[16] = [0; 16];
    var r = reject_stream(data, 0);
    var p = RejectProbe { bits: 0, reject: true, called: false };
    assert(!serialize_object(r, p));
    assert(serialize_error(r) == SERIALIZE_ERROR_PAST_END);
}

// The negative case: an object that does not reject is accepted.
fn TestU2ObjectThatDoesNotRejectIsAccepted() {
    var data: u8[16] = [0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var r = reject_stream(data, 1);
    var p = RejectProbe { bits: 0, reject: false, called: false };
    assert(serialize_object(r, p));
    assert(serialize_error(r) == SERIALIZE_ERROR_NONE);
}

// Reject is read only: on a write or a measure it is caller misuse and
// aborts (U9; TestU9RejectOnWriteAborts, TestU9RejectOnMeasureAborts in
// rulings_test.goose).

// U15: serialize_copy_string, the reference helper: zero the destination,
// then copy at most dest.len - 1 bytes, stopping at a zero byte.
fn TestU15CopyString() {
    var dest: u8[8] = [0xAA; 8];
    serialize_copy_string(dest, "hello world");
    assert(dest[0] == 'h' && dest[6] == 'w' && dest[7] == 0);
    var short: u8[8] = [0xAA; 8];
    let nul: u8[4] = ['a', 0, 'b', 'c'];
    serialize_copy_string(short, nul);
    assert(short[0] == 'a');
    for i in 7 { if i > 0 { assert(short[i] == 0); } }
    var one: u8[1] = [0xAA];
    serialize_copy_string(one, "x");
    assert(one[0] == 0);
}

// want-abort: serialize: copy_string destination must hold at least one byte
fn TestU15CopyStringEmptyDestinationAborts() {
    var none: u8[>..] = [];
    serialize_copy_string(none, "x");
}
