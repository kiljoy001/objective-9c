@unattended
Feature: Multi-node campaign launch and unattended completion
  run_3node_campaign.rc is the operator entry point for a long native 9front
  campaign. It builds the grid tools for the local objtype, inits the shared
  root, enqueues work (optionally via an external enqueue script), auth-probes
  each node, then launches one queue worker (o9mutq) per node and N task
  workers (o9mutw) per node over rcpu. New in this pass: it can also launch a
  recovery daemon (o9mutd) and optionally block until the grid drains, so a
  campaign can run start-to-finish unattended.

  Nodes default to: dev9p authomatic babyFileServer.rentonsoftworks.coin

  Usage:
    grid/run_3node_campaign.rc [-A] [-y] [-W] [-D] [-r root]
      [-n workers-per-node] [-j jobs-per-worker] [-E enqueue.rc] [node ...]
      -j 0 means persistent workers; drain them with o9mutctl drain-worker
      -A skips rcpu auth probes; -y skips interactive login confirmation
      -W wait for the grid to drain after launching (unattended)
      -D launch one o9mutd recovery daemon on the first node

  Background:
    Given a repo checkout reachable from every node at the same 9P path
    And the grid tools build cleanly for the local objtype

  # ---- build + init ----

  @existing
  Scenario: The campaign builds o9mutctl, o9mutq, and o9mutw from grid/*.o9
    When the campaign builds the grid tools
    Then o9mutctl, o9mutq, and o9mutw are linked against libo9.a and libndb.a
    And a 6c warning is treated as a build failure

  @existing
  Scenario: The campaign inits the shared root and copies the tools to root/bin
    When the campaign inits the root
    Then root/bin/o9mutctl, root/bin/o9mutq, root/bin/o9mutw all exist
    And the root directory layout is created

  @existing
  Scenario: The campaign copies the o9 stdlib alongside grid sources for the build
    When the campaign prepares the build src tree
    Then grid/*.o9 and stdlib/*.o9 (process.o9, time.o9) are both present in src
    And it falls back to /sys/lib/o9/stdlib then $home/lib/o9/stdlib if local stdlib is missing

  # ---- enqueue hook ----

  @existing
  Scenario: -E runs an external enqueue script against the root
    When the campaign is launched with -E enqueue.rc
    Then enqueue.rc is run with the root as $1 before any workers start
    And if enqueue.rc exits non-zero the campaign aborts with exit enqueue

  @existing
  Scenario: Omitting -E launches workers against whatever is already queued
    When the campaign is launched without -E
    Then no enqueue script is run
    And workers start against the existing pending work

  # ---- auth preflight ----

  @existing
  Scenario: The campaign confirms rcpu login is warmed before launching
    When the campaign is launched in interactive mode
    Then it prints a preflight message listing each node's rcpu probe command
    And it waits for the operator to type y before continuing

  @existing
  Scenario: -y skips the interactive confirmation
    When the campaign is launched with -y
    Then it does not prompt for confirmation

  @existing
  Scenario: -A skips the rcpu auth probe
    When the campaign is launched with -A
    Then no rcpu -h <node> -c 'echo o9mut-auth-ok' probes are run

  @existing
  Scenario: A failed auth probe aborts the campaign before launching workers
    Given a node whose rcpu probe returns non-zero
    When the campaign runs the auth check
    Then it prints "auth check failed for <node>" and exits auth
    And no workers are launched

  # ---- launch topology ----

  @existing
  Scenario: One queue worker is launched per node
    When the campaign launches with 3 nodes
    Then 3 rcpu o9mutq processes are started, one per node
    And each o9mutq uses a worker id of <node>-queue

  @existing
  Scenario: N task workers are launched per node
    When the campaign launches with -n 3 across 3 nodes
    Then 9 rcpu o9mutw processes are started
    And each uses a worker id of <node>-<i>

  @existing
  Scenario: Persistent workers (-j 0) run until drained
    When the campaign launches with -j 0
    Then each o9mutw is launched with -n 0 and stays alive after its first task
    And the operator is told to drain each worker with o9mutctl drain-worker

  @existing
  Scenario: The campaign prints monitor and drain instructions after launch
    When the campaign has launched all workers
    Then it prints status, report, and result-count monitor commands
    And it prints a drain-worker command for each launched worker

  @existing
  Scenario: Extra positional args override the default node list
    When the campaign is launched with nodes "alpha beta"
    Then workers are launched only against alpha and beta
    And the default node list is not used

  # ---- daemon launch (new) ----

  @new @unattended
  Scenario: -D launches one recovery daemon on the first node
    When the campaign is launched with -D
    Then one o9mutd is started via rcpu on the first node
    And the daemon runs with cycles=0 so it loops requeue-stale + report until killed
    And the daemon is logged under root/logs/

  @new @unattended
  Scenario: Omitting -D launches no daemon; stale recovery is manual
    When the campaign is launched without -D
    Then no o9mutd process is started
    And the campaign notes that requeue-stale must be run manually or via -D

  # ---- wait-for-drain (new) ----

  @new @unattended
  Scenario: -W blocks the campaign until the grid is fully drained
    When the campaign is launched with -W
    Then after launching workers it calls o9mutctl wait-drain on the root
    And it returns only when pending, claimed, chunks_pending, and chunks_claimed are all zero

  @new @unattended
  Scenario: -W -D together run a campaign start-to-finish unattended
    When the campaign is launched with -W -D -y -j 0 -E enqueue.rc
    Then it enqueues, launches a daemon and persistent workers, and blocks until drained
    And no operator interaction is required after launch

  @new @unattended
  Scenario: The campaign exits non-zero if wait-drain times out
    When the campaign is launched with -W and the grid never drains
    Then the campaign exits non-zero and reports the drain timeout

  # ---- node portability ----

  @new @hygiene
  Scenario: The campaign sets O9MUT_PLAN9_REPO so the gate does not depend on a hardcoded path
    When the campaign launches workers
    Then the gate env O9MUT_PLAN9_REPO is set to the node-visible repo path
    And o9um_gate.rc uses O9MUT_PLAN9_REPO instead of the hardcoded /mnt/term/mnt/term/home/scott path
