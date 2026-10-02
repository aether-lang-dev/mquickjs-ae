#!/bin/sh
# Differential test: run the same JS through this checkout and a reference
# build (default: upstream C mquickjs at 7ea5399, the last commit before the port, built in a git worktree)
# and require identical stdout+stderr and exit status.
#
#   scripts/diff-upstream.sh               # vs upstream C
#   scripts/diff-upstream.sh --ref HEAD~3  # vs an earlier port commit
#   scripts/diff-upstream.sh --keep        # keep outputs in target/diff/
#
# Corpus: tests/diff/*.js (generated number/math cases, tens of thousands of
# lines) plus the deterministic conformance scripts. Known, intentional
# divergences are listed in SKIP below with the reason.
#
# Also runs Bellard's C library tests from mquickjs-extras (downloaded and
# checksum-verified into target/extras) against this checkout's dtoa.c /
# libm.c: `dtoa_test t` (David Gay's vectors), libm_test (output must match
# upstream libm.c), and rem_pio2 on edge inputs (must match upstream).
set -e
. "$(dirname "$0")/lib.sh"

REF=$UPSTREAM_REF
KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF=$2; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

# Known, intentional divergences (space-separated file names), with reasons.
SKIP=""

build_port
build_ref "$REF"
OUT="$ROOT/target/diff"
rm -rf "$OUT"; mkdir -p "$OUT"
fails=0; n=0

run_case() {   # name, then the mqjs arguments (EXAMPLE=1: use the example host)
    name=$1; shift
    n=$((n + 1))
    ref_bin=$REF_MQJS; this_bin=$PORT_MQJS
    if [ "${EXAMPLE:-0}" = 1 ]; then ref_bin=$REF_EXAMPLE; this_bin=$PORT_EXAMPLE; fi
    rc=0; (cd "$ROOT" && "$ref_bin" "$@") > "$OUT/$name.ref" 2>&1 || rc=$?
    echo "exit $rc" >> "$OUT/$name.ref"
    rc=0; (cd "$ROOT" && "$this_bin" "$@") > "$OUT/$name.this" 2>&1 || rc=$?
    echo "exit $rc" >> "$OUT/$name.this"
    if cmp -s "$OUT/$name.ref" "$OUT/$name.this"; then
        echo "same  $name ($(wc -l < "$OUT/$name.ref") lines)"
    else
        echo "DIFF  $name"
        diff "$OUT/$name.ref" "$OUT/$name.this" | head -10
        fails=$((fails + 1))
    fi
}

for f in "$ROOT"/tests/diff/*.js "$ROOT"/tests/test_*.js; do
    b=$(basename "$f")
    case " $SKIP " in *" $b "*) echo "skip  $b"; continue ;; esac
    case "$b" in
        test_rect*) EXAMPLE=1 run_case "$b" "tests/${f#"$ROOT"/tests/}" ;;   # needs the embedding host
        *) run_case "$b" "tests/${f#"$ROOT"/tests/}" ;;
    esac
done
run_case mandelbrot-10k --memory-limit 10k tests/mandelbrot.js
run_case syntax-error -e 'var x = ;'
run_case uncaught-throw -e 'throw new TypeError("boom")'
run_case undefined-var -e 'foo'
run_case undefined-var-in-fn -e 'function f() { return bar + 1; } f()'
run_case assign-undeclared -e '"use strict"; function g() { zz = 1; } g()'
run_case oom-message --memory-limit 16k -e 'var a = []; for (;;) a.push({})'

# ---- Bellard's C library tests against this checkout's dtoa.c / libm.c ----
fetch_extras
C="$OUT/clib"; mkdir -p "$C/tests"
cp "$EXTRAS"/tests/*.c "$EXTRAS"/tests/*.h "$C/tests/"
for h in cutils.h dtoa.h libm.h list.h softfp_template.h softfp_template_icvt.h; do
    ln -sf "$ROOT/$h" "$C/$h"
done
# helpers the test drivers link: upstream's cutils.c / libm.c from the ref tree
git -C "$ROOT" show "$UPSTREAM_REF:cutils.c" > "$C/cutils.c"
git -C "$ROOT" show "$UPSTREAM_REF:libm.c" > "$C/libm_upstream.c"
# u32toa & co moved from dtoa.c into Aether (ae/dtoa.ae): link the real port code
aeb_env
"$AETHER_TREE/build/aetherc" --emit=lib --lib "$ROOT" "$ROOT/ae/dtoa.ae" "$C/dtoa_ae.c" >/dev/null 2>&1 \
    || die "aetherc failed on ae/dtoa.ae"
INC=$(find "$AETHER_TREE/runtime" "$AETHER_TREE/std" -name '*.h' -printf '-I%h\n' | sort -u | tr '\n' ' ')
CF="-O2 -D_GNU_SOURCE -fno-math-errno -fno-trapping-math -I$C -w"
(cd "$C" &&
    gcc $CF $INC -o dtoa_test tests/dtoa_test.c tests/gay-fixed.c tests/gay-precision.c \
        tests/gay-shortest.c "$ROOT/dtoa.c" cutils.c dtoa_ae.c "$AETHER_TREE/build/libaether.a" \
        -lm -lpthread -ldl &&
    gcc $CF -o libm_test tests/libm_test.c "$ROOT/libm.c" -lm &&
    gcc $CF -o libm_test_ref tests/libm_test.c libm_upstream.c -lm &&
    gcc $CF -o rempio2 tests/rempio2_test.c "$ROOT/libm.c" -lm &&
    gcc $CF -o rempio2_ref tests/rempio2_test.c libm_upstream.c -lm) \
    || die "building the C library tests failed"

n=$((n + 1))
if (cd "$C" && ./dtoa_test t > dtoa.out 2>&1); then
    echo "same  dtoa_test t (Gay vectors pass)"
else
    echo "FAIL  dtoa_test t"; tail -5 "$C/dtoa.out"; fails=$((fails + 1))
fi
n=$((n + 1))
(cd "$C" && { ./libm_test > libm.this 2>&1 || true; ./libm_test_ref > libm.ref 2>&1 || true; })
if cmp -s "$C/libm.ref" "$C/libm.this"; then
    echo "same  libm_test (vs upstream libm.c)"
else
    echo "DIFF  libm_test"; diff "$C/libm.ref" "$C/libm.this" | head -10; fails=$((fails + 1))
fi
n=$((n + 1)); rp=0
for x in 1 3.14159 100 1e10 1e22 1e300 -7.5 6.283185307179586 1.5707963267948966 \
         1e-300 5e-324 1.7976931348623157e308 -0 0 105414350 3.4e38 -1e15; do
    a=$("$C/rempio2" "$x" | sed -n 3p) || true; b=$("$C/rempio2_ref" "$x" | sed -n 3p) || true
    [ "$a" = "$b" ] || { echo "DIFF  rem_pio2($x): $a vs $b"; rp=1; }
done
if [ "$rp" = 0 ]; then echo "same  rem_pio2 edge inputs (vs upstream libm.c)"; else fails=$((fails + 1)); fi

echo
echo "$((n - fails))/$n identical to $REF_SHA"
[ "$KEEP" = 1 ] || rm -rf "$OUT"
[ "$fails" = 0 ]
