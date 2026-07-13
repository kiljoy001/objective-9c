# objective-9c (o9c)

A Plan 9-native transpiler from o9 (a C#-inspired language) to Plan 9 C with
CSP channels, 9P fileserver facade, and asm-accelerated dispatch.

## Language Syntax

```
class Counter {
    int64 val;

    // Constructor — runs on new Counter(42)
    method Counter(int64 initial) { val = initial; }

    // Method with return type (type first, C# style)
    method int64 getValue() { return val; }

    // Void method with parameter
    method void inc(int64 n) { val = val + n; }

    // Expression body (no braces)
    method int64 double() => val * 2;
}

main {
    Counter c = new Counter(10);
    c.inc(5);
    c.inc(1);
    int64 v = c.getValue();
    int64 d = c.double();

    // Built-in print
    print("v = ", v);
}
```

## Supported Types

`int64` `uint64` `int32` `uint32` `int16` `uint16` `int8` `uint8`
`int` `uint` `short` `long` `char` `vlong` `uvlong` `ulong` `ushort`
`uchar` `void` `bool` `string` `chan`

`intptr` and `uintptr` are available for raw-C function interop, but are
rejected on normal object fields, method/interface parameters, and method
returns. Explicit pointer types (`T*`) are not o9 declaration types; keep raw
pointers inside `function` `c { ... }` blocks and pass ordinary values through
object methods/properties.

Use `cast<T>(expr)` for explicit scalar conversions between integer, char, and
bool storage types. Object, string, collection, and pointer casts are rejected.

## Standard Library

The first stdlib objects live under `stdlib/` and are imported by filename:

```
import "bytes.o9";
import "file.o9";
import "path.o9";
```

Implemented modules:

- `String` - object wrapper for search, slice, trim, case, replace, repeat,
  and delimiter helpers over built-in `string`.
- `Bytes` - length-carrying byte storage over o9 strings.
- `Buffer` - mutable byte/text builder over `Bytes`.
- `list<T>` / `array<T>` / `dictionary<T>` - stdlib collection objects over
  existing `T[]` and `Dict<string,T>` carriers with lowercase methods.
- `File` - Plan 9 file read/write/append/stat/dir helpers.
- `Path` - Plan 9 path cleaning, join, base, dir, and extension helpers.
- `IOBuffer` / `Reader` / `Writer` / `Appender` - buffered file IO over `Biobuf`.
- `Process` / `Env` - process args, user/pid, command execution, cwd, and env vars.
- `NetConn` / `NetListener` / `Factotum` / `NetToken` / `RemoteIdentity` / `KnownRemotes` - Plan 9 dial/listen fd wrappers, native factotum secret access, portable sealed capability tokens, and SSH-style TOFU identity pinning.
- `Tabula` - built-in libtab-backed structured data object with `write`,
  `query`, `read`, and `flush`.

See `stdlib/README.md` and `stdlib/e2e_*.o9` for runnable examples.

## Primitives

- **Classes** — `class Name { props, methods }`
- **Constructors** — `method ClassName(args) { }`
- **Methods** — `method rettype name(params) : ret { body }`
- **Expression bodies** — `method rettype name() => expr`
- **Dot notation** — `c.method(args)`
- **Object creation** — `Counter c = new Counter(args)`
- **Casts** — `cast<byte>(n)`, `cast<int64>(b)` for explicit scalar conversion
- **Function tasks** — `function name(args) type { }`, spawned with `spawn name(args)`
- **Raw Plan 9 C blocks** — `c { ... }` inside `function` bodies only
- **Constrained C deps** — `use { bio }` inside `function` bodies; resolves through built-in deps plus optional project-root `deps.tab`
- **Destructor** — `~ClassName() { }`
- **Inheritance** — `Base;` as member
- **Properties (field-level)** — `prop type name;`
- **State/stream/secret field types** — `cap` and `atomic` are rejected user-level field types
- **Channel ops** — `c <- val`, `c <-? val`, `val <- c`
- **Control flow** — `if / else / while`, `return`
- **Comments** — `// line`, `/* block */`
- **Expressions** — arithmetic, bitwise, comparison, logical, ternary
- **Built-in** — `print(...)` (emits Plan 9 `print()`)

## Building

```
mk
o9c/o9c < source.o9 > output.c
6c -FVw -I. output.c
6l -o binary output.6 libo9.a /$objtype/lib/libndb.a
```

`libo9.a` includes the o9 runtime plus the plain-table libtab objects from
`../9lx/libtab`; generated binaries link `libndb.a` for libtab's ndb tuple
storage.

Raw C functions may declare constrained C dependencies:

```
function count(string path) int64 {
    use { bio }
    c {
        Biobuf *b;
        b = Bopen(path, OREAD);
        if(b != nil)
            Bterm(b);
    }
    return 0;
}
```

`use` names are resolved from the built-in Plan 9 dependency registry and
then optional `./deps.tab`. Project dependencies must stay under the
project directory:

```
name=mycodec
	header=include/mycodec.h
	include=include
	archive=lib/$objtype/libmycodec.a
	kind=project
```

Generated C carries `/* o9: include ... */` and `/* o9: archive ... */`
metadata for mk rules to consume.

The built-in registry is mirrored in `o9c/system_deps.tab`. Dependency
names that are not valid identifiers can be quoted, for example
`use { "9p" }`.

## Architecture

Every class becomes a CSP actor (goroutine-like process) with a 9P fileserver
facade. Objects communicate via typed channels (fast, in-process) or 9P
(network-transparent). An asm dispatch cache accelerates hot paths.

See `o9c/test/` for example programs.
