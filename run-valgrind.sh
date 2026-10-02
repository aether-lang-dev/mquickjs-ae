#!/bin/sh
# Runs the built mqjs / example binaries under valgrind memcheck: the JS
# conformance suites, the bytecode write/read round-trip, timers, the DSL
# demo and the embedding example. Any invalid access, uninitialised read or
# definite/possible leak fails the run (exit non-zero).
#
# Complements the ASAN debug build (which catches overflows earlier but needs
# a rebuild): this checks the release (-Os) binaries exactly as shipped.
# Kept out of the .tests.ae gate because test_gc_relocation takes ~2 min
# under valgrind. Build first: aeb .build.ae && aeb example-app/.build.ae
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
MQJS="$ROOT/target/build/bin/mqjs"
EXAMPLE="$ROOT/target/build/example-app/bin/example"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

VG="valgrind -q --error-exitcode=99 --leak-check=full --errors-for-leak-kinds=definite,possible"

rc=0
check() {
    name=$1; shift
    if $VG "$@" > "$TMP/out" 2>&1; then
        echo "ok    $name"
    else
        echo "FAIL  $name"
        cat "$TMP/out"
        rc=1
    fi
}

for t in test_closure test_language test_loop test_builtin test_gc_relocation \
         test_rom_write test_regexp_vs_div test_tagged_int; do
    check "$t" "$MQJS" "$ROOT/tests/$t.js"
done
check "low memory (32k)" "$MQJS" --memory-limit 32k "$ROOT/tests/test_low_memory.js"
check "bytecode write" "$MQJS" -o "$TMP/t.bin" "$ROOT/tests/test_builtin.js"
check "bytecode read" "$MQJS" -b "$TMP/t.bin"
printf 'var o=[]; setTimeout(function(){o.push(2)},40); setTimeout(function(){o.push(1); setTimeout(function(){ if (o.join()!="1,2") throw Error("order " + o); },60)},10);\n' > "$TMP/timers.js"
check "timers" "$MQJS" "$TMP/timers.js"
check "dsl demo" "$MQJS" --dsl-demo
check "embedding example" "$EXAMPLE" "$ROOT/tests/test_rect.js"
check "embedding churn + finalizers" "$EXAMPLE" "$ROOT/tests/test_rect_more.js"
exit $rc
