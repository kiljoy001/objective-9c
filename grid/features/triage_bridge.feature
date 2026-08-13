@triage
Feature: Triage bridge from grid results back to o9um recheck
  The grid runs mutants and writes one result file per task under results/.
  The interesting rows are survived (a missing test) and timeout (possibly a
  real hang or a flaky infra issue). The host-side o9um.py recheck workflow
  expects a triage TSV with a specific schema. This feature closes the loop:
  the grid (or a small python helper) exports its survived/timeout rows into
  the o9um triage schema so an operator can recheck just the actionable bucket
  after adding tests or equivalence entries.

  o9um triage schema (TRIAGE_HEADER):
    source  mutant  result  function  original_line  mutant_line
    triage_class  confidence  suggested_action  reason  diff_summary

  triage_class values relevant here:
    test_gap     the mutant survived -> a test is missing
    timeout      the mutant timed out -> real hang or flaky infra
    unknown      result could not be classified
    missing_report  a task with no result file

  Background:
    Given a finished campaign with result files under "results/"
    And the equivalence ledger at o9c/test/mutation_equiv.tsv

  # ---- export ----

  @new
  Scenario: Export maps grid results onto the o9um triage schema
    Given a survived result for source "o9c/o9_type.c" mutant "m01.c"
    When the triage bridge exports to triage.tsv
    Then triage.tsv has a header matching TRIAGE_HEADER
    And the row has source=o9c/o9_type.c mutant=m01.c result=survived triage_class=test_gap

  @new
  Scenario: Export includes timeout rows classified as timeout
    Given a timeout result for source "o9c/o9_type.c" mutant "m02.c"
    When the triage bridge exports to triage.tsv
    Then the row has result=timeout triage_class=timeout

  @new
  Scenario: Export excludes killed and setup_error rows
    Given 5 killed results and 1 setup_error result
    When the triage bridge exports to triage.tsv
    Then triage.tsv contains no rows with result=killed or result=setup_error

  @new
  Scenario: Equivalent mutants pre-classified against the ledger
    Given a survived result for source "o9c/o9_type.c" mutant "m03.c"
    And the ledger lists (o9c/o9_type.c, m03.c) as ledger_equivalent
    When the triage bridge exports with --classify-equivalent
    Then the row has result=equivalent triage_class=equivalent reason=already listed in the equivalence ledger

  @new
  Scenario: Whitespace-only mutants pre-classified as lexical_equivalent
    Given a survived result whose mutant differs from the source only in whitespace
    When the triage bridge exports with --classify-whitespace-equivalent
    Then the row has triage_class=equivalent reason=lexical_equivalent

  @new
  Scenario: Unproven likely-equivalent mutants are equivalent_candidate
    Given a survived result that is not in the ledger and not whitespace-only
    When the triage bridge exports
    Then the row has triage_class=equivalent_candidate
    And the suggested_action says it requires review and an exact ledger entry

  # ---- missing reports ----

  @new
  Scenario: A claimed task with no result file is flagged missing_report
    Given a task "t77" in tasks/done with no matching results/t77.tab
    When the triage bridge exports with --include-missing
    Then triage.tsv has a row for "t77" with triage_class=missing_report

  # ---- round-trip into recheck ----

  @new
  Scenario: The export is directly consumable by o9um.py recheck
    Given a triage.tsv produced by the bridge
    When o9um.py recheck runs with --triage triage.tsv --class test_gap,timeout --skip-baseline
    Then recheck accepts triage.tsv without a schema error
    And recheck re-runs only the test_gap and timeout mutants

  @new
  Scenario: The export preserves enough to recheck a single source
    Given a triage.tsv whose rows all come from one source
    When o9um.py recheck runs with --triage triage.tsv and --mutant-dir pointing at that source's mutants
    Then recheck resolves the mutant directory and re-runs the selected mutants

  # ---- source path translation ----

  @new
  Scenario: The export translates worker-visible plan9 paths back to repo-relative source paths
    Given a result whose source is /mnt/term/mnt/term/home/scott/Repo/objective-9c/o9c/o9_type.c
    When the triage bridge exports with --repo /home/scott/Repo/objective-9c
    Then the row's source column is o9c/o9_type.c (repo-relative)
    # So recheck, which runs host-side against the real checkout, can find the file.

  @new
  Scenario: The export is driven by the journal when available
    Given a root with a journal.log
    When the triage bridge exports with --from-journal
    Then it uses gate_exit events as the source of truth for results
    And tasks absent from the journal are not emitted
    # Prefer the journal over scanning results/ so the export and replay agree.
