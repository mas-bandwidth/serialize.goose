#!/bin/sh
# tools/controls.sh -- the negative controls (make controls; STANDARD.md, A
# gate nobody has seen go red).
#
# Each control deletes ONE refusal rule from a scratch copy of src/ (a literal
# replacement, never an edit of the tree) and runs the REAL corpus through the
# conformance runner built over that copy, which must fail EXACTLY the vectors
# conformance-controls/<control>.expected names, and no others
# (conf_control_main in test/conformance/conformance_test.goose, the C++
# runner's --expect-failures). The sabotages are the C++ reference's
# (serialize CMakeLists.txt, SERIALIZE_CONTROL_*), translated line for line:
# each keeps the line compiling and false exactly where the rule would fire.
#
# A needle must occur EXACTLY ONCE in its file, or the control fails naming
# it, so the table cannot rot silently into a control that sabotages nothing.
# Rows that share a control name are one sabotage: a rule this port carries
# at two sites (the ranged offset check in serialize_int and in the string
# length field) is deleted at both, as the C++ control deletes both
# FixedPointSerializer specializations.
#
# The unknown-operation control runs conformance-controls/unknown-operation.txt
# through the runner, which must REJECT it (abort naming the gap), never skip.
#
# The controls run without --debug, as the C++ controls build unchecked: a
# reader with a rule deleted must go red through the corpus's verdict, not a
# debug trap. Every copy is staged under build/control/<control>/ and the
# controls run JOBS at a time.
#
# The corpus and the controls' lists are the vendored conformance/ and
# conformance-controls/ unless SERIALIZE_CONFORMANCE_DIR and
# SERIALIZE_CONFORMANCE_CONTROLS_DIR name other directories (the nightly
# functional test points them at mas-bandwidth/serialize main). One that is
# not a directory fails, naming it. Output: one line per control, then
# `ok N controls` or `FAIL k of N controls`.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
GOOSE=${GOOSE:-$root/dist/goose-v2026.2-linux-x64/goose}
GOOSE_HOME=${GOOSE_HOME:-$root/build/goose-home}
export GOOSE GOOSE_HOME
JOBS=${JOBS:-4}  # shared benches: rocketnet has first claim
corpus=${SERIALIZE_CONFORMANCE_DIR:-$root/conformance}
controls=${SERIALIZE_CONFORMANCE_CONTROLS_DIR:-$root/conformance-controls}
for d in "SERIALIZE_CONFORMANCE_DIR=$corpus" "SERIALIZE_CONFORMANCE_CONTROLS_DIR=$controls"; do
	if [ ! -d "${d#*=}" ]; then
		echo "FAIL $d is not a directory"
		exit 1
	fi
done

# control<TAB>file<TAB>from<TAB>to
table() {
	cat <<'EOF_TABLE'
align-padding	src/serialize_stream.goose	guard serialize_packer_read(s, n) == 0 else	guard serialize_packer_read(s, n) != 0xFFFFFFFFFFFFFFFF else
ranged-reconstruction	src/serialize_int.goose	value = ((min as! u32) + offset) as! i32;	value = offset as! i32;
ranged-range	src/serialize_int.goose	if offset > (max as! u32) - (min as! u32) {	if false {
ranged-range	src/serialize_bytes.goose	guard v <= (buffer_size - 1) as u64 else	guard true else
fixed-degenerate-terminal	src/serialize_fixed.goose	guard s.error == SERIALIZE_ERROR_NONE else { return false; } // the latch first, zero-bit reads included	guard true else { return false; } // NEGATIVE CONTROL
float-finite	src/serialize_float.goose	guard serialize_float_bits_are_finite(bits) else	guard serialize_float_bits_are_finite(bits) || bits != 0 else
double-finite	src/serialize_float.goose	guard serialize_double_bits_are_finite(bits) else	guard serialize_double_bits_are_finite(bits) || bits != 0 else
compressed-float-finite	src/serialize_compressed_float.goose	guard serialize_float_bits_are_finite(serialize_f32_bits(decoded)) else	guard true else
end-trailing-data	src/serialize_stream.goose	guard remaining < 8 else	guard true else
end-padding	src/serialize_stream.goose	guard serialize_packer_read(s, padding_bits) == 0 else	guard serialize_packer_read(s, padding_bits) != 0xFFFFFFFFFFFFFFFF else
int-relative-canonical	src/serialize_int.goose	if absolute && reconstructed - (previous as! u32) <= 69914 {	if false {
string-embedded-nul	src/serialize_bytes.goose	guard payload[i] != 0 else	guard true else
string-utf8	src/serialize_bytes.goose	guard serialize_valid_utf8(payload) else	guard true else
string-utf8-surrogate	src/serialize_bytes.goose	if lead == 0xED && b1 >= 0xA0 {	if lead == 0xED && b1 >= 0xA0 && b1 == 0 {
int64-through-double	src/serialize_int.goose	value = ((min as! u64) + offset) as! i64;	let through_double = (((min as! u64) + offset) as! i64) as f64; value = if through_double >= 9223372036854775807.0 { 9223372036854775807 } else { through_double as! i64 };
wrong-reason	src/serialize_bytes.goose	serialize_fail(s, SERIALIZE_ERROR_EMBEDDED_NUL)	serialize_fail(s, SERIALIZE_ERROR_INVALID_UTF8)
EOF_TABLE
}

# replace_once FILE FROM TO: replace the one literal FROM in FILE; prints the
# number of occurrences found (the replacement happens only when it is 1).
replace_once() {
	awk -v from="$2" -v to="$3" -v out="$1.control" '
		{ lines[NR] = $0; n = 0; s = $0
		  while ((i = index(s, from)) > 0) { n++; s = substr(s, i + length(from)) }
		  total += n }
		END {
			for (k = 1; k <= NR; k++) {
				line = lines[k]
				if (total == 1 && (i = index(line, from)) > 0) {
					line = substr(line, 1, i - 1) to substr(line, i + length(from))
				}
				print line > out
			}
			print total
		}' "$1"
	mv "$1.control" "$1"
}

# stage DIR: the runner and the corpus over the (scratch) src/ in DIR.
stage() {
	run=$1/run
	mkdir -p "$run"
	cp "$1"/src/*.goose "$run"/
	cp "$root"/test/conformance/conformance_test.goose "$run"/
	cp "$corpus"/*.txt "$run"/
}

run_control() {
	name=$1
	copy=$root/build/control/$name
	rm -rf "$copy"
	mkdir -p "$copy"
	cp -R "$root/src" "$copy"/
	expected=$controls/$name.expected
	if [ ! -f "$expected" ]; then
		echo "FAIL CONTROL $name: conformance-controls/$name.expected is missing"
		return
	fi
	table | while IFS='	' read -r control file from to; do
		[ "$control" = "$name" ] || continue
		found=$(replace_once "$copy/$file" "$from" "$to")
		if [ "$found" != "1" ]; then
			echo "needle $file '$from' occurs $found times (must be exactly once)"
		fi
	done > "$copy/needles"
	if [ -s "$copy/needles" ]; then
		echo "FAIL CONTROL $name: $(cat "$copy/needles"); fix the table"
		return
	fi
	stage "$copy"
	cp "$expected" "$copy/run/control.expected"
	{
		echo "// generated by tools/controls.sh: control $name"
		echo "import .conformance_test;"
		echo "fn main() { conf_control_main(); }"
	} > "$copy/run/_control.goose"
	out=$(cd "$copy/run" && GOOSE_HOME=$copy/goose-home "$GOOSE" run _control.goose 2>&1)
	code=$?
	summary=$(printf '%s\n' "$out" | sed -n 's/^control: //p' | tail -n 1)
	if [ $code -eq 0 ]; then
		echo "CONTROL $name: red on exactly its .expected ($summary)"
	else
		echo "FAIL CONTROL $name: exit $code ($summary)"
		printf '%s\n' "$out" | grep -E '^(CONTROL|FAIL|goose runtime error)' | sed 's/^/    /'
	fi
}

run_unknown_operation() {
	copy=$root/build/control/unknown-operation
	rm -rf "$copy"
	mkdir -p "$copy/run"
	cp "$root"/src/*.goose "$root"/test/conformance/conformance_test.goose "$copy/run"/
	cp "$controls/unknown-operation.txt" "$copy/run"/
	{
		echo "// generated by tools/controls.sh: the unknown-operation control"
		echo "import .conformance_test;"
		echo "fn main() { conf_unknown_operation_main(); }"
	} > "$copy/run/_control.goose"
	out=$(cd "$copy/run" && GOOSE_HOME=$copy/goose-home "$GOOSE" run _control.goose 2>&1)
	code=$?
	if [ $code -ne 0 ] && printf '%s\n' "$out" | grep -qF "goose runtime error: conformance: no runner"; then
		echo "CONTROL unknown-operation: rejected, never skipped"
	else
		echo "FAIL CONTROL unknown-operation: exit $code; the runner did not reject conformance-controls/unknown-operation.txt"
	fi
}

mkdir -p "$root/build/control"
results=$root/build/control/results
names=$(table | cut -f1 | awk '!seen[$0]++')
# Every vendored .expected has a row, so no control is silently dropped.
missing=""
for f in "$controls"/*.expected; do
	n=$(basename "$f" .expected)
	printf '%s\n' "$names" | grep -qx "$n" || missing="$missing $n"
done

i=0
for name in $names; do
	i=$((i + 1))
	run_control "$name" > "$root/build/control/$i.out" &
	if [ $((i % JOBS)) -eq 0 ]; then wait; fi
done
run_unknown_operation > "$root/build/control/0.out" &
wait

total=$((i + 1))
{
	cat "$root/build/control/0.out"
	k=1
	while [ "$k" -le "$i" ]; do
		cat "$root/build/control/$k.out"
		k=$((k + 1))
	done
	for n in $missing; do echo "FAIL CONTROL $n: conformance-controls/$n.expected has no row in tools/controls.sh"; done
} | tee "$results"

bad=$(grep -c '^FAIL' "$results")
if [ "$bad" -ne 0 ]; then
	echo "FAIL $bad of $total controls"
	exit 1
fi
echo "ok $total controls"
