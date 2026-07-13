# o9 namespaces — produce-into-namespace design (July 2026)

Status: DESIGN (not built). This doc corrects an architectural drift and
sets the real direction for namespace control in o9.

## The architectural honesty check (why this doc exists)

o9 changed architectures partway through, and a feature was left behind:

- **OLD model (abandoned — "the jumble"):** an app is MANY objects, each a
  potential fileserver, COMPOSED via the namespace. You'd `link`/`bind`
  objects together into a tree; "the app" was an emergent namespace
  assembled from parts. Namespace composition was the load-bearing
  mechanism — it built the app.
- **SHIPPED model (the facade):** an app is ONE fileserver in a fixed
  SHAPE that exports a schema of virtual files — flat `/srv/o9.<app>`
  with ctl/data/status/methods/clone/exports/. Objects live INSIDE it as
  named participants addressed through ctl, NOT as mountable parts. The
  app is a shape, not an assembly.

The facade replaced namespace-composition-of-objects. So the old `link`
feature (which binds `<root>/obj/<name>` paths) is ORPHANED: it composes
per-object paths the flat facade no longer creates, and is used in ZERO
real tests (only a parse fixture + a negative test). Same pattern as cap,
the replica name, the o9type sidecar: a feature from a replaced
architecture surviving because nobody asked "does this still have a job?"

**Correction to a wrong turn:** "userspace namespace control is o9's
defining feature" (as composition-of-objects) is the ABANDONED thesis.
The real, shipped thesis is: **an o9 app is a fileserver in a particular
shape that exports a schema of virtual files.**

## The reframe: namespace control = organizing PRODUCED OUTPUT

Namespace control is NOT dead — it has a NEW, correct job that fits the
shipped thesis. The app PRODUCES files/data; namespace control is how the
program CONSTRUCTS a namespace and PLACES the files it produces into it.

Not "compose the app from objects" (dead) but "organize what the app
OUTPUTS into a namespace clients mount and read." Namespace = the SHAPE
OF THE APP'S OUTPUT, programmatically constructed.

This is consistent with — and generalizes — what the facade ALREADY does:
- `exports/` — the app produces Tabulae as virtual files in a served
  namespace. THIS IS ALREADY namespace-control-as-output.
- `clone`/sessions — each conversation gets its OWN namespace of files
  (17/ctl, 17/data, 17/status).
- the facade schema itself — the app SHAPES a namespace of virtual files.

So: an app is a fileserver that PRODUCES a namespace of virtual files,
and the namespace surface should serve THAT — a program builds a tree of
produced files, organized how it wants, that clients mount and read.
Generalize `exports/` from "publish one Tabula" to "the app builds a
tree of produced files in a namespace region."

## What to retire / what to reuse

RETIRE: `link`-as-object-composition — binding `/obj/<name>` paths the
facade doesn't create. Its NLink codegen (bind of obj subtrees) targets
the dead model.

REUSE (the machinery is right, the target was wrong): `bind`,
o9_ns_recipe (namespace-as-serializable-data), the served-tree
createfile-into-stable-parent pattern (exports/, clone sessions), MREPL/
MBEFORE.

NEW SURFACE: `MountTable` is the authority-bearing, Tabula-backed object
for `schema=mounts` data.  Users do not hand-write mount cells; typed
methods (`dir`, `bind`, `mountsrv`) store syscall-shaped parameters, and
`MountTable` validates policy (`allowRoot`) before applying them to the
current process namespace.  This is namespace control for application
setup/isolation, not object composition.

`replace`/`union` MIGHT survive — not to bind objects, but to compose
OUTPUT REGIONS (union several produced trees at a path; replace a region).
Decide when the produce-into-namespace surface is designed.

## Open design questions (resolve before build)

- Surface: how does a program declare "produce this tree of files here"?
  A generalized export (export a Tabula -> export a named tree)? A
  namespace-builder object? Declarative vs imperative?
- Does a produced namespace stay per-app (in the facade) or can it be a
  standalone served region a client mounts directly?
- Where do produced files live — the app's served tree (like exports/,
  synthetic in-memory) or optionally persisted?
- Do replace/union survive as output-region composition, or drop with
  link?
- Relationship to sessions: is a session's file set a produced namespace
  too (unifying clone/exports under one "produced namespace" concept)?

## Adversarial goal: NAMESPACE OUTPUT INTEGRITY

The security boundary for THIS thesis (as the private-facade review was
the boundary for the object model). The produce-into-namespace surface
must prove:

- clients CANNOT write into produced regions unless explicitly allowed
  (produced files default read-only; the app produces, clients read).
- export/produced names cannot ESCAPE the region: reject `/`, `..`, empty
  names, control bytes, absolute paths (same discipline as the import
  subtree boundary). A produced name is a leaf in the app's tree, not a
  path.
- session namespaces are ISOLATED from each other (already: clone gives
  each conversation its own dir; a client can't reach another session's
  files). Adversarial: prove no cross-session read/write.
- produced trees do NOT expose private object state by accident (the #7
  private-facade discipline extends to produced files — a produced file
  must never serialize a private field).
- replacing / re-exporting a file is ATOMIC from a reader's view (a
  concurrent reader sees the old bytes or the new bytes, never a torn
  half). Current o9_export_tab swaps aux->data — check the swap ordering.
- dead `link` behavior is REMOVED or FAILS CLOSED — never silently
  fabricates /obj/ paths and binds phantom regions (it currently
  o9_ns_ensure_dir's a source dir and binds unchecked = fails OPEN).

The distinction to preserve HARD: clone is NOT object composition — it is
a per-client PRODUCED namespace. exports/ is NOT object export — it is
data PUBLICATION. Both are the app producing files, not objects being
mounted as parts.

## Build order (design-first)

1. This doc — the reframe + honesty check.
2. DONE: `link`/`replace`/`union` REMOVED entirely (token, grammar,
   lexer, codegen, typecheck, fixtures) — not stubbed, not fail-closed,
   gone. Why keep a keyword whose only behavior is to error? It composed
   the abandoned jumble model, binding /obj/ paths the flat facade never
   creates. Retired like cap.
3. DONE: first `MountTable` surface for local namespace setup
   (`dir`/`bind`/`mountsrv`, root-confined targets, syscall-shaped
   Tabula storage).
4. Design the produce-into-namespace surface (generalize exports/) from
   the open questions above, with the output-integrity goals as the
   security spec.
5. Build it; tests: an app produces a tree of files into a namespace, a
   client mounts and reads the produced shape — plus the output-integrity
   adversarial tests.

Current implemented pieces: link is removed, and `MountTable` can build,
transport, validate, and apply root-confined local namespace setup from
`schema=mounts` Tabulae.  The remaining work relates to the app-facade
(the shipped shape), exports (the first produce-into-namespace instance),
and sessions (per-caller produced file sets).
