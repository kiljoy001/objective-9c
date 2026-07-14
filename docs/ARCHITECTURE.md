# o9: A Network-Native Language — Architecture

> **See TOUCHSTONE.md for the architecture of record.**  This document
> is detail under those decisions.  Two things below are superseded:
> (1) composition is the *application fileserver's* job, not the
> namespace's — an app is ONE 9P server with a FLAT interface
> (ctl/data/status/methods); objects are NOT paths, they are named in the
> ctl line (method Class.inst method ...).  Objects are CSP actors, not
> fileservers.  The namespace assembles apps into a tree; it is no longer
> the object-composition mechanism.  (2) o9 is a Plan 9 / 9front language:
> `near` = 9P over IL, `far` = 9P over TCP.  o9_connect prepends the
> transport by distance.  (No QUIC / dual-substrate — lean into Plan 9.)

o9 is built on one premise: **the network is not a library, it is the
execution model.** Every object is addressable; locality is a performance
tier, not a semantic boundary. A program does not "use" the network — it
inhabits a namespace that may span machines.

## The Four Rings

Each ring uses the cheapest mechanism for its radius. Identity is uniform;
only the transport changes.

```
 ring 0  SAME     inside one app process
                  shared memory (Internal structs), asm dispatch cache,
                  CSP channels; distance = -1; no 9P, no marshaling
 ring 1  MACHINE  other processes on this machine
                  /srv posts + namespace binds (pipe-backed 9P)
 ring 2  NEAR     other machines, local network
                  9P over IL (dial il!host!svc); distance = 0; new near
 ring 3  FAR      wide area
                  9P over TCP; distance = 1; new far
```

The `distance` field selects transport for crossing machines only.
Application composition is the app facade's job; the Plan 9 namespace
composes mounted apps, sessions, exports, and lower-level namespace setup
tables.

## Object Model

Every class compiles to:

- an **Internal struct** (authoritative state, persisted per-field via
  libtab), owned by a **CSP actor proc** that serializes all method
  execution — one writer per object, no locks;
- a **Client handle** callers hold: `(dispatch_chan, shm_base, table, distance, srvname)`;
- an **app 9P facade**: root `clone`, `methods`, `status`, `exports/`,
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
 4. 9P                ctl write + data read; "error: " prefix  cross-machine
                      carries failures; werrstr locally
```

Return values ride in per-call stack frames (`__o9fr[depth]`), so nested
calls cannot interfere. Errors propagate through every tier.

## Handles

One identity, two forms:

- **universal**: the `oid` — resolves through the object registry,
  method facade, or `/srv` mount protocol;
- **local fast form**: `(dispatch_chan, shm_base, gen)` — valid only
  in-process, guarded by the generation counter.

Handles are CSP values: sending one down a channel transfers the
capability (channel mobility). Crossing a process boundary degrades a
handle to its oid; the far side re-resolves in its own ring.

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
 └── root files: clone, methods, status, exports, sessions
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

Compile-and-grep suites (`type_ast.rc`, `production_ast.rc`: AST dumps,
generated-C requires, ~50 rejection fixtures) plus **execute-and-assert**
(`mk run-test`): real binaries run on 9front, stdout compared —
dispatch/frames/self-calls, builtin file roundtrip, destructor ordering,
generic instantiation.

## Roadmap

- [x] Type* metadata, line diagnostics, registry lexing, monomorphization
- [x] Method/object stores; methods file; error propagation; delete;
      Text/Fs/IO builtins; execute-and-assert harness
- [x] **Phase 1**: idempotent unique `/srv` posts — verified across the
      grid (demo/TWO_MACHINE_DEMO.md)
- [x] **Phase 2**: clone/session facade with per-request session state
- [x] **Phase 3**: `function`/`spawn`/`Task<T>` and stdlib object layer
- [x] **Phase 4**: `MountTable` data layer and `Namespace` object
- [ ] Next: produced-file namespace surface beyond `exports/`;
      higher-level 9P/client helpers; directional channel ends;
      IL placement for `new near`
