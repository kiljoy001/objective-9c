#!/usr/bin/env python3
"""Prepare QuickJS sources for a native Plan 9 6c build.

Native 6c does not implement #if/#elif/defined, token pasting, inline, or
[static N] parameters.  This host-side bridge vendors the engine, applies the
two native deltas, runs the host C preprocessor to resolve every conditional
and macro, and post-processes the result into plain C for 6c.

Usage:
    python3 preprocess-native.py \
        --source /path/to/generated9/sys/src/cmd/quickjs \
        --plan9 /path/to/9front

Run it from libquickjs/ (the default --out).  It writes engine/ and math/
(ignored by git) and replaces p9quickjs.c, p9time.c, p9math.c, and test.c
with their preprocessed forms.  Keep the raw copies elsewhere if you want to
edit them; this script is a build bridge, not the long-term source form.
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ENGINE_FILES = [
    "quickjs.c", "quickjs.h", "quickjs-atom.h", "quickjs-opcode.h",
    "cutils.c", "cutils.h", "libregexp.c", "libregexp.h",
    "libregexp-opcode.h", "libunicode.c", "libunicode.h",
    "libunicode-table.h", "dtoa.c", "dtoa.h", "list.h",
]


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, text=True, **kw)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True,
                    help="generated9 sys/src/cmd/quickjs directory")
    ap.add_argument("--plan9", default="/home/scott/Repo/9front",
                    help="9front source tree (for u.h/libc.h/stdio.h)")
    ap.add_argument("--out", default=".",
                    help="libquickjs directory (default: cwd)")
    ap.add_argument("--cpp", default="cpp")
    args = ap.parse_args()

    src = Path(args.source).resolve()
    plan9 = Path(args.plan9).resolve()
    out = Path(args.out).resolve()
    engine = out / "engine"
    math = out / "math"
    engine.mkdir(exist_ok=True)
    math.mkdir(exist_ok=True)

    if not (src / "quickjs.c").is_file():
        print(f"preprocess-native: no quickjs.c under {src}", file=sys.stderr)
        return 2
    for hdr in ("sys/include", "amd64/include"):
        if not (plan9 / hdr).is_dir():
            print(f"preprocess-native: missing {plan9 / hdr}", file=sys.stderr)
            return 2

    for name in ENGINE_FILES:
        shutil.copy2(src / name, engine / name)
    # Native time branch: use p9time.c's localtime_r/tm_gmtoff.
    q = (engine / "quickjs.c").read_text()
    q = q.replace("#if defined(_WIN32) || defined(PLAN9)",
                  "#if defined(_WIN32)")
    (engine / "quickjs.c").write_text(q)
    for p in src.glob("math/*.c"):
        shutil.copy2(p, math / p.name)
    for p in src.glob("math/*.h"):
        shutil.copy2(p, math / p.name)
    libm = math / "libm.h"
    if libm.is_file():
        libm.write_text(libm.read_text().replace("long double", "double"))

    cpp = [
        args.cpp, "-P", "-undef", "-DPLAN9=1",
        "-U__linux__", "-U__GLIBC__", "-U__APPLE__", "-U__FreeBSD__",
        "-U_WIN32", "-U_WIN64", "-U__GNUC__", "-U__clang__",
        "-U__SIZEOF_INT128__",
        "-nostdinc", f"-I{out / 'compat'}", f"-I{out}",
        f"-I{engine}", f"-I{math}",
        f"-I{plan9 / 'sys/include'}", f"-I{plan9 / 'amd64/include'}",
    ]

    files = sorted(engine.glob("*.c")) + sorted(math.glob("*.c"))
    files += [out / n for n in ("p9quickjs.c", "p9time.c", "p9math.c", "test.c")]

    for path in files:
        if not path.is_file():
            print(f"preprocess-native: missing {path}", file=sys.stderr)
            return 2
        r = subprocess.run(cpp + [str(path)], capture_output=True, text=True)
        if r.returncode:
            print(f"preprocess-native: cpp failed for {path}\n{r.stderr}",
                  file=sys.stderr)
            return 1
        s = r.stdout
        s = re.sub(r"\binline\b", "", s)
        s = re.sub(r"\[static\s+(\d+)\]", r"[\1]", s)
        # 6c does not know abort() is noreturn.
        s = s.replace(
            """    default:
        abort();
    }
}
static BOOL JS_AtomIsString""",
            """    default:
        abort();
        return JS_ATOM_KIND_STRING;
    }
    return JS_ATOM_KIND_STRING;
}
static BOOL JS_AtomIsString""")
        s = s.replace(
            """    default:
        abort();
    }
}
static JSValue js_dataview_setValue""",
            """    default:
        abort();
        return js_mkval(JS_TAG_UNDEFINED, 0);
    }
    return js_mkval(JS_TAG_UNDEFINED, 0);
}
static JSValue js_dataview_setValue""")
        path.write_text(s)

    print("preprocess-native: wrote preprocessed C under", out)
    print("preprocess-native: now run: mk && mk test")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
