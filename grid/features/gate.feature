@gate
Feature: Gate — apply a mutant to a private ramfs worktree and run the mk gate
  The gate (grid/o9um_gate.rc) is the per-task verification script the worker
  forks. It does NOT touch the real checkout: it builds a private ramfs
  worktree, copies the maintained source tree into it, overwrites the single
  target source with the mutant, runs `mk clean` then a source-routed set of
  mk targets, and exits zero on pass / non-zero on fail. The worker reads
  that exit status and classifies killed/survived/timeout (see worker.feature).

  Env contract from the worker:
    O9MUT_SOURCE   the repo-relative source file the mutant targets
    O9MUT_MUTANT   the mutant file to copy over the source
    O9MUT_LOG      the log path (gate's stdout/stderr are already redirected
                   by the worker via dup; the gate itself probes its own tmp)
    O9MUT_SCRATCH  the worker's scratch dir (gate uses its own ramfs instead)
    O9MUT_ROOT     the grid root
    O9MUT_ATTEMPT  the task attempt count
    O9MUT_PLAN9_REPO  optional node-visible repo path (overrides the default)
    O9MUT_TMP      optional tmp base override

  Background:
    Given a node with the repo mounted at a plan9-visible path
    And the gate env vars O9MUT_SOURCE and O9MUT_MUTANT are set

  # ---- setup guards ----

  @existing
  Scenario: The gate dies with setup status when O9MUT_SOURCE is missing
    Given O9MUT_SOURCE is unset
    When the gate runs
    Then it prints "o9um-grid-gate: missing O9MUT_SOURCE" to stderr
    And it exits with the setup status

  @existing
  Scenario: The gate dies with setup status when O9MUT_MUTANT is missing
    Given O9MUT_MUTANT is unset
    When the gate runs
    Then it prints "o9um-grid-gate: missing O9MUT_MUTANT" to stderr
    And it exits with the setup status

  @existing
  Scenario: The gate dies when the repo mkfile is missing
    Given the repo path has no mkfile
    When the gate runs
    Then it prints "missing repo <path>" to stderr and exits setup

  @existing
  Scenario: The gate dies when the mutant file is missing
    Given O9MUT_MUTANT points at a non-existent file
    When the gate runs
    Then it prints "missing mutant <path>" to stderr and exits setup

  # ---- repo resolution + tmp probing ----

  @existing
  Scenario: The gate uses O9MUT_PLAN9_REPO when set, else a hardcoded default
    Given O9MUT_PLAN9_REPO is set to /mnt/term/mnt/term/home/scott/Repo/objective-9c
    When the gate runs
    Then it uses that path as the repo root
    And it does not depend on the hardcoded fallback

  @existing
  Scenario: The gate falls back to the hardcoded repo path when O9MUT_PLAN9_REPO is unset
    Given O9MUT_PLAN9_REPO is unset
    When the gate runs
    Then it uses /mnt/term/mnt/term/home/scott/Repo/objective-9c as the repo root

  @existing
  Scenario: The gate probes /mnt/term/tmp, then /usr/$user/tmp, then /tmp for its scratch base
    When the gate probes a tmp base
    Then it tries /mnt/term/tmp first
    And falls back to /usr/$user/tmp if /mnt/term/tmp is unavailable
    And falls back to /tmp if neither is available

  @existing
  Scenario: O9MUT_TMP overrides the probed tmp base
    Given O9MUT_TMP=/some/scratch
    When the gate runs
    Then its scratch base is /some/scratch

  # ---- worktree construction ----

  @existing
  Scenario: The gate builds the worktree in a private ramfs
    When the gate runs
    Then it mounts a ramfs at its scratch
    And the worktree lives under that ramfs, not the real checkout

  @existing
  Scenario: The gate copies the o9c tree minus test/ and grammar.d, then grammar.d and test/ fully
    When the gate copies o9c
    Then o9c non-test, non-grammar.d files are copied as files
    And o9c/grammar.d is copied in full
    And o9c/test is copied in full except the artifacts dir
    And an empty o9c/test/artifacts with its .gitignore is created

  @existing
  Scenario: The gate copies the maintained runtime/lib files
    When the gate copies the repo
    Then libtab/ and stdlib/ are copied as dirs
    And mkfile, o9.h, o9_runtime.c, o9_crypto.c, o9_tab_discard.c, o9_dispatch.s, monocypher.c, monocypher.h are copied as files

  @existing
  Scenario: The gate applies the mutant by overwriting the source in the worktree
    Given O9MUT_SOURCE=o9c/o9_type.c and O9MUT_MUTANT=mutants/m01.c
    When the gate applies the mutant
    Then the worktree's o9c/o9_type.c is replaced by mutants/m01.c

  @existing
  Scenario: The gate binds the worktree's tmp over /tmp before building
    When the gate runs
    Then it bind -c's $work/tmp onto /tmp
    So mk's temp output goes into the worktree, not the node's real /tmp

  # ---- build + routing ----

  @existing
  Scenario: The gate runs mk clean before the verification targets
    When the gate runs
    Then `mk clean` is run first and its output is discarded

  @existing
  Scenario: Runtime/libtab sources route to crypto-test + tab-test
    Given O9MUT_SOURCE is one of libtab/foo.c o9_runtime.c o9_crypto.c o9_tab_discard.c
    When the gate runs
    Then it runs `mk crypto-test` and `mk tab-test`
    And it does not run ast-test or run-test

  @existing
  Scenario: All other sources route to ast-test + run-test + function-object-contract-test
    Given O9MUT_SOURCE=o9c/o9_type.c
    When the gate runs
    Then it runs `mk ast-test`, `mk run-test`, and `mk function-object-contract-test`
    And it does not run crypto-test or tab-test

  @existing
  Scenario: Any routed target failing makes the gate exit non-zero
    Given O9MUT_SOURCE=o9c/o9_type.c and `mk run-test` fails
    When the gate runs
    Then the gate exits non-zero (fail)

  @existing
  Scenario: All routed targets passing makes the gate exit zero
    Given O9MUT_SOURCE=o9c/o9_type.c and all routed mk targets pass
    When the gate runs
    Then the gate exits zero

  # ---- teardown ----

  @existing
  Scenario: The gate unmounts its ramfs before exiting
    When the gate finishes
    Then it unmounts the ramfs it mounted
    And no stray mount is left on the node

  # ---- portability (new) ----

  @new @hygiene
  Scenario: The campaign supplies O9MUT_PLAN9_REPO so the hardcoded default is only a fallback
    Given the campaign sets O9MUT_PLAN9_REPO to the node-visible repo path for each worker
    When the gate runs on a node
    Then it uses the campaign-supplied path and never relies on the hardcoded /mnt/term/mnt/term/home/scott path
    # The gate ALREADY honors O9MUT_PLAN9_REPO (@existing above); what is new is the
    # campaign actually setting it, removing the hardcoded-user-path dependency.
