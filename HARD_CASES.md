# Adversarial test findings (July 2026)

Six "break the model" tests (`o9c/test/e2e_hard_*.o9`) aimed at feature
combinations the feature-driven suite never isolated. Three passed;
three found real bugs.

## Passing — verified robust

- **Recursion through dispatch** (`e2e_hard_recursion`): `fact`/`fib`
  self-recursion works. The `o9_self_` wrapper bypasses the CSP reply
  channel, so a method calling itself does NOT deadlock. (This was the
  main fear — it's fine.)
- **Nested try** (`e2e_hard_nesttry`): 3-level error propagation works;
  an error from `try` propagating through another `try` is correct.
- **Multiple defers** (`e2e_hard_defer`): LIFO order correct; defers run
  on the fail path too.

## BUG 1 — inherited constructor never runs (e2e_hard_deep) — FIXED

4-level inheritance (A<-B<-C<-D). Symptom: reading an inherited field
returned 0 (`d.va()` = 0 not 7). Not a struct-layout bug — the Internal
structs are correctly flattened and identical, and `o9_impl_A_va` reads
`self->a` correctly.

Real cause: the FIELD WAS NEVER SET because the inherited constructor
never ran. `new D(7)` dispatches under `o9_hash("D")`, but the inherited
`A` constructor was registered in D's dispatch loop only under
`o9_hash("A")`. Selector mismatch -> "bad selector" -> constructor
skipped -> `a` stays 0.

Fix (gen_dispatch_cases): a constructor is a method whose name equals its
defining class. When that class is an ANCESTOR of the one being
constructed, ALSO emit a dispatch case under `o9_hash(childname)` aliased
to the same impl. Works at any depth because the alias always targets the
concrete class's hash. Verified: va 7 / vc 107 / who 4. Full suite green,
no regression (constructor dispatch is used by every class).

Follow-up — super() chaining (e2e_hard_super): the alias fixes `new Child`
reaching the NEAREST ancestor ctor. When MULTIPLE levels have their own
constructor (Animal<-Mammal<-Cat, each with a ctor), each must chain to
its parent so every level's fields get set. Added explicit `super(args)`
(o9-honest, no hidden calls): a gen_stmt special form that packs args and
calls the parent's ctor impl on the same self. Verified species 7 / legs
4 / lives 9 through a 3-level chain. The alias (entry) and super
(chaining) are the two halves that make deep inheritance with per-level
constructors fully work.

## BUG 2 — self-recursive construction — RESOLVED (forbidden by design)

A constructor doing `new` of its OWN class (`Node child = new Node(n-1)`
inside Node's ctor) faulted hard (GP violation) — reentrant actor spawn
during a constructor's own dispatch corrupts memory.

Decision (Scott): this is correctly FORBIDDEN, not a gap. A class cannot
construct itself while half-built — the same reason Swift's two-phase
init rejects self-use before all fields are set, and why C++/Java only
"allow" it into infinite recursion. o9's actor model makes it worse (a
GP-fault, not just stack overflow), so the compiler now rejects it with a
clear diagnostic instead of crashing.

Fix: narrow typecheck guard — `new C` inside C's own constructor is a
compile error ("cannot 'new C' inside C's own constructor ... build it in
a method or factory"). The ban is NARROW: `new OtherClass` into a field
(composition, e.g. Car makes an Engine) is still allowed — only direct
self-construction is banned. Verified: typecheck_bad_ctor_new errors as
expected; e2e_hard_field (composition) still passes.

## Summary — all six resolved

1. Recursion: worked as-is.  2. Nested try: worked.  3. Multiple defers:
worked.  4. Object-as-field composition: fixed.  5. Deep inheritance:
fixed (constructor alias + super()).  6. Self-recursive construction:
forbidden by design (clean error, not a crash).

## BUG 3 — object-as-field breaks in a constructor (e2e_hard_field)

`class Car { Engine motor; method Car(int64 p){ motor = new Engine(p); } }`
does not compile: `name not declared: motor` at the constructor's
dispatch line. The generated code creates a LOCAL `Engine_Client motor`
(gen_local_new path) but the field assignment needs `self->motor` /
`__i->motor`. The field-vs-local scope is confused: `new` assigned to a
class-typed field emits a dangling local.

Note: READING through the field works — `drive()` correctly generates
`self->motor` dispatch (line 591). Only CONSTRUCTING into the field is
broken. Also note the field is wrongly given a state column and treated
as a stored value (lines 529, 783-879) — a class-typed field is a
handle, not persisted state.
Priority: HIGHEST — object composition (has-a) is table-stakes OOP and
the exact case real programs need (Car has-an Engine).

## Root-cause hypotheses

- BUG 3: `gen_local_new`/`gen_assign_new` doesn't distinguish "new into
  a local var" from "new into a field". Field assignment of a class-typed
  value needs to target `self->field`/`__i->field` and NOT allocate a
  local, and NOT create a state column for it.
- BUG 1: field read across inheritance uses a flattening that resolves
  to offset 0 for deeply-inherited fields — likely the parent state
  isn't embedded at the expected offset, or the read walks the wrong
  struct.
- BUG 2: recursive `new` during construction — the constructor runs in
  the actor proc; a nested `new` spawns another proc and dispatches while
  the first is mid-construction. Possibly the same field/local confusion
  as BUG 3 combined with reentrancy, or an uninitialized dispatch path.

Fix order suggested: BUG 3 (composition) → BUG 1 (deep inheritance) →
BUG 2 (recursive ctor, may resolve with BUG 3).
