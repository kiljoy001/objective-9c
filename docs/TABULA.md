# Tabula — the data envelope

## What it is, in one sentence

A Tabula is a **data envelope**: an ordered, schema-carrying, on-disk
table of cells — any cell individually sealable — that moves across the
grid as a 9P file.  It is data.  It is never an object, never code,
never actionable on arrival.

## The four properties

- **Ordered** — rows carry sequence, so a Tabula can hold structure
  (sequences, trees via parent/seq), not just an unordered bag of
  key-values.
- **Schematic** — columns are declared and travel *with* the data. A
  Tabula is self-describing: a receiver knows what it got without an
  out-of-band contract. (JSON has no schema; protobuf keeps the schema
  in a separate file you must already hold. Here the schema is in the
  bytes.)
- **Loose / user-defined** — you declare the columns. The format
  imposes no data model: relational when you want rows, tree-shaped
  when you want parent/edge/seq, a single sealed cell when you want a
  secret.
- **Persistent** — the wire form, the at-rest form, and the serialized
  form are the *same bytes*. `writefile` it, `tab_open` it, mount it,
  mail it — one representation everywhere, no serialize/deserialize/
  re-serialize cycle at any boundary.

One line: a self-describing, ordered, user-schema'd record format whose
serialized, wire, and on-disk forms are identical text.  This is the
Plan 9 "everything is a cat-able file" thesis finally reaching
*structured* data, on the same terms as unstructured IO.

## Shape and API

A `.tab` file is one semantic collection.  The first entry is the schema
for the whole file; every following entry is one record in that schema.
The record type is not repeated per entry.

```text
schema=orders
	col=id
	col=item
	col=qty
	col=status

id=a
	item=widget
	qty=5
	status=paid

id=b
	item=gadget
	qty=3
	status=open
```

The language-level object is `Tabula`.  Its document API is deliberately
small:

```o9
Tabula t = new Tabula("orders", "item,qty,status")
string schema = t.schema()
int64 has_status = t.has("status")
t.write("a", "item", "widget")
t.write("a", "qty", "5")

Tabula paid = t.query("status", "paid")
string text = t.read()
t.flush()
```

- `write(id, col, value)` mutates the in-memory document, creating the
  `id` record when needed.
- `query(col, value)` searches for records whose column matches the value and
  returns another `Tabula` with the same schema.
- `schema()` returns the semantic collection name from the file's
  `schema=` entry.
- `has(col)` reports whether a column is declared in the schema.
- `read()` returns the complete serialized text form.
- `flush()` persists the current in-memory document to its backing path.

Persistence is explicit at the o9 level.  Closing a `Tabula` discards
unflushed changes; `flush()` is the disk boundary.

## The one law: inert on arrival

A Tabula that crosses the network is **read like any file**.  It is not
a process, not a spawn, not a hydration.  Nothing the sender wrote into
it can cause anything to happen on the receiver.  A receiver's own
local, already-installed code may read cell values out of a Tabula —
exactly as it reads values out of a config file or user input, with the
receiver's logic in full control of every branch.  The Tabula proposes
nothing; it just *is*.

- Not **executable**: no path compiles or interprets a Tabula into
  behavior.
- Not **actionable**: even without code, arrival triggers no side
  effect. Reading cells is a choice the receiver's code makes; sealed
  cells stay sealed until the receiver presents a key.

The threat model for receiving a Tabula is the threat model for
receiving a file: parse it carefully, do not trust its *values*
blindly.  That is the whole security story, and it is bounded and
well understood.

## Why we do NOT move objects or rehydrate them

Rehydration — reconstructing a live object on the receiver from
sender-supplied bytes — is remote code execution in disguise, even when
the class is local and trusted.  The reason is structural: hydration
means the *sender's bytes* decide which class is instantiated, which
constructor/method runs, and with which values — i.e. the sender gains
a lever on the receiver's control flow.  That is precisely the
deserialization-RCE family (Java, Python pickle, Ruby, .NET): each
began as "just rehydrate an object into a class you already have," and
each became an RCE class of its own.  You cannot secure it, because the
insecurity *is* the feature.

o9 therefore does not ship objects and does not rehydrate.  If a program
wants to build an object from received data, it reads the values out of
a Tabula and constructs the object itself, under its own control, the
same way it would from any file or input.  "The object arrived" is
never true; what is true is "data arrived, and my trusted local code
chose to build something from it."  Same practical outcome for the real
use case (state transfer / clone), with the RCE lever removed.

Consequence — what this deletes from the design, permanently: no capsule
exec format, no schema-hash admission gate, no signature-gated compile,
no interpreter, no sandbox for foreign behavior, no totality theorem to
enforce (nothing computes), no dp9ik-before-rehydration, no resource
bounds on visiting objects, no admission tiers.  All of that was
defending a thing that should not exist.

## Networking nativeness, scoped to data

What survives is exactly the value we wanted, minus the danger:

- **Data crosses the grid natively** — it's 9P, a file write and a file
  read. The language's "networking nativeness" is file IO, which is all
  9P ever was.
- **Secrets cross sealed** — any cell may be sealed (AEAD blob, the same
  `encrypt`/`decrypt` format as `secret` fields). Confidentiality that
  survives the table travelling, being cached, or being backed up.
- **Provenance crosses** — a Tabula is one text value, so `sign`/
  `verify` apply: a receiver can check who vouched for the data before
  trusting its values.

## Relationship to code-as-a-table

Homoiconicity (`CODE_AS_TABLE.md`) remains valid as a *compile-time*
idea: the AST as a table that build-time filters (macros) transform
between parse and typecheck, on the machine that owns the source.  What
is retired is any notion of transmitting that code table to another node
to be compiled or run.  Code-as-a-table is a local metaprogramming tool;
it is not a wire format.  Only Tabulae of **data** travel, and they
travel inert.

## Scope discipline

Standing by "Tabula is a data envelope" is a deliberate anti-bloat
decision.  Every temptation to make it heavier — carry an object, carry
code, run on arrival, self-instantiate — reintroduces the RCE it exists
to avoid.  The rule that keeps the design small is also the rule that
keeps it secure: **it sends a file; the file is data; the data is
inert.**  That is all a Tabula is, and all it should ever become.
