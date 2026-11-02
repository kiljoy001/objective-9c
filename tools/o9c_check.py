#!/usr/bin/env python3
"""Host-side smoke and fuzz checks for the o9c transpiler.

The compiler is a normal host program (plan9port's 9c/9l build it on Linux),
so the front end can be exercised without booting 9front.  This catches
parser/typechecker crashes and diagnostics regressions cheaply; native e2e
tests still cover generated Plan 9 C and the 9P facade.
"""

import argparse
import glob
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMPILER = ROOT / "o9c/o9c"

POSITIVE = [
    "o9c/test/counter.o9",
    "o9c/test/struct_test.o9",
    "o9c/test/modulo.o9",
    "o9c/test/struct_actor_return.o9",
    "o9c/test/codegen_generic_self_return.o9",
    "o9c/test/codegen_class_order.o9",
]

# Fixtures whose generated C must also compile.  These catch ordering and
# type-storage regressions that still transpile successfully.
GENERATED_C = [
    "o9c/test/codegen_generic_self_return.o9",
    "o9c/test/codegen_class_order.o9",
]

# Mutating these small, import-free programs keeps the fuzz input focused on
# the parser/typechecker rather than on import resolution.
FUZZ_SEEDS = POSITIVE[:3]

MUTATION_CHARS = (
    "{}()[];:,.=+-*/%<>!&|^~?@#$"
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789 \t\n\"'"
)


def run_compiler(compiler: Path, path: Path, timeout: float):
    return subprocess.run(
        [str(compiler), str(path)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def check_generated_c(compiler: Path, timeout: float) -> list[str]:
    """Compile generated C for fixtures that exercise codegen ordering.

    The transpiler can succeed while emitting invalid C (undeclared
    Internal structs, erased generic storage).  Compile when a Plan 9 C
    compiler is available; host_test.sh always provides one.
    """
    failures: list[str] = []
    cc = shutil.which("9c")
    if cc is None:
        return failures

    with tempfile.TemporaryDirectory(prefix="o9c-codegen-") as td:
        for rel in GENERATED_C:
            src = ROOT / rel
            if not src.is_file():
                failures.append(f"missing generated-C fixture: {rel}")
                continue
            stem = src.stem
            c_path = Path(td) / f"{stem}.c"
            o_path = Path(td) / f"{stem}.o"
            try:
                gen = subprocess.run(
                    [str(compiler), "--no-facade", str(src)],
                    cwd=str(ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=timeout,
                )
            except (subprocess.TimeoutExpired, OSError) as e:
                failures.append(f"cannot transpile {rel}: {e}")
                continue
            if gen.returncode != 0:
                failures.append(f"transpile failed for {rel} (rc={gen.returncode})")
                continue
            c_path.write_bytes(gen.stdout)
            try:
                cc_result = subprocess.run(
                    [
                        cc,
                        "-include",
                        str(ROOT / "o9c/test/host_compat.h"),
                        "-I",
                        str(ROOT),
                        "-I",
                        str(ROOT / "o9c/test"),
                        "-DO9_PLAN9PORT",
                        "-o",
                        str(o_path),
                        str(c_path),
                    ],
                    cwd=str(ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=timeout,
                )
            except (subprocess.TimeoutExpired, OSError) as e:
                failures.append(f"cannot compile generated C for {rel}: {e}")
                continue
            if cc_result.returncode != 0:
                errors = cc_result.stderr.decode(errors="replace").splitlines()
                detail = " | ".join(errors[:3])
                failures.append(f"generated C failed to compile: {rel} ({detail})")
    return failures


def smoke(compiler: Path, timeout: float) -> list[str]:
    failures: list[str] = []

    for rel in POSITIVE:
        path = ROOT / rel
        if not path.is_file():
            failures.append(f"missing positive fixture: {rel}")
            continue
        try:
            result = run_compiler(compiler, path, timeout)
        except subprocess.TimeoutExpired:
            failures.append(f"timeout compiling positive fixture: {rel}")
            continue
        except OSError as e:
            failures.append(f"cannot run compiler on {rel}: {e}")
            continue
        if result.returncode != 0:
            failures.append(
                f"positive fixture failed: {rel} (rc={result.returncode})"
            )
            continue
        if len(result.stdout) < 128:
            failures.append(f"positive fixture produced no generated C: {rel}")
            continue
        if b"#line" not in result.stdout:
            failures.append(f"generated C is missing source maps: {rel}")
        if rel == "o9c/test/counter.o9" and b"/* o9:" not in result.stdout:
            failures.append(
                "generated C is missing o9 source annotations: counter.o9"
            )
        if rel == "o9c/test/struct_actor_return.o9" and \
           b"obj9_msgSendStructN" not in result.stdout:
            failures.append(
                "struct-returning actor method did not use the struct reply path"
            )

    failures += check_generated_c(compiler, timeout)

    negatives = sorted(glob.glob(str(ROOT / "o9c/test/typecheck_bad_*.o9")))
    if not negatives:
        failures.append("no typecheck_bad_*.o9 fixtures found")
    for path in negatives:
        p = Path(path)
        try:
            result = run_compiler(compiler, p, timeout)
        except subprocess.TimeoutExpired:
            failures.append(f"timeout compiling negative fixture: {p.name}")
            continue
        except OSError as e:
            failures.append(f"cannot run compiler on {p.name}: {e}")
            continue
        if result.returncode == 0:
            failures.append(f"negative fixture unexpectedly compiled: {p.name}")
        elif result.returncode < 0:
            failures.append(
                f"compiler crashed on negative fixture: {p.name} "
                f"(signal {-result.returncode})"
            )

    return failures


def mutate(text: str, rng: random.Random) -> str:
    chars = list(text)
    if not chars:
        return rng.choice(MUTATION_CHARS) * 8
    for _ in range(rng.randint(1, 8)):
        op = rng.randrange(3)
        if op == 0 and chars:
            chars[rng.randrange(len(chars))] = rng.choice(MUTATION_CHARS)
        elif op == 1:
            chars.insert(rng.randrange(len(chars) + 1), rng.choice(MUTATION_CHARS))
        elif chars:
            del chars[rng.randrange(len(chars))]
    return "".join(chars)


def fuzz(compiler: Path, iterations: int, seed: int, timeout: float) -> list[str]:
    failures: list[str] = []
    rng = random.Random(seed)
    seeds = []
    for rel in FUZZ_SEEDS:
        path = ROOT / rel
        if path.is_file():
            seeds.append(path.read_text(errors="replace"))
    if not seeds:
        return ["no fuzz seeds available"]

    with tempfile.TemporaryDirectory(prefix="o9c-fuzz-") as td:
        for i in range(iterations):
            source = mutate(rng.choice(seeds), rng)
            path = Path(td) / f"case{i}.o9"
            path.write_text(source, errors="replace")
            try:
                result = run_compiler(compiler, path, timeout)
            except subprocess.TimeoutExpired:
                failures.append(
                    f"fuzz timeout at iteration {i}; input saved at {path}"
                )
                # Keep the input for reproduction even though the TemporaryDirectory
                # will disappear; copy it next to the artifacts directory.
                keep = ROOT / "o9c/test/artifacts" / f"o9c-fuzz-timeout-{i}.o9"
                keep.parent.mkdir(parents=True, exist_ok=True)
                keep.write_text(source, errors="replace")
                failures[-1] += f" (copy: {keep})"
                break
            except OSError as e:
                failures.append(f"cannot run compiler at iteration {i}: {e}")
                break
            if result.returncode < 0:
                keep = ROOT / "o9c/test/artifacts" / f"o9c-fuzz-crash-{i}.o9"
                keep.parent.mkdir(parents=True, exist_ok=True)
                keep.write_text(source, errors="replace")
                failures.append(
                    f"compiler crashed at iteration {i} with signal "
                    f"{-result.returncode}; input: {keep}"
                )
                break
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--compiler",
        type=Path,
        default=Path(os.environ.get("O9C", DEFAULT_COMPILER)),
        help="path to the o9c binary",
    )
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--fuzz", type=int, default=0, help="fuzz iterations")
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    compiler = args.compiler
    if not compiler.is_file():
        print(f"o9c_check: compiler not found: {compiler}", file=sys.stderr)
        return 1

    failures = smoke(compiler, args.timeout)
    if args.fuzz:
        failures += fuzz(compiler, args.fuzz, args.seed, args.timeout)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(
        f"o9c_check: PASS ({len(POSITIVE)} positive, "
        f"{len(glob.glob(str(ROOT / 'o9c/test/typecheck_bad_*.o9')))} negative"
        + (f", {args.fuzz} fuzz cases" if args.fuzz else "")
        + ")"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
