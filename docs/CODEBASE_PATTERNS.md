# Whole-Codebase Patterns For o9c

Status: survey of the entire 9front `sys/src` tree, not just `cmd` or the
kernel. The goal is to find the code shapes that o9c can abstract so a new
application is dramatically easier to write, without turning the stdlib into a
copy of libc.

Counts are **files containing the symbol** (`rg -l -F`), not total call sites.
They are a frequency signal, not a LOC estimate.

## Frequency Snapshot

| Pattern | Files | Category |
|---|---:|---|
| `malloc`, `free`, `realloc` | 1635, 1760, 501 | memory/ownership |
| `print`, `fprint(2`, `snprint`, `sprint`, `seprint`, `smprint` | 2280, 974, 793, 613, 340, 233 | formatting/output |
| `read`, `write`, `open`, `close` | 1301, 1211, 1297, 1171 | file/stream I/O |
| `strlen`, `strcmp`, `strncmp`, `strcpy`, `strncpy`, `strcat`, `strchr`, `strstr`, `strdup` | 1124, 1076, 434, 670, 251, 175, 537, 229, 483 | strings |
| `error`, `errstr`, `werrstr`, `rerrstr` | 1338, 503, 308, 88 | error handling |
| `exits`, `sysfatal`, `usage`, `ARGBEGIN` | 823, 682, 500, 578 | CLI/lifecycle |
| `Bopen`, `Brdline`, `Binit`, `Bwrite`, `Bflush` | 190, 154, 250, 101, 167 | buffered I/O |
| `dirstat`, `dirread`, `dirreadall` | 123, 185, 46 | directories |
| `readn`, `seek` | 191, 442 | exact/positioned I/O |
| `qlock`, `qunlock`, `sleep`, `wakeup` | 289, 255, 344, 124 | synchronization |
| `Channel`, `send`, `recv`, `alt`, `proccreate` | 117, 121, 104, 77, 86 | concurrency |
| `rfork`, `pipe`, `exec`, `wait`, `notify` | 256, 138, 998, 191, 154 | process/control |
| `dial`, `announce`, `listen`, `accept` | 98, 49, 35, 28 | networking |
| `srv`, `Req`, `Fid`, `convM2S`, `convS2M`, `threadpostmountsrv` | 338, 381, 86, 35, 33, 21 | 9P/file service |
| `print`, `iprint`, `panic` | 2280, 218, 256 | logging/panic |
| `getenv`, `getuser`, `getwd`, `chdir` | 154, 76, 51, 80 | environment |
| `chartorune`, `runetochar`, `utflen` | 187, 82, 35 | UTF-8/runes |

## 1. Formatting And Text Construction

This is the single largest cross-cutting pattern: `print`, `fprint`,
`snprint`, `sprint`, `seprint`, `smprint`, plus `strcpy`/`strcat` building.

C has `snprint`; o9 has `cat` and `print`, but there is no ergonomic **format
builder**. Every C program spends lines constructing messages, log lines,
paths, protocol fields, and HTML/text fragments.

Proposed: `stdlib/format.o9` (or a `TextBuilder`/`Format` class)

```o9
Format f = new Format();
f.str("user ").str(name).str(" port ").dec(port).nl();
string line = f.text();

// or, if the compiler gains variadic formatting:
string line = format("user %s port %d", name, port);
```

Minimum useful surface:

- `str`, `dec`, `hex`, `oct`, `bool`, `pad`, `width`, `nl`
- `clear`, `text`, `length`
- escaping/quoting helpers

This is the highest-leverage addition. It maps directly to the most common C
shape and is C-free for app authors.

## 2. CLI, Usage, Fatal

`ARGBEGIN`/`ARGEND` (578), `usage` (500), `sysfatal` (682), `exits` (823).

`cli.o9` now covers argv/options. The missing piece is a standard fatal/log
surface:

```o9
Log log = new Log("myapp");
log.info("starting");
log.error("cannot open ", path);
log.fatal("bad configuration");   // log + fail/exit convention
```

Proposed: `stdlib/log.o9` with levels, prefix, optional file, and a `fatal`
that uses the project's error/exit convention.

## 3. File And Stream I/O

`open`/`read`/`write`/`close` are the most common syscalls. `Bopen`/`Brdline`/
`Binit` show that line-oriented text is the dominant high-level shape.

o9 has `File`, `IOBuffer`, `Reader`, `Writer`, and the `readfile`/`writefile`
builtins. The gaps are:

- line-at-a-time reading,
- exact `readn`/`writen`,
- seek/pread/pwrite,
- streaming copy without loading the whole file,
- buffered formatting output.

Proposed extensions:

- `File.readLine()`, `File.readn(n)`, `File.seek`, `File.readAt`, `File.writeAt`
- `Lines` scanner over a file or `Reader`
- `Reader.copyTo(Writer)` and `Writer.copyFrom(Reader)`
- `BufWriter`/`BufReader` for formatted I/O

## 4. Directory Traversal

`dirstat` (123), `dirread` (185), `dirreadall` (46).

`File.list()` returns a newline string, which is convenient for shell-like
code but loses the `Dir` fields. File tools need typed entries and a walk.

Proposed: `stdlib/dir.o9`

- `DirEntry`: name, path, isDir, size, mode, mtime, owner
- `Dir.entries()`
- `walk`, `copyTree`, `removeTree`
- filter helpers (`ext`, `hidden`, `newer`)

## 5. Error Handling And Results

`error` (1338), `errstr` (503), `werrstr` (308), `rerrstr` (88).

o9 has `try`/`fail`, which is the right control-flow abstraction. What is
missing is a **value-shaped result** for APIs that do not want to throw:

```o9
Result r = File.openRead(path);
if(r.failed()) {
    log.error(r.error());
} else {
    Reader rd = r.reader();
}
```

Proposed: `stdlib/result.o9` or additions to `error` handling:

- `Result`/`Error` with message and optional code
- `ok()`, `failed()`, `value()`, `error()`
- `SysError` for `errstr`-style OS errors
- keep `try`/`fail` for exceptional paths

## 6. Synchronization And Concurrency

`qlock`/`qunlock` (289/255), `sleep`/`wakeup` (344/124),
`Channel`/`send`/`recv`/`alt` (117/121/104/77), `proccreate` (86).

o9's actor model covers much of this, but non-actor code and service loops
still need familiar synchronization primitives.

Proposed: `stdlib/sync.o9`

- `Mutex` (`lock`/`unlock`/`with`)
- `WaitGroup`
- `Once`
- `Semaphore`
- `Pool` / worker queue
- `Rendez`-style `wait`/`wake`

Keep channels as the primary message mechanism; do not rebuild them.

## 7. Processes And Pipelines

`rfork` (256), `pipe` (138), `exec` (998), `wait` (191), `notify` (154).

`Process.run`/`output` exists, but app authors need:

- stdin/stdout/stderr separately,
- exit status,
- pipelines,
- timeouts,
- cleanup on error/notes.

Proposed: `Cmd`/`Pipeline`/`Result` in `process.o9`:

```o9
Result r = new Cmd("grep").arg("foo").stdin(data).run();
if(r.ok()) print(r.out());
```

## 8. Networking

`dial` (98), `announce` (49), `listen` (35), `accept` (28).

`net.o9` has `NetConn`/`NetListener`. Missing app-level conveniences:

- `readLine`/`writeLine`
- timeouts
- accept loop with per-connection handler
- TLS/trust setup shortcuts

Proposed: extend `net.o9` with a `Lines` adapter and timeout-aware helpers.

## 9. 9P And File Services

`srv` (338), `Req` (381), `Fid` (86), `convM2S` (35), `convS2M` (33),
`threadpostmountsrv` (21).

`Service` + `ViewController` + `FileTree` now cover the common view service.
Custom servers still need a low-level `9p.o9`:

- `Fcall`, `Fid`, `Req` wrappers
- `read9pmsg`, `convM2S`, `convS2M`
- a `FileServer` base class for custom `walk/open/read/write` trees

Do not expose this to ordinary app authors; it is for real servers only.

## 10. UTF-8 And Runes

`chartorune` (187), `runetochar` (82), `utflen` (35).

o9 strings are UTF-8, but most `String` methods are byte-oriented. Text
editors, terminals, and UI layout need rune-aware offsets and widths.

Proposed: `stdlib/rune.o9` or `Text` methods:

- `runeCount`, `runeAt`, `byteAt`, `sliceRunes`
- `utf8Width` for display
- safe iteration over invalid UTF-8

## 11. Environment, User, And Time

`getenv` (154), `getuser` (76), `getwd` (51), `chdir` (80), `sleep` (344).

These are now covered by builtins (`getenv`, `getuser`, `cwd`, `chdir`,
`sleep`) and `process.o9`/`time.o9`. No new module is needed here.

## Priority: What Makes o9c Instantly More Useful

1. **`format.o9` / `Format` builder** — every program formats text.
2. **`log.o9`** — every program logs and fatals.
3. **`io.o9`/`file.o9` line scanner + seek/readn + copy** — every file tool.
4. **`dir.o9` typed traversal** — every file tool.
5. **`result.o9`** — predictable error handling for non-throwing APIs.
6. **`sync.o9`** — mutex/waitgroup/pool for service code.
7. **`process.o9` Cmd/Pipeline** — shell-like tools.
8. **`net.o9` line/timeout helpers** — network tools.
9. **`9p.o9` custom server kit** — only for filesystem authors.
10. **`rune.o9`** — editors and terminals.

The first four are the "instantly useful" set: they remove the largest amount
of routine C from ordinary tools and services without exposing low-level Plan 9
APIs.

## What Not To Abstract

- Do not reproduce `malloc`/`free` for app authors; o9 objects and strings own
  their storage. Keep explicit buffers/arenas for C interop only.
- Do not reproduce `strlen`/`strcmp`/`strcpy` as separate APIs. `len`, `cmp`,
  `String`, and `Buffer` already cover them.
- Do not expose `Req`/`Fid`/`convM2S` to app code.
- Do not add a second error mechanism beside `try`/`fail`.
- Do not hide 9P or namespace semantics behind a general-purpose web
  framework. Keep Plan 9 shapes visible.

## Suggested Implementation Order

1. `Format` + `Log` (formatting and CLI output).
2. `Lines` + `File` extensions + `Dir`.
3. `Result` + `Cmd`.
4. `Sync` + `Net` helpers.
5. `9p`/`Rune` for specialized apps.

This is deliberately application-first. The kernel survey remains in
`KERNEL_PATTERNS.md`; the 9front command/read-write survey remains in
`PLAN9_PATTERNS.md`.
