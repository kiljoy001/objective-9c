@replay
Feature: Replay — reconstruct the campaign from the event journal
  The replay tool reads <root>/journal.log and rebuilds the grid's state
  machine, the way Quake 3 plays a demo back from its recorded events. It is
  the debugging instrument: when a multi-node campaign misbehaved, you point
  replay at the journal and walk the timeline to find which node, worker, and
  task hit what, and when. Replay never touches the live grid; it is read-only.

  Replay answers four kinds of question:
    1. timeline   — what happened, in order, optionally filtered
    2. lifecycle  — the full history of one task or one worker
    3. integrity  — gaps and orphans that reveal lost work or a stuck claim
    4. summary    — aggregate counts and per-source mutation score over time

  Background:
    Given a grid root whose journal.log records a completed campaign
    And the journal is well-formed (6 base columns per line)

  # ---- timeline ----

  @new
  Scenario: Replay prints the full ordered timeline
    When replay reads the journal with no filters
    Then it prints every event in ts_ms, origin, seq order
    And each line shows ts_ms, origin, type, entity_kind, entity_id, and detail

  @new
  Scenario: Replay filters the timeline by event type
    When replay is run with --type gate_exit
    Then it prints only gate_exit events
    And each printed line is a gate_exit

  @new
  Scenario: Replay filters the timeline by origin (worker/node)
    When replay is run with --origin dev9p-2
    Then it prints only events whose origin is dev9p-2
    And the events appear in that origin's seq order

  @new
  Scenario: Replay filters the timeline to a time window
    When replay is run with --after T1 --before T2
    Then it prints only events with T1 <= ts_ms <= T2

  # ---- lifecycle ----

  @new
  Scenario: Replay reconstructs the full lifecycle of one task
    When replay is run with --task t1
    Then it prints the ordered events for task "t1": task_claim, gate_start, gate_exit, task_done
    And it states the final result, the worker that ran it, the elapsed seconds, and the attempt count

  @new
  Scenario: Replay reconstructs the activity of one worker
    When replay is run with --worker dev9p-2
    Then it prints worker_start, the sequence of tasks claimed and run, and worker_stop
    And it states how many tasks the worker killed, let survive, timed out, and errored

  @new
  Scenario: Replay shows the chunk expansion lineage for a task
    When replay is run with --task t1 --show-lineage
    Then it identifies the chunk that expanded into task "t1"
    And it shows the chunk_claim -> chunk_done events for that chunk

  # ---- integrity / bug detection ----

  @new
  Scenario: Replay flags a task that was claimed but never finished
    Given a journal where task "t30" has task_claim and gate_start but no gate_exit
    When replay is run with --integrity
    Then it reports "t30" as in-flight-without-exit
    And it names the worker origin that claimed it and the last event timestamp

  @new
  Scenario: Replay flags a chunk that was claimed but never done
    Given a journal where chunk "chunk.000040" has chunk_claim but no chunk_done
    When replay is run with --integrity
    Then it reports "chunk.000040" as claimed-without-done
    And it notes whether the chunk was later requeued (chunk_requeue) or lost

  @new
  Scenario: Replay detects a lost chunk — claimed, never done, never requeued
    Given a journal where chunk "chunk.000041" has chunk_claim and no chunk_done and no chunk_requeue
    When replay is run with --integrity
    Then it reports "chunk.000041" as lost
    And it lists the task ids that should have come from that chunk but are absent from the journal

  @new
  Scenario: Replay detects orphan gate_exit without task_claim
    Given a journal with a gate_exit event for "t99" and no preceding task_claim
    When replay is run with --integrity
    Then it reports "t99" as orphan-gate-exit

  @new
  Scenario: Replay reports workers that stopped without a drain request
    Given a journal where worker "alpha" has worker_stop but no drain_requested event
    When replay is run with --integrity
    Then it reports "alpha" as stopped-without-drain
    And it notes the last task the worker was running, if any

  @new
  Scenario: Replay reports a worker heartbeat gap suggesting a dead worker
    Given a journal where worker "beta" sent worker_heartbeat every 30s then stopped for 10 minutes
    When replay is run with --integrity
    Then it reports "beta" as heartbeat-gap and shows the last heartbeat timestamp
    And it cross-checks whether a task_claim for "beta" went unfinished

  # ---- summary / score over time ----

  @new
  Scenario: Replay summarises aggregate counts by result class
    When replay is run with --summary
    Then it prints counts of killed, survived, timeout, equivalent, infra_fail, setup_error
    And the counts match the result files under "results/"

  @new
  Scenario: Replay computes per-source mutation score
    When replay is run with --summary --by-source
    Then for each source it prints killed, survived, timeout, and the score killed/(killed+survived)
    And sources with zero finished tasks are listed separately

  @new
  Scenario: Replay points at the surviving mutants that need regression tests
    When replay is run with --survivors
    Then it lists every task whose gate_exit result=survived
    And each entry shows source, mutant_path, worker, and the first time it survived

  # ---- format / non-destructive ----

  @new
  Scenario: Replay never writes to the live grid
    When replay is run against a live root
    Then it opens root files read-only
    And it creates no files under root other than its own report output if requested

  @new
  Scenario: Replay can export a filtered journal slice for sharing
    When replay is run with --export-slice --after T1 --before T2 --output slice.log
    Then a file "slice.log" is written containing the events in that window
    And slice.log is itself a valid journal that replay can read back
