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

Imports are resolved inside the source tree namespace. The normal `o9build`
command binds the installed stdlib into that namespace before invoking `o9c`,
so installed projects can import either `file.o9` or `stdlib/file.o9`.
See [../stdlib/README.md](../stdlib/README.md) for the current module list.

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

`internal` marks an application-local member. Other objects in the same
application can call an internal method through its interface and CSP, but
the app's 9P `ctl`, `methods`, and status metadata do not publish it. An
interface method and its implementation must agree on `internal` visibility:

```o9
interface AccountModel {
    internal method int64 balance();
}

class AccountData {
    AccountModel;
    internal method int64 balance() { return 42; }
}
```

Use `private` for class-only details, `internal` for calls between actors in
one application, and public methods for the app facade. The controller can
consume an internal model interface and choose the `FileTree` exposed to each
viewer. An internal method has no client path or direct ctl command.

`secret string name;` stores sealed text. The compiler generates:

- `seal_name(string key, string val)`
- `open_name(string key) string`
- `seal_vault_name(Vault v, string val)`
- `open_vault_name(Vault v) string`

Storage is `name__blob` as lowercase hex AEAD ciphertext. Plaintext never
persists in object state, `/srv` data, or `.tab` rows. Key custody stays with
the caller. It is for secrets in object state and `.tab` workflows; it is not a
replacement for factotum when native Plan 9 authentication is available.

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
tabula Namespace MountTable FileTree Vault
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

Raw C is intentionally not a safe subset. It is the escape hatch for Plan 9 C,
so ordinary C memory bugs remain possible inside the block. The compiler's job
here is containment: raw C cannot be placed in app methods, cannot receive o9
object handles, and cannot name generated o9 internals such as instance lookup
helpers. Move values across the boundary, then mutate objects through their
normal properties and methods.

`use` names resolve through the built-in Plan 9 dependency registry and then
optional project-root `deps.tab`. Project dependencies must stay under the
project folder.

## Built-in Functions

o9 provides core built-in functions for text, files, process control, and
cryptography. A class method of the same name shadows any built-in function.

### Text And File Operations

- `len(string s) int64`: Byte count of string `s`.
- `cmp(string a, string b) int64`: Lexicographic comparison (0 if equal, -1 if `a < b`, 1 if `a > b`).
- `cat(string a, string b) string`: Concatenates two strings.
- `readfile(string path) string`: Reads complete file contents at `path` as text.
- `writefile(string path, string s) int64`: Writes string `s` to `path`. Returns byte count or -1 on error.
- `readline() string`: Reads one line from standard input.

### Application And 9P Facade

- `serve() void`: Blocks (yielding) so the process continues serving its 9P fileserver facade.
- `viewController(object vc) int64`: Registers custom dynamic view controller for 9P `/view` requests.
- `listen(string addr) void`: Starts listening on network address.
- `export(string name, tabula t) void`: Publishes a `tabula` into the served `exports/` directory.
- `fail(string msg) void`: Error-as-value. Sets the current method error and returns immediately.
- `lookup(string name) void`: Resolves client registration.
- `send(object obj, string cmd) string`: Executes a `ctl` command string against an actor handle and returns reply.

### Cryptographic Operations

o9 includes built-in cryptography backed by Monocypher.

The TEXT Invariant: All cryptographic boundary values (keys, signatures,
digests, salts, and AEAD cipher blobs) are lowercase hex strings. They can
travel inside `.tab` cells, `ctl` lines, 9P messages, and text files without
escaping, base64 corruption, or binary truncation.

- `keygen() string`: Generates 32 random bytes from `/dev/random` as a 64-character lowercase hex seed. The seed is the secret key.
- `pubkey(string sec) string`: Derives the 64-hex Ed25519 public key from the secret seed `sec`.
- `sign(string sec, string msg) string`: Signs string `msg` with secret seed `sec` using Ed25519. Returns a 128-hex signature string.
- `verify(string pub, string msg, string sig) int64`: Verifies Ed25519 signature `sig` for string `msg` against public key `pub`. Returns 1 if valid, 0 if invalid, -1 on malformed input.
- `hash(string msg) string`: Computes BLAKE2b-256 digest of string `msg`. Returns a 64-hex string.
- `mac(string key, string msg) string`: Computes keyed BLAKE2b-256 Message Authentication Code. `key` is 64 hex characters (32 bytes). Returns a 64-hex string.
- `passkey(string pass, string salt) string`: Key derivation via Argon2id (64 MiB RAM, 3 passes, 1 lane, matching `libtab`). `salt` must be at least 8 characters. Returns a deterministic 64-hex key.
- `salt() string`: Generates 16 random bytes from `/dev/random` as a 32-character lowercase hex salt string.
- `encrypt(string key, string msg) string`: Authenticated encryption with XChaCha20-Poly1305 AEAD. A fresh 24-byte nonce is drawn from `/dev/random` on every call. Returns a single lowercase hex string: `nonce[24] || mac[16] || ciphertext`.
- `decrypt(string key, string blob) string`: Authenticated decryption of an AEAD hex blob. Returns the plaintext string, or `nil` if the key is wrong or the blob was tampered with.
- `xpubkey(string sec) string`: Derives a 64-hex X25519 public key from seed `sec` for Diffie-Hellman key exchange.
- `exchange(string sec, string pub) string`: Computes X25519 shared secret between secret key `sec` and peer public key `pub`, hashed with BLAKE2b-256. Returns a 64-hex shared key. Returns `nil` if the peer public key is low-order.

## Cryptography And Vault

### Secret Fields

Declare confidential fields inside classes using the `secret` keyword:

```o9
class SecretBox {
    secret string apitoken;
}
```

The compiler desugars the field:
1. Replaces storage with `apitoken__blob`.
2. Generates `seal_apitoken(string key, string val)`.
3. Generates `open_apitoken(string key) string`.
4. Generates `seal_vault_apitoken(Vault v, string val)`.
5. Generates `open_vault_apitoken(Vault v) string`.

No plain getter or setter exists. The field is ciphertext in all representations
(memory, `/srv`, `.tab` storage). Key custody remains with the caller.

### Vault

`Vault` is an isolated memory arena (`O9KeyArena`) for key derivation, defense-in-depth
in-memory encryption, and at-rest file and table encryption.

Constructors:
- `new Vault()`: Generates random ephemeral key.
- `new Vault(string key_or_pass)`: Accepts a 64-hex key or passphrase. If given a passphrase, it generates an automatic 16-byte random salt and derives the key via Argon2id.
- `new Vault(string pass, string salt)`: Derives key via Argon2id with explicit salt (salt must be at least 8 characters).

Methods:
- `valid() int64`: Returns 1 if vault key is active, 0 if wiped or closed.
- `seal(string msg) string`: Encrypts `msg` with XChaCha20-Poly1305. Returns lowercase hex blob.
- `open(string blob) string`: Decrypts AEAD hex blob. Returns plaintext, or `nil` on authentication failure.
- `sealFile(string path, string data) int64`: Encrypts `data` and writes hex blob to `path`. Returns byte count or -1.
- `openFile(string path) string`: Reads hex blob from `path` and decrypts. Returns plaintext string or `nil`.
- `sealTab(string path, tabula t) int64`: Serializes `t`, encrypts it, and writes hex blob to `path`. Returns byte count or -1.
- `openTab(string path) tabula`: Reads and decrypts file at `path`, returning a restored `tabula` object.
- `put(string name, string val) int64`: Stores `val` encrypted inside an isolated RAM slot. Each slot has its own nonce and AEAD ciphertext in memory. Up to 64 slots. Returns 0 on success, -1 on failure.
- `get(string name) string`: Decrypts and returns plaintext from slot `name`. Returns plaintext string or `nil`.
- `has(string name) int64`: Returns 1 if slot exists, 0 otherwise.
- `drop(string name) int64`: Wipes slot memory and releases it. Returns 1 if found, 0 if not found.
- `salt() string`: Returns the salt string used by the Vault.
- `wipe() void`: Wipes key, slots, and salt in memory using `crypto_wipe`. Marks Vault invalid.
- `close() void`: Wipes memory and frees the Vault.

## tabula

`tabula` is the standard structured data object for `.tab` files. A `.tab`
file is text data with embedded semantics, not an executable object export.
The lowercase spelling is canonical; `Tabula` remains accepted as a
compatibility alias for older source. A tabula is one collection of entries;
an entry is an id value plus attached named values.

```o9
main {
    tabula t = new tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    print(t.value("a", "item"), "\n");

    tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
}
```

Common methods:

```text
schema()
has(col)
add(id)
write(id, col, val)
remove(id)
set(col, val)
get(col)
value(id, col)
first()
next()
read()
query(col, val)
flush()
close()
```

Typed tabulae bind that text document to a struct shape. The first data field
is the entry id; the remaining fields become attached values. This is
positional by design: there is no `id` keyword, annotation, or extra sugar.
Put the key field first. The constructor derives the column list from the
struct, so the schema is written once in code:

```o9
struct NdbEntry {
    string sys;      // row/entry id
    string ip;
    string dom;
    int64 version;
}

main {
    tabula<NdbEntry> entries = new tabula<NdbEntry>("ndb_entry");
    NdbEntry e;

    e.sys = "box1";
    e.ip = "10.0.0.2";
    e.dom = "box1.grid";
    e.version = 1;

    entries.write(e);

    NdbEntry copy = entries.row("box1");
    print(copy.ip, "\n");
}
```

`tabula<T>` requires `T` to be a struct whose first data field is `string`.
That first field names the identity column for this table: `sys` in the
example above, `id` only if the struct author names it `id`. Fields may be
`string` or scalar builtin values. It remains a normal `.tab` document
underneath: typed `write(record)` writes cells, `row(id)` hydrates a plain
value struct, and `query(col, val)` returns another `tabula<T>`.

`add` and `write` require a non-empty entry id; `nil` is reserved for the
hidden canonical nil entry. `nil` values are semantic nil, not empty strings:
writing nil clears the attached value, so the serialized entry omits that
`col=` line. `write` mutates a particular entry by id. `remove` collapses an
entry into the hidden nil entry, so it disappears from iteration, query, and
serialization. `value` reads one attached value by entry id and value name
without changing the current cursor. `set` and `get` operate on the current
entry after `add`, `first`, or `next`.

### Dial and remote tabulae

Use `dial protocol host:port` for an explicit network connection. It creates
a `NetConn`, attempts to open it, and translates the address to Plan 9's
`protocol!host!service` form. Import `net.o9` to use `NetConn`:

```o9
import "stdlib/net.o9";

main {
    NetConn conn = dial tcp fileserver.example:9999;
    if(conn.isOpen() && conn.mountReplace("/n/orders")) {
        tabula orders = new tabula("/n/orders/exports/orders.tab");
        print(orders.read());
        conn.unmount("/n/orders");
    }
}
```

`dial udp 127.0.0.1:9000` is valid for raw UDP I/O. The tabula 9P client
needs a transport that carries its 9P conversation; the protocol name alone
does not make every connection a 9P service. For a computed address, construct
`NetConn` with a Plan 9 address string and call its `dial()` method.

The older `near` and `far` tabula declarations remain for compatibility.
They select IL and TCP for tabula transfers; `dial` lets code choose a
protocol and endpoint explicitly. `near`, `far`, and `listener` are
data-locality forms for `tabula` only.
They do not construct remote objects.

```o9
main {
    near tabula lan = new tabula("orders", "item,qty,status") @ "il!fileserver!9999";
    far tabula wan = new tabula("orders", "item,qty,status") @ "tcp!remote.host!9999";
    listener tabula server = new tabula("orders", "item,qty,status") @ "il!*!9999";
}
```

- `near` reads `exports/orders.tab` from a 9P service over IL.
- `far` reads `exports/orders.tab` from a 9P service over TCP.
- `listener` exports the local tabula under `exports/orders.tab` and serves
  the app tree at the supplied address.
- `push()` writes a remote tabula copy back to `imports/orders.tab`.
- `sync()` refreshes a remote tabula copy from `exports/orders.tab`.

Ordinary classes cannot be declared `near`, `far`, or `listener`. If data
crosses a machine boundary, it crosses as `.tab` text with semantics embedded;
the receiver decides what to do with it using its own local code.
The legacy runtime fallback for remote object method dispatch has been removed;
generated user code cannot create or call remote object handles.

Generated app facades expose both directions:

```text
exports/    # app-owned published .tab files
imports/    # inert inbound .tab deposits
```

`imports/` accepts only `.tab` file names. Writes are staged per open fid and
become visible when that fid is closed; imported data never invokes methods by
itself.

The typical distributed application shape is shard-local code plus tabula
exchange. A controller or peer may read another node's `exports/` with `near`
or `far`, and may deposit input under `imports/` with `push()`, but all
meaningful work happens in the receiver's installed local code. For example,
a mutation grid node owns a local shard root, runs local workers against that
root, exports compact progress and final result tabulae, and lets a controller
merge those tabulae later. The controller combines data; it does not hold a
remote object handle to the node's workers.

Binary data stays text in tabula. The standard binary payload column is `0x`,
with bytes encoded as lowercase hex from `Bytes.hex()` and decoded with
`Bytes.fromHex()`.

## Namespace And MountTable

`Namespace` is the user-facing object for programmatic namespace setup. It is
for building private or application-specific Plan 9 namespaces from o9 code:

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

`MountTable` is the lower-level tabula-backed mount/bind data object. It stores
the parameters needed by Plan 9 `bind` and `mount` in a `schema=mounts` tabula.
Use `Namespace` in normal code; use `MountTable` when the app needs to persist,
inspect, query, export, or exchange syscall-shaped mount data directly.

This gives o9 three namespace layers:

- `Namespace` applies a controlled namespace to the current process.
- `MountTable` is the inert `.tab` recipe for those namespace operations.
- the served app facade exposes a public namespace of virtual files:
  `clone`, session dirs, `methods`, `exports/`, and `imports/`.

Reading or receiving a `MountTable` does not execute it. Local code must load
the data, set policy with `allowRoot`, validate it, and call `apply`. See
[MOUNTTABLE.md](MOUNTTABLE.md) for the syscall-shaped storage format.

## 9P Facade Usage

When an app calls `serve()`, it posts a 9P service. The service root has:

```text
clone
methods
status
view/
exports/
imports/
<session-id>/ctl
<session-id>/data
<session-id>/status
```

An app can also register a dynamic view controller before `serve()`:

```o9
viewController(myController);
serve();
```

When clients mount the service, requests under `/view` dispatch to the controller's `display(id, caller)` method, returning a tailored `FileTree`. See [VIEWS.md](VIEWS.md).

Use clone sessions for result-bearing calls:

```rc
mount -c /srv/Counter /mnt/o9

sid=`{cat /mnt/o9/clone}
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/status
cat /mnt/o9/$sid/data
echo close > /mnt/o9/$sid/ctl
```

The session id carries the conversation across separate shell commands.
Root-level `ctl` is for compatibility/debug and app-wide commands; normal
method calls that return data should use session-local `ctl` and `data`.
Generated app facades support session-local login through `ctl`:

```rc
sid=`{cat /mnt/o9/clone}
echo 'login scott password' > /mnt/o9/$sid/ctl
```

The generated server verifies the submitted user/password with Plan 9
`auth_userpasswd`, which talks to `/mnt/factotum/rpc` and the native auth
system. The app does not store the password; it only records that this clone
session is blessed as that user. Controller methods can use
`Factotum.caller()` from `stdlib/net.o9` to inspect the current request name,
and `Factotum.blessed()`/`Factotum.verify(name)` to require a successful
session login.
`FactotumAdmin` builds the common first-launch policy on top of that: it stores
one configured admin user in a `.tab` file, bootstrapping from the constructor
only when that file is empty or missing. It is app policy, not Plan 9 account
creation.

Apps can publish `.tab` data under `exports/`:

```o9
main {
    tabula t = new tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    export("orders.tab", t);
    serve();
}
```

Another program can mount the app, read `exports/orders.tab`, import it as a
`tabula`, and act according to its own local logic.

For the data format and design rules, read [TABULA.md](TABULA.md).
