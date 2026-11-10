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
if [ -z "${JOBS:-}" ]; then JOBS=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1); fi
case "$JOBS" in ''|*[!0-9]*|0*) echo "FAIL JOBS must be a positive integer (got '$JOBS')"; exit 1 ;; esac
if [ "${#JOBS}" -gt 4 ]; then echo "FAIL JOBS exceeds the supported maximum 4096 (got '$JOBS')"; exit 1; fi
if [ "$JOBS" -gt 4096 ]; then echo "FAIL JOBS exceeds the supported maximum 4096 (got '$JOBS')"; exit 1; fi
shard=${WITNESS_SHARD:-}
if [ -n "$shard" ]; then
	case "$shard" in
		[1-9]*/*) shard_k=${shard%%/*}; shard_n=${shard#*/} ;;
		*) echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1 ;;
	esac
	case "$shard_k" in ''|*[!0-9]*|0*) echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1 ;; esac
	case "$shard_n" in ''|*[!0-9]*|0*) echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1 ;; esac
	if [ "${#shard_k}" -gt 7 ] || [ "${#shard_n}" -gt 7 ]; then echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1; fi
	if [ "$shard_n" -lt 1 ] || [ "$shard_k" -lt 1 ] || [ "$shard_k" -gt "$shard_n" ]; then echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1; fi
	if [ "$shard_k" -gt 1000000 ] || [ "$shard_n" -gt 1000000 ]; then echo "FAIL invalid WITNESS_SHARD '$shard'"; exit 1; fi
fi

# file<TAB>line<TAB>from<TAB>to<TAB>rule (STANDARD.md section)
table() {
	cat <<'EOF'
src/serialize_stream.goose	173	guard bits <= s.num_bits - s.bits_read	guard true	read-past-end-refused (Reader Obligations)
src/serialize_stream.goose	173	SERIALIZE_ERROR_PAST_END); }	SERIALIZE_ERROR_VALUE_OUT_OF_RANGE); }	read-past-end-reason-past_end (Refusal reasons)
src/serialize_stream.goose	144	if s.error == SERIALIZE_ERROR_NONE { s.error = serialize_fail_kind(kind); }	s.error = serialize_fail_kind(kind);	first-refusal-reason-latched (Refusal reasons)
src/serialize_stream.goose	232	if bits != 64 && value >> (bits as u64) != 0	if false	bits-write-value-fits-width (bits)
src/serialize_stream.goose	279	!= 0;	== 0;	bool-reads-the-bit (bool)
src/serialize_stream.goose	350	serialize_packer_read(s, n) == 0	true	align-padding-zero (align)
src/serialize_stream.goose	350	return serialize_fail(s, SERIALIZE_ERROR_NONZERO_PADDING); }	return serialize_fail(s, SERIALIZE_ERROR_VALUE_OUT_OF_RANGE); }	align-reason-nonzero_padding (Refusal reasons)
src/serialize_stream.goose	367	guard remaining < 8	guard true	end-refuses-trailing-data (end)
src/serialize_stream.goose	372	serialize_packer_read(s, padding_bits) == 0	true	end-refuses-set-padding (end)
src/serialize_int.goose	32	if value < min || value > max	if false	int-write-in-range (int)
src/serialize_int.goose	48	if offset > (max as! u32) - (min as! u32)	if false	int-read-offset-in-span (int)
src/serialize_int.goose	51	(min as! u32) + offset	offset	int-read-adds-min (int)
src/serialize_int.goose	164	reconstructed <= (previous as! u32)	false	int-relative-strictly-increasing (int_relative)
src/serialize_int.goose	172	if absolute && reconstructed - (previous as! u32) <= 69914	if false	int-relative-absolute-tier-canonical (int_relative)
src/serialize_int128.goose	154	if serialize_int128_compare(value, min) < 0	if false	int128-write-in-range (int128)
src/serialize_fixed.goose	137	if serialize_fixed_u128_compare(serialize_fixed_u128_sub(raw_value, raw_min), span) > 0	if false	fixed-write-in-range (fixed)
src/serialize_fixed.goose	133	guard serialize_fixed_u128_compare(raw_value, raw_min) == 0	guard true	fixed-write-zero-width-is-min (fixed)
src/serialize_fixed.goose	162	if serialize_fixed_u128_compare(offset, span) > 0	if false	fixed-read-offset-in-span (fixed)
src/serialize_float.goose	54	guard serialize_float_bits_are_finite(pattern)	guard true	float-write-finite (Finite values only)
src/serialize_float.goose	60	guard serialize_float_bits_are_finite(bits)	guard true	float-read-finite (Finite values only)
src/serialize_float.goose	73	guard serialize_double_bits_are_finite(pattern)	guard true	double-write-finite (Finite values only)
src/serialize_float.goose	79	guard serialize_double_bits_are_finite(bits)	guard true	double-read-finite (Finite values only)
src/serialize_compressed_float.goose	120	if integer_value > max_integer_value	if false	compressed-float-integer-in-range (compressed_float)
src/serialize_compressed_float.goose	130	guard serialize_float_bits_are_finite(serialize_f32_bits(decoded))	guard true	compressed-float-decode-finite (compressed_float)
src/serialize_compressed_float.goose	93	if !serialize_cf_finite(top)	if false	compressed-float-write-top-finite (compressed_float)
src/serialize_bytes.goose	122	if value[i] == 0	if false	string-write-refuses-nul (string)
src/serialize_bytes.goose	168	guard payload[i] != 0	guard true	string-refuses-nul (string)
src/serialize_bytes.goose	168	SERIALIZE_ERROR_EMBEDDED_NUL	SERIALIZE_ERROR_INVALID_UTF8	string-nul-reason-embedded_nul (string)
src/serialize_bytes.goose	170	guard serialize_valid_utf8(payload)	guard true	string-valid-utf8 (string)
src/serialize_float.goose	60	guard serialize_float_bits_are_finite(bits) else	value = serialize_f32_from_bits(bits); guard serialize_float_bits_are_finite(bits) else	float-read-destination-unwritten (Reader Obligations)
src/serialize_compressed_float.goose	130	guard serialize_float_bits_are_finite(serialize_f32_bits(decoded)) else {	value = decoded; guard serialize_float_bits_are_finite(serialize_f32_bits(decoded)) else {	compressed-float-destination-unwritten (Reader Obligations)
src/serialize_bytes.goose	164	guard length <= serialize_bits_remaining(s) / 8	guard true	string-length-checked-before-payload (string; Reader Obligations)
src/serialize_stream.goose	92	if bytes < 0 || data.len - 8 < bytes	if false	read-init-misuse-refused (U7)
src/serialize_stream.goose	104	SERIALIZE_ERROR_VALUE_OUT_OF_RANGE	SERIALIZE_ERROR_PAST_END	padded-init-reason-value_out_of_range (Refusal reasons)
src/serialize_stream.goose	134	if kind < SERIALIZE_ERROR_PAST_END || kind > SERIALIZE_ERROR_REJECTED	if false	fail-outside-the-list-records-rejected (U14)
src/serialize_stream.goose	363	{ return true; }	{ return false; }	end-on-write-is-true (U12)
src/serialize_object.goose	29	SERIALIZE_ERROR_REJECTED	SERIALIZE_ERROR_VALUE_OUT_OF_RANGE	object-callback-refusal-latches-rejected (U2)
src/serialize_int.goose	122	guard previous >= 0 else	guard true else	int-relative-read-previous-in-domain (U16)
src/serialize_fixed.goose	109	return min >= -half && max <= half - 1;	return true;	fixed-bounds-fit-q-format (U16)
src/serialize_compressed_float.goose	27	max_integer_value <= serialize_CF_MAX_INTEGER_VALUE	true	compressed-float-max-integer-value-bound (U16)
src/serialize_bytes.goose	87	serialize_write_check(s, serialize_align_bits(s) + data.len * 8);	serialize_align(s); serialize_write_check(s, data.len * 8);	bytes-write-room-whole (U10)
src/serialize_bytes.goose	131	serialize_write_check(s, length_bits + align + value.len * 8);	if false { serialize_write_check(s, length_bits + align + value.len * 8); }	string-write-room-whole (U10)
src/serialize_int.goose	105	serialize_write_check(s, serialize_int_relative_bits(difference));	if false { serialize_write_check(s, serialize_int_relative_bits(difference)); }	int-relative-write-room-whole (U10)
src/serialize_bytes.goose	151	buffer_size - 1 <= serialize_string_capacity(value)	true	string-read-capacity-checked (U16)
src/serialize_bytes.goose	180	serialize_string_check(value, buffer_size);	if false { serialize_string_check(value, buffer_size); }	measure-string-checked (U3)
src/serialize_stream.goose	183	if bits > s.num_bits - s.bits_written	if false	write-past-end-aborts (U9)
src/serialize_stream.goose	184	if s.flushed_partial && bits > 0	if false	write-after-partial-flush-aborts (U11)
src/serialize_stream.goose	142	{ return false; }	{ return true; }	fail-on-write-returns-false (U9)
src/serialize_stream.goose	155	abort("serialize: reject is read only");	return false;	reject-on-write-aborts (U9)
src/serialize_stream.goose	157	abort("serialize: reject is read only");	return false;	reject-on-measure-aborts (U9)
src/serialize_stream.goose	248	serialize_bits_write_check(value, bits, 32);	serialize_bits_count_check(bits, 32);	measure-bits-value-fits-width (U6)
src/serialize_stream.goose	267	serialize_bits_write_check(value, bits, 64);	serialize_bits_count_check(bits, 64);	measure-bits64-value-fits-width (U6)
src/serialize_int.goose	56	if value < min || value > max	if false	measure-int-in-range (U6)
src/serialize_int.goose	88	if value < min || value > max	if false	measure-int64-in-range (U6)
src/serialize_int128.goose	190	if serialize_int128_compare(value, min) < 0 || serialize_int128_compare(value, max) > 0	if false	measure-int128-in-range (U6)
src/serialize_fixed.goose	171	serialize_fixed_check_value(raw_value, raw_min, raw_max)	serialize_fixed_u128_bit_length(serialize_fixed_u128_sub(raw_max, raw_min))	measure-fixed-in-range (U6)
src/serialize_float.goose	65	guard serialize_float_bits_are_finite(serialize_f32_bits(value))	guard true	measure-float-finite (U6)
src/serialize_float.goose	84	guard serialize_double_bits_are_finite(serialize_f64_bits(value))	guard true	measure-double-finite (U6)
src/serialize_compressed_float.goose	141	serialize_cf_check_write(value, max_integer_value, bits, delta, min);	serialize_cf_check_precomputed(max_integer_value, bits, delta);	measure-compressed-float-value-checked (U6)
src/serialize_bytes.goose	205	while length > 0 && length < source.len && (source[length] & 0xC0) == 0x80	while false	copy-string-backs-off-to-a-character (U15)
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

if [ "${1:-}" = --row ]; then
	IFS="$(printf '\t')" read -r idx file line from to rule <<EOF_ROW
$2
EOF_ROW
	run_row "$idx" "$file" "$line" "$from" "$to" "$rule" > "$root/build/witness/$idx.out"
	exit $?
fi

mkdir -p "$root/build/witness"
results=$root/build/witness/results
: > "$results"
i=0
table | while IFS='	' read -r file line from to rule; do
	i=$((i + 1))
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$file" "$line" "$from" "$to" "$rule"
done > "$root/build/witness/rows"
total=$(wc -l < "$root/build/witness/rows" | tr -d ' ')

# Run a rolling pool so each completed row immediately makes room for another.
if [ -n "$shard" ]; then
	awk -F '\t' -v k="$shard_k" -v n="$shard_n" '((($1 - 1) % n) + 1) == k' "$root/build/witness/rows" > "$root/build/witness/selected"
else
	cp "$root/build/witness/rows" "$root/build/witness/selected"
fi
selected=$(wc -l < "$root/build/witness/selected" | tr -d ' ')
while IFS="$(printf '\t')" read -r idx rest; do rm -f "$root/build/witness/$idx.out"; done < "$root/build/witness/selected"
rm -f "$root/build/witness/xargs-failure"
while IFS= read -r row; do printf '%s\0' "$row"; done < "$root/build/witness/selected" | xargs -0 -P "$JOBS" -I '{}' sh "$0" --row '{}' || xargs_status=$?
if [ "${xargs_status:-0}" -ne 0 ]; then echo "FAIL WITNESS worker pool exited $xargs_status" > "$root/build/witness/xargs-failure"; fi
while IFS="$(printf '\t')" read -r idx file line from to rule; do
	if [ ! -s "$root/build/witness/$idx.out" ]; then echo "FAIL WITNESS $rule: worker produced no result for $file:$line" > "$root/build/witness/$idx.out"; fi
done < "$root/build/witness/selected"

idx=1
while [ "$idx" -le "$total" ]; do
	if grep -q "^$idx[[:space:]]" "$root/build/witness/selected"; then
	cat "$root/build/witness/$idx.out"
	fi
	idx=$((idx + 1))
done | tee "$results"
if [ -f "$root/build/witness/xargs-failure" ]; then cat "$root/build/witness/xargs-failure" | tee -a "$results"; rm -f "$root/build/witness/xargs-failure"; fi

bad=$(grep -c '^FAIL' "$results")
if [ "$bad" -ne 0 ] || [ "$selected" -eq 0 ]; then
	echo "FAIL $bad of $selected witnesses"
	exit 1
fi
if [ -n "$shard" ]; then echo "ok $selected witnesses (shard $shard)"; else echo "ok $selected witnesses"; fi
