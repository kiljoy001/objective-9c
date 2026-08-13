@smoke
Feature: Smoke and trial harnesses — quick self-checks of the grid
  Two rc scripts exercise the grid end-to-end on a small scale before you trust
  it with a real campaign. run_o9mutgrid.rc is the mkfile `o9mutgrid-test`
  target: a single-node smoke test that fixes the contract "an echo gate
  survives and an exit-fail gate is killed". run_9worker_trial.rc is a
  multi-node trial that enqueues throwaway echo tasks and launches workers to
  drain them.

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

  @existing
  Scenario: The trial prints monitor instructions after launch
    When run_9worker_trial.rc has launched
    Then it prints status and result-count monitor commands

  @existing
  Scenario: The trial node list can be overridden by positional args
    When run_9worker_trial.rc is run with extra args "alpha beta"
    Then workers are launched only against alpha and beta
