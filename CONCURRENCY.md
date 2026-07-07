# o9 Concurrency — design (draft, July 2026)

Status: design only, nothing built. Decided from the discussion; the
build order and exact syntax are still open where noted.

## The core simplification

o9 already has one concurrency model: **every object is a CSP actor** —
a proc (proccreate) with a dispatch loop, talking over channels. We do
NOT add a second model. Everything below is a lighter *door* into the
machinery that already exists and is tested.

The load-bearing idea:

> **A `function` is an anonymous object with exactly one method.**

That collapses every hard question a "goroutine" would raise:

- What runs concurrently? The single method of an anonymous object, in
  its own proc. (Same proccreate + dispatch loop objects already use.)
- Closures / capture? None needed. It's an object; its "captured" state
  is just the arguments to its one method — an ordinary method call.
- Lifecycle? Same as any object: it lives as an actor proc; when its
  method returns and refcount hits zero, the existing ARC reap path
  collects it.
- How does `function` differ from `func` / `method`? It IS a method, on
  an unnamed one-method class the compiler synthesizes. `func main()`
  stays the entry point; `method` stays the class member; `function` is
  sugar that desugars to "anonymous single-method class + an instance."

So the concurrency feature is almost entirely REUSE of what works.

## Two channel kinds (the named/numbered split)

o9 then has two concurrency *patterns* over the one actor model, and
giving them different surfaces makes intent visible (o9-honest, like
try/defer):

- **Named channels** — structured IPC between long-lived NAMED objects
  (the actor mesh). Identity matters; you know who talks to whom. This
  is object-to-object IPC over a chan field (already built: chan fields
  auto-created at construction, e2e_chan).
- **Numbered channels** — anonymous concurrent tasks (the goroutine
  pool): `function` spawns talking back. Numbered precisely because they
  are anonymous — no name to give, so the runtime assigns an index.

Same primitive (CSP channel); the naming vs numbering encodes whether
the concurrent unit has an identity.

### Directional ends (part 1, the smaller build)

A named channel should carry direction so object-to-object IPC is a
typed pipe, not a shared mutable endpoint: a `send`-end one object holds,
a `recv`-end another holds. This is Go's `chan<- T` / `<-chan T`. The
type checker knows "A produces, B consumes"; misuse is a compile error.
Smaller, safer, a natural extension of the chan work already done. No new
runtime concept — a directional check at the boundary.

## `function` and `spawn` (part 2, the bigger build)

`function name(args) { ... }` declares the body — desugars to an
anonymous single-method class + method.

`spawn name(args)` (syntax TBD) desugars to:
1. construct the anonymous object,
2. proccreate its dispatch loop (already what `new` does),
3. send it the args without blocking on the reply,
4. hand back a NUMBERED channel to collect the result.

`func main()` unchanged (entry point). `method` unchanged (class member).
`function` is the standalone one-method routine; also directly callable,
not only spawnable.

## Honest caveats (survive even this simplification)

1. **Concurrency, not parallelism.** o9 runs on the Plan 9 thread
   library; procs interleave, they do NOT run on multiple cores in this
   model. This is CSP concurrency (interleaved progress), fine for IPC-
   shaped work, NOT a compute-parallelism story.
2. **Cooperative scheduler.** A proc that never yields (a tight compute
   loop with no channel op) starves others. Real use must be
   communication-bounded (CSP encourages this) or explicitly yield.
   Document this loudly; it's a footgun for compute-heavy spawns.
3. **Result collection / join.** Open question: does a numbered spawn
   support a join/wait for its result, or is the numbered channel the
   only way to get it back (fire-and-forget + channel)? Lean: the
   channel IS the join — recv on the numbered channel blocks until the
   spawn's method sends its result.

## Open questions before build

- Exact spawn syntax (`spawn f(x)` → what does it evaluate to? a numbered
  channel handle?).
- Directional channel syntax (`send chan`, `recv chan`? a decl modifier?).
- Does `function` fully subsume top-level `func` later, or stay distinct
  (func = entry only)?
- Numbered-channel identity: index assigned by the runtime — where does
  the program hold/name it to recv on it?

## Build order (decided)

1. Design doc (this) — done.
2. Named/directional channels — the safe, moderate extension.
3. `function` + `spawn` — the anonymous-one-method-object concurrency,
   the full "does this give us concurrency" payoff.

Nothing built yet; revisit the open questions when starting build.
