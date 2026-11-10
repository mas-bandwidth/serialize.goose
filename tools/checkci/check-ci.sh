#!/bin/sh
# tools/checkci/check-ci.sh -- TEST TestCheckCI (DESIGN.md, (g) THE RUNNER and
# "The vendored standard").
#
# Reads .github/workflows/ci.yml and DESIGN.md only; no network. It fails,
# naming the line, on any runs-on that is not [self-hosted, Linux, X64, fleet, serialize],
# when ci.yml spells a toolchain URL or sha256 (the pin lives once, in the
# Makefile), when the workflow does not run `make dist-goose` and `make test`,
# or when its corpus tag differs from DESIGN.md's pin. Every other workflow in
# .github/workflows/ (the nightly functional test) is held to the same runner
# and the same one-place pin. Its own controls are
# scratch copies of ci.yml with `runs-on: ubuntu-latest` and with a pasted
# sha256: both copies must fail this check, or TestCheckCI fails.
set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ci=${1:-"$root/.github/workflows/ci.yml"}
design="$root/DESIGN.md"

bad=0
fail() {
	printf '%s\n' "$*"
	bad=1
}

# scan_runs_on FILE prints every non-comment runs-on line whose value is not
# [self-hosted, Linux, X64, fleet, serialize], prefixed FILE:LINE.
scan_runs_on() {
	f=$1
	grep -nE '^[[:space:]]*runs-on:' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*runs-on:[[:space:]]*\[self-hosted,[[:space:]]*Linux,[[:space:]]*X64,[[:space:]]*fleet,[[:space:]]*serialize\][[:space:]]*$' |
		sed "s|^|$f:|"
}

# scan_pin FILE prints every non-comment line that spells the toolchain pin
# (its URL, its archive name, or any 64-digit hex sha256), prefixed FILE:LINE.
scan_pin() {
	f=$1
	grep -nE 'aardappel/goose|goose-v[0-9]|goose-.*linux-x64\.tar\.gz|[0-9A-Fa-f]{64}' "$f" |
		grep -vE '^[0-9]+:[[:space:]]*#' |
		sed "s|^|$f:|"
}

# runs_make FILE NAME is true when a non-comment line invokes `make NAME`.
runs_make() {
	grep -nE "make[[:space:]]+$2([[:space:]]|;|$)" "$1" |
		grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null
}

# scan_job_mix FILE names the line that completes a job containing both test
# and witnesses. Jobs begin at the workflow's two-space indentation.
scan_job_mix() {
	awk '
		function scan(line) {
			if (line ~ /(^|[;&|[:space:]])make[[:space:]]+test([[:space:]]|;|$)/) test_line=NR
			if (line ~ /(^|[;&|[:space:]])make[[:space:]]+witnesses([[:space:]]|;|$)/) witness_line=NR
			if (test_line && witness_line) { print FILENAME ":" (test_line > witness_line ? test_line : witness_line); test_line=0; witness_line=0 }
		}
		/^  [A-Za-z0-9_-]+:/ { test_line=0; witness_line=0; in_run=0; run_indent=0 }
		{
			if ($0 ~ /^[[:space:]]*(#|$)/) next
			indent=match($0, /[^ ]/) - 1
			if (in_run && indent <= run_indent) in_run=0
			if ($0 ~ /^[[:space:]]*run:/) {
				in_run=1; run_indent=indent
				line=$0; sub(/^[[:space:]]*run:[[:space:]]*/, "", line)
				if (line !~ /^[|>][-+]?$/) scan(line)
			} else if (in_run) scan($0)
		}
	' "$1"
}

check_job_default() {
	file=$1
	grep -nE '(^|[[:space:]])JOBS=([0-9]+|\$\{JOBS:(-|=)[0-9]+\})([[:space:];]|$)|([[:space:]:{])\$\{JOBS:(-|=)[0-9]+\}' "$file" | sed "s|^|$file:|"
}

# a_tag LINE extracts the first vX.Y.Z from a FILE:LINE record, or empty.
a_tag() {
	printf '%s\n' "$1" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

check_file() {
	target_ci=$1
	if [ ! -f "$target_ci" ]; then
		fail "$target_ci: ci.yml is missing"
		return
	fi

	runs_on_count=$(grep -cE '^[[:space:]]*runs-on:' "$target_ci" || true)
	if [ "$runs_on_count" -eq 0 ]; then
		fail "$target_ci:1: ci.yml declares no runs-on line"
	fi

	while IFS= read -r bad_runner; do
		[ -n "$bad_runner" ] && fail "$bad_runner: runs-on must be [self-hosted, Linux, X64, fleet, serialize]"
	done <<EOF_RUNS_ON
$(scan_runs_on "$target_ci")
EOF_RUNS_ON

	while IFS= read -r spelled; do
		[ -n "$spelled" ] && fail "$spelled: the toolchain pin is spelled in ci.yml; it belongs only in the Makefile"
	done <<EOF_PIN
$(scan_pin "$target_ci")
EOF_PIN

	for target in dist-goose test; do
		runs_make "$target_ci" "$target" || fail "$target_ci:1: ci.yml does not run 'make $target'"
	done
	while IFS= read -r mixed; do
		[ -n "$mixed" ] && fail "$mixed: one CI job runs both 'make test' and 'make witnesses'"
	done <<EOF_MIX
$(scan_job_mix "$target_ci")
EOF_MIX

	ci_line=$(grep -nE '^[[:space:]]*SERIALIZE_TAG:' "$target_ci" | head -1)
	ci_lineno=$(printf '%s\n' "$ci_line" | cut -d: -f1)
	ci_tag=$(a_tag "$ci_line")
	design_line=$(grep -nE 'VERBATIM from mas-bandwidth/serialize at tag' "$design" | head -1)
	design_lineno=$(printf '%s\n' "$design_line" | cut -d: -f1)
	design_tag=$(a_tag "$design_line")
	case "$ci_tag" in
	'')
		fail "$target_ci:${ci_lineno:-1}: ci.yml does not name a SERIALIZE_TAG corpus pin" ;;
	*)
		if [ "$ci_tag" != "$design_tag" ]; then
			fail "$target_ci:$ci_line: corpus tag $ci_tag differs from DESIGN.md:${design_lineno:-1} corpus pin ${design_tag:-none}"
		fi ;;
	esac
}

printf 'RUN TestCheckCI\n'

check_file "$ci"
while IFS= read -r fixed_default; do [ -n "$fixed_default" ] && fail "$fixed_default: JOBS must default to the available core count"; done <<EOF_WITNESS_DEFAULT
$(check_job_default "$root/tools/witnesses.sh")
EOF_WITNESS_DEFAULT
while IFS= read -r fixed_default; do [ -n "$fixed_default" ] && fail "$fixed_default: JOBS must default to the available core count"; done <<EOF_CONTROLS_DEFAULT
$(check_job_default "$root/tools/controls.sh")
EOF_CONTROLS_DEFAULT

# Every other workflow: the fleet runner and the Makefile pin, as ci.yml.
if [ $# -eq 0 ]; then
	for wf in "$root"/.github/workflows/*.yml; do
		[ "$wf" = "$ci" ] && continue
		while IFS= read -r bad_runner; do
			[ -n "$bad_runner" ] && fail "$bad_runner: runs-on must be [self-hosted, Linux, X64, fleet, serialize]"
		done <<EOF_WF_RUNS_ON
$(scan_runs_on "$wf")
EOF_WF_RUNS_ON
		while IFS= read -r spelled; do
			[ -n "$spelled" ] && fail "$spelled: the toolchain pin is spelled in a workflow; it belongs only in the Makefile"
		done <<EOF_WF_PIN
$(scan_pin "$wf")
EOF_WF_PIN
	done
fi

# Run self-controls when checking the repository's default ci.yml.
if [ $# -eq 0 ] && [ "$bad" -eq 0 ]; then
	mkdir -p "$root/build"
	ctl=$(mktemp -d "$root/build/checkci.XXXXXX") || fail "control: cannot make a scratch directory under $root/build"
	if [ -n "${ctl:-}" ] && [ -d "$ctl" ]; then
		sed 's/runs-on: \[self-hosted, Linux, X64, fleet, serialize\]/runs-on: ubuntu-latest/' "$ci" >"$ctl/ci-runner.yml"
		if sh "$0" "$ctl/ci-runner.yml" >"$ctl/runner.out" 2>&1; then
			fail "control: a scratch ci.yml with runs-on: ubuntu-latest passed; it must fail"
		else
			printf 'control: scratch ci.yml with runs-on: ubuntu-latest failed as required:\n'
			sed 's/^/  /' "$ctl/runner.out"
		fi

		cp "$ci" "$ctl/ci-pin.yml"
		printf '      - run: echo f9f0b448800b27b9d86fcd8341a08e8cda790ff86cd500c90e287fa1a616197c\n' >>"$ctl/ci-pin.yml"
		if sh "$0" "$ctl/ci-pin.yml" >"$ctl/pin.out" 2>&1; then
			fail "control: a scratch ci.yml with a pasted sha256 passed; it must fail"
		else
			printf 'control: scratch ci.yml with a pasted sha256 failed as required:\n'
			sed 's/^/  /' "$ctl/pin.out"
		fi

		awk '{ print; if (!inserted && /run:[[:space:]]*make test/) { print "      - name: Fold witnesses into test job"; print "        run: |"; print "          echo check"; print "          make witnesses"; inserted=1 } }' "$ci" >"$ctl/ci-mixed.yml"
		if sh "$0" "$ctl/ci-mixed.yml" >"$ctl/mixed.out" 2>&1; then
			fail "control: a scratch ci.yml with witnesses folded into the test job passed; it must fail"
		else
			printf 'control: scratch ci.yml with witnesses folded into test failed as required:\n'
			sed 's/^/  /' "$ctl/mixed.out"
		fi

		awk 'BEGIN { print "JOBS=${JOBS:-4}" } { print }' "$root/tools/witnesses.sh" >"$ctl/witnesses-fixed-jobs.sh"
		if [ -z "$(check_job_default "$ctl/witnesses-fixed-jobs.sh")" ]; then
			fail "control: a scratch witnesses.sh with JOBS=4 passed; it must fail"
		else
			printf 'control: scratch witnesses.sh with JOBS=4 failed as required:\n'
			check_job_default "$ctl/witnesses-fixed-jobs.sh" | sed 's/^/  /'
		fi

		awk '{ if ($0 ~ /JOBS=\$\(nproc/) { sub(/JOBS=\$\(nproc.*/, "JOBS=4;") } print }' "$root/tools/witnesses.sh" >"$ctl/witnesses-jobs-default.sh"
		if [ -z "$(check_job_default "$ctl/witnesses-jobs-default.sh")" ]; then
			fail "control: a scratch witnesses.sh with 'then JOBS=4; fi' passed; it must fail"
		else
			printf 'control: scratch witnesses.sh with a fixed JOBS=4 default failed as required:\n'
			check_job_default "$ctl/witnesses-jobs-default.sh" | sed 's/^/  /'
		fi

		awk 'BEGIN { print ": ${JOBS:=4}" } { print }' "$root/tools/controls.sh" >"$ctl/controls-jobs-default.sh"
		if [ -z "$(check_job_default "$ctl/controls-jobs-default.sh")" ]; then
			fail "control: a scratch controls.sh with ': ${JOBS:=4}' passed; it must fail"
		else
			printf 'control: scratch controls.sh with : ${JOBS:=4} failed as required:\n'
			check_job_default "$ctl/controls-jobs-default.sh" | sed 's/^/  /'
		fi

		rm -rf "$ctl"
	fi
fi

if [ "$bad" -ne 0 ]; then
	printf -- '--- FAIL TestCheckCI\n'
	exit 1
fi
printf -- '--- PASS TestCheckCI\n'
