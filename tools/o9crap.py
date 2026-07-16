#!/usr/bin/env python3
"""CRAP scoring support for the o9 transpiler.

This tool does two jobs:

1. instrument a generated o9c/y.tab.c so a 9front test run can collect real
   function/block hit counts from the transpiler; and
2. combine those counts with cyclomatic complexity into CRAP scores.

Coverage here is block coverage, not gcov line coverage: every function entry
and every brace-delimited control block gets a counter. That is deliberate.
It avoids rewriting unbraced C statements and keeps the instrumented Plan 9 C
semantics stable enough to trust the ranking.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Tuple


KEYWORDS = {
    "if",
    "for",
    "while",
    "switch",
    "return",
    "sizeof",
    "case",
    "do",
    "else",
}


@dataclass
class Point:
    pid: int
    function: str
    line: int
    kind: str
    offset: int


@dataclass
class Function:
    name: str
    line: int
    start: int
    body_start: int
    end: int
    complexity: int
    points: List[Point] = field(default_factory=list)


def line_at(src: str, off: int) -> int:
    return src.count("\n", 0, off) + 1


def previous_token(src: str, off: int) -> str:
    i = off - 1
    while i >= 0 and src[i].isspace():
        i -= 1
    j = i
    while j >= 0 and (src[j].isalnum() or src[j] == "_"):
        j -= 1
    return src[j + 1 : i + 1]


def previous_nonspace(src: str, off: int) -> str:
    i = off - 1
    while i >= 0 and src[i].isspace():
        i -= 1
    return src[i] if i >= 0 else ""


def sanitize_c(src: str) -> str:
    """Replace strings/comments/chars with spaces while preserving length."""
    out = list(src)
    i = 0
    n = len(src)
    state = "code"
    while i < n:
        c = src[i]
        if state == "code":
            if c == "/" and i + 1 < n and src[i + 1] == "/":
                out[i] = out[i + 1] = " "
                i += 2
                state = "line"
                continue
            if c == "/" and i + 1 < n and src[i + 1] == "*":
                out[i] = out[i + 1] = " "
                i += 2
                state = "block"
                continue
            if c == '"':
                out[i] = " "
                i += 1
                state = "string"
                continue
            if c == "'":
                out[i] = " "
                i += 1
                state = "char"
                continue
        elif state == "line":
            if c == "\n":
                state = "code"
            else:
                out[i] = " "
        elif state == "block":
            out[i] = " "
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                out[i + 1] = " "
                i += 2
                state = "code"
                continue
        elif state == "string":
            out[i] = " "
            if c == "\\":
                if i + 1 < n:
                    out[i + 1] = " "
                    i += 2
                    continue
            if c == '"':
                state = "code"
        elif state == "char":
            out[i] = " "
            if c == "\\":
                if i + 1 < n:
                    out[i + 1] = " "
                    i += 2
                    continue
            if c == "'":
                state = "code"
        i += 1
    return "".join(out)


def find_matching_brace(clean: str, open_off: int) -> int:
    depth = 1
    i = open_off + 1
    while i < len(clean):
        if clean[i] == "{":
            depth += 1
        elif clean[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"unmatched brace at offset {open_off}")


def function_name_from_header(header: str) -> str | None:
    h = "\n".join(
        line for line in header.strip().splitlines() if not line.lstrip().startswith("#")
    ).strip()
    if not h.endswith(")") or "(" not in h:
        return None
    paren = h.rfind("(")
    before = h[:paren].rstrip()
    m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", before)
    if not m:
        return None
    name = m.group(1)
    if name in KEYWORDS:
        return None
    # Avoid prototypes or function-pointer declarations that happen to be in
    # the top-level chunk.
    if ";" in h:
        h = h[h.rfind(";") + 1 :].strip()
        return function_name_from_header(h)
    return name


def cyclomatic_complexity(body: str) -> int:
    clean = sanitize_c(body)
    score = 1
    score += len(re.findall(r"\b(if|for|while|case|default)\b", clean))
    score += clean.count("&&")
    score += clean.count("||")
    # Count ternaries. Ignore question marks in comments/strings because they
    # were sanitized above.
    score += clean.count("?")
    return score


def discover_functions(src: str) -> List[Function]:
    clean = sanitize_c(src)
    funcs: List[Function] = []
    depth = 0
    last_top = 0
    i = 0
    while i < len(clean):
        c = clean[i]
        if c == "{" and depth == 0:
            header = src[last_top:i]
            name = function_name_from_header(header)
            if name:
                end = find_matching_brace(clean, i)
                body = src[i + 1 : end]
                funcs.append(
                    Function(
                        name=name,
                        line=line_at(src, i),
                        start=last_top,
                        body_start=i,
                        end=end,
                        complexity=cyclomatic_complexity(body),
                    )
                )
                last_top = end + 1
                i = end + 1
                continue
            depth += 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth = max(0, depth - 1)
            if depth == 0:
                last_top = i + 1
        elif c == ";" and depth == 0:
            last_top = i + 1
        i += 1
    return funcs


def block_points(src: str, fn: Function, next_pid: int) -> Tuple[List[Point], int]:
    points = [Point(next_pid, fn.name, fn.line, "entry", fn.body_start + 1)]
    next_pid += 1
    clean = sanitize_c(src)
    i = fn.body_start + 1
    depth = 1
    while i < fn.end:
        c = clean[i]
        if c == "{":
            prev = previous_nonspace(clean, i)
            tok = previous_token(clean, i)
            # Instrument statement/control blocks, not initializers.
            if prev == ")" or tok in {"else", "do"}:
                points.append(Point(next_pid, fn.name, line_at(src, i), "block", i + 1))
                next_pid += 1
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return points, next_pid


def runtime_prelude(npoints: int) -> str:
    return f"""

/* === o9 CRAP coverage instrumentation: generated, do not edit === */
enum {{ O9_CRAP_NPOINTS = {npoints} }};
static ulong o9_crap_hits[O9_CRAP_NPOINTS];
static void
o9_crap_hit(int p)
{{
    if(p >= 0 && p < O9_CRAP_NPOINTS)
        o9_crap_hits[p]++;
}}
static void
o9_crap_dump(void)
{{
    char *path;
    int fd, i;

    path = getenv("O9_CRAP_OUT");
    if(path == nil || path[0] == '\\0'){{
        free(path);
        return;
    }}
    fd = open(path, OWRITE);
    if(fd < 0)
        fd = create(path, OWRITE, 0666);
    if(fd < 0){{
        free(path);
        return;
    }}
    seek(fd, 0, 2);
    for(i = 0; i < O9_CRAP_NPOINTS; i++)
        if(o9_crap_hits[i] != 0)
            fprint(fd, "%d\\t%lud\\n", i, o9_crap_hits[i]);
    close(fd);
    free(path);
}}
#define O9CRAP_HIT(p) o9_crap_hit(p)
/* === end o9 CRAP coverage instrumentation === */

"""


def insert_after_includes(src: str, prelude: str) -> str:
    lines = src.splitlines(True)
    pos = 0
    for i, line in enumerate(lines):
        ls = line.lstrip()
        if ls.startswith("#include"):
            pos = i + 1
            continue
        if ls.startswith("#line") or line.strip() == "":
            continue
        if pos != 0:
            break
    return "".join(lines[:pos]) + prelude + "".join(lines[pos:])


def instrument_source(src: str) -> Tuple[str, List[Function], List[Point]]:
    funcs = discover_functions(src)
    all_points: List[Point] = []
    next_pid = 0
    for fn in funcs:
        pts, next_pid = block_points(src, fn, next_pid)
        fn.points = pts
        all_points.extend(pts)

    insertions: List[Tuple[int, str]] = []
    for p in all_points:
        insertions.append((p.offset, f" O9CRAP_HIT({p.pid});"))

    out = src
    for off, text in sorted(insertions, reverse=True):
        out = out[:off] + text + out[off:]

    out = re.sub(r"\bexits\s*\(([^;]*)\);", r"do { o9_crap_dump(); exits(\1); } while(0);", out)
    out = insert_after_includes(out, runtime_prelude(len(all_points)))
    return out, funcs, all_points


def write_meta(path: str, funcs: Iterable[Function], points: Iterable[Point]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write("kind\tid\tfunction\tline\tcomplexity\tpointkind\n")
        for fn in funcs:
            f.write(f"F\t\t{fn.name}\t{fn.line}\t{fn.complexity}\t\n")
        for p in points:
            f.write(f"P\t{p.pid}\t{p.function}\t{p.line}\t\t{p.kind}\n")


def cmd_instrument(args: argparse.Namespace) -> int:
    with open(args.source, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    out, funcs, points = instrument_source(src)
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    os.makedirs(os.path.dirname(args.meta) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(out)
    write_meta(args.meta, funcs, points)
    print(f"instrumented {len(funcs)} functions, {len(points)} coverage points")
    print(f"wrote {args.output}")
    print(f"wrote {args.meta}")
    return 0


def read_meta(path: str):
    funcs: Dict[str, Dict[str, float]] = {}
    point_to_func: Dict[int, str] = {}
    func_points: Dict[str, List[int]] = {}
    with open(path, "r", encoding="utf-8") as f:
        next(f, None)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 6:
                continue
            kind, pid, name, line_no, complexity, pointkind = parts[:6]
            if kind == "F":
                funcs[name] = {
                    "line": int(line_no),
                    "complexity": int(complexity),
                }
                func_points.setdefault(name, [])
            elif kind == "P":
                n = int(pid)
                point_to_func[n] = name
                func_points.setdefault(name, []).append(n)
    return funcs, point_to_func, func_points


def read_counts(path: str) -> Dict[int, int]:
    counts: Dict[int, int] = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 2:
                continue
            try:
                pid = int(parts[0])
                hits = int(parts[1])
            except ValueError:
                continue
            counts[pid] = counts.get(pid, 0) + hits
    return counts


def crap_score(complexity: int, coverage: float) -> float:
    miss = 1.0 - coverage
    return complexity * complexity * miss * miss * miss + complexity


def cmd_report(args: argparse.Namespace) -> int:
    funcs, point_to_func, func_points = read_meta(args.meta)
    counts = read_counts(args.counts)
    ignores = [re.compile(p) for p in args.ignore]
    rows = []
    violations = []
    for name, info in funcs.items():
        if any(p.search(name) for p in ignores):
            continue
        pts = func_points.get(name, [])
        total = len(pts)
        covered = sum(1 for p in pts if counts.get(p, 0) > 0)
        coverage = (covered / total) if total else 0.0
        complexity = int(info["complexity"])
        rows.append(
            (
                crap_score(complexity, coverage),
                complexity,
                coverage,
                covered,
                total,
                int(info["line"]),
                name,
            )
        )
    rows.sort(reverse=True)
    for row in rows:
        score, cc, cov, covered, total, line, name = row
        if args.max_crap is not None and score >= args.max_crap:
            violations.append(row)
        elif args.max_cc is not None and cc >= args.max_cc:
            violations.append(row)
    limit = args.limit if args.limit > 0 else len(rows)
    print("CRAP\tCC\tCOV%\tPTS\tLINE\tFUNCTION")
    for score, cc, cov, covered, total, line, name in rows[:limit]:
        print(f"{score:.2f}\t{cc}\t{cov*100:.1f}\t{covered}/{total}\t{line}\t{name}")
    if args.max_crap is not None or args.max_cc is not None:
        print(f"violations\t{len(violations)}", file=sys.stderr)
        if violations:
            print("CRAP\tCC\tCOV%\tPTS\tLINE\tFUNCTION", file=sys.stderr)
            for score, cc, cov, covered, total, line, name in violations[: args.violation_limit]:
                print(f"{score:.2f}\t{cc}\t{cov*100:.1f}\t{covered}/{total}\t{line}\t{name}", file=sys.stderr)
    if args.output:
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            f.write("crap\tcomplexity\tcoverage\tcovered_points\ttotal_points\tline\tfunction\n")
            for score, cc, cov, covered, total, line, name in rows:
                f.write(f"{score:.4f}\t{cc}\t{cov:.6f}\t{covered}\t{total}\t{line}\t{name}\n")
        print(f"wrote {args.output}", file=sys.stderr)
    if args.fail and violations:
        return 1
    return 0


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="Instrument and report o9c CRAP scores.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("instrument", help="instrument generated o9c/y.tab.c")
    p.add_argument("--source", default="o9c/y.tab.c")
    p.add_argument("--output", default="o9c/test/artifacts/y.tab.crap.c")
    p.add_argument("--meta", default="o9c/test/artifacts/o9crap_meta.tsv")
    p.set_defaults(func=cmd_instrument)

    p = sub.add_parser("report", help="combine metadata and hit counts into CRAP scores")
    p.add_argument("--meta", default="o9c/test/artifacts/o9crap_meta.tsv")
    p.add_argument("--counts", default="o9c/test/artifacts/o9crap_counts.tsv")
    p.add_argument("--output", default="o9c/test/artifacts/o9crap_report.tsv")
    p.add_argument("--limit", type=int, default=40)
    p.add_argument("--ignore", action="append", default=[],
        help="ignore function names matching this regex; repeatable")
    p.add_argument("--max-crap", type=float,
        help="report functions with CRAP greater than or equal to this value")
    p.add_argument("--max-cc", type=int,
        help="report functions with cyclomatic complexity greater than or equal to this value")
    p.add_argument("--violation-limit", type=int, default=40,
        help="number of gate violations to print to stderr")
    p.add_argument("--fail", action="store_true",
        help="exit non-zero when max-crap or max-cc violations exist")
    p.set_defaults(func=cmd_report)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
