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

func main() {
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
`int` `char` `vlong` `uvlong` `ulong` `ushort` `uchar` `void`
`bool` `string` `chan`

## Primitives

- **Classes** — `class Name { props, methods }`
- **Constructors** — `method ClassName(args) { }`
- **Methods** — `method rettype name(params) : ret { body }`
- **Expression bodies** — `method rettype name() => expr`
- **Dot notation** — `c.method(args)`
- **Object creation** — `Counter c = new Counter(args)`
- **Old-style C methods** — `func (T *self) name(params) ret { }`
- **Destructor** — `~ClassName() { }`
- **Inheritance** — `Base;` as member
- **Properties (field-level)** — `prop type name;`
- **State/atomic/stream/secret/cap field types**
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

## Architecture

Every class becomes a CSP actor (goroutine-like process) with a 9P fileserver
facade. Objects communicate via typed channels (fast, in-process) or 9P
(network-transparent). An asm dispatch cache accelerates hot paths.

See `o9c/test/` for example programs.
