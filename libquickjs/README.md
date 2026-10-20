# libquickjs — native Plan 9 QuickJS for lib9p servers

This directory is a **scaffold** for a native Plan 9 `libquickjs.a`, intended
to be linked into native lib9p servers (not the APE `qjs`/`qjsc` executables
from generated9). It is deliberately not a browser or Node compatibility
runtime.

Status: **host-verified and native-6c verified on generated9 amd64.**
The `mk test` target prints `1+1 = 2` with a native `6c`/`6l` build after
running the `preprocess-native.py` bridge. See
[Native 6c build](#native-6c-build-verified) for the required preprocessing.

## What this is (and is not)

Included:

- The QuickJS engine sources: parser, bytecode compiler, interpreter, GC,
  BigInt, RegExp, Unicode tables, dtoa, and the C API.
- A small native platform layer (`p9quickjs.[ch]`, `p9time.c`, `p9math.c`,
  `plan9.h`, `compat/`).
- An embedding API for lib9p servers: `p9js_new`, `p9js_eval`, `p9js_free`,
  plus an optional `print` global and interrupt/memory/stack hooks.
- A low-level smoke test using `JS_NewRuntime`, `JS_NewContext`, `JS_Eval`,
  `JS_ToCString`, and the matching free calls.

Intentionally omitted:

- `qjs.c`, `qjsc.c`, `quickjs-libc.c`, `quickjs-libc.h` (the APE CLI and its
  `std`/`os` modules, event loop, workers, filesystem/process access).
- `run-test262.c`, `unicode_gen.c`, tests, examples, REPL, release tooling.
- APE-only `plan9.c`, `poll9.c`, `poll9.h`, and the generated9 `mkfile`
  (which builds `qjs`/`qjsc` with `pcc`).
- Workers, Atomics, shared-memory threads, and dynamic C modules. QuickJS is
  built with `PLAN9`, which disables `CONFIG_ATOMICS`, `DIRECT_DISPATCH`, and
  APE-specific code paths.
- Any `std`/`os` module surface. A host that wants files, processes, or
  timers must implement those itself and expose them explicitly.

The result is an engine with ECMAScript built-ins (Object, Array, String,
Number, Math, Date, JSON, RegExp, Map/Set, Promise, TypedArrays, BigInt,
etc.) but **no ambient filesystem or process authority**.

## Source provenance

Engine version: **QuickJS 2026-06-04**.

- Upstream: <https://bellard.org/quickjs/>
- Tarball: <https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz>
- SHA-256: `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`
- License: MIT, Copyright Fabrice Bellard and Charlie Gordon. The upstream
  `LICENSE` is copied into `engine/LICENSE` by the vendor step.

The exact sources are taken from the generated9 Plan 9/APE port at
`sys/src/cmd/quickjs` (branch `gen`), not from a hand-written copy of the
upstream tree. generated9 carries the compiler and platform adaptations
described below. The files copied by `vendor.rc` are:

| File | Role |
| --- | --- |
| `quickjs.c` | engine, parser, compiler, interpreter, GC |
| `quickjs.h` | public C API; contains the Plan 9 value-construction helpers |
| `quickjs-atom.h` | predefined atoms |
| `quickjs-opcode.h` | bytecode opcodes |
| `cutils.c`, `cutils.h` | utility/container code; Plan 9 includes and float helpers |
| `libregexp.c`, `libregexp.h`, `libregexp-opcode.h` | RegExp engine |
| `libunicode.c`, `libunicode.h`, `libunicode-table.h` | Unicode tables and helpers |
| `dtoa.c`, `dtoa.h` | number ↔ string conversion |
| `list.h` | intrusive lists |
| `LICENSE` | upstream MIT notice |
| `math/*.c`, `math/*.h`, `math/COPYRIGHT` | musl 1.2.5 double-precision math and tables |

`math/` contains 49 C files and 6 headers. It comes from musl 1.2.5
(<https://musl.libc.org/>, MIT); generated9 retains the musl copyright and
per-file notices in `math/COPYRIGHT` and the source files. Native Plan 9 libc
lacks several C99 functions (`acosh`, `asinh`, `atanh`, `expm1`, `log1p`,
`log2`, `cbrt`, `round`, `trunc`, `scalbn`, and `fmin`/`fmax`), and JavaScript
needs IEEE 754 domain, signed-zero, and subnormal behavior. The musl routines
are therefore part of the intended library, not an accidental extra.

Local engine changes inherited from generated9 (relative to upstream
2026-06-04), and why they matter here:

- `PLAN9` branches replace `fenv.h`, `__builtin_frame_address`, and
  `alloca`; `p9_init`, `p9_malloc`/`p9_realloc`/`p9_free`/`p9_msize` are
  used instead. The stack-overflow probe uses a local variable.
- `DIRECT_DISPATCH` is disabled and the interpreter uses the switch form.
- Value constructors, closure bitfields, flexible-array spellings, and the
  RegExp stack field are written in forms accepted by the 6c/pcc family.
- Hex float literals and some negative-zero/NaN/Infinity constants are
  expressed through integer bit patterns to avoid compiler constant-folding
  differences.
- `js_alloca` becomes checked heap allocation; the corresponding `js_freea`
  calls are added.
- `getTimezoneOffset` has a `PLAN9` branch in generated9. **This scaffold
  changes one line** so native builds use `localtime_r` and `tm_gmtoff`
  instead of requiring a `struct tm`-based `gmtime`/`mktime` that would
  collide with Plan 9's `Tm` API. See `patches/` and `vendor.rc`.
- `math/libm.h` declares unused `long double` helpers. Native 6c has no
  `long double`, so `vendor.rc` rewrites `long double` to `double` in that
  header only. The vendored double-only routines do not use those helpers;
  see `patches/0002-native-libm-no-long-double.patch`.

The generated9 source hashes (before the one-line native time delta) are
recorded in `patches/SOURCES.sha256` for auditing.

## Compiler prerequisites

### 1. The 6c unordered-comparison fix is required

generated9's notes are correct: QuickJS on amd64 needs a 6c fix for IEEE
unordered comparisons. `sys/src/cmd/6c/txt.c:gopcode()` must lower `==` and
`!=` on `float`/`double` through `UCOMISS`/`UCOMISD` and test **PF** (parity /
unordered), not only ZF. The generated9 patch:

- selects an ordered branch (or its unordered complement) for `<`, `<=`, `>`,
  `>=` with the `OLO/OLS/OHS/OHI` forms, and
- for `OEQ`/`ONE` emits `JPS` (jump if parity set) before `JEQ`/`JNE`.

Without it, `NaN === NaN` and related comparisons can be wrong. generated9's
`quickjs/mkfile` even builds `qjs` and then runs:

```rc
./$O.qjs -e 'if (NaN === NaN) throw Error("rebuild and install /sys/src/cmd/6c, then mk clean")'
```

as a build-time guard.

**Upstream 9front 6c needs the same patch.** The 9front tree inspected for
this scaffold has `AUCOMISS`/`AUCOMISD` and `AJPS` support in 6c/6l, but its
`gopcode()` still emits only `JEQ`/`JNE` for `OEQ`/`ONE`; it does not emit the
`JPS` parity check. Apply `patches/0003-6c-nan.patch` (or the equivalent
generated9 change) to 9front's `6c`, rebuild `6c` and install it, then rebuild
QuickJS objects from clean. The 6l opcode table already has `AJPS`, so no 6l
change is known to be required.

The fix is a compiler prerequisite, not a library source change. If you build
with `pcc` (APE) you are on generated9's tested path; native `6c` is the path
this scaffold targets.

### 2. Native headers and compiler features

Native Plan 9 6c has no `stdint.h`, `inttypes.h`, `stdlib.h`, `string.h`,
`assert.h`, `math.h`, `time.h`, `sys/time.h`, `float.h`, or `setjmp.h` as
separate C99 headers. `compat/` supplies minimal versions. It assumes the
**amd64** ABI (`long`/pointer/`size_t` are 64-bit; `INTPTR_MAX` is 64-bit).
A 32-bit build needs a reviewed `compat/stdint.h`, `compat/stddef.h`, and
attention to Plan 9's 64-bit `usize` arguments to libc memory functions.

The engine is compiled with `-DPLAN9`. generated9's workarounds for
bitfields, flexible arrays, designated initializers, `__attribute__`, and
`long long` are retained. `plan9.h` neutralizes GCC attributes and builtins and
provides the Plan 9 allocation and math shims.

## Vendoring the engine

The engine is **not** checked in here; it is 2.6 MB of upstream code plus the
math directory. Populate it from a generated9 checkout:

```rc
cd /path/to/objective-9c/libquickjs
rc vendor.rc /path/to/generated9/sys/src/cmd/quickjs
```

`vendor.rc`:

- copies only the engine files listed above into `engine/` and `math/`,
- copies `LICENSE`, `VERSION`, and the provenance hashes,
- applies the one-line native time delta with `sed` (no `patch` dependency),
- rewrites `long double` to `double` in `math/libm.h` for 6c,
- refuses to overwrite a non-empty `engine/quickjs.c` unless run with
  `-f` (force), so an accidental vendor does not discard local experiments.

`engine/` and `math/` are ignored by git. If you prefer a self-contained
source drop, remove those ignore rules after reviewing the license and size.
Do not copy `qjs.c`, `qjsc.c`, or `quickjs-libc.c` into this library.

## Native 6c build (verified)

Native 6c works, but it needs a host preprocessing bridge: 6c supports
`#ifdef`/`#ifndef`, but not `#if`, `#elif`, `defined`, token pasting (`##`),
`inline`, `[static N]` array parameters, or `__attribute__` syntax.

The crash originally seen in `JS_NewRuntime` was not a 6c codegen bug. Plan 9
amd64 has 32-bit `long` and 64-bit pointers; native libc's `memset` takes
`usize`, which is `unsigned long long`. The compat headers had defined
`size_t`/`intptr_t` as `unsigned long`/`long`, so 6c wrote only 4 bytes of
the length argument. Native libc read 8 bytes, and the stale upper half
produced a huge `REP STOSL` that walked up the stack. `compat/stddef.h` and
`compat/stdint.h` now use `long long`/`unsigned long long` for machine-word
types.

Prepare and build:

```rc
cd libquickjs
python3 preprocess-native.py \
    --source /path/to/generated9/sys/src/cmd/quickjs \
    --plan9 /path/to/9front
mk
mk test
```

Expected output:

```text
1+1 = 2
```

`preprocess-native.py` vendors the engine/math sources, applies the native
time and libm deltas, runs the host `cpp` over every translation unit with the
compat headers and 9front headers, strips `inline`/`[static N]`, and adds the
two 6c `abort()` return fallbacks. The result is plain C for 6c. This is a
build bridge, not the long-term source form; keep the raw engine under
`vendor.rc`/generated9 as the source of truth.

The native library uses `6c`/`6l`, native libc, and native `libstdio`. It
does **not** use APE headers, APE libraries, or `pcc`. generated9's APE/pcc
tree is only a reference for engine behavior and provenance; it is not linked
into this library.

## Build

Native 6c needs the preprocessing bridge.  Do the preprocessing in a
throwaway copy so the tracked raw `p9quickjs.c`/`test.c` are not replaced by
generated output:

```rc
cp -a /path/to/objective-9c/libquickjs /tmp/libquickjs-build
cd /tmp/libquickjs-build
python3 preprocess-native.py \
    --source /path/to/generated9/sys/src/cmd/quickjs \
    --plan9 /path/to/9front
mk
mk test
```

On a native Plan 9 amd64 host with a patched 6c installed.  The generated
`engine/`, `math/`, `p9*.c`, and `test.c` in the throwaway copy are plain C
for 6c.  Keep the repository copy as the raw scaffolding.  `mk`/`mk test`
use native `6c`/`6l`, `libc.a`, and `libstdio.a`; no APE library is linked.
The host `cpp` in `preprocess-native.py` is only a text preprocessor and emits
plain C before the native build.

The mkfile builds `libquickjs.a` from:

- `engine/quickjs.c`, `engine/cutils.c`, `engine/libregexp.c`,
  `engine/libunicode.c`, `engine/dtoa.c`
- `p9quickjs.c` (allocation, time seed, print sink, error reporting,
  interrupt handler, embedding API)
- `p9time.c` (`gettimeofday`, `struct tm`, `localtime_r`/`gmtime_r`)
- `p9math.c` (signbit, `__builtin_clz`/`ctz`, `lrint`, `fmin`/`fmax`, and
  optional approximate fallbacks)
- `math/*.c` (musl double-precision routines)

The engine uses native `snprintf`/`vsnprintf`, so final links must include
`/$objtype/lib/libstdio.a` after `libquickjs.a`. The `mk test` target does
this explicitly; a lib9p server must do the same.

`$CC`, `$AR`, `$LD`, and `$O` come from `/$objtype/mkfile`; override on the
command line if needed, for example:

```rc
mk 'CC=pcc' 'LD=pcc' 'AR=ar'
```

The library is native code for the host object type. It is **not** an APE
archive and should not be linked into APE programs that expect APE headers.

### First native test

```rc
cd /sys/src/cmd/6c && mk && mk install   # after applying the NaN patch
cp -a /path/to/objective-9c/libquickjs /tmp/libquickjs-build
cd /tmp/libquickjs-build
python3 preprocess-native.py \
    --source /path/to/generated9/sys/src/cmd/quickjs \
    --plan9 /path/to/9front
mk && mk test
```

Expected output from `test`:

```
1+1 = 2
```

The test intentionally uses the low-level API, not the convenience wrapper:

```c
rt = JS_NewRuntime();
ctx = JS_NewContext(rt);
v = JS_Eval(ctx, "1+1", 3, "<test>", JS_EVAL_TYPE_GLOBAL);
s = JS_ToCString(ctx, v);
printf("1+1 = %s\n", s);
...
JS_FreeContext(ctx);
JS_FreeRuntime(rt);
```

If that passes, try the embedding API in a lib9p server:

```c
P9JS *js = p9js_new(nil);
char *s = nil;
if (p9js_eval(js, "6*7", nil, &s) == 0) {
    fprint(2, "6*7 = %s\n", s);
    free(s);
}
p9js_free(js);
```

(Include `p9quickjs.h`, not `quickjs.h`, from a server that already includes
`<libc.h>`; `p9quickjs.h` deliberately forward-declares the QuickJS types and
does not pull the engine's compatibility headers into the server translation
unit.)

## API

`p9quickjs.h`:

```c
typedef struct P9JS P9JS;

typedef struct P9JSOptions {
    unsigned long memory_limit;    /* 0: P9JS_DEFAULT_MEMORY_LIMIT */
    unsigned long max_stack_size;  /* 0: P9JS_DEFAULT_MAX_STACK_SIZE */
    int  (*interrupt)(void *opaque);          /* nonzero aborts execution */
    void (*output)(void *opaque, const char *s, unsigned long n);
    void (*error)(void *opaque, const char *s, unsigned long n);
    void *opaque;
} P9JSOptions;

P9JS *p9js_new(const P9JSOptions *opts);
int   p9js_eval(P9JS *js, const char *src, const char *filename, char **result);
void  p9js_free(P9JS *js);

struct JSContext *p9js_context(P9JS *js);   /* for host-installed bindings */
struct JSRuntime *p9js_runtime(P9JS *js);
```

`p9js_eval` returns `0` on success and `-1` on a JS exception or allocation
failure. On success, if `result` is non-NULL it receives a `malloc`-allocated
UTF-8 string of the completion value; the caller frees it with `free`.
`filename` may be NULL (`"<eval>"` is used). The context has a global
`print(...)` that writes to the `output` sink (or fd 1), with values converted
through `JS_ToCString`.

Defaults: 16 MiB memory limit and 256 KiB JS stack limit. These are starting
points for a 9P server, not a security boundary. A server should also impose
its own request size, wall-clock, and per-connection quotas.

## What is stubbed or approximate

`p9time.c` is a real adapter, not a stub:

- `gettimeofday` uses `nsec()` (`/dev/bintime`) and falls back to `time(nil)`
  if the file is unavailable. The engine's Date and Math.random seeding call
  it.
- `localtime_r` loads the `local` timezone with `tzload("local")`, converts
  through `tmtimens`, and fills the C `struct tm` fields including
  `tm_gmtoff` and a copied `tm_zone[16]`.
- `gmtime_r` does the same with a nil timezone (GMT).
- No `mktime`/`timegm` is provided; the engine does not use them after the
  native time delta.

`p9math.c` provides the pieces the musl math set does not:

- `p9_signbit`, `lrint`, `fmin`, `fmax`, `__builtin_clz`/`ctz` and the
  64-bit variants.
- Optional approximate fallbacks for `acosh`, `asinh`, `atanh`, `expm1`,
  `log1p`, `log2`, `cbrt`, `round`, `trunc`, and `scalbn`, compiled only with
  `-DP9MATH_FALLBACK`. These are enough to link and run basic scripts but are
  **not** conformance-grade near domain boundaries. The default mkfile uses
  the musl sources instead; do not enable the fallback in production. To try
  a math-less bootstrap build (for example while porting 6c), use:

  ```rc
  mk 'MATHFILES=' 'CFLAGS=-c -DPLAN9 -DP9MATH_FALLBACK -I. -Icompat'
  ```

Not implemented and intentionally absent: `std`/`os`, `std.loadFile`,
`os.platform`, file descriptors, timers/event loop, workers, Atomics,
dynamic modules, `std.urlGet`, and terminal handling. Those belong in the
embedding server, using lib9p/Plan 9 primitives, with explicit policy.

## Verification performed here

Host checks (Linux + plan9port):

- Inspected `/tmp/opencode/generated9/sys/src/cmd/quickjs` and its `mkfile`,
  `README.Plan9`, `UPSTREAM`, `plan9.[ch]`, `poll9.[ch]`, and `math/`.
- Downloaded upstream QuickJS 2026-06-04 and verified SHA-256
  `b376e839…70ad2a`.
- Diffed generated9 against upstream to classify engine vs APE/CLI changes
  (details in `patches/`).
- Inspected generated9's 6c `txt.c:gopcode()` NaN fix and compared it with the
  current 9front 6c, which lacks the `JPS` parity check.
- Inspected native Plan 9 headers/libc for available math, `nsec`, `Tm`,
  `tzload`, `qsort`, `strtod`, `snprintf`, and stdio.
- Ran `rc vendor.rc` against the generated9 checkout in a scratch copy: the
  copy set, the one-line `sed` delta, and the provenance file all worked.
- Ran a plan9port `mk -n` dry run with a stub object-type mkfile: the mkfile
  parses, expands all 49 math objects, builds the archive command, and emits
  the `test` link/run commands.
- Ran host `gcc -fsyntax-only` (with `-nostdinc`, the `compat/` headers, and
  minimal Plan 9 header stubs) over `quickjs.c`, `cutils.c`, `libregexp.c`,
  `libunicode.c`, `dtoa.c`, all 49 `math/*.c`, `p9quickjs.c`, `p9time.c`,
  `p9math.c`, and `test.c`. All passed. This checks C syntax and the QuickJS
  API calls, **not** 6c semantics or native ABI.

Native 6c checks on generated9 amd64:

- `python3 preprocess-native.py --source /path/to/generated9/sys/src/cmd/quickjs --plan9 /path/to/9front`
- `mk nuke && mk && mk test`
- output: `1+1 = 2`
- additional scripts against the same `libquickjs.a` returned
  `ABC [1,2,3]` and `1,2,3:bb`

**Not verified:** 32-bit 386 ABI, a pure raw-source build without the
preprocessing bridge, full Test262 conformance, and browser/event-loop
integration. A native 6c build requires the generated9 6c unordered-
comparison fix.

## Remaining porting risks

1. **6c NaN fix must be installed.** Without it, comparisons and Date/Number
   behavior are unreliable. Rebuild all objects after installing 6c.
2. **6c vs pcc source forms.** Native 6c needs the host preprocessing
   bridge because it lacks `#if`, `##`, `inline`, and `__attribute__`. The
   preprocessed amd64 build is verified; a raw-source 6c build is not
   supported.
3. **Musl math under 6c.** The double-precision math set now compiles and
   links under 6c as part of `mk test`. It has not been deeply validated near
   domain boundaries or against a full JavaScript conformance suite.
4. **Header ABI.** `compat/` assumes amd64. It uses 64-bit `size_t`/`long`.
   `memcpy`/`memset` in native libc take Plan 9 `usize` (also 64-bit on
   amd64); a 32-bit port needs a deliberate prototype review.
5. **stdio.** The engine calls `snprintf`/`vsnprintf` for error and Date
   formatting, so `libstdio.a` is in the `#pragma lib` set. If a server avoids
   libstdio, those calls need a replacement.
6. **`p9_malloc` accounting.** The engine uses a header-prefixed allocator to
   report `msize` on APE. It adds overhead and is independent of Plan 9
   `msize`; a future simplification can use native `msize` if the engine
   patch is adjusted.
7. **Interrupts.** `JS_SetInterruptHandler` is polled at bytecode boundaries.
   A native tight C loop or a blocked server read still needs server-level
   timeouts; the JS interrupt handler cannot preempt a blocked syscall.
8. **Time.** `localtime_r` depends on `tzload("local")`; environments without
   `/env/timezone` or the zoneinfo files fall back to GMT. `gettimeofday`
   returns a synthesized value rather than failing, because QuickJS does not
   check its return value when seeding `Math.random`.
9. **No module loader.** `import`/`require` are not wired. A lib9p host that
   wants modules must install a `JS_SetModuleLoaderFunc` and define its own
   resolution/authority policy. Dynamic C modules are unavailable.
10. **No independent test262 run.** This scaffold does not claim full
    conformance. Once the smoke test passes, run the upstream language tests
    with a native test driver, not the APE `qjs` binary.
11. **Not thread-safe by design.** A QuickJS `JSRuntime` is not safe to share
    between threads, and `p9time.c` caches the local `Tzone` without a lock.
    Give each concurrent lib9p worker its own `P9JS`, or serialize access.

## Files

```
libquickjs/
  README.md              this file
  mkfile                 native libquickjs.a + test
  plan9.h                engine-facing Plan 9 compatibility header
  p9quickjs.h            public embedding API (forward declarations only)
  p9quickjs.c            alloc/time/print/error/interrupt/memory hooks + API
  p9time.c               gettimeofday, struct tm, localtime_r/gmtime_r
  p9math.c               signbit/clz/lrint/fmin/fmax + optional fallbacks
  test.c                 low-level JS_NewRuntime/JS_Eval/1+1 smoke test
  vendor.rc              copies engine + math from generated9, applies delta
  compat/                minimal C99 headers for native 6c
  patches/               provenance hashes and the native time delta
```

## License

The QuickJS engine and musl math sources retain their MIT notices; see
`engine/LICENSE` and `math/COPYRIGHT` after vendoring. The scaffold files in
this directory are new contributions to this repository and follow the
repository's licensing. No third-party code is relicensed here.
