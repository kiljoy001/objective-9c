# Objective-9C Standard Library Roadmap

Status: current snapshot plus near roadmap.

## Ground Rules

- The stdlib is ordinary o9 objects where possible.
- Raw Plan 9 C stays inside `function` helpers and is exposed through
  object methods.
- Compiler/runtime builtins should stay small: core carriers such as
  `string`, `byte`, `double`, `Task<T>`, `tabula`, and collection storage
  are compiler/runtime concerns; richer behavior belongs in stdlib
  objects.
- `MountTable` is the lower-level tabula/syscall-parameter data object.
  `Namespace` is the normal user-facing object for namespace setup.
- App composition is through the shared app facade and Plan 9 namespace
  mounts. The retired `link`/`replace`/`union` object-composition model
  must not come back under stdlib names.
- Thin host primitives may be builtins when they remove repetitive raw C
  from ordinary programs: argv/env, small file checks, integer text, and
  sleep. Richer behavior still belongs in stdlib objects.

## Built Modules

- `stdlib/cli.o9`: `Args`, argv/option/flag/environment parsing for small
  command-line applications. `loadLine()` supports tests and ctl commands.
- `stdlib/config.o9`: `Config`, line-oriented key/value settings with
  comments, trim, custom separators, and ordered save.
- `stdlib/service.o9`: `Service`, the standard `viewController` + `serve`
  bootstrap for 9P view services and view-less facades.
- `stdlib/string.o9`: `String`, an object wrapper over built-in `string`
  with search, trim, case, replace, repeat, and delimiter helpers.
- `stdlib/bytes.o9`: `Bytes`, a length-carrying byte object over o9
  strings.
- `stdlib/buffer.o9`: `Buffer`, a mutable byte/text builder over
  `Bytes`.
- `stdlib/format.o9`: `Format`, a text builder for decimal, hex, octal,
  booleans, padding, and lines.
- `stdlib/log.o9`: `Log`, leveled application logging with timestamps,
  file output, and `fatal`.
- `stdlib/result.o9`: `Result`, explicit success/value/error returns for
  APIs that prefer data over `try`/`fail`.
- `stdlib/collections.o9`: `list<T>`, `array<T>`, and
  `dictionary<T>`, object-style wrappers over existing collection
  carriers.
- `stdlib/file.o9`: `File`, common Plan 9 file, stat, directory, copy,
  move, positional read/write, and byte helpers.
- `stdlib/dir.o9`: `DirEntry`, `DirList`, `Dir`, and `DirTree` for typed
  listings and iterative tree walk/copy/remove.
- `stdlib/path.o9`: `Path`, Plan 9 path cleaning and decomposition.
- `stdlib/io.o9`: `IOBuffer`, `Reader`, `Writer`, `Appender`,
  `StreamReader`, `StreamWriter`, and `Lines` over Plan 9 `Biobuf`.
- `stdlib/process.o9`: `Process`, `Env`, `Cmd`, `CmdResult`, and
  `Pipeline` over argv/env/cwd and command execution.
- `stdlib/sync.o9`: `Mutex`, `WaitGroup`, `Semaphore`, `Once`, and
  `Pool` over libthread locks and rendezvous.
- `stdlib/rune.o9`: `Runes`, UTF-8 count/index/offset/slice/conversion
  helpers.
- `stdlib/9p.o9`: `NineP`, low-level 9P2000 framing and common reply
  builders for custom servers.
- `stdlib/time.o9`: `Time` and `DateTime` over Plan 9 time functions.
  `DateTime()` captures now; explicit calendar construction uses
  `set(year, month, day, hour, minute, second)`.
- `stdlib/random.o9`: Plan 9 libc pseudo-random and entropy-backed
  helpers.
- `stdlib/math.o9`: Plan 9 libc `double` math wrappers plus integer
  `abs`.
- `stdlib/net.o9`: `NetConn`, `NetListener`, `Factotum`, `NetToken`,
  `RemoteIdentity`, and `KnownRemotes`. Line reads/writes and connection
  timeouts are available on `NetConn`. Plan 9-to-Plan 9 secret handling
  defaults to factotum; `Factotum` also exposes local/caller identity
  helpers for facade controller policy. Portable token files stay data.
- `stdlib/namespace.o9`: `Namespace`, the object wrapper over
  `MountTable` for programmatic namespace setup.
- `tabula`: runtime-backed structured data object over libtab with
  `write`, `query`, `read`, `flush`, iteration, and cell access.
- `MountTable`: runtime-backed namespace syscall-parameter data object
  over `schema=mounts` tabulae.

These are validated by native e2e tests in `stdlib/e2e_*.o9` plus
runtime/e2e tests under `o9c/test/`.

## Namespace Contract

In this project, "namespace" means the Plan 9 per-process file namespace:
a composed view built from `bind`, `mount`, `/srv`, and 9P file trees.
Source-level names such as `App.Counter` are modules/type qualifiers,
not the application namespace.

Current application shape:

```text
/mnt/o9/
    clone
    methods
    status
    exports/
    imports/
    <session-id>/
        ctl
        data
        status
```

Objects are actors inside the app process. They are addressed by names in
ctl messages and by in-process handles, not by mounting every object as a
separate namespace subtree.

For namespace setup/isolation:

- use `Namespace` in normal o9 code;
- use `MountTable` when the syscall-shaped `.tab` data needs to be
  saved, transported, inspected, or applied by another program.

## Remaining Roadmap

1. Fill practical gaps in existing stdlib objects based on first real
   applications.
2. Add focused collection helpers only where they do not disturb compiler
   collection carriers.
3. Add higher-level 9P/client helpers after real namespace workflows
   settle.
4. Design the produced-file namespace surface that generalizes
   `exports/` without reviving object-as-fileserver composition.
5. Keep adversarial tests current for:
   private member exposure,
   clone/session result isolation,
   raw C containment,
   `.tab` data-only transport,
   and namespace path confinement.
