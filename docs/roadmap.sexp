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
   :text ("The Goose port of serialize, the open-source bitpacking serializer: the same wire as serialize.c, byte for byte, with the same refusals. The work is on the integration branch sprint/serialize-goose and is not yet on main.")
   :rows
   (("design" "Design, family stubs and test runner")
    ("standard" "STANDARD.md matches serialize v1.17.0")
    ("ci" "Fleet CI workflow and its invariant test")
    ("bitpacker" "64-bit bitpacker and window reader")
    ("integers" "Ranged integers, int64, int128, uint128 and relative ints")
    ("floats" "float, double, fixed and compressed floats")
    ("strings" "Bytes, strings, wide strings, align and objects")
    ("conformance" "Whole conformance corpus, byte for byte with serialize.c")
    ("fuzz" "Differential fuzzing against serialize.c")
    ("bench" "Benchmark against serialize.c, C++ serialize and serialize.rs")
    ("bench-report" "Goose vs C++ vs Rust (and Lobster) benchmark report"))
   :columns (("goose" "goose"))
   :cells
   (("design" "goose" "port/design")
    ("standard" "goose" "port/standard")
    ("ci" "goose" "port/ci")
    ("bitpacker" "goose" "port/bitpacker")
    ("integers" "goose" "port/integers")
    ("floats" "goose" "port/floats")
    ("strings" "goose" "port/strings")
    ("conformance" "goose" "port/conformance")
    ("fuzz" "goose" "port/fuzz")
    ("bench" "goose" "port/bench")
    ("bench-report" "goose" "port/bench-report")))
  (:id "serialize-goose-design" :type :task :title "Design, family stubs and test runner" :state :done :evidence ("land commit 5a1636d75863 on sprint/serialize-goose (card serialize-goose-design, stream serialize-goose)"))
  (:id "port/design" :type :work-set :children ("serialize-goose-design"))
  (:id "serialize-goose-standard-matches-upstream" :type :task :title "STANDARD.md matches serialize v1.17.0" :state :done :evidence ("land commit ca44b72a107c on sprint/serialize-goose (card serialize-goose-standard-matches-upstream, stream serialize-goose)"))
  (:id "port/standard" :type :work-set :children ("serialize-goose-standard-matches-upstream"))
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
  (:id "serialize-goose-conformance" :type :task :title "Whole conformance corpus, byte for byte with serialize.c" :state :todo :evidence ()
   :note "card serialize-goose-conformance (stream serialize-goose, review when archived); last pushed head 625392bda3173fbf95ecf1a90f3b8eb2d5cc3c39 on sprint/serialize-goose-conformance.w2.g2.e21; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-conformance.md")
  (:id "port/conformance" :type :work-set :children ("serialize-goose-conformance"))
  (:id "serialize-goose-fuzz-differential" :type :task :title "Differential fuzzing against serialize.c" :state :todo :evidence ()
   :note "card serialize-goose-fuzz-differential (stream serialize-goose, review when archived); last pushed head ceab089a95ef670b9d746324ad67422f06fcee75 on sprint/serialize-goose-fuzz-differential.w1.g1.e21; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-fuzz-differential.md")
  (:id "port/fuzz" :type :work-set :children ("serialize-goose-fuzz-differential"))
  (:id "serialize-goose-bench" :type :task :title "Benchmark against serialize.c, C++ serialize and serialize.rs" :state :todo :evidence ()
   :note "card serialize-goose-bench (stream serialize-goose, waiting when archived); no pushed head; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-bench.md")
  (:id "port/bench" :type :work-set :children ("serialize-goose-bench"))
  (:id "serialize-goose-bench-report" :type :task :title "Goose vs C++ vs Rust (and Lobster) benchmark report" :state :todo :evidence ()
   :note "card serialize-goose-bench-report (stream serialize-goose, waiting when archived); no pushed head; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-goose/serialize-goose-bench-report.md")
  (:id "port/bench-report" :type :work-set :children ("serialize-goose-bench-report"))))
