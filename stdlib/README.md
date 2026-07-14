# o9 Standard Library

The stdlib is written as ordinary o9 modules where possible. Plan 9 system
calls stay behind `function` raw-C helpers, and the public surface is an object
API.

For language syntax and application shape, read
[../docs/LANGUAGE.md](../docs/LANGUAGE.md). For build commands and complete
programs, read [../docs/QUICKSTART.md](../docs/QUICKSTART.md) and
[../docs/EXAMPLES.md](../docs/EXAMPLES.md).

Import modules by filename:

```o9
import "string.o9";
import "bytes.o9";
import "buffer.o9";
import "collections.o9";
import "file.o9";
import "io.o9";
import "math.o9";
import "namespace.o9";
import "net.o9";
import "path.o9";
import "process.o9";
import "random.o9";
import "time.o9";
import "draw.o9";
```

## String

`String` is the object wrapper for o9's built-in length-carrying `string`.
It covers common search, slice, case, replacement, repetition, and delimiter
helpers without introducing a second text class.

```o9
import "string.o9";

main {
    String s = new String("alpha,beta,gamma");
    print(s.field(",", 1), "\n");       // beta
    print(s.before(","), "\n");         // alpha
    print(s.after(","), "\n");          // beta,gamma
    print(s.replace("beta", "rio"), "\n");
}
```

Methods:

- `String(string s)`
- `set(string s)`
- `get() string`
- `length() int64`
- `empty() bool`
- `compare(string other) int64`
- `equals(string other) bool`
- `concat(string suffix) string`
- `indexOf(string needle) int64`
- `lastIndexOf(string needle) int64`
- `count(string needle) int64`
- `contains(string needle) bool`
- `startsWith(string prefix) bool`
- `endsWith(string suffix) bool`
- `slice(int64 start, int64 count) string`
- `trim() string`
- `lower() string`
- `upper() string`
- `replace(string needle, string repl) string`
- `repeat(int64 times) string`
- `field(string sep, int64 index) string`
- `line(int64 index) string`
- `before(string sep) string`
- `after(string sep) string`

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
- `mode() int64`
- `mtime() int64`
- `owner() string`
- `remove() bool`
- `mkdir() bool`
- `mkdirAll() bool`
- `isDir() bool`
- `list() string`
- `copyTo(string dest) int64`
- `moveTo(string dest) bool`

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

## Math

`Math` wraps the floating-point functions Plan 9 exposes through
`/sys/include/libc.h` and `libc.a`. The raw C calls stay inside nested
function objects in the `Math` class; the public surface is ordinary methods.

```o9
import "math.o9";

main {
    Math m = new Math();
    print(m.sqrt(9.0), "\n");          // 3
    print(m.pow(2.0, 8.0), "\n");      // 256
    print(m.fmod(7.5, 2.0), "\n");     // 1.5
}
```

Methods:

- `Math()`
- `sqrt(double x) double`
- `sin(double x) double`
- `cos(double x) double`
- `tan(double x) double`
- `asin(double x) double`
- `atan(double x) double`
- `atan2(double y, double x) double`
- `sinh(double x) double`
- `log(double x) double`
- `log10(double x) double`
- `exp(double x) double`
- `pow(double x, double y) double`
- `pow10(double x) double`
- `floor(double x) double`
- `ceil(double x) double`
- `fmod(double x, double y) double`
- `fabs(double x) double`
- `abs(int64 n) int64`

## Random

`Random` wraps Plan 9 libc's pseudo-random functions and the kernel-backed
entropy helpers. Use `seed` when you want repeatable pseudo-random sequences;
use `entropy`/`entropyBounded` when you want system randomness.

```o9
import "random.o9";

main {
    Random r = new Random();
    r.seed(12345);
    print(r.bounded(10), "\n");
    print(r.float(), "\n");
}
```

Methods:

- `Random()`
- `seed(int64 value) int64`
- `next() int64`
- `bounded(int64 max) int64`
- `nextLong() int64`
- `boundedLong(int64 max) int64`
- `float() double`
- `entropy() int64`
- `entropyBounded(int64 max) int64`

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
- `output(string command) string`

`Env` methods:

- `get(string name) string`
- `exists(string name) bool`
- `set(string name, string value) bool`
- `unset(string name) bool`
- `cwd() string`
- `chdir(string path) bool`

`run` and `output` execute through `/bin/rc -c`; `run` returns `0` when the
command exits cleanly, while `output` returns captured stdout/stderr text.

## Time

`time.o9` exposes basic wall-clock helpers.

```o9
import "time.o9";

main {
    Time t = new Time();
    DateTime d = new DateTime();

    print(t.now() > 0, "\n");
    print(d.stamp(), "\n");
}
```

`Time` methods:

- `Time()`
- `now() int64`
- `nsec() int64`
- `sleep(int64 ms) int64`
- `format(int64 sec) string`
- `parse(string text) int64`

`format` returns Plan 9 `ctime`-style text without the trailing newline.
`parse` accepts numeric epoch seconds.

`DateTime` is a calendar-shaped object. Its constructor captures the current
local time; epoch seconds remain available for interop with Plan 9 C, file
mtimes, and serialized data.

- `DateTime()`
- `setEpoch(int64 sec)`
- `set(int64 year, int64 month, int64 day, int64 hour, int64 minute, int64 second)`
- `setNow()`
- `epoch() int64`
- `text() string`
- `stamp() string`
- `year() int64`
- `month() int64`
- `day() int64`
- `hour() int64`
- `minute() int64`
- `second() int64`
- `weekday() int64`
- `yearday() int64`
- `zoneOffset() int64`

`text` returns Plan 9 `ctime` text. `stamp` returns `YYYY-MM-DD HH:MM:SS`
in the local timezone.

## Namespace

`namespace.o9` wraps `MountTable` in an object API. `MountTable` remains the
Tabula-backed transport data; `Namespace` is the object that builds and applies
that table.

Use `Namespace` for normal application code. Drop to `MountTable` only when
you want the lower-level `.tab` data representation.

```o9
import "namespace.o9";

main {
    Namespace ns = new Namespace();

    ns.root("/tmp/appns");
    ns.dir("cache", 493);
    ns.bindReplace("/tmp", "tmp");
    ns.apply();
}
```

`Namespace` methods:

- `Namespace()`
- `root(string path) bool`
- `load(string path) bool`
- `save(string path) bool`
- `reset()`
- `close()`
- `replaceFlag() int64`
- `beforeFlag() int64`
- `afterFlag() int64`
- `createFlag() int64`
- `dir(string path, int64 mode) bool`
- `bind(string old, string new, int64 flag) bool`
- `bindReplace(string old, string new) bool`
- `bindBefore(string old, string new) bool`
- `bindAfter(string old, string new) bool`
- `bindCreate(string old, string new) bool`
- `bindBeforeCreate(string old, string new) bool`
- `bindAfterCreate(string old, string new) bool`
- `mountsrv(string srv, string new, int64 flag, string aname) bool`
- `mountsrvReplace(string srv, string new, string aname) bool`
- `mountsrvBefore(string srv, string new, string aname) bool`
- `mountsrvAfter(string srv, string new, string aname) bool`
- `validate() bool`
- `apply() bool`
- `read() string`

## Draw

`DrawWindow` is the first libdraw-facing object. It keeps ordinary o9 state
for title, size, and colors, then hides the raw C helpers behind object
methods. Snapshot methods render through `libmemdraw`/`topng`, while `show`
opens a live `libdraw` surface and paints an o9-owned title band inside the
window.

The e2e draw test leaves its latest PNG at
`o9c/test/artifacts/o9_draw_snapshot.png` for inspection. Live windows are
manual because they require rio/devdraw; run `mk draw-window-demo` from a rio
session to open the demo window. `DrawVisualProbe` adds a headless visual
interaction loop for testing: render a PNG, send a synthetic click, then render
the next PNG.

```o9
import "draw.o9";

main {
    DrawWindow w = new DrawWindow("o9 draw snapshot", 96, 48);
    w.background(0x203040);
    w.accent(0xe0c040);
    w.snapshotPng("/tmp/o9_draw_snapshot.png");
    w.show(3000);

    DrawVisualProbe p = new DrawVisualProbe("probe", 128, 72);
    p.snapshotPng("/tmp/probe-before.png");
    p.click(64, 42);
    p.snapshotPng("/tmp/probe-after.png");
}
```

Methods:

- `DrawWindow(string title, int64 width, int64 height)`
- `title() string`
- `width() int64`
- `height() int64`
- `resize(int64 width, int64 height)`
- `background(int64 rgb)`
- `accent(int64 rgb)`
- `snapshot(string path) bool`
- `snapshotPng(string path) bool`
- `show(int64 milliseconds) bool`

`DrawVisualProbe` methods:

- `DrawVisualProbe(string title, int64 width, int64 height)`
- `click(int64 x, int64 y) bool`
- `nextEvent() int64`
- `eventType() string`
- `eventX() int64`
- `eventY() int64`
- `eventButtons() int64`
- `eventCount() int64`
- `snapshot(string path) bool`
- `snapshotPng(string path) bool`
- `count() int64`
- `pressed() bool`

`DrawEventLoop` is the CSP event bus used by the probe and future live
widgets. Inputs send one packed scalar event over a channel; `next()` decodes
that event into accessor state on the loop. The channel runtime can carry
typed o9 values; this loop still uses a compact scalar event code until the
draw API grows a dedicated event value.

`DrawEventLoop` methods:

- `start()`
- `stop()`
- `running() bool`
- `mouse(int64 x, int64 y, int64 buttons)`
- `key(int64 keyCode)`
- `resize(int64 width, int64 height)`
- `next() int64`
- `eventType() string`
- `eventX() int64`
- `eventY() int64`
- `eventButtons() int64`
- `eventKey() int64`
- `eventWidth() int64`
- `eventHeight() int64`
- `count() int64`

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
as the first-class `.tab` data type.

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
