@queue
Feature: Two-tier work queue over a shared 9P tree
  The grid uses a filesystem-only queue on a shared 9P fileserver so that any
  node can enqueue, any node can claim, and no central broker is needed.
  Work arrives as a manifest, is split into chunks, chunks are expanded into
  individual task files, and tasks are claimed and run one at a time by
  workers. Claiming is a filesystem `create`-as-lock: creating a directory that
  already exists fails, which is the atomic mutual-exclusion primitive.

  Layout under root:
    tasks/pending/*.tab         one task per file (the unit of execution)
    tasks/claimed/<id>/         claim dir = lock; holds claim.tab
    tasks/done/*.tab             completion ledger
    queue/chunks/pending/*.tab   manifest batches, N task rows each
    queue/chunks/claimed/<id>/   chunk claim dir = lock
    queue/chunks/done/*.tab      chunk completion ledger
    config.tab                   schema, stale_sec, max_attempts, heartbeat_sec

  A task .tab row has the columns:
    task_id  source  mutant_path  gate  timeout_ms  priority  attempt  created_at

  Background:
    Given a grid root initialised at a shared 9P path
    And the config.tab reads stale_sec=300 max_attempts=3 heartbeat_sec=30

  # ---- enqueue (single task) ----

  @existing
  Scenario: Enqueue a single task with an explicit id
    When the control command enqueues task "ctl_arity.001" with source "o9c/grammar.d/50-app-facade.y" and mutant "mutants/m01.c" and gate "grid/o9um_gate.rc" and timeout 300000 and priority 100
    Then a task file "tasks/pending/ctl_arity.001.tab" exists
    And the task row has attempt=0
    And the control command prints "enqueued ctl_arity.001"

  @existing
  Scenario: Enqueue generates an id when none is given
    When the control command enqueues with an empty task id
    Then a task file matching "tasks/pending/task.*.tab" exists
    And the generated id contains no tab, newline, or slash characters

  @existing
  Scenario: Enqueue sanitises forbidden characters in fields
    When the control command enqueues task "a/b c\td" with a source containing a tab and newline
    Then the task id in the filename has slashes, tabs, and newlines replaced with underscore or space
    And no field in the task row contains a tab or newline inside its value

  @existing
  Scenario: Enqueue rejects a missing root or source
    When the control command enqueues with a missing source
    Then the control command prints "enqueue failed"
    And no task file is created

  # ---- manifest / chunking ----

  @existing
  Scenario: A manifest is split into chunks of O9MUT_CHUNK_LINES rows
    Given a manifest file with 600 rows and a header line
    And the env var O9MUT_CHUNK_LINES=256
    When the control command enqueues the manifest
    Then 3 chunk files exist under "queue/chunks/pending/"
    And the file "queue/counts.tab" records manifest_enqueued=600 manifest_chunks=3 chunk_size=256
    And each chunk row has the 6 columns task_id source mutant_path gate timeout_ms priority

  @existing
  Scenario: Manifest uses a default chunk size when O9MUT_CHUNK_LINES is unset
    Given a manifest file with 10 rows and no O9MUT_CHUNK_LINES env var
    When the control command enqueues the manifest
    Then 1 chunk file exists under "queue/chunks/pending/"
    And the chunk_size recorded in queue/counts.tab is 256

  @existing
  Scenario: Manifest skips rows missing task_id or gate
    Given a manifest file with 5 rows where 2 rows have an empty task_id and 1 row has an empty gate
    When the control command enqueues the manifest
    Then 2 chunk rows are written
    And queue/counts.tab records manifest_skipped=3

  # ---- chunk claim + expansion (queue worker / o9mutq) ----

  @existing
  Scenario: A queue worker claims one chunk and expands it into pending tasks
    Given 1 chunk "chunk.000000.tab" under "queue/chunks/pending/" with 4 rows
    When a queue worker runs once with worker id "dev9p-queue"
    Then "queue/chunks/claimed/chunk.000000" does not exist as a stale lock
    And "queue/chunks/done/chunk.000000.tab" exists
    And 4 task files exist under "tasks/pending/"
    And the queue worker output reports chunks=1 tasks=4

  @existing
  Scenario: A queue worker writes its own heartbeat to workers/<w>.queue.tab
    When a queue worker runs with worker id "dev9p-queue"
    Then "workers/dev9p-queue.queue.tab" exists
    And its row has columns worker_id pid last_seen status chunks tasks
    And status is "idle" before a chunk is claimed and "running" while expanding
    # Distinct from the task worker's workers/<w>.tab heartbeat file.

  @existing
  Scenario: Two queue workers on different nodes never expand the same chunk
    Given 1 chunk under "queue/chunks/pending/" with 4 rows
    When two queue workers race to claim the same chunk
    Then exactly one queue worker reports chunks=1
    And the other reports chunks=0
    And exactly 4 task files exist under "tasks/pending/"

  @existing
  Scenario: Expansion deduplicates an already-pending task id
    Given chunk "chunk.000001.tab" containing task id "dup.001"
    And a task file "tasks/pending/dup.001.tab" already exists
    When a queue worker runs once
    Then the queue worker output reports skipped=1 tasks=0
    And the existing "tasks/pending/dup.001.tab" is unchanged

  @existing
  Scenario: Expansion respects max-pending backpressure by waiting
    Given a chunk with 4 rows
    And 512 task files already under "tasks/pending/"
    When a queue worker runs with max-pending=512 and idle-ms=10
    Then the queue worker waits rather than writing a 513th task
    And after a pending task is removed the queue worker proceeds

  @new @crash
  Scenario: A claimed chunk keeps its content until completion, not lost at claim
    Given 1 chunk "chunk.000002.tab" under "queue/chunks/pending/" with 4 rows
    When a queue worker claims the chunk but dies before writing done
    Then the chunk file "queue/chunks/pending/chunk.000002.tab" still exists
    And the chunk content is recoverable from pending
    # This is the regression guard for the chunk-loss-on-crash fix:
    # remove(pending) must happen only after create(done), not at claim time.

  @new @crash
  Scenario: A second queue worker re-claims a chunk left claimed by a dead node
    Given chunk "chunk.000003.tab" under "queue/chunks/pending/" with 4 rows
    And a stale claim dir "queue/chunks/claimed/chunk.000003/" older than stale_sec
    When requeue-stale runs
    Then the stale claim dir is removed
    And a queue worker can subsequently claim and expand "chunk.000003.tab"
