ExUnit.start()
Code.require_file("o9mut_observer.ex", __DIR__)

defmodule O9Mut.ObserverTest do
  use ExUnit.Case, async: true

  @manifest_header "task_id\tsource\tmutant_path\tgate\ttimeout_ms\tpriority\n"
  @result_header "task_id\tworker_id\tsource\tmutant_path\tresult\texit_code\tseconds\tlog_path\treason\tfinished_at\n"

  setup do
    base = Path.join(System.tmp_dir!(), "o9mut-observer-#{System.unique_integer([:positive])}")
    root = Path.join(base, "campaign")
    report_dir = Path.join(base, "reports")
    manifest = Path.join(base, "manifest.tsv")

    for dir <- ["results", "logs", "queue"] do
      File.mkdir_p!(Path.join(root, dir))
    end

    on_exit(fn -> File.rm_rf!(base) end)
    {:ok, root: root, report_dir: report_dir, manifest: manifest}
  end

  test "counts text results and flags a killed result caused by no procs", ctx do
    write_manifest(ctx.manifest, [
      ["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"],
      ["m2", "o9c/a.c", "/mutants/m2", "/gate", "300000", "100"]
    ])

    write_result(ctx.root, "m1", "dev9p-1", "o9c/a.c", "/mutants/m1", "killed")
    write_result(ctx.root, "m2", "dev9p-2", "o9c/a.c", "/mutants/m2", "survived")
    File.write!(Path.join([ctx.root, "logs", "m1.dev9p-1.log"]), "rc: try again: no procs\n")

    File.write!(
      Path.join([ctx.root, "queue", "counts.tab"]),
      "key\tvalue\nmanifest_enqueued\t2\n"
    )

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-1")

    assert summary["manifest_total"] == 2
    assert summary["queue_enqueued"] == 2
    assert summary["killed"] == 1
    assert summary["reported_killed"] == 1
    assert summary["survived"] == 1
    assert summary["suspected_infra_kills"] == 1
    assert summary["missing_results"] == 0
    assert summary["recheck_candidates"] == 1
    assert File.read!(summary["suspected_infra_file"]) =~ "m1\tdev9p-1\tno_procs"
    assert File.read!(summary["summary_file"]) =~ "valid_results\t2\n"
    assert File.read!(summary["recheck_manifest_file"]) =~ "m1\to9c/a.c"
    refute File.read!(summary["recheck_manifest_file"]) =~ "m2\to9c/a.c"
  end

  test "keeps partial writes and malformed or unexpected rows out of valid counts", ctx do
    write_manifest(ctx.manifest, [
      ["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"],
      ["m2", "o9c/a.c", "/mutants/m2", "/gate", "300000", "100"]
    ])

    File.write!(Path.join([ctx.root, "results", "m1.tab"]), @result_header <> "m1\tdev9p")
    write_result(ctx.root, "unknown", "dev9p-1", "o9c/a.c", "/mutants/unknown", "killed")
    write_result(ctx.root, "m2", "dev9p-1", "o9c/a.c", "/wrong-mutant", "survived")

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-2")

    assert summary["valid_results"] == 0
    assert summary["in_progress_files"] == 1
    assert summary["invalid_files"] == 2
    assert summary["missing_results"] == 1
    assert summary["unvalidated_results"] == 1
    assert summary["recheck_candidates"] == 1
    assert File.read!(summary["invalid_file"]) =~ "unexpected_task_id"
    assert File.read!(summary["invalid_file"]) =~ "manifest_source_or_mutant_mismatch"
  end

  test "rejects duplicate manifest IDs and unsafe report names", ctx do
    row = ["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]
    write_manifest(ctx.manifest, [row, row])

    assert_raise ArgumentError, ~r/duplicate manifest task ID/, fn ->
      O9Mut.Observer.read_manifest(ctx.manifest)
    end

    write_manifest(ctx.manifest, [row])

    assert_raise ArgumentError, ~r/unsafe report ID/, fn ->
      O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "../escape")
    end
  end

  test "keeps a killed result visible when its log is unavailable", ctx do
    write_manifest(ctx.manifest, [["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]])
    write_result(ctx.root, "m1", "dev9p-1", "o9c/a.c", "/mutants/m1", "killed")

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-3")

    assert summary["killed"] == 1
    assert summary["unreadable_kill_logs"] == 1
    assert summary["suspected_infra_kills"] == 0
    assert summary["recheck_candidates"] == 1
  end

  test "marks a malformed completed result for recheck", ctx do
    write_manifest(ctx.manifest, [["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]])
    write_result(ctx.root, "m1", "dev9p-1", "o9c/a.c", "/mutants/m1", "killed")
    path = Path.join([ctx.root, "results", "m1.tab"])
    File.write!(path, File.read!(path) <> "failed\t123\n")

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-4")

    assert summary["invalid_files"] == 1
    assert summary["missing_results"] == 0
    assert summary["unvalidated_results"] == 1
    assert summary["recheck_candidates"] == 1
    assert File.read!(summary["recheck_manifest_file"]) =~ "m1\to9c/a.c"
  end

  test "audits the log named by the result inside the campaign log directory", ctx do
    write_manifest(ctx.manifest, [["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]])
    write_result(ctx.root, "m1", "new-worker", "o9c/a.c", "/mutants/m1", "killed")
    result = Path.join([ctx.root, "results", "m1.tab"])

    File.write!(
      result,
      String.replace(
        File.read!(result),
        "/logs/m1.new-worker.log",
        "/mnt/term/tmp/grid/logs/m1.old-worker.log"
      )
    )

    File.write!(Path.join([ctx.root, "logs", "m1.old-worker.log"]), "rc: no procs\n")
    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-5")

    assert summary["suspected_infra_kills"] == 1
    assert summary["unreadable_kill_logs"] == 0
  end

  test "finds an infrastructure failure at the end of a long gate log", ctx do
    write_manifest(ctx.manifest, [["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]])
    write_result(ctx.root, "m1", "dev9p-1", "o9c/a.c", "/mutants/m1", "killed")

    File.write!(
      Path.join([ctx.root, "logs", "m1.dev9p-1.log"]),
      String.duplicate("test output\n", 8_000) <> "ramfs: Killed: Insufficient physical memory\n"
    )

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-6")

    assert summary["suspected_infra_kills"] == 1
    assert File.read!(summary["suspected_infra_file"]) =~ "ramfs_out_of_memory"
  end

  test "rechecks a kill when the shared auth server reports kproc exhaustion", ctx do
    write_manifest(ctx.manifest, [["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"]])
    write_result(ctx.root, "m1", "authomatic-1", "o9c/a.c", "/mutants/m1", "killed")

    File.write!(
      Path.join([ctx.root, "logs", "m1.authomatic-1.log"]),
      "auth: no proc for kproc\n"
    )

    summary = O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-kproc")

    assert summary["suspected_infra_kills"] == 1
    assert summary["recheck_candidates"] == 1
    assert File.read!(summary["suspected_infra_file"]) =~ "kproc_exhaustion"
  end

  test "rechecks every kill when a shared outage cannot be timed", ctx do
    write_manifest(ctx.manifest, [
      ["m1", "o9c/a.c", "/mutants/m1", "/gate", "300000", "100"],
      ["m2", "o9c/a.c", "/mutants/m2", "/gate", "300000", "100"]
    ])

    write_result(ctx.root, "m1", "dev9p-1", "o9c/a.c", "/mutants/m1", "killed")
    write_result(ctx.root, "m2", "dev9p-2", "o9c/a.c", "/mutants/m2", "survived")
    File.write!(Path.join([ctx.root, "logs", "m1.dev9p-1.log"]), "ordinary gate failure\n")

    summary =
      O9Mut.Observer.snapshot(ctx.root, ctx.manifest, ctx.report_dir, "run-shared-outage",
        recheck_all_kills: true
      )

    assert summary["recheck_all_kills"]
    assert summary["suspected_infra_kills"] == 0
    assert summary["recheck_candidates"] == 1
    assert File.read!(summary["recheck_manifest_file"]) =~ "m1\to9c/a.c"
    refute File.read!(summary["recheck_manifest_file"]) =~ "m2\to9c/a.c"
  end

  defp write_manifest(path, rows) do
    File.write!(path, @manifest_header <> Enum.map_join(rows, "", &(Enum.join(&1, "\t") <> "\n")))
  end

  defp write_result(root, id, worker, source, mutant, result) do
    row = [
      id,
      worker,
      source,
      mutant,
      result,
      "1",
      "0",
      "/logs/#{id}.#{worker}.log",
      "gate failed",
      "1"
    ]

    File.write!(
      Path.join([root, "results", "#{id}.tab"]),
      @result_header <> Enum.join(row, "\t") <> "\n"
    )
  end
end
