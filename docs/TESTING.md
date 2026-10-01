# Testing Strategy

o9 tests should run on 9front and exercise the real transpiler, generated C,
and runtime. Host-side scripts can generate inputs or reports, but the
authoritative behavior checks should compile and run through `mk`.

## Current Layers

- `mk unit-test`: native C unit suites built on the `o9test` harness
  (see "Unit Testing" below).
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

## Generated Plan 9 C

`mk plan9-c-test` checks representative class, generic, tuple, spawn, scalar,
channel, alt, state, and raw-C interop output, then compiles, links, and runs those programs using
the native e2e harness. It is included in `mk verify`.

Compiler-owned output uses native headers and types, `nil`, libthread
channels, and libc's `ainc`/`adec` atomics. Function definitions put the return
type, signature, and opening brace on separate lines. Struct typedefs are
separate from their definitions, with one member declaration per line.
Automatic declarations and initialization are separate. Generated indentation
uses tabs, with `if(...)`, `for(...)`, and `while(...)` spacing following
Plan 9 `style(6)`. Existing ABI names and control-flow lowering are retained.
Edit the templates in `o9c/grammar.d/`, not generated C. Raw-C interop bodies
are preserved as written and excluded from the structural style checks.

The gate also verifies that each generated ARC attach/detach pair addresses
the same ledger slot. It is a structural regression check plus native
execution, not a complete C style checker or an ARC leak detector.

## Original source locations

`mk source-map-test`, also in `mk verify`, transpiles, compiles, links, and
runs a fixture with nested imports, a stripped imported main, multiline
statements, deferred calls, branches, and raw C with a continued macro.
It checks emitted return-statement locations, scans actual PCs within the
expected functions using libmach, then asks Acid to report those PCs' files
and lines. Removing the directives must make the PC checker fail. A separate
invalid raw-C fixture must produce a compiler error at its original `.o9`
file and line. The import fixture also exercises a source line over 1023 bytes.

All C emission goes through `cprint` in `21-source-map.y`, including output
from `02-type-helpers.y`, `40-codegen.y`, `50-app-facade.y`, and `91-cdeps.y`.
AST nodes retain original file/line locations through import splicing.
Generated statement lines are pinned to the statement's first source line;
raw C retains its own successive line numbers. Generated scaffolding uses
`<o9-generated>`, and input supplied without a filename uses `<stdin>`.
For locations after line 1, a blank spacer after an adjusted `#line` keeps
code beyond Plan 9 libmach's history boundary while preserving cc's line count.
Exact debugger attribution to source line 1 remains a native libmach boundary
limitation: `#line 1` preserves compiler diagnostics, but may have no matching
PC. Put executable statements after the first source line when checking Acid
locations. This gate does not change the native debugger.

Generated C also contains readable source comments. Each lowered statement
has an adjacent annotation, for example:

```c
/* o9: example.o9:4 | int64 value = 7; */
```

A numbered `/* o9 source: ... */` section at the end contains each original
file, including imports, so multiline statements can be read in full beside
their line references. Source text is captured before import rewriting.
Comment terminators are displayed as `* /`, and control characters are
escaped, so source text cannot accidentally end a generated comment.
Annotations are outside raw-C bodies and precede the restored `#line`
directives; they do not change compiler/debugger locations. They are C
comments, with no source bundle or extraction utility in the executable.

These checks establish source locations for representative emitted code;
optimization can remove statements or merge their instructions, so they do
not promise a distinct PC for every source line. `mk debug-test` separately
tests the 9P debug-state view. Local actors
use libthread channels, so actor scheduling and UI ownership tests should be
separate from 9P facade/session transport tests.

## Unit Testing

Unit tests run natively on 9front against compiler and runtime internals,
where a failure is cheap to localize. They use `o9test`, a small harness in
`o9c/test/o9test.h`.

The point of the harness is that **a failing check does not stop the run**.
The older native tests call `sysfatal` on the first bad value, so a change
that breaks twenty things reports one, and you find the next failure only
after fixing this one. `o9test` records each failure with its case, its
check name, and the got/want pair, then keeps going, so one run tells you
everything that is broken.

```c
#include <u.h>
#include <libc.h>
#include "o9test.h"

static void
test_basename(void)
{
	O9T_CASE("o9_basename_c");
	o9t_eqstr("nested", o9_basename_c("a/b/c"), "c");
	o9t_eqint("suffix match", o9_has_suffix("x.tab", ".tab"), 1);
}

void
main(int, char**)
{
	o9t_begin("mytest");
	test_basename();
	exits(o9t_report());
}
```

`o9t_report()` prints the summary and returns nil only when every check
passed, so `exits(o9t_report())` gives `mk` the non-zero exit it needs.
Suites that link `libo9.a` pull in the thread library, so they use
`threadmain` and `threadexitsall(o9t_report())` instead.

Checks: `o9t_ok`, `o9t_eqint`, `o9t_eqstr` (nil-safe, and nil is *not*
equal to `""`), `o9t_eqmem` (reports the first differing byte), `o9t_nil`,
`o9t_notnil`, `o9t_fail` (printf-style, for conditions the others do not
express), and `o9t_skip` (counted and listed, but does not fail the run —
so a disabled check stays visible). Each check returns 1 on pass and 0 on
fail, so a caller can guard follow-on work that would crash on a bad
value:

```c
if(o9t_notnil("parsed", p))
	o9t_eqstr("field", p->name, "x");
```

Disk-touching tests use `o9t_tmpdir()` and `o9t_tmppath()`, which honour
`$TMP` so a host with a read-only `/tmp` (a shared drawterm server) can
redirect them.

Current suites:

- `mk o9test-selftest`: the harness proving itself. It exercises both the
  passing and the failing arm of every check, since a library that reports
  a pass for a failing check would silently invalidate every suite above
  it.
- `mk type-test`: the compiler's type-builtin table and render helpers.
- `mk runtime-helpers-test`: the runtime's file, journal, and path
  primitives the grid is built on — `o9_append_event`, `o9_journal_split`,
  `o9_count_dir`, `o9_has_suffix`, `o9_basename_c`,
  `o9_strip_repo_prefix`, `o9_read_file_c`, `o9_kv_int`,
  `o9_tsv_get_col(s)`, `o9_hash`.
- `mk runtime-registry-test`, `mk runtime-9p-rpc-test`: object registry
  generations and 9P response framing.

When adding a unit suite, write the failing case first and confirm it
fails for the stated reason. A suite that passes on a deliberately broken
copy of the code under test is not testing it: the three mutants used to
validate `runtime-helpers-test` (a flipped `o9_has_suffix` boundary, a
dropped field reset in `o9_journal_split`, and a removed file/directory
partition in `o9_count_dir`) were each caught by a specific named check.

Where a test pins behavior that is arguably wrong, say so in the test
rather than quietly asserting the bug. `o9_tsv_get_col` reports a
header-only file as `found=1` with an empty value, which is
indistinguishable from a real row with an empty cell; the suite records
both, so tightening the runtime later has an obvious place to update.

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

### Invariant Dashboard

Known compiler semantic invariants are cataloged in
`o9c/test/invariants.tab`. Each row names the invariant, the checked-in tests
that exercise it, the semantic mutant(s) that break it, and the focused gate
that must kill those mutants. Run the registry gate:

```sh
mk invariant-test
```

or directly:

```sh
python3 tools/o9invariant.py run --keep-going
```

The dashboard first checks that each listed test file exists and that the
unmutated gate passes. It then applies each named semantic mutant with
`tools/o9mutate.py`, runs the assigned gate, restores the source, and reports
`killed`, `survived`, `timeout`, or `setup_error`. A semantic mutant must not
survive. Equivalent semantic mutants are not accepted; if one is equivalent,
replace the mutant with one that really violates the invariant. Timeouts are
reported separately because the self-send guard mutant is killed by the
deadlock it would otherwise reintroduce.

Semantic mutation runs take a shared `/tmp/o9mutate.lock` while a source file
is mutated and its gate is running. Do not bypass that lock with ad hoc
rewrites; two concurrent mutation runs against one checkout can corrupt the
working tree.

Good invariant rows use focused gates such as `ast-test`,
`function-object-contract-test`, or `run-test:e2e_widths,e2e_cast` instead of
the full `mk verify` target. New compiler features should update
`invariants.tab` and add at least one named semantic mutant before relying on
sampled Universal Mutator campaigns.

When running from the host with drawterm, wrap each gate command with
`O9_INVARIANT_CMD_TEMPLATE` and set `O9_INVARIANT_STATUS_MARKER` so drawterm's
exit status cannot hide a remote test failure. The template must contain
`{gate}`, which is replaced by the registry gate command.

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

Use sampled campaigns only for quick harness checks. The real audit uses
`--exhaustive` and lets the run finish instead of stopping on the first live
mutant. Per-mutant reports are streamed to `o9c/test/artifacts/o9um_<source>.tsv`
as each mutant completes, so an interrupted run can be resumed with
`--resume-report` for one source or `--resume-reports` for a batch target set.
`--stop-on-survive` is for debugging one mutant locally; do not use it for a
real campaign.

Run a quick sampled compiler campaign:

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

Run the maintained-source campaign as a real unattended pass:

```sh
python3 tools/o9um.py batch --target-set all \
  --clean --exhaustive --resume-reports --synthetic-ramfs \
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

For a resumed unattended pass, rerun the same command without `--clean`.
`o9um.py` skips mutant names already present in the streamed per-source report
and appends new rows as each remaining mutant completes. For a single source,
use `run --exhaustive --resume-report o9c/test/artifacts/o9um_o9c_o9_type.c.tsv`
with the same gate arguments.

After a batch campaign, classify all live rows into one triage report:

```sh
python3 tools/o9um.py triage-batch --target-set all \
  --mutant-root /tmp/o9um-batch \
  --output o9c/test/artifacts/o9um_batch_all.triage.tsv
```

### 3-node 9front grid campaign

For long native 9front campaigns, generate Universal Mutator files on the host
once, then let the o9 grid drain the queue through the shared 9P fileserver.
The host-side generator writes worker-visible mutant paths and a small rc
enqueue wrapper:

```sh
python3 tools/o9grid_um_manifest.py --target-set all \
  --mutant-root o9c/test/artifacts/o9um-grid-mutants \
  --manifest o9c/test/artifacts/o9um_grid_manifest.tsv \
  --enqueue-rc o9c/test/artifacts/o9um_grid_enqueue.rc \
  --timeout-ms 300000
```

From drawterm on `dev9p`, launch persistent workers across the three nodes:

```rc
cd /mnt/term/home/scott/Repo/objective-9c
root=/n/babyFileServer.rentonsoftworks.coin/tmp/o9mut-campaign
rc grid/run_3node_campaign.rc \
  -r $root \
  -n 3 \
  -j 0 \
  -E /mnt/term/home/scott/Repo/objective-9c/o9c/test/artifacts/o9um_grid_enqueue.rc \
  dev9p authomatic babyFileServer.rentonsoftworks.coin
```

The launcher asks you to confirm that `rcpu` login has already been warmed for
each node, then runs an auth probe before launching workers. After you have
already done that preflight and want a non-interactive rerun, pass `-y`. Use
`-A` only when intentionally skipping the rcpu probe.

`-j 0` keeps workers alive until drained. Monitor from `dev9p`:

```rc
$root/bin/o9mutctl -r $root status
ls $root/results | wc -l
```

To stop the campaign cleanly, request a drain for each worker; workers finish
their current task and then exit:

```rc
for(n in dev9p authomatic babyFileServer.rentonsoftworks.coin)
  for(i in 1 2 3)
    $root/bin/o9mutctl -r $root drain-worker $n^-$i
```

The triage report has one row per survived or timed-out mutant. Exact ledger
matches are `ledger_equivalent`; whitespace/comment-only changes are
`lexical_equivalent` in triage and can be preclassified during the run with
`--classify-whitespace-equivalent`; likely but unproven cases are only
`equivalent_candidate`. Candidates still require review and an exact
`o9c/test/mutation_equiv.tsv` entry before they stop counting as open work.

After adding tests or exact equivalence entries, recheck only the actionable
bucket instead of rerunning the whole campaign:

```sh
python3 tools/o9um.py recheck \
  --triage o9c/test/artifacts/o9um_batch_all.triage.tsv \
  --mutant-root /tmp/o9um-batch \
  --class test_gap,timeout \
  --skip-baseline --synthetic-ramfs \
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

The working project target is zero live survivors in `mk invariant-test` and
zero live survivors in the real maintained-source Universal Mutator campaign
after exact equivalents are removed. Sampled campaigns are only harness checks.
A survivor is not just a score problem; it is a missing executable invariant.
Add the smallest regression test that kills it, then rerun the same mutant set.

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

## Actor Concurrency and Lifecycle Testing

Actor interactions are checked as end-to-end tests under `mk run-test` and
`mk verify`:

- `e2e_actor_cycle.o9`: Multi-hop and 1-hop direct synchronous actor call
  cycle detection. The runtime wait-for graph (`o9_call_edges[]` in
  `o9_runtime.c`) runs `o9_path_exists_locked(callee, caller)` prior to
  allowing any thread to block in `recvp(reply_chan)`. When a circular
  dependency is detected ($A \to B \to A$), the runtime aborts the call
  immediately without blocking, sets `werrstr("actor call cycle detected")`,
  and returns `nil`/`-1`/`0.0`, allowing the caller's `try` block to catch
  the error cleanly.
- `e2e_actor_exit.o9`: Premature worker exit recovery. When an asynchronous
  actor task is spawned (`task = spawn worker.run()`), the forwarder captures
  the worker thread's libthread thread ID (`tid = proccreate(...)`). If the
  worker proc terminates without writing to `replyc`, the forwarder polls
  `nbrecvp` and detects termination via `threadpid(tid) < 0`, injecting a
  synthetic `O9Reply` with error `"actor exited without reply"`. This unblocks
  the awaiting caller cleanly.
- `e2e_channel_handles.o9`: Stale channel object handle safety. When an actor
  or channel object is deallocated via ARC / `delete`, teardown invokes
  `chanclose(self->dispatch_chan)` rather than `chanfree`, keeping the channel
  header allocated as an immutable tombstone. Senders inspect
  `chanclosing(obj->dispatch_chan)` and verify `sendp(...) < 0`, returning
  `"stale object handle"` instead of panicking on `libthread` assertion
  failures (`assert(c->e == sizeof(void*))`).

## Order

1. Keep the normal e2e suite green.
2. Use CRAP to shrink large compiler functions.
3. Use PMD/CPD to find repeated compiler/runtime shapes.
4. Add property tests for scalar language behavior and stable stdlib behavior.
5. Add fuzzing for parser/type/codegen edges.
6. Add mutation testing for language invariants.
