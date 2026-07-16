#!/usr/bin/env python3
"""Generate property-test corpora for o9.

The generated cases are checked on 9front by compiling two programs:

    case.o9     -> o9c -> generated C -> stdout
    case.ref.c  -> Plan 9 C directly   -> stdout

The rc harness compares stdout.  Python is only the case generator.  When
Hypothesis is installed it drives seed generation; otherwise a deterministic
fallback seed stream keeps the checked-in corpus reproducible.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import random
import shutil
from pathlib import Path
from typing import Iterable, List, Sequence


@dataclasses.dataclass(frozen=True)
class Expr:
    typ: str
    o9: str
    c: str


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    seed: int
    int_values: Sequence[int]
    bool_values: Sequence[int]
    exprs: Sequence[Expr]


@dataclasses.dataclass(frozen=True)
class WidthCast:
    typ: str
    ctyp: str | None
    source: int


@dataclasses.dataclass(frozen=True)
class WidthCase:
    name: str
    seed: int
    casts: Sequence[WidthCast]


INT_VARS = ("a", "b", "d")
BOOL_VARS = ("p", "q")
WIDTH_TYPES: Sequence[tuple[str, str | None]] = (
    ("bool", None),
    ("byte", "uchar"),
    ("int8", "char"),
    ("uint8", "uchar"),
    ("int16", "short"),
    ("uint16", "ushort"),
    ("int32", "long"),
    ("uint32", "ulong"),
    ("char", "char"),
    ("uchar", "uchar"),
    ("short", "short"),
    ("ushort", "ushort"),
    ("int", "int"),
    ("uint", "uint"),
    ("long", "long"),
    ("ulong", "ulong"),
    ("int64", "vlong"),
    ("uint64", "uvlong"),
    ("vlong", "vlong"),
    ("uvlong", "uvlong"),
    ("intptr", "intptr"),
    ("uintptr", "uintptr"),
)
WIDTH_VALUES = (
    -65537,
    -65536,
    -32769,
    -32768,
    -257,
    -256,
    -129,
    -128,
    -1,
    0,
    1,
    2,
    7,
    15,
    31,
    63,
    64,
    127,
    128,
    255,
    256,
    1023,
    32767,
    32768,
    65535,
    65536,
)
WIDTH_NONNEG_VALUES = tuple(v for v in WIDTH_VALUES if v >= 0)


def atom_int(rng: random.Random, *, nonneg: bool = False, small: bool = False) -> Expr:
    choices: List[Expr] = []
    limit = 15 if small else 200
    lo = 0 if nonneg else -limit
    if not nonneg:
        for name in INT_VARS:
            choices.append(Expr("int64", name, name))
    for _ in range(4):
        n = rng.randint(lo, limit)
        choices.append(Expr("int64", str(n), str(n)))
    return rng.choice(choices)


def int_expr(rng: random.Random, depth: int, *, nonneg: bool = False, small: bool = False) -> Expr:
    if depth <= 0:
        return atom_int(rng, nonneg=nonneg, small=small)

    ops = ["+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>", "neg", "bitnot"]
    if nonneg:
        ops = ["+", "*", "/", "%", "&", "|", "^", "<<", ">>"]
    op = rng.choice(ops)

    if op == "neg":
        x = int_expr(rng, depth - 1, small=True)
        return Expr("int64", f"(0 - ({x.o9}))", f"(0 - ({x.c}))")
    if op == "bitnot":
        x = int_expr(rng, depth - 1, small=True)
        return Expr("int64", f"(~{x.o9})", f"(~{x.c})")
    if op in ("/", "%"):
        left = int_expr(rng, depth - 1, nonneg=True, small=True)
        right = atom_int(rng, nonneg=True, small=True)
        divisor = rng.randint(1, 15)
        if rng.randint(0, 1):
            right = Expr("int64", str(divisor), str(divisor))
        else:
            right = Expr("int64", f"({right.o9} + {divisor})", f"({right.c} + {divisor})")
        return Expr("int64", f"({left.o9} {op} {right.o9})", f"({left.c} {op} {right.c})")
    if op in ("<<", ">>"):
        left = int_expr(rng, depth - 1, nonneg=True, small=True)
        shift = rng.randint(0, 5)
        return Expr("int64", f"({left.o9} {op} {shift})", f"({left.c} {op} {shift})")

    left = int_expr(rng, depth - 1, small=small or op == "*")
    right = int_expr(rng, depth - 1, small=small or op == "*")
    return Expr("int64", f"({left.o9} {op} {right.o9})", f"({left.c} {op} {right.c})")


def atom_bool(rng: random.Random) -> Expr:
    choices = [
        Expr("bool", "true", "1"),
        Expr("bool", "false", "0"),
        Expr("bool", "p", "p"),
        Expr("bool", "q", "q"),
    ]
    return rng.choice(choices)


def bool_expr(rng: random.Random, depth: int) -> Expr:
    if depth <= 0:
        return atom_bool(rng)

    op = rng.choice(["cmp", "eqbool", "and", "or", "not"])
    if op == "not":
        x = bool_expr(rng, depth - 1)
        return Expr("bool", f"(!{x.o9})", f"(!{x.c})")
    if op in ("and", "or"):
        left = bool_expr(rng, depth - 1)
        right = bool_expr(rng, depth - 1)
        sym = "&&" if op == "and" else "||"
        return Expr("bool", f"({left.o9} {sym} {right.o9})", f"({left.c} {sym} {right.c})")
    if op == "eqbool":
        left = bool_expr(rng, depth - 1)
        right = bool_expr(rng, depth - 1)
        sym = rng.choice(["==", "!="])
        return Expr("bool", f"({left.o9} {sym} {right.o9})", f"({left.c} {sym} {right.c})")

    left = int_expr(rng, depth - 1, small=True)
    right = int_expr(rng, depth - 1, small=True)
    sym = rng.choice(["==", "!=", "<", "<=", ">", ">="])
    return Expr("bool", f"({left.o9} {sym} {right.o9})", f"({left.c} {sym} {right.c})")


def make_case(name: str, seed: int) -> Case:
    rng = random.Random(seed)
    int_values = tuple(rng.randint(-64, 64) for _ in INT_VARS)
    bool_values = tuple(rng.randint(0, 1) for _ in BOOL_VARS)
    exprs: List[Expr] = []
    for _ in range(4):
        exprs.append(int_expr(rng, rng.randint(1, 3)))
    for _ in range(4):
        exprs.append(bool_expr(rng, rng.randint(1, 3)))
    return Case(name, seed, int_values, bool_values, tuple(exprs))


def case_key(case: Case) -> str:
    h = hashlib.sha256()
    for expr in case.exprs:
        h.update(expr.typ.encode())
        h.update(b"\0")
        h.update(expr.o9.encode())
        h.update(b"\0")
    return h.hexdigest()


def fallback_seeds(count: int, seed: int) -> List[int]:
    rng = random.Random(seed)
    return [rng.randrange(0, 2**31 - 1) for _ in range(count * 4)]


def hypothesis_seeds(count: int, seed: int) -> List[int]:
    try:
        from hypothesis import Phase, given, settings, strategies as st
    except Exception:
        return []

    seeds: List[int] = []

    @settings(
        max_examples=count * 8,
        database=None,
        derandomize=True,
        phases=(Phase.generate,),
        deadline=None,
    )
    @given(st.integers(min_value=0, max_value=2**31 - 1))
    def collect(value: int) -> None:
        mixed = value ^ seed
        if mixed not in seeds:
            seeds.append(mixed)

    collect()
    return seeds


def build_cases(count: int, seed: int) -> List[Case]:
    seeds = hypothesis_seeds(count, seed)
    if len(seeds) < count:
        seeds.extend(fallback_seeds(count - len(seeds), seed + 1))

    cases: List[Case] = []
    seen = set()
    for value in seeds:
        case = make_case(f"scalar_{len(cases):03d}", value)
        key = case_key(case)
        if key in seen:
            continue
        seen.add(key)
        cases.append(case)
        if len(cases) >= count:
            break
    return cases


def make_width_case(name: str, seed: int) -> WidthCase:
    rng = random.Random(seed)
    casts: List[WidthCast] = []
    for typ, ctyp in WIDTH_TYPES:
        values = WIDTH_NONNEG_VALUES if typ in ("uint64", "uvlong", "uintptr") else WIDTH_VALUES
        casts.append(WidthCast(typ, ctyp, rng.choice(values)))
    rng.shuffle(casts)
    return WidthCase(name, seed, tuple(casts))


def width_case_key(case: WidthCase) -> str:
    h = hashlib.sha256()
    for cast in case.casts:
        h.update(cast.typ.encode())
        h.update(b"\0")
        h.update(str(cast.source).encode())
        h.update(b"\0")
    return h.hexdigest()


def build_width_cases(count: int, seed: int) -> List[WidthCase]:
    seeds = hypothesis_seeds(count, seed)
    if len(seeds) < count:
        seeds.extend(fallback_seeds(count - len(seeds), seed + 1))

    cases: List[WidthCase] = []
    seen = set()
    for value in seeds:
        case = make_width_case(f"width_{len(cases):03d}", value)
        key = width_case_key(case)
        if key in seen:
            continue
        seen.add(key)
        cases.append(case)
        if len(cases) >= count:
            break
    return cases


def o9_source(case: Case) -> str:
    lines = [
        f"// generated by tools/o9prop.py seed={case.seed}",
        "main {",
    ]
    for name, value in zip(INT_VARS, case.int_values):
        lines.append(f"    int64 {name} = {value};")
    for name, value in zip(BOOL_VARS, case.bool_values):
        lit = "true" if value else "false"
        lines.append(f"    bool {name} = {lit};")
    lines.append('    print("vars ", a, " ", b, " ", d, " ", p, " ", q, "\\n");')
    for idx, expr in enumerate(case.exprs):
        lines.append(f"    print(\"{idx} \", {expr.o9}, \"\\n\");")
    lines.append("}")
    return "\n".join(lines) + "\n"


def width_o9_source(case: WidthCase) -> str:
    lines = [
        f"// generated by tools/o9prop.py kind=width seed={case.seed}",
        "main {",
    ]
    for idx, cast in enumerate(case.casts):
        lines.append(f"    int64 s{idx} = {cast.source};")
    source_print = ['    print("vars"']
    for idx, _ in enumerate(case.casts):
        source_print.append(f', " ", s{idx}')
    source_print.append(', "\\n");')
    lines.append("".join(source_print))
    for idx, cast in enumerate(case.casts):
        expr = f"cast<int64>(cast<{cast.typ}>(s{idx}))"
        lines.append(f"    print(\"{idx} {cast.typ} \", {expr}, \"\\n\");")
    lines.append("}")
    return "\n".join(lines) + "\n"


def c_source(case: Case) -> str:
    lines = [
        f"/* generated by tools/o9prop.py seed={case.seed} */",
        "#include <u.h>",
        "#include <libc.h>",
        "",
        "void",
        "main(void)",
        "{",
    ]
    for name, value in zip(INT_VARS, case.int_values):
        lines.append(f"\tvlong {name} = {value};")
    for name, value in zip(BOOL_VARS, case.bool_values):
        lines.append(f"\tint {name} = {value};")
    lines.append("\tUSED(a); USED(b); USED(d); USED(p); USED(q);")
    lines.append('\tfprint(1, "vars %lld %lld %lld %lld %lld\\n", a, b, d, (vlong)p, (vlong)q);')
    for idx, expr in enumerate(case.exprs):
        lines.append(f"\tfprint(1, \"{idx} %lld\\n\", (vlong)({expr.c}));")
    lines.append("\texits(nil);")
    lines.append("}")
    return "\n".join(lines) + "\n"


def width_c_expr(cast: WidthCast, var: str) -> str:
    if cast.typ == "bool":
        return f"(({var}) != 0)"
    return f"(({cast.ctyp})({var}))"


def width_c_source(case: WidthCase) -> str:
    lines = [
        f"/* generated by tools/o9prop.py kind=width seed={case.seed} */",
        "#include <u.h>",
        "#include <libc.h>",
        "",
        "void",
        "main(void)",
        "{",
    ]
    for idx, cast in enumerate(case.casts):
        lines.append(f"\tvlong s{idx} = {cast.source};")
    if case.casts:
        used = "; ".join(f"USED(s{idx})" for idx, _ in enumerate(case.casts))
        lines.append(f"\t{used};")
    fmt = " ".join(["vars"] + ["%lld"] * len(case.casts))
    args = ", ".join(f"s{idx}" for idx, _ in enumerate(case.casts))
    lines.append(f'\tfprint(1, "{fmt}\\n", {args});')
    for idx, cast in enumerate(case.casts):
        expr = width_c_expr(cast, f"s{idx}")
        lines.append(f'\tfprint(1, "{idx} {cast.typ} %lld\\n", (vlong)({expr}));')
    lines.append("\texits(nil);")
    lines.append("}")
    return "\n".join(lines) + "\n"


def clean_outdir(outdir: Path) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    for path in outdir.iterdir():
        if path.is_file() and (path.suffix in (".o9", ".c") or path.name == "manifest"):
            path.unlink()


def write_cases(cases: Sequence[Case], outdir: Path) -> None:
    clean_outdir(outdir)
    manifest = []
    for case in cases:
        (outdir / f"{case.name}.o9").write_text(o9_source(case), encoding="utf-8")
        (outdir / f"{case.name}.ref.c").write_text(c_source(case), encoding="utf-8")
        manifest.append(case.name)
    (outdir / "manifest").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def write_width_cases(cases: Sequence[WidthCase], outdir: Path) -> None:
    clean_outdir(outdir)
    manifest = []
    for case in cases:
        (outdir / f"{case.name}.o9").write_text(width_o9_source(case), encoding="utf-8")
        (outdir / f"{case.name}.ref.c").write_text(width_c_source(case), encoding="utf-8")
        manifest.append(case.name)
    (outdir / "manifest").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def command_generate(args: argparse.Namespace) -> None:
    if args.kind == "scalar":
        cases = build_cases(args.cases, args.seed)
        write_cases(cases, Path(args.out))
    else:
        cases = build_width_cases(args.cases, args.seed)
        write_width_cases(cases, Path(args.out))
    print(f"wrote {len(cases)} {args.kind} property cases to {args.out}")
    if shutil.which("python3") is not None:
        try:
            import hypothesis  # type: ignore  # noqa: F401
            print("generator: hypothesis")
        except Exception:
            print("generator: deterministic fallback (install hypothesis to enable Hypothesis seeds)")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate o9 property test corpora")
    sub = parser.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("generate", help="generate checked-in property cases")
    gen.add_argument("--kind", choices=("scalar", "width"), default="scalar")
    gen.add_argument("--out", default="o9c/test/prop/scalar")
    gen.add_argument("--cases", type=int, default=32)
    gen.add_argument("--seed", type=int, default=9009)
    gen.set_defaults(func=command_generate)

    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
