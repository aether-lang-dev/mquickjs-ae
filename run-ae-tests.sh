#!/bin/sh
# Runs the std.spec unit tests for the ported Aether modules. These test
# pure-Aether leaf logic (tag math, string/UTF-8 utilities, ...) in
# isolation, complementing the end-to-end JS conformance gate in
# .tests.ae. Exit non-zero if any test fails.
set -e

AETHER=${AETHER_HOME:-${AETHER:-/home/paul/scm/aether}}
AE=$AETHER/build/ae; [ -x "$AE" ] || AE=$AETHER/bin/ae    # dev tree or release install
ROOT=$(cd "$(dirname "$0")" && pwd)
if [ -d "$AETHER/std" ]; then LIB="$AETHER/std:$ROOT"; else LIB="$AETHER/share/aether/std:$ROOT"; fi

rc=0
for t in "$ROOT"/tests/ae/test_*.ae; do
    echo "=== $t ==="
    if ! AETHER_HOME="$AETHER" "$AE" run --lib "$LIB" "$t"; then
        rc=1
    fi
done
exit $rc
