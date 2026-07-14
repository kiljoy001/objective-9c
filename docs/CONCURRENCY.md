# o9 Concurrency

Status: BUILT for object actors, typed channels/streams, directional public
channel endpoints, `function`, `spawn`, `Task<T>`, and clone/session facade
isolation.

## Current Implementation

- Every constructed object is an actor: an Internal struct, a
  `dispatch_chan`, and a `proccreate` dispatch loop. Ordinary method calls
  send an `O9Msg` and wait for an `O9Reply`.
- Object actor procs are real Plan 9 processes created with
  `proccreate`; separate object actors can run on separate cores.
- `chan<T>` and `stream<T>` fields are typed object fields. They are
  auto-created at construction and support send, try-send, receive, `alt`,
  and public endpoint direction (`send chan<T>` / `recv chan<T>`).
- `function name(args) T { ... }` is a compiler-synthesized class with a
  fixed spawn envelope and one user method, `run`.
- `spawn name(args)` constructs a one-shot function instance, dispatches
  `run(args)` without blocking the caller, and returns `Task<T>`.
- `Task<T>.await()` blocks for completion and returns `T`; errors are
  carried through the task reply and surfaced through the per-proc call
  error path so `try t.await()` works.
- Raw Plan 9 C blocks and `use { ... }` dependency blocks are allowed only
  inside `function` bodies.
- The 9P app facade uses `clone` sessions. Result-bearing calls go through
  `<sid>/ctl`, `<sid>/data`, and `<sid>/status`, with per-request session
  routing from `Req *`, not a process-global current session.

## One Concurrency Model

o9 has one concurrency model: **actors plus channels**.

Objects are long-lived named actors. `function`/`spawn` is the same model
with a short-lived anonymous actor. That avoids a second goroutine model:
the compiler reuses construction, dispatch, type checking, method
lowering, and teardown.

The load-bearing rule remains:

> A `function` is an anonymous object with exactly one method.

That gives predictable behavior:

- Arguments are normal method arguments, not closure capture.
- The function body cannot capture the enclosing object's fields or
  methods. It must be passed values explicitly.
- Raw C is confined to this one-shot function surface, which keeps low
  level interop away from object internals.
- `main {}` remains the reserved entry point. `method` remains a class
  member. `function` is the spawnable one-method object form.

## Function-Class Shape

The compiler desugars:

```o9
function worker(int64 n) int64 {
    return n + 1;
}
```

into a normal generated class shape with framework-owned spawn metadata
and one user method:

```o9
class worker {
    prop int64 __spawn_index;
    prop int64 __spawn_state;
    stream __spawn_result;

    method int64 run(int64 n) {
        return n + 1;
    }
}
```

The real generated name is made C-safe and module/class-qualified when
needed so nested functions do not collide. Instance identity is distinct
per spawn.

## Spawn Lowering

`spawn worker(5)` lowers to a generated helper such as
`o9_spawn_worker(5)`:

1. Allocate an `O9Task`.
2. Construct a one-shot worker instance.
3. Send a `run(5)` message to the instance without waiting in the caller.
4. Start a small forwarder proc that waits for the normal `O9Reply`.
5. Deliver the reply into the task channel.
6. Reap the one-shot instance.

This preserves ordinary method code generation. Spawn does not special-case
the method body; only the helper and forwarder are special.

## Task Surface

The user-visible result object is `Task<T>`, not a numbered channel:

```o9
function addone(int64 n) int64 {
    return n + 1;
}

main {
    Task<int64> t = spawn addone(41);
    int64 v = t.await();
    print(v, "\n");
}
```

The earlier "numbered channel" idea survives only as internal machinery:
spawned work needs an internal per-instance result path, but user code
does not name or receive from that channel directly.

## Channels

Current channel surface:

```o9
class Counter {
    stream<int64> events;
    chan<string> names;
    recv chan<int64> publicEvents;
    send chan<string> publicCommands;

    method void sendValue(int64 n) {
        events -> n;
    }

    method int64 recvValue() {
        int64 n = <- events;
        return n;
    }
}
```

Built:

- typed `chan<T>` and `stream<T>` fields
- generic value transport for primitives, strings, structs, object handles,
  tasks/stdlib handles, arrays, and `List<T>`
- directional public endpoints with `send chan<T>` and `recv chan<T>`
- blocking send/recv
- try-send
- `alt`

Still future work:

- `Dict<K,V>` channel payloads, once Dict has typed value ownership instead
  of `void*` entries
- richer fan-in/fan-out helpers over many tasks or channels

## 9P Facade Concurrency

The flat root `ctl`/`data` shape is not the semantic result channel for
concurrent clients. Result-bearing calls use clone sessions:

```rc
sid=`{cat /mnt/o9/clone}
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/status
cat /mnt/o9/$sid/data
echo close > /mnt/o9/$sid/ctl
```

Session state is reached from the current request (`Req *`) and guarded
by per-session locks. There is no global `o9app_cur_session`.

## Remaining Work

- Add higher-level task/channel collection helpers if real programs need
  fan-in beyond simple `await()` loops.
- Continue adversarial testing around concurrent session calls, task
  errors, and channel cleanup.
