# Stdlib Patterns From Real o9 Programs

Status: analysis of the programs built so far, with proposed stdlib entries.
This complements `docs/STDLIB_PLAN.md`; it does not replace the roadmap.
For the corresponding survey of 9front `/sys/src/cmd` read/write, file,
process, network, and service patterns, see `docs/PLAN9_PATTERNS.md`.

## Scope

Reviewed:

- `o9irc`: `irc.o9`, `ircfs.o9`, `gui.o9`, `history.o9`
- `o9mail`: `mailfs.o9`, `upas-sync.o9`
- `objective-9c/demo`: draw demos, `syslogmon`
- `objective-9c/grid`: `o9mutlib.o9`, `o9mutctl.o9`, `o9mutreplay.o9`,
  `zabbix_agent.o9`
- `o9-testing`: `stdlib/appuser.o9`, `stdlib/property.o9`,
  `grid/house/house.o9`
- existing `stdlib/*.o9`

The goal is not to move application logic into the standard library. It is
to identify repeated *scaffolding* and *data-shape* work that every program
currently rewrites.

## Implemented In This Pass

- `stdlib/cli.o9`: `Args` for argv, options, flags, environment, and usage.
- `stdlib/config.o9`: `Config` for small key/value profiles with ordered
  save, comments, trim, and custom separators.
- `stdlib/service.o9`: `Service` for the standard `viewController` + `serve`
  bootstrap.

These are covered by `stdlib/e2e_cli.o9`, `stdlib/e2e_config.o9`, and
`stdlib/e2e_service.o9` in both the host gate and the native e2e suite. The
new `docs/APP_DEVELOPER.md` page collects the quickstarts and program index.

## Inventory

| Program | Role | Repeated shape |
|---|---|---|
| `o9irc/ircfs.o9` | 9P service | argv parsing, `ViewController`, `FileTree`, `MountTable`, `serve()`, profile load/save, private history files |
| `o9irc/irc.o9` | terminal client | argv parsing, `ProcessArgRaw`, `String*Raw`, usage text |
| `o9irc/gui.o9` | Rio UI + 9P view | argv parsing, raw string helpers, event loop, window lifecycle |
| `o9irc/history.o9` | bounded transcript archive | ad-hoc file read/write, FNV path naming, zlib blob format |
| `o9mail/mailfs.o9` | 9P service | argv parsing, `ViewController`, `FileTree`, `serveAppUsers`, private-root file helpers, tab-separated records |
| `o9mail/upas-sync.o9` | sync tool | argv parsing, line/field parsing, file writes |
| `demo/syslogmon` | watcher/service | tail-read, tabula schema, logging, `serve()` |
| `grid/o9mutlib.o9` | mutation engine | 50 `create()` calls, directory scaffolding, tab-separated manifests, `try` error handling |
| `grid/o9mutctl.o9` | CLI control tool | `Process` object, command dispatch, usage strings, option scanning |
| `grid/zabbix_agent.o9` | tiny CLI | read key, dispatch, write reply |
| `o9-testing/stdlib/appuser.o9` | app identity/auth | public profile, challenge, enroll, factotum RSA |
| `o9-testing/stdlib/property.o9` | property tests | generators, replay, shrinking |
| `o9-testing/grid/house/house.o9` | service/UI app | `FileTree`/`MountTable`, field validation, record serialization |

## Pattern 1: CLI / Service Bootstrap

Evidence:

- `ircfs.o9`, `gui.o9`, `irc.o9` still use `ProcessArgcRaw` /
  `ProcessArgRaw` plus `spawn`/`take`.
- `o9mutctl.o9` already uses the newer `Process` object and is much cleaner.
- `mailfs.o9`, `syslogmon`, `auth_facade_app.o9` all end in
  `viewController(...)` + `serve()`, or `serveAppUsers(...)`.
- `usage:` strings and ad-hoc option scanning appear in `ircfs`, `irc`,
  `mailfs`, `zabbix_agent`, `o9mutctl`.

Proposed entry: `stdlib/cli.o9` and/or `stdlib/service.o9`

```o9
class Args {
    method Args(int64 first);       // first user arg (usually 2)
    method int64 count();
    method string at(int64 index);
    method string opt(string name, string def);
    method bool flag(string name);
    method void usage(string text); // print and return
    method bool require(int64 n, string usageText);
}

class Service {
    method Service(string name);
    method int64 run(ViewController view);
    method int64 runWithUsers(ViewController view, AppUserRSAProvider provider);
}
```

The service entry should own the common order: service name, `viewController`,
optional auth provider, `serve`, and usage/exit behavior. Apps should not
each rediscover that sequence.

## Pattern 2: Config / Field Records

Evidence:

- IRC: `IrcProfileLoadRaw`, `IrcProfileSaveRaw`
- mail: `MailAccountFieldRaw`, tab-separated account profiles
- house: `HouseRecordRaw`, `HouseSpecRaw`, `snprint("%s\t%s\t...")`
- grid: manifests and task records are tab-separated lines
- GUI/IRC: raw `StringFieldRaw`, `StringSliceRaw`, `StringTrimRaw`,
  `StringStartsWithRaw`

Proposed entry: `stdlib/config.o9`

```o9
class Fields {
    method Fields(string line, string sep);
    method int64 count();
    method string at(int64 index);
    method string rest(int64 index); // rejoin remaining fields
    method string join(string sep);
}

class Config {
    method Config(string path);
    method string get(string key, string def);
    method bool set(string key, string value);
    method bool load();
    method bool save();              // atomic temp + rename
    method int64 count();
}
```

This is deliberately small. Structured multi-row data stays in `tabula`;
`Config` is for the one-line key/value and tab-separated records that real
programs keep in `$home/lib` and private directories.

## Pattern 3: Private / Atomic File Storage

Evidence:

- `mailfs.o9` has a complete private-root wrapper:
  `MailPrivateDirRaw`, `MailPrivateWriteRaw`, `MailPrivateReadRaw`,
  `MailPrivateRemoveRaw`, `MailPrivateExistsRaw`.
- `history.o9` writes `0600` files with `create(..., OWRITE|OTRUNC, 0600)`.
- IRC profile saves also need 0600 and atomic replacement.
- `grid/o9mutlib.o9` repeats `create(path, OREAD, DMDIR|0755)` for every
  directory level.

Proposed entry: `stdlib/privdir.o9`

```o9
class PrivateDir {
    method PrivateDir(string path);
    method bool ensure();                  // 0700, mkdir -p
    method string read(string name, int64 max);
    method bool write(string name, string data);   // 0600, temp+rename
    method bool append(string name, string data);
    method bool remove(string name);
    method bool exists(string name);
    method string list();
}
```

Keep `Vault` for encrypted storage. `PrivateDir` is the plaintext 0600
working directory used by mail, history, profiles, and keys.

## Pattern 4: Bounded Log / History Buffer

Evidence:

- IRC `statuslog` truncates with `StringSliceRaw` to 32768 bytes.
- `o9irc/history.o9` implements bounded snapshot files and indexes.
- `syslogmon` keeps a bounded tail and tabula rows.
- `grid` keeps journals and reports.

Proposed entry: `stdlib/logbuf.o9`

```o9
class LogBuffer {
    method LogBuffer(int64 limit);
    method bool append(string line);
    method string text();
    method string tail(int64 bytes);
    method int64 lines();
    method bool save(string path, int64 mode);
    method bool load(string path, int64 max);
}
```

The compressed `o9h` archive format in `history.o9` can stay application
specific; `LogBuffer` should standardize the plain bounded-text case.

## Pattern 5: UI Application Loop

Evidence:

- Every `demo_draw_*.o9` repeats:
  `new DrawWindow(...)`, `open()`, `while(running)`, `nextEvent`,
  `routeEvent`, `update/repaint`, `close`.
- `o9irc/gui.o9` has its own `DrawWindow` loop with `poll`/`nextEvent`.
- `house.o9` combines a view/service with a UI loop.
- `DrawVisualProbe.show()` repeats the same shape.

Proposed entry: `stdlib/uiapp.o9` (or a `DrawApp` class in `draw.o9`)

```o9
class UIApp {
    method UIApp(string title, int64 width, int64 height);
    method bool open();
    method void onEvent(DrawEventLoop event);  // override
    method int64 run();                        // open/loop/close
    method void close();
}
```

At minimum this should own cleanup and the `q`/Escape exit convention that
the demos and probes hand-roll today.

## Pattern 6: App Identity / Auth

Evidence:

- `o9mail/mailfs.o9` constructs `AppUserRSAProvider`, enrolls keys from a
  tabula, and calls `serveAppUsers`.
- `stdlib/auth_facade_app.o9` is a minimal `Gate` + `serve()` app.
- `o9-testing/stdlib/appuser.o9` and `o9-appuser-rsa` contain the full
  public-profile/challenge/factotum implementation.
- `stdlib/net.o9` already has `Factotum`, `FactotumAdmin`, and identity
  objects.

Proposed entry: upstream `stdlib/appuser.o9` into the main tree and unify
the `Gate`/`AppUserRSAProvider`/`serveAppUsers` path. The standard service
entry should accept an optional auth provider instead of each app wiring
enrollment, provider construction, and serving separately.

## Pattern 7: Property Testing

Evidence:

- `o9-testing/stdlib/property.o9` is a complete generator/replay/shrinker.
- `stdlib/testing.o9` already exists in main.
- Mutation/grid tests need deterministic generators.

Proposed entry: upstream `stdlib/property.o9` and add it to `mkfile`/e2e
coverage alongside `testing.o9`.

## Pattern 8: Task / Worker Pool Combinators

Evidence:

- `spawn` + `take` is the dominant control-flow shape in every program.
- Grid workers, IRC pump, and UI passes all hand-roll sequencing.
- The runtime now makes spawn cheap and direct, but there is no shared
  `parallel`/`map`/`race`/`Pool`.

Proposed entry: `stdlib/async.o9`

```o9
class Pool {
    method Pool(int64 workers);
    method bool submit(function f);   // shape TBD with compiler support
    method bool drain();
    method int64 active();
}
```

This is lower priority because the compiler's function-object syntax limits
how generic a pool can be. Start with a concrete `map`/`parallel` helper for
`list<T>` if the language surface allows it.

## Pattern 9: FileTree / View Service Builder

Evidence:

- `IrcViews.display` builds a `FileTree`, creates directories, marks live
  files, creates a `MountTable`, applies it, and closes it.
- `MailView` and `house.o9` repeat parts of that sequence.
- `ViewController` is already an interface; the missing piece is a small
  builder/helper for the common tree shape.

Proposed entry: extend `stdlib/view.o9` with:

```o9
class ViewTree {
    method ViewTree();
    method bool dir(string path);
    method bool live(string path, bool writable);
    method bool apply(MountTable mounts);
    method FileTree tree();
}
```

## Priority

1. `cli.o9` + `service.o9` — every program parses argv and most services
   repeat the same startup sequence.
2. `config.o9` — profiles, accounts, manifests, and one-line records are
   everywhere.
3. `privdir.o9` — mail, history, profiles, and keys all need the same
   private/atomic behavior.
4. `logbuf.o9` — IRC/syslog/grid bounded text is repeated.
5. Upstream `appuser.o9` and `property.o9` — already written, just not in
   the main tree.
6. `uiapp.o9` — demos and GUI apps repeat the window loop.
7. `view.o9` builder — reduces `FileTree` boilerplate.
8. `async.o9` — valuable but constrained by current function-object
   generics; design after the others.

## Non-Goals

- Do not move IRC protocol, mail envelope parsing, mutation semantics, or
  zabbix payloads into stdlib. Those are application/domain logic.
- Do not hide raw C behind more layers. Raw helpers stay `function XxxRaw`
  as the stdlib plan requires.
- Do not replace `tabula` for multi-row structured data. `Config` and
  `Fields` are for small line-oriented records only.
- Do not encourage actor-per-field or actor-per-line designs. Prefer one
  object per file, logger, or service.

## Migration Notes

The first consistency win is not a new module: migrate older programs from
raw helpers to the existing objects.

- `ProcessArgcRaw`/`ProcessArgRaw` -> `Process.argc()`/`Process.arg()`.
- `StringSliceRaw`/`StringFieldRaw`/`StringTrimRaw` -> `String` methods
  where the extra object is justified; otherwise keep the raw helper.
- `readfile`/`writefile`/ad-hoc `0600` writes -> `File`/`IOBuffer`/
  `PrivateDir`.
- `create(-, DMDIR)` chains -> `File.mkdirAll()`.
- Ad-hoc `usage:` strings -> `Args.usage()`.

Validate each standard entry with a native `stdlib/e2e_<name>.o9` case and
run `mk verify` plus the host gate.
