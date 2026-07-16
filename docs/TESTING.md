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
- `mk verify`: full normal gate. It runs AST, e2e, property, facade,
  session, issue, runtime C, and CRAP checks. After changing
  `o9c/grammar.y`, regenerate CRAP instrumentation on the host before
  running it:

```sh
python3 tools/o9crap.py instrument
```

Generated C warnings are failures. The main e2e harness captures `6c` output
and treats any `warning:` line as a regression. Do not hide warning noise in
tests; fix the generated C or the runtime declaration that caused it.

## Property Testing

Property tests generate many small programs, lower each generated case to o9
and to reference Plan 9 C, then compare stdout on 9front. Python is only the
case generator; Plan 9 C is the oracle.

The checked-in property lanes are:

```sh
python3 tools/o9prop.py generate --cases 32 --seed 9009
python3 tools/o9prop.py generate --kind width --out o9c/test/prop/width --cases 32 --seed 9010
python3 tools/o9prop.py generate --kind stdlib --out o9c/test/prop/stdlib --cases 25 --seed 9020
```

Then run the checked-in corpus on 9front:

```rc
mk prop-test
```

When Hypothesis is installed, `tools/o9prop.py` uses Hypothesis to generate
case seeds. Without Hypothesis, it uses a deterministic fallback stream so the
repo still has a runnable property corpus. Failed cases should be saved as
ordinary focused `.o9` regressions after shrinking or simplifying.

Good first properties:

- Scalar expressions: arithmetic, comparisons, bitwise ops, shifts, unary ops.
- Width/cast expressions: scalar casts match Plan 9 C storage behavior.
- Stdlib surface: String, Bytes, built-in List/Dict, channel values, and
  Tabula read/query/write behavior.
- Namespaces: MountTable serialization recreates the same bind/mount rows.

The default corpus should stay deterministic and quick. Longer local corpora
can use a higher `--cases` count and a different seed.

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

The mutation harness is host-side because it rewrites `o9c/grammar.y`, runs a
caller-supplied command, then restores the file. List mutants:

```sh
python3 tools/o9mutate.py list
```

Run one mutant against a focused 9front command:

```sh
python3 tools/o9mutate.py run --only ctl_arity \
  --timeout 75 --status-marker O9MUTATE \
  --cmd "PASS='\$Master001' timeout 60s drawterm -G -h dev9p.rentonsoftworks.coin -a Authomatic.rentonsoftworks.coin -u scott -c 'cd /mnt/term/home/scott/Repo/objective-9c; fail=0; if(! mk ast-test) fail=1; if(! mk ctlargs-test) fail=1; if(~ \$fail 0) echo O9MUTATE pass; if not echo O9MUTATE fail'"
```

The pass condition is that the command fails for every mutant. A command that
still succeeds means the mutant survived. Surviving mutants are more useful
than the mutation score itself: each survivor should become a new regression
test, then the mutant should be killed on the next run.

## Order

1. Keep the normal e2e suite green.
2. Use CRAP to shrink large compiler functions.
3. Add property tests for scalar language behavior and stable stdlib behavior.
4. Add fuzzing for parser/type/codegen edges.
5. Add mutation testing for language invariants.
