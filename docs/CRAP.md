# Transpiler CRAP Score

CRAP combines complexity and coverage:

```text
CRAP = complexity^2 * (1 - coverage)^3 + complexity
```

For o9c, coverage is collected on 9front from the real transpiler test suite.
Because Plan 9 C does not have gcov, the harness uses generated block
instrumentation:

- every discovered C function gets an entry counter;
- every brace-delimited control block gets a counter;
- coverage is covered counters / total counters for that function;
- complexity is cyclomatic complexity from the generated C.

This is not fake static scoring. The hit counts come from running an
instrumented `o9c` against the existing tests.

## Run

After changing `o9c/grammar.y`, run a normal 9front build first so
`o9c/y.tab.c` is current:

```rc
mk o9c
```

Then, from the host side, generate the instrumented yacc output:

```sh
python3 tools/o9crap.py instrument
```

Then run the 9front harness:

```rc
mk crap-test
```

That temporarily swaps in `o9c/test/artifacts/y.tab.crap.c`, rebuilds `o9c`,
runs the main transpiler-facing tests, writes
`o9c/test/artifacts/o9crap_counts.tsv`, and restores the normal generated
source and binary.

Finally, generate the report:

```sh
python3 tools/o9crap.py report
```

The default report is written to:

```text
o9c/test/artifacts/o9crap_report.tsv
```

The console output is sorted worst-first and is the starting point for
refactoring. High CRAP means high complexity with poor observed coverage.

To hide yacc skeleton helpers and focus on o9-owned code:

```sh
python3 tools/o9crap.py report --ignore '^yy'
```

To enforce the strict “under 5” goal for owned code:

```sh
python3 tools/o9crap.py report --ignore '^yy' --max-crap 5 --fail
```

Because CRAP is always at least cyclomatic complexity, this target implies
every passing function must have CC 4 or lower.

## Interpreting Results

Use the ranking as a triage list, not as a moral score.

- High complexity and low coverage: refactor or add direct tests first.
- High complexity and high coverage: risky but currently exercised.
- Low complexity and low coverage: usually not worth refactoring yet.

For yacc-generated code, ignore parser skeleton helpers unless they dominate
the list. The targets that matter most are the o9 semantic/typecheck/codegen
functions from `grammar.y`.

## First Baseline

The first real run ranked the worst owned functions like this:

```text
CRAP     CC   COV%   FUNCTION
5411.03  337  64.5   typecheck_expr
3101.69  230  62.1   gen_stmt
984.14   221  75.0   gen_expr
491.12   181  78.8   yylex
210.00   147  85.7   gen_class_server
```

After the first refactor, `typecheck_expr` delegates major semantic branches
to helper functions. Its measured score dropped to:

```text
CRAP     CC   COV%   FUNCTION
1953.52  139  54.5   typecheck_expr
```

The second refactor made `gen_stmt` a dispatcher and moved statement lowering
into named helpers. Its measured score dropped to:

```text
CRAP    CC  COV%  FUNCTION
40.25   28  75.0  gen_stmt
```

That exposed the next real codegen target:

```text
CRAP    CC   COV%  FUNCTION
966.00  117  60.4  gen_assign_stmt
```

## Current Shape

After the cleanup passes, the former worst functions have been split:

- `typecheck_expr` became a semantic dispatcher.
- `gen_stmt` became a statement dispatcher.
- `gen_expr` and assignment lowering were split into focused helpers.
- dead per-class handler emitters were removed.
- `scan_buffer` was split into prescan helpers.
- `gen_class_server` now delegates state layout, methods, cleanup, dispatch,
  instance bookkeeping, generated 9P read/write handlers, spawn helpers, and
  registration.
- dead helpers such as `scan_file`, `channel_box_storage`,
  `resolve_object_sym`, and `alt_target_storage` were removed.
- `rawc_forbidden_ident`, `validate_type`, `load_project_cdeps`,
  `gen_class_method_artifacts`, `gen_assign_new_to`,
  `type_storage_for_codegen`, `typecheck_assign_expr`, and `check_node`
  were split into smaller helpers.

The current worst owned functions after regenerating instrumentation and
running `mk crap-test` are:

```text
CRAP   CC   COV%   FUNCTION
23.20  20   80.0   main
20.00  4    0.0    gen_msg_typed_receiver
19.00  19   100.0  gen_dispatch_cases
19.00  19   100.0  gen_class_spawn_helper
19.00  19   100.0  type_cast_for_codegen
18.52  15   75.0   gen_state_store_typed
18.05  16   80.0   typecheck_local_var_expr
18.00  18   100.0  typed_member_lookup_in
18.00  18   100.0  gen_method_registrations
17.56  13   70.0   gen_class_fsread_props
```

`gen_class_server` is no longer the top offender; the facade split moved its
branches into named read/write helpers. The strict target is still far away:
the current report has 223 owned functions above CRAP 5. That count can rise
temporarily when large functions are split, because newly visible helper
branches get scored independently. The useful short-term signal is that the
worst owned score has dropped from thousands to `23.20`. The strict target
still implies either very small functions or direct coverage of every branch.

## Next Refactors

The next useful reductions are:

- split `main` into source loading, import resolution, scan/typecheck,
  generation, and cleanup phases;
- decide whether `gen_msg_typed_receiver` is a live missing test path or dead
  code, since it has low complexity but zero measured coverage;
- split dispatch/spawn codegen helpers such as `gen_dispatch_cases` and
  `gen_class_spawn_helper` without changing their emitted C shape;
- add direct tests for partly covered state/typecheck paths such as
  `gen_state_store_typed`, `typecheck_local_var_expr`, and
  `gen_class_fsread_props`;
- use PMD/CPD reports to remove duplicated semantic checks before adding new
  compiler features.

Prefer reducing high-complexity functions before adding broad mutation tests.
Mutation testing is most useful once mutants point to real missing behavior
tests rather than giant helper functions with several unrelated branches.
