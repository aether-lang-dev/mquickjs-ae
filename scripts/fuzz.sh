#!/bin/sh
# Mutation fuzzer for the parser, regexp engine, number parsing and VM.
#
#   scripts/fuzz.sh                 # 2000 cases, seed 1
#   scripts/fuzz.sh -n 20000 -s 7   # more cases / another seed
#   scripts/fuzz.sh --no-asan       # fuzz the release build (faster, less precise)
#
# Builds an AddressSanitizer copy of the working tree under target/fuzz/asan
# (unless --no-asan), generates inputs by mutating the JS corpus (tests/*.js,
# tests/diff/*.js): byte flips, span deletes/duplicates, splices between
# files, JS token insertion, truncation, plus generated regexp patterns and
# number strings. Each case runs with a timeout and a small heap.
#
# Pass: every case exits normally (0, or 1 for a JS exception/syntax error).
# Fail: a signal, an ASAN report, or exit status >= 2. Crashing inputs are
# saved to target/fuzz/crashes/ with the tool's stderr alongside.
# Hangs (timeout) are counted but not failures: mutation easily makes
# infinite loops.
set -e
. "$(dirname "$0")/lib.sh"

N=2000; SEED=1; ASAN=1
while [ $# -gt 0 ]; do
    case "$1" in
        -n) N=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        --no-asan) ASAN=0; shift ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

FZ="$ROOT/target/fuzz"
mkdir -p "$FZ/crashes"
if [ "$ASAN" = 1 ]; then
    # copy the working tree (tracked + untracked, not ignored) and build it
    # with -fsanitize=address
    SRC="$FZ/asan"
    rm -rf "$SRC"; mkdir -p "$SRC"
    (cd "$ROOT" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -xf - -C "$SRC"
    sed -i 's/cflag("-Os")/cflag("-O1 -g -fsanitize=address -fno-omit-frame-pointer")\n            link_flag("-fsanitize=address")/' "$SRC/.build.ae"
    aeb_env
    (cd "$SRC" && aeb .build.ae > "$FZ/asan-build.log" 2>&1) || die "ASAN build failed (see $FZ/asan-build.log)"
    MQJS="$SRC/target/build/bin/mqjs"
    export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0:exitcode=86
else
    build_port
    MQJS=$PORT_MQJS
fi
[ -n "$FUZZ_MQJS" ] && MQJS=$FUZZ_MQJS   # test hook: fuzz a given binary

python3 - "$MQJS" "$N" "$SEED" "$FZ" "$ROOT" <<'EOF'
import glob, os, random, subprocess, sys
mqjs, n, seed, fz, root = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
rnd = random.Random(seed)
corpus = [open(p, 'rb').read() for p in sorted(glob.glob(root + '/tests/*.js') + glob.glob(root + '/tests/diff/*.js'))
          if 'microbench' not in p]
tokens = [b'(', b')', b'{', b'}', b'[', b']', b';', b',', b'.', b'=', b'==', b'===', b'=>',
          b'+', b'++', b'-', b'--', b'*', b'**', b'/', b'%', b'<<', b'>>>', b'&&', b'||', b'??',
          b'?', b':', b'!', b'~', b'"', b"'", b'`', b'/x/g', b'\\', b'\n', b' ', b'0x', b'1e', b'.5',
          b'function', b'return', b'var', b'let', b'const', b'if', b'else', b'for', b'while', b'do',
          b'break', b'continue', b'new', b'delete', b'typeof', b'instanceof', b'in', b'of', b'this',
          b'try', b'catch', b'finally', b'throw', b'switch', b'case', b'default', b'null',
          b'undefined', b'NaN', b'Infinity', b'arguments', b'eval', b'__proto__', b'prototype',
          b'Math.pow', b'JSON.parse', b'String.fromCharCode(0xd800)', b'"\\ud800"', b'\xc3\xa9',
          b'\xf0\x9f\x98\x80', b'\xff', b'\x00', b'new Array(1e7)', b'.toString(36)', b'.repeat(1e6)']
def mutate(b):
    b = bytearray(b)
    for _ in range(rnd.randint(1, 8)):
        if not b:
            b += rnd.choice(tokens)
            continue
        op = rnd.randrange(7); i = rnd.randrange(len(b))
        if op == 0: b[i] = rnd.randrange(256)
        elif op == 1: del b[i:i + rnd.randint(1, 64)]
        elif op == 2: j = rnd.randrange(len(b)); b[i:i] = b[j:j + rnd.randint(1, 64)]
        elif op == 3: b[i:i] = rnd.choice(tokens)
        elif op == 4: del b[rnd.randrange(len(b)):]
        elif op == 5:
            o = rnd.choice(corpus); j = rnd.randrange(max(1, len(o)))
            b[i:i] = o[j:j + rnd.randint(1, 400)]
        else: b[i:i] = str(rnd.choice([0, -1, 2**31, 2**53, 1e308, 5e-324])).encode()
    return bytes(b)
re_atoms = ['a', '.', '\\d', '\\w', '\\s', '\\b', '\\B', '[a-z]', '[^x]', '(a)', '(?:b)', '(?=c)',
            '(?!d)', '\\1', '\\2', '|', '^', '$', '*', '+', '?', '{2}', '{1,3}', '{0,}', '*?', '\\u{1F600}',
            '\\ud83d', '[\\ud800-\\udfff]', '\\x41', '\\cA', '\\0', '[', ']', '(', ')', '\\', '(?<n>x)', '\\k<n>']
def regexp_case():
    pat = ''.join(rnd.choice(re_atoms) for _ in range(rnd.randint(1, 12)))
    flags = ''.join(f for f in 'gimsuy' if rnd.random() < 0.3)
    subj = ''.join(rnd.choice(['a', 'b', 'c', 'x', '1', ' ', '\\n', '\\u00e9', '\\ud83d\\ude00'])
                   for _ in range(rnd.randint(0, 30)))
    return ('try { var r = new RegExp(%r, %r); var s = "%s"; s.replace(r, "$&$1");'
            ' s.split(r); r.exec(s); r.test(s); s.match(r); } catch (e) {}\n'
            % (pat, flags, subj)).encode()
def number_case():
    chars = '0123456789.eE+-xXbBoO_ '
    s = ''.join(rnd.choice(chars) for _ in range(rnd.randint(1, 30)))
    return ('var s = %r; Number(s); parseFloat(s); parseInt(s, %d);'
            ' (+s).toString(%d); (+s).toFixed(%d); (+s).toPrecision(%d);\n'
            % (s, rnd.randint(0, 36), rnd.randint(2, 36), rnd.randint(0, 20), rnd.randint(1, 21))).encode()

case_path = os.path.join(fz, 'case.js')
crashes = hangs = 0
ran_ok = 0   # exit 0: the mutated program ran to completion
for k in range(n):
    r = rnd.random()
    if r < 0.15: data = b''.join(regexp_case() for _ in range(20))
    elif r < 0.25: data = b''.join(number_case() for _ in range(20))
    else: data = mutate(rnd.choice(corpus))
    with open(case_path, 'wb') as f:
        f.write(data)
    try:
        p = subprocess.run([mqjs, '--memory-limit', '4M', case_path], stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=10)
        rc, err = p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        hangs += 1
        continue
    if rc == 0:
        ran_ok += 1
    if rc < 0 or rc >= 2 or b'AddressSanitizer' in err or b'runtime error:' in err:
        crashes += 1
        name = os.path.join(fz, 'crashes', 'seed%d-case%d' % (seed, k))
        open(name + '.js', 'wb').write(data)
        open(name + '.txt', 'wb').write(('exit %d\n' % rc).encode() + err[-4000:])
        print('CRASH case %d (exit %d) -> %s.js' % (k, rc, name))
    if (k + 1) % 500 == 0:
        print('%d/%d cases, %d ran clean, %d crashes, %d hangs' % (k + 1, n, ran_ok, crashes, hangs), flush=True)
print('done: %d cases (%d ran to completion, the rest threw or failed to parse), '
      '%d crashes, %d hangs (seed %d)' % (n, ran_ok, crashes, hangs, seed))
sys.exit(1 if crashes else 0)
EOF
