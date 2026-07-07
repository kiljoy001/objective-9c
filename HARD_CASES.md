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

## BUG 1 — inherited field access returns 0 (e2e_hard_deep)

4-level inheritance (A<-B<-C<-D). Method *override* dispatch works
(`who()` returns the most-derived 4). But reading an inherited FIELD
through the chain fails:
- `d.va()` returned **0**, expected 7 (va reads field `a` from A, 3
  levels up)
- `d.vc()` returned **100**, expected 107 (C method calls A method va)

So flattened state isn't read correctly across depth. Override dispatch
and field access use different mechanisms; field access breaks at depth.
Priority: HIGH — deep inheritance is silently wrong (returns 0, no
error).

## BUG 2 — recursive construction crashes (e2e_hard_ctor)

A constructor doing `new` of its own class (`Node child = new Node(n-1)`)
faults hard: `general protection violation pc=0x208c55`. Reentrant actor
spawn during a constructor's own dispatch corrupts memory.
Priority: HIGH — a GP fault, not a clean error.

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
