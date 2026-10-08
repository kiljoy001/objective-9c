Code.require_file("/opt/o9mut/o9mut_observer.ex")

defmodule O9Mut.Observe do
  @moduledoc """
  Periodic, read-only quality check of the active 9front mutation campaign.

  The Linux bridge mirrors ordinary result and log text files into /campaign.
  Gust never writes to the grid queue or its 9P namespace.
  """

  use Gust.DSL, schedule: "*/15 * * * *"
  require Logger

  task :scan, downstream: [:publish], save: true, ctx: %{run_id: run_id} do
    O9Mut.Observer.snapshot(
      "/campaign",
      "/campaign/manifest.tsv",
      "/reports",
      "gust-run-#{run_id}",
      recheck_all_kills: true
    )
  end

  task :publish, downstream: [:quality_gate], ctx: %{run_id: run_id} do
    summary = Gust.Flows.get_task_by_name_run("scan", run_id).result

    Logger.info(
      "o9mut snapshot: #{summary["valid_results"]}/#{summary["manifest_total"]} valid; " <>
        "#{summary["missing_results"]} missing; #{summary["suspected_infra_kills"]} suspect kills; " <>
        "#{summary["invalid_files"]} invalid files; report=#{summary["summary_file"]}"
    )
  end

  task :quality_gate, ctx: %{run_id: run_id} do
    summary = Gust.Flows.get_task_by_name_run("scan", run_id).result

    failures =
      [
        {"mirror stale",
         summary["mirror_age_seconds"] == nil or summary["mirror_age_seconds"] > 1800},
        {"queue/manifest count mismatch", summary["queue_enqueued"] != summary["manifest_total"]},
        {"invalid results", summary["invalid_files"] > 0},
        {"suspected infrastructure kills", summary["suspected_infra_kills"] > 0},
        {"shared auth outage requires kill recheck",
         summary["recheck_all_kills"] and summary["killed"] > 0},
        {"unverifiable kills (missing logs)", summary["unreadable_kill_logs"] > 0},
        {"setup errors", summary["reported_setup_error"] > 0},
        {"infrastructure failures", summary["reported_infra_fail"] > 0}
      ]
      |> Enum.filter(fn {_message, failed?} -> failed? end)
      |> Enum.map(fn {message, _failed?} -> message end)

    if failures != [] do
      raise Gust.DAG.NonRecError,
            "mutation campaign needs triage: #{Enum.join(failures, ", ")}; " <>
              "summary=#{summary["summary_file"]}"
    end

    :ok
  end
end
