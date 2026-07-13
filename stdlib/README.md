# o9 Standard Library

The stdlib is written as ordinary o9 modules where possible. Plan 9 system
calls stay behind `function` raw-C helpers, and the public surface is an object
API.

Import modules by filename:

```o9
import "bytes.o9";
import "collections.o9";
import "file.o9";
import "io.o9";
import "net.o9";
import "path.o9";
import "process.o9";
```

## Bytes

`Bytes` is the byte-oriented companion to `string`. It stores length-carrying
o9 strings internally, so binary zero bytes can be represented without C string
truncation.

```o9
import "bytes.o9";

main {
    Bytes b = new Bytes("ab");
    b.append(67);
    b.set(1, 90);
    print(b.text(), " ", b.hex(), "\n");  // aZC 615a43
}
```

Methods:

- `Bytes(string initial)`
- `clear()`
- `setText(string data)`
- `text() string`
- `length() int64`
- `empty() bool`
- `get(int64 index) byte`
- `set(int64 index, byte b)`
- `append(byte b)`
- `appendString(string s)`
- `slice(int64 start, int64 count) string`
- `hex() string`
- `compare(string other) int64`
- `equals(string other) bool`

Out-of-range byte reads return `0`; out-of-range writes leave the value
unchanged.

## Buffer

`Buffer` is a small mutable byte/text builder over `Bytes`.

```o9
import "buffer.o9";

main {
    Buffer b = new Buffer("hello");
    b.append(", ");
    b.append("rio");
    print(b.text(), "\n");
}
```

Methods:

- `Buffer(string initial)`
- `clear()`
- `empty() bool`
- `append(string s)`
- `appendByte(byte b)`
- `setByte(int64 index, byte b)`
- `byteAt(int64 index) byte`
- `length() int64`
- `slice(int64 start, int64 count) string`
- `hex() string`
- `text() string`

## File

`File` wraps common Plan 9 file operations.

```o9
import "file.o9";

main {
    File f = new File("/tmp/o9-note");
    Bytes body = new Bytes("hello\n");

    f.writeBytes(body);
    f.append("world\n");
    print(f.read());
}
```

Methods:

- `File(string path)`
- `read() string`
- `write(string data) int64`
- `append(string data) int64`
- `writeBytes(Bytes data) int64`
- `appendBytes(Bytes data) int64`
- `readInto(Bytes data)`
- `exists() bool`
- `size() int64`
- `remove() bool`
- `mkdir() bool`
- `isDir() bool`
- `list() string`

`list()` returns newline-separated directory entries.

## Path

`Path` wraps Plan 9 path cleaning and common path decomposition.

```o9
import "path.o9";

main {
    Path p = new Path("/tmp//a/../b/file.txt");
    print(p.clean(), " ", p.base(), " ", p.ext(), "\n");
    print(p.join("../note.md"), "\n");
}
```

Methods:

- `Path(string path)`
- `set(string path)`
- `text() string`
- `clean() string`
- `normalize()`
- `base() string`
- `dir() string`
- `ext() string`
- `join(string child) string`
- `append(string child)`

## IO

`io.o9` provides buffered file IO over Plan 9 `Biobuf`.

```o9
import "io.o9";

main {
    Writer w = new Writer("/tmp/o9-note");
    w.write("alpha\n");
    w.writeByte(66);
    w.close();

    Reader r = new Reader("/tmp/o9-note");
    print(r.readLine(), " ", r.readByte(), "\n");
}
```

`IOBuffer` methods:

- `IOBuffer(string path)`
- `file() string`
- `position() int64`
- `seek(int64 pos)`
- `reset()`
- `appendWrites()`
- `truncate() int64`
- `readAll() string`
- `eof() bool`
- `readLine() string`
- `readByte() byte`
- `write(string data) int64`
- `writeBytes(Bytes data) int64`
- `writeByte(byte b) int64`
- `flush() int64`
- `close()`

`Reader`, `Writer`, and `Appender` are narrower wrappers over the same raw
helpers. They avoid exposing file descriptors or raw `Biobuf*` pointers.

## Collections

`collections.o9` provides object-style wrappers over the existing collection
keywords. These classes do not replace the compiler's collection support; they
make it easier to use from ordinary o9 code.

```o9
import "collections.o9";

main {
    list<int64> xs = new list<int64>();
    xs.add(10);
    xs.add(20);
    xs.set(1, 99);
    print(xs.length(), " ", xs.get(1), "\n");

    dictionary<int64> ages = new dictionary<int64>();
    ages.set("sam", 42);
    print(ages.has("sam"), " ", ages.get("sam"), "\n");
}
```

`list<T>` is a compact mutable sequence backed by `T[]`:

- `list()`
- `add(T value)`
- `length() int64`
- `empty() bool`
- `valid(int64 index) bool`
- `get(int64 index) T`
- `set(int64 index, T value) bool`
- `remove(int64 index) bool`
- `pop() T`
- `clear()`

`array<T>` wraps `T[]` and tracks the logical length explicitly:

- `array()`
- `add(T value)`
- `put(int64 index, T value) bool`
- `length() int64`
- `empty() bool`
- `valid(int64 index) bool`
- `get(int64 index) T`
- `set(int64 index, T value) bool`
- `remove(int64 index) bool`
- `pop() T`
- `clear()`

`put` grows the logical length when writing beyond the current end; skipped
slots read back as the type's zero value.

`dictionary<T>` wraps `Dict<string,T>`:

- `dictionary()`
- `set(string key, T value)`
- `has(string key) bool`
- `get(string key) T`
- `remove(string key) bool`
- `clear()`
- `length() int64`
- `empty() bool`

`dictionary<T>` intentionally uses string keys. The underlying runtime dict is
string-keyed, and this wrapper keeps that fact visible. `remove` and `clear`
are logical deletes implemented with generation stamps, so stale values are not
reachable through the object API. Key iteration and value iteration are not
exposed yet because the current runtime carrier has no safe iterator primitive
for wrappers to call.

## Process And Env

`process.o9` exposes process metadata, shell command execution, cwd, and
environment variables.

```o9
import "process.o9";

main {
    Process p = new Process();
    Env e = new Env();

    print(p.argc(), " ", p.user(), "\n");
    e.set("o9_mode", "dev");
    p.run("echo ok >/tmp/o9-process");
}
```

`Process` methods:

- `pid() int64`
- `user() string`
- `argc() int64`
- `arg(int64 index) string`
- `run(string command) int64`

`Env` methods:

- `get(string name) string`
- `exists(string name) bool`
- `set(string name, string value) bool`
- `unset(string name) bool`
- `cwd() string`
- `chdir(string path) bool`

`run` executes through `/bin/rc -c`; return `0` means the command exited cleanly.

## Net

`net.o9` wraps Plan 9 `dial`, `announce`, `listen`, `accept`, `read`, `write`,
and `close`.

```o9
import "net.o9";

main {
    NetConn c = new NetConn("tcp!example.com!80");
    if(c.dial()) {
        c.write("GET / HTTP/1.0\r\n\r\n");
        print(c.read(512));
        c.close();
    }
}
```

`NetConn` methods:

- `NetConn(string address)`
- `endpoint() string`
- `dial() bool`
- `isOpen() bool`
- `read(int64 max) string`
- `write(string data) int64`
- `close() bool`

`NetListener` methods:

- `NetListener(string address)`
- `listen() bool`
- `dir() string`
- `local() string`
- `accept() bool`
- `read(int64 max) string`
- `write(string data) int64`
- `closeAccepted() bool`
- `close() bool`

`Factotum` is the default Plan 9 secret boundary. Use it when both ends are
Plan 9/9front and the app should rely on the native auth agent instead of
storing private key material in `.tab` files.

```o9
import "net.o9";

main {
    Factotum f = new Factotum();
    if(f.available()) {
        print("native secrets available\n");
    }
}
```

Methods:

- `Factotum()`
- `useMount(string path)`
- `path() string`
- `available() bool`
- `keys() string`
- `has(string query) bool`
- `ctl(string command) bool`
- `addKey(string spec) bool`
- `delKey(string query) bool`

`addKey` writes `key <spec>` to factotum's `ctl` file; `delKey` writes
`delkey <query>`. The object does not expose private key bytes. It only checks
and controls the native auth agent.

`NetToken` is the portable fallback for capability-style authorization strings,
mainly for Unix interop or exported `.tab` workflows where factotum is not
available. It stores the signing key as a `secret string`, so the object state
contains only sealed text. Issuing or verifying requires the caller to supply
the unlock key:

```o9
string unlock = passkey("operator passphrase", "my.app.net.unlock.v1");
string signing = passkey("signing seed", "my.app.net.signing.v1");

NetToken nt = new NetToken(unlock, signing);
string tok = nt.issue(unlock, "tcp!host!svc");
print(nt.verify(unlock, "tcp!host!svc", tok), "\n");
```

Methods:

- `NetToken(string unlock, string signingKey)`
- `issue(string unlock, string subject) string`
- `verify(string unlock, string subject, string token) bool`

For Plan 9-to-Plan 9 secure connections, the intended policy is:

- use `Factotum` for private secrets and authentication material;
- use `RemoteIdentity`/`KnownRemotes` for public identity pinning;
- use `NetToken` only when the app needs a portable text capability outside
  factotum.

`RemoteIdentity` and `KnownRemotes` implement SSH-style trust on first use.
The first public identity seen for a host is pinned in a local `.tab`; later
connections must match that fingerprint. A changed key fails until code calls
`replace` explicitly.

Remote identity files are public data, not secret material:

```text
remote_identity
    id=server
    host=tcp!host!svc
    algo=x25519
    pub=<public-key>
    fingerprint=<hash(host:algo:pub)>
```

Known remotes are local pinned state:

```text
known_remote
    id=tcp!host!svc
    algo=x25519
    pub=<public-key>
    fingerprint=<pinned-fingerprint>
```

Example:

```o9
RemoteIdentity id = new RemoteIdentity("/mnt/remote/exports/identity.tab");
KnownRemotes known = new KnownRemotes("/lib/o9/known-remotes.tab");

if(known.verifyOrPin("tcp!host!svc", id)) {
    print("identity ok\n");
}
```

`RemoteIdentity` methods:

- `RemoteIdentity(string path)`
- `set(string host, string algo, string pub)`
- `load(string path) bool`
- `write(string path) bool`
- `valid() bool`
- `host() string`
- `algo() string`
- `pub() string`
- `fingerprint() string`

`KnownRemotes` methods:

- `KnownRemotes(string path)`
- `ensure() bool`
- `known(string host) bool`
- `fingerprint(string host) string`
- `verify(string host, RemoteIdentity id) bool`
- `pin(string host, RemoteIdentity id) bool`
- `verifyOrPin(string host, RemoteIdentity id) bool`
- `replace(string host, RemoteIdentity id) bool`
- `read() string`

## Tabula

`Tabula` is the standard structured data object. It is built into the runtime
because it wraps libtab directly.

```o9
main {
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    Tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
    t.flush();
}
```

Constructors:

- `new Tabula(path)` opens an existing `.tab` file.
- `new Tabula(schema, "col1,col2")` creates an in-memory table whose first
  column is the row identity column `id`.

Methods:

- `schema() string`
- `has(string col) int64`
- `add(string id) int64`
- `write(string id, string col, string val) int64`
- `set(string col, string val) int64`
- `get(string col) string`
- `first() int64`
- `next() int64`
- `read() string`
- `serialize() string`
- `query(string col, string val) Tabula`
- `flush() int64`
- `close()`

`write` mutates a specific record by id. `set` mutates the current record after
`add`, `first`, or `next`.
