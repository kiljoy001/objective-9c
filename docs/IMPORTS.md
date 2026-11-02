# o9 imports - design (July 2026)

Status: BUILT (July 2026). The supported form is `import "path";`.
The imported file's full body is spliced into the compilation and
transpiled. The subtree boundary is enforced. Tests: `e2e_import`
(`import` runs), `stdlib/e2e_import_stdlib.o9` (root-style
`import "stdlib/process.o9"` with process's own bare imports),
`production_ast.rc` import escape fixtures (`../` rejected), and a
negative `from ... import` fixture. Selective import was removed until it
can honestly filter declarations.

Compile with a PATH for imports: `o9c FILE.o9` (imports resolve relative
to FILE's dir). `o9c < FILE.o9` still works (resolves relative to cwd).

## Principle: the path is the path (anti-Python)

Python's package system is the anti-pattern we reject: `__init__.py`
marker files whose mere presence changes whether a dir is a package,
`sys.path` search, implicit vs explicit relative imports, namespace
packages - a pile of implicit, stateful, action-at-a-distance
resolution. You cannot tell from an import statement what file actually
opens; it depends on cwd, PYTHONPATH, installed site-packages, and which
`__init__.py` files exist.

o9 imports are HONEST:

- The import string is a real filesystem path. What you write is what
  opens. The importing file's directory is the primary base; the only
  fallbacks are project-root locations for the same spelled path. There
  is no environment path variable, package list, or hidden state.
- **NO `__init__`-style marker files.** A directory is a directory; a
  file is a file. o9 never scans a directory deciding what is
  "importable." You point at a FILE; it reads THAT file.
- Grouping/namespacing is `module` (in the source, visible), NOT a
  filesystem convention.
- The dependency is legible from the text alone: `import "path";` names
  the exact file. No resolver search is needed to know what opens.

This matches the rest of o9's honesty theme (try/defer make control flow
visible; super() is explicit; errors are values). Import makes
dependencies and their locations visible.

## Path resolution + the project boundary (firm rule)

An import path resolves **relative to the directory of the importing
file** first, so a module's own bare imports (`import "buffer.o9";`)
always find its neighbours. If that file does not exist, the compiler
falls back to the entry source directory and then the invocation cwd.
This fallback is what lets a root program write
`import "stdlib/process.o9";` while `process.o9` itself keeps bare
`import "buffer.o9";`. There is no environment variable, installed
package list, or `__init__`-style directory scanning.

The path may only reach the importing directory or its subdirectories.
Never upward, never sideways, never absolute:

- `import "db.o9";`               same folder            OK
- `import "lib/db.o9";`           a subfolder            OK
- `import "../other/db.o9";`      escapes subtree        ERROR
- `import "/usr/lib/foo.o9";`     absolute/system path   ERROR

Enforcement (compile time): reject `..` that climbs above the
importing directory, canonicalize the path (fold `.`/`..`), then try the
importing directory, its parent directories, the entry source directory,
and the invocation cwd. If none contains the file, report
`cannot open import`. File identity is checked as well as path, so a
module reached through a symlink and through its real path is spliced only
once.

Why: a project is a self-contained subtree. All of a project's
dependencies live inside the project - move the folder, it still builds,
no machine-specific paths. And it's a real boundary: the import graph
physically cannot escape the project root (no ../../../ traversal into
other projects or system files). Better than Python (imports from
anywhere on sys.path) and C #include (searches system paths).

## One honest verb: `import "path";`

`import "path";` pulls the file's declarations (full bodies) into the
compilation.

There is deliberately NO `from "path" import A, B;`. It was tried and
removed: because the mechanism splices the WHOLE file, a `from` that
named A, B produced output IDENTICAL to `import` - the name list was a
lie. o9 does not ship a verb that overpromises. `from` is rejected with:
"'from ... import' is not supported; use `import "path";`. Selective
import is not yet implemented." A real filtering `from` (splice only the
named decls + their transitive dependency closure) can return WHEN it
actually filters - not before.

## Mechanism: splice into one compilation

Decided: the compiler reads the imported file, strips any imported
`main { ... }`, splices the remaining declarations into THIS compilation,
and transpiles them into the SAME output C. One o9c invocation, one .c,
one binary. No separate compile/link step, no build convention needed.
(Recompiles imported code each build; fine for now.)

The key bug this fixed: prescan registered imported names with nil
members. Real import brings the complete source text, so classes have
members and method bodies when typecheck and codegen run.

## Build steps

Implemented:

1. `import STRINGLIT ;` only.
2. Path resolution + project-subtree boundary check.
3. Full source splice of imported declarations, with imported `main`
   stripped so only the root file owns program entry.
4. Tests: two-file import, rejected `from`, rejected path escape, and
   legacy imported `func main()` failure.
