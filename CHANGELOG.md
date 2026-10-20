# Changelog

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
