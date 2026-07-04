# Learning o9

Everything here is verified by the test suite (`o9c/test/e2e_*.o9` are
runnable, asserted examples — read them alongside this).

## Build & run (on 9front)

```rc
mk                                  # builds o9c + libo9.a
./o9c/o9c < prog.o9 > /tmp/p.c
6c -FVw -I. -o /tmp/p.6 /tmp/p.c
6l -o /tmp/p /tmp/p.6 libo9.a /$objtype/lib/libndb.a
/tmp/p
```

Errors come with line numbers: `o9c: error: line 3: cannot assign
string to int64`.

## 1. Hello

```
func main() {
    print("hello ", 42, "\n");      // auto-format: %s for strings,
}                                    // numbers as %lld; % is literal
```

## 2. Classes — every object is an actor + a fileserver

```
class Counter {
    int64 val;                       // field
    method Counter(int64 n) { val = n; }        // constructor
    method int64 get() { return val; }
    method void add(int64 n) { val = val + n; }
    method int64 twice() { return get() * 2; }  // bare self-call
}

func main() {
    Counter a = new Counter(20);
    a.add(a.twice());                // nested calls are safe
    print("a ", a.get(), "\n");      // → a 60
}
```

Each `new` spawns a CSP actor proc owning the state — one writer per
object, no locks. PascalCase members work (`method int64 GetValue()`,
`prop string Name;`, bare self-access). `delete a;` runs `~Counter()`
synchronously, then the actor exits (see e2e_delete.o9).

Inheritance: name the parent as a member (`Base;`). `interface` and
`abstract class` are compile-time contracts the checker enforces.

## 3. Generics — real classes per instantiation

```
class Box<T> {
    T value;
    method Box(T v) { value = v; }
    method T get() { return value; }
}
Box<int64> a = new Box<int64>(41);   // Box__int64: vlong field
Box<string> s = new Box<string>("hi"); // Box__string: char* field
```

## 4. Builtins

`len(s)` `cmp(a,b)` `cat(a,b)` — strings;
`readfile(path)` `writefile(path, s)` `readline()` — files/stdin.
A class method of the same name shadows the builtin. (e2e_text.o9)

## 5. Handles — lookup by identity

```
Counter c = new Counter(77);
Counter h = lookup("c");             // registry first, /srv fallback
print(h.get(), "\n");                // → 77
```

## 6. Your object from the shell — no client code

While a program runs, its classes are posted at
`/srv/o9.<app>.<class>.<inst>`:

```rc
mount /srv/o9.Counter.Counter.Counter /mnt/o9
cat /mnt/o9/status                   # identity, schema, instances
cat /mnt/o9/methods                  # dispatch table
echo 'method c add arg0=5' > /mnt/o9/ctl
echo 'method c get' > /mnt/o9/ctl
cat /mnt/o9/data                     # → the value
```

Across machines it's the same, plus one import
(demo/TWO_MACHINE_DEMO.md): `rimport host /srv /n/x` then mount.

## 7. Composition

`object` and `link` declarations record intent; `link ref a -> b`
binds b over a at startup, `link replica` union-binds (read
fallback). Every mount/bind is mirrored in
`/mnt/o9/<app>/state/<app>.namespace` — your program's assembly, as
replayable text.

## Current sharp edges

- `int64` → `int` narrowing is rejected; keep to `int64`/`string`/`bool`
- a *variable* named identically to a declared class parses as the type
- `replica` doesn't sync state yet; `while`, `if/else if`, `for` exist
  but there's no `switch`; strings returned by methods print with a
  6c format warning (harmless)

## Exercises

1. A `Stack` class (`push`/`pop`/`size`) over an `int64` field per slot
   of `List<int64>` — drive it from main, then from the shell via ctl.
2. `Logger` with `prop string Name;` writing lines via `writefile` —
   `delete` it and watch the destructor fire.
3. `Box<string>` holding `readline()` input, echoed back via a
   `lookup`-resolved handle.
4. Re-run demo/TWO_MACHINE_DEMO.md, but drive *your* Stack remotely.
