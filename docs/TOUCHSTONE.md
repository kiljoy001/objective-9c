# o9 — Architecture of Record (Touchstone)

This is the anchor document.  When a design question arises, it is
answered here or made consistent with here.  Everything else
(ARCHITECTURE.md, TABULA.md, CODE_AS_TABLE.md, and README.md) is detail
under these decisions.

## The seed

> **An object is a struct whose representation is uniform across memory,
> disk, and wire, accessed through a file protocol rather than a
> pointer.**

A normal struct is memory; you serialize it *to* a file, send it *over*
a socket, store it *in* a database — three formats, translation at every
seam.  o9's struct does not translate: its memory *is* a table, the file
*is* that table, the thing on the wire *is* that table.  One
representation, three jobs, no serialization seam anywhere.

The access interface is 9P verbs (walk/read/write), not a pointer
dereference.  A pointer cannot cross a machine and cannot be denied; a
9P fid can do both.  That single choice is why the struct is *reachable*
(across machines) and *safe to expose* (a verb returns data, never runs
anything).

Everything below is a consequence of this seed.

## 9P is the dependency — not Plan 9

o9 depends on **9P, the protocol**, not on Plan 9, the operating system.
9P has independent implementations: plan9port, the Linux kernel's v9fs /
9pnet, u9fs, py9p, and 9lx's own server.  o9 needs a machine that can
speak 9P and run compiled code; it does not need to *be* Plan 9.

This is the escape-velocity property.  o9's deepest value
(struct-as-file-over-9P) is inseparable from *9P* — but 9P is portable,
so the value travels to any host that implements the protocol.  The
substrate is a protocol, not a kernel.  (Contrast Amoeba: its value was
inseparable from the *OS*, and it stayed a research artifact while the
language built on it — Python — survived by being portable.  9P being a
protocol is what lets o9 avoid that fate without abandoning its soul.)

Targets, concretely: 9front (native), and 9lx/Linux (9P via plan9port +
kernel v9fs; the port scoped separately).  libtab and monocypher already
build on both — proof the dual-target approach holds.

## The five decisions

1. **Core primitive.**  Object = compiled code + a `.tab`.  The `.tab`
   is the struct's uniform representation; the code operates on it.
   Data and behavior are cleanly split: code is rigid (compiled,
   installed), state is fluid (rows in a table).  That split is what
   makes checkpoint, live redefinition, and safe transmission possible.

2. **9P-on-tables is the semantics; the machinery is the transport.**
   A method's effect on state *means* "a 9P action on the object's
   `.tab`."  shm + CSP channel + asm thunk is the **zero-distance
   transport** that realizes that meaning in-process — no walk, no
   marshal, no round-trip.  9P-over-a-connection is the remote
   transport.  `distance` selects the transport under one interface.
   **Law:** the local fast path must faithfully realize the 9P
   semantics — same effect on the same `.tab`, only faster — and must
   never become a literal 9P round-trip for `same`, nor diverge from
   what a remote caller would see.  The asm tier is documented in
   [ASM_DISPATCH.md](ASM_DISPATCH.md); it is a cache over local
   dispatch, not a separate semantic path.

3. **The network carries data only; it is inert on arrival.**  A
   Tabula that crosses the wire is read like any file.  It is never an
   object, never code, never actionable — nothing the sender wrote can
   cause anything to happen on the receiver.  **o9 does not move objects
   and does not rehydrate them**: reconstructing a live thing from
   sender-supplied bytes is RCE in disguise (the deserialization-RCE
   family), unsecurable because the insecurity is the feature.  State
   transfer / clone is done by the *receiver's* trusted local code
   reading values and building its own object under its own control.
   Full statement: TABULA.md.

4. **Homoiconicity is local and compile-time only.**  The AST is a
   Tabula that build-time filters (macros) transform between parse and
   typecheck, on the machine that owns the source.  It is a
   metaprogramming tool, never a wire format.  Full statement:
   CODE_AS_TABLE.md.

5. **Naming.**  The language-level table type is **Tabula** (not
   Table/Tab).  libtab / `.tab` stay at the C and file layer.

## Everything is a consequence

Each feature is an implication of the seed, not an independent addition —
the test that the architecture is coherent:

- **secret field** = a struct field stored encrypted (a sealed cell).
- **the object** = struct + the code that operates on it.
- **the application** = many such structs served from one process under
  one `/srv/o9.<app>` (per-app fileserver; see roadmap A).
- **distance tiers** = how far Tabula data travels.  `same` is an in-process
  Tabula.  `near` reads a Tabula over **9P/IL**.  `far` reads a Tabula over
  **9P/TCP**.  `listener` serves local Tabula exports/imports through the
  app's 9P tree.  Remote objects are rejected, and the old runtime object-RPC
  fallback is removed; data crosses as `.tab` text and the receiver's local
  code decides what to do.
- **object relationships** = names, registry lookup, namespace reachability,
  and explicit handles passed through local CSP. A stored reference graph
  was cut; relationships are enacted at call time.
- **live / REPL** = the struct (state) outlives the code (behavior)
  because they were never the same bytes (roadmap D).
- **"no rehydration"** = never send the code, only the struct; a struct
  is data and data is inert.

If a proposed feature is *not* expressible as a consequence of the seed,
that is the signal to question it — bloat and insecurity have entered
together every time in this design's history (rehydration, shipped code,
a fat runtime), and the seed is the filter that catches them.

## Build roadmap — converged, dependency-ordered

Each item is independently useful; the order is forced by what each one
needs to exist first.

- **A. Per-application fileserver.**  Collapse the per-object fileserver
  to per-app: one process per app, one `/srv/o9.<app>` post, one shared
  facade (`clone`, `methods`, `status`, `exports/`, `imports/`, and
  per-session `ctl`/`data`/`status`). Objects are addressed by name through the
  facade or by in-process handles, not mounted as separate public object
  trees. Foundation for B/C/D — they all need "a program" to be one
  addressable thing. Escape hatch: behavior that needs a real trust boundary
  runs as a separate app and exchanges Tabula data through `exports/` and
  `imports/`, paying 9P cost exactly where isolation is wanted.

- **B. ~~One `kind`-keyed ledger per app.~~  Abandoned (July 2026).**
  A unified store requires a query filter to answer "what methods does
  this class have?" — a separate in-memory method table answers that
  directly.  One purpose per table is still the honest Plan 9 design, but
  authority-bearing metadata is no longer a public writable file:
    - method table — private in-memory registrations
    - object table — private in-memory object inventory / node table
    - `<class>.<inst>.tab` — per-instance field state when debug state
      snapshots are explicitly enabled
    - `exports/<name>.tab` — published Tabulae (written by `export()`)
    - `imports/<name>.tab` — inert inbound Tabula deposits
  Persisted method/object copies are debug snapshots only.  Roadmap order
  collapses to **A (done) → C → D**.

- **C. ~~Reference graph.~~  Abandoned (July 2026) — wrong in principle.**
  An explicit reference graph (write-barrier on every handle assignment)
  is a manual GC write barrier: you're doing by hand what a GC does
  automatically.  o9 has no GC and no VM, and this mechanism belongs to
  that world.  The object graph in o9 is not stored — it is *enacted at
  call time* through late-bound dispatch, exactly as in ObjC.  "What does
  this object connect to" is answered by the registry (who's alive, by
  oid) and the namespace (what's bound where), which are already real and
  working.  Objects find each other by name (lookup by oid), not by held
  pointers.  That is the correct model for this architecture.

- **D. REPL / live editing (gated, last).**  Attach to the app server
  (A), inspect public methods/exports and debug snapshots, and explore
  whether code can be swapped while object state survives. Blocker:
  9front has no `dlopen`; this stays gated until the compiled-code story
  is honest on 9front. This is the "Python-on-Amoeba" moment: the layer
  that makes the substrate conversational. Whether it becomes
  Python-the-survivor or Amoeba-the-artifact turns on the dual-target
  reach (see 9P section) — o9 being compelling to someone who doesn't
  already believe in the substrate.

The old A/B/C sequence has converged: A is built, B and C were cut, and
D remains gated on an honest 9front code-loading story. None requires the
transmitted code / rehydration path that was cut.

## Public Data Without Dispatch

The public data interface is `exports/` plus `imports/`: an app publishes
Tabulae as readable files under `exports/`, and receives inert inbound Tabula
deposits under `imports/`. That keeps transport inert while letting
applications share useful state.

Internal object state is not the normal public data interface. It lives
in memory and may be mirrored through the debug-only `state` inspector
when `O9DEBUG` is enabled. That snapshot is read-only and
non-authoritative. Mutation goes through methods and the app facade, not
by editing metadata files.

So the split is:

- **Read/write data** — mount `exports/` to read published Tabulae, or write
  `.tab` files into `imports/`. Data is inert, signable, and cat-able.
- **Invoke behavior** — write a method command to a session `ctl`, or use
  direct in-process dispatch. Required for side effects, arguments, and
  computed return values.

## What was cut, permanently

Recorded so it is not re-derived: remote object spawn, capsule exec,
rehydration, schema-hash admission gates, signature-gated compile of
foreign code, an interpreter / VM, a foreign-code sandbox, the totality
theorem it would have needed, dp9ik-before-rehydration, admission tiers.
All of it was defending a primitive that should not exist.  The safe,
small system is: **compiled code that thinks in-process and speaks in
tables; the network is other code reading those tables.**
