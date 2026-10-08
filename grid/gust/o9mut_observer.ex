defmodule O9Mut.Observer do
  @moduledoc """
  Read-only snapshot of an Objective-9 mutation campaign.

  The grid's `.tab` files are ordinary UTF-8, tab-separated text here. This
  module does not need libtab or a writable view of the 9P-backed campaign.
  """

  @manifest_header ~w(task_id source mutant_path gate timeout_ms priority)
  @result_header ~w(task_id worker_id source mutant_path result exit_code seconds log_path reason finished_at)
  @statuses ~w(killed survived timeout equivalent infra_fail setup_error)
  @infra_markers [
    {"no_procs", "no procs"},
    {"kproc_exhaustion", "no proc for kproc"},
    {"cant_fork", "can't fork"},
    {"out_of_memory", "out of memory"},
    {"ramfs_out_of_memory", "Insufficient physical memory"},
    {"missing_mk_target", "don't know how to make"},
    {"gate_missing", "o9um-grid-gate: missing"},
    {"ramfs_failed", "o9um-grid-gate: ramfs"},
    {"copy_failed", "o9um-grid-gate: copy"},
    {"bind_failed", "o9um-grid-gate: bind"}
  ]

  @doc "Parse results, audit killed logs, and write text reports."
  def snapshot(root, manifest_path, report_dir, report_id, opts \\ []) do
    recheck_all_kills = Keyword.get(opts, :recheck_all_kills, false)
    manifest = read_manifest(manifest_path)
    result_dir = Path.join(root, "results")
    {:ok, names} = File.ls(result_dir)

    state = %{
      counts: Map.new(@statuses, &{&1, 0}),
      reported_counts: Map.new(@statuses, &{&1, 0}),
      seen: MapSet.new(),
      present_ids: MapSet.new(),
      recheck_ids: MapSet.new(),
      invalid: [],
      in_progress: [],
      suspect: [],
      recheck_all_kills: recheck_all_kills,
      unreadable_kill_logs: 0,
      files_seen: 0
    }

    state =
      names
      |> Enum.filter(&String.ends_with?(&1, ".tab"))
      |> Enum.sort()
      |> Enum.reduce(state, &scan_result(&1, result_dir, root, manifest, &2))

    queue_enqueued = read_queue_enqueued(root)
    valid = MapSet.size(state.seen)
    present = MapSet.size(state.present_ids)
    missing = map_size(manifest) - present
    observed_at = DateTime.utc_now() |> DateTime.to_iso8601()
    report_id = safe_report_id(report_id)
    File.mkdir_p!(report_dir)
    summary_path = Path.join(report_dir, "#{report_id}.summary.tsv")
    suspect_path = Path.join(report_dir, "#{report_id}.suspected-infra.tsv")
    invalid_path = Path.join(report_dir, "#{report_id}.invalid.tsv")
    recheck_path = Path.join(report_dir, "#{report_id}.recheck-manifest.tsv")

    summary = %{
      "observed_at" => observed_at,
      "manifest_total" => map_size(manifest),
      "queue_enqueued" => queue_enqueued,
      "mirror_age_seconds" => read_mirror_age(root),
      "files_seen" => state.files_seen,
      "valid_results" => valid,
      "unvalidated_results" => present - valid,
      "missing_results" => missing,
      "in_progress_files" => length(state.in_progress),
      "invalid_files" => length(state.invalid),
      "suspected_infra_kills" => length(state.suspect),
      "unreadable_kill_logs" => state.unreadable_kill_logs,
      "recheck_candidates" => MapSet.size(state.recheck_ids),
      "recheck_all_kills" => recheck_all_kills
    }

    summary =
      Enum.reduce(@statuses, summary, fn status, acc ->
        acc
        |> Map.put(status, Map.fetch!(state.counts, status))
        |> Map.put("reported_#{status}", Map.fetch!(state.reported_counts, status))
      end)

    write_tsv(
      summary_path,
      ["key", "value"],
      Enum.map(Enum.sort(summary), fn {k, v} -> [k, v] end)
    )

    write_tsv(
      suspect_path,
      ["task_id", "worker_id", "marker", "log_file"],
      Enum.reverse(state.suspect)
    )

    write_tsv(invalid_path, ["file", "problem"], Enum.reverse(state.invalid))
    write_manifest_subset(manifest_path, recheck_path, state.recheck_ids)

    Map.merge(summary, %{
      "summary_file" => summary_path,
      "suspected_infra_file" => suspect_path,
      "invalid_file" => invalid_path,
      "recheck_manifest_file" => recheck_path,
      "suspect_sample" => state.suspect |> Enum.take(10) |> Enum.map(&hd/1)
    })
  end

  @doc "Read the six-column grid manifest as text, rejecting duplicate IDs."
  def read_manifest(path) do
    lines = File.stream!(path, [], :line) |> Stream.with_index()

    if Enum.empty?(lines), do: raise(ArgumentError, "empty manifest")

    Enum.reduce(lines, %{}, fn {line, index}, acc ->
      fields = fields(line)

      cond do
        index == 0 and fields == @manifest_header ->
          acc

        index == 0 ->
          raise ArgumentError, "manifest header does not match grid schema"

        length(fields) != length(@manifest_header) ->
          raise ArgumentError, "malformed manifest row #{index + 1}"

        true ->
          [id, source, mutant | _] = fields

          if id == "" or Map.has_key?(acc, id),
            do: raise(ArgumentError, "empty or duplicate manifest task ID on row #{index + 1}")

          Map.put(acc, id, {source, mutant})
      end
    end)
  end

  defp scan_result(name, dir, root, manifest, state) do
    path = Path.join(dir, name)
    state = %{state | files_seen: state.files_seen + 1}

    case read_result(path) do
      {:error, :in_progress} ->
        %{state | in_progress: [name | state.in_progress]}

      {:error, reason} ->
        state
        |> track_malformed_result(name, manifest)
        |> invalid(name, reason)

      {:ok, row} ->
        id = row["task_id"]

        state =
          if name == id <> ".tab" and Map.has_key?(manifest, id) do
            %{
              state
              | present_ids: MapSet.put(state.present_ids, id),
                reported_counts: Map.update!(state.reported_counts, row["result"], &(&1 + 1))
            }
          else
            state
          end

        cond do
          name != id <> ".tab" ->
            invalid(state, name, "filename_task_id_mismatch")

          not Map.has_key?(manifest, id) ->
            invalid(state, name, "unexpected_task_id")

          Map.fetch!(manifest, id) != {row["source"], row["mutant_path"]} ->
            state
            |> add_recheck(id)
            |> invalid(name, "manifest_source_or_mutant_mismatch")

          not safe_name?(id) or not safe_name?(row["worker_id"]) ->
            invalid(state, name, "unsafe_task_or_worker_id")

          MapSet.member?(state.seen, id) ->
            invalid(state, name, "duplicate_task_id")

          true ->
            state = %{
              state
              | seen: MapSet.put(state.seen, id),
                counts: Map.update!(state.counts, row["result"], &(&1 + 1))
            }

            state =
              if row["result"] in ["timeout", "infra_fail", "setup_error"],
                do: add_recheck(state, id),
                else: state

            state =
              if row["result"] == "killed" and state.recheck_all_kills,
                do: add_recheck(state, id),
                else: state

            if row["result"] == "killed", do: audit_kill(root, row, state), else: state
        end
    end
  end

  defp read_result(path) do
    with {:ok, data} <- File.read(path),
         true <- byte_size(data) <= 65_536,
         true <- String.ends_with?(data, "\n") do
      lines = data |> String.split("\n", trim: true) |> Enum.map(&String.trim_trailing(&1, "\r"))

      case lines do
        [header, row] ->
          columns = String.split(header, "\t", trim: false)
          values = String.split(row, "\t", trim: false)

          if columns == @result_header and length(values) == length(@result_header) do
            record = Map.new(Enum.zip(columns, values))

            if record["result"] in @statuses,
              do: {:ok, record},
              else: {:error, "unknown_result"}
          else
            {:error, "result_schema_mismatch"}
          end

        _ ->
          {:error, "result_row_count"}
      end
    else
      false -> {:error, :in_progress}
      {:error, reason} -> {:error, "read_error:#{inspect(reason)}"}
    end
  end

  defp audit_kill(root, row, state) do
    id = row["task_id"]
    worker = row["worker_id"]
    log_name = Path.basename(row["log_path"])

    log_name =
      if String.starts_with?(log_name, id <> ".") and
           String.ends_with?(log_name, ".log") and safe_name?(log_name),
         do: log_name,
         else: "#{id}.#{worker}.log"

    log_file = Path.join([root, "logs", log_name])

    case File.open(log_file, [:read, :binary]) do
      {:ok, file} ->
        {:ok, size} = :file.position(file, :eof)
        {:ok, _offset} = :file.position(file, max(size - 65_536, 0))
        data = IO.binread(file, 65_536)
        File.close(file)

        marker =
          Enum.find_value(@infra_markers, fn {label, text} ->
            if is_binary(data) and :binary.match(data, text) != :nomatch, do: label
          end)

        if marker do
          state
          |> add_recheck(id)
          |> Map.update!(:suspect, &[[id, worker, marker, log_file] | &1])
        else
          state
        end

      {:error, _} ->
        state
        |> add_recheck(id)
        |> Map.update!(:unreadable_kill_logs, &(&1 + 1))
    end
  end

  defp read_queue_enqueued(root) do
    path = Path.join([root, "queue", "counts.tab"])

    case File.read(path) do
      {:ok, data} ->
        data
        |> String.split("\n", trim: true)
        |> Enum.map(&String.split(&1, "\t", parts: 2))
        |> Enum.find_value(fn
          ["manifest_enqueued", value] ->
            case Integer.parse(value) do
              {count, ""} -> count
              _ -> nil
            end

          _ ->
            nil
        end)

      _ ->
        nil
    end
  end

  defp read_mirror_age(root) do
    case File.stat(Path.join(root, "sync-complete"), time: :posix) do
      {:ok, stat} -> max(System.system_time(:second) - stat.mtime, 0)
      _ -> nil
    end
  end

  defp invalid(state, name, reason), do: %{state | invalid: [[name, reason] | state.invalid]}

  defp track_malformed_result(state, name, manifest) do
    id = String.trim_trailing(name, ".tab")

    if name == id <> ".tab" and Map.has_key?(manifest, id) do
      state
      |> add_recheck(id)
      |> Map.update!(:present_ids, &MapSet.put(&1, id))
    else
      state
    end
  end

  defp add_recheck(state, id), do: %{state | recheck_ids: MapSet.put(state.recheck_ids, id)}

  defp write_manifest_subset(source, target, ids) do
    temp = target <> ".tmp.#{System.unique_integer([:positive])}"

    count =
      File.open!(temp, [:write], fn out ->
        source
        |> File.stream!([], :line)
        |> Stream.with_index()
        |> Enum.reduce(0, fn {line, index}, count ->
          if index == 0 do
            IO.binwrite(out, line)
            count
          else
            [id | _] = fields(line)

            if MapSet.member?(ids, id) do
              IO.binwrite(out, line)
              count + 1
            else
              count
            end
          end
        end)
      end)

    if count != MapSet.size(ids), do: raise(ArgumentError, "recheck manifest is incomplete")
    File.rename!(temp, target)
  end

  defp fields(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
    |> String.split("\t", trim: false)
  end

  defp safe_name?(name), do: is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, name)

  defp safe_report_id(id) do
    id = to_string(id)
    if safe_name?(id), do: id, else: raise(ArgumentError, "unsafe report ID")
  end

  defp write_tsv(path, header, rows) do
    content =
      ([header] ++ rows)
      |> Enum.map_join("\n", fn row -> Enum.map_join(row, "\t", &safe_field/1) end)
      |> Kernel.<>("\n")

    temp = path <> ".tmp.#{System.unique_integer([:positive])}"
    File.write!(temp, content)
    File.rename!(temp, path)
  end

  defp safe_field(nil), do: ""

  defp safe_field(value) do
    value
    |> to_string()
    |> String.replace(["\t", "\r", "\n"], " ")
  end
end
