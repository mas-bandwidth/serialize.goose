// serialize.goose -- the entry (DESIGN.md (f)). Importing it imports the
// stream and every family, so `import .serialize;` is the whole library.
// Every import is relative to this file (the leading dot), so the unit works
// wherever a program vendors src/.

import .serialize_stream;
import .serialize_bitpacker;
import .serialize_int;
import .serialize_int128;
import .serialize_float;
import .serialize_fixed;
import .serialize_compressed_float;
import .serialize_bytes;
import .serialize_object;

// The library version (semantic versioning, like the sibling serialize ports).
let SERIALIZE_VERSION = "2.1.2";

// The wire format this library writes and reads (STANDARD.md, Format version).
let SERIALIZE_FORMAT_VERSION = "2.0";
