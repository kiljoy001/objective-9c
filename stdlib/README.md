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
import "9p.o9";
import "string.o9";
import "bytes.o9";
import "buffer.o9";
import "cli.o9";
import "collections.o9";
import "config.o9";
import "dir.o9";
import "file.o9";
import "format.o9";
import "io.o9";
import "log.o9";
import "math.o9";
import "namespace.o9";
import "net.o9";
import "path.o9";
import "process.o9";
import "random.o9";
import "result.o9";
import "rune.o9";
import "service.o9";
import "sync.o9";
import "testing.o9";
import "time.o9";
import "draw.o9";
import "rtext.o9";
import "view.o9";
```

## Start Here: Application Developer

You do not need raw C, `spawn`, or `await` for ordinary application
scaffolding. Start with these three modules:

- `cli.o9`: argv, flags, options, environment, usage.
- `config.o9`: small key/value profiles and settings files.
- `service.o9`: start a 9P view service or a view-less facade.

A complete CLI:

```o9
import "cli.o9";
import "config.o9";

main {
    Args args = new Args(1);
    string configPath = args.opt("config", "/tmp/hello.conf");
    Config config = new Config(configPath);
    string name = args.opt("name", config.get("name", "world"));
    print("hello, ", name, "\n");
}
```

A complete 9P service:

```o9
import "service.o9";

class HelloViews {
    ViewController;

    internal method FileTree display(string id, string caller) {
        FileTree root = new FileTree();
        root.text("status", "hello from o9\n", false);
        return root;
    }

    internal method string readText(string id, string path) { return ""; }
    internal method int64 writeText(string id, string path, int64 offset,
                                    string text, bool truncate) { return -1; }
}

main {
    HelloViews views = new HelloViews();
    Service service = new Service("helloservice");
    service.run(views);
}
```

Runnable copies live in `../demo/hello_cli.o9` and
`../demo/hello_service.o9`. For a discoverable list of existing programs, see
[../docs/APP_DEVELOPER.md](../docs/APP_DEVELOPER.md).

## CLI

`Args` hides argv and option scanning behind one object.

```o9
Args args = new Args(1);              // skip argv[0]; use 2 for services
args.count();                         // number of user arguments
args.at(0);                           // first positional argument
args.opt("port", "6667");             // -port 6667 or --port=6667
args.flag("verbose");                 // -verbose or --verbose
args.intOption("limit", 100);         // parsed integer or default
args.env("HOME", "/tmp");             // environment or default
args.require(2, "usage: app INPUT OUTPUT");
```

`args.loadLine("-n 3 --verbose")` replaces the argument list from a simple
whitespace-separated line. It is intended for tests and ctl handlers, not for
shell quoting.

## Config

`Config` reads and writes small line-oriented files:

```text
name = alice
port = 6667
# comment
```

```o9
Config config = new Config("/tmp/app.conf");
config.get("name", "world");
config.set("port", "6667");
config.has("name");
config.remove("port");
config.count();
config.save();
```

Whitespace around keys and values is trimmed. Use
`setSeparator("\t")` for tab-separated records. Missing files are treated as
empty configurations. `save()` writes the current key order. Config uses
normal file permissions; store secrets in `Vault` or a private directory.

## Service

`Service.run(ViewController view)` registers the controller and enters
`serve()`. `Service.start()` enters `serve()` without a view controller, for
small auth facades.

```o9
Service service = new Service("myapp");
service.run(views);       // blocks
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
- `isHex(string hex) bool`
- `fromHex(string hex) bool`
- `compare(string other) int64`
- `equals(string other) bool`

Out-of-range byte reads return `0`; out-of-range writes leave the value
unchanged. `hex()` is the standard way to carry binary data through tabula
text. `fromHex()` accepts uppercase or lowercase hex, stores the decoded bytes
in the receiver, and returns false for invalid or odd-length input.

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

## Format

`format.o9` builds text without `snprint`, `sprint`, `smprint`, or repeated
`strcat`.

```o9
import "format.o9";

main {
    Format f = new Format();
    f.str("user ");
    f.str("alice");
    f.str(" ");
    f.dec(42);
    f.str(" ");
    f.hex(255);
    f.nl();
    print(f.text());
}
```

Methods:

- `Format()`
- `str(string text)`
- `dec(int64 value)`
- `hex(int64 value)`
- `oct(int64 value)`
- `boolean(bool value)`
- `nl()`
- `spaces(int64 count)`
- `zeros(int64 count)`
- `pad(int64 width)` — append spaces until the current text is `width` bytes
- `zeroPad(int64 width)` — prepend zeroes until the current text is `width` bytes
- `clear()`
- `length() int64`
- `text() string`

## Log

`log.o9` provides leveled application logging.

```o9
import "log.o9";

main {
    Log log = new Log("myapp");
    log.level(1);                 // 0 debug, 1 info, 2 warn, 3 error
    log.info("started");
    log.toFile("/tmp/myapp.log"); // append instead of printing
    log.error("request failed");
}
```

Methods:

- `Log(string name)`
- `level(int64 level)`
- `timestamps(bool enabled)`
- `toFile(string path)`
- `debug(string text)`
- `info(string text)`
- `warn(string text)`
- `error(string text)`
- `fatal(string text)` — logs at ERROR and raises the o9 call error

## Result

`result.o9` is for APIs that prefer returning a success flag and message over
`try`/`fail`.

```o9
import "result.o9";

main {
    Result r = new Result(false, "", "not found");
    if(r.failed()) {
        print(r.err(), "\n");
    }
}
```

Members:

- `Result(bool ok, string value, string errmsg)`
- `ok` (property)
- `value` (property)
- `errmsg` (property)
- `succeeded() bool`
- `failed() bool`
- `unwrap(string fallback) string`
- `err() string`

## Sync

`sync.o9` exposes libthread-backed synchronization. A blocked lock or wait
does not block the object's actor dispatch loop.

```o9
import "sync.o9";

main {
    Mutex m = new Mutex();
    m.lock();
    m.unlock();
    m.close();
}
```

`Mutex`: `lock()`, `unlock()`, `isOpen()`, `close()`.

`WaitGroup`: `add(int64 delta)`, `done()`, `wait()`, `isOpen()`, `close()`.

`Semaphore`: `Semaphore(int64 count)`, `acquire()`, `release()`, `isOpen()`,
`close()`.

`Once`: `claim() bool` — true only for the first caller.

`Pool`: `Pool(int64 size)`, `acquire()`, `release()`, `close()`. This is a
concurrency limiter; pair it with a channel for a job queue.

## Dir

`dir.o9` provides typed directory entries and iterative tree helpers.

```o9
import "dir.o9";

main {
    Dir d = new Dir("/tmp");
    DirList entries = d.entries();
    int64 i = 0;
    while(i < entries.length()) {
        DirEntry e = entries.get(i);
        print(e.name, " ", e.isdir, " ", e.size, "\n");
        i = i + 1;
    }
}
```

`DirEntry` fields: `name`, `path`, `isdir`, `size`, `mode`, `mtime`,
`owner`.

`Dir`: `Dir(string path)`, `file()`, `entries() DirList`.

`DirList`: `length()`, `get(int64 index)`, `add(DirEntry)`, `set`.

`DirTree` adds iterative recursion:

```o9
DirTree tree = new DirTree("/tmp/source");
DirList all = tree.walk();
tree.copyTree("/tmp/destination");
tree.removeTree();
```

## 9P

`9p.o9` is a low-level 9P2000 framing and reply kit for custom servers. Most
applications should use `service.o9` and `FileTree` instead.

```o9
import "9p.o9";

main {
    NineP p = new NineP();
    string reply = p.error(7, "not found");
    print(p.type(reply), " ", p.tag(reply), "\n");
}
```

Methods:

- `read(int64 fd, int64 max) string`
- `write(int64 fd, string message) int64`
- `type(string message) int64`
- `tag(string message) int64`
- `fid(string message) int64`
- `error(int64 tag, string text) string`
- `readReply(int64 tag, string data) string`
- `versionReply(int64 tag, int64 msize, string version) string`

## Rune

`rune.o9` treats a UTF-8 string as runes instead of bytes.

```o9
import "rune.o9";

main {
    Runes r = new Runes("naïve");
    print(r.count(), " ", r.at(2), " ", r.offset(3), "\n");
    print(r.slice(1, 2), "\n");
}
```

Methods:

- `Runes(string text)`
- `text() string`
- `count() int64`
- `at(int64 index) int64` — code point, or `-1`
- `offset(int64 index) int64` — byte offset, or `-1`
- `slice(int64 start, int64 count) string`
- `fromRune(int64 value) string`

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
- `readn(int64 n) string`
- `readLine() string`
- `readAt(int64 offset, int64 n) string`
- `write(string data) int64`
- `writeAt(int64 offset, string data) int64`
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
- `copyFrom(string src) int64`
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

For a long-lived byte stream, use `StreamReader` and `StreamWriter`; the
underlying `Biobuf` stays open across calls instead of reopening the file.

```o9
import "io.o9";

main {
    Lines lines = new Lines("/tmp/o9-note");
    while(!(lines.eof())) {
        print(lines.next(), "\n");
    }
    lines.close();
}
```

`StreamReader`: `read(int64 n)`, `readLine()`, `position()`,
`seek(int64 pos)`, `copyTo(StreamWriter)`, `endOfStream()`, `isOpen()`,
`close()`.

`StreamWriter`: `write(string)`, `writeBytes(Bytes)`, `flush()`,
`position()`, `isOpen()`, `close()`.

`Lines`: `Lines(string path)`, `next()`, `eof()`, `close()`. `next()` returns
`""` at EOF, so check `eof()` when empty lines are meaningful.

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

For direct argv execution with captured streams, use `Cmd`:

```o9
import "process.o9";

main {
    Cmd c = new Cmd("/bin/echo");
    c.arg("hello");
    c.stdin("ignored\n");
    CmdResult r = c.run();
    print(r.ok, " ", r.out, r.err, "\n");
}
```

`Cmd`: `Cmd(string program)`, `arg(string)`, `stdin(string)`, `run()`.

`CmdResult`: `ok`, `status`, `out`, `err` properties; `failed()`,
`output()`, `error()`.

`Pipeline` builds a shell pipeline string and runs it through `rc`:

```o9
Pipeline p = new Pipeline();
p.add("cat /tmp/input");
p.add("wc -l");
CmdResult r = p.run();
```

Callers are responsible for quoting arguments inside pipeline stages.

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
tabula-backed transport data; `Namespace` is the object that builds and applies
that table.

Use `Namespace` for normal application code. Drop to `MountTable` only when
you want the lower-level `.tab` data representation. A namespace recipe is
inert data until local code validates and applies it.

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
- `query(string column, string value) tabula`

## Draw

`DrawWindow` is the first libdraw-facing object. It keeps ordinary o9 state
for title, size, colors, a live canvas handle, and a `DrawEventLoop`, then
hides the raw C helpers behind object methods. Snapshot methods render through
`libmemdraw`/`topng`, while `open()` creates a live `libdraw` surface for
widgets to draw into. Use `canvas()` and `events()` to get the object handles
for drawing and input.

The e2e draw test leaves its latest PNG at
`o9c/test/artifacts/o9_draw_snapshot.png` for inspection. Live windows are
manual because they require rio/devdraw; run `mk draw-window-demo` from a rio
session to open the demo window. Manual demo sources live under `demo/`;
`stdlib/` should stay focused on library objects and e2e fixtures.
`DrawVisualProbe` adds a headless visual
interaction loop for testing: render a PNG, send a synthetic click, then render
the next PNG. `DrawCanvas` is the low-level drawing surface. `DrawFrame` batches
widget drawing commands and flushes them to libdraw in small chunks, so normal
UI code should add widgets to a window and call `update()` instead of drawing
each rectangle directly. `DrawButton` is the first reusable widget object: it
owns label, geometry, enabled state, hit testing, mouse-event activation, and
frame drawing.
`DrawTextInput` is a single-line focused text field with placeholder text,
cursor movement, printable-key insertion, backspace/delete, and frame drawing.
`DrawTextView` is a clipped multi-line text viewport with line and column
offsets. `DrawScrollText` composes that viewport with vertical and horizontal
scrollbars, keeping bar ranges and text offsets synchronized when text, wrap
mode, or viewport size changes.
`DrawTable` is a fixed-column table widget with headers, visible cells,
selection, row scrolling, mouse selection, keyboard movement, and frame
drawing.
`DrawButtonDemo` opens a real libdraw window with a clickable button whose
on-screen status text changes after each click.
`DrawBox` is the shared widget box model: position, size, colors, and hit
testing. `DrawLabel` is the shared text object built on the same box model.
`DrawScrollbar` is the reusable vertical/horizontal low-level control behind
`DrawScrollText`; use it directly when the scrolled content is not text.
Draw widgets are reactive in the small Plan 9 sense: mutating a widget marks it
dirty/layout-dirty, panels report dirty when any child changes, and
`DrawWindow` repaints automatically while it handles routed events. The normal
live loop can call `nextRoutedEvent()` and mutate application state around it.
For manual batching, call `setReactive(false)` on the window or on a specific
widget, then call `update()` or `repaint()` when the batch is ready.
`DrawMenu` wraps Plan 9's button-menu primitive for live windows, and
`DrawClipboard` reads/writes the rio snarf buffer through `/dev/snarf`.

`DrawPanel.pack(child, side, expand, fillx, filly, gravity)` adds a child to
the edge packer. Sides are 0 north, 1 south, 2 east, 3 west. Gravity is 0
center, 1 north, 2 south, 3 east, 4 west, 5 northeast, 6 northwest,
7 southeast, 8 southwest. Call `layoutPack(padding, spacing)` after sizing
the panel. It preserves each child's preferred size across resizes.

`rtext.o9` adds `DrawRichText` for a laid-out stream of colored text, links,
Plan 9 draw image files, and inline `DrawWidget`s. Text wraps at spaces and
splits overwide words at UTF-8 rune boundaries. `linkAt(x, y)` resolves a
link under the pointer. `handleMouse(x, y, buttons)` routes clicks to inline
widgets and records clicked links for `takeLink()`.
`hitCell` and `byteAt` map pointer positions to UTF-8 byte boundaries.
`selectText` and `selectedText` support partial-word selection; `select`
selects whole laid-out cells. `addTextFont` and `addLinkFont` accept a 9front
font path for individual spans. Layout uses each font's width, ascent, and
height; paths that cannot be opened use the active libdraw font. Repeated
paths share a cached font. Call `closeFonts()` before closing the display.
`fontAvailable(canvas, path)` reports whether a path opened successfully.
9front includes, for example, `lucidasans/unicode.10.font`,
`lucidasans/italicunicode.10.font`, `lucidasans/boldunicode.13.font`, and
`lucidasans/typeunicode.12.font` under `/lib/font/bit/`.

```o9
import "rtext.o9";

main {
    DrawRichText text = new DrawRichText(16, 16, 320, 160);
    text.addText("Read ", 0x203040);
    text.addLinkFont("the guide", "https://example.com/guide", 0x2244cc,
        "/lib/font/bit/lucidasans/boldunicode.10.font");
    text.breakLine();
    text.addImage("/tmp/icon.img", 16, 16);
    DrawWindow window = new DrawWindow("rich text", 360, 200);
    if(window.open()) {
        window.add(text);
        window.update();
    }
}
```

```o9
import "draw.o9";

main {
    DrawWindow w = new DrawWindow("o9 draw snapshot", 96, 48);
    w.background(0x203040);
    w.accent(0xe0c040);
    w.snapshotPng("/tmp/o9_draw_snapshot.png");

    DrawWindow live = new DrawWindow("widgets", 320, 160);
    if(live.open()) {
        DrawButton button = new DrawButton("ok", 24, 48, 96, 30);
        DrawLabel label = new DrawLabel("ready", 24, 90, 180, 24);
        DrawTextInput input = new DrawTextInput("", 24, 122, 160, 28);
        input.setPlaceholder("name");
        live.add(button);
        live.add(label);
        live.add(input);
        live.update();
        live.close();
    }

    DrawVisualProbe p = new DrawVisualProbe("probe", 128, 72);
    p.snapshotPng("/tmp/probe-before.png");
    p.click(64, 42);
    p.snapshotPng("/tmp/probe-after.png");

    DrawButton b = new DrawButton("ok", 10, 20, 64, 24);
    b.position(10, 20);
    b.size(64, 24);
    b.color(0x466080, 0xffffff);
    b.click(16, 24);
    print(b.text(), " ", b.count(), "\n");

    DrawLabel label = new DrawLabel("status", 10, 54, 120, 20);
    label.color(0x203040, 0xffffff);

    DrawScrollText scrollText = new DrawScrollText("alpha\nbeta\ngamma", 150, 20, 150, 80);
    scrollText.setWrap(false);

    DrawButtonDemo demo = new DrawButtonDemo("click text test", 460, 300);
    demo.show();

    DrawMenu menu = new DrawMenu();
    menu.add("snarf status");
    menu.add("paste snarf");
    menu.add("quit");
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
- `setReactive(bool value)`
- `reactive() bool`
- `open() bool`
- `close() bool`
- `isOpen() bool`
- `canvasId() int64`
- `canvas() DrawCanvas`
- `events() DrawEventLoop`
- `bindCanvas(DrawCanvas canvas)`
- `add(DrawWidget widget) bool`
- `widgets() int64`
- `needsRepaint() bool`
- `repaint() bool`
- `update() bool`
- `routeEvent() bool`
- `nextRoutedEvent() int64`
- `focus(int64 index)`
- `focusIndex() int64`
- `layoutVertical(int64 padding, int64 spacing)`
- `layoutHorizontal(int64 padding, int64 spacing)`
- `layoutFlow(int64 padding, int64 spacing)`
- `poll() int64`
- `nextEvent() int64`
- `clear() bool`
- `flush() bool`
- `eventType() string`
- `eventX() int64`
- `eventY() int64`
- `eventButtons() int64`
- `eventKey() int64`
- `eventWidth() int64`
- `eventHeight() int64`
- `snapshot(string path) bool`
- `snapshotPng(string path) bool`
- `show(int64 milliseconds) bool`

`DrawCanvas` methods:

- `DrawCanvas()`
- `attach(int64 handle)`
- `id() int64`
- `ready() bool`
- `clear(int64 color) bool`
- `fillRect(int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `borderRect(int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `borderRectN(int64 x, int64 y, int64 width, int64 height, int64 thickness, int64 color) bool`
- `text(string value, int64 x, int64 y, int64 color) bool`
- `textBox(string value, int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `textWidth(string value) int64`
- `fontHeight() int64`
- `flush() bool`
- `readEventCode() int64`

`DrawFrame` methods:

- `DrawFrame()`
- `reset(int64 color)`
- `clear(int64 color)`
- `count() int64`
- `fillRect(int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `borderRect(int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `borderRectN(int64 x, int64 y, int64 width, int64 height, int64 thickness, int64 color) bool`
- `text(string value, int64 x, int64 y, int64 color) bool`
- `textBox(string value, int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `textLeft(string value, int64 x, int64 y, int64 width, int64 height, int64 color) bool`
- `flush(DrawCanvas canvas) bool`

`DrawWidget` base methods:

- `position(int64 x, int64 y)`
- `size(int64 width, int64 height)`
- `bounds(int64 x, int64 y, int64 width, int64 height)`
- `preferred(int64 width, int64 height)`
- `preferredWidth() int64`
- `preferredHeight() int64`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `setVisible(bool value)`
- `setEnabled(bool value)`
- `setFocusable(bool value)`
- `setFocused(bool value)`
- `setRole(string value)`
- `setAction(string value)`
- `setReactive(bool value)`
- `reactive() bool`
- `markDirty()`
- `invalidate()`
- `requestLayout()`
- `clearDirty()`
- `clearLayout()`
- `isDirty() bool`
- `needsLayout() bool`
- `contains(int64 x, int64 y) bool`
- `capturesMouse() bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `handleKey(int64 key) bool`

`DrawBox` methods:

- `DrawBox(int64 x, int64 y, int64 width, int64 height)`
- `position(int64 x, int64 y)`
- `size(int64 width, int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `x() int64`
- `y() int64`
- `width() int64`
- `height() int64`
- `right() int64`
- `bottom() int64`
- `background() int64`
- `foreground() int64`
- `borderColor() int64`
- `contains(int64 x, int64 y) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawLabel` methods:

- `DrawLabel(string text, int64 x, int64 y, int64 width, int64 height)`
- `text() string`
- `setText(string text)`
- `position(int64 x, int64 y)`
- `size(int64 width, int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `setVisible(bool value)`
- `visible() bool`
- `x() int64`
- `y() int64`
- `width() int64`
- `height() int64`
- `background() int64`
- `foreground() int64`
- `borderColor() int64`
- `contains(int64 x, int64 y) bool`
- `draw(DrawCanvas canvas) bool`
- `drawText(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawButton` methods:

- `DrawButton(string text, int64 x, int64 y, int64 width, int64 height)`
- `text() string`
- `setText(string text)`
- `move(int64 x, int64 y)`
- `position(int64 x, int64 y)`
- `resize(int64 width, int64 height)`
- `size(int64 width, int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `x() int64`
- `y() int64`
- `width() int64`
- `height() int64`
- `background() int64`
- `foreground() int64`
- `borderColor() int64`
- `setEnabled(bool value)`
- `isEnabled() bool`
- `contains(int64 x, int64 y) bool`
- `hover(int64 x, int64 y) bool`
- `hovered() bool`
- `pressed() bool`
- `count() int64`
- `release()`
- `click(int64 x, int64 y) bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawTextInput` methods:

- `DrawTextInput(string text, int64 x, int64 y, int64 width, int64 height)`
- `text() string`
- `setText(string text)`
- `placeholder() string`
- `setPlaceholder(string text)`
- `cursorIndex() int64`
- `setCursor(int64 index)`
- `count() int64`
- `moveLeft() bool`
- `moveRight() bool`
- `home() bool`
- `end() bool`
- `insertKey(int64 key) bool`
- `backspace() bool`
- `deleteForward() bool`
- `clear() bool`
- `position(int64 x, int64 y)`
- `size(int64 width, int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `setEnabled(bool value)`
- `isEnabled() bool`
- `contains(int64 x, int64 y) bool`
- `hover(int64 x, int64 y) bool`
- `hovered() bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `handleKey(int64 key) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawTextView` methods:

- `DrawTextView(string text, int64 x, int64 y, int64 width, int64 height)`
- `text() string`
- `setText(string text)`
- `setWrap(bool value)`
- `wrap() bool`
- `rows() int64`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `grid(int64 rgb)`
- `setLineHeight(int64 height)`
- `line(int64 row) string`
- `visibleLines() int64`
- `pageLines() int64`
- `visibleColumns() int64`
- `maxColumn() int64`
- `maxFirstLine() int64`
- `maxFirstColumn() int64`
- `setOffset(int64 row, int64 column)`
- `firstVisibleLine() int64`
- `firstVisibleColumn() int64`
- `scrollLines(int64 delta) bool`
- `scrollColumns(int64 delta) bool`
- `contains(int64 x, int64 y) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawScrollText` methods:

- `DrawScrollText(string text, int64 x, int64 y, int64 width, int64 height)`
- `text() string`
- `setText(string text)`
- `setWrap(bool value)`
- `wrap() bool`
- `position(int64 x, int64 y)`
- `size(int64 width, int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `grid(int64 rgb)`
- `setLineHeight(int64 height)`
- `firstVisibleLine() int64`
- `firstVisibleColumn() int64`
- `rows() int64`
- `maxFirstLine() int64`
- `maxFirstColumn() int64`
- `visibleLines() int64`
- `visibleColumns() int64`
- `setOffset(int64 row, int64 column)`
- `scrollLines(int64 delta) bool`
- `scrollColumns(int64 delta) bool`
- `contains(int64 x, int64 y) bool`
- `capturesMouse() bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `handleKey(int64 key) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawTable` methods:

- `DrawTable(int64 x, int64 y, int64 width, int64 height, int64 columns, int64 rows)`
- `columns() int64`
- `rows() int64`
- `setRows(int64 rows)`
- `setRowHeight(int64 height)`
- `setHeaderHeight(int64 height)`
- `color(int64 background, int64 foreground)`
- `border(int64 rgb)`
- `grid(int64 rgb)`
- `headerColor(int64 background)`
- `selectedColor(int64 background)`
- `setHeader(int64 col, string text) bool`
- `header(int64 col) string`
- `setCell(int64 row, int64 col, string text) bool`
- `cell(int64 row, int64 col) string`
- `clear()`
- `columnWidth() int64`
- `visibleRows() int64`
- `setFirstRow(int64 row)`
- `firstVisibleRow() int64`
- `scrollRows(int64 delta) bool`
- `select(int64 row) bool`
- `selectedRow() int64`
- `rowAt(int64 y) int64`
- `columnAt(int64 x) int64`
- `contains(int64 x, int64 y) bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `handleKey(int64 key) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawScrollbar` methods:

- `DrawScrollbar(int64 x, int64 y, int64 width, int64 height)`
- `setVertical(bool value)`
- `isVertical() bool`
- `setRange(int64 low, int64 high, int64 page)`
- `setValue(int64 value)`
- `scrollBy(int64 delta) bool`
- `pageBackward() bool`
- `pageForward() bool`
- `value() int64`
- `minimum() int64`
- `maximum() int64`
- `pageSize() int64`
- `isDragging() bool`
- `hovered() bool`
- `thumbLength() int64`
- `thumbStart() int64`
- `thumbEnd() int64`
- `thumbContains(int64 x, int64 y) bool`
- `contains(int64 x, int64 y) bool`
- `capturesMouse() bool`
- `handleMouse(int64 x, int64 y, int64 buttons) bool`
- `handleKey(int64 key) bool`
- `draw(DrawCanvas canvas) bool`
- `drawFrame(DrawFrame frame) bool`

`DrawButtonDemo` methods:

- `DrawButtonDemo(string title, int64 width, int64 height)`
- `background(int64 rgb)`
- `accent(int64 rgb)`
- `show() bool`

`DrawMenu` methods:

- `DrawMenu()`
- `add(string label) bool`
- `clear()`
- `count() int64`
- `last() int64`
- `label(int64 index) string`
- `hit(int64 handle, int64 button, int64 x, int64 y, int64 buttons) int64`

`DrawClipboard` methods:

- `DrawClipboard()`
- `read() string`
- `write(string value) bool`

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
widgets. Inputs send typed `DrawEvent` values over `chan<DrawEvent>`;
`next()` stores the most recent event in accessor state on the loop.

`DrawEvent` fields:

- `kind int64` (`1` mouse, `2` key, `3` resize)
- `x int64`
- `y int64`
- `buttons int64`
- `key int64`
- `width int64`
- `height int64`

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
    NetConn c = dial tcp example.com:80;
    if(c.isOpen()) {
        c.write("GET / HTTP/1.0\r\n\r\n");
        print(c.read(512));
        c.close();
    }
}
```

`dial protocol host:port` constructs a `NetConn` and attempts to open it. The compiler
translates the colon to Plan 9's `protocol!host!service` address form. For
example, `dial udp 127.0.0.1:9000` produces a UDP connection. `NetConn.dial()`
also remains available when the address is computed at run time.

`NetConn` methods:

- `NetConn(string address)`
- `endpoint() string`
- `dial() bool`
- `isOpen() bool`
- `read(int64 max) string`
- `readLine(int64 max) string`
- `write(string data) int64`
- `writeLine(string line) int64`
- `setTimeout(int64 ms) bool`
- `close() bool`

`readLine` buffers bytes until `\n` or `max`; `writeLine` appends `\n`.
`setTimeout` writes `timeout <ms>` to the connection's `/net/.../ctl` file and
returns `false` for path-backed connections that have no control directory.

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
- `user() string`
- `caller() string`
- `blessed() bool`
- `isUser(string name) bool`
- `isCaller(string name) bool`
- `verify(string name) bool`
- `available() bool`
- `keys() string`
- `has(string query) bool`
- `ctl(string command) bool`
- `addKey(string spec) bool`
- `delKey(string query) bool`

`user` returns the local Plan 9 user. `caller` returns the current 9P request
user when a method is invoked through the generated app facade, falling back
to the local user outside a facade call. That name is metadata. `blessed`
returns true only when the current clone session has completed a generated
facade `ctl` login verified by Plan 9 `auth_userpasswd` through factotum.
`isCaller` and `verify` require both: the request must be blessed and the
blessed caller name must match.

The default generated facade command is:

```rc
sid=`{cat /mnt/app/clone}
echo 'login scott password' > /mnt/app/$sid/ctl
```

The password is transient `ctl` input, not policy data. The generated server
wipes its local command buffer after the factotum check and stores only the
session result: blessed/unblessed plus the verified user name. For networked
mounts, protect the transport separately if you do not want the login command
visible on the wire.

`addKey` writes `key <spec>` to factotum's `ctl` file; `delKey` writes
`delkey <query>`. The object does not expose private key bytes. It checks
caller identity and controls the native auth agent without handing raw secrets
to o9 code.

`FactotumAdmin` is the small app-policy layer over `Factotum.verify()`. It does
not create Plan 9 accounts and does not edit `/adm/users`; it records which
factotum-blessed Plan 9 user is allowed to administer this o9 app facade. The
policy is stored as a `.tab` file so first-launch bootstrap is explicit and
auditable:

```o9
import "net.o9";

class Controller {
    private FactotumAdmin auth;

    method Controller(string firstAdmin) {
        auth = new FactotumAdmin("/usr/scott/lib/myapp.admin.tab", firstAdmin);
    }

    method bool mutate(string value) {
        if(!auth.isAdmin()) {
            return false;
        }
        // mutation goes here
        return true;
    }
}
```

The constructor takes `(policyPath, firstAdmin)`. If `policyPath` already
contains policy data, the file wins and `firstAdmin` is ignored. If the file is
empty or missing, `firstAdmin` is written as the initial admin.

Methods:

- `FactotumAdmin(string policyPath, string firstAdmin)`
- `ensure(string firstAdmin) bool`
- `load() bool`
- `configured() bool`
- `admin() string`
- `caller() string`
- `blessed() bool`
- `isAdmin() bool`
- `is(string user) bool`
- `setAdmin(string nextAdmin) bool`
- `read() string`

`setAdmin` only succeeds when the current caller is already the configured
admin. This makes admin rotation an authenticated app action instead of a
manual edit to the policy file.

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

## tabula

`tabula` is the standard structured data object. It is built into the runtime
as the first-class `.tab` data type. A tabula is one collection of entries; an
entry is an id value plus attached named values.

```o9
main {
    tabula t = new tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    print(t.value("a", "item"), "\n");

    tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
    t.flush();
}
```

Constructors:

- `new tabula(path)` opens an existing `.tab` file.
- `new tabula(schema, "col1,col2")` creates an in-memory document whose
  first column is the entry identity column `id`.
- `new tabula<Struct>(schema)` creates an in-memory document whose columns
  are derived from `Struct` fields. The first field must be `string` and is
  the entry id. This is positional: there is no `id` keyword or annotation.
  Put the key field first.

Methods:

- `schema() string`
- `has(string col) int64`
- `add(string id) int64`
- `write(string id, string col, string val) int64`
- `write(Struct record) int64` on `tabula<Struct>`
- `remove(string id) int64`
- `set(string col, string val) int64`
- `get(string col) string`
- `value(string id, string col) string`
- `first() int64`
- `next() int64`
- `read() string`
- `serialize() string`
- `query(string col, string val) tabula`
- `row(string id) Struct` on `tabula<Struct>`
- `flush() int64`
- `sync() int64`
- `push() int64`
- `close()`

`add` and `write` require a non-empty entry id; `nil` is reserved for the
hidden canonical nil entry. `nil` values are semantic nil, not empty strings:
writing nil clears the attached value, so the serialized entry omits that
`col=` line. `write` mutates a specific entry by id. `remove` collapses an
entry into the hidden nil entry, so it disappears from iteration, query, and
serialization. `value` reads one attached value by entry id and value name
without changing the current cursor. `set` and `get` operate on the current
entry after `add`, `first`, or `next`.

Typed tabula keeps schemas DRY when a `.tab` represents repeated copies of one
struct. The first field is the identity field; in this example `sys` is the
entry id because it appears first:

```o9
struct NdbEntry {
    string sys;
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
    e = entries.row("box1");
}
```

Binary data should be stored as hex text in a column named `0x`:

```o9
import "bytes.o9";

main {
    Bytes b = new Bytes("payload");
    tabula file = new tabula("file", "name,kind,0x");

    file.write("p", "name", "payload.bin");
    file.write("p", "kind", "application/octet-stream");
    file.write("p", "0x", b.hex());
}
```

## View

`view.o9` defines the `ViewController` interface. The compiler/runtime also provides `FileTree`, an actor-owned dynamic 9P directory tree carrier.

```o9
import "view.o9";

class MyController {
    ViewController;

    internal method FileTree display(string id, string caller) {
        FileTree t = new FileTree();
        t.dir("docs");
        t.text("docs/hello", "Hello, " + caller + "\n", false);
        return t;
    }

    internal method string readText(string id, string path) {
        return "";
    }

    internal method int64 writeText(string id, string path, int64 offset, string text, bool truncate) {
        return -1;
    }
}

main {
    MyController c = new MyController();
    viewController(c);
    serve();
}
```

`ViewController` interface methods:

- `display(string id, string caller) FileTree`
- `readText(string id, string path) string`
- `writeText(string id, string path, int64 offset, string text, bool truncate) int64`

`FileTree` methods:

- `FileTree()`
- `dir(string path) int64`
- `text(string path, string data, bool writable) int64`
- `live(string path, bool writable) int64`
- `remove(string path) int64`
- `register(string id) int64`
- `apply(MountTable m) int64`
- `close()`

For architecture and 9P interaction, read [../docs/VIEWS.md](../docs/VIEWS.md).

## Vault

`Vault` is the built-in isolated memory arena (`O9KeyArena`) for cryptographic
key custody, RAM slot encryption, and at-rest file and table encryption.

```o9
main {
    // Construct with passphrase and salt
    Vault v = new Vault("hunter2", "my.app.salt");

    // Seal and open text in memory
    string blob = v.seal("secret message");
    string text = v.open(blob);
    print(text, "\n");

    // Defense-in-depth RAM slot storage (encrypted in memory)
    v.put("token", "my-api-token");
    print(v.get("token"), "\n");
    v.drop("token");

    // Encrypt tabula at rest
    tabula t = new tabula("keys", "service,pass");
    t.add("entry1");
    t.set("service", "plan9");
    t.set("pass", "shhh");
    v.sealTab("/tmp/keys.enc", t);

    tabula restored = v.openTab("/tmp/keys.enc");
    print(restored.get("pass"), "\n");

    // Zero memory and invalidate keys
    v.wipe();
    v.close();
}
```

Constructors:

- `Vault()`: Initializes an ephemeral random 32-byte key.
- `Vault(string key_or_pass)`: Uses a 64-hex key directly, or derives a 32-byte key from a passphrase with an auto-generated 16-byte random salt.
- `Vault(string pass, string salt)`: Derives a 32-byte key from a passphrase and explicit salt via Argon2id (salt >= 8 bytes).

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

## Testing

`Test` provides an xUnit-style test harness for writing native unit and
integration tests in o9. In accordance with the Plan 9 `o9test` philosophy,
individual assertion failures do not halt execution, allowing a single run to
uncover all regressions.

Features:
- Fixtures: isolated temporary scratch directories (`tmpDir`, `tmpPath`, `cleanTmp`).
- Error Assertions: verifies expected failures and error strings (`assertFail`, `assertNoFail`, `assertError`, `clearError`).
- Specialized Assertions: scalars, strings, substrings, floats with epsilon tolerances (`eqInt`, `neInt`, `eqStr`, `neStr`, `containsStr`, `emptyStr`, `notEmptyStr`, `eqBool`, `eqDouble`, `ok`, `notOk`, `skip`, `fail`).
- Parameterized Tests: table-driven cases (`caseParam`).
- Hierarchical Subtests: nested test grouping (`testCase`, `subcase`, `endSubcase`).
- Fault Isolation: runs fragile or fault-prone commands in child process sandboxes (`isolate`, `isolateFail`).
- Standard Formats: human-readable console summaries and TAP (Test Anything Protocol) mode (`setTAP`, `report`, `finish`).

```o9
import "testing.o9";

main {
    Test t = new Test("math");

    t.testCase("arithmetic");
    t.eqInt("addition", 10 + 20, 30);
    t.neInt("inequality", 10, 20);

    t.testCase("floats");
    t.eqDouble("tolerance", 3.14159, 3.141592, 0.001);

    t.report();
    t.finish();
}
```

Constructors:

- `Test(string suite)`: Initializes the suite name and resets counters.

Methods:

- `setTAP(bool enabled) void`: Enables or disables Test Anything Protocol output.
- `testCase(string name) void`: Sets the current top-level test case label.
- `caseParam(string name, string param) void`: Sets a parameterized test case label (e.g. `name[param]`).
- `subcase(string name) void`: Enters a nested subcase.
- `endSubcase() void`: Exits the current subcase.
- `ok(string what, bool cond) bool`: Asserts that `cond` is true.
- `notOk(string what, bool cond) bool`: Asserts that `cond` is false.
- `eqInt(string what, int64 got, int64 want) bool`: Asserts integer equality.
- `neInt(string what, int64 got, int64 want) bool`: Asserts integer inequality.
- `eqStr(string what, string got, string want) bool`: Asserts string equality.
- `neStr(string what, string got, string want) bool`: Asserts string inequality.
- `eqBool(string what, bool got, bool want) bool`: Asserts boolean equality.
- `eqDouble(string what, double got, double want, double epsilon) bool`: Asserts floating point equality within `epsilon`.
- `containsStr(string what, string haystack, string needle) bool`: Asserts that `haystack` contains `needle`.
- `emptyStr(string what, string s) bool`: Asserts that `s` is empty.
- `notEmptyStr(string what, string s) bool`: Asserts that `s` is not empty.
- `fail(string what, string msg) bool`: Records an explicit test failure.
- `skip(string what, string reason) void`: Records a skipped test check.
- `assertFail(string what) bool`: Asserts that the preceding call failed.
- `assertNoFail(string what) bool`: Asserts that the preceding call succeeded without error.
- `assertError(string what, string wantErr) bool`: Asserts that the preceding call produced `wantErr`.
- `clearError() void`: Clears the thread call error state.
- `tmpDir() string`: Creates and returns a unique temporary directory under `$TMP`.
- `tmpPath(string stem) string`: Returns a path under `tmpDir()`.
- `cleanTmp() void`: Removes temporary test directory and its files.
- `isolate(string what, string cmd) bool`: Executes `cmd` in a child process sandbox; succeeds if `cmd` exits cleanly.
- `isolateFail(string what, string cmd) bool`: Executes `cmd` in a child process sandbox; succeeds if `cmd` crashes or exits with an error.
- `passed() int64`: Returns count of passing assertions.
- `failed() int64`: Returns count of failing assertions.
- `skipped() int64`: Returns count of skipped checks.
- `count() int64`: Returns total assertions evaluated.
- `report() bool`: Prints test summary (or TAP header/plan). Returns `true` if all passed, `false` otherwise.
- `finish() void`: Exits the process with status `"failed"` if any check failed, or exits cleanly if all passed.
