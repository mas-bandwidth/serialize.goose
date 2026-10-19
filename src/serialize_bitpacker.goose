// serialize_bitpacker.goose -- the packer: the 64-bit scratch word, LSB first,
// whole little-endian words (STANDARD.md, General Conventions; DESIGN.md (b),
// (d)). Card serialize-goose-bitpacker fills this file. Every function is
// called by the stream (src/serialize_stream.goose) and the families only
// after the gate, so none checks the latch, the bounds or the value again.

import .serialize_stream;

// Packs the low `bits` bits of value, bits in [1,64], value < 2^bits, the
// capacity already checked; advances bits_written.
fn serialize_packer_write(s: WriteStream&, value: u64, bits: i64) {
    abort("serialize: serialize_packer_write not implemented");
}

// Unpacks `bits` bits, bits in [1,64], the bounds already checked; advances
// bits_read. Loads 64-bit windows inside data (the slack contract) and never
// interprets a byte at or past num_bits / 8.
fn serialize_packer_read(s: ReadStream&, bits: i64) -> u64 {
    abort("serialize: serialize_packer_read not implemented");
}

// Writes the partial scratch word out (STANDARD.md, General Conventions, Flush).
fn serialize_packer_flush(s: WriteStream&) {
    abort("serialize: serialize_packer_flush not implemented");
}

// Copies data at a byte-aligned position, the capacity already checked.
fn serialize_packer_write_bytes(s: WriteStream&, data: const u8[:]) {
    abort("serialize: serialize_packer_write_bytes not implemented");
}

// Copies data.len bytes from a byte-aligned position, the bounds already checked.
fn serialize_packer_read_bytes(s: ReadStream&, data: u8[:]) {
    abort("serialize: serialize_packer_read_bytes not implemented");
}
