#!/usr/bin/env python3
"""Run Universal Mutator against o9 compiler/runtime sources.

Universal Mutator generates replacement source files.  This wrapper can either
stage one mutant at a time over the original source and restore it, or, better,
run each mutant inside a synthetic 9front ramfs worktree so the checkout is
never mutated.
"""

from __future__ import annotations

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable, Sequence


ARTIFACT_DIR = Path("o9c/test/artifacts")
DEFAULT_MUTATE = "/tmp/o9-universalmutator-venv/bin/mutate"
DEFAULT_PLAN9_REPO = "/mnt/term" + str(Path.cwd())
DEFAULT_EQUIV_FILE = Path("o9c/test/mutation_equiv.tsv")
GRAMMAR_TARGETS = (
    "o9c/grammar.d/00-ast-globals.y",
    "o9c/grammar.d/01-symbols.y",
    "o9c/grammar.d/02-type-helpers.y",
    "o9c/grammar.d/03-yacc-decls.y",
    "o9c/grammar.d/10-grammar-rules.y",
    "o9c/grammar.d/20-ast-construction.y",
    "o9c/grammar.d/30-lexer.y",
    "o9c/grammar.d/40-codegen.y",
    "o9c/grammar.d/50-app-facade.y",
    "o9c/grammar.d/60-prescan.y",
    "o9c/grammar.d/70-typecheck.y",
    "o9c/grammar.d/80-ast-dump.y",
    "o9c/grammar.d/90-import-resolution.y",
    "o9c/grammar.d/91-cdeps.y",
    "o9c/grammar.d/92-import-resolution-continued.y",
    "o9c/grammar.d/99-main.y",
)
COMPILER_TARGETS = ("o9c/o9_type.c",) + GRAMMAR_TARGETS
RUNTIME_TARGETS = (
    "o9_runtime.c",
    "o9_crypto.c",
    "o9_tab_discard.c",
    "libtab/tab_error.c",
    "libtab/tab_create.c",
    "libtab/tab_row.c",
    "libtab/tab_rowmap.c",
    "libtab/tab_iter.c",
    "libtab/tab_codec.c",
    "libtab/tab_open.c",
    "libtab/tab_serialize.c",
    "libtab/tab_persist.c",
)
TARGET_SETS = {
    "compiler": COMPILER_TARGETS,
    "runtime": RUNTIME_TARGETS,
    "all": COMPILER_TARGETS + RUNTIME_TARGETS,
}


def load_equiv(path: Path | None) -> dict[tuple[str, str], str]:
    equiv: dict[tuple[str, str], str] = {}
    if path is None or not path.exists():
        return equiv
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise SystemExit(f"o9um: malformed equivalent file {path}:{lineno}")
        equiv[(parts[0], parts[1])] = parts[2]
    return equiv


def equiv_reason(equiv: dict[tuple[str, str], str], source: Path, mutant: Path) -> str | None:
    return equiv.get((str(source), mutant.name))


def natural_key(path: Path) -> tuple[str, int]:
    match = re.search(r"\.mutant\.(\d+)\.", path.name)
    if match:
        return (path.name[: match.start()], int(match.group(1)))
    return (path.name, -1)


def safe_name(path: Path) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", str(path))


def rc_quote(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def host_to_plan9(path: Path) -> str:
    resolved = path.resolve()
    return "/mnt/term" + str(resolved)


def language_for_source(source: Path, requested: str | None) -> str:
    if requested:
        return requested
    if source.suffix == ".py":
        return "python"
    return "c"


def target_sources(name: str) -> list[Path]:
    if name not in TARGET_SETS:
        raise SystemExit(f"o9um: unknown target set {name!r}")
    paths = [Path(p) for p in TARGET_SETS[name]]
    missing = [str(p) for p in paths if not p.exists()]
    if missing:
        raise SystemExit("o9um: missing target(s): " + ", ".join(missing))
    return paths


def find_mutate(explicit: str | None) -> str:
    candidates = [
        explicit,
        os.environ.get("O9_MUTATE"),
        shutil.which("mutate"),
        DEFAULT_MUTATE,
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit(
        "o9um: missing Universal Mutator. Install it or pass --mutate. "
        "Example: python3 -m venv /tmp/o9-universalmutator-venv && "
        "/tmp/o9-universalmutator-venv/bin/python -m pip install universalmutator"
    )


def run(cmd: Sequence[str], timeout: float | None = None) -> tuple[int | None, str, float]:
    start = time.monotonic()
    try:
        proc = subprocess.run(
            list(cmd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, time.monotonic() - start
    except subprocess.TimeoutExpired as exc:
        out = ""
        if exc.stdout:
            out = exc.stdout if isinstance(exc.stdout, str) else exc.stdout.decode("utf-8", "replace")
        return None, out, time.monotonic() - start


def run_shell(cmd: str, timeout: float | None = None) -> tuple[int | None, str, float]:
    start = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, time.monotonic() - start
    except subprocess.TimeoutExpired as exc:
        out = ""
        if exc.stdout:
            out = exc.stdout if isinstance(exc.stdout, str) else exc.stdout.decode("utf-8", "replace")
        return None, out, time.monotonic() - start


def marker_status(output: str, marker: str | None) -> bool | None:
    if marker is None:
        return None
    status = None
    for line in output.splitlines():
        if line.startswith(marker):
            parts = line.split()
            if len(parts) >= 2:
                status = parts[1]
    if status == "pass":
        return True
    if status == "fail":
        return False
    return None


def command_passed(code: int | None, output: str, marker: str | None) -> bool:
    marked = marker_status(output, marker)
    if marked is not None:
        return marked
    return code == 0


def write_plan9_ramfs_script(args: argparse.Namespace, source: Path, mutant: Path | None) -> Path:
    if not args.gate_rc:
        raise SystemExit("o9um: --synthetic-ramfs requires --gate-rc")
    stem = safe_name(source)
    if mutant is not None:
        stem += "." + safe_name(Path(mutant).name)
    fd, name = tempfile.mkstemp(prefix=f"o9um.{stem}.", suffix=".rc", dir="/tmp", text=True)
    script = Path(name)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("#!/bin/rc\n")
        f.write("rfork n\n")
        f.write("repo=" + rc_quote(args.plan9_repo) + "\n")
        f.write("src=" + rc_quote(str(source)) + "\n")
        f.write("mut=" + rc_quote(host_to_plan9(mutant) if mutant is not None else "") + "\n")
        f.write("mnt=/tmp/o9umram.$pid\n")
        f.write("mkdir $mnt || exit mkdirram\n")
        f.write("ramfs -m $mnt || exit ramfs\n")
        f.write("work=$mnt/repo\n")
        f.write("mkdir $work || exit mkdir\n")
        f.write("fn copydir {\n")
        f.write("\tif(test -d $repo/$1){\n")
        f.write("\t\tmkdir $work/$1 || exit mkdircopydir\n")
        f.write("\t\tdircp $repo/$1 $work/$1 || exit copydir\n")
        f.write("\t}\n")
        f.write("}\n")
        f.write("fn copyfile {\n")
        f.write("\tif(test -e $repo/$1)\n")
        f.write("\t\tcp $repo/$1 $work/$1 || exit copyfile\n")
        f.write("}\n")
        f.write("copydir o9c\n")
        f.write("copydir libtab\n")
        f.write("copydir stdlib\n")
        f.write("copyfile mkfile\n")
        f.write("copyfile o9.h\n")
        f.write("copyfile o9_runtime.c\n")
        f.write("copyfile o9_crypto.c\n")
        f.write("copyfile o9_tab_discard.c\n")
        f.write("copyfile o9_dispatch.s\n")
        f.write("copyfile monocypher.c\n")
        f.write("copyfile monocypher.h\n")
        f.write("if(! ~ $mut ''){\n")
        f.write("\tcp $mut $work/$src || exit mutant\n")
        f.write("}\n")
        f.write("cd $work || exit cd\n")
        f.write("mk clean >/dev/null >[2=1]\n")
        f.write("fn o9um_gate {\n")
        for line in args.gate_rc.splitlines():
            f.write("\t" + line + "\n")
        f.write("}\n")
        f.write("o9um_gate\n")
        f.write("st=$status\n")
        f.write("unmount $mnt >[2]/dev/null\n")
        f.write("exit $st\n")
    return script


def run_verification(
    args: argparse.Namespace,
    source: Path | None,
    mutant: Path | None,
) -> tuple[int | None, str, float]:
    if not args.synthetic_ramfs:
        return run_shell(args.cmd, args.timeout)
    if source is None:
        source = Path("mkfile")
    script = write_plan9_ramfs_script(args, source, mutant)
    plan9_script = host_to_plan9(script)
    cmd = args.cmd.replace("{script}", plan9_script)
    cmd = cmd.replace("{repo}", args.plan9_repo)
    cmd = cmd.replace("{source}", str(source))
    cmd = cmd.replace("{mutant}", host_to_plan9(mutant) if mutant is not None else "")
    try:
        return run_shell(cmd, args.timeout)
    finally:
        try:
            script.unlink()
        except FileNotFoundError:
            pass


def generate_mutants(args: argparse.Namespace, source: Path, language: str, mutant_dir: Path) -> list[Path]:
    mutate = find_mutate(args.mutate)
    mutant_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        mutate,
        str(source),
        language,
        "--noCheck",
        "--mutantDir",
        str(mutant_dir),
    ]
    if args.only_rule:
        cmd.extend(["--only", args.only_rule])
    if args.swap:
        cmd.append("--swap")
    if args.mutate_in_strings:
        cmd.append("--mutateInStrings")
    code, output, _ = run(cmd, timeout=args.generate_timeout)
    log = ARTIFACT_DIR / f"o9um_generate_{safe_name(source)}.log"
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    log.write_text(output, encoding="utf-8")
    if code != 0:
        raise SystemExit(f"o9um: mutate failed; see {log}")
    mutants = sorted(mutant_dir.glob("*mutant*"), key=natural_key)
    if not mutants:
        raise SystemExit(f"o9um: no mutants generated; see {log}")
    return mutants


def pick_mutants(mutants: list[Path], limit: int | None, seed: int | None) -> list[Path]:
    if seed is not None:
        rng = random.Random(seed)
        picked = list(mutants)
        rng.shuffle(picked)
    else:
        picked = mutants
    if limit is not None:
        picked = picked[:limit]
    return picked


def remove_generated_dependents(source: Path) -> None:
    if source.parent.name == "grammar.d":
        try:
            (source.parent.parent / "grammar.y").unlink()
        except FileNotFoundError:
            pass


def write_rows(report: Path, rows: Iterable[Sequence[object]]) -> None:
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write("\t".join(str(cell) for cell in row))
            f.write("\n")


def cmd_generate(args: argparse.Namespace) -> int:
    source = Path(args.source)
    mutant_dir = Path(args.mutant_dir) if args.mutant_dir else Path(
        tempfile.mkdtemp(prefix=f"o9um.{safe_name(source)}.")
    )
    if args.clean and mutant_dir.exists():
        shutil.rmtree(mutant_dir)
    mutants = generate_mutants(args, source, language_for_source(source, args.language), mutant_dir)
    print(f"o9um: generated {len(mutants)} mutants in {mutant_dir}", flush=True)
    return 0


def evaluate_source(
    args: argparse.Namespace,
    source: Path,
    mutant_dir: Path,
    *,
    check_baseline: bool,
) -> tuple[dict[str, int], int]:
    equiv = load_equiv(Path(args.equiv_file) if args.equiv_file else None)
    if not source.exists():
        raise SystemExit(f"o9um: missing source: {source}")
    language = language_for_source(source, args.language)
    if args.clean or not mutant_dir.exists():
        if mutant_dir.exists():
            shutil.rmtree(mutant_dir)
        mutants = generate_mutants(args, source, language, mutant_dir)
    else:
        mutants = sorted(mutant_dir.glob("*mutant*"), key=natural_key)
        if not mutants:
            mutants = generate_mutants(args, source, language, mutant_dir)

    selected = pick_mutants(mutants, args.limit, args.seed)
    if not selected:
        raise SystemExit("o9um: no mutants selected")

    print(f"o9um: source {source}", flush=True)
    print(f"o9um: selected {len(selected)} of {len(mutants)} mutants", flush=True)

    if check_baseline:
        base_code, base_output, base_seconds = run_verification(args, source, None)
        if not command_passed(base_code, base_output, args.status_marker):
            base_log = ARTIFACT_DIR / f"o9um_baseline_{safe_name(source)}.log"
            ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
            base_log.write_text(base_output, encoding="utf-8")
            raise SystemExit(f"o9um: baseline command failed; see {base_log}")
        print(f"o9um: baseline passed in {base_seconds:.2f}s", flush=True)

    rows: list[Sequence[object]] = [("mutant", "result", "exit", "seconds", "reason")]
    counts = {"killed": 0, "survived": 0, "timeout": 0, "equivalent": 0}

    if args.synthetic_ramfs:
        for mutant in selected:
            code, output, seconds = run_verification(args, source, mutant)
            if code is None:
                result = "timeout"
            elif command_passed(code, output, args.status_marker):
                result = "survived"
            else:
                result = "killed"
            reason = ""
            if result == "survived":
                reason = equiv_reason(equiv, source, mutant) or ""
                if reason:
                    result = "equivalent"
            counts[result] += 1
            rows.append((mutant.name, result, "timeout" if code is None else code, f"{seconds:.2f}", reason))
            print(f"o9um: {mutant.name}: {result} ({seconds:.2f}s)", flush=True)
            if result == "survived" and args.stop_on_survive:
                break
    else:
        original = source.read_bytes()
        try:
            for mutant in selected:
                source.write_bytes(mutant.read_bytes())
                remove_generated_dependents(source)
                code, output, seconds = run_verification(args, source, mutant)
                if code is None:
                    result = "timeout"
                elif command_passed(code, output, args.status_marker):
                    result = "survived"
                else:
                    result = "killed"
                reason = ""
                if result == "survived":
                    reason = equiv_reason(equiv, source, mutant) or ""
                    if reason:
                        result = "equivalent"
                counts[result] += 1
                rows.append((mutant.name, result, "timeout" if code is None else code, f"{seconds:.2f}", reason))
                print(f"o9um: {mutant.name}: {result} ({seconds:.2f}s)", flush=True)
                if result == "survived" and args.stop_on_survive:
                    break
        finally:
            source.write_bytes(original)
            remove_generated_dependents(source)

    report = ARTIFACT_DIR / f"o9um_{safe_name(source)}.tsv"
    write_rows(report, rows)
    print(
        "o9um: killed={killed} survived={survived} timeout={timeout} "
        "equivalent={equivalent} report={report}".format(
            report=report, **counts
        ),
        flush=True,
    )
    return counts, len(selected)


def cmd_run(args: argparse.Namespace) -> int:
    source = Path(args.source)
    mutant_dir = Path(args.mutant_dir) if args.mutant_dir else Path(
        tempfile.mkdtemp(prefix=f"o9um.{safe_name(source)}.")
    )
    counts, _ = evaluate_source(args, source, mutant_dir, check_baseline=True)
    return 1 if counts["survived"] or counts["timeout"] else 0


def cmd_batch(args: argparse.Namespace) -> int:
    sources = target_sources(args.target_set)
    if args.source:
        sources.extend(Path(s) for s in args.source)

    base_code, base_output, base_seconds = run_verification(args, None, None)
    if not command_passed(base_code, base_output, args.status_marker):
        base_log = ARTIFACT_DIR / f"o9um_baseline_{args.target_set}.log"
        ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
        base_log.write_text(base_output, encoding="utf-8")
        raise SystemExit(f"o9um: baseline command failed; see {base_log}")
    print(f"o9um: baseline passed in {base_seconds:.2f}s", flush=True)

    root = Path(args.mutant_root)
    total = {"killed": 0, "survived": 0, "timeout": 0, "equivalent": 0}
    rows: list[Sequence[object]] = [
        ("source", "selected", "killed", "survived", "timeout", "equivalent", "score")
    ]

    for source in sources:
        mutant_dir = root / safe_name(source)
        counts, selected = evaluate_source(args, source, mutant_dir, check_baseline=False)
        for key in total:
            total[key] += counts[key]
        live = counts["killed"] + counts["survived"] + counts["timeout"]
        score = 100.0 if live == 0 else (counts["killed"] * 100.0 / live)
        rows.append((
            source,
            selected,
            counts["killed"],
            counts["survived"],
            counts["timeout"],
            counts["equivalent"],
            f"{score:.2f}",
        ))

    live = total["killed"] + total["survived"] + total["timeout"]
    score = 100.0 if live == 0 else (total["killed"] * 100.0 / live)
    rows.append((
        "TOTAL",
        live + total["equivalent"],
        total["killed"],
        total["survived"],
        total["timeout"],
        total["equivalent"],
        f"{score:.2f}",
    ))
    report = ARTIFACT_DIR / f"o9um_batch_{args.target_set}.tsv"
    write_rows(report, rows)
    print(
        "o9um: target={target} killed={killed} survived={survived} "
        "timeout={timeout} equivalent={equivalent} score={score:.2f}% "
        "report={report}".format(
            target=args.target_set,
            score=score,
            report=report,
            **total,
        ),
        flush=True,
    )
    return 1 if total["survived"] or total["timeout"] else 0


def cmd_list_targets(_: argparse.Namespace) -> int:
    for name, paths in TARGET_SETS.items():
        print(f"{name}:")
        for path in paths:
            print(f"\t{path}")
    return 0


def add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("source", type=Path, help="source file to mutate")
    p.add_argument("--language", default=None, help="Universal Mutator language/rules name")
    p.add_argument("--mutate", default=None, help="path to mutate executable")
    p.add_argument("--mutant-dir", default=None, help="directory for generated mutants")
    p.add_argument("--clean", action="store_true", help="delete existing mutant directory first")
    p.add_argument("--only-rule", default=None, help="pass --only to mutate")
    p.add_argument("--swap", action="store_true", help="enable adjacent-line swap mutants")
    p.add_argument("--mutate-in-strings", action="store_true", help="allow mutations inside strings")
    p.add_argument("--generate-timeout", type=float, default=None)
    p.add_argument("--synthetic-ramfs", action="store_true",
        help="run each mutant in a private 9front ramfs worktree; --cmd must contain {script}")
    p.add_argument("--plan9-repo", default=DEFAULT_PLAN9_REPO,
        help="Plan 9 path to the real checkout used as ramfs input")
    p.add_argument("--gate-rc", default=None,
        help="rc snippet run from inside the synthetic ramfs worktree")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Universal Mutator wrapper for objective-9c")
    sub = parser.add_subparsers(dest="cmdname", required=True)

    p = sub.add_parser("generate", help="generate mutants only")
    add_common(p)
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("run", help="generate/stage mutants and run a verification command")
    add_common(p)
    p.add_argument("--limit", type=int, default=10, help="number of mutants to run")
    p.add_argument("--seed", type=int, default=None, help="shuffle mutants with this seed before limiting")
    p.add_argument("--timeout", type=float, default=None, help="timeout per verification command")
    p.add_argument("--status-marker", default=None, help="line marker: '<marker> pass' or '<marker> fail'")
    p.add_argument("--stop-on-survive", action="store_true")
    p.add_argument("--cmd", required=True, help="verification command; nonzero means mutant killed")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("batch", help="run a sampled mutation campaign over a target set")
    p.add_argument("--target-set", choices=sorted(TARGET_SETS), default="compiler")
    p.add_argument("--source", action="append", default=[], help="extra source file to include")
    p.add_argument("--language", default=None, help="force Universal Mutator language/rules name")
    p.add_argument("--mutate", default=None, help="path to mutate executable")
    p.add_argument("--mutant-root", default="/tmp/o9um-batch", help="root directory for generated mutants")
    p.add_argument("--clean", action="store_true", help="delete existing mutant directories first")
    p.add_argument("--only-rule", default=None, help="pass --only to mutate")
    p.add_argument("--swap", action="store_true", help="enable adjacent-line swap mutants")
    p.add_argument("--mutate-in-strings", action="store_true", help="allow mutations inside strings")
    p.add_argument("--generate-timeout", type=float, default=None)
    p.add_argument("--synthetic-ramfs", action="store_true",
        help="run each mutant in a private 9front ramfs worktree; --cmd must contain {script}")
    p.add_argument("--plan9-repo", default=DEFAULT_PLAN9_REPO,
        help="Plan 9 path to the real checkout used as ramfs input")
    p.add_argument("--gate-rc", default=None,
        help="rc snippet run from inside the synthetic ramfs worktree")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.add_argument("--limit", type=int, default=5, help="number of mutants to run per source")
    p.add_argument("--seed", type=int, default=None, help="shuffle mutants with this seed before limiting")
    p.add_argument("--timeout", type=float, default=None, help="timeout per verification command")
    p.add_argument("--status-marker", default=None, help="line marker: '<marker> pass' or '<marker> fail'")
    p.add_argument("--stop-on-survive", action="store_true")
    p.add_argument("--cmd", required=True, help="verification command; nonzero means mutant killed")
    p.set_defaults(func=cmd_batch)

    p = sub.add_parser("list-targets", help="list built-in mutation target sets")
    p.set_defaults(func=cmd_list_targets)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
