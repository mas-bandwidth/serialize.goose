// serialize_object.goose -- composition (STANDARD.md, object; DESIGN.md (a)).
// Calls the caller's own `serialize(s, object)` overload inline, no bytes of
// its own; false from it latches SERIALIZE_ERROR_FAILED unless the stream has
// latched already, and a latched stream refuses before calling it. Card
// serialize-goose-strings fills this file. The function is a stub with its
// final signature.

import .serialize_stream;

fn serialize_object<S, T>(s: S&, object: T&) -> bool {
    abort("serialize: serialize_object not implemented");
}
