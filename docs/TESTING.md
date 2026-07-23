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
- `python3 tools/o9pmd.py`: host-side PMD/CPD duplicate-code gate for
  o9-owned C-ish sources and Python tools.
- `mk verify`: full normal gate. It runs AST, e2e, property, facade,
  session, issue, runtime C, and CRAP checks. After changing
  files under `o9c/grammar.d/`, rebuild `o9c` on 9front and regenerate CRAP
  instrumentation on the host before running it:

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
  tabula read/query/write behavior.
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
- allow `near`, `far`, or `listener` on non-tabula objects;
- weaken ctl arity checks;
- reverse channel direction checks;
- allow object values inside tuple returns;
- weaken raw C boundary validation;
- change tabula import commit semantics;
- change generated arithmetic or comparison operators;
- remove per-session result isolation.

The mutation harness is host-side because it rewrites the editable grammar
chunks under `o9c/grammar.d/`, runs a caller-supplied command, then restores
the files. List mutants:

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

### Universal Mutator

`tools/o9mutate.py` is for hand-picked semantic mutants. For broader mutation
testing, use Universal Mutator through `tools/o9um.py`. Universal Mutator is
host-side; it generates mutated source files. The preferred runner mode is
`--synthetic-ramfs`: `o9um.py` writes a tiny rc script, drawterm runs it on
9front, the script creates a private `ramfs` worktree, copies maintained source
inputs into it, writes the mutant into that ramfs copy, runs the real gate, and
throws the whole synthetic tree away. The real checkout is not opened for write.

Install Universal Mutator into an isolated host venv:

```sh
python3 -m venv /tmp/o9-universalmutator-venv
/tmp/o9-universalmutator-venv/bin/python -m pip install universalmutator
```

Run a small sampled pass against the type system source:

```sh
python3 tools/o9um.py run o9c/o9_type.c \
  --clean --limit 10 --seed 9009 --synthetic-ramfs \
  --timeout 180 --status-marker O9UM \
  --gate-rc 'fail=0
if(! mk ast-test) fail=1
if(~ $fail 0) echo O9UM pass
if not echo O9UM fail' \
  --cmd "PASS='\$Master001' timeout 150s drawterm -G -h dev9p.rentonsoftworks.coin -a Authomatic.rentonsoftworks.coin -u scott -c 'rc {script}'"
```

The marker is important because drawterm may still exit 0 after the remote rc
script reports a test failure. `O9UM pass` means the original or mutant passed
the verification command; `O9UM fail` means the mutant was killed. The TSV
`exit` column records the host command status, but the `result` column is the
authoritative classification when a status marker is used.

`--synthetic-ramfs` requires `--cmd` to contain `{script}`. `o9um.py` replaces
that placeholder with a host-generated rc script path as seen from 9front
through `/mnt/term`. The rc snippet passed to `--gate-rc` runs from the root of
the private ramfs worktree, not the real repo.

Good first Universal Mutator targets are:

```text
o9c/o9_type.c
o9c/grammar.d/70-typecheck.y
o9c/grammar.d/40-codegen.y
o9c/grammar.d/10-grammar-rules.y
```

The campaign wrapper has explicit source sets:

```sh
python3 tools/o9um.py list-targets
```

Run a sampled compiler campaign:

```sh
python3 tools/o9um.py batch --target-set compiler \
  --clean --limit 5 --seed 9009 --synthetic-ramfs \
  --timeout 180 --status-marker O9UM \
  --gate-rc 'fail=0
if(! mk ast-test) fail=1
if(! mk run-test) fail=1
if(~ $fail 0) echo O9UM pass
if not echo O9UM fail' \
  --cmd "PASS='\$Master001' timeout 150s drawterm -G -h dev9p.rentonsoftworks.coin -a Authomatic.rentonsoftworks.coin -u scott -c 'rc {script}'"
```

Run a sampled runtime/libtab campaign:

```sh
python3 tools/o9um.py batch --target-set runtime \
  --limit 1 --seed 9009 --synthetic-ramfs \
  --timeout 180 --status-marker O9UM \
  --gate-rc 'fail=0
if(! mk crypto-test) fail=1
if(! mk tab-test) fail=1
if(~ $fail 0) echo O9UM pass
if not echo O9UM fail' \
  --cmd "PASS='\$Master001' timeout 160s drawterm -G -h dev9p.rentonsoftworks.coin -a Authomatic.rentonsoftworks.coin -u scott -c 'rc {script}'"
```

Prefer focused gates. For example, `mk ast-test` is a good compiler
type/parser gate, and `mk crypto-test && mk tab-test` is a good local runtime
gate. Full transport gates such as `mk tabula-transport-test` are valuable
verification tests, but they are too slow to use as the default mutation gate
for every runtime mutant.

Run the maintained-source campaign as a long/nightly pass:

```sh
python3 tools/o9um.py batch --target-set all \
  --clean --limit 5 --seed 9009 --synthetic-ramfs \
  --timeout 300 --status-marker O9UM \
  --gate-rc 'fail=0
if(! mk ast-test) fail=1
if(! mk run-test) fail=1
if(! mk crypto-test) fail=1
if(! mk tab-test) fail=1
if(! mk function-object-contract-test) fail=1
if(~ $fail 0) echo O9UM pass
if not echo O9UM fail' \
  --cmd "PASS='\$Master001' timeout 270s drawterm -G -h dev9p.rentonsoftworks.coin -a Authomatic.rentonsoftworks.coin -u scott -c 'rc {script}'"
```

The mutation score is:

```text
killed / (killed + survived + timeout)
```

Known equivalent or out-of-target mutants are tracked in
`o9c/test/mutation_equiv.tsv` as exact `source, mutant, reason` triples.
`tools/o9um.py` reports them separately as `equivalent` and excludes them from
the score denominator. Do not add broad patterns here. A mutant only belongs in
that file when the behavior is actually impossible under the gate, such as an
allocator-failure branch with no fault injection or code under `#ifdef
__GNUC__` when the gate is native 9front.

The working project target is at least 90% on sampled campaigns and no known
survivors for hand-picked semantic mutants. A survivor is not just a score
problem; it is a missing executable invariant. Add the smallest regression
test that kills it, then rerun the same mutant set.

Do not mutate generated files such as `o9c/grammar.y`, `o9c/y.tab.c`, or temp
generated C. Mutating generated output tests yacc/codegen noise, not the source
rules we maintain.

Weaknesses of this approach:

- Sampled campaigns are evidence, not proof. `--limit 1` per source verifies
  the harness and catches broad gaps, but it does not exhaustively measure the
  source.
- The gate decides what a survivor means. A local runtime gate cannot kill a
  transport-only mutant; use a focused transport gate or classify the mutant
  exactly when the behavior is outside that gate.
- Equivalent classification is a sharp tool. Keep
  `o9c/test/mutation_equiv.tsv` small and exact. Broad equivalence rules make
  the score meaningless.
- Synthetic ramfs copies only the maintained inputs named by `tools/o9um.py`.
  If a future test depends on a new source directory, add it to the synthetic
  copy list before trusting mutation results for that path.
- Slow tests distort mutation work. Use `mk verify` for final confidence, but
  prefer small gates while developing tests for a surviving mutant.

## Duplicate Detection

PMD/CPD is a host-side static gate. It is not part of `mk verify` because PMD
runs on Linux, while `mk verify` runs the authoritative compiler/runtime checks
on 9front.

Run:

```sh
python3 tools/o9pmd.py
```

The wrapper scans:

- the assembled `o9c/grammar.d/*.y` grammar as a temporary `.c` file, using
  PMD's C++ tokenizer;
- o9-owned runtime/header C sources;
- Python host tools.

The initial thresholds are intentionally conservative:

```sh
python3 tools/o9pmd.py --cpp-min-tokens 220 --python-min-tokens 80
```

Use report mode when investigating known duplication without failing the
command:

```sh
python3 tools/o9pmd.py --report-only --cpp-min-tokens 100
```

Reports are written under `o9c/test/artifacts/`, which is ignored. Lower the
token thresholds as duplicated compiler/runtime code is extracted into named
helpers.

## Order

1. Keep the normal e2e suite green.
2. Use CRAP to shrink large compiler functions.
3. Use PMD/CPD to find repeated compiler/runtime shapes.
4. Add property tests for scalar language behavior and stable stdlib behavior.
5. Add fuzzing for parser/type/codegen edges.
6. Add mutation testing for language invariants.
