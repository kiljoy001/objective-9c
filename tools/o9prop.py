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


@dataclasses.dataclass(frozen=True)
class ExpectedCase:
    name: str
    seed: int
    o9: str
    output: str


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
WORDS = (
    "alpha",
    "beta",
    "front",
    "rio",
    "tabula",
    "grid",
    "draw",
    "orders",
)


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


def c_quote(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def o9_quote(s: str) -> str:
    return c_quote(s)


def string_before(s: str, sep: str) -> str:
    pos = s.find(sep)
    if pos < 0:
        return s
    return s[:pos]


def string_after(s: str, sep: str) -> str:
    pos = s.find(sep)
    if pos < 0:
        return ""
    return s[pos + len(sep) :]


def string_field(s: str, sep: str, index: int) -> str:
    parts = s.split(sep)
    if index < 0 or index >= len(parts):
        return ""
    return parts[index]


def make_string_case(name: str, seed: int) -> ExpectedCase:
    rng = random.Random(seed)
    left = rng.choice(WORDS)
    mid = rng.choice([w for w in WORDS if w != left])
    right = rng.choice([w for w in WORDS if w not in (left, mid)])
    base = f"  {left} {mid} {right}  "
    csv = f"{left},{mid},{right}"
    needle = mid[: max(1, min(3, len(mid)))]
    repl = rng.choice([w for w in WORDS if w not in (left, mid, right)])
    start = rng.randint(0, 3)
    count = rng.randint(2, 6)
    repeat = rng.randint(2, 4)
    output = "".join(
        [
            f"len {len(base)}\n",
            f"trim {base.strip()}\n",
            f"slice {base[start:start + count]}\n",
            f"contains {int(needle in base)} {int('missing' in base)}\n",
            f"last {base.rfind(needle)} count {base.count(needle)}\n",
            f"prefix {int(base.startswith('  ' + left[:2]))} suffix {int(base.endswith(right + '  '))}\n",
            f"case {base.lower()} | {base.upper()}\n",
            f"cat {base}!\n",
            f"replace {base.replace(mid, repl)}\n",
            f"repeat {left[:2] * repeat}\n",
            f"field {string_field(csv, ',', 1)} missing {string_field(csv, ',', 9)}\n",
            f"before {string_before(csv, ',')} after {string_after(csv, ',')}\n",
            f"line {mid}\n",
        ]
    )
    o9 = f'''import "stdlib/string.o9";

main {{
    String s = new String("{o9_quote(base)}");
    String csv = new String("{o9_quote(csv)}");
    String lines = new String("{o9_quote(left + chr(10) + mid + chr(10) + right)}");
    String rep = new String("{o9_quote(left[:2])}");
    print("len ", s.length(), "\\n");
    print("trim ", s.trim(), "\\n");
    print("slice ", s.slice({start}, {count}), "\\n");
    print("contains ", s.contains("{o9_quote(needle)}"), " ", s.contains("missing"), "\\n");
    print("last ", s.lastIndexOf("{o9_quote(needle)}"), " count ", s.count("{o9_quote(needle)}"), "\\n");
    print("prefix ", s.startsWith("  {o9_quote(left[:2])}"), " suffix ", s.endsWith("{o9_quote(right)}  "), "\\n");
    print("case ", s.lower(), " | ", s.upper(), "\\n");
    print("cat ", s.concat("!"), "\\n");
    print("replace ", s.replace("{o9_quote(mid)}", "{o9_quote(repl)}"), "\\n");
    print("repeat ", rep.repeat({repeat}), "\\n");
    print("field ", csv.field(",", 1), " missing ", csv.field(",", 9), "\\n");
    print("before ", csv.before(","), " after ", csv.after(","), "\\n");
    print("line ", lines.line(1), "\\n");
}}
'''
    return ExpectedCase(name, seed, o9, output)


def make_bytes_case(name: str, seed: int) -> ExpectedCase:
    rng = random.Random(seed)
    base = "".join(rng.choice("abcdefxyz") for _ in range(3))
    append_byte = rng.randint(65, 90)
    append_text = rng.choice(("9", "!", "Q"))
    set_index = rng.randint(0, 2)
    set_byte = rng.randint(48, 57)
    data = bytearray(base.encode("ascii"))
    data.append(append_byte)
    data.extend(append_text.encode("ascii"))
    after_append = data.decode("latin1")
    data[set_index] = set_byte
    after_set = data.decode("latin1")
    hex_text = data.hex()
    output = "".join(
        [
            f"len0 {len(base)} empty {int(len(base) == 0)}\n",
            f"text {after_append}\n",
            f"set {after_set}\n",
            f"get {data[0]} {data[-1]} 0\n",
            f"slice {after_set[1:4]} \n",
            f"hex {hex_text}\n",
            f"fromhex 1 {after_set} {hex_text}\n",
            "badhex 0 0\n",
            "clear 0 1\n",
        ]
    )
    o9 = f'''import "stdlib/bytes.o9";

main {{
    Bytes b = new Bytes("{o9_quote(base)}");
    Bytes decoded = new Bytes("");
    print("len0 ", b.length(), " empty ", b.empty(), "\\n");
    b.append({append_byte});
    b.appendString("{o9_quote(append_text)}");
    print("text ", b.text(), "\\n");
    b.set({set_index}, {set_byte});
    print("set ", b.text(), "\\n");
    print("get ", b.get(0), " ", b.get(b.length() - 1), " ", b.get(99), "\\n");
    print("slice ", b.slice(1, 3), " ", b.slice(99, 4), "\\n");
    print("hex ", b.hex(), "\\n");
    print("fromhex ", decoded.fromHex("{hex_text}"), " ", decoded.text(), " ", decoded.hex(), "\\n");
    print("badhex ", decoded.fromHex("zz"), " ", decoded.length(), "\\n");
    b.clear();
    print("clear ", b.length(), " ", b.empty(), "\\n");
}}
'''
    return ExpectedCase(name, seed, o9, output)


def make_collection_case(name: str, seed: int) -> ExpectedCase:
    rng = random.Random(seed)
    vals = [rng.randint(1, 50) for _ in range(3)]
    replacement = rng.randint(51, 99)
    key1 = rng.choice(WORDS)
    key2 = rng.choice([w for w in WORDS if w != key1])
    output = "".join(
        [
            f"list {len(vals)} {vals[0]} {replacement} {vals[2]} {vals[0] + replacement + vals[2]}\n",
            f"dict {int(True)} {int(False)} {vals[0]} {replacement}\n",
            f"names {key1} {key2}\n",
        ]
    )
    o9 = f'''main {{
    List<int64> xs;
    xs.Add({vals[0]});
    xs.Add({vals[1]});
    xs.Add({vals[2]});
    xs[1] = {replacement};
    print("list ", xs.Length(), " ", xs[0], " ", xs[1], " ", xs[2], " ", xs[0] + xs[1] + xs[2], "\\n");

    Dict<string,int64> nums;
    nums["{o9_quote(key1)}"] = {vals[0]};
    nums["{o9_quote(key2)}"] = {replacement};
    print("dict ", nums.Has("{o9_quote(key1)}"), " ", nums.Has("missing"), " ", nums["{o9_quote(key1)}"], " ", nums["{o9_quote(key2)}"], "\\n");

    Dict<int64,string> names;
    names[1] = "{o9_quote(key1)}";
    names[2] = "{o9_quote(key2)}";
    print("names ", names[1], " ", names[2], "\\n");
}}
'''
    return ExpectedCase(name, seed, o9, output)


def make_channel_case(name: str, seed: int) -> ExpectedCase:
    rng = random.Random(seed)
    a = rng.randint(1, 40)
    b = rng.randint(41, 90)
    word = rng.choice(WORDS)
    output = f"int {a + b}\nstring {word}\nlist {a + b + 2}\n"
    o9 = f'''class PropPipe {{
    chan<int64> ints;
    chan<string> strings;
    chan<List<int64> > lists;

    method void sendInt(int64 a, int64 b) {{
        ints -> a;
        ints -> b;
    }}

    method int64 takeInt() {{
        int64 a;
        int64 b;
        a = <- ints;
        b = <- ints;
        return a + b;
    }}

    method void sendString(string s) {{
        strings -> s;
    }}

    method string takeString() {{
        string s;
        s = <- strings;
        return s;
    }}

    method void sendList(int64 a, int64 b) {{
        List<int64> xs;
        xs.Add(a);
        xs.Add(b);
        lists -> xs;
    }}

    method int64 takeList() {{
        List<int64> xs;
        xs = <- lists;
        return xs[0] + xs[1] + xs.Length();
    }}
}}

main {{
    PropPipe p = new PropPipe();
    p.sendInt({a}, {b});
    print("int ", p.takeInt(), "\\n");
    p.sendString("{o9_quote(word)}");
    print("string ", p.takeString(), "\\n");
    p.sendList({a}, {b});
    print("list ", p.takeList(), "\\n");
}}
'''
    return ExpectedCase(name, seed, o9, output)


def make_tabula_case(name: str, seed: int) -> ExpectedCase:
    rng = random.Random(seed)
    item = rng.choice(WORDS)
    other = rng.choice([w for w in WORDS if w != item])
    qty = rng.randint(1, 20)
    output = "".join(
        [
            "schema orders has 1 missing 0\n",
            f"paid 1 {item} {qty}\n",
            "readcmp 0\n",
            "bad -1\n",
            f"open 1 {other}\n",
        ]
    )
    o9 = f'''main {{
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "{o9_quote(item)}");
    t.write("a", "qty", "{qty}");
    t.write("a", "status", "paid");
    t.write("b", "item", "{o9_quote(other)}");
    t.write("b", "qty", "{qty + 1}");
    t.write("b", "status", "open");
    print("schema ", t.schema(), " has ", t.has("status"), " missing ", t.has("missing"), "\\n");
    Tabula paid = t.query("status", "paid");
    print("paid ", paid.first(), " ", paid.get("item"), " ", paid.get("qty"), "\\n");
    print("readcmp ", cmp(t.read(), t.serialize()), "\\n");
    print("bad ", t.write("c", "missing", "x"), "\\n");
    Tabula open = t.query("status", "open");
    print("open ", open.first(), " ", open.get("item"), "\\n");
}}
'''
    return ExpectedCase(name, seed, o9, output)


def make_stdlib_case(kind: str, index: int, seed: int) -> ExpectedCase:
    name = f"{kind}_{index:03d}"
    if kind == "string":
        return make_string_case(name, seed)
    if kind == "bytes":
        return make_bytes_case(name, seed)
    if kind == "collections":
        return make_collection_case(name, seed)
    if kind == "channels":
        return make_channel_case(name, seed)
    return make_tabula_case(name, seed)


def build_stdlib_cases(count: int, seed: int) -> List[ExpectedCase]:
    lanes = ("string", "bytes", "collections", "channels", "tabula")
    seeds = fallback_seeds(max(count, len(lanes)), seed)
    cases: List[ExpectedCase] = []
    i = 0
    while len(cases) < count:
        lane = lanes[len(cases) % len(lanes)]
        cases.append(make_stdlib_case(lane, len(cases), seeds[i]))
        i += 1
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


def expected_c_source(case: ExpectedCase) -> str:
    return "\n".join(
        [
            f"/* generated by tools/o9prop.py kind=stdlib seed={case.seed} */",
            "#include <u.h>",
            "#include <libc.h>",
            "",
            "void",
            "main(void)",
            "{",
            f'\tfprint(1, "{c_quote(case.output)}");',
            "\texits(nil);",
            "}",
        ]
    ) + "\n"


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


def write_expected_cases(cases: Sequence[ExpectedCase], outdir: Path) -> None:
    clean_outdir(outdir)
    manifest = []
    for case in cases:
        (outdir / f"{case.name}.o9").write_text(case.o9, encoding="utf-8")
        (outdir / f"{case.name}.ref.c").write_text(expected_c_source(case), encoding="utf-8")
        manifest.append(case.name)
    (outdir / "manifest").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def command_generate(args: argparse.Namespace) -> None:
    if args.kind == "scalar":
        cases = build_cases(args.cases, args.seed)
        write_cases(cases, Path(args.out))
    elif args.kind == "width":
        cases = build_width_cases(args.cases, args.seed)
        write_width_cases(cases, Path(args.out))
    else:
        cases = build_stdlib_cases(args.cases, args.seed)
        write_expected_cases(cases, Path(args.out))
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
    gen.add_argument("--kind", choices=("scalar", "width", "stdlib"), default="scalar")
    gen.add_argument("--out", default="o9c/test/prop/scalar")
    gen.add_argument("--cases", type=int, default=32)
    gen.add_argument("--seed", type=int, default=9009)
    gen.set_defaults(func=command_generate)

    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
