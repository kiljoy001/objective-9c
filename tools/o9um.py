#!/usr/bin/env python3
"""Run Universal Mutator against o9 compiler/runtime sources.

Universal Mutator generates replacement source files.  This wrapper can either
stage one mutant at a time over the original source and restore it, or, better,
run each mutant inside a synthetic 9front ramfs worktree so the checkout is
never mutated.
"""

from __future__ import annotations

import argparse
import fnmatch
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
TRIAGE_HEADER = (
    "source",
    "mutant",
    "result",
    "function",
    "original_line",
    "mutant_line",
    "triage_class",
    "confidence",
    "suggested_action",
    "reason",
    "diff_summary",
)
TRIAGE_FAILURE_CLASSES = {"test_gap", "timeout", "unknown", "missing_report"}


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


def timeout_exit_codes(args: argparse.Namespace) -> set[int]:
    codes: set[int] = set()
    for raw in getattr(args, "timeout_exit_code", []) or []:
        for part in raw.split(","):
            if part:
                codes.add(int(part))
    return codes


def command_timed_out(args: argparse.Namespace, code: int | None) -> bool:
    return code is None or (code in timeout_exit_codes(args))


def write_plan9_ramfs_script(
    args: argparse.Namespace,
    source: Path,
    mutant: Path | None,
    gate_rc: str | None = None,
) -> Path:
    gate_rc = args.gate_rc if gate_rc is None else gate_rc
    if not gate_rc:
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
        plan9_tmp = getattr(args, "plan9_tmp", "/tmp") or "/tmp"
        f.write("tmp=" + rc_quote(plan9_tmp.rstrip("/")) + "\n")
        f.write("mnt=$tmp/o9umram.$pid\n")
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
        f.write("copyfile o9_dispatch_$objtype.s\n")
        f.write("copyfile monocypher.c\n")
        f.write("copyfile monocypher.h\n")
        f.write("if(! ~ $mut ''){\n")
        f.write("\tcp $mut $work/$src || exit mutant\n")
        f.write("}\n")
        f.write("cd $work || exit cd\n")
        f.write("mk clean >/dev/null >[2=1]\n")
        f.write("fn o9um_gate {\n")
        for line in gate_rc.splitlines():
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
    *,
    cmd_text: str | None = None,
    gate_rc: str | None = None,
    timeout: float | None = None,
) -> tuple[int | None, str, float]:
    cmd_text = args.cmd if cmd_text is None else cmd_text
    timeout = args.timeout if timeout is None else timeout
    if not args.synthetic_ramfs:
        return run_shell(cmd_text, timeout)
    if source is None:
        source = Path("mkfile")
    script = write_plan9_ramfs_script(args, source, mutant, gate_rc)
    plan9_script = host_to_plan9(script)
    cmd = cmd_text.replace("{script}", plan9_script)
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


def verification_result(args: argparse.Namespace, code: int | None, output: str) -> str:
    if command_timed_out(args, code):
        return "timeout"
    if command_passed(code, output, args.status_marker):
        return "survived"
    return "killed"


def run_mutant_verification(
    args: argparse.Namespace,
    source: Path,
    mutant: Path,
) -> tuple[int | None, str, float, str]:
    total_seconds = 0.0

    if getattr(args, "pre_gate_rc", None):
        pre_cmd = args.pre_cmd or args.cmd
        pre_timeout = args.pre_timeout if args.pre_timeout is not None else args.timeout
        code, output, seconds = run_verification(
            args,
            source,
            mutant,
            cmd_text=pre_cmd,
            gate_rc=args.pre_gate_rc,
            timeout=pre_timeout,
        )
        total_seconds += seconds
        result = verification_result(args, code, output)
        if result != "survived":
            return code, output, total_seconds, result

    code, output, seconds = run_verification(args, source, mutant)
    total_seconds += seconds
    return code, output, total_seconds, verification_result(args, code, output)


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


def mutant_patterns(raw: Sequence[str] | None) -> list[str]:
    patterns: list[str] = []
    for item in raw or []:
        patterns.extend(part for part in item.split(",") if part)
    return patterns


def filter_mutants(mutants: list[Path], only_mutant: Sequence[str] | None) -> list[Path]:
    patterns = mutant_patterns(only_mutant)
    if not patterns:
        return mutants
    selected: list[Path] = []
    for mutant in mutants:
        for pattern in patterns:
            if (
                mutant.name == pattern
                or str(mutant) == pattern
                or fnmatch.fnmatch(mutant.name, pattern)
                or fnmatch.fnmatch(str(mutant), pattern)
            ):
                selected.append(mutant)
                break
    if not selected:
        raise SystemExit("o9um: --only-mutant matched no mutants: " + ", ".join(patterns))
    return selected


def skip_through_mutant(mutants: list[Path], start_after: str | None) -> list[Path]:
    if not start_after:
        return mutants
    for idx, mutant in enumerate(mutants):
        if mutant.name == start_after or str(mutant) == start_after:
            return mutants[idx + 1 :]
    raise SystemExit(f"o9um: --start-after matched no mutant: {start_after}")


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


def effective_limit(args: argparse.Namespace) -> int | None:
    if getattr(args, "exhaustive", False):
        return None
    return getattr(args, "limit", None)


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


def append_row(report: Path, row: Sequence[object]) -> None:
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open("a", encoding="utf-8") as f:
        f.write("\t".join(str(cell) for cell in row))
        f.write("\n")


def read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    rows: list[dict[str, str]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return rows
    header = lines[0].split("\t")
    for line in lines[1:]:
        if not line.strip():
            continue
        cells = line.split("\t")
        row = {name: cells[idx] if idx < len(cells) else "" for idx, name in enumerate(header)}
        rows.append(row)
    return rows


def report_path_for_source(args: argparse.Namespace, source: Path) -> Path:
    report_out = getattr(args, "report_out", None)
    resume_report = getattr(args, "resume_report", None)
    if report_out:
        return Path(report_out)
    if resume_report:
        return Path(resume_report)
    return ARTIFACT_DIR / f"o9um_{safe_name(source)}.tsv"


def prepare_stream_report(
    args: argparse.Namespace,
    source: Path,
) -> tuple[Path, set[str], dict[str, int]]:
    report = report_path_for_source(args, source)
    resume_report = getattr(args, "resume_report", None)
    counts = {"killed": 0, "survived": 0, "timeout": 0, "equivalent": 0}
    completed: set[str] = set()

    if resume_report and report.exists() and report.stat().st_size > 0:
        for row in read_tsv(report):
            mutant = row.get("mutant", "")
            result = row.get("result", "")
            if mutant:
                completed.add(mutant)
            if result in counts:
                counts[result] += 1
    else:
        write_rows(report, [("mutant", "result", "exit", "seconds", "reason")])
    return report, completed, counts


MULTI_CHAR_C_TOKENS = (
    "...", ">>=", "<<=", "##",
    "->", "++", "--", "==", "!=", "<=", ">=", "&&", "||",
    "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>",
)


def c_tokens_without_ws(text: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch.isspace():
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i = min(i + 2, n)
            continue
        if ch == '"' or ch == "'":
            quote = ch
            start = i
            i += 1
            escaped = False
            while i < n:
                ch = text[i]
                if escaped:
                    escaped = False
                    i += 1
                    continue
                if ch == "\\":
                    escaped = True
                    i += 1
                    continue
                i += 1
                if ch == quote:
                    break
            tokens.append(text[start:i])
            continue
        if ch.isalpha() or ch == "_":
            start = i
            i += 1
            while i < n and (text[i].isalnum() or text[i] == "_"):
                i += 1
            tokens.append(text[start:i])
            continue
        if ch.isdigit() or (ch == "." and i + 1 < n and text[i + 1].isdigit()):
            start = i
            i += 1
            while i < n:
                ch = text[i]
                if ch.isalnum() or ch in "._":
                    i += 1
                    continue
                if ch in "+-" and i > start and text[i - 1] in "eEpP":
                    i += 1
                    continue
                break
            tokens.append(text[start:i])
            continue
        matched = False
        for token in MULTI_CHAR_C_TOKENS:
            if text.startswith(token, i):
                tokens.append(token)
                i += len(token)
                matched = True
                break
        if matched:
            continue
        tokens.append(ch)
        i += 1
    return tokens


def lexical_whitespace_equiv(source: Path, mutant: Path) -> str | None:
    try:
        source_text = source.read_text(encoding="utf-8")
        mutant_text = mutant.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    if source_text == mutant_text:
        return None
    if c_tokens_without_ws(source_text) != c_tokens_without_ws(mutant_text):
        return None
    return "lexical whitespace/comment-only source change"


def preclassified_equiv_reason(args: argparse.Namespace, source: Path, mutant: Path) -> str | None:
    if getattr(args, "classify_whitespace_equivalent", False):
        reason = lexical_whitespace_equiv(source, mutant)
        if reason is not None:
            return reason
    return None


def clean_cell(text: object) -> str:
    return str(text).replace("\t", " ").replace("\n", "\\n")


def mutant_diff(source: Path, mutant: Path) -> tuple[int, int, list[str], list[str], str]:
    code, output, _ = run(["diff", "-u", str(source), str(mutant)])
    old_line = 0
    new_line = 0
    removed: list[str] = []
    added: list[str] = []
    for line in output.splitlines():
        match = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if match and old_line == 0:
            old_line = int(match.group(1))
            new_line = int(match.group(2))
            continue
        if line.startswith("---") or line.startswith("+++"):
            continue
        if line.startswith("-"):
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
    summary_parts = []
    for line in removed[:2]:
        summary_parts.append("-" + line.strip())
    for line in added[:2]:
        summary_parts.append("+" + line.strip())
    summary = " | ".join(summary_parts) if summary_parts else output.splitlines()[0] if output else ""
    return old_line, new_line, removed, added, summary


def enclosing_function(source: Path, line_no: int) -> str:
    if line_no <= 0:
        return ""
    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return ""
    keywords = {"if", "for", "while", "switch", "return", "sizeof"}
    for idx in range(min(line_no - 1, len(lines) - 1), -1, -1):
        stripped = lines[idx].strip()
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)$", stripped)
        if match and match.group(1) not in keywords:
            return match.group(1)
    return ""


def nonblank(lines: Sequence[str]) -> list[str]:
    return [line.strip() for line in lines if line.strip()]


def only_added_break(removed: Sequence[str], added: Sequence[str]) -> bool:
    return not nonblank(removed) and nonblank(added) == ["break;"]


def line_mentions_return_before(source: Path, line_no: int) -> bool:
    if line_no <= 1:
        return False
    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return False
    for idx in range(min(line_no - 2, len(lines) - 1), max(-1, line_no - 8), -1):
        stripped = lines[idx].strip()
        if not stripped:
            continue
        return stripped.startswith("return ") or stripped == "return;"
    return False


def line_before_first_case(source: Path, line_no: int) -> bool:
    if line_no <= 0:
        return False
    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return False
    switch_seen = False
    for idx in range(min(line_no - 1, len(lines) - 1), -1, -1):
        stripped = lines[idx].strip()
        if stripped.startswith("case ") or stripped.startswith("default:"):
            return False
        if stripped.startswith("switch"):
            switch_seen = True
            break
    return switch_seen


def joined_change(removed: Sequence[str], added: Sequence[str]) -> tuple[str, str]:
    return " ".join(nonblank(removed)), " ".join(nonblank(added))


def classify_survivor(
    source: Path,
    mutant: Path,
    result: str,
    equiv: dict[tuple[str, str], str],
) -> tuple[str, str, str, str, int, int, str, str]:
    old_line, new_line, removed, added, summary = mutant_diff(source, mutant)
    function = enclosing_function(source, old_line)
    reason = equiv_reason(equiv, source, mutant)
    if reason:
        return (
            "ledger_equivalent",
            "exact",
            "already listed in the equivalence ledger",
            reason,
            old_line,
            new_line,
            function,
            summary,
        )

    reason = lexical_whitespace_equiv(source, mutant)
    if reason:
        return (
            "lexical_equivalent",
            "exact",
            "review not required unless this source has whitespace-sensitive generated text",
            reason,
            old_line,
            new_line,
            function,
            summary,
        )

    old_text, new_text = joined_change(removed, added)
    if result == "timeout":
        return (
            "timeout",
            "needs_recheck",
            "rerun with a focused gate or classify the timeout cause",
            "",
            old_line,
            new_line,
            function,
            summary,
        )

    if only_added_break(removed, added):
        if line_mentions_return_before(source, old_line):
            return (
                "equivalent_candidate",
                "high",
                "review, then add exact ledger entry if the break is unreachable after return",
                "break after return appears unreachable",
                old_line,
                new_line,
                function,
                summary,
            )
        if line_before_first_case(source, old_line):
            return (
                "equivalent_candidate",
                "high",
                "review, then add exact ledger entry if switch dispatch skips the break",
                "break before first switch case appears unreachable",
                old_line,
                new_line,
                function,
                summary,
            )

    if re.search(r"/\*\s*free\([^)]*\);\s*\*/", new_text) and "free(" in old_text:
        return (
            "leak_only_candidate",
            "medium",
            "review whether this gate has leak detection; otherwise ledger as gate-limited leak-only",
            "free call removed without changing normal output",
            old_line,
            new_line,
            function,
            summary,
        )

    truthy_patterns = (
        ("= 1", "= -1"),
        ("= 1", "= (1+1)"),
        (", 1", ", -1"),
        (", 1", ", (1+1)"),
    )
    if any(old in old_text and new in new_text for old, new in truthy_patterns):
        return (
            "equivalent_candidate",
            "medium",
            "review truthiness-only use, then add exact ledger entry or strengthen test",
            "truthy flag changed to another truthy value",
            old_line,
            new_line,
            function,
            summary,
        )

    if (
        ("== nil" in old_text and "<= nil" in new_text)
        or ("!= nil" in old_text and "> nil" in new_text)
    ):
        return (
            "equivalent_candidate",
            "medium",
            "review pointer domain, then add exact ledger entry or boundary test",
            "nil guard changed to equivalent pointer-domain comparison candidate",
            old_line,
            new_line,
            function,
            summary,
        )

    if re.search(r"\+\s*\(\d+\+1\)", new_text) or re.search(r"\+\s*\(\d+-1\)", new_text):
        return (
            "equivalent_candidate",
            "medium",
            "review allocation slack; add exact ledger entry only if output is unchanged for all inputs",
            "allocation size changed by one byte",
            old_line,
            new_line,
            function,
            summary,
        )

    if re.match(r"^(char|int|long|Type|TypeList)\b", old_text) and re.match(r"^(char|int|long|Type|TypeList)\b", new_text):
        return (
            "equivalent_candidate",
            "low",
            "review declaration-only change, then add exact ledger entry if generated behavior is unchanged",
            "local declaration change candidate",
            old_line,
            new_line,
            function,
            summary,
        )

    return (
        "test_gap",
        "high",
        "add or strengthen a focused test, then recheck this mutant",
        "",
        old_line,
        new_line,
        function,
        summary,
    )


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

    mutants = skip_through_mutant(mutants, getattr(args, "start_after", None))
    mutants = filter_mutants(mutants, getattr(args, "only_mutant", None))
    selected = pick_mutants(mutants, effective_limit(args), args.seed)
    if not selected:
        raise SystemExit("o9um: no mutants selected")

    report, completed, counts = prepare_stream_report(args, source)
    selected_total = len(selected)
    if completed:
        selected = [mutant for mutant in selected if mutant.name not in completed]

    print(f"o9um: source {source}", flush=True)
    if completed:
        print(
            f"o9um: selected {selected_total} of {len(mutants)} mutants "
            f"({len(completed)} already reported, {len(selected)} remaining)",
            flush=True,
        )
    else:
        print(f"o9um: selected {len(selected)} of {len(mutants)} mutants", flush=True)

    if check_baseline:
        base_code, base_output, base_seconds = run_verification(args, source, None)
        if not command_passed(base_code, base_output, args.status_marker):
            base_log = ARTIFACT_DIR / f"o9um_baseline_{safe_name(source)}.log"
            ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
            base_log.write_text(base_output, encoding="utf-8")
            raise SystemExit(f"o9um: baseline command failed; see {base_log}")
        print(f"o9um: baseline passed in {base_seconds:.2f}s", flush=True)

    if args.synthetic_ramfs:
        for mutant in selected:
            reason = preclassified_equiv_reason(args, source, mutant)
            if reason:
                code = 0
                seconds = 0.0
                result = "equivalent"
            else:
                code, output, seconds, result = run_mutant_verification(args, source, mutant)
                reason = ""
                if result == "survived":
                    reason = equiv_reason(equiv, source, mutant) or ""
                    if reason:
                        result = "equivalent"
            counts[result] += 1
            append_row(report, (mutant.name, result, "timeout" if result == "timeout" else code, f"{seconds:.2f}", reason))
            print(f"o9um: {mutant.name}: {result} ({seconds:.2f}s)", flush=True)
            if result == "survived" and args.stop_on_survive:
                break
    else:
        original = source.read_bytes()
        try:
            for mutant in selected:
                reason = preclassified_equiv_reason(args, source, mutant)
                if reason:
                    code = 0
                    seconds = 0.0
                    result = "equivalent"
                else:
                    source.write_bytes(mutant.read_bytes())
                    remove_generated_dependents(source)
                    code, output, seconds, result = run_mutant_verification(args, source, mutant)
                    reason = ""
                    if result == "survived":
                        reason = equiv_reason(equiv, source, mutant) or ""
                    if reason:
                        result = "equivalent"
                counts[result] += 1
                append_row(report, (mutant.name, result, "timeout" if result == "timeout" else code, f"{seconds:.2f}", reason))
                print(f"o9um: {mutant.name}: {result} ({seconds:.2f}s)", flush=True)
                if result == "survived" and args.stop_on_survive:
                    break
        finally:
            source.write_bytes(original)
            remove_generated_dependents(source)

    print(
        "o9um: killed={killed} survived={survived} timeout={timeout} "
        "equivalent={equivalent} report={report}".format(
            report=report, **counts
        ),
        flush=True,
    )
    return counts, selected_total


def cmd_run(args: argparse.Namespace) -> int:
    source = Path(args.source)
    mutant_dir = Path(args.mutant_dir) if args.mutant_dir else Path(
        tempfile.mkdtemp(prefix=f"o9um.{safe_name(source)}.")
    )
    counts, _ = evaluate_source(args, source, mutant_dir, check_baseline=not args.skip_baseline)
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
        source_args = argparse.Namespace(**vars(args))
        source_args.report_out = None
        source_args.resume_report = None
        if getattr(args, "resume_reports", False):
            source_args.resume_report = str(ARTIFACT_DIR / f"o9um_{safe_name(source)}.tsv")
        counts, selected = evaluate_source(source_args, source, mutant_dir, check_baseline=False)
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
    report = Path(args.report_out) if args.report_out else ARTIFACT_DIR / f"o9um_batch_{args.target_set}.tsv"
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


def triage_rows_for_source(
    source: Path,
    mutant_dir: Path,
    report_rows: Sequence[dict[str, str]],
    equiv: dict[tuple[str, str], str],
) -> tuple[list[Sequence[object]], dict[str, int]]:
    out_rows: list[Sequence[object]] = []
    counts: dict[str, int] = {}
    for row in report_rows:
        result = row.get("result", "")
        if result not in {"survived", "timeout"}:
            continue
        mutant_name = row.get("mutant", "")
        mutant = mutant_dir / mutant_name
        if not mutant_name or not mutant.exists():
            triage_class = "unknown"
            confidence = "missing"
            suggested = f"mutant file not found under {mutant_dir}"
            reason = ""
            old_line = new_line = 0
            function = ""
            summary = ""
        else:
            (
                triage_class,
                confidence,
                suggested,
                reason,
                old_line,
                new_line,
                function,
                summary,
            ) = classify_survivor(source, mutant, result, equiv)
        counts[triage_class] = counts.get(triage_class, 0) + 1
        out_rows.append((
            clean_cell(source),
            clean_cell(mutant_name),
            clean_cell(result),
            clean_cell(function),
            old_line,
            new_line,
            clean_cell(triage_class),
            clean_cell(confidence),
            clean_cell(suggested),
            clean_cell(reason),
            clean_cell(summary),
        ))
    return out_rows, counts


def triage_failed(counts: dict[str, int]) -> bool:
    return any(counts.get(name, 0) for name in TRIAGE_FAILURE_CLASSES)


def triage_summary(counts: dict[str, int]) -> str:
    if not counts:
        return "no_survivors=0"
    return " ".join(f"{key}={counts[key]}" for key in sorted(counts))


def cmd_triage(args: argparse.Namespace) -> int:
    source = Path(args.source)
    mutant_dir = Path(args.mutant_dir)
    report = Path(args.report) if args.report else ARTIFACT_DIR / f"o9um_{safe_name(source)}.tsv"
    output = Path(args.output) if args.output else ARTIFACT_DIR / f"o9um_{safe_name(source)}.triage.tsv"
    equiv = load_equiv(Path(args.equiv_file) if args.equiv_file else None)

    rows = read_tsv(report)
    if not rows:
        raise SystemExit(f"o9um: no report rows found in {report}")

    triage_rows, counts = triage_rows_for_source(source, mutant_dir, rows, equiv)
    out_rows: list[Sequence[object]] = [TRIAGE_HEADER]
    out_rows.extend(triage_rows)

    write_rows(output, out_rows)
    print(f"o9um: triage report={output} {triage_summary(counts)}", flush=True)
    return 1 if triage_failed(counts) else 0


def cmd_triage_batch(args: argparse.Namespace) -> int:
    sources = target_sources(args.target_set)
    if args.source:
        sources.extend(Path(s) for s in args.source)

    root = Path(args.mutant_root)
    report_dir = Path(args.report_dir) if args.report_dir else ARTIFACT_DIR
    output = Path(args.output) if args.output else ARTIFACT_DIR / f"o9um_batch_{args.target_set}.triage.tsv"
    equiv = load_equiv(Path(args.equiv_file) if args.equiv_file else None)

    out_rows: list[Sequence[object]] = [TRIAGE_HEADER]
    total_counts: dict[str, int] = {}
    for source in sources:
        report = report_dir / f"o9um_{safe_name(source)}.tsv"
        rows = read_tsv(report)
        if not rows:
            total_counts["missing_report"] = total_counts.get("missing_report", 0) + 1
            out_rows.append((
                clean_cell(source),
                "",
                "",
                "",
                0,
                0,
                "missing_report",
                "missing",
                clean_cell(f"run the campaign or pass --report-dir; expected {report}"),
                "no streamed report rows found",
                "",
            ))
            continue
        triage_rows, counts = triage_rows_for_source(
            source,
            root / safe_name(source),
            rows,
            equiv,
        )
        out_rows.extend(triage_rows)
        for key, value in counts.items():
            total_counts[key] = total_counts.get(key, 0) + value

    write_rows(output, out_rows)
    print(f"o9um: triage-batch report={output} {triage_summary(total_counts)}", flush=True)
    return 1 if triage_failed(total_counts) else 0


def filter_values(raw: Sequence[str] | None, default: Sequence[str] | None = None) -> set[str]:
    values: set[str] = set()
    for item in raw or []:
        values.update(part for part in item.split(",") if part)
    if not values and default is not None:
        values.update(default)
    return values


def cmd_recheck(args: argparse.Namespace) -> int:
    triage = Path(args.triage)
    rows = read_tsv(triage)
    if not rows:
        raise SystemExit(f"o9um: no triage rows found in {triage}")

    class_filter = filter_values(args.class_filter)
    result_filter = filter_values(args.result_filter, ("survived", "timeout"))
    selected_by_source: dict[Path, list[str]] = {}
    for row in rows:
        source_text = row.get("source", "")
        mutant = row.get("mutant", "")
        if not source_text or not mutant:
            continue
        source = Path(source_text)
        if args.source and str(source) != args.source:
            continue
        if result_filter and row.get("result", "") not in result_filter:
            continue
        if class_filter and row.get("triage_class", "") not in class_filter:
            continue
        selected_by_source.setdefault(source, []).append(mutant)

    if not selected_by_source:
        raise SystemExit("o9um: triage filters selected no mutants")
    if args.mutant_dir and len(selected_by_source) > 1:
        raise SystemExit("o9um: --mutant-dir can only be used when triage selects one source")
    if args.report_out and len(selected_by_source) > 1:
        raise SystemExit("o9um: --report-out can only be used when triage selects one source")

    total = {"killed": 0, "survived": 0, "timeout": 0, "equivalent": 0}
    for source, mutants in selected_by_source.items():
        mutant_dir = Path(args.mutant_dir) if args.mutant_dir else Path(args.mutant_root) / safe_name(source)
        recheck_args = argparse.Namespace(**vars(args))
        recheck_args.clean = False
        recheck_args.only_mutant = mutants
        recheck_args.start_after = None
        recheck_args.limit = None
        recheck_args.seed = None
        recheck_args.resume_report = None
        if args.report_out:
            recheck_args.report_out = args.report_out
        else:
            recheck_args.report_out = str(ARTIFACT_DIR / f"o9um_{safe_name(source)}.recheck.tsv")
        counts, _ = evaluate_source(
            recheck_args,
            source,
            mutant_dir,
            check_baseline=not args.skip_baseline,
        )
        for key in total:
            total[key] += counts[key]

    fail_on = filter_values([args.fail_on], ("survived", "timeout"))
    print(
        "o9um: recheck killed={killed} survived={survived} timeout={timeout} "
        "equivalent={equivalent}".format(**total),
        flush=True,
    )
    return 1 if any(total.get(result, 0) for result in fail_on) else 0


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
    p.add_argument("--only-mutant", action="append", default=[],
        help="run only matching mutant basename/path/glob; may be repeated or comma-separated")
    p.add_argument("--start-after", default=None,
        help="resume selection after this mutant basename/path")
    p.add_argument("--swap", action="store_true", help="enable adjacent-line swap mutants")
    p.add_argument("--mutate-in-strings", action="store_true", help="allow mutations inside strings")
    p.add_argument("--generate-timeout", type=float, default=None)
    p.add_argument("--synthetic-ramfs", action="store_true",
        help="run each mutant in a private 9front ramfs worktree; --cmd must contain {script}")
    p.add_argument("--plan9-repo", default=DEFAULT_PLAN9_REPO,
        help="Plan 9 path to the real checkout used as ramfs input")
    p.add_argument("--plan9-tmp", default="/tmp",
        help="Plan 9 writable directory used for synthetic ramfs mount points")
    p.add_argument("--gate-rc", default=None,
        help="rc snippet run from inside the synthetic ramfs worktree")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.add_argument("--classify-whitespace-equivalent", action="store_true",
        help="preclassify lexical whitespace/comment-only source mutants as equivalent")
    p.add_argument("--report-out", default=None,
        help="write the streamed per-mutant report to this path")
    p.add_argument("--resume-report", default=None,
        help="append to this streamed report and skip mutants already present in it")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Universal Mutator wrapper for objective-9c")
    sub = parser.add_subparsers(dest="cmdname", required=True)

    p = sub.add_parser("generate", help="generate mutants only")
    add_common(p)
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("run", help="generate/stage mutants and run a verification command")
    add_common(p)
    p.add_argument("--limit", type=int, default=10, help="number of mutants to run")
    p.add_argument("--exhaustive", action="store_true",
        help="run every selected mutant; ignores --limit")
    p.add_argument("--seed", type=int, default=None, help="shuffle mutants with this seed before limiting")
    p.add_argument("--timeout", type=float, default=None, help="timeout per verification command")
    p.add_argument("--timeout-exit-code", action="append", default=[],
        help="verification exit code to report as timeout; may be repeated or comma-separated")
    p.add_argument("--status-marker", default=None, help="line marker: '<marker> pass' or '<marker> fail'")
    p.add_argument("--stop-on-survive", action="store_true")
    p.add_argument("--skip-baseline", action="store_true", help="skip baseline verification for resumed runs")
    p.add_argument("--pre-gate-rc", default=None,
        help="rc snippet to run before --gate-rc; non-pass kills before the main gate")
    p.add_argument("--pre-cmd", default=None,
        help="verification command for --pre-gate-rc; defaults to --cmd")
    p.add_argument("--pre-timeout", type=float, default=None,
        help="timeout for --pre-cmd; defaults to --timeout")
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
    p.add_argument("--only-mutant", action="append", default=[],
        help="run only matching mutant basename/path/glob; may be repeated or comma-separated")
    p.add_argument("--start-after", default=None,
        help="resume selection after this mutant basename/path")
    p.add_argument("--swap", action="store_true", help="enable adjacent-line swap mutants")
    p.add_argument("--mutate-in-strings", action="store_true", help="allow mutations inside strings")
    p.add_argument("--generate-timeout", type=float, default=None)
    p.add_argument("--synthetic-ramfs", action="store_true",
        help="run each mutant in a private 9front ramfs worktree; --cmd must contain {script}")
    p.add_argument("--plan9-repo", default=DEFAULT_PLAN9_REPO,
        help="Plan 9 path to the real checkout used as ramfs input")
    p.add_argument("--plan9-tmp", default="/tmp",
        help="Plan 9 writable directory used for synthetic ramfs mount points")
    p.add_argument("--gate-rc", default=None,
        help="rc snippet run from inside the synthetic ramfs worktree")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.add_argument("--classify-whitespace-equivalent", action="store_true",
        help="preclassify lexical whitespace/comment-only source mutants as equivalent")
    p.add_argument("--report-out", default=None,
        help="write the batch summary report to this path")
    p.add_argument("--resume-reports", action="store_true",
        help="append to existing per-source streamed reports and skip mutants already reported there")
    p.add_argument("--limit", type=int, default=5, help="number of mutants to run per source")
    p.add_argument("--exhaustive", action="store_true",
        help="run every selected mutant per source; ignores --limit")
    p.add_argument("--seed", type=int, default=None, help="shuffle mutants with this seed before limiting")
    p.add_argument("--timeout", type=float, default=None, help="timeout per verification command")
    p.add_argument("--timeout-exit-code", action="append", default=[],
        help="verification exit code to report as timeout; may be repeated or comma-separated")
    p.add_argument("--status-marker", default=None, help="line marker: '<marker> pass' or '<marker> fail'")
    p.add_argument("--stop-on-survive", action="store_true")
    p.add_argument("--pre-gate-rc", default=None,
        help="rc snippet to run before --gate-rc; non-pass kills before the main gate")
    p.add_argument("--pre-cmd", default=None,
        help="verification command for --pre-gate-rc; defaults to --cmd")
    p.add_argument("--pre-timeout", type=float, default=None,
        help="timeout for --pre-cmd; defaults to --timeout")
    p.add_argument("--cmd", required=True, help="verification command; nonzero means mutant killed")
    p.set_defaults(func=cmd_batch)

    p = sub.add_parser("triage", help="classify survived/timeout mutants from a streamed report")
    p.add_argument("--source", required=True, help="source file used for the mutation campaign")
    p.add_argument("--mutant-dir", required=True, help="directory containing generated mutants")
    p.add_argument("--report", default=None, help="streamed mutant report; defaults to the source report")
    p.add_argument("--output", default=None, help="triage TSV output path")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.set_defaults(func=cmd_triage)

    p = sub.add_parser("triage-batch", help="classify survived/timeout mutants across a target set")
    p.add_argument("--target-set", choices=sorted(TARGET_SETS), default="compiler")
    p.add_argument("--source", action="append", default=[], help="extra source file to include")
    p.add_argument("--mutant-root", default="/tmp/o9um-batch",
        help="root directory containing per-source mutant dirs")
    p.add_argument("--report-dir", default=None,
        help="directory containing streamed per-source reports; defaults to o9c/test/artifacts")
    p.add_argument("--output", default=None, help="combined triage TSV output path")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.set_defaults(func=cmd_triage_batch)

    p = sub.add_parser("recheck", help="rerun selected mutants from a triage report")
    p.add_argument("--triage", required=True, help="triage TSV produced by 'o9um.py triage'")
    p.add_argument("--source", default=None, help="limit recheck to this source path")
    p.add_argument("--mutant-dir", default=None, help="directory containing mutants for a single selected source")
    p.add_argument("--mutant-root", default="/tmp/o9um-batch",
        help="root directory containing per-source mutant dirs")
    p.add_argument("--class", dest="class_filter", action="append", default=[],
        help="triage class to recheck; may be repeated or comma-separated")
    p.add_argument("--result", dest="result_filter", action="append", default=[],
        help="original result to recheck; defaults to survived,timeout")
    p.add_argument("--fail-on", default="survived,timeout",
        help="comma-separated recheck results that produce a nonzero exit")
    p.add_argument("--language", default=None, help="force Universal Mutator language/rules name")
    p.add_argument("--mutate", default=None, help="path to mutate executable")
    p.add_argument("--only-rule", default=None, help="pass --only to mutate if mutants must be generated")
    p.add_argument("--swap", action="store_true", help="enable adjacent-line swap mutants if generation is needed")
    p.add_argument("--mutate-in-strings", action="store_true",
        help="allow mutations inside strings if generation is needed")
    p.add_argument("--generate-timeout", type=float, default=None)
    p.add_argument("--synthetic-ramfs", action="store_true",
        help="run each mutant in a private 9front ramfs worktree; --cmd must contain {script}")
    p.add_argument("--plan9-repo", default=DEFAULT_PLAN9_REPO,
        help="Plan 9 path to the real checkout used as ramfs input")
    p.add_argument("--plan9-tmp", default="/tmp",
        help="Plan 9 writable directory used for synthetic ramfs mount points")
    p.add_argument("--gate-rc", default=None,
        help="rc snippet run from inside the synthetic ramfs worktree")
    p.add_argument("--equiv-file", default=str(DEFAULT_EQUIV_FILE),
        help="TSV of exact source/mutant pairs classified as equivalent")
    p.add_argument("--classify-whitespace-equivalent", action="store_true",
        help="preclassify lexical whitespace/comment-only source mutants as equivalent")
    p.add_argument("--report-out", default=None, help="write the streamed recheck report to this path")
    p.add_argument("--skip-baseline", action="store_true", help="skip baseline verification")
    p.add_argument("--timeout", type=float, default=None, help="timeout per verification command")
    p.add_argument("--timeout-exit-code", action="append", default=[],
        help="verification exit code to report as timeout; may be repeated or comma-separated")
    p.add_argument("--status-marker", default=None, help="line marker: '<marker> pass' or '<marker> fail'")
    p.add_argument("--stop-on-survive", action="store_true")
    p.add_argument("--pre-gate-rc", default=None,
        help="rc snippet to run before --gate-rc; non-pass kills before the main gate")
    p.add_argument("--pre-cmd", default=None,
        help="verification command for --pre-gate-rc; defaults to --cmd")
    p.add_argument("--pre-timeout", type=float, default=None,
        help="timeout for --pre-cmd; defaults to --timeout")
    p.add_argument("--cmd", required=True, help="verification command; nonzero means mutant killed")
    p.set_defaults(func=cmd_recheck)

    p = sub.add_parser("list-targets", help="list built-in mutation target sets")
    p.set_defaults(func=cmd_list_targets)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
