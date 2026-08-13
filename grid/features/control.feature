@control
Feature: o9mutctl — the control-plane CLI for the grid
  o9mutctl is the operator's interface: it inits the root, enqueues work,
  inspects status, recovers stale claims, drains workers, and (new) waits for
  the grid to drain and exports a triage report. Every mutating subcommand
  emits a journal event as its observable side effect (see event_journal).

  Usage:
    o9mutctl [-r root] <command> [args...]

  Background:
    Given a grid root initialised at a shared 9P path

  # ---- init ----

  @existing
  Scenario: init creates the full directory layout and a default config.tab
    When the control command runs init on an empty root
    Then directories tasks/pending tasks/claimed tasks/done queue/chunks/pending queue/chunks/claimed queue/chunks/done workers results logs repo mutants reports all exist
    And "config.tab" exists with schema=o9mut-grid-v1 heartbeat_sec=30 stale_sec=300 max_attempts=3

  @existing
  Scenario: init is idempotent and does not clobber an existing config.tab
    Given a root with a config.tab whose max_attempts=9
    When the control command runs init again
    Then config.tab still has max_attempts=9
    And all directories still exist

  @existing
  Scenario: init reports failure when the pending dir could not be created
    When the control command runs init on a path that cannot be created
    Then it prints "init failed" and returns non-zero

  # ---- status ----

  @existing
  Scenario: status reports pending, claimed, done, and per-result counts
    Given 2 pending tasks, 1 claimed task, 3 done results (1 killed, 1 survived, 1 timeout)
    When the control command runs status
    Then the output has lines pending=2 claimed=1 done=3
    And lines killed=1 survived=1 timeout=1

  @existing
  Scenario: status reports a header and the root path
    When the control command runs status
    Then the first line is "o9mut grid status"
    And the next line is "root\t<root>"

  @existing
  Scenario: status reports chunk counts alongside task counts
    Given 2 pending chunks, 1 claimed chunk, 4 done chunks
    When the control command runs status
    Then the output has lines chunks_pending=2 chunks_claimed=1 chunks_done=4
    # The two-tier queue surfaces both the chunk and task tiers in one status view.

  @existing
  Scenario: status reports equivalent, infra_fail, and setup_error counts
    Given done results including 1 equivalent, 1 infra_fail, and 1 setup_error
    When the control command runs status
    Then the output has lines equivalent=1 infra_fail=1 setup_error=1

  @new @hygiene
  Scenario: status counts tasks by .tab suffix, not by name length
    Given a pending dir containing "t1.tab", "ab.tab", and a stray "x" file
    When the control command runs status
    Then pending counts only files ending in .tab and skips dot-entries
    # Replaces the brittle strlen(name) > 4 heuristic.

  @new @hygiene
  Scenario: status reads result rows by parsing the result column, not by hand-walked offsets
    Given a result row whose log_path contains a tab-stripped value with many fields
    When the control command runs status
    Then the result class is read from the result column by name, not by counting tabs
    # Replaces the 4x manual tab-walk field parser (the current code skips
    # task_id, worker_id, source, mutant_path, then reads result).

  # ---- report ----

  @existing
  Scenario: report writes the current status to reports/latest.tab
    When the control command runs report
    Then "reports/latest.tab" contains the status text
    And report returns the status text

  # ---- enqueue / manifest ----

  @existing
  Scenario: enqueue with too few args prints usage
    When the control command runs enqueue with only a task id
    Then it prints the enqueue usage line and creates no task

  @existing
  Scenario: manifest with a missing manifest path prints usage
    When the control command runs manifest with no path
    Then it prints the manifest usage line

  # ---- requeue-stale ----

  @existing
  Scenario: requeue-stale uses the provided stale-seconds argument
    When the control command runs requeue-stale 120
    Then it releases claims older than 120 seconds
    And it prints the count of released claims

  @existing
  Scenario: requeue-stale defaults to 300 seconds when no argument is given
    When the control command runs requeue-stale with no argument
    Then it releases claims older than 300 seconds

  @new @crash
  Scenario: requeue-stale releases both stale chunks and stale tasks
    Given 1 stale chunk claim and 2 stale task claims
    When the control command runs requeue-stale
    Then it reports requeued_chunks=1 and requeued_tasks=2

  # ---- drain-worker ----

  @existing
  Scenario: drain-worker writes a drain marker the worker checks on its next loop
    When the control command runs drain-worker dev9p-2
    Then "workers/dev9p-2.drain" exists
    And the worker exits after finishing its current task

  @existing
  Scenario: drain-worker with no worker id prints usage
    When the control command runs drain-worker with no argument
    Then it prints the drain-worker usage line

  # ---- wait-drain (new) ----

  @new @unattended
  Scenario: wait-drain blocks until the grid is fully drained
    Given 2 pending tasks and 1 claimed task and 1 pending chunk
    When the control command runs wait-drain
    Then it polls status until pending=0 claimed=0 chunks_pending=0 chunks_claimed=0
    And it returns once all four are zero

  @new @unattended
  Scenario: wait-drain respects a timeout and exits non-zero if not drained in time
    Given a grid that never drains
    When the control command runs wait-drain --timeout 60
    Then it exits non-zero after 60 seconds and reports "drain timed out"

  @new @unattended
  Scenario: wait-drain polls at a configurable interval
    When the control command runs wait-drain --poll-ms 500
    Then it re-checks status no more often than every 500ms

  # ---- triage export (new) ----

  @new @triage
  Scenario: triage exports survived and timeout rows for recheck
    Given 2 survived results and 1 timeout result and 5 killed results
    When the control command runs triage --output grid_triage.tsv
    Then "grid_triage.tsv" has a row for each survived and timeout task
    And each row has source, mutant_path, result, task_id, and worker_id
    And killed tasks are not included

  @new @triage
  Scenario: triage rows are consumable by o9um.py recheck
    Given a triage export produced by the control command
    When o9um.py recheck reads it with --triage grid_triage.tsv --class test_gap,timeout
    Then recheck accepts the file and selects the matching rows
    # The export maps grid result columns onto the o9um triage schema.

  # ---- journal surface (new) ----

  @new @journal
  Scenario: every mutating control command emits a journal event
    When the control command runs enqueue, manifest, requeue-stale, and drain-worker
    Then the journal contains an enqueue event, a manifest_chunked event, chunk_requeue/task_requeue events, and a drain_requested event
    # Non-mutating commands (status, report, wait-drain, triage) do not emit.

  @new
  Scenario: an unknown command prints the usage and returns non-zero
    When the control command runs frobnicate
    Then it prints "unknown command frobnicate" and the usage line
