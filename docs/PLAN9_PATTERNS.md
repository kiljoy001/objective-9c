# Plan 9 Source Patterns For The o9 Stdlib

Status: analysis of 9front `/sys/src/cmd` and the standard libraries, focused
on read/write, file, process, network, and service patterns an o9 application
author should not have to rewrite.

The counts below are files under `9front/sys/src/cmd` containing the symbol
(`rg -l`), not total call sites. They are useful as a rough frequency signal.

## Frequency

| Pattern | Files | Proposed o9 entry |
|---|---:|---|
| `ARGBEGIN` / `usage` / `sysfatal` | 526 / many / 536 | `cli.o9` (done), `log.o9` |
| `Bopen`, `Brdline`, `Binit` | 167, 137 | extend `io.o9`; `text.o9` |
| `getfields`, `tokenize` | 65, 117 | `text.o9` |
| `dirread`, `dirstat` | 101, 102 | `dir.o9` |
| `readn`, `write` loops | 117 | `io.o9` streaming helpers |
| `pipe`, `rfork`, `wait` | 119, 216 | `process.o9` pipeline helpers |
| `threadpostmountsrv`, `read9pmsg`, `convM2S` | 19, 24, 29 | `view.o9`/`9p.o9` service helpers |
| `dial`, `announce` | 84, 32 | `net.o9` line/timeout helpers |
| `notify`, `atnotify` | 112 | cleanup conventions; `defer` already exists |
| `fprint(2, ...)` | 843 | `log.o9` |
| `getenv`, `getuser` | 130, 69 | builtins and `process.o9` (done) |

## 1. Command Scaffolding

The 9front shape is:

```c
argv0 = "tool";
ARGBEGIN {
case 'v':
    verbose++;
    break;
case 'o':
    output = EARGF(usage());
    break;
default:
    usage();
} ARGEND
```

with `usage()` and `sysfatal()` for every error. o9 now has `Args` in
`cli.o9`; the remaining gap is a standard **fatal/usage/log** surface so a
program does not repeat `print(...); fail(...)` shapes.

Proposed: `stdlib/log.o9`

```o9
class Log {
    method Log(string name);
    method void info(string msg);
    method void warn(string msg);
    method void error(string msg);
    method void fatal(string msg);   // log, then fail/exit convention
    method void setLevel(int64 level);
    method void toFile(string path);
}
```

## 2. Buffered Line I/O And Fields

`Bopen`/`Brdline`/`Bgetd`/`Bwrite` are the Plan 9 way to read text without
hand-rolling buffers. Then `getfields` or `tokenize` splits records.

o9 has `io.o9` (`Reader`, `Writer`, `IOBuffer`, `StreamReader`), but the common
app pattern is still missing:

- line-at-a-time reading,
- a scanner with lookahead/pushback,
- whitespace and quoted tokenization,
- field access by index,
- writing lines back out.

Proposed: `stdlib/text.o9`

```o9
class Lines {
    method Lines(string path);
    method Lines.fromReader(Reader r);
    method string next();        // "" at EOF
    method bool eof();
    method void close();
}

class Scanner {
    method Scanner(string text);
    method string nextLine();
    method string nextToken();
    method string nextField(string sep);
    method bool hasMore();
}
```

`Config` covers small key/value files; `text.o9` should cover stream-shaped
text.

## 3. Copy And Read/Write Loops

`cat.c`, `cp.c`, `dd.c`, and `tar.c` all contain the same loop:

```c
while((n = read(fd, buf, sizeof buf)) > 0)
    if(write(out, buf, n) != n)
        sysfatal(...);
```

o9 has `File.read`/`write` and `IOBuffer`, but not a streaming copy that does
not load the whole file. The useful abstraction is a `Stream`/`copy` surface:

```o9
Reader r = new Reader(src);
Writer w = new Writer(dst);
r.copyTo(w);
```

or simply:

```o9
File.copyFrom(string src);
File.copyTo(string dst);   // exists, but is whole-file
```

For atomic/private writes, `cp`/`mail`/`history` patterns converge on:

- create temp file in the destination directory,
- write and flush,
- remove/replace the destination,
- preserve mode/owner where appropriate.

Proposed: `stdlib/privdir.o9` / `AtomicFile` (still on the roadmap).

## 4. Directory Traversal And Stat

`ls.c`, `du.c`, `rm.c`, `cp.c`, and `tar.c` all use `dirstat` plus
`dirread`/`dirreadall`. The repeated work is:

- get a typed directory entry,
- distinguish file/dir/symlink,
- format mode/owner/time,
- walk recursively,
- copy or remove a tree.

o9's `File.list()` returns a newline-separated string, which is convenient for
shell-like code but loses the `Dir` fields. A typed entry is the missing piece.

Proposed: `stdlib/dir.o9`

```o9
class DirEntry {
    method string name();
    method string path();
    method bool isDir();
    method bool isSymlink();
    method int64 size();
    method int64 mode();
    method int64 mtime();
    method string owner();
}

class Dir {
    method Dir(string path);
    method list<DirEntry> entries();
    method bool walk(function visit);   // shape depends on function objects
    method bool copyTree(string dest);
    method bool removeTree();
}
```

Start with `entries()` and `DirEntry`; recursive walk/copy can follow.

## 5. Pipelines And Command Results

`rc/havefork.c` and the rest of `rc` implement `pipe` + `rfork` + `dup` +
`exec` + `wait` for pipelines. o9's `Process.run`/`output` covers simple
commands, but not:

- capture stdout, stderr, and status separately,
- feed stdin,
- run a pipeline,
- enforce a timeout.

Proposed: extend `process.o9`

```o9
class Cmd {
    method Cmd(string program);
    method Cmd arg(string a);
    method Cmd stdin(string data);
    method Result run();
}

class Result {
    method int64 status();
    method string out();
    method string err();
}
```

A `Pipeline` can be added after `Cmd`.

## 6. 9P Services

`ramfs.c`, `exportfs`, `webfs`, `cfs`, and the other
`threadpostmountsrv` servers follow the same shape:

- build a `File`/`Tree`,
- set read/write/create/remove callbacks,
- `threadpostmountsrv` (or `srv` + `mount`),
- optional auth,
- serve forever.

o9's `Service` + `ViewController` + `FileTree` already cover the common view
service. The remaining abstractions are lower-level:

- `read9pmsg`/`convM2S` clients (mostly covered by `net_9p_client.o9`),
- a small `Fid`/`Req` wrapper for custom servers,
- `threadpostmountsrv`-style “post and mount” helper,
- auth/factotum plumbing for `serveAppUsers`.

Do not expose raw `Req`/`Fid` to ordinary app authors. Keep a high-level
`Service`/`FileTree` surface and add a low-level module only for real custom
servers.

## 7. Network I/O

`dial` (84 files) and `announce` (32 files) are already wrapped by `net.o9`
(`NetConn`, `NetListener`). The repeated app-level work is:

- read/write a line,
- set a timeout,
- accept loop with per-connection handling,
- close both ends cleanly.

Proposed: extend `net.o9` with `readLine`, `writeLine`, and a timeout-aware
`Conn`/`Lines` adapter. Keep the raw `NetConn` for binary protocols.

## 8. Logging And Errors

`fprint(2, ...)` appears in 843 files; `sysfatal` in 536. Applications still
hand-roll prefixes, timestamps, and exit behavior. A `Log` object with levels
and a `fatal` that uses the o9 error/exit convention would remove that.

Error handling itself already has `try`/`fail`; the gap is presentation and
cleanup, not control flow.

## 9. Auth

`auth_proxy`, `fauth`, and factotum appear throughout network servers. o9's
`net.o9` already has `Factotum`, `FactotumAdmin`, `NetToken`,
`RemoteIdentity`, and `KnownRemotes`. The useful next abstraction is a small
`Auth` facade for servers:

- require a caller identity,
- verify a token,
- map a caller to a role,
- fail with a standard 9P error.

`auth_facade_app.o9` and the AppUser modules are the starting points.

## 10. Cleanup And Lifecycle

`notify`/`atnotify` appear in 112 files because Plan 9 programs must remove
temp files, unmount, and restore state on notes. o9 has `defer`; the missing
piece is a standard **resource scope** convention (close/unmount/remove in
reverse order) rather than more syntax.

A small `Cleanup`/`Scope` object or documented `defer` pattern may be enough.
Do not add a second exception mechanism.

## Priority

1. `text.o9` — line scanners, tokens, fields, quoting.
2. `dir.o9` — typed `DirEntry`, directory listing, walk/copy.
3. `log.o9` — levels, prefixes, fatal convention.
4. Extend `io.o9` — streaming copy, line reader, exact read/write.
5. `process.o9` — `Cmd`/`Pipeline` with stdin/stdout/stderr/status.
6. `privdir.o9`/`AtomicFile` — private and atomic writes.
7. `net.o9` — line/timeout helpers.
8. Low-level `9p.o9` only for custom servers.

## Non-Goals

- Do not expose `Req`, `Fid`, `convM2S`, or `convS2M` to ordinary app code.
- Do not move `rc` parsing, device drivers, or filesystem implementations into
  stdlib.
- Do not replace `bio` semantics with a new buffered-I/O model; wrap the
  common line/field/stream cases.
- Do not add a second error or cleanup mechanism beside `try`/`fail`/`defer`.
