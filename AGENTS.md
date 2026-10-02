# Notes for agents working on mquickjs-ae

These notes are short and opinionated. They are written for an agent (or a
human) picking up mid-task, so re-read them at the start of every session.
The maintainers are Paul, Claude and Nic.

## What this repo is

This is a port of [MicroQuickJS](https://github.com/bellard/mquickjs) to
[Aether](../aether/LLM.md). MicroQuickJS is Fabrice Bellard's and Charlie
Gordon's ES5-subset embedded JS engine, under the MIT licence.

- `mquickjs.c`, the ~18 kloc C engine, is **deleted**. The engine is now Aether
  modules under `ae/`, linked with a small set of remaining C files.
- The build runs on [aeb](../aeb/), using the `.build.ae` and `.tests.ae` nodes
  at the repo root.
- Upstream history is the first 45 commits, ending at `7ea5399`. The port
  starts at `c8659eb`. Run `git log --oneline c8659eb^..HEAD` to see the port's
  history alone.

Background reading:

- **`migration_assessment.md`** is the porting guide, idioms included. It is
  the best single doc.
- **`reminaing_c_code_plan.md`** holds scratch working notes. Some of it is
  stale; trust `git log` over it.

## Layout

| Path | What |
|---|---|
| `ae/*.ae`, `ae/<pkg>/module.ae` | The engine in Aether (~170 files). Leaf TUs sit at top level; import-only libraries are packages (`ae/mqtypes`, `ae/coerce`, `ae/props`, `ae/gc`, …) |
| `ae/layout_guard.c` | `_Static_assert`s that the C struct layouts match the Aether overlays |
| `ae/cli_host.ae`, `ae/readline.ae`, `ae/mqjs_dsl/` | The CLI host, line editor, and the declarative stdlib DSL |
| `dtoa.c`, `libm.c` | Third-party C (Bellard's bignum dtoa and the math library). Still C |
| `mqjs.c`, `readline_tty.c` | Remaining CLI glue in C |
| `example.c` | The embedding demo (a custom Rectangle class) |
| `mquickjs_build.c` | Host-side glue for the stdlib-baking generator |
| `gen/` | Generated-header node. Builds the generator (`gen/genengine`, `gen/buildtool`, `stdlib_main.c`) and emits `mquickjs_atom.h` and `mqjs_stdlib.h` |
| `gen/mqjssources/module.ae` | **The single source of truth for the engine's source set.** Both program nodes call `register_engine_c_sources` and `register_engine_sources`. A new engine TU goes here |
| `example-app/` | The embedding-demo program node and its own `gen/` (`example_stdlib.h`) |
| `tests/*.js` | JS conformance suites. They check themselves and `exit(1)` on a mismatch |
| `tests/ae/test_*.ae` | Unit tests for pure-Aether leaf logic (tag math, UTF-8, pc2line, …) |
| `tests/diff/*.js` | Generated corpora for the differential test (numbers, Math) |
| `scripts/` | `bench.sh`, `diff-upstream.sh`, `fuzz.sh` and shared `lib.sh` (worktree builds of any commit, extras download) |
| `ci-pins` | Aether tag and aeb commit that CI (`.github/workflows/ci.yml`) builds |

## Build and test

```sh
aeb .build.ae          # builds ./mqjs (depends on gen/)
aeb .tests.ae          # the conformance gate (builds both programs first)
./run-ae-tests.sh      # unit tests in tests/ae (std.spec)
./run-valgrind.sh      # memcheck of the built binaries (~2 min)
scripts/diff-upstream.sh   # same output as upstream C? + Bellard's dtoa/libm tests
scripts/fuzz.sh            # ASAN mutation fuzzer (-n cases, -s seed)
scripts/bench.sh           # microbench vs upstream C (--ref <commit>, --octane)
```

**The upstream baseline is `7ea5399`**, Bellard's last C commit before the
port (`UPSTREAM_REF` in `scripts/lib.sh`), not the initial release `ebae6ce`:
the repo carries his later fixes, and comparisons against `ebae6ce` show
false differences. `build_ref` in `scripts/lib.sh` builds any commit in a git
worktree under `target/ref/<sha>`: upstream C commits with their own
Makefile, port commits with aeb. `scripts/diff-upstream.sh` must stay 100%
identical; any new divergence needs either a fix or a `SKIP` entry with a
reason. Bellard's extras (Octane, dtoa/libm test drivers) are downloaded on
demand, checksum-pinned, into `target/extras`; they are not vendored.

When checking that a regression test fails without its fix, build the pre-fix
tree separately (for example `build_ref`, or a scratch copy). Do not stash and
rebuild in place: aeb's timestamp cache can keep the fixed objects, and the
test then wrongly "passes without the fix".

The build nodes resolve the Aether tree with `aether_root()` in `.build.ae`.
It reads `$MQJS_AETHER_HOME`, falls back to `/home/paul/scm/aether`, and
passes the result to `c.aether_home(...)`. It deliberately does not read
`AETHER_HOME`, because that names the toolchain aeb itself runs on. The
engine therefore builds against a **dev checkout** of Aether, not just an
installed release. Rebuild that tree (`make` in `../aether`) before
validating against a new Aether version. aeb's own orchestrator needs
Aether 0.758 or later on `PATH`.

`run-ae-tests.sh` runs each `tests/ae/test_*.ae` with
`$AETHER/build/ae run --lib "$AETHER/std:$ROOT"`.

`run-valgrind.sh` runs the release binaries under valgrind memcheck: the JS
suites, the bytecode round-trip, timers, the DSL demo and the embedding
example. Any invalid access, uninitialised read or definite/possible leak
fails it. Run it after changes to allocation, GC roots or the CLI host. For
overflows, an ASAN build (add `-fsanitize=address` to `cflag`/`link_flag` in
a scratch copy of `.build.ae`) pinpoints the faulting access, which valgrind
on `-Os` cannot. Both tools are blind *inside* the JS heap: it is one
`malloc`'d block that the engine sub-allocates, so `tests/test_gc_relocation.js`
and the microbench are what exercise the GC itself.

### Definition of done

`.tests.ae` is the gate. A change is done when it passes. It runs:

- The JS suites: `test_closure`, `test_language`, `test_loop`, `test_builtin`
- Regression tests: `test_gc_relocation` (compacting GC under load),
  `test_rom_write`, `test_regexp_vs_div`, `test_tagged_int`
- Tiny heaps: mandelbrot at `--memory-limit 10k`, and `test_low_memory` at
  32k (OOM must be a catchable error, and the engine must recover)
- A bytecode write and read-back (`-o test_builtin.bin`, then
  `-b test_builtin.bin`)
- `--dsl-demo`
- The embedding checks (`example-app` running `tests/test_rect.js` and
  `tests/test_rect_more.js`)
- The REPL line editor (`tests/test_readline.sh`, via `bash.test`)

(aeb's summary line counts only the last test block, so it says `1/1`. The
per-run results are in `target/.aeb/logs/tests_..log`, and a failing run
still fails the gate.)

For changes to the engine's semantics, also keep `scripts/diff-upstream.sh`
at 100% identical, and run `./run-valgrind.sh` after allocation/GC changes.
Also keep the `tests/ae` unit suites green. If you touch a struct overlay,
`ae/layout_guard.c` must still compile.

For generator changes (`gen/`), the emitted `mquickjs_atom.h` and
`mqjs_stdlib.h` should stay **byte-identical** unless the change is meant to
alter them. That is how the N3 generator port was verified.

## Workflow rules

- **Commit and push straight to `main`. No PRs and no feature branches.** The
  same rule applies to `../aeb` and `../aether-ui`. (`../aether` itself is
  different: it uses PRs and `new_changelogs/` fragments.)
- Keep commits small and focused, one idea each, and leave the gate green after
  every commit.
- When an Aether release or fix drives a change, name the version and issue
  in the subject, matching the existing style:
  - `array_resize: use &field for the in-place shrink (aether 0.315 #890)`
  - `numstr: drop the long-temp E0200 workaround (aether 0.309 #869 fix)`
- When you need a workaround for an Aether bug, **file an ask upstream** in
  `../aether/asks/` (or as an issue) rather than working around it silently.
  Leave a comment at the workaround naming the issue, so it can be removed
  when the fix ships. The `numstr` commit above is that loop closing.

## Porting idioms (what the code actually does)

- **Typed extern-struct overlays instead of raw offsets.** `ae/mqtypes/module.ae`
  mirrors the engine's C structs byte for byte as `extern struct`s with
  bitfields (`gc_mark: uint64_t : 1`, …). Engine code reads them with
  `(p as *JSObject).proto`. The engine-wide sweep (`b451bf1`) moved
  `mem.*`-at-offset access over to these.
- **Unions selected by class_id.** `JSObject.u` is an inline `union` of
  per-class variants (`closure`, `cfunc`, `array`, `typed_array`, `regexp`, …),
  read as `(p as *JSObject).u.array.len` (`7a85a8d`). The file's header
  comment still says "unions are not declared inline". That comment predates
  the change and is stale.
- **`bitstruct` for packed flag words.** `JSPropertyFlags` (`hash_next`,
  `prop_type`) lives in `ae/mqtypes/module.ae` (`df900b5`). The pattern is
  repeated in `ae/parse_escape.ae` and `ae/regexp_flags.ae`.
- **Typed fn-pointer casts for dispatch and callbacks.** Examples:
  - `mem.long_to_ptr(fnptr) as fn(ptr, ptr) -> int` (`ae/vm_finalizer.ae`)
  - Comparator addresses `js_array_sort_cmp as fn(long, long, ptr) -> int`
    (`ae/builtins_iter.ae`)
  - `rqsort` uses typed casts, not the old `std.mem.call_fn3_*` shim
    (`013ff5e`)
- **`std.mem` for whatever isn't overlaid.** This covers `get_uint32`,
  `get_long`, `long_to_ptr` and `ptr_to_long` (there are many call sites).
  JSValues are `long`, and JSWord is 8 bytes.
- **E0200 narrowing.** Aether refuses implicit narrowing, including from an
  inferred `int`. Widen explicitly (`long`) or cast at the site; don't
  scatter casts to make the error go away. See `427f319` and the numstr fix
  above.
- **`try` / `catch` / `panic` instead of `setjmp`/`longjmp`** in the parser
  harness. Don't `return` from inside a `try` body: stash the result in a
  local and return after the block.
- **`const` arrays** hold the static tables (opcode info, char ranges).
- **Public ABI forwarding.** `ae/api_forwarders.ae` is a flat TU that emits
  the bare `JS_*` symbols. The implementation lives in import-only libraries
  such as `ae/coerce`.

## Neighbours

- **`../aether`** is upstream: the compiler, runtime and std. The changelog
  is `CHANGELOG.md` plus `CHANGELOG-archive.md`, with pending entries in
  `new_changelogs/`. Read the changelog range you are crossing before bumping
  the version.
- **`../aeb`** is the build runner. Its `lib/c` supplies `c.program`,
  `c.generated_header` and `c.tests`. aeb pins the Aether that compiles its
  *own* machinery (`AETHER_PIN`/`AETHER_FETCH`) separately from the Aether that
  compiles this engine (`aether_home`). The port can only move to an Aether
  release that aeb can also run on.

## Current state (2026-10-02)

- **Validated end to end on Aether 0.760.0** with aeb at `b0cc057` (the
  versions in `ci-pins`). The gate, `run-ae-tests.sh` (16 suites),
  `run-valgrind.sh` and `scripts/diff-upstream.sh` (23/23 identical to
  `7ea5399`) all pass. Octane runs with correct results throughout. The ASAN
  fuzzer has run 9,000 cases with no crashes.
- **Performance is the open item.** The port runs about 4.5× slower than
  upstream C on Octane and about 7× on the microbench. Opcode dispatch in
  `ae/vm.ae` is a linear `if opcode == …` chain (~124 compares), not a
  jump table, and that is the main lever. Measure with `scripts/bench.sh`.
- **Bugs found by the new harnesses and fixed (October 2026):**
  - VM: missing b/pc reloads after GC-capable calls.
  - Tokenizer: buffer overread.
  - put_field: wrote ROM properties in place.
  - Short-int decode: shifted 64-bit, so computed negatives broke typed
    arrays and coercion.
  - Negative array indices: read and wrote out of bounds.
  - TOK_DEC/TOK_INC were wrong.
  - ReferenceError dropped the variable name.
  - GC finalizers were skipped for merged dead blocks. This one is an
    upstream bug; report it to Bellard.
- What the 0.417 → 0.760 upgrade changed:
  - The build nodes use the `bldr` grammar. `aether_root()` reads
    `MQJS_AETHER_HOME`, not `AETHER_HOME`, because `AETHER_HOME` names the
    toolchain aeb itself runs on.
  - **File-local helpers end in `_`** (Aether #279 emits them `static`). aeb
    no longer links with `--allow-multiple-definition`, so a non-exported
    helper defined in two translation units is a duplicate-symbol error. The
    same name with no trailing `_` collides. Any new private helper in a
    top-level `ae/*.ae` or an `ae/<pkg>/module.ae` needs the trailing `_`.
  - **`@c_callback` marks the bare C symbols** that must keep their names.
    There are two kinds, and each site carries a comment saying which:
    - the C API (`JS_Call` and `JS_ToNumber` for `mqjs.c`/`example.c`, and
      `js_typed_array_constructor` for the generated ROM table);
    - functions forward-declared by an `extern` inside the definer's own
      import closure to break a cycle. Aether rejects import cycles, and
      otherwise renames such a definition to `ae_<name>`.
  - **`utf8_get` / `unicode_to_utf8` / `unicode_from_utf8` / `js_poll_interrupt`**
    lost their C-reserved `__` prefix. Callers `import ae.cutils (...)` /
    `import ae.interrupt_vars (...)` instead of declaring `extern`s.
  - `ae/quickjs` (the public Aether facade) is no longer compiled as an
    engine translation unit. Consumers import it.
  - `tests/ae` moved from the retired `aeocha` to `std.spec`, ending with
    `return spec.run_summary(fw)`.
- **CLI host OS glue is on Aether std.** `Date.now` and `performance.now` use
  `std.os` clocks. `load_file` and the bytecode write use `std.fs`.
  `run_timers` is Aether: `std.os` clock plus the built-in `sleep`. The mqjs
  node therefore declares `aether_caps("fs,os")`, because `--emit=lib`
  refuses gated std modules without it.
- **The VM brackets GC-capable calls the way upstream does.** Each slow-path
  call stores `cur_pc` before it and reloads `b`/`pc` after it, because the
  compacting GC can move bytecode. `tests/test_gc_relocation.js` guards this.
- - Follow-ups (not blocking):
  - Consolidate the identical `_` helper copies (`argv_get_` ×10,
    `gc_push_` ×7, …) into shared modules.
  - Clear the 24 W1001 unused-variable warnings.
  - Port `mqjs.c`/`example.c` so the 3 C-API `@c_callback`s can go.
