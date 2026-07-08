# o9 imports — design (July 2026)

Status: DESIGN + partial current state. The current `import "path";`
is half-built (registers class NAMES with nil bodies via the prescan —
so an imported class exists but has no members and no generated code;
"'X' has no member 'm'" and nothing to link). This doc is the intended
real design. Not fully built yet.

## Principle: the path is the path (anti-Python)

Python's package system is the anti-pattern we reject: `__init__.py`
marker files whose mere presence changes whether a dir is a package,
`sys.path` search, implicit vs explicit relative imports, namespace
packages — a pile of implicit, stateful, action-at-a-distance
resolution. You cannot tell from an import statement what file actually
opens; it depends on cwd, PYTHONPATH, installed site-packages, and which
`__init__.py` files exist.

o9 imports are HONEST:

- The import string is a real filesystem path. What you write is what
  opens. No search list, no path variable, no hidden state.
- **NO `__init__`-style marker files.** A directory is a directory; a
  file is a file. o9 never scans a directory deciding what is
  "importable." You point at a FILE; it reads THAT file.
- Grouping/namespacing is `module` (in the source, visible), NOT a
  filesystem convention.
- The dependency is legible from the text alone: `from "path" import
  A, B;` names the file AND the names — no need to run a resolver to
  know what a file depends on.

This matches the rest of o9's honesty theme (try/defer make control flow
visible; super() is explicit; errors are values). Import makes
dependencies and their locations visible.

## Path resolution + the project boundary (firm rule)

An import path resolves **relative to the directory of the importing
file** (NOT the cwd — location-stable: the path means the same thing no
matter where o9c is invoked).

AND it may only reach that directory or its SUBDIRECTORIES. Never
upward, never sideways, never absolute:

- `from "db.o9" import X;`        same folder            OK
- `from "lib/db.o9" import X;`    a subfolder            OK
- `from "../other/db.o9" ...;`    escapes subtree        ERROR
- `from "/usr/lib/foo.o9" ...;`   absolute/system path   ERROR

Enforcement (compile time): resolve `<importing-dir>/<import-path>`,
canonicalize (fold `.`/`..`), and verify the result is still a
descendant of the importing file's directory. If a `..` climbed above
the base, reject: "import path escapes the importing file's directory;
imports must stay within the project subtree."

Why: a project is a self-contained subtree. All of a project's
dependencies live inside the project — move the folder, it still builds,
no machine-specific paths. And it's a real boundary: the import graph
physically cannot escape the project root (no ../../../ traversal into
other projects or system files). Better than Python (imports from
anywhere on sys.path) and C #include (searches system paths).

## Two forms (Python-like, kept deliberately)

- `import "path";` — import ALL public decls from the file (import-all).
- `from "path" import A, B;` — selective: only the named decls (+ their
  transitive dependencies — if A uses a struct Point from the same file,
  Point comes too even if unnamed).

## Mechanism: splice into one compilation

Decided: the compiler FULLY PARSES the imported file (not just a name
prescan), pulls the named decls — and the decls THEY transitively depend
on — into THIS compilation's class table, and transpiles them into the
SAME output C. One o9c invocation, one .c, one binary. No separate
compile/link step, no build convention needed. (Recompiles imported code
each build; fine for now.)

The current gap this fixes: prescan registers names with nil members
(mk(type, cn, nil, nil, nil)). Real import must bring the COMPLETE class
node (members + method bodies) so it both typechecks and generates code.

## Build steps

1. This doc.
2. Grammar: `from STRINGLIT import name_list ;` (new form) alongside the
   existing `import STRINGLIT ;`.
3. Path resolution + project-subtree boundary check (the firm rule).
4. Full-parse + splice of imported decls (bodies, not just names) into
   the compilation; transitive-dependency closure for the selective form.
5. Tests: two-file import (from + import-all), a negative test for a
   path that escapes the subtree.
