# Function Object Contract Tests

These tests pin the intended `function` model for the refactor.

They are intentionally kept out of the default `mk run-test` and `mk verify`
paths until the implementation is changed. Run them explicitly:

```rc
mk function-object-contract-test
```

Current contract:

- `function` is the type of a one-method function object; it does not take
  angle-bracket type parameters.
- `function name(args) ret { ... }` creates an anonymous object instance.
  The signature lives on the function body, not the property type.
- `new function ...` is not valid syntax; function bodies are already object
  constructors.
- The generated object has exactly one hidden method: `run(...)`.
- Users run function objects with `spawn fn(args)`, which returns `Task<ret>`.
- Direct function-object calls are rejected; function objects are for spawned
  work.
- Raw C may appear inside the function object's `run` body.
- Function object bodies do not capture enclosing fields or methods.
- Raw C inside function objects must not access generated `self` internals.
- Object handles are not valid function-object parameters while raw C interop
  remains the low-level function use case.
