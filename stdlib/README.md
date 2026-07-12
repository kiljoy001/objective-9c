# o9 Standard Library

The stdlib is written as ordinary o9 modules where possible. Plan 9 system
calls stay behind `function` raw-C helpers, and the public surface is an object
API.

Import modules by filename:

```o9
import "bytes.o9";
import "file.o9";
import "path.o9";
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
