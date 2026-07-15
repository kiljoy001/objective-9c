# o9: A Network-Native Language — Architecture

> **See TOUCHSTONE.md for the architecture of record.**  This document
> is detail under those decisions.  Current architecture: an app is one
> 9P server with a fixed facade (`clone`, session `ctl`/`data`/`status`,
> `methods`, `exports/`, `imports/`). Objects are local CSP actors inside
> that process. `near`, `far`, and `listener` move Tabula data only;
> source-level remote objects are rejected.

o9 is built on one premise: **the network is not a library, it is the
application's namespace.** Objects are local CSP actors. The network-facing
surface is the app facade: `exports/` publishes Tabula data, `imports/`
accepts inert Tabula deposits, and `ctl` is an explicit command interface.
Source-level object handles do not cross machines.

## The Four Rings

Each ring uses the cheapest mechanism for what is allowed to cross it.

```
 ring 0  SAME     inside one app process
                  shared memory (Internal structs), asm dispatch cache,
                  CSP channels; distance = -1; no 9P, no marshaling
 ring 1  MACHINE  other processes on this machine
                  /srv posts + namespace binds; explicit app facade commands
 ring 2  NEAR     other machines, local network
                  Tabula data over 9P/IL
 ring 3  FAR      wide area
                  Tabula data over 9P/TCP
```

The source-level distance forms select transport for Tabula data only.
Remote class/object construction is intentionally rejected.
Application composition is the app facade's job; the Plan 9 namespace
composes mounted apps, sessions, exports/imports, and lower-level namespace setup
tables.

## Object Model

Every class compiles to:

- an **Internal struct** (authoritative state, persisted per-field via
  libtab), owned by a **CSP actor proc** that serializes all method
  execution — one writer per object, no locks;
- a **local client handle** callers hold for in-process dispatch;
- an **app 9P facade**: root `clone`, `methods`, `status`, `exports/`, `imports/`,
  and per-session `<id>/ctl`, `<id>/data`, `<id>/status`;
- generated **impl functions**, asm-cache **thunks**, and same-class-call
  wrappers.

Inheritance is struct embedding with flattened dispatch; interfaces and
`abstract` are compile-time contracts; generics are **monomorphized** —
each concrete instantiation (`Box<int64>` → `Box__int64`) is a real class.

## Dispatch Tiers (per call, fastest first)

```
 1. asm L1 cache      64-entry direct-mapped, per-client       ~ns
 2. method store      libtab (class, selector) → thunk;
                      pid-generation guard: a hit is always
                      a same-process pointer                   fill L1, retry
 3. CSP channel       O9Msg over dispatch_chan to the actor    in-process
 4. app facade        explicit ctl write + data read over 9P;
                      not generated source-level remote object dispatch
```

Return values ride in per-call stack frames (`__o9fr[depth]`), so nested
calls cannot interfere. Errors propagate through every tier.

See [ASM_DISPATCH.md](ASM_DISPATCH.md) for the fixed client ABI, cache
layout, miss/refill behavior, and fallback invariants.

## Handles

One identity, two forms:

- **process identity**: the `oid` — resolves through the in-process object
  registry and debug/method metadata;
- **local fast form**: `(dispatch_chan, shm_base, gen)` — valid only
  in-process, guarded by the generation counter.

Channels carry typed o9 values through a generic byte envelope. Handles are
CSP values too: sending one down a channel transfers the capability
(channel mobility), not the actor memory. Crossing a process boundary uses
Tabula data or explicit app facade commands, not object-handle rehydration.

## The Data Plane (libtab)

- **O9ObjectStore**: private in-memory libtab carrying oid, type, class,
  status (declared|live), addr+gen, ns, path, owner. `new` writes live
  rows; optional `object` declarations are metadata. It is not mounted as
  a writable `.tab` file.
- **O9MethodStore**: private in-memory libtab carrying class, method,
  selector, arity, signature, thunk addr+gen(pid). Registered at startup
  (inherited methods flattened), backs the dispatch cache, served as each
  class's read-only `methods` file.
- Per-instance field state persisted through `O9State`.

Rule shared by all tables: identity columns are portable truth; `addr`
is a per-process hint that dies with its generation.

Object and method tabs are authority-bearing runtime metadata, not public
data transport. They normally stay in memory only. Any persisted copy is a
debug snapshot and must be read-only/non-authoritative; external mutation
must go through the app facade (`ctl`/methods), never by editing metadata
files.

`O9DEBUG` connects those private tables to the existing debug inspector:
reading the app's `state` file emits read-only method/object snapshots
alongside live instance state. With `O9DEBUG` unset, the inspector remains
gated.

## The Process Model

**One OS process per app instance.** All classes of an app are roommates:
actors share memory and dispatch through ring 0's machinery. The external
surface is the shared app fileserver facade:

```
 app process
 ├── actors (one proc per instance, CSP-serialized)
 ├── object/method stores     ← private runtime metadata
 ├── /srv/o9.<app>...         ← published app facade
 └── root files: clone, methods, status, exports, imports, sessions
```

### The Registry Actor (CSP as the intra-program bus)

One registry path per process owns the live handle table:
`register(oid, handle)`, `lookup(oid) -> handle`, and `unregister`.
Single-writer discipline protects the object store. `delete` unregisters
the handle after the actor exits.

Discipline: the registry never calls out synchronously (notifications use
try-send `<-?` / buffered channels); handles travel in messages, never as
nested synchronous call cycles.

### Namespace Control

The retired `link`/`replace`/`union` object-composition model is gone.
Namespace control now has two jobs:

- compose mounted app facades and exported data in a client's namespace;
- let programs use `Namespace`/`MountTable` to build controlled private
  namespaces for setup and isolation.

**The /srv seam (verified on the grid):** a server's self-mount is
visible only inside its own process namespace. The idempotent `/srv`
post is therefore the canonical publication point — machine-global,
importable (`rimport host /srv`), mountable anywhere. Assembled
`/mnt/o9/App` trees are built by consumers in their own namespaces, never
by the server for others.

## Compilation Pipeline

```
 source.o9 → o9c (prescan registry → registry-only lexing → AST with
 Type* + line numbers → typecheck with bindings → monomorphize →
 codegen) → Plan 9 C → 6c/6l + libo9.a → binary
```

Diagnostics carry line numbers everywhere. TTYPEIDENT means *declared
type* — PascalCase members, locals, and bare self-access all work.

## Testing

Compile-and-grep suites (`production_ast.rc`: AST dumps, generated-C
requires, rejection fixtures) plus **execute-and-assert** (`mk run-test`):
real binaries run on 9front, stdout compared — dispatch/frames/self-calls,
builtins, destructors, generics, channels, Tabula transport, stdlib, and
libdraw headless checks.

## Roadmap

- [x] Type* metadata, line diagnostics, registry lexing, monomorphization
- [x] Method/object stores; methods file; error propagation; delete;
      stdlib object layer; execute-and-assert harness
- [x] **Phase 1**: idempotent unique `/srv` posts — verified across the
      grid (demo/TWO_MACHINE_DEMO.md)
- [x] **Phase 2**: clone/session facade with per-request session state
- [x] **Phase 3**: `function`/`spawn`/`Task<T>` and stdlib object layer
- [x] **Phase 4**: `MountTable` data layer and `Namespace` object
- [x] **Phase 5**: directional public channel endpoints for UI/event APIs
- [ ] Next: events/watch support for import/export changes;
      higher-level 9P/client helpers
