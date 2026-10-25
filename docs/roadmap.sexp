; The serialize.goose roadmap: the data ROADMAP.md is generated from, in the shape of
; mas-bandwidth/schema's docs/roadmap.sexp (one restricted S-expression; data, never evaluated).
; ROADMAP.md is rendered by tools/roadmap/render.lisp (vendored from mas-bandwidth/schema
; tools/roadmap at 609d4e032aff3323e4ee3a3495a1c86d56720914): edit this file, then `make roadmap`; `make roadmap-check`
; fails when the committed page is not what this data renders. Never edit ROADMAP.md by hand.
;
; A cell is ✅ only when every task under it is :done, and a :done task names its evidence (the
; land commit of the sprint card that built it, on the branch named). Every ❌ task names its
; sprint card, the archive file that keeps the card's whole brief and record, and its last pushed
; head. Rewritten 2026-10-20 at the pit stop, when Glenn archived every sprint stream that is not
; rocketnet: "Archive everything from the sprint that isn't rocketnet. Move the cards into their
; respective roadmaps."
(:schema 1 :root "serialize-goose/roadmap"
 :page (:title "serialize.goose roadmap"
        :roadmaps ("port")
        :closing ((:title "About this page" :text ("Each table lists the features of one area: ✅ is built, tested and landed, with the evidence in the source data; ❌ is not yet. The open rows were sprint cards when the sprint stopped for its pit stop on 2026-10-20; each one names its card, its archived brief and any pushed head in the source data, so the work can be picked up again."))))
 :nodes
 ((:id "serialize-goose/roadmap" :type :work-set :children ("port"))
  (:id "port" :type :roadmap :title "The Goose port of serialize"
   :text ("The Goose port of serialize, the open-source bitpacking serializer: the same wire as serialize.c, byte for byte, with the same refusals. The families and the conformance runner are on main (PR #2, PR #3, 2026-10-22); format 2.0 landed with PR #5 (2026-10-22).")
   :rows
   (("design" "Design, family stubs and test runner")
    ("standard" "STANDARD.md matches serialize v2.0.0")
    ("format2" "Format 2.0: refusal reasons, finite floats, end, canonical int_relative, no wstring")
    ("ci" "Fleet CI workflow and its invariant test")
    ("bitpacker" "64-bit bitpacker and window reader")
    ("integers" "Ranged integers, int64, int128, uint128 and relative ints")
    ("floats" "float, double, fixed and compressed floats")
    ("strings" "Bytes, strings, wide strings, align and objects")
    ("conformance" "Whole conformance corpus, byte for byte with serialize.c")
    ("witnesses" "Reversed witnesses: each deleted refusal rule turns the suite red")
    ("controls" "Negative controls: each deleted rule fails exactly its conformance-controls list")
    ("fuzz" "Differential fuzzing against serialize.c")
    ("bench" "Benchmark against serialize.c, C++ serialize and serialize.rs")
    ("bench-report" "Goose vs C++ vs Rust (and Lobster) benchmark report"))
   :columns (("goose" "goose"))
   :cells
   (("design" "goose" "port/design")
    ("standard" "goose" "port/standard")
    ("format2" "goose" "port/format2")
    ("ci" "goose" "port/ci")
    ("bitpacker" "goose" "port/bitpacker")
    ("integers" "goose" "port/integers")
    ("floats" "goose" "port/floats")
    ("strings" "goose" "port/strings")
    ("conformance" "goose" "port/conformance")
    ("witnesses" "goose" "port/witnesses")
    ("controls" "goose" "port/controls")
    ("fuzz" "goose" "port/fuzz")
    ("bench" "goose" "port/bench")
    ("bench-report" "goose" "port/bench-report")))
  (:id "serialize-goose-design" :type :task :title "Design, family stubs and test runner" :state :done :evidence ("land commit 5a1636d75863 on sprint/serialize-goose (card serialize-goose-design, stream serialize-goose)"))
  (:id "port/design" :type :work-set :children ("serialize-goose-design"))
  (:id "serialize-goose-standard-matches-upstream" :type :task :title "STANDARD.md matches serialize v1.17.0" :state :done :evidence ("land commit ca44b72a107c on sprint/serialize-goose (card serialize-goose-standard-matches-upstream, stream serialize-goose)"))
  (:id "serialize-goose-standard-2-0" :type :task :title "STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/ match serialize v2.0.0" :state :done :evidence ("PR #5 on main (branch rowan/format-2.0): the corpus job diffs all four against tag v2.0.0 in CI on the fleet runners"))
  (:id "port/standard" :type :work-set :children ("serialize-goose-standard-matches-upstream" "serialize-goose-standard-2-0"))
  (:id "serialize-goose-format-2-0" :type :task :title "Format 2.0: refusal reasons, finite floats, end, canonical int_relative, no wstring" :state :done :evidence ("PR #5 on main (branch rowan/format-2.0): TestConformanceCorpus runs 18 files, 397 of 397 records, every refusal for its stated reason"))
  (:id "port/format2" :type :work-set :children ("serialize-goose-format-2-0"))
  (:id "serialize-goose-ci" :type :task :title "Fleet CI workflow and its invariant test" :state :done :evidence ("land commit aca98ffcff41 on sprint/serialize-goose (card serialize-goose-ci, stream serialize-goose)"))
  (:id "port/ci" :type :work-set :children ("serialize-goose-ci"))
  (:id "serialize-goose-bitpacker" :type :task :title "64-bit bitpacker and window reader" :state :done :evidence ("land commit 41a7ba07d24b on sprint/serialize-goose (card serialize-goose-bitpacker, stream serialize-goose)"))
  (:id "port/bitpacker" :type :work-set :children ("serialize-goose-bitpacker"))
  (:id "serialize-goose-integers" :type :task :title "Ranged integers, int64, int128, uint128 and relative ints" :state :done :evidence ("land commit 306262b54358 on sprint/serialize-goose (card serialize-goose-integers, stream serialize-goose)"))
  (:id "port/integers" :type :work-set :children ("serialize-goose-integers"))
  (:id "serialize-goose-floats" :type :task :title "float, double, fixed and compressed floats" :state :done :evidence ("land commit 8f9a5ec8da26 on sprint/serialize-goose (card serialize-goose-floats, stream serialize-goose)"))
  (:id "port/floats" :type :work-set :children ("serialize-goose-floats"))
  (:id "serialize-goose-strings" :type :task :title "Bytes, strings, wide strings, align and objects" :state :done :evidence ("land commit c7cdfa7fc662 on sprint/serialize-goose (card serialize-goose-strings, stream serialize-goose)"))
  (:id "port/strings" :type :work-set :children ("serialize-goose-strings"))
  (:id "serialize-goose-conformance" :type :task :title "Whole conformance corpus, byte for byte with serialize.c" :state :done :evidence ("merge commit e9be15505f1c on main (PR #3): TestConformanceCorpus runs 18 files, 351 of 351 records; two sabotaged readers, the unknown-operation control and TestGoldenWireFormat green in CI on the fleet runners"))
  (:id "port/conformance" :type :work-set :children ("serialize-goose-conformance"))
  (:id "serialize-goose-witnesses" :type :task :title "Reversed witnesses: each deleted refusal rule turns the suite red" :state :done :evidence ("merge commit e9be15505f1c on main (PR #3): make witnesses, 16 of 16 single-rule deletions red in CI"))
  (:id "serialize-goose-witnesses-2-0" :type :task :title "Reversed witnesses extended for format 2.0" :state :done :evidence ("PR #5 on main (branch rowan/format-2.0): make witnesses, 32 of 32 single-rule deletions red in CI"))
  (:id "port/witnesses" :type :work-set :children ("serialize-goose-witnesses" "serialize-goose-witnesses-2-0"))
  (:id "serialize-goose-controls" :type :task :title "Negative controls: each deleted rule fails exactly its conformance-controls list" :state :done :evidence ("PR #5 on main (branch rowan/format-2.0): make controls, 16 of 16 (15 sabotaged readers on their exact .expected lists, and unknown-operation rejected) in CI"))
  (:id "port/controls" :type :work-set :children ("serialize-goose-controls"))
  (:id "serialize-goose-fuzz-differential" :type :task :title "Differential fuzzing against serialize.c" :state :done :evidence ("PR #7 merged to main as 2b437823b80855385443d72d73fd26a7756a0da0 (branch rowan/fuzz-differential): make fuzz in CI, 2000 fixed-seed programs over every operation against serialize.c v2.0.0, 495 mutants agreeing on accept, step and reason; negative controls range widened, reader range refusals deleted and wrong reason each red for its own reason" "nightly-fuzz.yml dispatched on main with duration 300: run 40218563731 success, seed 40218563731, 4394500 programs green")
   :note "the earlier head ceab089 on sprint/serialize-goose-fuzz-differential.w1.g1.e21 targeted serialize.c v1.11.2 (format 1.1) and never had a PR; superseded by PR #7")
  (:id "port/fuzz" :type :work-set :children ("serialize-goose-fuzz-differential"))
  (:id "serialize-goose-bench" :type :task :title "Benchmark against serialize.c, C++ serialize and serialize.rs" :state :todo :evidence ()
   :note "card serialize-goose-bench (stream serialize-goose, waiting when archived); no pushed head; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-bench.md")
  (:id "port/bench" :type :work-set :children ("serialize-goose-bench"))
  (:id "serialize-goose-bench-report" :type :task :title "Goose vs C++ vs Rust (and Lobster) benchmark report" :state :todo :evidence ()
   :note "card serialize-goose-bench-report (stream serialize-goose, waiting when archived); no pushed head; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-bench-report.md")
  (:id "port/bench-report" :type :work-set :children ("serialize-goose-bench-report"))))
