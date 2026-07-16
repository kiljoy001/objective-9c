#!/usr/bin/env python3
"""Apply deliberate o9 compiler mutants and require tests to kill them.

This is a host-side harness.  It mutates `o9c/grammar.y`, runs a caller
supplied command, then restores the original file.  A mutant is "killed" when
the command fails.  A command that still succeeds means the mutant survived
and the tests are missing an invariant.
"""

from __future__ import annotations

import argparse
import dataclasses
import subprocess
import sys
from pathlib import Path
from typing import Sequence


@dataclasses.dataclass(frozen=True)
class Mutant:
    name: str
    description: str
    old: str
    new: str
    count: int = 1


MUTANTS = (
    Mutant(
        "ctl_arity",
        "disable generated ctl method arity checks",
        "if(nf - 3 != %d){ char __ab[96];",
        "if(0 && nf - 3 != %d){ char __ab[96];",
    ),
    Mutant(
        "remote_objects",
        "allow near/far/listener declarations on non-Tabula objects",
        "if(!o9_type_is_tabula(e->typeinfo)){\n"
        "            fprint(2, \"o9c: error: line %d: remote objects are not supported; only Tabula data may be declared near/far/listener with @\\n\",\n"
        "                sem_line);\n"
        "            (*errs)++;\n"
        "        }",
        "if(0 && !o9_type_is_tabula(e->typeinfo)){\n"
        "            fprint(2, \"o9c: error: line %d: remote objects are not supported; only Tabula data may be declared near/far/listener with @\\n\",\n"
        "                sem_line);\n"
        "            (*errs)++;\n"
        "        }",
    ),
    Mutant(
        "tabula_ctor_arity",
        "allow malformed Tabula constructor arity",
        "if(got != 1 && got != 2){\n"
        "        fprint(2, \"o9c: error: line %d: Tabula constructor takes 1 path argument or 2 schema arguments, got %d\\n\",",
        "if(0 && got != 1 && got != 2){\n"
        "        fprint(2, \"o9c: error: line %d: Tabula constructor takes 1 path argument or 2 schema arguments, got %d\\n\",",
    ),
    Mutant(
        "send_to_recvonly",
        "allow sends to recv-only channel endpoints",
        "if(!recvop && (m->flags & NFChanRecvOnly)){",
        "if(0 && !recvop && (m->flags & NFChanRecvOnly)){",
    ),
    Mutant(
        "recv_from_sendonly",
        "allow receives from send-only channel endpoints",
        "if(recvop && (m->flags & NFChanSendOnly)){",
        "if(0 && recvop && (m->flags & NFChanSendOnly)){",
    ),
    Mutant(
        "tuple_object_payload",
        "allow object handles inside tuple payloads",
        "if(tuple_field_is_object_handle(a)){",
        "if(0 && tuple_field_is_object_handle(a)){",
    ),
)


def selected_mutants(names: Sequence[str]) -> list[Mutant]:
    if not names:
        return list(MUTANTS)
    by_name = {m.name: m for m in MUTANTS}
    missing = [name for name in names if name not in by_name]
    if missing:
        raise SystemExit(f"unknown mutant(s): {', '.join(missing)}")
    return [by_name[name] for name in names]


def apply_mutant(src: str, mutant: Mutant) -> str:
    got = src.count(mutant.old)
    if got < mutant.count:
        raise RuntimeError(
            f"{mutant.name}: pattern not found enough times "
            f"(wanted {mutant.count}, found {got})"
        )
    return src.replace(mutant.old, mutant.new, mutant.count)


def run_command(args: argparse.Namespace) -> tuple[int | None, str]:
    try:
        result = subprocess.run(
            args.cmd,
            shell=True,
            text=True,
            capture_output=True,
            timeout=args.timeout,
        )
        return result.returncode, (result.stdout or "") + (result.stderr or "")
    except subprocess.TimeoutExpired as exc:
        out = ""
        if exc.stdout:
            out += exc.stdout if isinstance(exc.stdout, str) else exc.stdout.decode("utf-8", "replace")
        if exc.stderr:
            out += exc.stderr if isinstance(exc.stderr, str) else exc.stderr.decode("utf-8", "replace")
        return None, out


def command_survived(args: argparse.Namespace, code: int | None, output: str) -> bool:
    if args.status_marker:
        status = None
        for line in output.splitlines():
            if line.startswith(args.status_marker):
                parts = line.split()
                if len(parts) >= 2:
                    status = parts[1]
        if status == "pass":
            return True
        if status == "fail":
            return False
        print(f"missing status marker {args.status_marker!r}; falling back to exit status", file=sys.stderr)
    return code == 0


def run_mutants(args: argparse.Namespace) -> int:
    path = Path(args.file)
    original = path.read_text(encoding="utf-8")
    failed = False

    for mutant in selected_mutants(args.only):
        print(f"mutant {mutant.name}: {mutant.description}", flush=True)
        try:
            path.write_text(apply_mutant(original, mutant), encoding="utf-8")
            code, output = run_command(args)
        finally:
            path.write_text(original, encoding="utf-8")

        if output:
            print(output, end="" if output.endswith("\n") else "\n")
        if command_survived(args, code, output):
            print(f"mutant {mutant.name}: SURVIVED", file=sys.stderr)
            failed = True
            if not args.keep_going:
                break
        else:
            print(f"mutant {mutant.name}: killed")

    return 1 if failed else 0


def list_mutants(_: argparse.Namespace) -> int:
    for mutant in MUTANTS:
        print(f"{mutant.name}\t{mutant.description}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run o9 compiler mutation checks")
    sub = parser.add_subparsers(dest="cmdname", required=True)

    p = sub.add_parser("list", help="list available mutants")
    p.set_defaults(func=list_mutants)

    p = sub.add_parser("run", help="run mutants against a test command")
    p.add_argument("--file", default="o9c/grammar.y")
    p.add_argument("--only", action="append", default=[])
    p.add_argument("--keep-going", action="store_true")
    p.add_argument("--timeout", type=float, default=None)
    p.add_argument(
        "--status-marker",
        default=None,
        help="optional marker whose last line is '<marker> pass' or '<marker> fail'",
    )
    p.add_argument("--cmd", required=True, help="command that must fail for each mutant")
    p.set_defaults(func=run_mutants)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
