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
Composition — which objects appear where — is always the namespace's job.

## Object Model

Every class compiles to:

- an **Internal struct** (authoritative state, persisted per-field via
  libtab), owned by a **CSP actor proc** that serializes all method
  execution — one writer per object, no locks;
- a **Client handle** callers hold: `(dispatch_chan, shm_base, table, distance, srvname)`;
- a **9P file tree**: `ctl` (commands), `data` (replies), `status`
  (identity, schema, instances), `methods` (dispatch table as text);
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

- **universal**: the `oid` — resolves anywhere via the object store or a
  namespace walk (`/mnt/o9/App/obj/<oid>`);
- **local fast form**: `(dispatch_chan, shm_base, gen)` — valid only
  in-process, guarded by the generation counter.

Handles are CSP values: sending one down a channel transfers the
capability (channel mobility). Crossing a process boundary degrades a
handle to its oid; the far side re-resolves in its own ring.

## The Data Plane (libtab)

- **O9ObjectStore** (`state/<app>.objects.tab`): oid, type, class,
  status (declared|live), addr+gen, ns, path, owner. `new` writes live
  rows; `object` declarations sit at declared.
- **O9MethodStore** (`state/<app>.methods.tab`): class, method, selector,
  arity, signature, thunk addr+gen(pid). Registered at startup (inherited
  methods flattened), backs the dispatch cache, served as each class's
  `methods` file.
- Per-instance field state persisted through `O9State`.

Rule shared by all tables: identity columns are portable truth; `addr`
is a per-process hint that dies with its generation.

## The Process Model (planned: phases below)

**One OS process per app instance.** All classes of an app are roommates:
actors share memory, dispatch through rings 0's machinery, and each class
still posts its own 9P tree — per-class servers preserved, but post-only:

```
 app process
 ├── actors (one proc per instance, CSP-serialized)
 ├── registry actor           ← the intra-program bus hub
 ├── /srv/o9.<app>.<class>    (one post per class, idempotent)
 └── shared: object store, method store, app root
```

### The Registry Actor (CSP as the intra-program bus)

One actor per process owns the live handle table:
`register(oid, handle)`, `lookup(oid) → handle`, `watch(oid) → channel`,
`unregister + notify`. Single-writer by construction. The object store is
its persisted state; the 9P `obj/` tree is its external projection.
`delete` flows through it, so watchers re-resolve on death — Plan B
re-resolution, in-process, with no coordinator daemon.

Discipline: the registry never calls out synchronously (notifications use
try-send `<-?` / buffered channels); handles travel in messages, never as
nested synchronous call cycles.

### Namespace as the Box

Assembly is a **generated namespace recipe** — mount/bind lines emitted
into startup and mirrored as a text file under `state/` (`/lib/namespace`
format). The compiler's `object` and `link` declarations compile to it:

```
 mount /srv/o9.App.Counter    /mnt/o9/App/class/Counter
 bind  …/class/Counter/c      /mnt/o9/App/obj/c
 bind  …/obj/mirror           /mnt/o9/App/obj/primary    # link replace
 bind -b …/obj/backup         /mnt/o9/App/obj/primary    # fallback union
```

`link replace` is a bind — kernel-implemented redirection; union binds give
failover; re-resolution is re-binding after a repost.

**The /srv seam (verified on the grid):** a server's self-mount is
visible only inside its own process namespace. The idempotent `/srv`
post is therefore the canonical publication point — machine-global,
importable (`rimport host /srv`), mountable anywhere. Assembled
`/mnt/o9/App` trees are built by *consumers* executing the recipe in
their own namespaces, never by the server for others. Replica semantics
(actual state sync) remain future work. There is no box daemon: the box
is a text file the kernel interprets, inside the process it is the
registry actor — provably the same table, two projections.

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
- [x] **Phase 2**: registry actor + namespace assembly recipe
- [x] **Phase 3**: `link replace`/`union` as binds with union fallbacks
- [ ] Next: oid handle form in method args; registry watch channels;
      replica sync; module-based stdlib services under `lib/`;
      IL placement for `new near`
