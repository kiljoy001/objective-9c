# Undo/Redo Patterns From 9front

Status: analysis of 9front editor and snapshot undo/redo, with proposed o9
stdlib entries. This is the "redo" companion to `PLAN9_PATTERNS.md`; it is
about change history, not ordinary read/write I/O.

## Source Survey

| Source | Pattern |
|---|---|
| `acme/file.c` | per-file undo list, append-only records read backwards, sequence numbers, delta/epsilon swap, save bit |
| `acme/exec.c` | Undo/Redo commands, applying undo to every view with the same sequence |
| `acme/elog.c` | command change log with `Replace` records and adjacent-change merging |
| `sam/file.c`, `sam/sam.c` | epsilon/delta buffers for undo and redo, dot/mark/name restoration |
| `cmd/paint.c` | bounded snapshot ring: `Image *undo[1024]`, free old snapshots |
| `ext4srv/ext4_journal.c`, `aux/flashfs` | persistent redo journal / replay (lower-level filesystem pattern) |

## What Acme Actually Does

The undo record is deliberately small and lives in a rune buffer:

```c
struct Undo {
    short type;   /* Delete, Insert, Filename */
    short mod;    /* previous modify bit */
    uint  seq;    /* sequence number */
    uint  p0;     /* location */
    uint  n;      /* rune count */
};
```

Important choices:

- **Records are read backwards.** The record header is followed by its payload
  (inserted text, old name), so the log is one compact append-only buffer.
- **A change is reversible.** Every insertion records the matching delete;
  every deletion records the text to reinsert.
- **Sequence numbers group simultaneous changes.** Successive records with the
  same `seq` are undone/redone as one unit.
- **Undo and redo swap two buffers.** `delta` is the undo transcript;
  `epsilon` is its inversion. Undo moves records from `delta` to `epsilon`;
  redo moves them back.
- **The modify bit and save point are part of the record.** Undo restores the
  previous modified state, not just the text.
- **Multiple views share the file.** `acme/exec.c` finds every window at the
  same undo sequence and applies the change to all of them.
- **Selection state is part of history.** `sam` stores dot/mark inversions so
  undo restores the cursor and selection.

`acme/elog.c` is a related but different log: it records `Replace` operations
for command addressing while an editing command is running. It merges nearby
changes (`Minstring`/`Maxstring`) so small edits do not explode the log. That
is the coalescing rule an o9 `UndoLog` should copy.

`cmd/paint.c` shows the other extreme: for opaque image state, keep a bounded
ring of full snapshots and free the oldest:

```c
x = nundo++ % nelem(undo);
if(undo[x])
    freeimage(undo[x]);
```

## Proposed Stdlib Entries

### 1. `stdlib/undo.o9` — core change log

```o9
class Change {
    method int64 kind();       // insert, delete, replace, command
    method int64 offset();
    method int64 count();
    method string text();
    method int64 sequence();
}

class UndoLog {
    method UndoLog(int64 limit);
    method void begin();       // group following changes under one sequence
    method void end();
    method void insert(int64 offset, string text);
    method void delete(int64 offset, int64 count, string removed);
    method void replace(int64 offset, int64 count, string before, string after);
    method bool undo();
    method bool redo();
    method bool canUndo();
    method bool canRedo();
    method int64 sequence();
    method bool modified();
    method void markSaved();
    method void clear();
    method void setLimit(int64 changes);
}
```

The log stores record headers plus payload in a `Buffer`/`Bytes` append-only
area. Undo and redo move records between two stacks or two buffers, following
acme/sam. `begin()`/`end()` are the transaction boundary. Adjacent edits inside
one transaction coalesce, with a size cap.

### 2. `stdlib/textbuf.o9` — mutable rune-aware text

o9's `string` is immutable and byte/UTF-8 shaped. Editors need a mutable rune
buffer with offsets that survive edits.

```o9
class TextBuffer {
    method TextBuffer(string initial);
    method int64 length();             // runes
    method string text();
    method string slice(int64 start, int64 count);
    method void insert(int64 offset, string text);
    method void delete(int64 offset, int64 count);
    method void replace(int64 offset, int64 count, string text);
    method int64 runeAt(int64 offset);
    method int64 byteAt(int64 runeOffset);

    method bool undo();
    method bool redo();
    method bool canUndo();
    method bool canRedo();
    method bool modified();
    method void markSaved();
}
```

`TextBuffer` owns an `UndoLog`, so an app author does not wire records by hand.
This is the main abstraction that makes an editor or text-heavy app practical
without raw C.

### 3. `stdlib/document.o9` — shared document and views

Acme's real lesson is that undo is a **document** property, not a widget
property. Multiple views must see the same sequence.

```o9
interface DocumentView {
    method void changed(int64 sequence, int64 offset, int64 count);
}

class Document {
    method Document(string name, TextBuffer buffer);
    method void attach(DocumentView view);
    method void detach(DocumentView view);
    method TextBuffer buffer();
    method bool undo();
    method bool redo();
    method bool save();
}
```

`DrawTextInput`, `DrawTextView`, and `DrawRichText` can implement
`DocumentView`. Undo then updates every attached view and restores selection
through the view's `changed` callback.

### 4. `stdlib/snapshot.o9` — bounded snapshot history

For paint, image editing, and opaque state, deltas are the wrong shape.

```o9
class SnapshotHistory {
    method SnapshotHistory(int64 limit);
    method void push(int64 handle);     // caller-owned state handle
    method int64 undo();
    method int64 redo();
    method bool canUndo();
    method bool canRedo();
    method void clear();
}
```

The caller supplies a release/restore convention (for images, free the evicted
snapshot; for a canvas, restore the saved image). Start with `ImageHistory`
if generic handles are awkward under current function-object rules.

### 5. `stdlib/journal.o9` — persistent redo log

Only if undo/redo must survive a crash or restart. The filesystem pattern is:

- append a record with a transaction id,
- flush the record,
- commit the transaction,
- replay committed transactions on open,
- truncate/checkpoint after a safe point.

```o9
class Journal {
    method Journal(string path);
    method void begin();
    method void record(string op, string payload);
    method bool commit();
    method bool replay(UndoLog log);
    method bool checkpoint(int64 sequence);
}
```

This is lower priority and should stay out of text-editor code unless the app
actually needs crash recovery.

## Design Rules

1. **Store deltas for text, snapshots for opaque state.** Do not store a full
   text snapshot per keystroke.
2. **Group changes with sequence numbers.** One user action is one undo step.
3. **Coalesce adjacent edits** with a size cap, as `acme/elog.c` does.
4. **Save the modify bit and selection state** with each change.
5. **Undo belongs to the document, not the widget.** Notify all views.
6. **Bound the history.** A limit in changes and bytes; free payloads when
   evicting.
7. **Keep app-facing APIs free of raw C.** `TextBuffer`/`UndoLog`/`Document`
   are o9 objects; raw buffers stay internal.

## Suggested Order

1. `textbuf.o9` + `undo.o9` — editor core; highest value.
2. `document.o9` — multi-view synchronization.
3. `snapshot.o9` — paint/image undo.
4. `journal.o9` — persistent history, only when needed.
5. Integrate undo hooks into `DrawTextInput`/`DrawTextView`/`DrawRichText`.

Validate with property tests: `undo(redo(x)) == x`, transaction grouping,
save-point restoration, coalescing limits, and multi-view sequence agreement.
