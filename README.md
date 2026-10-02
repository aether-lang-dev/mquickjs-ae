MicroQuickJS for Aether
=======================

A port of Fabrice Bellard and Charlie Gordon's
[MicroQuickJS](https://github.com/bellard/mquickjs) (MQuickJS) JavaScript
engine to the [Aether](https://github.com/aether-lang-dev/aether) programming
language.

MQuickJS is a JavaScript engine for embedded systems: it runs programs in as
little as 10 kB of RAM, supports a [stricter subset](#the-javascript-dialect)
of JavaScript close to ES5, and uses a compacting tracing GC, a VM that does
not use the CPU stack, and UTF-8 strings. In this repository the ~18,000-line
C engine (`mquickjs.c`) has been rewritten in Aether: the parser, compiler,
bytecode VM, GC, regexp engine and the whole standard library are Aether
modules under `ae/`. The engine keeps upstream's design, bytecode format and
C API, so C embedders can use it as before.

Maintained by Paul Hammant, Nic and Claude. Contributor and agent notes are
in [AGENTS.md](AGENTS.md).

## Status

| | |
|---|---|
| **Correctness** | Output identical to upstream C (`7ea5399`, Bellard's last commit before the port) across the differential corpus: ~76k lines of generated number formatting/parsing and Math cases, the conformance suites and error paths (`scripts/diff-upstream.sh`, 23/23). Bellard's own `dtoa_test` (Gay vectors), `libm_test` and `rem_pio2` checks pass against this tree's `dtoa.c`/`libm.c`. All of the Octane benchmark runs with correct results. |
| **Memory safety** | valgrind-clean (`run-valgrind.sh`); an ASAN mutation fuzzer (`scripts/fuzz.sh`) runs in CI. |
| **Speed** | Slower than upstream C today: about **4.5×** on Octane's overall score and about **7×** on the microbench geometric mean (individual benchmarks range from 1.5× to 11×). The main cause is known: opcode dispatch is a chain of comparisons rather than a jump table. Track it with `scripts/bench.sh`. |
| **Size** | The `-Os` binary's code is about 4.5× larger than upstream C's. |
| **Remaining C** | `dtoa.c` and `libm.c` (third-party numerics), `mqjs.c` and `readline_tty.c` (CLI glue), `example.c` (C embedding demo), `mquickjs_build.c` (generator glue). |

Fixes this port carries over upstream: GC finalizers now run for every
dead object (upstream skips all but the first of each run of adjacent dead
objects, leaking embedders' C data).

## Building

You need an Aether source tree (the engine builds against a dev checkout;
see `ci-pins` for the validated version, currently `v0.760.0`) and
[aeb](https://github.com/aether-lang-dev/aeb), the build runner, with
Aether 0.758 or later on `PATH`.

```sh
export MQJS_AETHER_HOME=/path/to/aether   # default: /home/paul/scm/aether
aeb .build.ae                 # builds target/build/bin/mqjs
aeb example-app/.build.ae     # builds the C embedding demo
aeb .tests.ae                 # builds both and runs the conformance gate
```

## The `mqjs` command

```
usage: mqjs [options] [file [args]]
-h  --help            list options
-e  --eval EXPR       evaluate EXPR
-i  --interactive     go to interactive mode
-I  --include file    include an additional file
-d  --dump            dump the memory usage stats
    --memory-limit n  limit the memory usage to 'n' bytes
--no-column           no column number in debug information
-o FILE               save the bytecode to FILE
-m32                  force 32 bit bytecode output (use with -o)
-b  --allow-bytecode  allow bytecode in input file
```

Compile and run a program using 10 kB of RAM:

```sh
target/build/bin/mqjs --memory-limit 10k tests/mandelbrot.js
```

`mqjs` can save the compiled bytecode to persistent storage (a file or ROM)
and run it later:

```sh
target/build/bin/mqjs -o mandelbrot.bin tests/mandelbrot.js
target/build/bin/mqjs -b mandelbrot.bin
```

The bytecode format depends on the endianness and word length of the CPU.
On a 64-bit CPU, `-m32` generates 32-bit bytecode for an embedded 32-bit
system. `--no-column` drops column numbers from the debug info (line numbers
remain) to save storage.

## Using the engine from Aether

`ae/quickjs` is the Aether-facing API: create an engine over its own heap,
evaluate source, and inspect results without touching the internal
`JS_*` symbols.

```aether
import ae.quickjs

quickjs.with_engine(stdlib_ptr, 4 * 1024 * 1024) |eng| {
    r = quickjs.eval(eng, "40 + 2")
    println(quickjs.result_int(eng, r))      // 42
}
```

The standard library is baked at build time into a ROM table, so the host
passes its address (`stdlib_ptr`, for example `mqjs`'s `js_stdlib`). The
standard library itself is declared in Aether (`gen/genengine`) and turned
into `mqjs_stdlib.h` by the generator node in `gen/`.

**This path is the least finished part of the port.** The facade is not yet
built or tested as a standalone Aether library: its example
(`ae/quickjs/example_embed.ae`) is not compiled by any build node.
`mqjs --dsl-demo` shows the related declarative launch DSL (`ae/mqjs_dsl`).

## Using the engine from C

The C API is upstream's (see `mquickjs.h`), and `example.c` is a complete
example with a custom `Rectangle` class.

### Engine initialization

MQuickJS has almost no dependency on the C library. In particular it does not
use `malloc()`, `free()` or `printf()` itself. When creating a context you
provide a memory buffer, and the engine allocates only inside it:

```c
    JSContext *ctx;
    uint8_t mem_buf[8192];
    ctx = JS_NewContext(mem_buf, sizeof(mem_buf), &js_stdlib);
    ...
    JS_FreeContext(ctx);
```

`JS_FreeContext(ctx)` is only needed to call the finalizers of user objects,
as the engine allocates no system memory.

### Memory handling

The C API is very similar to QuickJS's, but because the garbage collector
compacts, there are important differences:

1. Explicitly freeing values is not necessary (there is no `JS_FreeValue()`).

2. Objects can move whenever a JS allocation happens. Avoid keeping `JSValue`
   variables in C except briefly between API calls; otherwise use a pointer
   to a `JSValue`. `JS_PushGCRef()` returns a pointer to a temporary opaque
   `JSValue` stored in a `JSGCRef` variable, which the GC updates when
   objects move; `JS_PopGCRef()` releases it:

```c
JSValue my_js_func(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv)
{
        JSGCRef obj1_ref, obj2_ref;
        JSValue *obj1, *obj2, ret;

        ret = JS_EXCEPTION;
        obj1 = JS_PushGCRef(ctx, &obj1_ref);
        obj2 = JS_PushGCRef(ctx, &obj2_ref);
        *obj1 = JS_NewObject(ctx);
        if (JS_IsException(*obj1))
            goto fail;
        *obj2 = JS_NewObject(ctx); // obj1 may move
        if (JS_IsException(*obj2))
            goto fail;
        JS_SetPropertyStr(ctx, *obj1, "x", *obj2);  // obj1 and obj2 may move
        ret = *obj1;
     fail:
        PopGCRef(ctx, &obj2_ref);
        PopGCRef(ctx, &obj1_ref);
        return ret;
}
```

### Standard library

The standard library is compiled at build time into C structures that may
reside in ROM, so instantiating it is very fast and needs almost no RAM. In
this port the library is declared in Aether (`gen/genengine/module.ae`) and
the `gen/` node emits `mquickjs_atom.h` and `mqjs_stdlib.h`; `example-app/gen/`
does the same for the demo's `example_stdlib.h`.

### Persistent bytecode

Bytecode generated by `mqjs` can execute from ROM. Relocate it before
flashing (`JS_RelocateBytecode()`), instantiate it with `JS_LoadBytecode()`
and run it with `JS_Run()`. As with QuickJS, there is no bytecode
compatibility guarantee across versions, and bytecode is not verified before
execution: only run bytecode from trusted sources.

### Math library and floating-point emulation

MQuickJS has its own small math library (`libm.c`), so results are identical
on every platform, and its own floating-point emulator for CPUs without an
FPU.

## The JavaScript dialect

### Stricter mode

MQuickJS supports a subset of JavaScript (mostly ES5) and is always in a
**stricter** mode where some error-prone features are disabled. The stricter
mode is a subset of JavaScript, so code written for it runs unchanged in
other engines.

- Only **strict mode** constructs are allowed: no `with`, and global
  variables must be declared with `var`.
- Arrays cannot have holes. Writing past the end is an error, except
  appending at exactly `length`:
```js
    a = []
    a[0] = 1;  // OK, extends the array
    a[10] = 2; // TypeError
```
  Use a plain object for sparse data. `new Array(len)` works, with elements
  initialized to `undefined`. Array literals with holes (`[1, , 3]`) are a
  SyntaxError.
- Only global (indirect) `eval` is supported, so it cannot see or modify
  local variables: `eval('1 + 2')` is forbidden, `(1, eval)('1 + 2')` is OK.
- No value boxing: `new Number(1)` is not supported (and never necessary).

### Subset reference

- Only strict mode, with emphasis on ES5 compatibility.
- `Array` objects have no holes; numeric properties are always handled by the
  array itself (never forwarded to the prototype); out-of-bound sets are an
  error except at the end; `length` is a getter/setter on the prototype.
- All properties are writable, enumerable and configurable.
- `for in` iterates only over the object's own properties. Prefer `for of`
  over `Object.keys(obj)`.
- `prototype`, `length` and `name` are getter/setters on function objects.
- C functions cannot have their own properties (C constructors behave as
  expected).
- The global object is supported but discouraged: it cannot hold
  getter/setters, and properties created directly on it are not visible as
  global variables.
- The `catch` variable is a normal variable.
- Regexp: case folding is ASCII-only, and matching is by Unicode code point
  (`/./` matches a code point, as with the `u` flag).
- `String.prototype.toLowerCase` / `toUpperCase` handle ASCII only.
- `Date`: only `Date.now()`.

Beyond ES5: `for of` over arrays (no custom iterators yet), typed arrays,
`\u{hex}` in string literals, `Math.imul`/`clz32`/`fround`/`trunc`/`log2`/`log10`,
the `**` operator, regexp `s`/`y`/`u` flags (without Unicode properties),
`codePointAt`, `replaceAll`, `trimStart`, `trimEnd`, and `globalThis`.

## Internals

### Garbage collection

A tracing, compacting garbage collector replaces QuickJS's reference
counting. It allows smaller objects (a few bits of overhead per block) and
avoids fragmentation. The engine has its own allocator and does not use the
C library's `malloc`.

### Values and objects

A value is one CPU word (32 bits on a 32-bit CPU) and holds a 31-bit integer
(1-bit tag), a single Unicode code point, a 64-bit float with a small
exponent (64-bit CPUs only), or a pointer to a tagged memory block.

Objects take at least 3 words (12 bytes on a 32-bit CPU) plus class-specific
data. Properties live in a hash table, at least 3 words each, and standard
library properties may reside in ROM. Property keys are JSValues: a string or
a non-negative 31-bit integer, with string keys interned.

Strings are stored as WTF-8 (UTF-8 plus unpaired surrogates) rather than 8-
or 16-bit arrays. Surrogate pairs are not stored explicitly but are visible
when iterating 16-bit code units, keeping full compatibility with both
JavaScript and UTF-8. C functions can be stored as a single value; most
standard library functions are stored this way.

### Bytecode and compiler

A stack-based bytecode similar to QuickJS's, referencing atoms through an
indirect table, with line/column information compressed using
[exponential-Golomb codes](https://en.wikipedia.org/wiki/Exponential-Golomb_coding).
The parser is close to QuickJS's but avoids recursion, so stack use is
bounded. There is no AST: bytecode is generated in one pass.

### The Aether port

- `ae/*.ae` are leaf translation units; `ae/<pkg>/module.ae` are import-only
  libraries (`ae/mqtypes` holds the struct overlays, `ae/gc`, `ae/coerce`,
  `ae/props`, …). `gen/mqjssources` lists the engine's source set.
- C structs are mirrored as Aether `extern struct` overlays (with bitfields,
  class-id-selected unions and `bitstruct` flag words), checked against the
  C layout by `ae/layout_guard.c`.
- `AGENTS.md` describes the idioms, the build, and the rules for changes.

## Tests and benchmarks

```sh
aeb .tests.ae               # conformance gate: JS suites, low memory (10k/32k heaps),
                            #   GC relocation, bytecode round-trip, REPL, embedding
./run-ae-tests.sh           # Aether unit tests (tests/ae)
./run-valgrind.sh           # memcheck of the built binaries
scripts/diff-upstream.sh    # differential test vs upstream C + Bellard's dtoa/libm tests
scripts/fuzz.sh             # ASAN mutation fuzzer (parser, regexp, numbers, VM)
scripts/bench.sh            # microbench vs upstream C; --octane for Octane
```

`scripts/` builds upstream C (or any earlier commit) in a git worktree under
`target/ref/`. Bellard's [extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)
(Octane and the dtoa/libm test drivers) are downloaded on demand into
`target/extras`, checksum-verified. CI (`.github/workflows/ci.yml`) runs all
of the above except the benchmark, against the Aether and aeb versions in
`ci-pins`.

## License

MIT, see [LICENSE](LICENSE). MQuickJS is copyright Fabrice Bellard and
Charlie Gordon; portions of this port are copyright Paul Hammant. `libm.c`
includes code from Sun Microsystems' fdlibm under its own permissive notice,
preserved in the file.
