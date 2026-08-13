@hygiene @journal
Feature: Status, observability, and worker liveness
  An operator monitoring a long multi-node campaign needs to tell, at a
  glance, how far the campaign has come, what the mutation score is so far,
  and — the hardest — whether a worker is actually alive or silently dead.
  This feature upgrades the status view with per-source progress and a live
  mutation score, and adds a heartbeat side-process so a long gate run does
  not make a worker look dead.

  Background:
    Given a grid root mid-campaign with workers on 3 nodes
    And some finished results under "results/"

  # ---- per-source progress ----

  @new
  Scenario: status groups results by source
    Given results for sources "o9c/o9_type.c" and "o9c/grammar.d/70-typecheck.y"
    When the control command runs status --by-source
    Then the output has one section per source
    And each section lists killed, survived, timeout, equivalent, infra_fail counts for that source

  @new
  Scenario: status reports per-source pending and claimed counts
    Given pending and claimed tasks whose rows name two distinct sources
    When the control command runs status --by-source
    Then each source section reports its own pending and claimed counts
    # Requires reading the source column from pending/claimed task rows.

  @new
  Scenario: status reports a per-source mutation score
    Given source "o9c/o9_type.c" with 8 killed and 2 survived finished results
    When the control command runs status --by-source
    Then the section for "o9c/o9_type.c" reports score=0.80 (killed/(killed+survived))
    And sources with zero finished results report score=n/a

  @new
  Scenario: status reports overall campaign progress as done/total
    Given a manifest that enqueued 100 tasks total
    When the control command runs status
    Then the output reports progress done/total where total is manifest_enqueued from queue/counts.tab
    And done is the count of result files

  # ---- worker liveness via heartbeat ----

  @new
  Scenario: A worker heartbeats while a long gate is running
    Given a worker running a gate that takes 120s
    And heartbeat_sec=30
    When the worker is mid-gate
    Then "workers/dev9p-2.tab" last_seen is updated at most 30s ago
    And the worker status reads "running" with the current task id
    # A side-process updates last_seen during the blocking wait() for the gate.

  @new
  Scenario: status flags a worker whose heartbeat is stale relative to heartbeat_sec
    Given a worker whose last_seen is 5 minutes old and heartbeat_sec=30
    When the control command runs status
    Then the worker is flagged stale/dead
    And the output shows the last_seen age in seconds

  @new
  Scenario: status distinguishes idle, running, drained, and dead workers
    Given an idle worker, a running worker, a drained worker, and a worker whose heartbeat is stale
    When the control command runs status --workers
    Then it lists each worker with one of: idle, running, drained, dead
    And the dead worker is the one whose heartbeat is stale beyond heartbeat_sec

  @new
  Scenario: A worker that exited cleanly is shown as stopped, not dead
    Given a worker with max-jobs=1 that finished and exited, leaving a final worker_stop journal event
    When the control command runs status --workers
    Then that worker is shown as stopped with its final task counts
    # Distinguished from dead by the presence of a worker_stop event in the journal.

  # ---- robust parsing (hygiene) ----

  @new @hygiene
  Scenario: status counts pending by .tab suffix not name length
    Given pending dir entries "a.tab", "longname.tab", ".tmp", ".."
    When the control command runs status
    Then pending counts only "a.tab" and "longname.tab" (2)
    # Replaces strlen(name) > 4 which miscounts short names and dot-entries.

  @new @hygiene
  Scenario: result class is parsed by column name, not by fixed tab offset
    Given result rows with variable-length log_path and reason fields
    When the control command runs status
    Then every result is classified correctly regardless of field width
    # Replaces the hand-rolled walk-four-tabs parser (the current code skips
    # task_id, worker_id, source, mutant_path, then reads the result column).

  # ---- observability from the journal ----

  @new @journal
  Scenario: status --from-journal derives counts from events instead of scanning files
    Given a complete journal.log
    When the control command runs status --from-journal
    Then counts match the gate_exit events grouped by result
    And this agrees with a file-scan status of the same root

  @new @journal
  Scenario: status --workers --from-journal derives worker states from events
    Given a journal with worker_start, worker_heartbeat, and worker_stop events
    When the control command runs status --workers --from-journal
    Then each worker's state is derived from its last event
    And a worker whose last event is worker_stop is shown as stopped
