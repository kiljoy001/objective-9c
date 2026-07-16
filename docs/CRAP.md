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
CRAP   CC  COV%  FUNCTION
34.34  34  93.3  check_inheritance_contract
31.05  30  89.5  try_raw_c_block
30.64  29  87.5  validate_rawc_boundary
30.00  12  50.0  gen_class_prop_write
26.96  8   33.3  strip_imported_main
26.50  9   40.0  typecheck_generic_msg
26.12  11  50.0  find_main_block_start
26.12  11  50.0  type_contains_address_scalar
24.00  24  100.0 gen_class_ctl_method_cases
23.20  20  80.0  main
```

`gen_class_server` is no longer the top offender; the facade split moved its
branches into named read/write helpers. The strict target is still far away:
the current report has 216 owned functions above CRAP 5. That count can rise
temporarily when large functions are split, because newly visible helper
branches get scored independently. The useful short-term signal is that the
worst owned score has dropped from thousands to `34.34`. The strict target
still implies either very small functions or direct coverage of every branch.

## Next Refactors

The next useful reductions are:

- split `check_inheritance_contract` into local conflict, inheritance rule,
  override, and abstract-method enforcement helpers;
- split raw-C parsing/validation further: `try_raw_c_block` and
  `validate_rawc_boundary`;
- split generated facade property writes in `gen_class_prop_write`;
- split import-main stripping helpers: `strip_imported_main` and
  `find_main_block_start`;
- decide whether low-coverage helpers such as `gen_msg_typed_receiver`,
  `gen_print_explicit_args`, and `gen_raw_func_call_expr` need direct tests
  or are now stale paths.

Prefer reducing high-complexity functions before adding broad mutation tests.
Mutation testing is most useful once mutants point to real missing behavior
tests rather than giant helper functions with several unrelated branches.
