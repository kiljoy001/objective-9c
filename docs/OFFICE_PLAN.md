# OFFICE_PLAN.md — the Office Plan suite; Office Sheets as the first program

Status: **design / hypothetical / not yet implemented**. A product-level view of
the work captured in `DRAWGRID.md` and `docs/TABULA.md`. Nothing here is built;
this doc exists so the shape of the thing is settled before the building starts.

Related: `docs/DRAWGRID.md` (the UI primitive), `docs/TABULA.md` (the substrate),
`docs/NAMESPACE.md`, `o9c/grammar.d/50-app-facade.y` (the facade that serves a
tabula as 9P).

---

## 1. Pitch

**Office Plan** is an office suite for Plan 9 — not a set of applications that
share a file format, but a set of **views over one substrate**: every document
is a signed `tabula` served on the 9P namespace, and every "application" is a
facade (o9c-generated 9P server) that renders a constrained view of it. The
suite is unified the way Plan 9 is unified: by the namespace, not by a vendor.

**Office Sheets** is the first program — the "Plan 9 VisiCalc." A worksheet
whose cells are typed and signed, whose references are 9P paths, whose
recalculation is dependency-graph propagation, and whose whole document is a
grepable text file you can also mount from across the grid.

One line: **the spreadsheet language you already know, on the substrate it
always should have had.**

---

## 2. Lineage and thesis

The spreadsheet formula **language** matured by about 1990 and is the lingua
franca of business — every accountant writes `=SUM(A1:A10)*1.1`. The spreadsheet
**substrate** did not mature; it is still the VisiCalc-era model:

- a flat 2D grid (so hierarchical and relational data are forced into it),
- IEEE-754 float with silent coercion (so `0.1+0.2 ≠ 0.3`),
- grid-coordinate addressing (so cross-sheet relationships need `VLOOKUP` soup),
- a sealed, opaque, single-user file (so sharing means email, and provenance
  means "trust me"),
- no constraints (so a typo in one cell silently breaks a model).

The thesis of Office Sheets: **steal the language, reject the substrate.** Keep
the grammar, the precedence, the named references, the core functions, and the
familiar feel; replace the grid, the float, the coordinates, the opacity, and
the ephemerality with the Plan 9 / libtab substrate. The language is the good
part. The substrate is what we are escaping.

| era | program | contribution |
|---|---|---|
| 1979 | VisiCalc | the grid, A1, cell-reference-as-relationship, relative/absolute "replicate" |
| 1983 | Lotus 1-2-3 | `@`-functions, macros, the IBM-PC scale |
| 1985– | Excel | real operator precedence (fixing VisiCalc), named ranges, the function library, dependency-DAG recalc |
| — | **Office Sheets** | the same language on path references, typed decimal cells, signed provenance, a 9P namespace |

---

## 3. The suite: Office Plan

Plan 9's founding idea is "everything is a file you can walk, locally or over
the wire." Office Plan's claim is that **office documents are not an exception**:
a worksheet, a memo, a presentation, a contact list, a project plan are all, at
bottom, structured records — and a structured record is a `tabula`, and a
`tabula` is a namespace. So the suite is not N apps with N formats; it is N
facades over one substrate, composable by `bind`.

- **Office Sheets** — typed, signed, path-referenced worksheets (this doc).
- *Office Words* (speculative) — a memo/doc program; a document is a tabula of
  styled text blocks, paragraphs as rows, structure as nesting. Same grid
  primitive, `outline`/`form` display modes.
- *Office Slides* (speculative) — a deck is a tabula of slides; a slide is a
  sub-tabula of blocks. `form`/`grid` modes; the renderer is one more facade.
- *Office Mail* / *Contacts* / *Planner* (speculative) — each a tabula on the
  namespace, each a thin facade.

The unifying rule: **every Office Plan program is a constrained view over signed
tabulae, served as 9P.** No program owns its data; the data is first-class on
the namespace, the program is one lens. This is what lets the suite compose:
a sheet can reference a Contacts cell by path; a memo can `bind` a sheet's
summary sub-grid; mail can plumb a row into a sheet. The integration problem
that a conventional office suite spends its life on disappears because there
was never a boundary to integrate across.

The rest of this doc is about the anchor program.

---

## 4. Office Sheets — the program

### 4.1 The model (storage)

A sheet is a `tabula` (libtab): an ndb-shaped, grepable text file with a
`schema=` tuple and typed columns. Cells carry inline provenance:

- **`HASHED:`** — BLAKE2b content hash (integrity; content-addressed dedup).
- **`SIGNED:`** — Ed25519 signature (tamper-evidence + non-repudiation; the
  cell knows its origin).
- plain cells stay plain — only the cells that need provenance carry crypto.

The file is grepable (`grep '^row=txn-001' ledger.tab`), `diff`-able, and
*also* a live 9P namespace when served by the facade. **The .tab file is the
workbook; there is no second serialization.** Storage and protocol are one
artifact. (See `docs/TABULA.md`, `libtab/libtab.h`.)

### 4.2 The view (layout)

The recursive grid from `DRAWGRID.md`: a `DrawGrid` whose cells hold
`DrawWidget`s (so a cell can be a sub-grid, a `DrawTextInput`, a signed field),
with display modes:

| mode | use |
|---|---|
| `grid` | browse / navigate the hierarchy |
| `flat` | volume (10k+ rows) — reuse `DrawTable` |
| `outline` | read as an indented tree |
| `tree` | nested boxes / mind-map |
| `graph` | **draw the references as edges** — see the relational structure |
| `form` | enter / edit one record's fields |

Constraints live in the model (the tabula schema), so **every mode is equally
constrained — validate once, render many.** You cannot draw an invalid invoice
in any mode, because no mode owns the validation. Layout is *derived* by the
renderer (not stored), so there is no spatial state for concurrent writers to
conflict on — multi-user comes from 9P, free.

### 4.3 The verbs (interaction)

The Plan 9 three-button set, uniform across all display modes (see
`DRAWGRID.md` §5):

- **B1** select a cell (sweep = cross-hierarchy multi-select).
- **B2** operate — a command menu **generated from the selected cell's type**
  (data → cut/paste/snarf; signed → verify/provenance/re-sign; code → run;
  sub-grid → open/bind/commit). The schema is the verb palette.
- **B3** chase — follow a reference to its target (descend a sub-grid, jump to
  a referenced cell, chase a signer).
- **chords** — snarf carries a signed cell's identity; paste runs the
  verification membrane (tampered cells rejected on paste). The cut/paste chord
  becomes verified-record transfer between tabulae.

### 4.4 The computation (formulas)

The "Plan 9 VisiCalc" core. Detailed in §5.

### 4.5 The architecture in one line

**model** = `tabula` (libtab: schema + `signed:`/`hashed:` cells)
· **view** = display mode (`DrawWidget` renderers)
· **verb** = 3-button (uniform)
· **computation** = the formula layer (§5).

Four independent axes; uniform model + uniform verbs + uniform engine, variable
views. The recursion is the same at every layer (UI cell holds a grid; tabula
field holds a sub-tabula; over 9P that sub-tabula is mounted from another node —
cross-node composition shows up as a sub-grid cell).

---

## 5. The formula layer

### 5.1 Steal the language

| steal | from | note |
|---|---|---|
| `=` grammar, operators, parentheses | Excel | universal; zero learning curve |
| **real operator precedence** | Excel | fixes VisiCalc's bug (`3+5*4` = 23, not 32) |
| named references | Excel | `=revenue * tax_rate`; resolves to a schema-published path binding |
| core function library | Excel | math, text, date, logical, aggregation (~30, curated) |
| dependency-DAG recalculation | Excel | fixes VisiCalc's row/col-order recalc |
| typed propagated errors | Excel `#N/A`/`#REF!` | rendered through the o9 type system, not `#`-strings |
| `LET` / `LAMBDA` | modern Excel | the bridge from a formula to a `CT_CODE` cell |

### 5.2 Reject the substrate

| reject | why | what instead |
|---|---|---|
| **A1 coordinate addressing** | wrong addressing for a namespace | **9P paths**: `/ledger/txn-001/amount`. A1 is only a rendering label in `flat` mode |
| **IEEE-754 float + silent coercion** | `0.1+0.2 ≠ 0.3`; silent string→number bugs | **typed decimal/currency cells, explicit coercion** — Frankston's VisiCalc instinct, which was right |
| **`VLOOKUP`/`XLOOKUP`/`INDEX`+`MATCH`** | the lookup category is a workaround for joins in a flat grid | **a reference *is* the join** — path-reference the related cell; the whole category evaporates |
| implicit intersection / spilled-array quirks | artifacts of the 2D-grid evaluation model | not needed in a typed namespace |
| ~400-function sprawl | the long tail is poor code-in-disguise | curated core + `CT_CODE` escape hatch (LET/LAMBDA is the ramp) |
| ephemeral, no-provenance | a result has no history/trust | signed results; a formula reading a tampered source fails verification *during recalc* |

### 5.3 References are paths (the central reframe)

In Excel a reference is a grid coordinate. In Office Sheets a reference is a
**9P path**. Relative vs absolute is preserved as a *concept*, changed as
*syntax*:

- absolute: `/ledger/txn-001/amount`
- relative: `../amount`, `sibling(amount)`
- the `$` lock becomes an *anchor-this-path-component* operator
- A1 survives only as a label the `flat` renderer prints in the gutter

### 5.4 Recalculation is reference-graph propagation

The dependency DAG is **already the data**: the `CT_VARU` cell-to-cell reference
edges *are* the dependency edges. Recalc = propagate values through the
reference graph. No second structure is built. And because the same edges are
what `graph` display mode draws and what B3 chases, **one reference structure
serves four uses**: it is the value dependency, it is the `CT_VARU` edge, it is
the line in `graph` mode, it is the B3 navigation target.

### 5.5 Provenance runs through recalc

A cell's *result* may itself be `signed:`. A formula that reads a tampered
source cell does not return a wrong number — it returns a **verification error**
that propagates like any other typed error. The crypto membrane is part of
evaluation, not a check bolted on after. This is what makes a recombinable,
shared worksheet safe: verification is the fitness function, applied at every
recalc.

### 5.6 The escape hatch is real code

When a formula outgrows the curated library, it doesn't hit a wall: wrap it in
`LAMBDA`, then let it become a `CT_CODE` cell — actual o9 code in a cell, with
full access to the language. The formula surface and the code layer are one
continuum, not two modes. This is the thing Excel never had and the thing that
ends "you can't do that in a spreadsheet."

---

## 6. How a sheet lives on the grid

- **stored** as `ledger.tab` — grepable ndb text, `diff`-able, version-controllable.
- **served** by the o9c facade as a 9P tree (`50-app-facade.y`: `Srv` + `Tree`
  + `o9app_exports_dir`). The same bytes are a file and a namespace.
- **shared** by mounting — no email, no "send a copy"; you `bind` someone
  else's exported sheet, or a cell references their path over ygg+aan.
- **composed** — an invoice sheet references a vendor's price sub-grid (a
  mounted foreign tabula); the reference is a path; the price cell is signed
  by the vendor; if the vendor tampers, your invoice's recalc surfaces a
  verification error at that cell. **Provenance crosses organizational lines
  without a trust reset.**
- **audited** — every signed cell carries its signer; walk the reference graph
  to reconstruct where any number came from.

This is the Contoso application layer (#36) made concrete: business records as
signed tabulae on the namespace, the office apps as facades over them.

---

## 7. Honest scope, non-goals

- **Not a relational database.** Path references *are* joins for the
  cell-reference case; `graph` mode shows relationships; but this is not a SQL
  engine. Bulk analytics across many sheets is a separate reporting client that
  walks many mounted tabulae — faithful to the substrate (local, no global
  coordinator), not a missing feature.
- **Not free-form.** Deliberately. The TreeSheets canvas is the wrong face for
  record-keeping; Office Sheets is schema-driven. A free-form organizer may be
  a *later* Office Plan program (for the thinking/planning 20%), but Sheets is
  the constrained 80%.
- **Hardware.** The 3-button model degrades to modifier-chord (2-button),
  context menu (1-button/touch). B2's type-driven menu is the discoverable
  path; chords are the power-user fast path.
- **Layout is derived, not stored.** A user's spatial arrangement is a personal
  facade view; the shared canonical thing is the typed data tree. (The genome
  is shared; the arrangement is per-organism.)
- **Float is gone on purpose.** Decimal is slower than float and that is fine;
  for financial data it is *correct*, and that is the one decision an accountant
  cannot argue with.
- **v1 non-goals:** TLS on the relay path, a full function library, a query
  language, the speculative sibling apps (Words/Slides/Mail).

---

## 8. Implementation phases

Anchored on `DRAWGRID.md` §8; Office Sheets is the product that exercises those
primitives:

1. **`DrawGrid`** — cell = `DrawWidget`, grid layout, zoom/collapse.
2. **`renderStyle`** — grid + flat, then outline, then form.
3. **3-button verbs** — `routeMouse` enum, B2 type-driven menu, B3 chase.
4. **`graph` mode** — render references as edges.
5. **9P binding** — sub-grid cell ← mounted sub-tabula (cross-node composition).
6. **Formula engine** — grammar, path references, dependency-DAG recalc, typed
   decimal, curated function core, signed-result verification in-recalc.
7. **`LET`/`LAMBDA` → `CT_CODE` bridge.**
8. **Chords + provenance-carrying snarf** — verified record transfer.

Phases 1–5 are `DRAWGRID.md`; 6–8 are the Office Sheets computation layer on
top. Phase 6 is where "Plan 9 VisiCalc" becomes real.

---

## 9. Open questions

- **2D grid → 1D directory convention** for 9P serving (rows = records, columns
  = fields? or a relation view synthesized by the facade). Must be settled
  before phase 5. (See `DRAWGRID.md` §9.)
- **Formula syntax for path references** — exact form of relative/absolute path
  refs and the `$`-anchor operator; whether to allow a hybrid A1-in-flat-mode
  for muscle memory.
- **Recalc semantics across a mounted foreign sheet** — partial vs full, caching,
  what happens when the remote cell changes (push vs pull; aan sessions).
- **Where `renderStyle` lives** — per-widget or per-screen (likely per-screen for
  business apps, per-widget for exploratory).
- **The sibling apps** — when, and whether Words/Slides reuse `DrawGrid` or get
  their own facade shapes.

---

## 10. In-repo references

- `docs/DRAWGRID.md` — the UI primitive this program is built from
- `docs/TABULA.md`, `docs/NAMESPACE.md`, `docs/CONCURRENCY.md` — the substrate
- `stdlib/draw.o9:1876/3276/4424` — `DrawWidget`/`DrawTable`/`DrawPanel`
- `o9c/grammar.d/50-app-facade.y` — the facade that serves a tabula as 9P
- `libtab/libtab.h`, `libtab/tab_persist.c` — signed/hashed cells, content
  addressing (note: the 9P *client* path is `#ifdef __GNUC__`, OFF on native
  Plan 9; the 9P *server* over a tabula implied here is the direction, not the
  existing client blob-write)
- Task #36 — the Contoso application layer; Office Sheets is its first concrete
  program