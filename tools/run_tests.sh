#!/bin/sh
# tools/run_tests.sh -- the test runner (DESIGN.md, (g) THE RUNNER).
#
#   sh tools/run_tests.sh          run every test/*/ directory
#   sh tools/run_tests.sh <name>   run test/<name>/ only
#
# A test file is test/<name>/<x>_test.goose. Each `fn Test<Name>()` it declares
# at the start of a line is one test, run in its own process: the runner stages
# build/run/<name>/ (a copy of src/*.goose, every .goose file of test/<name>/
# and the corpus's *.txt), writes a root file there that imports the test file
# and calls the one test from main, and runs it with `$GOOSE run`. A test fails
# by aborting (assert, abort, a bounds or debug check): a nonzero exit.
#
# Directives, on the comment lines directly above a test's `fn` line:
#   // goose: --debug           run it with these extra goose flags (debug checks)
#   // want-abort: <message>    it PASSES only if it exits nonzero AND its output
#                               holds `goose runtime error: <message>`
#
# A test whose build prints a compiler warning FAILS: zero warnings.
#
# The corpus is the vendored conformance/ unless SERIALIZE_CONFORMANCE_DIR names
# another directory (the nightly functional test points it at
# mas-bandwidth/serialize main). A SERIALIZE_CONFORMANCE_DIR that is not a
# directory fails, naming it: never a silent fall back to the vendored copy.
#
# EXTRA CORPUS DIRECTORIES: conformance-regress/ (this port's fixed regression
# vectors) and every directory of SERIALIZE_CONFORMANCE_EXTRA_DIR (':'-separated)
# are staged beside the corpus with their *.txt renamed *.extra, so the corpus
# run (which discovers *.txt and asserts the committed corpus's record count)
# never counts them and the controls never see them; TestConformanceCorpus runs
# the *.extra files separately and requires them all to pass. A named directory
# that is not a directory fails, naming it.
#
# Output: `RUN Test<Name>`, then `--- PASS Test<Name>` or `--- FAIL Test<Name>`
# with the run's output indented below. The runner exits nonzero on any FAIL, on
# a missing or empty test/<name>/, and on a test file that declares no test,
# naming each: never a skip. Its last line is `ok N test directories` or
# `FAIL k of N test directories`.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
GOOSE=${GOOSE:-$root/dist/goose-v2026.2-linux-x64/goose}
# goose run builds C sidecars and caches under GOOSE_HOME: keep it in the job.
GOOSE_HOME=${GOOSE_HOME:-$root/build/goose-home}
export GOOSE_HOME
corpus=${SERIALIZE_CONFORMANCE_DIR:-$root/conformance}
if [ ! -d "$corpus" ]; then
    echo "FAIL SERIALIZE_CONFORMANCE_DIR=$corpus is not a directory"
    exit 1
fi

extras="$root/conformance-regress"
if [ -n "${SERIALIZE_CONFORMANCE_EXTRA_DIR:-}" ]; then
    oldifs=$IFS
    IFS=:
    for d in $SERIALIZE_CONFORMANCE_EXTRA_DIR; do
        if [ ! -d "$d" ]; then
            echo "FAIL SERIALIZE_CONFORMANCE_EXTRA_DIR entry $d is not a directory"
            exit 1
        fi
        extras="$extras:$d"
    done
    IFS=$oldifs
fi

if [ $# -gt 0 ] && [ -n "$1" ]; then
    names=$1
else
    names=""
    for d in "$root"/test/*/; do
        [ -d "$d" ] || continue
        names="$names $(basename "$d")"
    done
    if [ -z "$names" ]; then
        echo "FAIL test/ holds no test directory"
        exit 1
    fi
fi

dirs=0
faildirs=0
for name in $names; do
    dirs=$((dirs + 1))
    dir=$root/test/$name
    if [ ! -d "$dir" ]; then
        echo "FAIL test/$name/ is missing"
        faildirs=$((faildirs + 1))
        continue
    fi
    files=$(ls "$dir"/*_test.goose 2>/dev/null)
    if [ -z "$files" ]; then
        echo "FAIL test/$name/ is empty: it holds no *_test.goose file"
        faildirs=$((faildirs + 1))
        continue
    fi
    stage=$root/build/run/$name
    rm -rf "$stage"
    mkdir -p "$stage"
    cp "$root"/src/*.goose "$stage"/
    cp "$dir"/*.goose "$stage"/
    for f in "$corpus"/*.txt; do
        [ -f "$f" ] && cp "$f" "$stage"/
    done
    oldifs=$IFS
    IFS=:
    for d in $extras; do
        [ -d "$d" ] || continue
        for f in "$d"/*.txt; do
            [ -f "$f" ] && cp "$f" "$stage/$(basename "$f" .txt).extra"
        done
    done
    IFS=$oldifs
    dirfail=0
    for file in $files; do
        base=$(basename "$file" .goose)
        tests=$(sed -n 's/^fn \(Test[A-Za-z0-9_]*\)() *{.*$/\1/p' "$file")
        if [ -z "$tests" ]; then
            echo "FAIL test/$name/$base.goose declares no test (fn Test<Name>() at the start of a line)"
            dirfail=1
            continue
        fi
        for t in $tests; do
            # The comment block directly above the fn line carries the directives.
            above=$(awk -v t="$t" '
                /^\/\// { block = block $0 "\n"; next }
                $0 ~ "^fn " t "\\(\\)" { printf "%s", block; exit }
                { block = "" }' "$file")
            flags=$(printf '%s' "$above" | sed -n 's|^// goose: *||p' | tr '\n' ' ')
            want=$(printf '%s' "$above" | sed -n 's|^// want-abort: *||p' | head -n 1)
            driver=_run_$t
            {
                echo "// generated by tools/run_tests.sh: runs $t from test/$name/$base.goose"
                echo "import .$base;"
                echo "fn main() { $t(); }"
            } > "$stage/$driver.goose"
            echo "RUN $t"
            # shellcheck disable=SC2086
            out=$(cd "$stage" && "$GOOSE" run $flags "$driver.goose" 2>&1)
            code=$?
            ok=0
            if [ -n "$want" ]; then
                if [ $code -ne 0 ] && printf '%s\n' "$out" | grep -qF "goose runtime error: $want"; then
                    ok=1
                fi
            elif [ $code -eq 0 ]; then
                ok=1
            fi
            # Zero warnings: a compiler warning anywhere in the program the
            # test builds fails the test, naming it.
            warned=""
            if [ $ok -eq 1 ] && printf '%s\n' "$out" | grep -q ': warning: '; then
                ok=0
                warned=", a compiler warning: zero warnings"
            fi
            if [ $ok -eq 1 ]; then
                echo "--- PASS $t"
            else
                echo "--- FAIL $t (exit $code${want:+, want abort: $want}$warned)"
                printf '%s\n' "$out" | sed 's/^/    /'
                dirfail=1
            fi
        done
    done
    if [ $dirfail -ne 0 ]; then
        faildirs=$((faildirs + 1))
    fi
done

if [ $faildirs -ne 0 ]; then
    echo "FAIL $faildirs of $dirs test directories"
    exit 1
fi
echo "ok $dirs test directories"
