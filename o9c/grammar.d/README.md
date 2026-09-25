# o9 grammar chunks

`grammar.y` is generated from these ordered chunks by the root `mkfile`.
Edit these files, not `../grammar.y`.

The order is significant:

- `00-*` through `03-*`: yacc prologue, shared compiler state, helpers, and declarations.
- `10-*`: yacc grammar rules.
- `20-*` through `30-*`: AST construction, source-location tracking, and lexer.
- `40-*` through `50-*`: code generation and app facade emission.
- `60-*` through `70-*`: prescan and typechecking.
- `80-*` through `99-*`: diagnostics, imports, C dependencies, and compiler main.

The split is intentionally mechanical. Keep behavior-preserving movement
separate from refactors that change helper boundaries.

`21-source-map.y` owns original file/line tracking across import splicing and
the `cprint` output writer. All generated C, including emission in `02-*`
and `91-*`, must use that writer. AST and diagnostic output remain separate.
Use `mk plan9-c-test` and `mk source-map-test` to check native C conventions
and original-source locations in compiler diagnostics and Acid.
Statement annotations and numbered original-source comments make the generated
C readable alongside the o9 logic. Source snapshots are captured before import
rewriting and are emitted only as comments, with comment terminators escaped.
