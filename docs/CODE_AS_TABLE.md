# Compile-Time Code Tables

> **Scope note (July 2026):** this is a future *compile-time, local*
> macro design. It is not runtime self-modification, runtime eval, live
> method-set editing, or a wire format. Any earlier notion here of
> transmitting code tables to another node to be compiled or run is
> **retired**: rehydrating sender-supplied structure into behavior is
> RCE in disguise (see `TABULA.md`). Only Tabulae of *data* travel the
> network, and they travel inert.

## Thesis

o9 can eventually expose the compiler's surface syntax as a table so
trusted build-time filters can transform a program before typecheck.
This borrows the useful part of Lisp-style macros — code transformation
as data transformation — without making runtime objects rewrite their
own behavior.

The Plan 9-shaped translation is:

- runtime invocation as *lines* — done: the `send` builtin fires the
  same ctl line the shell writes (e2e_send.o9);
- program structure as *tables* — this design: the compiler's AST as a
  libtab table that ordinary programs can transform between parse and
  typecheck.

A macro is then any program that maps code-table → code-table.  Not a
new sublanguage, not an interpreter in the compiler: a filter in a
pipeline, which is what this OS already knows how to compose.

## What exists today

- `o9c -ast` dumps the parse tree as indented text after typecheck
  (production_ast.rc asserts against it).  The tree is already
  serializable; it just isn't canonical, keyed, or re-readable.
- The private method table (`o9_runtime.c`) proves that table-shaped
  metadata works well in o9. It is runtime dispatch metadata, not a
  public writable code representation and not a mechanism for editing
  method sets at runtime.
- `Tabula` is now a first-class runtime-backed o9 type for `.tab` data
  (`write`, `query`, `read`, `flush`, iteration, and network
  sync/push). Code-as-table has not been built on top of it yet.
- libtab files are text: a code table is cat-able, grep-able,
  diff-able, and signable like every other value in the stack.

## The Code Table

One row per AST node.  `Node` is {type, flags, line, name, typename,
qname, left, right, params, next} — everything else (`typeinfo`,
`cname`) is derived by typecheck/codegen and deliberately NOT
serialized: macros operate on surface structure, and the typechecker
re-derives semantics after expansion.

Columns:

| col      | meaning                                            |
|----------|----------------------------------------------------|
| id       | node id, the row key (dense ints, pre-order)       |
| parent   | id of the owning node, empty for roots             |
| edge     | which pointer owns this node: left, right, params  |
| seq      | position along the sibling (`next`) chain          |
| type     | node type name ("NClass", "NMethod", ...)          |
| flags    | numeric flags word                                 |
| line     | source line (provenance; survives transformation)  |
| name     | Node.name (libtab cell quoting handles any text)   |
| typename | Node.typename                                      |
| qname    | Node.qname                                         |

Pointer order becomes (parent, edge, seq) — tables have no pointer
identity, so sibling chains are explicit sequence numbers.  String
literals with spaces/newlines are safe because libtab cell encoding
already quotes arbitrary text.

## Compiler seams

Two flags beside the existing `-ast`:

- `o9c -T < prog.o9 > prog.code.tab` — parse only, emit the code
  table, exit.  (Pre-typecheck, unlike `-ast`: macros must see the
  program before semantic analysis, and expansion output gets checked
  afterward anyway.)
- `o9c -t < prog.code.tab > prog.c` — skip lexer/parser, rebuild the
  Node graph from rows, then run the normal typecheck + codegen.

These flags are design targets, not current command-line options.

The invariant that makes the whole design testable:

    o9c -T < x.o9 | o9c -t   ≡   o9c < x.o9

for every program in the e2e corpus.  That roundtrip identity is the
Phase-2 gate (`mk table-test`), and it is what licenses trusting the
table as *the* program rather than a lossy view of it.

## The Macro Pipeline

    o9c -T < prog.o9 | expand_secret | derive_accessors | o9c -t > prog.c

Each stage is an ordinary program reading a table and writing a
table — rc, awk, or o9 itself. These stages run in a trusted build
namespace chosen by the developer. They do not run because an app
received a file under `imports/`, and they are not part of the
generated runtime.

Two properties Lisp macros don't have:

1. **Post-expansion typechecking.**  Expansion output goes through the
   full semantic pass; a macro cannot smuggle an ill-typed program
   past the compiler.  Errors cite the `line` column, which macros
   preserve (or set to the macro's own provenance), so diagnostics
   point at the source that *caused* the code, not the code.
2. **Attested expansion.**  A code table is one text value, so the
   crypto builtins apply as-is: `hash` the input table, `sign` the
   output table, and a build can `verify` who expanded what before
   codegen runs.  Macro provenance becomes a checkable chain instead
   of a build-log anecdote.

## Hygiene and limits (v1)

- Unhygienic, like early Lisp: macro-introduced names can capture.
  Convention: macros prefix generated identifiers (`__m_...`) and
  allocate node ids above 1<<20 so origin stays visible in the table.
- No runtime eval and no in-process macro interpreter. Staging is
  strictly compile-time, and the typechecker stays the sole authority
  on what compiles.

## First macro: secret fields

The proof-of-design macro ties into the crypto stdlib.  Today the
Vault pattern (TUTORIAL.md) is hand-written; with the table stage,

    class Account {
        secret string apitoken;
    }

is rewritten by `expand_secret` into what e2e_crypto.o9 does by hand:
the stored field becomes the AEAD blob, and accessors take the key:

    class Account {
        string apitoken__blob;
        method void seal_apitoken(string key, string v)
            { apitoken__blob = encrypt(key, v); }
        method string open_apitoken(string key)
            { return decrypt(key, apitoken__blob); }
    }

A language feature shipped as a table transformation: nothing added
to the grammar, nothing hardcoded in codegen, fully typechecked after
expansion — and removable by deleting one pipeline stage.

## Staging

1. **-T**: emit rows (rework `dump_ast` into `dump_table`; move the
   call site before typecheck).  Assert well-formedness: every parent
   exists, (parent, edge, seq) unique.
2. **-t**: rows → Node graph (two passes: allocate by id, then link).
   Gate: roundtrip identity over the whole e2e corpus, `mk table-test`.
3. **expand_secret** as the first macro + e2e case; TUTORIAL section.
4. Later, if wanted: use the existing `Tabula` object for code-table
   editing, add signed-expansion verification in mk rules, and build a
   pretty-printer (table → .o9 source) for debugging macros.

## Naming: Tabula

The language-level type is **Tabula**, not Table or Tab.  "Tab" reads
as the whitespace character; "Table" quietly promises relational
algebra (joins, SQL semantics) that libtab deliberately does not
have.  A tabula is the writing surface itself — rows written to a
slate, searched and iterated, nothing heaped on top — which is what
this storage actually is.  The lineage decays naturally through the
layers: Tabula (language) → .tab (files) → libtab (C library), the
same relationship string has to char*.
