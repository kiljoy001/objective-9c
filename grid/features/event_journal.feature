@journal
Feature: Quake-3-style event journal for deterministic playback
  Inspired by Quake 3's demo recorder: every state-changing transition in the
  grid appends exactly one structured event to a single ordered journal. The
  journal is the system of record for "what actually happened". A separate
  replay tool walks the journal to reconstruct task and worker lifecycles and
  pinpoint where and when a bug occurred — the play-back that lets you figure
  out failures after the fact.

  Properties borrowed from the Quake 3 demo model:
    - append-only: events are never edited or deleted; the log only grows
    - one event per transition: no silent state mutation (if it changed the
      grid, it is in the journal)
    - timestamped + originated: every event carries a millisecond wall clock
      and the worker/node that caused it, so concurrent writers can be ordered
    - reconstructable: feeding the journal back through the replay tool rebuilds
      the grid state machine; you can step to any point and inspect

  Journal location: <root>/journal.log
  One event per line, tab-separated:
    seq  ts_ms  origin  type  entity_kind  entity_id  detail...

  - seq      : monotonic per origin (no global counter exists across nodes)
  - ts_ms    : wall-clock milliseconds from nsec() at emit time
  - origin   : worker id (e.g. "dev9p-2") or "ctl" / "daemon" / a node name
  - type     : one of the enumerated event types below
  - entity_kind : task | chunk | worker | manifest | root
  - entity_id   : the task id, chunk name, worker id, etc.
  - detail   : zero or more type-specific fields (e.g. result, attempt, reason)

  Enumerated event types:
    enqueue            manifest_chunked
    chunk_claim        chunk_done         chunk_requeue
    task_claim         gate_start         gate_exit        task_done        task_requeue        task_retire
    worker_start       worker_heartbeat   worker_drain     worker_stop
    daemon_cycle       drain_requested

  Background:
    Given a grid root initialised at a shared 9P path
    And the journal file "journal.log" is empty

  # ---- emission: one event per transition ----

  @new
  Scenario: Enqueuing a task emits an enqueue event
    When the control command enqueues task "ctl_arity.001"
    Then the journal contains one event with type=enqueue entity_kind=task entity_id=ctl_arity.001
    And the event detail includes source, mutant_path, gate, timeout_ms, and attempt=0

  @new
  Scenario: Chunking a manifest emits one manifest_chunked event
    When the control command enqueues a manifest that produces 3 chunks
    Then the journal contains one event with type=manifest_chunked
    And the event detail includes manifest_enqueued, manifest_skipped, and manifest_chunks

  @new
  Scenario: A queue worker emits chunk_claim and chunk_done around expansion
    When a queue worker claims and finishes chunk "chunk.000020"
    Then the journal contains a chunk_claim event for entity_id=chunk.000020
    And a chunk_done event for entity_id=chunk.000020
    And both events carry the queue worker's id as origin

  @new
  Scenario: A task worker emits task_claim, gate_start, gate_exit, task_done
    When a worker claims, runs, and finishes task "t1" with result killed
    Then the journal has four events for "t1" in order: task_claim, gate_start, gate_exit, task_done
    And the gate_exit event detail includes result=killed and exit_code
    And the task_done event detail includes finished_at

  @new
  Scenario: A timeout emits gate_exit with result=timeout and a kill note marker
    When a worker's gate is killed by the watchdog after timeout_ms
    Then the journal gate_exit event for that task has result=timeout
    And the event detail records timeout_ms

  @new
  Scenario: requeue-stale emits chunk_requeue and task_requeue events
    Given 1 stale chunk claim and 1 stale task claim
    When requeue-stale runs
    Then the journal contains a chunk_requeue event and a task_requeue event
    And the task_requeue event detail includes the new attempt value

  @new
  Scenario: Retiring a task past max_attempts emits a task_retire event
    Given a stale task "t13" with attempt=3 and max_attempts=3
    When requeue-stale runs
    Then the journal contains a task_retire event for "t13"
    And the detail includes reason=max_attempts_exceeded

  @new
  Scenario: A worker emits worker_start and worker_stop around its loop
    When a worker with max-jobs=1 starts and finishes one task
    Then the journal's first event from that origin is worker_start
    And the journal's last event from that origin is worker_stop

  @new
  Scenario: A persistent worker emits periodic worker_heartbeat events
    Given a persistent worker with max-jobs=0 and heartbeat_sec=30
    When the worker idles across two heartbeat intervals
    Then the journal contains worker_heartbeat events at roughly heartbeat_sec cadence
    And each heartbeat detail includes status=idle or running and the current task if any

  @new
  Scenario: Requesting a drain emits drain_requested
    When the control command drains worker "dev9p-2"
    Then the journal contains a drain_requested event with entity_kind=worker entity_id=dev9p-2

  # ---- concurrent append integrity ----

  @new
  Scenario: Concurrent workers append without corrupting each other's lines
    Given 3 workers each emitting 100 events
    When they all append to the same journal simultaneously
    Then every line in the journal is well-formed (has at least the 6 base columns)
    And no event is lost, duplicated, or interleaved with another event's bytes
    # Achieved by opening journal.log with OAPPEND and emitting one line per write.

  @new
  Scenario: Each origin has its own monotonically increasing seq
    Given 2 workers "alpha" and "beta" each emitting events
    When the journal is read
    Then within origin "alpha" the seq values strictly increase from 1
    And within origin "beta" the seq values strictly increase from 1
    And seq is not globally unique across origins

  @new
  Scenario: Events are globally orderable by ts_ms then origin then seq
    Given events emitted concurrently by several origins
    When the journal is sorted by ts_ms, then origin, then seq
    Then every event's ts_ms is non-decreasing in that order
    And the ordering is a valid total order across the grid

  # ---- completeness / no silent mutation ----

  @new
  Scenario: No state transition is silent — every result file has a matching event
    Given a finished campaign with 10 results under "results/"
    When the journal is read
    Then every result task id has a matching gate_exit and task_done event
    And there are no gate_exit events without a preceding task_claim

  @new
  Scenario: The journal is append-only across the whole campaign
    Given a campaign that ran to completion
    When the journal file size is observed over time
    Then it only grows; no line is ever rewritten or truncated
    And the byte offset of earlier events never changes
