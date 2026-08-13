#!/usr/bin/env python3
"""Prepare file-backed o9 mutation-grid task queues.

This is intentionally a bridge, not the grid runner. Universal Mutator can keep
generating candidate mutants on the host while the o9 tools coordinate workers
through the shared 9P tree.
"""

from __future__ import annotations

import argparse
import csv
import os
import time
from pathlib import Path


HEADER = [
    "task_id",
    "source",
    "mutant_path",
    "gate",
    "timeout_ms",
    "priority",
    "attempt",
    "created_at",
]


def clean_field(value: object) -> str:
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


def ensure_layout(root: Path) -> None:
    for rel in [
        "",
        "tasks",
        "tasks/pending",
        "tasks/claimed",
        "tasks/done",
        "workers",
        "results",
        "logs",
        "repo",
        "mutants",
        "reports",
    ]:
        (root / rel).mkdir(parents=True, exist_ok=True)
    config = root / "config.tab"
    if not config.exists():
        config.write_text(
            "key\tvalue\n"
            "schema\to9mut-grid-v1\n"
            "heartbeat_sec\t30\n"
            "stale_sec\t300\n"
            "max_attempts\t3\n",
            encoding="utf-8",
        )


def write_task(
    root: Path,
    task_id: str,
    source: str,
    mutant_path: str,
    gate: str,
    timeout_ms: str,
    priority: str,
    attempt: str = "0",
) -> Path:
    task_id = clean_field(task_id).replace("/", "_")
    if not task_id:
        task_id = f"task.{time.time_ns()}.{os.getpid()}"
    row = [
        task_id,
        clean_field(source),
        clean_field(mutant_path),
        clean_field(gate),
        clean_field(timeout_ms),
        clean_field(priority),
        clean_field(attempt),
        str(int(time.time())),
    ]
    path = root / "tasks" / "pending" / f"{task_id}.tab"
    tmp = path.with_suffix(".tab.tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerow(row)
    tmp.replace(path)
    return path


def enqueue_one(args: argparse.Namespace) -> None:
    root = Path(args.root)
    ensure_layout(root)
    path = write_task(
        root,
        args.task_id,
        args.source,
        args.mutant_path,
        args.gate,
        args.timeout_ms,
        args.priority,
    )
    print(path)


def enqueue_manifest(args: argparse.Namespace) -> None:
    root = Path(args.root)
    ensure_layout(root)
    count = 0
    with Path(args.manifest).open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        missing = [name for name in ["task_id", "source", "mutant_path", "gate"] if name not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(f"manifest missing columns: {', '.join(missing)}")
        for row in reader:
            write_task(
                root,
                row.get("task_id", ""),
                row.get("source", ""),
                row.get("mutant_path", ""),
                row.get("gate", ""),
                row.get("timeout_ms", args.timeout_ms),
                row.get("priority", args.priority),
                row.get("attempt", "0"),
            )
            count += 1
    print(f"enqueued\t{count}")


def enqueue_dir(args: argparse.Namespace) -> None:
    root = Path(args.root)
    mutants = Path(args.mutants_dir)
    ensure_layout(root)
    count = 0
    for path in sorted(mutants.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(mutants)
        task_id = f"{Path(args.source).name}.{str(rel).replace('/', '_')}"
        write_task(
            root,
            task_id,
            args.source,
            str(path),
            args.gate,
            args.timeout_ms,
            args.priority,
        )
        count += 1
    print(f"enqueued\t{count}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    init = sub.add_parser("init")
    init.add_argument("--root", required=True)
    init.set_defaults(func=lambda args: ensure_layout(Path(args.root)))

    one = sub.add_parser("enqueue")
    one.add_argument("--root", required=True)
    one.add_argument("--task-id", required=True)
    one.add_argument("--source", required=True)
    one.add_argument("--mutant-path", required=True)
    one.add_argument("--gate", required=True)
    one.add_argument("--timeout-ms", default="300000")
    one.add_argument("--priority", default="100")
    one.set_defaults(func=enqueue_one)

    manifest = sub.add_parser("manifest")
    manifest.add_argument("--root", required=True)
    manifest.add_argument("--manifest", required=True)
    manifest.add_argument("--timeout-ms", default="300000")
    manifest.add_argument("--priority", default="100")
    manifest.set_defaults(func=enqueue_manifest)

    directory = sub.add_parser("from-dir")
    directory.add_argument("--root", required=True)
    directory.add_argument("--source", required=True)
    directory.add_argument("--mutants-dir", required=True)
    directory.add_argument("--gate", required=True)
    directory.add_argument("--timeout-ms", default="300000")
    directory.add_argument("--priority", default="100")
    directory.set_defaults(func=enqueue_dir)

    args = parser.parse_args()
    result = args.func(args)
    if result is not None:
        print(result)


if __name__ == "__main__":
    main()
