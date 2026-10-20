// fuzz/negative.goose -- the negative control: the same test with the C side
// writing one int range one bit wider. It must go red, so make fuzz passes
// only when this program exits nonzero.

import .differential_test;

fn main() {
    d_enable_negative();
    TestDifferentialAgainstSerializeC(true);
}
