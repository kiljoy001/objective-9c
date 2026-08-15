@agent @unattended
Feature: Resident node agents consume tabula launch commands
  The grid should not depend on per-worker rcpu logins for multi-node CPU.
  rcpu is allowed as a bootstrap tool, but the runtime launch path is a shared
  9P root plus one resident agent per node. The controller writes inert tabula
  command files; each node-local agent claims only its own commands and starts
  local grid processes.

  Command directory layout:
    <root>/agents/<node>/pending/*.tab
    <root>/agents/<node>/claimed/<command-id>/command.tab
    <root>/agents/<node>/done/<command-id>.tab
    <root>/agents/<node>/failed/<command-id>.tab

  Command schema:
    op root bindir repo worker jobs idle_ms max_pending interval_ms stale_sec cycles log
    Optional decentralized columns:
      shard_id manifest local_root collect_root

  Supported ops:
    ping
    start-worker
    start-queue
    start-daemon
    prepare-shard
    collect-shard

  Background:
    Given a shared grid root mounted at the same path on every node
    And root/bin contains o9mutw, o9mutq, o9mutd when those commands are needed
    And one o9mutagent.rc process is already running on each target node

  # ---- agent bootstrap boundary ----

  @new
  Scenario: rcpu is only required to bootstrap the resident agent
    Given no o9mutagent.rc process is running on node "Authomatic.rentonsoftworks.coin"
    When an operator uses rcpu to start o9mutagent.rc on that node
    Then subsequent worker, queue worker, and daemon launches do not require rcpu
    And the node stays eligible for new work as long as the agent remains running

  @new
  Scenario: An agent declares its node identity explicitly
    When o9mutagent.rc starts with -n "Authomatic.rentonsoftworks.coin"
    Then it watches only "agents/Authomatic.rentonsoftworks.coin/pending/"
    And it never claims commands written for another node

  @new
  Scenario: An agent falls back to the local Plan 9 sysname
    Given o9mutagent.rc starts without -n
    And "/dev/sysname" contains "dev9p"
    Then it watches "agents/dev9p/pending/"

  # ---- command files are inert tabula data ----

  @new
  Scenario: The controller queues a worker launch as a tabula command
    When the controller wants worker "Authomatic.rentonsoftworks.coin-1" to run 2 jobs
    Then it writes one command file under "agents/Authomatic.rentonsoftworks.coin/pending/"
    And the command has op=start-worker
    And the command carries root, bindir, repo, worker, jobs, idle_ms, and log
    And the command contains no shell fragment supplied by the campaign input

  @new
  Scenario: The controller queues a queue-worker launch as a tabula command
    When the controller wants a queue worker on node "dev9p.rentonsoftworks.coin"
    Then it writes one command file under "agents/dev9p.rentonsoftworks.coin/pending/"
    And the command has op=start-queue
    And the command carries worker=<node>-queue, idle_ms, max_pending, root, bindir, and log

  @new
  Scenario: The controller queues a recovery daemon launch as a tabula command
    When the campaign is launched with -L agent -D
    Then it writes one command file under the first node's pending directory
    And the command has op=start-daemon
    And the command carries cycles=0, interval_ms=30000, stale_sec=300, root, bindir, repo, and log

  @new @decentralized
  Scenario: The controller queues shard preparation as a tabula command
    When the controller wants node "dev9p.rentonsoftworks.coin" to own shard "shard-1"
    Then it writes one command file under "agents/dev9p.rentonsoftworks.coin/pending/"
    And the command has op=prepare-shard
    And the command carries bindir, repo, manifest, local_root, shard_id, and collect_root
    And the command contains no shell fragment supplied by the campaign input

  @new @decentralized
  Scenario: The controller queues shard collection as a tabula command
    Given node "dev9p.rentonsoftworks.coin" has drained its node-local shard root
    When the controller wants to collect the shard
    Then it writes one command file under "agents/dev9p.rentonsoftworks.coin/pending/"
    And the command has op=collect-shard
    And the command carries local_root and collect_root

  @new
  Scenario: Ping verifies that an agent is consuming commands
    When the controller writes a command with op=ping
    Then the node agent claims the command
    And it writes a done status with status=ok
    And no worker, queue worker, or daemon is started

  # ---- claim and execution semantics ----

  @new
  Scenario: A command is claimed atomically before execution
    Given a command file "agents/dev9p.rentonsoftworks.coin/pending/c1.tab"
    When the node agent sees the command
    Then it creates "agents/dev9p.rentonsoftworks.coin/claimed/c1/"
    And it copies the command to "claimed/c1/command.tab"
    And it removes the pending command only after the claim directory exists

  @new
  Scenario: A start-worker command launches o9mutw locally on the node
    Given a claimed command with op=start-worker
    When the node agent executes the command
    Then it starts "root/bin/o9mutw" on the local node
    And it passes -r, -w, -n, and -idle-ms from the command row
    And it exports O9MUT_PLAN9_REPO from the repo column when repo is present
    And stdout and stderr go to the command's log path
    And a done status records the accepted launch and child pid

  @new
  Scenario: A start-queue command launches o9mutq locally on the node
    Given a claimed command with op=start-queue
    When the node agent executes the command
    Then it starts "root/bin/o9mutq" on the local node
    And it passes -r, -w, -idle-ms, and -max-pending from the command row
    And a done status records the accepted launch and child pid

  @new
  Scenario: A start-daemon command launches o9mutd locally on the node
    Given a claimed command with op=start-daemon
    When the node agent executes the command
    Then it starts "root/bin/o9mutd" on the local node
    And it passes -r, -cycles, -interval-ms, and -stale-sec from the command row
    And it exports O9MUT_PLAN9_REPO from the repo column when repo is present
    And a done status records the accepted launch and child pid

  @new @decentralized
  Scenario: A prepare-shard command stages a node-local root
    Given a claimed command with op=prepare-shard
    When the node agent executes the command
    Then it creates the local_root tree
    And it copies grid binaries, repo-src, and the shard manifest into local_root
    And it runs o9mutctl init and o9mutctl manifest against local_root
    And a done status records the shard as ready

  @new @decentralized
  Scenario: A collect-shard command publishes local results to the controller
    Given a claimed command with op=collect-shard
    When the node agent executes the command
    Then it copies local results under "collect_root/results/<node>/"
    And it copies the local journal under "collect_root/journals/<node>.log"
    And it writes a compact status tabula under "collect_root/progress/<node>.tab"
    And a done status records the shard as collected

  @new
  Scenario: An unsupported op is rejected without executing anything
    Given a command file with op="run-shell"
    When the node agent claims the command
    Then it writes a failed status for that command
    And it does not invoke a shell using command file data
    And it does not start any grid process

  @new
  Scenario: Malformed commands are failed instead of blocking the agent
    Given a pending command file with no data row
    When the node agent claims the command
    Then it writes a failed status for that command
    And it continues polling for later commands

  # ---- campaign integration ----

  @new
  Scenario: Agent launch mode never runs per-worker rcpu commands
    When run_3node_campaign.rc is launched with -L agent
    Then no "rcpu -h <node>" command is run for auth, queue workers, task workers, or daemon launch
    And command tabula files are written for each requested node-local process

  @new
  Scenario: Agent commands can use a node-visible path prefix
    Given agents are bootstrapped through rcpu and see the controller namespace under "/mnt/term"
    When run_3node_campaign.rc is launched with -L agent -M /mnt/term
    Then each command row stores root, bindir, repo, and log paths prefixed with "/mnt/term"
    And the command file itself is still written under the controller-visible root

  @new
  Scenario: Agent launch mode remains compatible with wait-drain
    Given a campaign launched with -L agent -W
    And every resident agent accepts its launch commands
    When the workers drain the pending and claimed work
    Then run_3node_campaign.rc exits only after o9mutctl wait-drain reports drained

  @new
  Scenario: Agent command status is operator-visible
    When run_3node_campaign.rc queues agent commands
    Then it prints the agent startup command for each node
    And it prints where to inspect "agents/*/done" and "agents/*/failed"
