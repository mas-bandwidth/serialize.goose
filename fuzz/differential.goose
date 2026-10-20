// fuzz/differential.goose -- the root of the positive differential run.
// make fuzz stages this directory with src/ and .ref/serialize.c and runs it.

import .differential_test;

fn main() {
    TestDifferentialAgainstSerializeC(false);
}
