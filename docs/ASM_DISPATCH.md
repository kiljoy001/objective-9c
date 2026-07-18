# o9 Assembly Dispatch Design

This document describes the small assembly layer in `o9_dispatch.s`.
It is a same-process acceleration tier for object calls and field reads.
It is not the object model, not a network protocol, and not a second
semantic path.

## Design Rule

The assembly path must behave like the normal actor dispatch path, only
faster. If it cannot prove the call or data read is local and cached, it
returns failure and generated C falls back to the CSP actor path.

The source of truth remains:

- generated method implementations;
- the actor's `dispatch_chan`;
- private runtime method/object metadata;
- the app facade for external callers.

The asm cache is only a local shortcut over those facts.

## Runtime Shape

Every generated class client begins with the same ABI shape as `o9_Object`
in `o9.h`:

```c
int fd;
void *shm_base;
o9_AsmTable *table;
long ref;
void *dispatch_chan;
```

`o9_dispatch.s` depends on those first fields staying in that order. The
generated class client may append class-specific fields after them, but it
must not reorder the prefix.

The cache table is:

```c
typedef struct O9CacheEntry {
    u64int hash;
    void *ptr;
} O9CacheEntry;

typedef struct o9_AsmTable {
    O9CacheEntry data_cache[64];
    O9CacheEntry ctrl_cache[64];
} o9_AsmTable;
```

Both caches are direct-mapped: `slot = hash & 63`. A cache entry is valid
only when the full 32-bit selector hash in the slot matches the requested
hash. Collisions are allowed; they cause a miss/refill/fallback, not a
wrong dispatch.

## Data Dispatch

`o9_dispatch_data(client, hash)` is for same-process field reads.

The status/cache text reports field offsets. During client initialization,
the runtime maps the class shared-memory segment on 9front with
`segattach`, then converts cached offsets into absolute field pointers:

```text
offset -> shm_base + offset
```

The asm path then:

1. loads `client->table`;
2. indexes `data_cache[hash & 63]`;
3. compares the stored full hash;
4. returns the cached pointer on hit;
5. calls `o9_cache_fill(client, hash, 0)` on miss and retries once;
6. returns nil if still missing.

If shared memory is unavailable, data dispatch fails and generated code
uses the ordinary path.

## Control Dispatch

`o9_dispatch_call(client, hash, frame)` is for same-process method calls.

Generated C gives each method-send expression its own stack frame:

```c
__o9fr[n][0] = receiver.shm_base;  /* Internal* for the thunk */
__o9fr[n][1] = first argument;
__o9fr[n][2] = second argument;
...
```

The asm path indexes `ctrl_cache[hash & 63]`. On hit, the cached pointer is
a generated thunk:

```c
static void o9_ctrl_Class_method(void *frame);
```

That thunk unpacks the frame, invokes the generated method implementation,
stores the return value back in `frame[0]`, and records any method error in
the per-proc error slot used by `try`.

On miss, asm calls `o9_cache_fill(client, hash, 1)` and retries once. If
the thunk still is not present, it returns zero and generated C falls back
to `obj9_msgSendN`, which sends an `O9Msg` over the actor channel and waits
for `O9Reply`.

## Cache Fill

`o9_cache_fill` fills the table from the safest available local source:

- control calls first query the private method store for `(class, selector)`;
- method-store hits are guarded by the runtime generation/pid discipline,
  so a hit is a same-process thunk pointer;
- older/status-based cache text can still populate data offsets and method
  entries, but misses remain harmless.

The cache is intentionally small and direct-mapped. This keeps the asm
simple enough to audit. A heavily colliding class may lose performance, but
not correctness, because the full hash is checked before use.

## Boundaries

Assembly dispatch is only valid for ring 0: same app process, same address
space, same generated binary.

It is not used to move objects across the network. `near`, `far`, and
`listener` are tabula transport features; remote object construction is
rejected by the language, and the runtime no longer has a remote-object
method fallback. When a call leaves the process boundary, the public surface
is the app facade and tabula files, not cached function pointers.

On Linux/9lx targets, the shared-memory tier may be absent. The design still
works because asm miss/failure falls back to CSP or facade behavior.

## Invariants

- `o9_Object`/generated client prefix layout is ABI; do not reorder it.
- The cache entry must match the full selector hash before use.
- Cached control pointers must be same-process generated thunks.
- Cached data pointers must be derived from the mapped local `shm_base`.
- A miss, nil table, nil thunk, or unavailable shared-memory mapping must
  fall back rather than guess.
- Private members are not exposed through the app facade; asm is an
  internal same-process optimization and does not weaken facade access
  rules.

## Why This Exists

The language wants objects to feel cheap in the common case without giving
up the Plan 9 shape:

- local objects are CSP actors with explicit message dispatch;
- app boundaries are 9P facades;
- network data is inert tabula text.

The asm layer gives same-process calls a fast path while preserving that
model. It is deliberately small: two entry points, one fixed table layout,
one miss path, and a mandatory fallback.
