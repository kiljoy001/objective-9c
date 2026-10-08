# Gust observer for the mutation grid

Gust runs on `rentonsoftworks.coin`. The active Objective-9 campaign remains on
the workstation at `/tmp/o9mut-campaign-20261003-full`; 9front workers still
use its existing drawterm-backed 9P namespace. The observer never writes to
that campaign. A workstation user timer mirrors only the manifest, result
files, logs, and compact worker/queue status into
`~/services/gust/campaigns/active` on the Gust host.

`o9mut_observe.ex` is a Gust DAG scheduled every 15 minutes. Its `scan` task
uses `O9Mut.Observer` to parse each `.tab` file as tab-separated text. It
validates result IDs, source paths, and mutant paths against the manifest;
counts each outcome; and reads the last 64 KiB of each available killed log
for known infrastructure and setup messages. It writes four TSV artifacts per Gust run
under `~/services/gust/reports`: summary, suspected infrastructure kills,
invalid results, and a recheck manifest using the grid's six-column schema.
The active campaign's recheck manifest includes every killed result because a
shared Authomatic process outage has no reliable per-task time boundary. It
also includes timeouts, setup errors, infrastructure failures, malformed
completed results, and results whose source or mutant disagrees with the
manifest. It is
an input for a later fresh campaign; the observer never enqueues it. The
`quality_gate` task fails the Gust run when it finds invalid results, setup
failures, suspected infrastructure kills, killed results whose logs cannot be
audited, a manifest count mismatch, or a mirror older than 30 minutes. An
incomplete result file being written by a worker is counted separately and
retried on the next scan.

The raw `reported_*` counts include structurally valid result rows even when
their source or mutant differs from the manifest. The unprefixed outcome
counts include only rows that pass those checks. `missing_results` counts
manifest IDs with no complete result file; an invalid result with a matching
task ID is instead included in `unvalidated_results`.

## Operate

Refresh the mirror immediately from the workstation:

```sh
grid/gust/sync_active_campaign.sh
```

Open `https://rentonsoftworks.coin:4443/`, select `o9mut_observe`, and click
**Trigger** for an immediate snapshot. The dashboard shows each task and its
logs. A failed quality gate means the summary was still written; read the
`scan` task result or the corresponding TSV files on the Gust host.

The installed workstation timer is `o9mut-gust-sync.timer`. Inspect it with
`systemctl --user status o9mut-gust-sync.timer` or run its service once with
`systemctl --user start o9mut-gust-sync.service`. Gust's Compose project is
`/home/scott/services/gust/compose.yaml` on `rentonsoftworks.coin`.

## Develop

The parser has no Gust or libtab dependency and can be tested locally:

```sh
elixir grid/gust/o9mut_observer_test.exs
```

The active campaign is observed only. Fresh campaign launch and node control
will use a separately planned namespace and worker protocol after this
observer has established which existing outcomes require rechecking.
