# grid/features — mutation grid behaviour specification (Gherkin)

Spec-first: the full behaviour of the multi-CPU-node mutation tester is
defined here in Gherkin **before** implementation. These features are the
contract for the improvement pass. Implementation must make every scenario
pass without violating any `@existing` scenario (regression guard).

The features describe the **target** system: current behaviour that must be
preserved is tagged `@existing`; behaviour added by this pass is tagged
`@new`. Bundle tags mark which improvement bundle a scenario belongs to.

## Feature files

| File | Scope | Bundles |
|------|-------|---------|
| `queue.feature` | two-tier queue: enqueue, manifest chunking, chunk claim, task expansion, backpressure, dedup | @queue, @crash |
| `worker.feature` | task worker: claim, gate exec, timeout watchdog, result classification, scratch lifecycle | @worker, @hygiene, @journal |
| `crash_recovery.feature` | no-work-lost and bounded-retry invariants; daemon loop | @crash, @unattended |
| `event_journal.feature` | Quake-3-style append-only event log; one event per transition | @journal |
| `replay.feature` | reconstruct timeline/lifecycle/integrity/summary from the journal | @replay |
| `control.feature` | o9mutctl subcommands incl. new wait-drain and triage | @control, @hygiene, @unattended, @triage, @journal |
| `campaign.feature` | multi-node rcpu or tabula-agent launch, auth preflight, daemon launch, wait-for-drain | @unattended, @hygiene |
| `agent_launch.feature` | resident node agents consuming inert tabula launch commands instead of per-worker rcpu | @agent, @unattended |
| `throughput.feature` | recommended high-throughput campaign shape: agents, persistent workers, queues, daemon, wait-drain | @throughput, @agent, @unattended |
| `triage_bridge.feature` | grid results → o9um triage schema → recheck round-trip | @triage |
| `status_observability.feature` | per-source progress, mutation score, worker liveness, robust parsing | @hygiene, @journal |
| `gate.feature` | the gate: ramfs worktree, repo copy list, mk-target routing by source, teardown | @gate, @hygiene |
| `host_bridge.feature` | Python bridges: o9grid_prepare.py (layout+enqueue) and o9grid_um_manifest.py (manifest+enqueue-rc gen) | @host_bridge |
| `smoke.feature` | run_o9mutgrid.rc, run_o9mutjournal.rc, run_o9mutreplay.rc, run_9worker_trial.rc, cleanup_mutation_node.rc | @smoke, @journal, @replay, @hygiene |

## Tag legend

Lifecycle:
- `@existing` — behaviour already implemented; must be preserved (regression).
- `@new` — behaviour added by this improvement pass.

Bundle (maps to the four requested bundles + the event/replay system):
- `@crash` — crash recovery: no work lost, bounded retries, chunk+task requeue.
- `@journal` — Quake-3-style event journal: one event per state transition.
- `@replay` — playback tool: reconstruct the campaign from the journal to find bugs.
- `@unattended` — start-to-finish unattended campaigns: daemon + wait-drain.
- `@triage` — grid → o9um triage bridge, recheck round-trip.
- `@hygiene` — worker leaks, scratch cleanup, robust parsing, portability.
- `@agent` — resident node launcher that consumes tabula command files.
- `@throughput` — utilization-oriented campaign behavior for large mutation runs.

Component:
- `@queue` `@worker` `@control` `@gate` `@host_bridge` `@smoke` `@agent` `@throughput` — which part
  of the runtime or harness suite the scenario exercises.

## Domain glossary

- **root** — the shared 9P tree (`$root`) holding the queue, results, workers,
  logs, journal, and config. Default `O9MUT_ROOT` or
  `/n/babyFileServer.rentonsoftworks.coin/o9mut`.
- **chunk** — a file under `queue/chunks/pending/*.tab` holding N task rows
  (a manifest batch). The unit of enqueue-to-expansion fan-out.
- **task** — a `.tab` file under `tasks/pending/` with columns
  `task_id source mutant_path gate timeout_ms priority attempt created_at`.
  The unit of execution.
- **claim** — a directory created under `.../claimed/<id>/` as a filesystem
  lock. `create(dir, OREAD, DMDIR)` fails if the dir exists → atomic mutex.
- **result** — `results/<taskid>.tab` with columns
  `task_id worker_id source mutant_path result exit_code seconds log_path reason finished_at`.
  `result ∈ {killed, survived, timeout, equivalent, infra_fail, setup_error}`.
- **worker (o9mutw)** — claims a task, `rfork`s the gate, races a watchdog,
  writes the result. One task at a time.
- **queue worker (o9mutq)** — claims a chunk, expands it into pending tasks
  respecting `max-pending` backpressure. One chunk at a time.
- **daemon (o9mutd)** — loops `requeue-stale` + `report` at an interval.
- **agent (o9mutagent.rc)** — optional resident per-node launcher. It polls
  `agents/<node>/pending/*.tab` for inert launch commands, claims each command
  by directory lock, and starts local `o9mutq`, `o9mutw`, or `o9mutd` without
  a per-worker `rcpu` login.
- **agent command** — a tabula row with columns
  `op root bindir repo worker jobs idle_ms max_pending interval_ms stale_sec cycles log`.
  The row is data only; supported ops are explicitly enumerated by the agent.
- **gate (o9um_gate.rc)** — the per-task verification script the worker forks.
  Builds a private ramfs worktree, copies the maintained tree, overwrites the
  target source with the mutant, runs `mk clean` then a source-routed set of
  mk targets (`crypto-test`+`tab-test` for libtab/runtime sources;
  `ast-test`+`run-test`+`function-object-contract-test` for everything else),
  and exits zero on pass / non-zero on fail. Honors `O9MUT_PLAN9_REPO`.
- **host bridges** — `o9grid_prepare.py` and `o9grid_um_manifest.py`: Python
  tools that prepare work for the grid from the host, writing the same 9P
  file layout the o9 tools produce. Universal Mutator generates mutants on
  the host; the bridges translate host paths to worker-visible plan9 paths.
- **journal** — `<root>/journal.log`, append-only, one event per line:
  `seq ts_ms origin type entity_kind entity_id detail...`
- **replay** — read-only tool that walks the journal to rebuild lifecycles
  and pinpoint failures. The "play back work and figure out bugs" instrument.
- **attempt / max_attempts** — a task's retry budget. `requeue-stale`
  increments attempt; when it exceeds `max_attempts` (from `config.tab`,
  default 3) the task is retired as `infra_fail`.
- **stale** — a claim dir whose mtime is older than `stale_sec` (default 300).
- **throughput campaign** — the recommended large-run topology:
  `run_3node_campaign.rc -L agent -M /mnt/term -D -W -y -j 0 -n 3 -E enqueue.rc`.
  It uses resident agents, persistent workers, queue workers, daemon recovery,
  and wait-drain to keep nodes busy without per-worker rcpu.

## The two crash-recovery invariants

1. **No work lost** — a unit (chunk or task) is removed from `pending` only
   after its `done` marker is written. A crash at any point leaves the unit
   recoverable from `pending`. (Guards the chunk-loss fix: today
   `o9mutq` does `remove(pending)` at claim time, before `done`.)
2. **Bounded retries** — each requeue increments `attempt`; past
   `max_attempts` the task is retired as `infra_fail`, not re-queued forever.

## Quake-3 model mapped to the grid

Quake 3 records every server event to an ordered demo file and plays it back
by re-simulating. This grid borrows three properties:

- **append-only** — `journal.log` only grows; events are never edited.
- **one event per transition** — no silent state mutation; if the grid
  changed, an event was emitted.
- **reconstructable** — `replay` rebuilds task/worker lifecycles from the
  journal, the way a demo plays back a match.

Differences from Quake 3: there is no global tick clock across nodes, so `seq`
is per-origin (monotonic per worker) and global ordering is by `ts_ms` then
`origin` then `seq`. Concurrency safety comes from `OAPPEND` + one write per
event, not from a single-threaded recorder.

## How this maps to the four requested bundles

- **Crash recovery** → `crash_recovery.feature` + the chunk-loss scenarios in
  `queue.feature`; invariants above.
- **Unattended completion** → `campaign.feature` (-D, -W) +
  `control.feature` (wait-drain) + the daemon scenarios in
  `crash_recovery.feature`.
- **Observability + triage** → `status_observability.feature` +
  `triage_bridge.feature` + the triage subcommand in `control.feature`.
- **Worker hygiene** → the `@hygiene` scenarios across `worker.feature`,
  `control.feature`, `campaign.feature`, `status_observability.feature`.
- **Event/replay system** (the requested Quake-3 playback) →
  `event_journal.feature` + `replay.feature` + the `@journal` scenarios
  woven through every other feature.

## Implementation notes (non-normative)

- The journal is the preferred source of truth for observability and triage
  (`status --from-journal`, triage `--from-journal`); file-scan status
  remains as a cross-check.
- `OAPPEND` is the intended append primitive for `journal.log`; each event
  is a single `fprint` so one 9P write = one atomic append. (Verify `OAPPEND`
  availability on the target 9front libc during implementation.)
- `requeue-stale` gains a chunk sweep and an attempt-increment path; it reads
  `max_attempts` from `config.tab`.
- The chunk-loss fix is mechanical: move `remove(pending)` to after
  `create(done)`. Task pending already survives until done; chunks did not.
