# o9 grammar chunks

`grammar.y` is generated from these ordered chunks by the root `mkfile`.
Edit these files, not `../grammar.y`.

The order is significant:

- `00-*` through `03-*`: yacc prologue, shared compiler state, helpers, and declarations.
- `10-*`: yacc grammar rules.
- `20-*` through `30-*`: AST construction and lexer.
- `40-*` through `50-*`: code generation and app facade emission.
- `60-*` through `70-*`: prescan and typechecking.
- `80-*` through `99-*`: diagnostics, imports, C dependencies, and compiler main.

The split is intentionally mechanical. Keep behavior-preserving movement
separate from refactors that change helper boundaries.
