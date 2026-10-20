// serialize_object.goose -- composition (STANDARD.md, object; DESIGN.md (a)).
// It contributes no bytes of its own: the nested operations run inline at
// exactly this position, with no framing, length prefix or alignment.
//
// Goose resolves a generic body's names in its own module, so this file cannot
// name the importer's `serialize(s, object)` overload (measured: "unknown
// function: serialize" at instantiation, and a library-side generic fallback
// ties with the caller's generic overload, "ambiguous call to serialize").
// The runner therefore composes by calling the caller's serialize directly;
// see RESULT.md.

import .serialize_stream;

fn serialize_object<S, T>(s: S&, object: T&) -> bool {
    abort("serialize: serialize_object cannot name the caller's serialize overload");
}
