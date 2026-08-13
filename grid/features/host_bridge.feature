@host_bridge
Feature: Host-side bridges — Python tools that write the same 9P layout
  Two Python helpers let the host prepare work for the grid without invoking
  the o9 tools. They write the EXACT same file layout the o9 side produces, so
  a root prepared by Python is indistinguishable from one prepared by
  o9mutctl. These are bridges, not the runner: Universal Mutator generates
  mutants on the host while the o9 grid drains them through 9P.

  Background:
    Given a host checkout of the repo
    And a grid root path on the shared 9P fileserver

  # ---- o9grid_prepare.py: layout + enqueue ----

  @existing
  Scenario: `init` creates the full grid layout and a default config.tab from the host
    When o9grid_prepare.py runs `init --root <root>`
    Then tasks/pending tasks/claimed tasks/done queue/chunks/pending queue/chunks/claimed queue/chunks/done workers results logs repo mutants reports all exist
    And config.tab exists with schema=o9mut-grid-v1 heartbeat_sec=30 stale_sec=300 max_attempts=3
    # This mirrors o9mutctl init; the resulting root is compatible with the o9 workers.

  @existing
  Scenario: `enqueue` writes a single task row atomically
    When o9grid_prepare.py runs `enqueue --root <root> --task-id t1 --source s --mutant-path m --gate g`
    Then "tasks/pending/t1.tab" exists with the header and a data row
    And it was written via a tmp file renamed into place (atomic replace)

  @existing
  Scenario: enqueue defaults timeout-ms=300000 and priority=100
    When o9grid_prepare.py enqueues without specifying timeout or priority
    Then the task row has timeout_ms=300000 and priority=100

  @existing
  Scenario: enqueue sanitises tab/newline/CR out of every field
    When o9grid_prepare.py enqueues with a source containing a tab and newline
    Then no field in the task row contains a tab or newline inside its value
    # clean_field replaces tab/newline/CR with space.

  @existing
  Scenario: enqueue generates an id from time+pid when task-id is empty
    When o9grid_prepare.py enqueues with an empty task-id
    Then a task file matching "tasks/pending/task.*.tab" exists
    And the id contains no slash characters

  @existing
  Scenario: `manifest` bulk-loads a TSV and reports the count
    Given a manifest TSV with 7 data rows and the required columns
    When o9grid_prepare.py runs `manifest --root <root> --manifest <file>`
    Then 7 task files exist under "tasks/pending/"
    And it prints "enqueued\t7"

  @existing
  Scenario: `manifest` rejects a TSV missing required columns
    Given a manifest TSV without a mutant_path column
    When o9grid_prepare.py runs `manifest`
    Then it exits non-zero with "manifest missing columns: mutant_path"

  @existing
  Scenario: `manifest` lets each row override timeout_ms, priority, and attempt
    Given a manifest TSV whose rows carry timeout_ms, priority, and attempt columns
    When o9grid_prepare.py runs `manifest`
    Then each task row uses the row's own timeout_ms, priority, and attempt
    And rows missing those columns fall back to the defaults (timeout 300000, priority 100, attempt 0)

  @existing
  Scenario: `from-dir` enqueues one task per file in a mutants directory
    Given a mutants directory with 3 mutant files under subdirs
    When o9grid_prepare.py runs `from-dir --root <root> --source s --mutants-dir <dir> --gate g`
    Then 3 task files exist under "tasks/pending/"
    And each task id is "<source-name>.<relpath with slashes replaced by underscore>"

  # ---- o9grid_um_manifest.py: manifest + enqueue-rc generation ----

  @existing
  Scenario: It generates a manifest TSV with the 6-column header
    When o9grid_um_manifest.py runs against a target set
    Then the manifest file has the header "task_id source mutant_path gate timeout_ms priority"
    And one row per selected mutant

  @existing
  Scenario: Mutant paths are translated to the worker-visible plan9 prefix
    When o9grid_um_manifest.py runs with --plan9-prefix /mnt/term/mnt/term
    Then each row's mutant_path is the host path prefixed with /mnt/term/mnt/term
    So a worker reaching the host via rcpu can read the mutant

  @existing
  Scenario: The gate path defaults to the repo's grid/o9um_gate.rc under the plan9 prefix
    When o9grid_um_manifest.py runs without --gate-plan9-path
    Then each row's gate is <plan9-prefix>/<repo>/grid/o9um_gate.rc

  @existing
  Scenario: A custom gate path can be supplied
    When o9grid_um_manifest.py runs with --gate-plan9-path /mnt/term/mnt/term/custom/gate.rc
    Then each row's gate is that custom path

  @existing
  Scenario: --limit caps the mutants selected per source
    Given a source with 20 available mutants
    When o9grid_um_manifest.py runs with --limit 5
    Then the manifest has 5 rows for that source

  @existing
  Scenario: --seed makes mutant selection reproducible
    When o9grid_um_manifest.py runs twice with --seed 9009
    Then both manifests select the same mutants in the same order

  @existing
  Scenario: --clean discards and regenerates an existing mutant directory
    Given a pre-existing mutant directory with stale mutants
    When o9grid_um_manifest.py runs with --clean
    Then the mutant directory is removed and regenerated

  @existing
  Scenario: Existing mutants are reused when --clean is not given
    Given a mutant directory already populated for a source
    When o9grid_um_manifest.py runs without --clean
    Then the mutants are not regenerated
    And the manifest is built from the existing files

  @existing
  Scenario: It also writes an enqueue rc wrapper
    When o9grid_um_manifest.py runs
    Then an executable enqueue rc script is written at --enqueue-rc
    And the script takes the root as $1

  @existing
  Scenario: Bulk enqueue mode calls o9mutctl manifest once with the manifest path
    When o9grid_um_manifest.py runs without --inline-enqueue
    Then the enqueue rc runs `o9mutctl -r $root manifest <enqueue-prefix manifest path>`
    And it greps the log for manifest_enqueued and fails if the count is zero

  @existing
  Scenario: Inline enqueue mode calls o9mutctl enqueue once per row
    When o9grid_um_manifest.py runs with --inline-enqueue
    Then the enqueue rc has one `o9mutctl enqueue` command per manifest row
    And each field is single-quote-escaped for rc (inner quotes doubled)

  @existing
  Scenario: The enqueue rc checks the o9mutctl binary exists before enqueuing
    When the generated enqueue rc runs
    Then it first checks $root/bin/o9mutctl exists and exits missing if not

  @existing
  Scenario: It reports the mutant count and output paths when done
    When o9grid_um_manifest.py finishes
    Then it prints mutants=<n> manifest=<path> enqueue_rc=<path>

  # ---- compatibility with the o9 side ----

  @existing
  Scenario: A Python-prepared root is consumable by the o9 workers unchanged
    Given a root prepared by o9grid_prepare.py with enqueued tasks
    When o9mutw runs against that root
    Then it claims and runs the tasks and writes results just as it would for an o9-enqueued root
    # The file layout is the contract; both sides produce the same shape.
