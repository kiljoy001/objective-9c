@decentralized @throughput @agent
Feature: Decentralized mutation campaigns run node-owned shards
  The high-throughput grid should not put the controller's shared 9P tree on
  the hot path for every task claim, gate run, and result write. A
  decentralized campaign treats each node as the owner of a complete shard:
  local repo snapshot, local queue, local workers, local journal, and local
  results. The controller plans shards and merges published tabula summaries.

  This is the Objective-9 distributed application shape in miniature:
  installed code runs locally; data moves as inert tabula files; receivers
  decide what imported data means with their own local code.

  Usage:
    grid/run_decentralized_campaign.rc [-r controller-root] [-m manifest.tsv]
      [-n workers-per-node] [-j jobs-per-worker] [-Q queue-max-pending] [-B node-local-base] [node ...]
      The script builds grid tools, snapshots repo-src, writes controller/shards,
      queues prepare-shard commands, waits for agents to prepare local roots,
      then queues start-queue and start-worker commands against each local root.

    grid/steal_decentralized_shard.rc -r controller-root -f donor-node -t thief-node -s shard-id
      The script queues a thief-side steal-shard command, then starts queue and
      task workers on a thief-local root containing only unfinished donor rows.

  Controller layout:
    controller/manifest.tsv
    controller/nodes.tab
    controller/shards/<node>.manifest.tsv
    controller/progress/<node>.tab
    controller/results/<node>/*.tab
    controller/journals/<node>.log
    controller/merge/report.tab

  Node-local shard layout:
    repo-src/
    shard/manifest.tsv
    queue/chunks/pending/*.tab
    tasks/pending/*.tab
    tasks/claimed/<id>/
    tasks/done/*.tab
    results/*.tab
    journal.log
    workers/*.tab

  Shard plan schema:
    shard_id node task_count manifest_path local_root status created_at

  Progress schema:
    node shard_id pending claimed done killed survived timeout infra_fail setup_error last_seen

  Merge report schema:
    task_id node shard_id result source mutant_path status reason

  Background:
    Given one resident o9mutagent.rc process is already running on each target node
    And each node can create a node-local shard root
    And the controller has a complete Universal Mutator manifest

  # ---- shard planning ----

  @new
  Scenario: The controller splits a manifest into deterministic node shards
    Given a manifest with 153367 task rows
    And the target nodes are "dev9p.rentonsoftworks.coin Authomatic.rentonsoftworks.coin babyFileServer.rentonsoftworks.coin"
    When the controller plans a decentralized campaign
    Then it writes one shard manifest per node under "controller/shards/"
    And every task id from the input manifest appears in exactly one shard manifest
    And repeating the plan with the same manifest and node list produces the same task ownership

  @new
  Scenario: The decentralized campaign launcher writes the shard plan
    When the operator launches "grid/run_decentralized_campaign.rc"
    Then the launcher writes "controller/manifest.tsv"
    And it writes "controller/shards/<node>.manifest.tsv" for every target node
    And it writes "controller/nodes.tab" with each node's shard id, task count, manifest path, local root, and status

  @new
  Scenario: The shard plan is explicit campaign data
    When the controller writes the shard plan
    Then "controller/nodes.tab" records each node, shard id, local root, and status
    And the controller never infers active ownership only from pending task files
    And an operator can inspect the planned work without starting any worker

  @new
  Scenario: Changing the node list creates a new shard plan
    Given a previous campaign was planned for 3 nodes
    When the controller replans for 4 nodes
    Then it writes a new campaign plan with a distinct campaign id
    And it does not silently move work inside the existing plan

  # ---- shard preparation ----

  @new
  Scenario: An agent prepares a complete node-local shard bundle
    When the controller queues op=prepare-shard for node "dev9p.rentonsoftworks.coin"
    Then the node agent creates the configured local shard root
    And it installs root/bin, repo-src, and the node's shard manifest there
    And the prepared shard can run without reading controller task directories

  @new
  Scenario: Prepared shard input is copied as data, not mounted as the hot path
    Given the controller root is visible through a 9P mount
    When a node prepares its shard
    Then repo-src and shard/manifest.tsv are copied into the node-local root
    And task workers use the node-local root for queue, task, log, journal, and result IO
    And the controller root is used only for command, progress, and collection files

  @new
  Scenario: prepare-shard is idempotent for an already prepared node
    Given a node-local shard root already has repo-src and shard/manifest.tsv
    When the controller queues op=prepare-shard for the same shard id
    Then the agent verifies the existing shard id and manifest
    And it does not delete completed results
    And it reports status=ready

  # ---- local execution ----

  @new
  Scenario: A node expands only its own shard manifest
    Given node "Authomatic.rentonsoftworks.coin" owns shard "s2"
    When its local queue worker starts
    Then it enqueues chunks from "shard/manifest.tsv" in the node-local root
    And it does not read "controller/shards/dev9p.rentonsoftworks.coin.manifest.tsv"
    And it never expands tasks owned by another node's shard

  @new
  Scenario: Workers claim tasks only from the node-local root
    Given node "babyFileServer.rentonsoftworks.coin" has a prepared shard
    When its local task workers run
    Then every claim directory is created under the node-local "tasks/claimed/"
    And every result file is written under the node-local "results/"
    And no worker claims from the controller's shared "tasks/pending/"

  @new
  Scenario: Gate execution reads the node-local repo snapshot
    When a local worker runs a mutant gate
    Then O9MUT_PLAN9_REPO points at the node-local "repo-src"
    And the gate does not copy source through the controller drawterm mount for that mutant
    And the worker writes logs under the node-local shard root

  @new
  Scenario: Node-local processing tolerates a slow controller mount
    Given the controller 9P mount is slow but still reachable
    When a prepared shard is already running locally
    Then task claim, gate execution, result write, and journal append continue locally
    And only progress publication or final collection waits on the controller mount

  # ---- progress publication ----

  @new
  Scenario: Nodes publish compact progress tabulae to the controller
    When a node-local shard is running
    Then the node periodically writes "controller/progress/<node>.tab"
    And the progress row includes pending, claimed, done, result counts, and last_seen
    And progress publication never copies per-task pending or claimed state

  @new
  Scenario: Controller status reads progress from every shard
    Given all nodes have published progress tabulae
    When the operator asks for decentralized campaign status
    Then the controller reports per-node utilization and total campaign progress
    And it identifies nodes that are stale by comparing last_seen with the current time

  # ---- result collection and merge ----

  @new
  Scenario: Final collection imports node-local results and journals
    Given a node reports its shard as drained
    When the controller queues op=collect-shard
    Then the node publishes its result files under "controller/results/<node>/"
    And it publishes its journal under "controller/journals/<node>.log"
    And it marks the shard status collected only after the copy completes

  @new
  Scenario: Merge validates complete manifest coverage
    Given every node has been collected
    When the controller merges the decentralized campaign
    Then every task id from "controller/manifest.tsv" appears in the merged report exactly once
    And missing task ids are reported as merge errors
    And the merged report records the owning node and shard id for each task

  @new
  Scenario: Merge deduplicates identical result rows
    Given two collected result files contain the same task id with identical result data
    When the controller merges results
    Then the merged report keeps one row for that task id
    And it records the duplicate as a benign duplicate

  @new
  Scenario: Merge rejects conflicting result rows
    Given two collected result files contain the same task id with different result data
    When the controller merges results
    Then the merged report records a conflict for that task id
    And the campaign exits non-zero instead of hiding the disagreement

  # ---- failure and recovery ----

  @new
  Scenario: A failed node reassigns its shard as a whole
    Given node "Authomatic.rentonsoftworks.coin" has stopped publishing progress
    When the operator reassigns its shard to "dev9p.rentonsoftworks.coin"
    Then the controller writes a new shard assignment for that shard id
    And the replacement node receives the failed node's shard manifest
    And already collected results for that shard are not rerun

  @new
  Scenario: An idle fast node can steal unfinished work from a slower shard
    Given node "dev9p.rentonsoftworks.coin" has drained its own shard
    And node "Authomatic.rentonsoftworks.coin" still has unfinished shard rows
    When the operator runs "grid/steal_decentralized_shard.rc" from Authomatic to dev9p
    Then the controller queues op=steal-shard for dev9p
    And dev9p prepares a thief-local root from Authomatic's shard manifest
    And the thief-local manifest excludes task ids already present in Authomatic's results
    And dev9p starts local queue and task workers against the thief-local root

  @new
  Scenario: Work stealing keeps completed donor rows stable
    Given a donor shard has already written result file "t1.tab"
    When another node steals from that donor shard
    Then the stolen manifest does not contain task id "t1"
    And merge can later deduplicate any race where donor and thief both finish the same task
    And no pending or claimed donor files are moved over the controller root

  @new
  Scenario: A restarted node resumes from local state
    Given a node stopped during a shard run
    And its node-local root still contains results and journal.log
    When the node agent starts that shard again
    Then completed task ids are skipped
    And pending or stale claimed work is recovered from the node-local root
    And the node resumes publishing progress for the same shard id

  @new
  Scenario: Draining a decentralized campaign drains every node shard
    When the campaign is launched with decentralized wait-drain
    Then the controller waits until each shard reports pending=0 and claimed=0
    And it collects every shard
    And it merges results before reporting the campaign complete

  # ---- language shape ----

  @new @language
  Scenario: Decentralized grid matches the normal Objective-9 application shape
    Given each node runs installed Objective-9 grid code locally
    And each node publishes progress and results as tabula data
    When the controller reads those publications through near or far tabula locality
    Then the controller receives inert data only
    And no remote object handle or remote method dispatch is created
    And the controller combines received tabulae using its own local merge code

  @new @language
  Scenario: Imports are proposals, not commands
    Given the controller deposits a shard command tabula for a node
    When the resident node agent reads the imported tabula
    Then the agent validates the op against its local allowlist
    And unsupported ops are rejected without invoking a shell
    And command arrival alone does not execute anything
