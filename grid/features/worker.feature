@worker
Feature: Task worker runs one gate per claimed task and classifies the result
  A task worker (o9mutw) loops: claim a pending task, fork the gate command,
  race it against a timeout watchdog, classify the outcome, write a result
  file, and move the task to done. Workers are stateless beyond their worker
  id; all coordination is through the shared 9P tree.

  Result classification:
    killed       gate exited non-zero (the mutant was detected)
    survived     gate exited zero (the mutant passed — a missing test)
    timeout      the watchdog killed the gate after timeout_ms
    setup_error  the task row was missing a gate or scratch could not be made
    infra_fail   reserved for infrastructure failure (see crash_recovery)
    equivalent   reserved for ledger/lexical equivalence (see triage_bridge)

  Result file columns:
    task_id  worker_id  source  mutant_path  result  exit_code  seconds
    log_path  reason  finished_at

  Background:
    Given a grid root initialised at a shared 9P path
    And a worker id "dev9p-2"
    And a task "t1" under "tasks/pending/t1.tab" with gate "grid/o9um_gate.rc" and timeout 5000

  # ---- claim ----

  @existing
  Scenario: A worker claims a pending task by creating a lock dir
    When the worker claims task "t1"
    Then "tasks/claimed/t1/" exists as a directory
    And "tasks/claimed/t1/claim.tab" records worker_id=dev9p-2 and a claimed_at timestamp

  @existing
  Scenario: A worker skips a task that already has a result
    Given a result file "results/t1.tab" already exists
    When the worker scans pending
    Then the worker does not create "tasks/claimed/t1/"
    And the worker does not re-run the gate for "t1"

  @new @throughput
  Scenario: A worker removes stale pending files whose result already exists
    Given a pending task "t1"
    And a result file "results/t1.tab" already exists
    When the worker scans pending
    Then "tasks/pending/t1.tab" is removed
    And no claim directory is created for "t1"
    And later worker scans do not repeatedly rediscover the stale file

  @new @throughput
  Scenario: A worker streams pending directory reads instead of reading the whole hot set
    Given thousands of pending task files
    When the worker looks for a task to claim
    Then it reads directory entries in batches until one claim succeeds
    And it does not require a full dirreadall of "tasks/pending/"
    And adding workers does not multiply whole-directory scans across the grid

  @existing
  Scenario: Two workers racing for one task: only one wins the lock
    Given one pending task "t1"
    When two workers race to claim "t1"
    Then exactly one "tasks/claimed/t1/" directory is created
    And only the winning worker runs the gate

  # ---- gate execution + classification ----

  @existing
  Scenario: A gate that exits zero is classified survived
    When the worker runs a gate that exits 0
    Then the result file "results/t1.tab" has result=survived exit_code=0
    And the task is moved to "tasks/done/t1.tab"
    And "tasks/pending/t1.tab" no longer exists
    And "tasks/claimed/t1/" no longer exists

  @existing
  Scenario: A gate that exits non-zero is classified killed
    When the worker runs a gate that exits 1
    Then the result file "results/t1.tab" has result=killed exit_code=1
    And the task is moved to "tasks/done/t1.tab"

  @existing
  Scenario: A gate that exceeds timeout_ms is classified timeout and killed
    When the worker runs a gate that sleeps longer than timeout_ms
    Then the watchdog sends a kill note to the gate's process group
    And the result file "results/t1.tab" has result=timeout
    And the elapsed seconds are recorded

  @existing
  Scenario: The watchdog child is reaped if the gate finishes first
    When the worker runs a gate that exits before timeout_ms
    Then the watchdog child is killed and reaped
    And no orphaned watchdog process remains

  @existing
  Scenario: A task with an empty gate is classified setup_error
    Given task "t2" with an empty gate field
    When the worker claims "t2"
    Then the result file "results/t2.tab" has result=setup_error reason=missing gate
    And the task is moved to done without forking a gate

  @existing
  Scenario: A task with a non-positive timeout defaults to 300000 ms
    Given task "t3" with timeout_ms=0
    When the worker runs the gate for "t3"
    Then the watchdog uses 300000 ms as the effective timeout
    # strtoll <= 0 falls back to 300000.

  @existing
  Scenario: Result rows carry a human-readable reason string
    When the worker runs a gate that exits 0
    Then the result row reason is "gate passed"
    When the worker runs a gate that exits non-zero
    Then the result row reason is "gate failed"
    When the worker runs a gate that times out
    Then the result row reason is "timeout_ms=<n>"

  @existing
  Scenario: The gate runs in a per-task scratch directory with env vars set
    When the worker runs the gate for "t1"
    Then the gate child has O9MUT_ROOT, O9MUT_TASK_ID, O9MUT_SOURCE, O9MUT_MUTANT, O9MUT_LOG, O9MUT_SCRATCH, and O9MUT_ATTEMPT in its environment
    And the gate's stdout and stderr are written to "logs/t1.dev9p-2.log"

  # ---- loop / lifecycle ----

  @existing
  Scenario: A worker with max-jobs=N stops after N tasks
    Given 5 pending tasks
    When the worker runs with max-jobs=2
    Then the worker completes exactly 2 tasks
    And the worker exits

  @existing
  Scenario: A worker with max-jobs=0 stays alive and idles when pending is empty
    Given 0 pending tasks
    When the worker runs with max-jobs=0 and idle-ms=10
    Then the worker writes a heartbeat to "workers/dev9p-2.tab" with status=idle
    And the worker sleeps idle-ms and re-scans rather than exiting

  @existing
  Scenario: A worker exits when a drain request is present
    Given a drain file "workers/dev9p-2.drain"
    When the worker finishes its current task
    Then the worker exits without claiming another task

  # ---- hygiene (new) ----

  @new @hygiene
  Scenario: The worker does not leak getenv("sysname") across heartbeats
    When the worker writes many heartbeats in a persistent loop
    Then each heartbeat calls getenv("sysname") at most once and frees the result
    # Regression guard for the per-iteration getenv leak in long-running workers.

  @new @hygiene
  Scenario: The worker removes its per-task scratch dir after the result is written
    When the worker runs and writes the result for "t1"
    Then the per-task scratch directory created for "t1" is removed
    And persistent workers do not accumulate scratch dirs across jobs

  @new @journal
  Scenario: The worker emits a journal event for each lifecycle transition
    When the worker claims, starts, and finishes task "t1"
    Then the journal contains a task_claim event, a gate_start event, and a gate_exit event for "t1"
    And each event carries the worker id, a millisecond timestamp, and the task id
