# Changelog

## 0.3.1 — 2026-10-31

This release converts actor dispatch and spawned functions from OS kernel processes (`proccreate`)
to lightweight cooperative user-space tasks (`threadcreate`), paired with the Duplex One Ring multiplexed
mailbox architecture.

### Cooperative Task Actors & Multiplexed Ring Mailboxes

- Converted object actor dispatch loops and spawned function instances from `proccreate` (64 KB kernel stack + `rfork`)
  to `threadcreate` (16 KB cooperative task stack).
- Per-thread execution context: upgraded `o9_proc_ctx()` to query `threaddata()` before falling back to `procdata()`,
  guaranteeing each actor task maintains independent call error signals and actor identity when multiple tasks run within the same proc.
- Router worker migration: isolated router worker thread model, eliminating OS process creation during mailbox processing.
- Massive scalability win: object creation memory overhead reduced by 75% per instance (from 64 KB to 16 KB stack)
  and kernel process exhaustion (`NPROC` limit) completely eliminated for object instances.

### Gemini & Dat Protocol Libraries

- **Gemini (`stdlib/gemini.o9`)**:
  - Implements the Gemini protocol (`gemini://`) client envelope and Gemtext (`text/gemini`) document processor.
  - Supports heading hierarchy (`#`, `##`, `###`), links (`=> url [label]`), unordered lists (`*`), blockquotes (`>`), and multi-line preformatted code blocks (```` [alt]```).
  - Provides `GeminiProtocol` for request line formatting and response parsing (`GeminiResponse`), with status code classification (`isSuccess`, `isRedirect`, `isError`).
  - Added end-to-end verification suite in `stdlib/e2e_gemini.o9`.
- **Dat (`stdlib/dat.o9`)**:
  - Implements the Dat / Hypercore protocol for P2P append-only feeds and streaming multimedia.
  - Supports `dat://` URL parsing, 64-hex discovery key derivation and validation.
  - Implements append-only chunk log (`DatFeed`) with BLAKE2b cryptographic integrity verification (`DatBlock.verify()`).
  - Provides multimedia streaming engine (`DatStream`) supporting byte range slicing across block boundaries and chunk seek indexing.
  - Supports Hyperdrive archive indexing (`DatArchive`, `DatEntry`) for multi-file content distribution.
  - Added end-to-end verification suite in `stdlib/e2e_dat.o9`.


## 0.3.0 — 2026-10-28

This release introduces the **One Ring Duplex 9ring** architecture for zero-allocation
in-process CSP routing and sub-microsecond actor messaging, alongside string builtins
and runtime teardown stability improvements.

### Duplex One Ring & Lockless 9ring Architecture

- Replaced heap-allocated `O9RouterOp` linked list and per-message process creation with
  cache-aligned, duplex lockless SPSC 9rings (`O9TRing` submission ring and `O9RRing`
  completion ring) inspired by Harvey's `9ring.h` and 9vm.
- Introduced the **One Ring** architecture: unified in-process object table handles
  (`(gen << 16) | index`) as generation-checked, in-process FIDs. Slots carry compact
  POD descriptors rather than raw C pointers.
- Zero-allocation hot path: eliminated `chancreate`, `mallocz(sizeof(O9SyncWait))`, and
  `proccreate` on the message dispatch and completion paths.
- Dedicated pre-allocated duplex reply channels (`mb->replyc`) per mailbox, bypassing the
  global `o9_pending` table and locks completely during message dispatch and completion.
- Persistent worker process reuse with idle backoff (`sleep(0)`), eliminating kernel
  process table exhaustion during high-volume bursts.
- Added comprehensive benchmark suite `o9c/test/runtime_router_bench.c` (`mk runtime-router-bench`).
- Verified benchmarks on native 9front hardware (`dev9p` amd64):
  - Raw 9ring SPSC core: **60 ns / op** (16.6 million ops/sec).
  - Duplex 9ring CSP round-trip: **5.08 µs / op** (over 202,000 round-trips/sec), a **6.1× speedup**
    over legacy proc-per-message dispatch.
  - End-to-end 9P file IO on `o9irc`: **4,873 full file lifecycle writes/sec** (`open + 9P write + close`)
    in 205 µs/op.

### Builtins & String Manipulation

- Added builtins `chr()` and `slice()` for inline string manipulation and rune inspection
  without external helper allocations.

### Stability & Teardown

- Fixed channel and task teardown race condition and use-after-free in `o9_task_close`.
- Safe mailbox unregistration in 9P router with active worker unblocking via `nbsendp` on error.
- Verified all native 9front test suites (`mk unit-test`, `mk plan9-c-test`, `mk runtime-router-test`)
  and host validation suites (8,189 runtime checks, 0 valgrind leaks, 32 UI tests).

## 0.2.0 — 2026-10-19

This release is focused on making ordinary applications possible without raw
C, manual `spawn`/`await`, or hand-rolled Plan 9 plumbing.

### Application kit

- Added `cli.o9` (`Args`): positional arguments, `-name value` options,
  flags, environment fallbacks, integer options, usage, and test-friendly
  argument loading.
- Added `config.o9` (`Config`): small key/value profiles with load, save,
  defaults, removal, separators, and change tracking.
- Added `service.o9` (`Service`): one-call bootstrap for view services and
  view-less facades.
- Added C-free starting demos: `demo/hello_cli.o9` and
  `demo/hello_service.o9`; the `o9proj` template now produces a C-free
  CLI/config application.

### Text and data

- Added `format.o9` (`Format`): decimal, hex, octal, boolean, newline,
  padding, and zero-padding without `snprint`/`sprint`/`strcat`.
- Added `log.o9` (`Log`): debug/info/warn/error levels, timestamps, console
  or append-file output, and `fatal`.
- Added `result.o9` (`Result`): explicit success/value/error values for APIs
  that prefer ordinary returns over `try`/`fail`.
- Added `rune.o9` (`Runes`): rune count, code point at index, byte offset,
  rune slicing, and rune-to-UTF-8 conversion.
- Added `dir.o9`: typed `DirEntry`, sorted `DirList`, and iterative
  `DirTree.walk`, `copyTree`, and `removeTree`.
- Added `9p.o9` (`NineP`): 9P2000 message framing, type/tag/fid decoding, and
  Rerror/Rread/Rversion builders for custom servers.
- Added `libquickjs/`: a native Plan 9 QuickJS embedding library for lib9p
  servers, with a small `p9js_*` API, native time/math adapters, a host-side
  preprocessing bridge for 6c, and a verified `mk test` smoke test. The APE
  `qjs` CLI and `std`/`os` modules are intentionally out of scope.

### Files, processes, and networking

- Extended `file.o9` with `readn`, `readLine`, `readAt`, `writeAt`,
  `copyTo`, and `copyFrom`.
- Extended `io.o9` with `StreamReader.readLine`, `copyTo`, and the `Lines`
  line-at-a-time reader.
- Extended `process.o9` with `Cmd` (direct argv execution with captured
  stdout/stderr/stdin), `CmdResult`, and `Pipeline`.
- Extended `net.o9` with `NetConn.readLine`, `writeLine`, and `setTimeout`
  using the Plan 9 `/net` control file.

### Concurrency

- Added `sync.o9`: `Mutex`, `WaitGroup`, `Semaphore`, `Once`, and the `Pool`
  concurrency limiter. The primitives use libthread locks/rendezvous rather
  than blocking an object's dispatch loop.

### Host primitives

- Added builtins for common host operations: append, file existence, size,
  directory checks/creation, removal, argv, environment, pid/user/cwd,
  integer conversion, and sleep.

### Compiler

- Resolve imports relative to the file that contains the import line, with
  entry-directory, parent-directory, and cwd fallbacks. A module can keep
  bare neighbour imports such as `import "buffer.o9";` while an application
  imports `stdlib/process.o9` from the project root. File identity is used
  to deduplicate a module reached through both a symlink and its real path.
- Preserve non-ASCII bytes in string literals when generating C. UTF-8 source
  text such as `"héllo"` previously reached generated C with the non-ASCII
  bytes stripped.
- Added the builtins used by the application kit, `sync.o9`, and the new
  stdlib modules.
- Improved facade/typecheck support needed by app services and view
  controllers.

### Validation

- Host suite covers the compiler, runtime, UI/e2e programs, compiler smoke
  tests, and fuzzing.
- Native 9front e2e cases cover the application kit and the new stdlib
  modules.
- The native e2e runner selects `8c`/`8l` on 386 and `6c`/`6l` on amd64,
  so the `libo9.a` archive and generated objects use the same architecture.
- Network loopback cases are verified with an explicit loopback
  configuration on the test image.
