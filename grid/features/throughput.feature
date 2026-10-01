@throughput @agent @unattended
Feature: High-throughput mutation campaigns keep every node busy
  Speed comes from utilization, not from making one mutant gate faster. A
  high-throughput campaign keeps node agents resident, workers persistent,
  queue expansion continuous, stale work recoverable, and the operator out of
  the loop after launch.

  Recommended native command:
    grid/run_3node_campaign.rc -L agent -M /mnt/term -D -W -y -j 0 -n 3 -E enqueue.rc

  Tuned native command:
    grid/run_3node_campaign.rc -L agent -M /mnt/term -S -Q 512 -D -W -y -j 0 -n 8 -E enqueue.rc

  Background:
    Given one o9mutagent.rc process is already resident on each target node
    And each agent can see the controller namespace with the path prefix "/mnt/term"
    And the enqueue script writes manifest chunks instead of per-task inline launches

  # ---- warm launch path ----

  @new
  Scenario: The throughput campaign avoids per-worker rcpu startup
    When the operator launches the recommended native command
    Then rcpu is not used for task worker, queue worker, or daemon startup
    And the controller writes tabula commands for the resident agents
    And every command row uses "/mnt/term" before root, bindir, repo, and log paths

  @new
  Scenario: Agents stay resident across campaign launches
    Given a previous campaign has drained
    And the same o9mutagent.rc process is still running on each node
    When a second campaign writes new agent command tabulae
    Then the agents consume the new commands without another rcpu login
    And the only per-campaign remote work is local process startup by the resident agent

  @new
  Scenario: Agent command acceptance is separate from work completion
    When the controller queues start-worker commands for 9 workers
    Then "agents/*/done" eventually contains 9 accepted command statuses
    And worker completion is tracked separately under "workers/" and "results/"
    And a failed command status fails launch diagnostics even if the task queue still has work

  @new
  Scenario: wait-drain starts only after agent launches are accepted
    When the campaign is launched with -L agent -W
    Then it waits for every queued agent command to reach done or failed status
    And it exits agent-failed if any command writes a failed status
    And it exits agent-timeout if any command remains unaccepted
    And it calls o9mutctl wait-drain only after every launch command is accepted

  # ---- persistent workers ----

  @new
  Scenario: Persistent workers keep polling after their first task
    When workers are launched with -j 0
    Then each o9mutw command row has jobs=0
    And each worker remains alive after completing a task unless it receives a drain request
    And status --workers reports each live worker as idle or running instead of dead

  @new
  Scenario: Persistent workers are drained automatically after wait-drain
    Given a persistent-worker campaign has reached wait-drain
    When the campaign was launched with -W -j 0
    Then o9mutctl drain-worker is issued for each worker id
    And each worker exits only after finishing its current task or observing the drain marker
    And the campaign waits until each worker status is stopped
    And the journal records drain_requested and worker_stop events

  # ---- queue expansion ----

  @new
  Scenario: One queue worker per node keeps pending tasks replenished
    When the campaign launches across 3 nodes
    Then 3 start-queue commands are accepted, one per node
    And each queue worker expands manifest chunks into "tasks/pending/"
    And max-pending prevents unbounded pending-task growth

  @new
  Scenario: Chunked enqueue amortizes controller overhead
    Given Universal Mutator produces many mutant rows
    When the enqueue script writes manifest chunks
    Then o9mutq expands chunks into tasks near the workers
    And the controller does not run o9mutctl enqueue once per mutant during the hot path

  @new
  Scenario: Queue refill keeps the hot pending directory small
    When the campaign is launched with -Q 512
    Then each queue worker runs with max-pending=512
    And workers scan a bounded hot set instead of thousands of pending files
    And queue chunks remain in "queue/chunks/pending" until the hot set needs refill

  @new
  Scenario: Workers clean stale pending rows while scanning
    Given "tasks/pending/" contains a task whose result file already exists
    When a persistent worker scans for work
    Then it removes the stale pending task
    And it continues looking for claimable work without re-running the completed task

  @new
  Scenario: Campaign snapshots the source tree into the grid root
    When the campaign is launched with -S
    Then it copies the gate-visible repo subset into "root/repo-src"
    And worker launch commands set O9MUT_PLAN9_REPO to that snapshot
    And mutation gates do not copy source files through the controller's drawterm mount for every mutant

  # ---- daemon recovery ----

  @new
  Scenario: The daemon keeps stale claims from reducing utilization
    When the campaign is launched with -D
    Then one start-daemon command is accepted on the first node
    And o9mutd runs with cycles=0
    And stale chunk and task claims are requeued while the campaign continues

  @new
  Scenario: Bounded retries prevent bad infrastructure work from monopolizing workers
    Given a task repeatedly becomes stale
    When requeue-stale observes the task past max_attempts
    Then the task is retired as infra_fail
    And persistent workers continue claiming other pending tasks

  # ---- unattended completion ----

  @new
  Scenario: wait-drain measures true grid completion
    When the campaign is launched with -W
    Then the campaign does not exit while tasks/pending, tasks/claimed, queue/chunks/pending, or queue/chunks/claimed are non-empty
    And it exits only after o9mutctl wait-drain reports drained

  @new
  Scenario: The recommended command needs no operator input after launch
    When the operator launches with -L agent -M /mnt/term -D -W -y -j 0 -n 3 -E enqueue.rc
    Then no interactive rcpu preflight is shown
    And workers, queue workers, and daemon are started through agent commands
    And the campaign blocks until drained or exits non-zero on timeout/failure

  # ---- observability for throughput ----

  @new
  Scenario: Status shows whether speed is limited by launch, queueing, or gates
    When a throughput campaign is running
    Then status --by-source --workers --from-journal reports pending, claimed, done, and result counts
    And it reports worker liveness and current task when available
    And an operator can distinguish idle workers from an empty queue or a stuck gate

  @new
  Scenario: Replay can reconstruct utilization after the campaign
    Given the campaign journal contains agent-started worker lifecycle events
    When o9mutreplay summarizes the journal
    Then it shows task_claim, gate_start, gate_exit, task_done, worker_heartbeat, and worker_stop events
    And the summary identifies nodes or workers that accepted commands but did little work
