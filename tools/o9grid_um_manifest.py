#!/usr/bin/env python3
"""Generate Universal Mutator grid tasks for the o9 9front worker grid."""

from __future__ import annotations

import argparse
import csv
import random
import shutil
import sys
import time
from pathlib import Path
from typing import Sequence

import o9um


HEADER = ("task_id", "source", "mutant_path", "gate", "timeout_ms", "priority")


def rc_quote(text: object) -> str:
    s = str(text)
    return "'" + s.replace("'", "''") + "'"


def host_to_plan9(path: Path, prefix: str) -> str:
    return prefix.rstrip("/") + str(path.resolve())


def pick(mutants: Sequence[Path], limit: int | None, seed: int | None) -> list[Path]:
    selected = list(mutants)
    if seed is not None:
        rng = random.Random(seed)
        rng.shuffle(selected)
    if limit is not None and limit >= 0:
        selected = selected[:limit]
    return selected


def source_list(args: argparse.Namespace) -> list[Path]:
    sources: list[Path] = []
    if args.target_set:
        sources.extend(o9um.target_sources(args.target_set))
    sources.extend(Path(s) for s in args.source)
    if not sources:
        raise SystemExit("o9grid_um_manifest: choose --target-set and/or --source")
    missing = [str(p) for p in sources if not p.exists()]
    if missing:
        raise SystemExit("o9grid_um_manifest: missing source(s): " + ", ".join(missing))
    return sources


def generated_mutants(args: argparse.Namespace, source: Path, mutant_dir: Path) -> list[Path]:
    if args.clean and mutant_dir.exists():
        shutil.rmtree(mutant_dir)
    if mutant_dir.exists():
        mutants = sorted(mutant_dir.glob("*mutant*"), key=o9um.natural_key)
        if mutants:
            return mutants
    return o9um.generate_mutants(
        args,
        source,
        o9um.language_for_source(source, args.language),
        mutant_dir,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-set", choices=sorted(o9um.TARGET_SETS), default=None)
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--mutant-root", default="o9c/test/artifacts/o9um-grid-mutants")
    parser.add_argument("--manifest", default="o9c/test/artifacts/o9um_grid_manifest.tsv")
    parser.add_argument("--enqueue-rc", default="o9c/test/artifacts/o9um_grid_enqueue.rc")
    parser.add_argument("--plan9-prefix", default="/mnt/term/mnt/term",
        help="worker-visible prefix for host paths; rcpu workers usually need /mnt/term/mnt/term")
    parser.add_argument("--enqueue-prefix", default="/mnt/term",
        help="dev9p-visible prefix used by the generated enqueue rc script")
    parser.add_argument("--inline-enqueue", action="store_true",
        help="write one o9mutctl enqueue command per row instead of using bulk manifest enqueue")
    parser.add_argument("--gate-plan9-path", default=None)
    parser.add_argument("--timeout-ms", default="300000")
    parser.add_argument("--priority", default="100")
    parser.add_argument("--limit", type=int, default=None, help="mutants per source; omit for exhaustive")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--language", default=None)
    parser.add_argument("--mutate", default=None)
    parser.add_argument("--only-rule", default=None)
    parser.add_argument("--swap", action="store_true")
    parser.add_argument("--mutate-in-strings", action="store_true")
    parser.add_argument("--generate-timeout", type=float, default=None)
    args = parser.parse_args()

    mutate = o9um.find_mutate(args.mutate)
    args.mutate = mutate

    repo = Path.cwd()
    gate = args.gate_plan9_path or host_to_plan9(repo / "grid" / "o9um_gate.rc", args.plan9_prefix)
    root = Path(args.mutant_root)
    rows: list[tuple[str, str, str, str, str, str]] = []

    for source in source_list(args):
        mutant_dir = root / o9um.safe_name(source)
        mutants = generated_mutants(args, source, mutant_dir)
        selected = pick(mutants, args.limit, args.seed)
        for mutant in selected:
            task_id = f"{o9um.safe_name(source)}.{mutant.name}".replace("/", "_")
            rows.append((
                task_id,
                str(source),
                host_to_plan9(mutant, args.plan9_prefix),
                gate,
                args.timeout_ms,
                args.priority,
            ))

    manifest = Path(args.manifest)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    with manifest.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerows(rows)

    enqueue = Path(args.enqueue_rc)
    enqueue.parent.mkdir(parents=True, exist_ok=True)
    enqueue_manifest_path = host_to_plan9(manifest, args.enqueue_prefix)
    with enqueue.open("w", encoding="utf-8") as f:
        f.write("#!/bin/rc\n")
        f.write("if(~ $#* 0){ echo 'usage: o9um_grid_enqueue.rc root' >[1=2]; exit usage }\n")
        f.write("root=$1\n")
        f.write("bindir=$root/bin\n")
        f.write("if(! test -e $bindir/o9mutctl){ echo missing $bindir/o9mutctl >[1=2]; exit missing }\n")
        f.write("echo enqueue_count " + str(len(rows)) + "\n")
        if args.inline_enqueue:
            for row in rows:
                task_id, source, mutant, gate_path, timeout_ms, priority = row
                f.write(
                    "$bindir/o9mutctl -r $root enqueue "
                    + " ".join(rc_quote(v) for v in (task_id, source, mutant, gate_path, timeout_ms, priority))
                    + " >/dev/null\n"
                )
        else:
            f.write("elog=$root/logs/enqueue.$pid.out\n")
            f.write("$bindir/o9mutctl -r $root manifest " + rc_quote(enqueue_manifest_path) + " >$elog >[2=1]\n")
            f.write("cat $elog\n")
            f.write("if(! grep -s 'manifest_enqueued' $elog){ echo manifest enqueue failed >[1=2]; exit enqueue }\n")
            f.write("enq=`{grep '^manifest_enqueued' $elog}\n")
            f.write("if(~ $#enq 0){ echo manifest enqueue count missing >[1=2]; exit enqueue }\n")
            f.write("if(~ $enq(2) 0){ echo manifest enqueue produced zero tasks >[1=2]; exit enqueue }\n")
        f.write("echo enqueued " + str(len(rows)) + "\n")
    enqueue.chmod(0o755)

    print(f"o9grid_um_manifest: mutants={len(rows)} manifest={manifest} enqueue_rc={enqueue} generated_at={int(time.time())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
