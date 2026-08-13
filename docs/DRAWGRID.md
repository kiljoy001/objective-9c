# DRAWGRID.md — Recursive Grid as a UI Primitive

Status: **design / not yet implemented**. Captures the outcome of a design
thread so it survives until someone builds it. All primitives referenced are
written in o9 and live in `stdlib/draw.o9`; this doc proposes additions to that
library and to the o9c facade binding.

Related: `docs/TABULA.md`, `docs/NAMESPACE.md`, `docs/CONCURRENCY.md`,
`docs/STDLIB_PLAN.md`, `o9c/grammar.d/50-app-facade.y`, `libtab/`.

---

## 1. Motivation

The business-application layer (#36, the Contoso apps) needs a UI primitive
that is:

- **hierarchical** — records nest (org → region → quarter → invoice → line),
  and the legacy flat 2D grid forces that into awkward joins;
- **constrained** — business data entry must validate (required fields, types,
  sums reconcile), not be a free-form canvas;
- **shared** — multiple users / roles, concurrent, audited;
- **multi-faced** — the same data wants several faces (grid to browse, outline
  to read, form to enter, graph to see relationships), without re-validation.

Two existing tools bracket the space:

- **VisiCalc (1979)** gave the durable metaphor: a grid of rows/cols where a
  cell *references* another and recalculates. "Programming by example" — point
  at a cell to reference it. Every spreadsheet since is this grid + more.
- **TreeSheets** (Wouter van Oortmersen) generalized the grid to a *recursive
  grid-of-grids*: a `Cell` can contain another `Grid`, to any depth, with typed
  cells (`CT_DATA`/`CT_CODE`/`CT_VAR`) and references between them. Its
  display has multiple render styles (standard grid, horizontal/vertical blob,
  lines) and zoom/relative-size to collapse subtrees.

TreeSheets solved the **shape** problem (recursion + typed cells + refs) but
sits on the wrong **substrate**: a free-form, opaque XML (`.cts`), single-user,
single-file, no provenance, no network, no constraints. That is exactly why it
is "cool but hard to use" for business work — free-form fights trustworthy
record-keeping, and a hierarchical grid hides the *relational* (many-to-many)
structure that business data actually has.

This doc proposes taking TreeSheets' shape and putting it on the o9 substrate:
the recursive grid becomes a **language-level UI primitive in `stdlib/draw.o9`**,
backed by a `tabula` (libtab), constrained by a schema, served over 9P by the
o9c facade, and driven by the Plan 9 three-button verb set.

---

## 2. What already exists (grounded)

The draw library is written in o9 (`stdlib/draw.o9`, ~5300 lines) and already
has nearly all the pieces:

- **`DrawWidget`** (`stdlib/draw.o9:1876`) — base class. Position/size,
  dirty/reactive flags, focus, `role`, `action`, and crucially
  `preferredWidth()`/`preferredHeight()` + `wlayoutdirty` — the
  measure/layout-propagation machinery a recursive grid needs.
- **`DrawPanel`** (`stdlib/draw.o9:4424`) — **the recursion seam.** It embeds
  `DrawWidget` *and* has `prop List<DrawWidget> children` with
  `method bool add(DrawWidget child)`. A Panel is a `DrawWidget` that holds a
  list of `DrawWidget`s. Because a Panel is itself a `DrawWidget`, **a Panel
  can contain a Panel — the tree-of-widgets recursion already exists.** It has
  `layoutVertical`/`layoutFlow`, focus routing (`routeMouse`/`routeKey`), and
  dirty propagation through children.
- **`DrawTable`** (`stdlib/draw.o9:3276`) — a flat 2D grid: `string[] cells`
  indexed `row*ncols+col`, with headers, selection (`selectedRow`), scroll. Cells
  hold **strings only** — this is the single limitation that `DrawGrid` removes.
- **`DrawTextView` / `DrawScrollText`** — text views; building blocks for an
  outline mode.
- **`DrawLabel` / `DrawButton` / `DrawTextInput` / `DrawBox`** — the leaf
  widgets a cell can host (form mode, etc.).
- **The tell:** `DrawPanel` stores its routing/layout state in
  `prop tabula routes = new tabula("draw_routes", "slot,type,x,y,w,h,...")`.
  **The UI's own internal state is already backed by a libtab `tabula`.** The
  draw library and the libtab substrate are already connected, by design.
- **Mouse API:** `routeMouse(x, y, button)` currently passes a **down/up
  state (1/0), not a three-button enum** (see `stdlib/e2e_draw_panel.o9`:
  `routeMouse(20, 64, 1)` then `routeMouse(12, 12, 0)`). So B1 exists; B2/B3
  distinction is the extension, not free.
- **Facade:** `o9c/grammar.d/50-app-facade.y` emits a 9P `Srv` with a `Tree`,
  `clone` for sessions, and `o9app_exports_dir`/`o9app_imports_dir` for
  published tabulae. **An o9 app's structure is already a directory tree.** A
  grid client that mounts any 9P tree and renders directories as grids *is* the
  recursive grid UI, with no extra storage format.

---

## 3. Proposed primitive: `DrawGrid`

A `DrawWidget` subclass; the one change that makes TreeSheets' recursion native:

- cells hold **`DrawWidget`**, not `string`:
  - `setCell(row, col, string)` — convenience for a `DrawLabel` cell (today's
    `DrawTable` behavior);
  - `setCellWidget(row, col, DrawWidget)` — a cell that *is* another widget,
    most importantly another `DrawGrid` (recursion) or any leaf widget.
- built from `DrawTable`'s row/column layout + `DrawPanel`'s container
  semantics (`children`, dirty propagation, routing);
- composes everywhere a `DrawWidget` does — grid in panel, panel in grid cell,
  grid in grid cell, any depth;
- **zoom / collapse**: a collapsed sub-grid cell reports a tiny
  `preferredWidth/Height`; the parent's `wlayoutdirty` triggers reflow. This
  reuses the existing measure/layout machinery — collapse is a layout mode of
  the recursive grid, not a new subsystem;
- **backing**: a `tabula` (schema-defined) drives cell values; a sub-grid cell
  may bind to a sub-tabula, optionally *mounted over 9P* (see §6).

```o9
# sketch — not yet implemented
DrawGrid org = new DrawGrid(0, 0, 600, 400, 3, 4);
org.setHeader(0, "region"); org.setHeader(1, "qtr"); org.setHeader(2, "invoice");
DrawGrid emea = new DrawGrid(0, 0, 0, 0, 3, 8);   # sized by parent
# ... fill emea from a mounted sub-tabula ...
org.setCellWidget(0, 0, emea);                     # a cell that IS a grid
```

### Why this is the constrained, business-viable version (not TreeSheets)

The crucial generalization is that a cell holds a `DrawWidget`, not just a
sub-grid. So a cell can be a sub-grid **or** a `DrawTextInput` with validation,
a `DrawButton` with an action, a locked/signed field. "Cell contains grid"
becomes "cell contains any typed, behavior-bearing widget." The structure is
*programmatically declared from the schema*; the user fills cells rather than
drawing them. The TreeSheets visual idea survives; the free-form pain does
not. Three failures of TreeSheets-for-business are fixed by construction:

| TreeSheets failure | `DrawGrid` fix |
|---|---|
| free-form (no constraints) | schema-driven generation — cells that exist are cells the schema permits, with its types/validation |
| layout-as-data (concurrent merge hell) | layout is **derived** by the renderer, not stored — no spatial state to conflict on; multi-user via 9P |
| single-user single-file | served over 9P; everyone mounts the same tree |
| hierarchical vs relational | `graph` display mode (§4) draws the references as edges — relational data is *shown*, not hidden |

---

## 4. Display modes (render styles over one `tabula`)

TreeSheets has render styles (`A_GS` grid, `A_V_BS`/`A_H_BS` blob, `A_LS` lines)
and the higher-level grid/outline/mind-map idiom layer. These are **multiple
renderers of one model** — exactly model/view separation, and the `tabula` is
the model. `DrawGrid` carries a `renderStyle` selector; each mode is a
`DrawWidget` view over the same `tabula`:

| mode | renderer | built from |
|---|---|---|
| `grid` (default) | `DrawGrid` — matrix, sub-grids nested in cells | `DrawTable` layout + `DrawPanel` container |
| `flat` | `DrawTable` — no nesting, for volume (10k+ rows) | already exists |
| `outline` | 1D indented tree | `DrawScrollText` + indent |
| `tree` / blob | nested boxes, spatial | `DrawBox` + `DrawPanel` nesting |
| `graph` / lines | **draw `CT_VARU` references as edges between cells** | `DrawBox` + edge lines |
| `form` / detail | one record's fields as label+input widgets | `DrawLabel`/`DrawTextInput`/`DrawPanel` |

**The constraint lives in the model, not the view.** Schema + `signed:`/
`hashed:` cells (libtab) are enforced at the `tabula`; every mode is equally
constrained — **validate once, render many.** You cannot draw an invalid
invoice in grid mode *or* outline mode *or* form mode, because none of them own
the validation.

**`graph` mode is the one that earns its keep beyond cosmetics.** A pure grid
hides the relational 80% by nesting it. `graph`/lines renders the cell-to-cell
references (`CT_VARU`) as edges: invoice → customer → account, drawn. So the
display-mode set is what lets one recursive primitive honestly cover *both*
the tree-shaped 20% (grid/outline) and the relational 80% (graph) — by
switching face, not by forcing one shape.

**Zoom / relative-size** (TreeSheets' collapse) = a sub-grid cell reporting a
tiny `preferredWidth/Height`; reflow via `wlayoutdirty`. Free of the base (§3).

---

## 5. Three-button verbs (uniform across all modes)

Plan 9's interaction philosophy is **uniform verbs across all programs**:
B1 select, B2 operate, B3 chase, plus chords for cut/snarf/paste. The recursive
grid + display modes is a system of **one model, many views**; the 3-button
model is the matching **one verb set, many targets**. So buttons and display
modes are **orthogonal axes**: the buttons stay what you *do*; the mode only
changes what you *see*. You can chase a reference in grid mode, flip to graph
to see the web, B3 an edge, flip to form to edit the arrived record — same
three buttons throughout.

- **B1 — select a cell** (already implemented via `handleMouse`/`routeMouse`).
  Sweep B1 = multi-select; sweeping across a child-grid boundary selects the
  whole child grid (TreeSheets' cross-hierarchy selection, falling out of B1
  over a recursive container). Same verb in every mode (cell / row / node /
  field).
- **B2 — operate, type-driven.** In acme B2's menu is user-extensible; here it
  is **generated from the selected cell's schema type**, so the verb palette
  *is* the type system:
  - plain data cell → Cut / Paste / Snarf
  - `signed:` cell → **Verify / Show provenance / Re-sign**
  - `CT_CODE` cell → **Run / Execute**
  - sub-grid (tabula) cell → **Open / Zoom / Bind / Commit**

  The o9 type system and the mouse menu become the same thing — the way acme
  makes "file" and "command" the same thing. The schema *is* the verb palette.
- **B3 — chase the reference.** On a cell that references another
  (`CT_VARU` edge), B3 follows it — jumps to the referenced cell, opening
  sub-grids as needed. On a sub-grid cell, B3 descends (zoom). On a signed
  cell, B3 chases to the signer's key. **B3 = walk the edge** — the navigation
  for the relational data a grid hides. `graph` mode draws those edges; B3
  traverses them. Uniform verb; the view renders the navigation.
- **Chords = verified record transfer.** Because cells are signed and
  content-addressed, the snarf buffer carries *identity*:
  - B1+B3 (snarf) a signed cell = grab its value *with hash/sig intact*;
  - B2 (paste) elsewhere = the **membrane runs on paste**: if the cell
    verifies, it is accepted into the new tabula; if tampered, rejected.

  The Plan 9 cut/copy/paste chord becomes the mechanism for moving **verified
  records between tabulae** — the horizontal-transfer / composition operation,
  with signature-as-selection firing on every transfer.
- **rio window ops → recursive panes.** In rio, B3 manages windows (New,
  Resize, Front). For the grid, the "windows" are zoomed sub-grids/panes; a
  B3-sweep tears a cell's sub-grid off into its own pane. Same gesture,
  applied recursively.

**Requires:** extend `routeMouse` to a real 3-button enum (currently down/up
only). B2/B3 wiring and the type-driven B2 menu are the actual work here.

---

## 6. How the layers compose

One line:

**model** = `tabula` (libtab: schema + `signed:`/`hashed:` cells, content-addressed)
· **view** = display mode (`DrawWidget` renderers) · **verb** = 3-button
(uniform). Three independent axes; uniform model + uniform verbs, variable
views.

The recursion is the same at every layer:

- **UI recursion** — a `DrawGrid` cell holds a `DrawGrid` (`DrawPanel` already
  nests; `DrawGrid` generalizes `DrawTable` cells from `string` to `DrawWidget`).
- **substrate recursion** — a `tabula` field can be a sub-tabula; a sub-grid
  cell binds to a sub-tabula.
- **namespace recursion** — over 9P, that sub-tabula can be *mounted from
  another node* (the facade's `o9app_exports_dir`/`o9app_imports_dir`). A grid
  cell that zooms into another node's data is `setCellWidget` on a widget bound
  to a mounted 9P tabula. **Cross-node composition shows up as visual nesting**
  — exactly the "import a published tabula" path the facade already exposes,
  now rendered as a sub-grid.

This closes the loop in the language: the recursive grid (draw lib) is the UI
primitive, the `tabula` (libtab) is the substrate, 9P (the facade) is the
network, and they are already wired together through `DrawPanel.routes`.

---

## 7. Honest scope, risks, non-goals

- **Layout is the real work.** Recursive measure/layout propagation (a
  sub-grid's preferred size feeds its parent cell; TreeSheets' auto-resize is
  non-trivial) is genuine engineering — but the plumbing
  (`preferredWidth/Height`, `wlayoutdirty`, dirty propagation through children)
  already exists. It is a layout policy to write, not a new model to invent.
- **Performance: widget-per-cell is heavy.** Use flat `DrawTable` for large
  tabular data (10k+ rows); the recursive `DrawGrid` is the
  navigation/composition view, not the volume view. Two classes, two purposes.
- **Hardware: a real 3-button mouse is rare.** Trackpads and the
  browser-over-v86 path get two buttons at best; touch gets none. The 3-button
  model is a **design discipline** (uniform verbs) that degrades: modifier-chord
  on 2-button, context/pie menu on 1-button and touch. **B2's type-driven menu
  is the discoverable path** (acme-style, lists the verbs); chords are the
  power-user fast path, not the only path — the same hierarchy Plan 9 itself
  uses.
- **Not a query engine.** `graph` mode *shows* references; it does not do
  relational joins at the cell level. Analytics across many tabulae is a
  separate reporting client that walks many mounted tabulae — faithful to how
  real genetic/systems data is processed (locally, no global coordinator), not
  a missing feature. (See `docs/TABULA.md`.)
- **Display modes are N renderers** — N pieces of layout/input code each — but
  they share the `tabula` model and `DrawWidget` base, so it is N views over
  one model, not N systems.
- **Non-goals for v1:** TLS for the relay path, graceful ctl-stop, per-cell
  provenance graph query. Those are later.

---

## 8. Suggested implementation phases

1. **`DrawGrid`** — cell = `DrawWidget`, grid layout, zoom/collapse via
   `preferredWidth/Height` + `wlayoutdirty`. (the primitive; the rest depends
   on it)
2. **`renderStyle` selector** — grid + flat first (reuse `DrawTable`), then
   outline, then form.
3. **`routeMouse` 3-button enum + B2 type-driven menu + B3 chase.**
4. **`graph` mode** — render `CT_VARU` references as edges.
5. **9P binding** — sub-grid cell ← mounted sub-tabula (compose across nodes;
   wire to the facade's exports/imports).
6. **Chords + provenance-carrying snarf buffer** — verified record transfer
   between tabulae; membrane verifies on paste.

Phase 1 alone is already a usable constrained hierarchical grid; phases 2–3
make it multi-mode and Plan-9-idiomatic; phases 4–6 make it relational and
distributed.

---

## 9. Open questions

- **2D grid → 1D directory convention** for 9P serving. A `tabula` row is a
  directory's child; its fields are files. But a grid has two axes — serving
  it as a namespace forces a convention (rows = records, columns = fields; or
  treat the grid as a relation view synthesized by the facade). This is the
  old hierarchical-vs-relational decision resurfacing at the protocol layer
  and must be settled before phase 5.
- **Layout stored vs derived.** This design chooses **derived** — layout is a
  view property, not data — which is what preserves multi-user (no spatial
  state to conflict). TreeSheets users treat spatial arrangement as semantic;
  we accept losing that as a stored concern and let a per-user facade render
  layout. The shared canonical thing is the typed data tree; the personal
  thing is the arrangement. (Biologically: the genome is shared; expression /
  tissue architecture is per-organism.)
- **Selection/zoom persistence across a mode switch.** Keep a `currentPath`
  into the `tabula` so flipping grid→outline doesn't lose your place. Small
  controller concern, not structural.
- **Where the `renderStyle` selector lives** — on `DrawGrid` (per-widget) or
  on the facade (per-screen). Likely per-screen for business apps (the app
  picks the face), per-widget for exploratory use.

---

## 10. In-repo references

- `stdlib/draw.o9:1876` — `DrawWidget` (base: measure/layout machinery)
- `stdlib/draw.o9:3276` — `DrawTable` (flat `string[] cells`; the cell type to
  generalize)
- `stdlib/draw.o9:4424` — `DrawPanel` (recursive container; `tabula routes`)
- `stdlib/e2e_draw_table.o9`, `stdlib/e2e_draw_panel.o9`,
  `demo/demo_draw_table.o9` — usage patterns / test surface
- `o9c/grammar.d/50-app-facade.y` — facade 9P `Srv`, `clone`,
  `o9app_exports_dir`/`o9app_imports_dir`
- `libtab/libtab.h`, `libtab/tab_persist.c` — substrate (note: 9P client path
  is `#ifdef __GNUC__`, OFF on native Plan 9 today; a 9P *server* over the
  tabula is the direction implied here, not the existing client blob-write)
- `docs/TABULA.md`, `docs/NAMESPACE.md`, `docs/CONCURRENCY.md`,
  `docs/STDLIB_PLAN.md`