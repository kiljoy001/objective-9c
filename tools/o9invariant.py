#!/usr/bin/env python3
"""Registry-driven invariant mutation dashboard for o9.

The registry maps semantic invariants to checked-in tests, named mutants, and
focused gates.  A semantic mutant is acceptable only when its assigned gate
passes without mutation and then fails or times out with the mutant applied.
"""

from __future__ import annotations

import argparse
import dataclasses
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Sequence

import o9mutate


REPO = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY = REPO / "o9c/test/invariants.tab"


@dataclasses.dataclass(frozen=True)
class Invariant:
    ident: str
    area: str
    rule: str
    behavior: str
    tests: tuple[str, ...]
    mutants: tuple[str, ...]
    gate: str
    timeout: float | None


@dataclasses.dataclass(frozen=True)
class CommandResult:
    code: int | None
    output: str
    timed_out: bool


def split_csv(value: str) -> tuple[str, ...]:
    if value == "" or value == "-":
        return ()
    return tuple(part.strip() for part in value.split(",") if part.strip())


def parse_timeout(value: str | None) -> float | None:
    if value is None or value == "" or value == "-":
        return None
    return float(value)


def parse_registry(path: Path) -> list[Invariant]:
    rows: list[Invariant] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields: dict[str, str] = {}
        for token in shlex.split(line, comments=True, posix=True):
            if "=" not in token:
                raise SystemExit(f"{path}:{lineno}: expected key=value, got {token!r}")
            key, value = token.split("=", 1)
            fields[key] = value
        required = ("id", "area", "rule", "behavior", "tests", "mutants", "gate")
        missing = [key for key in required if key not in fields]
        if missing:
            raise SystemExit(f"{path}:{lineno}: missing required field(s): {', '.join(missing)}")
        rows.append(
            Invariant(
                ident=fields["id"],
                area=fields["area"],
                rule=fields["rule"],
                behavior=fields["behavior"],
                tests=split_csv(fields["tests"]),
                mutants=split_csv(fields["mutants"]),
                gate=fields["gate"],
                timeout=parse_timeout(fields.get("timeout")),
            )
        )
    return rows


def mutant_map() -> dict[str, o9mutate.Mutant]:
    return {mutant.name: mutant for mutant in o9mutate.MUTANTS}


def gate_command(gate: str) -> str:
    if gate == "ast-test":
        return "mk ast-test"
    if gate == "run-test":
        return "mk run-test"
    if gate.startswith("run-test:"):
        cases = " ".join(shlex.quote(case) for case in split_csv(gate.split(":", 1)[1]))
        return f"mk o9c libo9.a; rc ./o9c/test/run_e2e.rc {cases}"
    if gate == "function-object-contract-test":
        return "mk function-object-contract-test"
    if gate == "verify":
        return "mk verify"
    return "mk " + shlex.quote(gate)


def apply_cmd_template(template: str | None, gate: str) -> str:
    command = gate_command(gate)
    if template is None:
        return command
    if "{gate}" not in template:
        raise SystemExit("--cmd-template must contain {gate}")
    return template.replace("{gate}", command)


def run_shell(command: str, timeout: float | None) -> CommandResult:
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=REPO,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        return CommandResult(result.returncode, (result.stdout or "") + (result.stderr or ""), False)
    except subprocess.TimeoutExpired as exc:
        output = ""
        if exc.stdout:
            output += exc.stdout if isinstance(exc.stdout, str) else exc.stdout.decode("utf-8", "replace")
        if exc.stderr:
            output += exc.stderr if isinstance(exc.stderr, str) else exc.stderr.decode("utf-8", "replace")
        return CommandResult(None, output, True)


def marker_status(marker: str | None, output: str) -> str | None:
    if marker is None:
        return None
    status = None
    for line in output.splitlines():
        if line.startswith(marker):
            parts = line.split()
            if len(parts) >= 2:
                status = parts[1]
    return status


def command_passed(result: CommandResult, marker: str | None) -> bool:
    if result.timed_out:
        return False
    status = marker_status(marker, result.output)
    if status == "pass":
        return True
    if status == "fail":
        return False
    return result.code == 0


def present_tests(tests: Iterable[str]) -> tuple[tuple[str, ...], tuple[str, ...]]:
    present: list[str] = []
    missing: list[str] = []
    for test in tests:
        path = REPO / test
        if path.exists():
            present.append(test)
        else:
            missing.append(test)
    return tuple(present), tuple(missing)


def mutation_status(
    mutant: o9mutate.Mutant,
    command: str,
    timeout: float | None,
    marker: str | None,
) -> tuple[str, str]:
    target = mutant.target
    with o9mutate.mutation_lock():
        sources = o9mutate.load_sources(target)
        try:
            try:
                o9mutate.apply_mutant(sources, mutant)
            except Exception as exc:  # noqa: BLE001 - setup error should be reported, not hidden.
                return "setup_error", str(exc)
            result = run_shell(command, timeout)
        finally:
            o9mutate.restore_sources(sources)
            o9mutate.remove_generated_grammar(target)

    if result.timed_out:
        return "timeout", result.output
    if command_passed(result, marker):
        return "survived", result.output
    return "killed", result.output


def row_selected(row: Invariant, only: set[str]) -> bool:
    if not only:
        return True
    return row.ident in only or row.area in only or any(mutant in only for mutant in row.mutants)


def print_output(label: str, output: str, show_output: bool) -> None:
    if not show_output or not output:
        return
    print(f"--- {label} output ---")
    print(output, end="" if output.endswith("\n") else "\n")


def run_dashboard(args: argparse.Namespace) -> int:
    rows = [row for row in parse_registry(Path(args.registry)) if row_selected(row, set(args.only))]
    mutants = mutant_map()
    baseline: dict[str, tuple[str, str]] = {}
    failed = False
    killed = survived = timed_out = setup_error = 0

    print("id\tarea\tgate\ttests\tmutant\tstatus\tresult", flush=True)
    for row in rows:
        present, missing_tests = present_tests(row.tests)
        missing_mutants = tuple(name for name in row.mutants if name not in mutants)
        tests_status = "present" if not missing_tests else "missing:" + ",".join(missing_tests)

        if missing_tests or missing_mutants:
            failed = True
            mutant_label = ",".join(missing_mutants) if missing_mutants else "-"
            print(f"{row.ident}\t{row.area}\t{row.gate}\t{tests_status}\t{mutant_label}\tmissing\tfail", flush=True)
            continue

        command = apply_cmd_template(args.cmd_template, row.gate)
        timeout = args.timeout if args.timeout is not None else row.timeout

        if not args.skip_baseline and row.gate not in baseline:
            result = run_shell(command, timeout)
            if result.timed_out:
                baseline[row.gate] = ("timeout", result.output)
            elif command_passed(result, args.status_marker):
                baseline[row.gate] = ("pass", result.output)
            else:
                baseline[row.gate] = ("fail", result.output)
            print_output(f"baseline {row.gate}", result.output, args.show_output)

        bstatus, boutput = baseline.get(row.gate, ("pass", ""))
        if bstatus != "pass":
            failed = True
            print_output(f"baseline {row.gate}", boutput, True)
            for name in row.mutants:
                print(f"{row.ident}\t{row.area}\t{row.gate}\t{tests_status}\t{name}\tbaseline_{bstatus}\tfail", flush=True)
            if not args.keep_going:
                break
            continue

        for name in row.mutants:
            status, output = mutation_status(mutants[name], command, timeout, args.status_marker)
            if status == "survived":
                survived += 1
                failed = True
                result = "fail"
            elif status == "setup_error":
                setup_error += 1
                failed = True
                result = "fail"
            elif status == "timeout":
                timed_out += 1
                result = "pass"
            else:
                killed += 1
                result = "pass"
            print_output(f"{row.ident} {name}", output, args.show_output or status in {"survived", "setup_error"})
            print(f"{row.ident}\t{row.area}\t{row.gate}\t{tests_status}\t{name}\t{status}\t{result}", flush=True)
            if result == "fail" and not args.keep_going:
                print(
                    f"summary\tinvariants={len(rows)} killed={killed} timeout={timed_out} "
                    f"survived={survived} setup_error={setup_error}",
                    flush=True,
                )
                return 1

    print(
        f"summary\tinvariants={len(rows)} killed={killed} timeout={timed_out} "
        f"survived={survived} setup_error={setup_error}",
        flush=True,
    )
    return 1 if failed else 0


def list_rows(args: argparse.Namespace) -> int:
    for row in parse_registry(Path(args.registry)):
        print(f"{row.ident}\t{row.area}\t{row.gate}\t{','.join(row.mutants)}\t{row.rule}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    os.chdir(REPO)
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass
    parser = argparse.ArgumentParser(description="Run o9 invariant mutation checks")
    parser.add_argument("--registry", default=str(DEFAULT_REGISTRY))
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="list registered invariants")
    p.set_defaults(func=list_rows)

    p = sub.add_parser("run", help="run invariant mutants against their gates")
    p.add_argument("--only", action="append", default=[], help="invariant id, area, or mutant name")
    p.add_argument("--timeout", type=float, default=None, help="override registry timeouts")
    p.add_argument(
        "--cmd-template",
        default=os.environ.get("O9_INVARIANT_CMD_TEMPLATE"),
        help="wrap each gate command, using {gate}; defaults to O9_INVARIANT_CMD_TEMPLATE",
    )
    p.add_argument(
        "--status-marker",
        default=os.environ.get("O9_INVARIANT_STATUS_MARKER"),
        help="marker line '<marker> pass|fail' in wrapped output; defaults to O9_INVARIANT_STATUS_MARKER",
    )
    p.add_argument("--skip-baseline", action="store_true")
    p.add_argument("--keep-going", action="store_true")
    p.add_argument("--show-output", action="store_true")
    p.set_defaults(func=run_dashboard)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
