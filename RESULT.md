RESULT: sra-goose sha=af700c3d96ee tier: frontier

head: 2fe3774b1d839a756c95397363af30b9775fcdd2
branch: sprint/serialize-audit-goose/sra-goose
verdict: bounded — the read path is bounded at every entry point; no critical, high or medium finding; five info/low observations reported and accepted; no fix made (report-only scope)

gate:
  make test:      ok 7 test directories (zero warnings)
  make witnesses: ok 58 witnesses
  make controls:  ok 19 controls
  make fuzz:      TestDifferentialAgainstSerializeC PASS — 2000 programs, 486 mutants; refusals by reason past_end 87, value_out_of_range 158, nonzero_padding 7, trailing_data 83, non_finite_float 52, invalid_utf8 17, embedded_nul 13, non_canonical 1; all six negative controls red for their own reason

output:
  docs/security/AUDIT-2026-11-05.md — the entry-point table (function, input, bound relied on, verdict) and findings sra-goose-1..5, each with file:line, what attacker input can reach, severity, reduction and pin

report:
  - sra-goose-1 (info, accepted): src/serialize_bitpacker.goose:29-40,:82,:93 — window load and cross-word tail read bounded only by the slack contract, enforced at src/serialize_stream.goose:89-93,:100-106; pinned by make witnesses read-init-misuse-refused and TestBitpackerReadSlackMissingRefuses.
  - sra-goose-2 (info, accepted): src/serialize_int.goose:46-51,:78-83,:120-175; src/serialize_fixed.goose:166-184; src/serialize_bitpacker.goose:78-96 — unsigned/as! arithmetic so no wire byte can trap under --debug (U7); pinned by witnesses and conformance refuse-offset vectors.
  - sra-goose-3 (low, accepted): src/serialize_bytes.goose:159-190 — a hostile string length can grow a destination only to the packet's own size, never to buffer_size; pinned by TestSerializeStringClaimedLengthCheckedFirst (test/strings/strings_test.goose:458).
  - sra-goose-4 (info, accepted): src/serialize_compressed_float.goose:35-38,:124-144 — the precomputed form does not validate min, by the U16 list; refused as non_finite_float at decode; pinned by TestU16ReadPrecomputedBadConstantsRefuses.
  - sra-goose-5 (info, accepted): src/serialize_bitpacker.goose:30,:82 — the slack contract is a named residual (DESIGN.md (d)); the window assert is provably true for every position the gate admits.

not done (and why):
  - No fixes, no new tests, no fuzz corpora, no proof inputs, no hostile-input reproductions — report-only scope (coordinator note 2026-11-05 13:40).
  - make fuzz-extended (nightly long run) not run; the bounded make fuzz (2000 programs + controls) is the CI smoke and it is green.
  - No Linux bench / fleet before-after numbers: no hot-path change was made, so none is owed.
  - No TLA+ model change: no state or index arithmetic changed.
  - JSON parsing limits: not applicable — the runtime carries no JSON parser.
  - No push / no PR: JOB.md's finish does both from outside the wall.
