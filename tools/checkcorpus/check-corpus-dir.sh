#!/bin/sh
# tools/checkcorpus/check-corpus-dir.sh -- TEST TestCorpusDir, a unit test of
# SERIALIZE_CONFORMANCE_DIR and SERIALIZE_CONFORMANCE_CONTROLS_DIR (the corpus
# override in tools/run_tests.sh and tools/controls.sh, which the nightly
# functional test points at mas-bandwidth/serialize main).
#
# No Goose, no network, no real time: GOOSE is a stub that records what the
# runner staged beside it and exits. The fixtures are scratch directories
# under build/: a corpus holding one marker vector file, and a copy of the
# vendored conformance-controls/ whose align-padding.expected holds a marker
# line. It fails, naming the case, unless
#   - by default, run_tests.sh stages the vendored conformance/*.txt;
#   - with the override, run_tests.sh stages the fixture's *.txt and none of
#     the vendored ones, and controls.sh stages the fixture's *.txt and the
#     fixture's .expected;
#   - an override that is not a directory is refused by both, by name.
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

bad=0
fail() {
	printf '%s\n' "$*"
	bad=1
}

printf 'RUN TestCorpusDir\n'

mkdir -p "$root/build"
scratch=$(mktemp -d "$root/build/checkcorpus.XXXXXX") || { printf 'cannot make a scratch directory under %s/build\n--- FAIL TestCorpusDir\n' "$root"; exit 1; }

cat >"$scratch/goose" <<'EOF_STUB'
#!/bin/sh
# Stub goose: record the staged directory, never build or run anything.
ls >staged.list
if [ -f control.expected ]; then cat control.expected >>staged.list; fi
exit 0
EOF_STUB
chmod +x "$scratch/goose"

mkdir -p "$scratch/corpus"
printf 'operation bool\nname corpus-dir-marker\nbytes 01\nexpect value = true\nconsumed 1\n' >"$scratch/corpus/corpus-dir-marker.txt"
cp -R "$root/conformance-controls" "$scratch/controls"
printf 'corpus-dir-expected-marker\n' >"$scratch/controls/align-padding.expected"

staged=$root/build/run/conformance/staged.list

# The default: the vendored corpus.
GOOSE=$scratch/goose GOOSE_HOME=$scratch/goose-home sh "$root/tools/run_tests.sh" conformance >"$scratch/default.out" 2>&1
grep -qx 'bits.txt' "$staged" 2>/dev/null || fail "default: run_tests.sh did not stage the vendored conformance/bits.txt"
grep -qx 'corpus-dir-marker.txt' "$staged" 2>/dev/null && fail "default: run_tests.sh staged the fixture corpus without the override"

# The override: the fixture corpus, and only it.
rm -f "$staged"
SERIALIZE_CONFORMANCE_DIR=$scratch/corpus GOOSE=$scratch/goose GOOSE_HOME=$scratch/goose-home \
	sh "$root/tools/run_tests.sh" conformance >"$scratch/override.out" 2>&1
grep -qx 'corpus-dir-marker.txt' "$staged" 2>/dev/null || fail "override: run_tests.sh did not stage SERIALIZE_CONFORMANCE_DIR's corpus-dir-marker.txt"
grep -qx 'bits.txt' "$staged" 2>/dev/null && fail "override: run_tests.sh staged the vendored bits.txt beside SERIALIZE_CONFORMANCE_DIR's corpus"

control_staged=$root/build/control/align-padding/run/staged.list
SERIALIZE_CONFORMANCE_DIR=$scratch/corpus SERIALIZE_CONFORMANCE_CONTROLS_DIR=$scratch/controls \
	GOOSE=$scratch/goose GOOSE_HOME=$scratch/goose-home sh "$root/tools/controls.sh" >"$scratch/controls.out" 2>&1
grep -qx 'corpus-dir-marker.txt' "$control_staged" 2>/dev/null || fail "override: controls.sh did not stage SERIALIZE_CONFORMANCE_DIR's corpus-dir-marker.txt"
grep -qx 'bits.txt' "$control_staged" 2>/dev/null && fail "override: controls.sh staged the vendored bits.txt"
grep -qx 'corpus-dir-expected-marker' "$control_staged" 2>/dev/null || fail "override: controls.sh did not stage SERIALIZE_CONFORMANCE_CONTROLS_DIR's align-padding.expected"

# An override that is not a directory is refused, by name.
if SERIALIZE_CONFORMANCE_DIR=$scratch/missing GOOSE=$scratch/goose sh "$root/tools/run_tests.sh" conformance >"$scratch/missing.out" 2>&1; then
	fail "refusal: run_tests.sh passed with SERIALIZE_CONFORMANCE_DIR naming no directory"
fi
grep -qF "FAIL SERIALIZE_CONFORMANCE_DIR=$scratch/missing is not a directory" "$scratch/missing.out" || fail "refusal: run_tests.sh did not name the missing SERIALIZE_CONFORMANCE_DIR"
if SERIALIZE_CONFORMANCE_CONTROLS_DIR=$scratch/missing GOOSE=$scratch/goose sh "$root/tools/controls.sh" >"$scratch/missing-controls.out" 2>&1; then
	fail "refusal: controls.sh passed with SERIALIZE_CONFORMANCE_CONTROLS_DIR naming no directory"
fi
grep -qF "FAIL SERIALIZE_CONFORMANCE_CONTROLS_DIR=$scratch/missing is not a directory" "$scratch/missing-controls.out" || fail "refusal: controls.sh did not name the missing SERIALIZE_CONFORMANCE_CONTROLS_DIR"

rm -rf "$scratch" "$root/build/run/conformance" "$root/build/control"

if [ "$bad" -ne 0 ]; then
	printf -- '--- FAIL TestCorpusDir\n'
	exit 1
fi
printf -- '--- PASS TestCorpusDir\n'
