# o9 Concurrency — design (draft, July 2026)

Status: mixed implementation and design. The existing compiler/runtime
already have object actors and basic named `chan` fields. Directional
channel ends, numbered channels, and `function`/`spawn` are still design
only; the exact syntax is open where noted.

## Current implementation baseline

These pieces exist today and are the ground truth future work must fit:

- Every constructed object is already an actor: an Internal struct, a
  `dispatch_chan`, and a `proccreate` dispatch loop. Ordinary method
  calls send an `O9Msg` and wait for an `O9Reply`.
- Basic named channels are partly built. A `chan` field is stored as a
  `Channel *`, auto-created at construction, and covered by `e2e_chan`.
  `c -> v`, `c <-? v`, and `x = <- c` lower to boxed Plan 9 channel
  sends/receives.
- Current `chan` is not yet a typed pipe. It has no element type and no
  direction, and the semantic pass only annotates channel-send/recv
  operands. Type and direction misuse still need compile-time checks.
- `function`, `spawn`, and numbered channels do not exist in the lexer,
  grammar, codegen, or runtime yet.

## The core simplification

o9 already has one concurrency model: **every object is a CSP actor** -
a proc (`proccreate`) with a dispatch loop, talking over channels. Do
NOT add a second model. Future concurrency syntax should be a lighter
door into the machinery that already exists.

The load-bearing idea:

> **A `function` is an anonymous object with exactly one method.**

That collapses every hard question a "goroutine" would raise:

- What runs concurrently? The single method of an anonymous object, in
  its own proc. (Same proccreate + dispatch loop objects already use.)
- Closures / capture? None needed. It's an object; its "captured" state
  is just the arguments to its one method — an ordinary method call.
- Lifecycle? Not automatic as written for normal objects. Ordinary
  actors keep receiving after a method returns and exit only through
  `destroy`. A `function`/`spawn` actor must be explicitly one-shot:
  after its single method publishes a result, generated code must tear
  down the instance, unregister it, and let the proc exit, or use a
  special one-shot dispatch loop.
- How does `function` differ from `func` / `method`? It IS a method, on
  an unnamed one-method class the compiler synthesizes. `func main()`
  stays the entry point; `method` stays the class member; `function` is
  sugar that desugars to "anonymous single-method class + an instance."

So the concurrency feature is mostly reuse of what works, with one-shot
lifecycle and result delivery made explicit.

## Two channel kinds (the named/numbered split)

o9 then has two concurrency *patterns* over the one actor model, and
giving them different surfaces makes intent visible (o9-honest, like
try/defer):

- **Named channels** — structured IPC between long-lived NAMED objects
  (the actor mesh). Identity matters; you know who talks to whom. This
  is object-to-object IPC over a `chan` field. Basic fields and
  send/recv are already built; typed payloads and direction are not.
- **Numbered channels** — anonymous concurrent tasks (the goroutine
  pool): future `function` spawns talking back. Numbered precisely
  because they are anonymous - no name to give, so the runtime assigns
  an index.

Same primitive (CSP channel); the naming vs numbering encodes whether
the concurrent unit has an identity.

### Directional ends (part 1, the smaller build)

A named channel should carry direction so object-to-object IPC is a
typed pipe, not a shared mutable endpoint: a `send`-end one object holds,
a `recv`-end another holds. This is Go's `chan<- T` / `<-chan T`. The
type checker knows "A produces, B consumes"; misuse is a compile error.
Smaller, safer, a natural extension of the chan work already done. No new
runtime concept — a directional check at the boundary.

Direction depends on payload typing. The current `chan` surface has no
element type, so the channel type work should come first or at the same
time: the checker needs to know both "this is a channel" and "this
channel carries T" before it can soundly reject bad sends/receives.

## `function` and `spawn` (part 2, the bigger build)

`function name(args) { ... }` declares the body — desugars to an
anonymous single-method class + method.

`spawn name(args)` (syntax TBD) desugars to:
1. construct the anonymous object,
2. proccreate its dispatch loop (already what `new` does),
3. send it the args,
4. hand back a NUMBERED channel to collect the result,
5. destroy/unregister the one-shot instance after the result is
   delivered.

Do not use a nil method reply channel for spawn. Current generated
methods always send an `O9Reply` to `msg->replyc`; a nil `replyc` would
break. Either spawn uses a private `O9Reply` channel and forwards the
declared return value to the numbered channel, or the compiler emits a
special one-shot method wrapper whose result path is the numbered
channel.

`func main()` unchanged (entry point). `method` unchanged (class member).
`function` is the standalone one-method routine; also directly callable,
not only spawnable.

## CRITICAL: anonymous-class identity must derive from the function name

A trap (Scott caught this pre-build): if `function` synthesizes an
anonymous class, that class's identity CANNOT be a generic placeholder
("anon", "function", etc.) — two different functions (worker, logger)
would collide in every hash-keyed table:

- **Method store** keys rows on `"<class>/0x<selector>"` (o9_runtime.c
  ~891) — same class name -> colliding rows.
- **Dispatch selector** is `o9_hash(<name>)` — same synthesized name ->
  same selector -> the `case 0x...:` dispatch-loop collision (the exact
  bug we hit in deep-inheritance constructor dispatch).
- **Registry oid** keys the live-object table — needs a distinct oid.

Fix (bake into the design): the synthesized anonymous class takes its
identity FROM THE FUNCTION (method) NAME, and THAT is what gets hashed.
That identity should be module-qualified, not just the bare identifier:
`Mod.worker` and `Other.worker` must not collide in C symbols, dispatch
tables, registry ids, or namespace entries. If overloads or generic
functions are later allowed, the generated identity also needs enough
signature/type information to remain unique.

For multiple concurrent instances of the SAME function (the numbered
channels), the class is shared (worker's one method) but each spawned
INSTANCE needs a distinct registry oid - e.g. `worker#0`, `worker#1`
(function name + spawn index). Class identity comes from the function;
instance identity comes from function + index. This is also where the
"numbered" in numbered channels comes from.

## Honest caveats (survive even this simplification)

1. **Concurrency first; verify parallelism claims on 9front.** The
   design should assume CSP-style interleaved progress through Plan 9
   thread/proc scheduling and should not sell `spawn` as a compute-
   parallelism feature until the exact target scheduler behavior is
   verified.
2. **Cooperative scheduler.** A proc that never yields (a tight compute
   loop with no channel op) starves others. Real use must be
   communication-bounded (CSP encourages this) or explicitly yield.
   Document this loudly; it's a footgun for compute-heavy spawns.
3. **Result collection / join.** Open question: does a numbered spawn
   support a join/wait for its result, or is the numbered channel the
   only way to get it back (fire-and-forget + channel)? Lean: the
   channel IS the join — recv on the numbered channel blocks until the
   spawn's method sends its result.
4. **Error state must be per call or per actor.** Current `try` observes
   `o9_call_err`, a process-global last-call error. That is not safe for
   concurrent spawned work. Spawn result delivery should carry errors in
   the result/reply object, not through shared global state.

## Open questions before build

- Exact spawn syntax (`spawn f(x)` → what does it evaluate to? a numbered
  channel handle?).
- Channel type and direction syntax (`chan<int64>`, `send chan<int64>`,
  `recv chan<int64>`? declaration modifiers?).
- Does `function` fully subsume top-level `func` later, or stay distinct
  (func = entry only)?
- Numbered-channel identity: index assigned by the runtime — where does
  the program hold/name it to recv on it?
- Result channel shape: raw declared return type, `O9Reply`, or a
  typed result/error pair?

## Build order (decided)

1. Design doc (this) — done.
2. Typed named channels — establish payload type checks for existing
   `chan` fields and send/recv.
3. Directional channel ends — add send-only/recv-only checking once the
   typed channel base exists.
4. `function` + `spawn` — the anonymous-one-method-object concurrency,
   the full "does this give us concurrency" payoff.
