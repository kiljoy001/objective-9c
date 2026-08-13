@crash
Feature: Crash recovery — a node dying must not lose work or loop forever
  A multi-node grid must tolerate a worker or queue worker process dying while
  holding a claim. Recovery is driven by the daemon (o9mutd) calling
  requeue-stale, which finds claim dirs older than stale_sec and releases them.
  Two invariants govern this feature:

  Invariant 1 (no work lost): a unit of work (chunk or task) is only removed
  from pending after its done marker is written. A crash at any point leaves
  the unit recoverable from pending.

  Invariant 2 (bounded retries): each requeue increments the task's attempt
  counter. When attempt exceeds max_attempts from config.tab, the task is
  retired as infra_fail instead of being retried again, so a perpetually
  crashing task cannot loop forever across nodes.

  Background:
    Given a grid root initialised at a shared 9P path
    And config.tab with stale_sec=300 max_attempts=3 heartbeat_sec=30

  # ---- chunk recovery ----

  @new
  Scenario: A chunk is not removed from pending until it is done
    Given chunk "chunk.000010.tab" under "queue/chunks/pending/" with 4 rows
    When a queue worker claims the chunk
    Then "queue/chunks/pending/chunk.000010.tab" still exists
    # The content must survive the claim so a crash is recoverable.

  @new
  Scenario: A queue worker that completes a chunk removes pending and writes done
    Given chunk "chunk.000011.tab" under "queue/chunks/pending/" with 4 rows
    When a queue worker claims and finishes the chunk
    Then "queue/chunks/pending/chunk.000011.tab" no longer exists
    And "queue/chunks/done/chunk.000011.tab" exists
    And the chunk claim dir is removed

  @new
  Scenario: requeue-stale releases a stale chunk claim so it can be re-expanded
    Given chunk "chunk.000012.tab" under "queue/chunks/pending/" with 4 rows
    And a stale claim dir "queue/chunks/claimed/chunk.000012/" older than stale_sec
    When requeue-stale runs
    Then the stale claim dir is removed
    And the chunk remains in "queue/chunks/pending/" ready for a new queue worker
    And the requeue-stale output counts the released chunk

  @new
  Scenario: A non-stale chunk claim is left untouched by requeue-stale
    Given chunk "chunk.000013.tab" under "queue/chunks/pending/"
    And a fresh claim dir "queue/chunks/claimed/chunk.000013/" younger than stale_sec
    When requeue-stale runs
    Then the fresh claim dir is preserved
    And the chunk is not double-expanded

  # ---- task recovery ----

  @existing
  Scenario: A task pending file survives a worker crash mid-gate
    Given task "t10" under "tasks/pending/t10.tab" claimed by a worker that then dies
    When the worker dies without writing a result
    Then "tasks/pending/t10.tab" still exists
    And "tasks/claimed/t10/" still exists as a stale lock

  @existing
  Scenario: requeue-stale releases a stale task claim; the task becomes re-claimable
    Given task "t11" under "tasks/pending/t11.tab"
    And a stale claim dir "tasks/claimed/t11/" older than stale_sec
    When requeue-stale runs
    Then "tasks/claimed/t11/" is removed
    And "tasks/pending/t11.tab" remains so another worker can claim it

  @existing
  Scenario: requeue-stale preserves a non-stale task claim
    Given task "t11b" under "tasks/pending/t11b.tab"
    And a fresh claim dir "tasks/claimed/t11b/" younger than stale_sec
    When requeue-stale runs
    Then "tasks/claimed/t11b/" is preserved
    And "tasks/pending/t11b.tab" is untouched
    # The current code skips claims whose mtime is within stale_sec; this is the
    # existing behaviour the new chunk sweep must mirror.

  @new
  Scenario: requeue-stale increments attempt when a task is re-released
    Given task "t12" under "tasks/pending/t12.tab" with attempt=0
    And a stale claim dir "tasks/claimed/t12/" older than stale_sec
    When requeue-stale runs
    Then "tasks/pending/t12.tab" now has attempt=1
    And the requeue-stale output counts the released task

  @new
  Scenario: A task past max_attempts is retired as infra_fail, not re-queued
    Given task "t13" under "tasks/pending/t13.tab" with attempt=3
    And a stale claim dir "tasks/claimed/t13/" older than stale_sec
    And config.tab max_attempts=3
    When requeue-stale runs
    Then "tasks/pending/t13.tab" no longer exists
    And a result file "results/t13.tab" exists with result=infra_fail reason=max_attempts_exceeded
    And "tasks/done/t13.tab" exists
    And the task is never claimed again

  @new
  Scenario: requeue-stale reports how many chunks and tasks it released
    Given 2 stale chunk claims and 3 stale task claims
    When requeue-stale runs
    Then the output reports requeued_chunks=2 and requeued_tasks=3
    And tasks retired as infra_fail are counted separately

  # ---- daemon ----

  @existing
  Scenario: The daemon loops requeue-stale then report at the configured interval
    Given a daemon configured with interval-ms=100 stale-sec=300 cycles=3
    When the daemon runs
    Then it calls requeue-stale and report 3 times
    And it sleeps interval-ms between cycles but not after the last

  @existing
  Scenario: A daemon with cycles=0 runs forever until killed
    Given a daemon with cycles=0
    When the daemon is started
    Then it loops requeue-stale + report indefinitely
    And it stops when killed

  @new @unattended
  Scenario: The daemon requeues both chunks and tasks each cycle
    Given 1 stale chunk claim and 1 stale task claim
    When the daemon runs one cycle
    Then both the chunk claim and the task claim are released
