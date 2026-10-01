@smoke
Feature: Smoke, focused harnesses, and node cleanup
  Small rc harnesses exercise the grid end-to-end before you trust it with a
  real campaign. run_o9mutgrid.rc is the mkfile `o9mutgrid-test` target: a
  single-node smoke test that fixes the contract "an echo gate survives and an
  exit-fail gate is killed". run_o9mutjournal.rc and run_o9mutreplay.rc are
  focused mkfile targets for the journal and replay contracts. run_9worker_trial.rc
  is a multi-node trial that enqueues throwaway echo tasks and launches workers
  to drain them. cleanup_mutation_node.rc is the operator's local recovery tool
  for stale processes left by aborted mutation work.

  Background:
    Given the repo is built (o9c and libo9.a present)

  # ---- run_o9mutgrid.rc (the mkfile smoke test) ----

  @existing
  Scenario: The smoke test builds o9mutctl, o9mutw, and o9mutd from grid sources
    When run_o9mutgrid.rc builds the grid tools
    Then o9mutctl, o9mutw, and o9mutd are transpiled, compiled, and linked
    And a 6c warning is treated as a build failure

  @existing
  Scenario: The smoke test copies grid sources and the o9 stdlib into the build tree
    When run_o9mutgrid.rc prepares the src tree
    Then grid/*.o9 and the o9 stdlib (process.o9, time.o9) are present
    And it falls back to /sys/lib/o9/stdlib then $home/lib/o9/stdlib if the local stdlib is missing

  @existing
  Scenario: The smoke test aborts if o9c or libo9.a is missing
    Given o9c or libo9.a is absent
    When run_o9mutgrid.rc runs
    Then it prints "missing" and exits missing without building

  @existing
  Scenario: The smoke test uses /mnt/term/tmp when available, else /tmp, overridable by O9MUT_TMP
    When run_o9mutgrid.rc picks a tmp base
    Then it uses /mnt/term/tmp if that dir exists
    Else it uses /tmp
    And O9MUT_TMP overrides both

  @existing
  Scenario: The smoke test enqueues a pass task and a kill task then runs two workers
    When run_o9mutgrid.rc runs the smoke
    Then it inits a local root
    And it enqueues a "pass" task with gate "echo pass"
    And it enqueues a "kill" task with gate "exit fail"
    And it runs o9mutw with worker id "smoke" and -n 2

  @existing
  Scenario: The smoke test asserts the pass task survived and the kill task was killed
    When run_o9mutgrid.rc runs the smoke to completion
    Then status reports "survived\t1" and "killed\t1" and "done\t2"
    And it prints "o9mutgrid: OK"

  @existing @unattended
  Scenario: The smoke test asserts wait-drain succeeds after work is processed
    Given the pass and kill tasks have both completed
    When run_o9mutgrid.rc calls o9mutctl wait-drain 5
    Then wait-drain prints a line beginning with "drained"
    And the smoke test continues

  @existing @unattended
  Scenario: The smoke test asserts wait-drain times out while work remains pending
    Given run_o9mutgrid.rc enqueues task "stuck" after the worker has exited
    When it calls o9mutctl wait-drain 1 200
    Then wait-drain prints a line beginning with "timeout"
    And the smoke test fails if that timeout marker is missing

  @existing
  Scenario: The smoke test fails if any expected count is missing
    Given the kill task unexpectedly survives
    When run_o9mutgrid.rc runs the smoke
    Then it does not print "o9mutgrid: OK"
    And it exits non-zero

  @existing
  Scenario: The smoke test cleans up its tmp dir on exit
    When run_o9mutgrid.rc finishes (pass or fail)
    Then its tmp dir under the tmp base is removed

  # ---- run_9worker_trial.rc ----

  @existing
  Scenario: The trial builds o9mutctl and o9mutw only (no queue worker, no daemon)
    When run_9worker_trial.rc builds the grid tools
    Then o9mutctl and o9mutw are built
    And o9mutq and o9mutd are not built

  @existing
  Scenario: The trial enqueues N throwaway echo tasks directly to pending
    When run_9worker_trial.rc runs with -t 18
    Then 18 tasks are enqueued under "tasks/pending/" with gate "/bin/echo"
    And each has timeout_ms=5000 and priority=100
    # No queue/chunks tier is used; tasks go straight to pending.

  @existing
  Scenario: The trial auth-probes each node unless -A is given
    When run_9worker_trial.rc runs without -A
    Then it runs `rcpu -h <node> -c 'echo o9mut-auth-ok'` for each node
    And it aborts on a failed probe

  @existing
  Scenario: The trial launches N workers per node each running up to -j jobs
    When run_9worker_trial.rc runs with -n 3 -j 2 across 3 nodes
    Then 9 o9mutw processes are launched via rcpu
    And each uses worker id <node>-<i> and -n 2

  @new @smoke @unattended
  Scenario: The trial can queue tabula launch commands for resident node agents
    When run_9worker_trial.rc runs with -L agent -n 3 -j 2 across 3 nodes
    Then no rcpu worker launches are attempted
    And 9 command tabula files are written under "agents/<node>/pending/"
    And each command has op=start-worker, the worker id <node>-<i>, and -n 2
    And the trial prints the o9mutagent.rc command needed on each node

  @existing
  Scenario: The trial prints monitor instructions after launch
    When run_9worker_trial.rc has launched
    Then it prints status and result-count monitor commands

  @existing
  Scenario: The trial node list can be overridden by positional args
    When run_9worker_trial.rc is run with extra args "alpha beta"
    Then workers are launched only against alpha and beta

  # ---- run_o9mutjournal.rc (focused journal + crash recovery harness) ----

  @existing @journal
  Scenario: The journal harness builds only the tools it needs
    When run_o9mutjournal.rc builds the grid tools
    Then o9mutctl and o9mutw are transpiled, compiled, and linked
    And o9mutq, o9mutd, and o9mutreplay are not built
    And a 6c warning is treated as a build failure

  @existing @journal
  Scenario: The journal harness verifies a normal worker run emits the lifecycle
    When run_o9mutjournal.rc runs task "jpass" with worker id "jw"
    Then "journal.log" exists under the local root
    And the journal contains enqueue, worker_start, task_claim, gate_start, gate_exit, and task_done
    And the journal contains worker_stop

  @existing @crash @journal
  Scenario: The journal harness verifies stale requeue increments attempt
    Given run_o9mutjournal.rc fabricates task "crashtest" with attempt=2
    And a stale claim dir for that task
    When it runs o9mutctl requeue-stale 1
    Then the output contains "requeued_tasks\t1"
    And the pending task row now has attempt=3

  @existing @crash @journal
  Scenario: The journal harness verifies max-attempt retirement writes infra_fail
    Given task "crashtest" has attempt=3 and config.tab has max_attempts=3
    And the task is claimed by a stale worker again
    When run_o9mutjournal.rc runs o9mutctl requeue-stale 1
    Then the output contains "retired\t1"
    And "results/crashtest.tab" contains infra_fail
    And "tasks/pending/crashtest.tab" is removed

  @existing @journal
  Scenario: The journal harness cleans up and prints OK only after every assertion passes
    When run_o9mutjournal.rc finishes successfully
    Then it prints "o9mutjournal: OK"
    And its tmp dir under the tmp base is removed
    When any journal or crash-recovery assertion fails
    Then it exits fail after cleaning up its tmp dir

  # ---- run_o9mutreplay.rc (focused replay harness) ----

  @existing @replay
  Scenario: The replay harness builds the replay stack
    When run_o9mutreplay.rc builds the grid tools
    Then o9mutctl, o9mutw, and o9mutreplay are transpiled, compiled, and linked
    And a 6c warning is treated as a build failure

  @existing @replay
  Scenario: The replay harness creates a two-result campaign from a real journal
    When run_o9mutreplay.rc runs its setup campaign
    Then it enqueues task "jpass" with gate "echo pass"
    And it enqueues task "jkill" with gate "exit fail"
    And worker "jw" runs exactly 2 jobs

  @existing @replay
  Scenario: The replay harness verifies timeline and type filtering
    Given the setup campaign journal has worker and task lifecycle events
    When run_o9mutreplay.rc runs o9mutreplay without filters
    Then the output includes worker_start and task_done
    When it runs o9mutreplay --type gate_exit
    Then the output contains only gate_exit events and does not contain worker_start

  @existing @replay
  Scenario: The replay harness verifies task, worker, summary, and source views
    When run_o9mutreplay.rc queries task "jpass"
    Then the task view includes "final_result=survived"
    When it queries worker "jw"
    Then the worker view includes "survived=1" and "killed=1"
    When it runs --summary --by-source
    Then the output includes source "sample" and a score field

  @existing @replay
  Scenario: The replay harness verifies survivors and clean integrity
    When run_o9mutreplay.rc runs --survivors
    Then the output includes task "jpass" and "source=sample"
    When it runs --integrity against the clean setup campaign
    Then the output does not report in-flight-without-exit, lost, or orphan-gate-exit

  @existing @replay
  Scenario: The replay harness verifies exported slices can be replayed
    When run_o9mutreplay.rc exports a slice to slice.log
    Then slice.log exists and contains task_done
    When slice.log is copied to a fresh root as journal.log
    Then o9mutreplay can read that fresh root and print task_done

  # ---- cleanup_mutation_node.rc ----

  @existing @hygiene
  Scenario: Cleanup always slays stale web/session helpers and orphaned gate children
    When cleanup_mutation_node.rc runs with no flags
    Then it slays webfs, webcookies, and plumber
    And it slays o9_type_test, o9c, mk, and ramfs
    And it prints "cleanup: done"

  @existing @hygiene
  Scenario: Cleanup does not slay workers or factotum unless explicitly requested
    When cleanup_mutation_node.rc runs with no flags
    Then it does not slay o9mutq or o9mutw
    And it does not slay factotum

  @existing @hygiene
  Scenario: Cleanup can also slay mutation workers
    When cleanup_mutation_node.rc runs with -w
    Then it prints "cleanup: mutation workers"
    And it slays o9mutq and o9mutw

  @existing @hygiene
  Scenario: Cleanup can also slay factotum when re-authentication is acceptable
    When cleanup_mutation_node.rc runs with -f
    Then it prints "cleanup: factotum"
    And it slays factotum

  @existing @hygiene
  Scenario: Cleanup usage is shown for help or unknown arguments
    When cleanup_mutation_node.rc runs with -h
    Then it prints "usage: grid/cleanup_mutation_node.rc [-f] [-w]" and exits usage
    When cleanup_mutation_node.rc runs with an unknown flag
    Then it prints the same usage and exits usage
