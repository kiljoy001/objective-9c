#!/usr/bin/env python3
"""Run PMD CPD duplicate-code checks for o9-owned sources.

PMD does not have a yacc grammar frontend, and it ignores `.y` files by
extension.  The transpiler's grammar file is mostly C action code, so this
wrapper copies it to a temporary `.c` path and scans it with CPD's C++ lexer.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


CPP_SOURCES = (
    "o9_runtime.c",
    "o9_tab_discard.c",
    "o9_crypto.c",
    "o9.h",
)

PYTHON_SOURCES = ("tools",)


def run_cmd(cmd: Sequence[str]) -> tuple[int, str]:
    result = subprocess.run(
        list(cmd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.returncode, result.stdout or ""


def read_report(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def normalize_report(text: str) -> str:
    text = text.replace("grammar.c", "o9c/grammar.y")
    return re.sub(r"/tmp/o9pmd\.[^/\s]+/o9c/grammar\.y", "o9c/grammar.y", text)


def run_cpd(
    *,
    label: str,
    pmd: str,
    language: str,
    min_tokens: int,
    inputs: Sequence[Path],
    report: Path,
    relativize: Sequence[Path],
    report_only: bool,
) -> int:
    try:
        report.unlink()
    except FileNotFoundError:
        pass

    cmd = [
        pmd,
        "cpd",
        "--language",
        language,
        "--minimum-tokens",
        str(min_tokens),
        "--format",
        "text",
        "--encoding",
        "UTF-8",
        "--report-file",
        str(report),
    ]
    for path in relativize:
        cmd.extend(["--relativize-paths-with", str(path)])
    if report_only:
        cmd.append("--no-fail-on-violation")
    for path in inputs:
        cmd.extend(["--dir", str(path)])

    code, out = run_cmd(cmd)
    text = normalize_report(read_report(report))
    if out.strip():
        print(out, end="" if out.endswith("\n") else "\n")
    if text.strip():
        print(f"o9pmd: {label}: duplicates found")
        print(text, end="" if text.endswith("\n") else "\n")
    elif code == 0:
        print(f"o9pmd: {label}: OK")
    return code


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run PMD CPD checks for o9")
    parser.add_argument("--pmd", default="pmd", help="PMD executable")
    parser.add_argument("--cpp-min-tokens", type=int, default=220)
    parser.add_argument("--python-min-tokens", type=int, default=80)
    parser.add_argument("--report-dir", default="o9c/test/artifacts")
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="print duplicate reports but do not fail on violations",
    )
    args = parser.parse_args(argv)

    if shutil.which(args.pmd) is None:
        print(f"o9pmd: missing PMD executable: {args.pmd}", file=sys.stderr)
        return 127

    root = Path.cwd()
    report_dir = Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="o9pmd.") as tmpname:
        tmp = Path(tmpname)
        grammar_copy = tmp / "grammar.c"
        shutil.copyfile(root / "o9c" / "grammar.y", grammar_copy)

        failures = 0
        failures += run_cpd(
            label="cpp",
            pmd=args.pmd,
            language="cpp",
            min_tokens=args.cpp_min_tokens,
            inputs=[grammar_copy, *(root / p for p in CPP_SOURCES)],
            report=report_dir / "o9pmd_cpp.txt",
            relativize=[root, tmp],
            report_only=args.report_only,
        )
        failures += run_cpd(
            label="python",
            pmd=args.pmd,
            language="python",
            min_tokens=args.python_min_tokens,
            inputs=[root / p for p in PYTHON_SOURCES],
            report=report_dir / "o9pmd_python.txt",
            relativize=[root],
            report_only=args.report_only,
        )

    if args.report_only:
        return 0
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
