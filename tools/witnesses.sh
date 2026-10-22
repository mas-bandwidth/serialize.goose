#!/bin/sh
# tools/witnesses.sh -- the reversed witnesses (make witnesses).
#
# A green suite is only evidence if it can go red. Each row below deletes or
# reverses exactly ONE rule in src/ (a literal replacement on one line of a
# scratch copy, never an edit of the tree) and the whole suite (`make test`) must
# then FAIL. A row whose suite stays green is a rule nothing pins, and this
# script fails naming it. A row whose literal no longer matches its line also
# fails, naming it, so the table cannot rot silently into a skip.
#
# Every copy is staged under build/witness/<n>/ and the rows run in parallel.
# Output: one line per row, `WITNESS <rule>: red (<failing tests>)`, then
# `ok N witnesses` or `FAIL k of N witnesses`.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
GOOSE=${GOOSE:-$root/dist/goose-v2026.2-linux-x64/goose}
export GOOSE
JOBS=${JOBS:-4}  # shared benches: rocketnet has first claim

# file<TAB>line<TAB>from<TAB>to<TAB>rule (STANDARD.md section)
table() {
	cat <<'EOF'
src/serialize_stream.goose	145	guard bits <= s.num_bits - s.bits_read	guard true	read-past-end-refused (Reader Obligations)
src/serialize_stream.goose	145	SERIALIZE_ERROR_PAST_END); }	SERIALIZE_ERROR_VALUE_OUT_OF_RANGE); }	read-past-end-reason-past_end (Refusal reasons)
src/serialize_stream.goose	122	if s.error == SERIALIZE_ERROR_NONE { s.error = kind; }	s.error = kind;	first-refusal-reason-latched (Refusal reasons)
src/serialize_stream.goose	189	guard bits == 32 || value >> (bits as u32) == 0	guard true	bits-write-value-fits-width (bits)
src/serialize_stream.goose	234	!= 0;	== 0;	bool-reads-the-bit (bool)
src/serialize_stream.goose	306	serialize_packer_read(s, n) == 0	true	align-padding-zero (align)
src/serialize_stream.goose	306	return serialize_fail(s, SERIALIZE_ERROR_NONZERO_PADDING); }	return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE); }	align-reason-nonzero_padding (Refusal reasons)
src/serialize_stream.goose	323	guard remaining < 8	guard true	end-refuses-trailing-data (end)
src/serialize_stream.goose	328	serialize_packer_read(s, padding_bits) == 0	true	end-refuses-set-padding (end)
src/serialize_int.goose	30	if value < min || value > max	if false	int-write-in-range (int)
src/serialize_int.goose	46	if offset > (max as! u32) - (min as! u32)	if false	int-read-offset-in-span (int)
src/serialize_int.goose	49	(min as! u32) + offset	offset	int-read-adds-min (int)
src/serialize_int.goose	158	reconstructed <= (previous as! u32)	false	int-relative-strictly-increasing (int_relative)
src/serialize_int.goose	166	if absolute && reconstructed - (previous as! u32) <= 69914	if false	int-relative-absolute-tier-canonical (int_relative)
src/serialize_int128.goose	142	if serialize_int128_compare(value, min) < 0	if false	int128-write-in-range (int128)
src/serialize_fixed.goose	132	if fixed_u128_compare(offset, span) > 0	if false	fixed-write-in-range (fixed)
src/serialize_fixed.goose	127	guard fixed_u128_compare(raw_value, raw_min) == 0	guard true	fixed-write-zero-width-is-min (fixed)
src/serialize_fixed.goose	151	if fixed_u128_compare(offset, span) > 0	if false	fixed-read-offset-in-span (fixed)
src/serialize_float.goose	55	guard serialize_float_bits_are_finite(pattern)	guard true	float-write-finite (Finite values only)
src/serialize_float.goose	61	guard serialize_float_bits_are_finite(bits)	guard true	float-read-finite (Finite values only)
src/serialize_float.goose	74	guard serialize_double_bits_are_finite(pattern)	guard true	double-write-finite (Finite values only)
src/serialize_float.goose	80	guard serialize_double_bits_are_finite(bits)	guard true	double-read-finite (Finite values only)
src/serialize_compressed_float.goose	93	if integer_value > max_integer_value	if false	compressed-float-integer-in-range (compressed_float)
src/serialize_compressed_float.goose	103	guard serialize_float_bits_are_finite(serialize_f32_bits(decoded))	guard true	compressed-float-decode-finite (compressed_float)
src/serialize_compressed_float.goose	69	if !cf_finite(top)	if false	compressed-float-write-top-finite (compressed_float)
src/serialize_bytes.goose	132	if value[i] == 0	if false	string-write-refuses-nul (string)
src/serialize_bytes.goose	153	guard payload[i] != 0	guard true	string-refuses-nul (string)
src/serialize_bytes.goose	153	SERIALIZE_ERROR_EMBEDDED_NUL	SERIALIZE_ERROR_INVALID_UTF8	string-nul-reason-embedded_nul (string)
src/serialize_bytes.goose	155	guard serialize_valid_utf8(payload)	guard true	string-valid-utf8 (string)
EOF
}

# replace_on_line FILE LINE FROM TO: replace the first literal FROM on LINE.
replace_on_line() {
	awk -v n="$2" -v from="$3" -v to="$4" '
		NR == n { i = index($0, from); if (i > 0) { $0 = substr($0, 1, i - 1) to substr($0, i + length(from)) } }
		{ print }' "$1" > "$1.witness" && mv "$1.witness" "$1"
}

run_row() {
	idx=$1 file=$2 line=$3 from=$4 to=$5 rule=$6
	copy=$root/build/witness/$idx
	rm -rf "$copy"
	mkdir -p "$copy"
	cp -R "$root/src" "$root/test" "$root/conformance" "$root/tools" "$copy"/
	cp "$copy/$file" "$copy/$file.orig"
	replace_on_line "$copy/$file" "$line" "$from" "$to"
	if cmp -s "$copy/$file" "$copy/$file.orig"; then
		echo "FAIL WITNESS $rule: '$from' is not on $file:$line any more; fix the table"
		return
	fi
	rm -f "$copy/$file.orig"
	out=$(GOOSE_HOME=$copy/build/goose-home sh "$copy/tools/run_tests.sh" 2>&1)
	code=$?
	if [ $code -eq 0 ]; then
		echo "FAIL WITNESS $rule: $file:$line '$from' -> '$to' and the suite stayed green"
	else
		red=$(printf '%s\n' "$out" | sed -n 's/^--- FAIL \(Test[A-Za-z0-9_]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')
		echo "WITNESS $rule: red ($red)"
	fi
}

mkdir -p "$root/build/witness"
results=$root/build/witness/results
: > "$results"
i=0
table | while IFS='	' read -r file line from to rule; do
	i=$((i + 1))
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$file" "$line" "$from" "$to" "$rule"
done > "$root/build/witness/rows"
total=$(wc -l < "$root/build/witness/rows" | tr -d ' ')

# Run the rows JOBS at a time.
while IFS='	' read -r idx file line from to rule; do
	run_row "$idx" "$file" "$line" "$from" "$to" "$rule" > "$root/build/witness/$idx.out" &
	if [ $((idx % JOBS)) -eq 0 ]; then wait; fi
done < "$root/build/witness/rows"
wait

idx=1
while [ "$idx" -le "$total" ]; do
	cat "$root/build/witness/$idx.out"
	idx=$((idx + 1))
done | tee "$results"

bad=$(grep -c '^FAIL' "$results")
if [ "$bad" -ne 0 ] || [ "$total" -eq 0 ]; then
	echo "FAIL $bad of $total witnesses"
	exit 1
fi
echo "ok $total witnesses"
