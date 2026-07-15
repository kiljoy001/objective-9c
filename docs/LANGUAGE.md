# o9 Language Guide

This is the canonical guide for writing o9 programs. o9 source is transpiled
to Plan 9 C; generated C is the artifact that gets compiled and linked.

## Program Shape

An o9 program is made from imports, optional modules, classes, structs, enums,
top-level `function` blocks, and one reserved `main` block.

```o9
import "string.o9";

class Counter {
    int64 val;

    method Counter(int64 initial) {
        val = initial;
    }

    method void inc(int64 n) {
        val = val + n;
    }

    method int64 get() {
        return val;
    }
}

main {
    Counter c = new Counter(10);
    c.inc(5);
    print(c.get(), "\n");
}
```

`main { ... }` is reserved. Do not write `func main()`, `method main()`, or
put `main` inside a user class.

`module Name { ... }` may be used to group declarations:

```o9
module App {
    class Thing {
        method int64 id() { return 1; }
    }
}

main {
    App.Thing t = new App.Thing();
    print(t.id(), "\n");
}
```

## Imports

Imports are source-level includes of o9 modules:

```o9
import "file.o9";
import "namespace.o9";
```

Stdlib modules live under `stdlib/`. See [../stdlib/README.md](../stdlib/README.md)
for the current module list.

Raw C dependencies are not imported this way. They are declared with `use`
inside a `function` body.

## Classes

Classes are actor-backed objects. Their public methods are callable from o9
code and, when the app is served, through the 9P facade.

```o9
class Account {
    private int64 balance;
    secret string token;

    method Account(int64 initial) {
        balance = initial;
    }

    private method void adjust(int64 delta) {
        balance = balance + delta;
    }

    method int64 deposit(int64 amount) {
        adjust(amount);
        return balance;
    }

    method int64 get() {
        return balance;
    }
}
```

Constructors are `method ClassName(...)`. Destructors use `~ClassName()`.

Fields may be written as plain declarations or with `prop`:

```o9
int64 count;
prop bool ready;
```

`private` is class-scoped: methods in the same class can read private fields
and call private methods; outside code cannot. Private members are also
filtered from the 9P facade.

`secret string name;` stores sealed text and generates `seal_name` and
`open_name` helpers. It is for secrets in object state and `.tab` workflows;
it is not a replacement for factotum when native Plan 9 authentication is
available.

A class can contain fields of other class types:

```o9
class Engine { method Engine() { } }

class Machine {
    Engine e;

    method Machine() {
        e = new Engine();
    }
}
```

A class should not contain itself directly as a field. Use another object,
a collection, or an id/reference pattern instead.

## Methods

Methods use type-first signatures:

```o9
method int64 add(int64 a, int64 b) {
    return a + b;
}
```

Void methods use `void`:

```o9
method void reset() {
    count = 0;
}
```

Expression-bodied methods are supported:

```o9
method int64 doubled() => count * 2;
```

Self-calls are bare:

```o9
method int64 doubled() {
    return get() * 2;
}
```

Calling an object through an object reference sends a message to that
particular instance.

## Main

`main` is the program entry block:

```o9
main {
    print("hello\n");
}
```

To keep an app available through its 9P facade, create the exported objects and
then call `serve()`:

```o9
class Counter {
    int64 val;
    method Counter(int64 n) { val = n; }
    method int64 get() { return val; }
}

main {
    Counter c = new Counter(42);
    serve();
}
```

Without `serve()`, the program runs `main` and exits.

## Types

Core value types:

```text
bool
byte
char uchar
int8 uint8 int16 uint16 int32 uint32 int64 uint64
int uint short ushort long ulong vlong uvlong
double
string
void
```

Interop-only integer pointer storage:

```text
intptr uintptr
```

Use `intptr` and `uintptr` inside raw-C `function` interop when Plan 9 C needs
that storage shape. They are not the normal way to expose object state.

Object and library types:

```text
ClassName
Task<T>
chan<T> stream<T>
List<T> Dict<string,T>
list<T> array<T> dictionary<T>
Tabula Namespace MountTable
```

`List<T>` and `Dict<string,T>` are compiler/runtime carriers. The stdlib
wrappers `list<T>`, `array<T>`, and `dictionary<T>` provide object-style
methods over those carriers.

Tuples can be returned and destructured:

```o9
function pair(int64 x) (int64, int64) {
    return (x, x + 1);
}

main {
    int64 a;
    int64 b;
    Task<(int64, int64)> t = spawn pair(10);
    (a, b) = t.await();
}
```

Tuple fields are data-only for now. Object handles are rejected as tuple
fields because tuples can escape through returns, tasks, and channels; pass
object handles as named values instead.

Structs are plain data aggregates:

```o9
struct Point {
    prop int64 x;
    prop int64 y;
}
```

Enums are named integer-like values:

```o9
enum Color { Red, Green, Blue }
```

## Casts

Use `cast<T>(expr)` for explicit scalar conversions between integer, char,
double, and bool storage types:

```o9
int64 wide = 260;
byte b = cast<byte>(wide);
int64 back = cast<int64>(b);
```

Object, string, collection, and pointer casts are rejected.

## Control Flow

Supported control flow:

```o9
if(x > 0) {
    print("positive\n");
} else {
    print("zero or negative\n");
}

while(i < 10) {
    i = i + 1;
}

for(i = 0; i < 10; i = i + 1) {
    print(i, "\n");
}
```

Errors are values carried through calls and tasks:

```o9
method int64 withdraw(int64 n) {
    if(n > balance) {
        fail("insufficient funds");
    }
    balance = balance - n;
    return balance;
}

method int64 spend(int64 n) {
    defer cleanup();
    int64 left = try withdraw(n);
    return left;
}
```

`fail` returns early with an error. `try` propagates a callee error out of the
current method or function. `defer` runs cleanup at method/function exit.

## Channels And Streams

`chan<T>` and `stream<T>` are object-internal CSP channels. They are created
when the containing object is constructed. Channels carry typed o9 values:
numbers, `bool`, `byte`, `double`, `string`, structs, object handles,
arrays, `List<T>`, `Task<T>`, and stdlib handles. Sends copy the value at
the channel boundary; object sends copy the object handle, not the actor's
internal memory. `Dict<K,V>` is intentionally rejected as a channel payload
until Dict has typed value ownership.

```o9
class Pipe {
    chan<int64> c;

    method void put(int64 v) {
        c -> v;
    }

    method int64 take() {
        int64 x;
        x = <- c;
        return x;
    }
}
```

`stream<T>` is the same channel shape with a different semantic name:

```o9
stream<string> events;
```

Directional public endpoints can be declared with contextual `send` and
`recv` prefixes:

```o9
class Widget {
    recv chan<int64> events;
    send chan<int64> commands;

    method void emit(int64 v) {
        events -> v;           // owner endpoint: allowed
    }

    method int64 nextCommand() {
        int64 v;
        v = <- commands;       // owner endpoint: allowed
        return v;
    }
}

main {
    Widget w = new Widget();
    int64 event;

    w.emit(7);
    event = <- w.events;       // public recv endpoint: allowed
    w.commands -> 11;          // public send endpoint: allowed
}
```

`recv chan<T>` means outside code may receive from `obj.field` but may not
send to it. `send chan<T>` means outside code may send to `obj.field` but may
not receive from it. Inside the declaring object, bare field use is the owner
endpoint and remains bidirectional, so the object can feed its own event
stream or drain its own command channel.

Use `alt` to wait on multiple receives:

```o9
alt {
case x = <- leftc:
    x = x + 10;
case x = <- rightc:
    x = x + 20;
default:
    x = 0;
}
```

## Function, Spawn, And Task

`function` defines a one-method function object. It can be top-level or nested
inside a class. It is the intended place for low-level Plan 9 C interop.

```o9
function addone(int64 n) int64 {
    return n + 1;
}

main {
    Task<int64> t = spawn addone(41);
    print(t.await(), "\n");
}
```

`spawn f(args)` returns immediately with `Task<T>`. `Task<T>.await()` waits for
completion and returns the value or propagates the task error through `try`.

Nested function example:

```o9
class Worker {
    function addraw(int64 a, int64 b) int64 {
        int64 out;
        c {
            out = a + b;
        }
        return out;
    }

    method int64 add(int64 a, int64 b) {
        Task<int64> t = spawn addraw(a, b);
        return t.await();
    }
}
```

## Raw C Rules

Raw Plan 9 C is allowed only inside `function` bodies:

```o9
function countbytes(string path) int64 {
    use { bio }

    int64 n;
    c {
        Biobuf *b;
        char *cpath;

        n = 0;
        cpath = o9_string_cstr(path);
        b = cpath != nil ? Bopen(cpath, OREAD) : nil;
        free(cpath);
        if(b != nil) {
            while(Bgetc(b) >= 0)
                n++;
            Bterm(b);
        }
    }
    return n;
}
```

Rules:

- `c { ... }` is rejected in `main` and normal class methods.
- `use { ... }` is allowed only inside `function` bodies.
- Raw C functions may accept and return o9 scalar values, strings, tuples, and
  task-compatible values.
- Object handles are rejected as raw-C function parameters, locals, and
  returns.
- Explicit pointer declarations such as `T*` are not o9 declaration types.
- Raw pointers and object memory addresses should stay inside C blocks.
- Use properties and methods as the mutable interface between C helpers and
  o9 objects.

`use` names resolve through the built-in Plan 9 dependency registry and then
optional project-root `deps.tab`. Project dependencies must stay under the
project folder.

## Tabula

`Tabula` is the standard structured data object for `.tab` files. A `.tab`
file is text data with embedded semantics, not an executable object export.

```o9
main {
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    Tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
}
```

Common methods:

```text
schema()
has(col)
add(id)
write(id, col, val)
set(col, val)
get(col)
first()
next()
read()
query(col, val)
flush()
close()
```

`write` mutates a particular record by id. `set` mutates the current record
after `add`, `first`, or `next`.

### Tabula Locality

`near`, `far`, and `listener` are data-locality forms for `Tabula` only.
They do not construct remote objects.

```o9
main {
    near Tabula lan = new Tabula("orders", "item,qty,status") @ "il!fileserver!9999";
    far Tabula wan = new Tabula("orders", "item,qty,status") @ "tcp!remote.host!9999";
    listener Tabula server = new Tabula("orders", "item,qty,status") @ "il!*!9999";
}
```

- `near` reads `exports/orders.tab` from a 9P service over IL.
- `far` reads `exports/orders.tab` from a 9P service over TCP.
- `listener` exports the local Tabula under `exports/orders.tab` and serves
  the app tree at the supplied address.
- `push()` writes a remote Tabula copy back to `imports/orders.tab`.
- `sync()` refreshes a remote Tabula copy from `exports/orders.tab`.

Ordinary classes cannot be declared `near`, `far`, or `listener`. If data
crosses a machine boundary, it crosses as `.tab` text with semantics embedded;
the receiver decides what to do with it using its own local code.

Generated app facades expose both directions:

```text
exports/    # app-owned published .tab files
imports/    # inert inbound .tab deposits
```

`imports/` accepts only `.tab` file names. Writes are staged per open fid and
become visible when that fid is closed; imported data never invokes methods by
itself.

Binary data stays text in Tabula. The standard binary payload column is `0x`,
with bytes encoded as lowercase hex from `Bytes.hex()` and decoded with
`Bytes.fromHex()`.

## Namespace And MountTable

`Namespace` is the user-facing object for programmatic namespace setup:

```o9
import "namespace.o9";

main {
    Namespace ns = new Namespace();
    ns.root("/tmp/o9_namespace_root");
    ns.dir("cache", 493);
    ns.bindReplace("/tmp", "tmp");
    ns.apply();
}
```

`MountTable` is the lower-level Tabula-backed mount/bind data object. Use
`Namespace` in normal code; use `MountTable` when the app needs to persist or
exchange syscall-shaped mount data directly.

## 9P Facade Usage

When an app calls `serve()`, it posts a 9P service. The service root has:

```text
clone
methods
status
exports/
<session-id>/ctl
<session-id>/data
<session-id>/status
```

Use clone sessions for result-bearing calls:

```rc
mount -c /srv/o9.Counter.Counter.app /mnt/o9

sid=`{cat /mnt/o9/clone}
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/status
cat /mnt/o9/$sid/data
echo close > /mnt/o9/$sid/ctl
```

The session id carries the conversation across separate shell commands.
Root-level `ctl` is for compatibility/debug and app-wide commands; normal
method calls that return data should use session-local `ctl` and `data`.

Apps can publish `.tab` data under `exports/`:

```o9
main {
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    export("orders.tab", t);
    serve();
}
```

Another program can mount the app, read `exports/orders.tab`, import it as a
`Tabula`, and act according to its own local logic.

For the data format and design rules, read [TABULA.md](TABULA.md).
