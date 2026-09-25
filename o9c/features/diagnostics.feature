@diagnostics
Feature: Structured o9c compiler diagnostics
  o9c error messages should explain what failed, where it failed, and what the
  programmer can do next. Human output is for fast correction. Structured
  diagnostic records are for tests, tools, editors, mutation analysis, and
  replayable build reports.

  Diagnostic base fields:
    code        stable identifier such as O9E0001
    severity    error | warning | note
    phase       lex | parse | prescan | typecheck | import | codegen | link
    path        source file path
    line        1-based source line
    column      1-based source column when available
    span        byte or rune range when available
    message     concise human summary
    detail      optional expanded explanation
    hint        optional corrective action

  Background:
    Given o9c is invoked with diagnostics enabled
    And source paths are reported relative to the current project when possible

  # ---- human-facing diagnostics ----

  @new @human
  Scenario: A parse error reports source location and nearby token
    Given a source file "bad_parse.o9" with an unexpected token on line 7 column 14
    When o9c compiles "bad_parse.o9"
    Then it exits non-zero
    And stderr contains "bad_parse.o9:7:14"
    And stderr contains "error[O9E_PARSE]"
    And stderr names the unexpected token
    And stderr includes the source line and a caret under the token

  @new @human
  Scenario: An undeclared capitalized identifier includes the existing type hint
    Given a source file that uses "Widget" as a type without declaring it
    When o9c compiles the source
    Then stderr contains "error[O9E_UNDECLARED_TYPE]"
    And stderr says "'Widget' is not a declared type"
    And stderr includes the declaration context where the type was expected
    And the existing parser hint is preserved in the new diagnostic format

  @new @human
  Scenario: A type mismatch reports expected and actual types
    Given a method expects "int64"
    And the call passes "string"
    When o9c typechecks the source
    Then stderr contains "error[O9E_TYPE_MISMATCH]"
    And stderr contains "expected int64"
    And stderr contains "actual string"
    And stderr points at the expression that produced the actual type
    And stderr includes a note pointing at the method declaration

  @new @human
  Scenario: A missing method lists the receiver type and method name
    Given a source file calls "user.save()" on a receiver type "User"
    And "User" has no method named "save"
    When o9c typechecks the source
    Then stderr contains "error[O9E_NO_METHOD]"
    And stderr says "User has no method save"
    And stderr points at the method-send expression
    And stderr suggests similarly named methods when any exist

  @new @human
  Scenario: An import error preserves the full attempted search chain
    Given source imports "stdlib/journal.o9"
    And the file cannot be found in any import root
    When o9c resolves imports
    Then stderr contains "error[O9E_IMPORT_NOT_FOUND]"
    And stderr contains the import string "stdlib/journal.o9"
    And stderr lists each searched path in order
    And stderr points at the import statement

  @new @human
  Scenario: A raw C block error includes the generated C context
    Given a raw C block emits invalid Plan 9 C
    When o9c transpiles and the generated C compiler fails
    Then the diagnostic keeps the original .o9 source location
    And it includes the generated C file and line
    And it labels the phase as codegen or C compile
    And it preserves the Plan 9 C compiler message as a cause

  # ---- structured records ----

  @new @tooling
  Scenario: Every diagnostic has a stable machine-readable record
    Given o9c reports any error
    When diagnostics are collected
    Then the diagnostic record has code, severity, phase, path, line, column, message, and hint fields
    And code is stable across wording changes
    And message can change without breaking tests that assert code and location

  @new @tooling
  Scenario: Compiler output can be emitted as diagnostics.tab
    Given o9c is invoked with "--diagnostics-tab diagnostics.tab"
    And compilation fails with 2 errors and 1 note
    When o9c exits
    Then "diagnostics.tab" exists
    And it has the header "code	severity	phase	path	line	column	span	message	detail	hint"
    And it contains one row per diagnostic
    And tab, newline, and carriage return characters inside fields are escaped or sanitized

  @new @tooling
  Scenario: Human stderr and diagnostics.tab agree
    Given o9c is invoked with "--diagnostics-tab diagnostics.tab"
    And the compiler reports "O9E_TYPE_MISMATCH" on line 12
    When the command exits
    Then stderr contains "error[O9E_TYPE_MISMATCH]"
    And "diagnostics.tab" contains a row with code=O9E_TYPE_MISMATCH line=12
    And the human message is derived from the same diagnostic record as the tab row

  @new @tooling
  Scenario: Diagnostics can be filtered by severity
    Given compilation emits errors, warnings, and notes
    When o9c is invoked with "--diagnostic-severity error"
    Then stderr prints errors
    And stderr suppresses warnings and notes
    And diagnostics.tab still records all diagnostics unless "--diagnostics-filtered" is set

  # ---- multiple errors and recovery ----

  @new @recovery
  Scenario: Typechecking reports independent errors in one pass
    Given a source file contains 3 independent type errors
    When o9c typechecks the source
    Then it reports all 3 errors before exiting
    And each error has its own code and source location
    And one error does not cascade into duplicate follow-on messages for the same expression

  @new @recovery
  Scenario: Parser recovery suppresses noisy cascades
    Given a source file has one missing closing brace
    When o9c parses the source
    Then it reports the first parse error with location and context
    And it emits at most one follow-up note about parser recovery
    And it does not print dozens of unrelated syntax errors from later lines

  @new @recovery
  Scenario: A fatal internal compiler error keeps user context
    Given o9c hits an internal invariant failure while compiling a specific AST node
    When the compiler aborts the phase
    Then stderr contains "internal error"
    And the diagnostic includes the current source path and best-known node location
    And the diagnostic includes the compiler phase
    And it tells the user to file the minimized source and compiler version

  # ---- distributed build and mutation use cases ----

  @new @mutation
  Scenario: Mutation gates classify compiler diagnostics by code
    Given a mutation gate compiles a mutant that fails with O9E_TYPE_MISMATCH
    When the gate writes its log
    Then the log includes the diagnostic code
    And the mutation report can group killed mutants by diagnostic code
    And report analysis does not depend on matching fragile English text

  @new @distributed
  Scenario: Remote node diagnostics include node and worker provenance
    Given o9c runs inside a grid worker on node "dev9p.rentonsoftworks.coin"
    When compilation fails
    Then the worker can attach node, worker_id, task_id, and journal event id to the diagnostic record
    And the compiler diagnostic remains separate from the grid infrastructure error
    And report consumers can tell "program failed to compile" from "worker failed to run"

  @new @journal
  Scenario: Compiler diagnostics can be journaled without losing structure
    Given a grid worker receives structured diagnostics from o9c
    When it appends a gate_exit event
    Then the event detail includes diagnostic_code and diagnostic_phase
    And full diagnostic rows are written to a diagnostics tab file or artifact
    And the journal stays compact while preserving a link to the detailed records

  # ---- compatibility ----

  @new @compat
  Scenario: Existing simple stderr checks continue during migration
    Given an existing test asserts that stderr contains "duplicate enum value"
    When diagnostics are upgraded
    Then stderr still contains the phrase "duplicate enum value"
    And it also contains the stable diagnostic code
    And tests can migrate from phrase checks to code checks incrementally

  @new @compat
  Scenario: Diagnostic codes are documented and reserved
    Given a diagnostic code is introduced
    When it ships in a release
    Then the code is added to the diagnostics reference
    And the code is never reused for a different meaning
    And deprecated diagnostics remain documented with replacement guidance
