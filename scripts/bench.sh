#!/bin/sh
# Performance comparison: this checkout vs a reference commit, both built
# from source (the reference in a git worktree under target/ref/).
#
#   scripts/bench.sh                      # vs upstream C mquickjs (7ea5399)
#   scripts/bench.sh --ref HEAD~5         # vs an earlier port commit
#   scripts/bench.sh prop_ empty_loop     # only matching microbenchmarks
#   scripts/bench.sh --octane             # also run Octane (downloads extras)
#
# Prints ns/op per microbenchmark for both builds, the ratio (this / ref; >1
# means this checkout is slower) and the geometric mean of the ratios.
# Octane prints both score tables (higher is better). Timings are noisy:
# compare runs on a quiet machine, and treat <10% differences as noise.
set -e
. "$(dirname "$0")/lib.sh"

REF=$UPSTREAM_REF
OCTANE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) REF=$2; shift 2 ;;
        --octane) OCTANE=1; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) break ;;
    esac
done

build_port
build_ref "$REF"
OUT="$ROOT/target/bench"
mkdir -p "$OUT"

echo "this checkout: $(git -C "$ROOT" rev-parse --short=12 HEAD)$(git -C "$ROOT" diff --quiet || echo '+dirty')"
echo "reference:     $REF_SHA"
echo

# microbench.js writes its tables to stdout; run from OUT so any files it
# drops land there.
(cd "$OUT" && "$REF_MQJS" "$ROOT/tests/microbench.js" "$@" > ref.txt 2>&1) || die "reference microbench failed (see $OUT/ref.txt)"
(cd "$OUT" && "$PORT_MQJS" "$ROOT/tests/microbench.js" "$@" > this.txt 2>&1) || die "microbench failed (see $OUT/this.txt)"

python3 - "$OUT/ref.txt" "$OUT/this.txt" <<'EOF'
import math, re, sys
def load(p):
    d = {}
    for l in open(p):
        m = re.match(r'\s*(\w+)\s+(\d+)\s+([\d.]+)\s*$', l)
        if m and m.group(1) != "total":
            d[m.group(1)] = float(m.group(3))
    return d
ref, this = load(sys.argv[1]), load(sys.argv[2])
names = [k for k in ref if k in this and ref[k] > 0]
print(f"{'benchmark':22}{'ref ns':>10}{'this ns':>10}{'ratio':>8}")
logs = []
for k in names:
    r = this[k] / ref[k]
    logs.append(math.log(r))
    print(f"{k:22}{ref[k]:10.1f}{this[k]:10.1f}{r:8.2f}")
if logs:
    print(f"{'geomean ratio':42}{math.exp(sum(logs) / len(logs)):8.2f}")
EOF

if [ "$OCTANE" = 1 ]; then
    fetch_extras
    echo
    echo "Octane (score, higher is better):"
    "$REF_MQJS" --memory-limit 256M "$EXTRAS/tests/octane/run.js" > "$OUT/octane-ref.txt" 2>&1 || true
    "$PORT_MQJS" --memory-limit 256M "$EXTRAS/tests/octane/run.js" > "$OUT/octane-this.txt" 2>&1 || true
    python3 - "$OUT/octane-ref.txt" "$OUT/octane-this.txt" <<'EOF'
import re, sys
def load(p):
    return {m.group(1): int(m.group(2)) for m in
            (re.match(r'^(\w+): (\d+)$', l.strip()) for l in open(p)) if m}
ref, this = load(sys.argv[1]), load(sys.argv[2])
print(f"{'benchmark':18}{'ref':>8}{'this':>8}{'this/ref':>10}")
for k in ref:
    t = this.get(k)
    print(f"{k:18}{ref[k]:8}{(t if t is not None else '-'):>8}"
          f"{(f'{t / ref[k]:.2f}' if t else 'FAILED'):>10}")
for k in this:
    if k not in ref:
        print(f"{k:18}{'-':>8}{this[k]:8}")
EOF
    echo "(full output: $OUT/octane-ref.txt, $OUT/octane-this.txt)"
fi
