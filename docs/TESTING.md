# Testing Strategy

o9 tests should run on 9front and exercise the real transpiler, generated C,
and runtime. Host-side scripts can generate inputs or reports, but the
authoritative behavior checks should compile and run through `mk`.

## Current Layers

- `mk ast-test`: parser and typechecking negatives.
- `mk run-test`: end-to-end o9 programs compiled to Plan 9 C.
- `mk issue-test`: focused C/runtime regressions.
- `mk export-test`, `mk session-test`, `mk ctlargs-test`,
  `mk ctlquote-test`: 9P facade behavior.
- `mk crap-test`: instrumented transpiler coverage plus complexity scoring.

## Property Testing

Property tests should generate many small o9 programs that include their own
oracle and print `OK` on success. This keeps the check native and readable.

Good first properties:

- String round trips: concat, slice, length, compare.
- Bytes round trips: hex text to bytes to hex.
- Tabula round trips: write, read, query, serialize, reopen.
- Channel values: send/receive preserves type and value.
- Casts: valid numeric casts match Plan 9 C behavior.
- Namespaces: MountTable serialization recreates the same bind/mount rows.

The useful shape is:

```rc
mk prop-test
```

with a deterministic seed list checked into the repo. Failed seeds should be
saved as ordinary `.o9` regression files.

## Fuzzing

Fuzzing should be compiler-aware, not random bytes into yacc. A small 9front C
or rc generator can emit valid-ish o9 programs from a seed and mode:

- parser fuzz: valid class/method/property/control-flow shapes;
- type fuzz: expected-pass and expected-fail programs;
- codegen fuzz: small runnable programs with known output;
- facade fuzz: generated apps with randomized method/property surfaces.

The first targets should be:

```rc
mk fuzz-parse
mk fuzz-type
mk fuzz-run
```

The default fuzz run should be short and deterministic. A longer local target
can run more seeds:

```rc
mk fuzz-long
```

Every crash, hang, bad diagnostic, or wrong output becomes a checked-in
regression test.

## Mutation Testing

Mutation testing changes the compiler or runtime and expects the existing tests
to fail. A mutant that still passes is a missing test or a dead rule.

Start with deliberate semantic mutants, not arbitrary token edits:

- remove private field/method checks;
- allow `near`, `far`, or `listener` on non-Tabula objects;
- weaken ctl arity checks;
- reverse channel direction checks;
- allow object values inside tuple returns;
- weaken raw C boundary validation;
- change Tabula import commit semantics;
- change generated arithmetic or comparison operators;
- remove per-session result isolation.

The expected command shape is:

```rc
mk mutate-test
```

Each mutant should be applied one at a time, then run a focused test subset.
The pass condition is that the subset fails. Surviving mutants are more useful
than the mutation score itself: each survivor should turn into a new regression
test, then the mutant should be killed on the next run.

## Order

1. Keep the normal e2e suite green.
2. Use CRAP to shrink large compiler functions.
3. Add property tests for stable stdlib behavior.
4. Add fuzzing for parser/type/codegen edges.
5. Add mutation testing for language invariants.

