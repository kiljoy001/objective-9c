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
main {
    print("hello ", 42, "\n");      // auto-format: %s for strings,
}                                    // numbers as %lld; % is literal
```

## 2. Classes — every object is a CSP actor

```
class Counter {
    int64 val;                       // field
    method Counter(int64 n) { val = n; }        // constructor
    method int64 get() { return val; }
    method void add(int64 n) { val = val + n; }
    method int64 twice() { return get() * 2; }  // bare self-call
}

main {
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

Construction chains explicitly with `super(args)` — when a class and its
parent both have constructors, call the parent's first so every level
initializes its own fields (e2e_hard_super.o9):

```
class Animal { int64 species;
    method Animal(int64 s) { species = s; } }
class Mammal { Animal; int64 legs;
    method Mammal(int64 s, int64 l) { super(s); legs = l; } }  // super -> Animal(s)
class Cat { Mammal; int64 lives;
    method Cat(int64 s, int64 l, int64 v) { super(s, l); lives = v; } }
// new Cat(7,4,9): Cat -> super -> Mammal -> super -> Animal; all fields set
```

o9-honest: no hidden super calls, you write the chain. If the parent has
no constructor, `new Child(...)` reaches the nearest ancestor constructor
automatically (no `super` needed).

A class cannot `new` **itself** inside its own constructor — the object
is half-built (same reason Swift's two-phase init forbids it; C++/Java
just recurse forever). Constructing a *different* class into a field
(composition) is fine; build more of your own kind in a method, not the
constructor.

### public / private — the network boundary

A member is `public` by default. `private` makes it class-scoped
(C#-style) — callable only from the declaring class's own methods, and
**not reachable through the app's fileserver** (see §6). So the access
modifier is also the network API boundary: public methods are the
service; private ones are internal.

```
class Counter {
    private int64 val;                 // not directly readable by peers
    method Counter(int64 n) { val = n; }
    private method void bump(int64 d) { val = val + d; }
    method void add(int64 d) { bump(d); }   // public -> private, same class: ok
    method int64 get() { return val; }
}
```

Calling `bump` (or reading `val`) from outside `Counter` is a compile
error. You publish a method by *not* marking it private — there is no
separate interface to author (e2e_private.o9).

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

## 4. Errors — values, not exceptions

o9 has no exceptions and no stack unwinding. Errors are values, checked
where they happen (Go's model), with two conveniences (e2e_error.o9):

```
class Bank {
    int64 balance;
    method Bank(int64 b) { balance = b; }
    method int64 withdraw(int64 n) {
        if(n > balance) { fail("insufficient funds"); }   // set error, return
        balance = balance - n;
        return balance;
    }
    method int64 spend(int64 n) {
        defer bump();                  // runs at method exit, on EVERY path
        int64 left = try withdraw(n);  // if withdraw failed, propagate out of spend
        return left;
    }
    method void bump() { /* ... */ }
}
```

- **`fail("msg")`** — sets the method's error and returns early. Success
  is an ordinary `return`.
- **`try expr`** — if the call failed, the *enclosing* method returns
  that same error immediately (like Rust's `?`); otherwise `try` yields
  the value. No boilerplate `if err != nil { return err }`.
- **`defer expr`** — schedules cleanup to run when the method exits,
  whichever way it exits (normal return, `fail`, or a `try` that
  propagated). LIFO. This is what `finally` is good for, without the
  exception machinery.

Across the fileserver (§6), a failed call surfaces as `error: <msg>` in
the `data` file — so a shell or remote caller checks the same way: read
the result, look for `error:`. Errors are values all the way out.

## 5. Builtins

`len(s)` `cmp(a,b)` `cat(a,b)` — strings;
`readfile(path)` `writefile(path, s)` `readline()` — files/stdin;
`serve()` — block (yielding) so an app keeps serving its fileserver.

Crypto (monocypher; every key/sig/digest/blob is a lowercase hex
string, so values travel in files, ctl lines and libtab cells
unchanged):

- `keygen()` — 32 random bytes as 64 hex; the seed IS the secret.
- `pubkey(sec)` `sign(sec, msg)` `verify(pub, msg, sig)` — Ed25519.
  `verify` returns 1/0 (valid/invalid).
- `hash(msg)` — BLAKE2b-256; `mac(key, msg)` — keyed BLAKE2b-256.
- `encrypt(key, msg)` — XChaCha20-Poly1305; a fresh random nonce is
  generated inside and carried in the blob, so there is no nonce to
  get wrong. `decrypt(key, blob)` returns the plaintext, or nil if
  the key is wrong or the blob was tampered with.
- `xpubkey(sec)` `exchange(mysec, theirpub)` — X25519 agreement;
  both sides derive the same 64-hex key, ready to feed `encrypt`
  or `mac`. Don't reuse a signing seed for exchange.
- `passkey(password, salt)` — Argon2id (64 MiB, 3 passes; libtab's
  cost). Deterministic: the same password+salt always derives the
  same key, so an object can hold only sealed text and reopen it
  from a passphrase — nothing key-shaped is ever stored. Salt is
  per-secret context, 8 chars minimum.

Secret safety is a declaration — `secret` fields (e2e_secret.o9):

```
class Account {
    secret string apitoken;
    method Account(int64 n) { }
}
```

The compiler rewrites the field so plaintext storage never exists:
the member becomes `apitoken__blob` (the AEAD blob, still one
cat-able hex string) and the only generated accessors take the key —
`seal_apitoken(key, v)` and `open_apitoken(key)`. There is no plain
getter to call, so every visible form of the object (shm, /srv data,
persisted rows, send replies) carries ciphertext:

```
string k = passkey(readline(), "app.vault.v1");
Account a = new Account(1);
a.seal_apitoken(k, "tok-12345");
print(a.open_apitoken(k), "\n");     // plaintext, only here
```

Key custody stays with the program (`passkey`/`exchange`/`keygen`) —
the language guarantees at-rest safety, never key storage. v1:
string fields only. The same pattern written by hand is in
e2e_crypto.o9 (the Vault class).

A class method of the same name shadows any builtin.
(e2e_text.o9, e2e_crypto.o9)

## 6. Standard Library Objects

The stdlib is ordinary o9 where possible. Raw Plan 9 C is kept inside
`function` helpers, then exposed through objects:

```
import "bytes.o9";
import "file.o9";
import "path.o9";

main {
    Bytes b = new Bytes("ab");
    b.append(67);
    print(b.text(), " ", b.hex(), "\n");

    File f = new File("/tmp/o9-note");
    f.writeBytes(b);
    print(f.read(), "\n");

    Path p = new Path("/tmp//x/../o9-note");
    print(p.clean(), " ", p.base(), "\n");
}
```

`Bytes`, `Buffer`, `File`, and `Path` live in `stdlib/`. `Tabula` is built into
the runtime because it wraps libtab:

```
main {
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    Tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
}
```

See `stdlib/README.md` for the method list and `stdlib/e2e_*.o9` for runnable
examples.

## 7. Handles — lookup by identity

```
Counter c = new Counter(77);
Counter h = lookup("c");             // registry first, /srv fallback
print(h.get(), "\n");                // → 77
```

### Code as data — send

The ctl line the shell writes is a value the language can build and
fire (e2e_send.o9):

```
send(c, "method c add arg0=2");       // same line as: echo ... > ctl
print(send(c, "method c get"), "\n"); // reply as text → 42
```

Far handles get the raw line written to their ctl file and the data
file read back verbatim; in-process handles parse it into the same
selector+frame a compiled call site uses, with the reply formatted by
the method table's ret column. Construct calls at runtime from
strings — dispatch is text all the way down.

## 8. Your app from the shell — one fileserver, no client code

The whole program is **one** 9P fileserver posted at `/srv/o9.<app>`,
with a flat, uniform interface — the same shape for every app regardless
of its classes. Objects are **not** paths; they're named in the ctl
line (like factotum or plumber, not procfs). A method that ran needs
`serve()` in `main` to keep the app alive.

```rc
mount /srv/o9.Counter.Counter.app /mnt/o9
cat /mnt/o9/status                   # live objects: which classes/instances exist
cat /mnt/o9/methods                  # the public method surface (private omitted)
echo 'method Counter.c add arg0=5' > /mnt/o9/ctl   # target named in the line
echo 'method Counter.c get' > /mnt/o9/ctl
cat /mnt/o9/data                     # → the value, or "error: <msg>" on failure
```

A string arg with spaces must be **single-quoted** (the ctl line is
tokenized rc-style): `arg0='hello world'` is one value; unquoted
`hello world` is two tokens and fails the arity check — as it should.
Object-handle and Tabula args can't be marshaled over a text ctl line
and are rejected (pass objects in-process instead).

The five files: `ctl` (write a call), `data` (read the result), `status`
(the live object graph), `methods` (the public API — this *is* the
contract, generated from the actual public methods, so it never drifts),
and `exports/` (a dir where objects can publish `.tab` data files).

A public method **is** the network API — no REST/gRPC/schema layer to
author. The shell, a script, another o9 program, and a remote machine
all call it the same way: write text to `ctl`. (e2e_twoclass.o9 serves
two classes as peers from one post; ext_access proves an outside process
drives it over real 9P.)

Across machines it's the same, plus one import
(demo/TWO_MACHINE_DEMO.md): `rimport host /srv /n/x` then mount.

### Inspecting live state — debug only

Object state is in memory, not on disk (persistence is an explicit act,
not a side effect). By default it's private — the app exposes behavior,
not its guts. Set `O9DEBUG` before launching and the `state` file dumps
read-only method/object metadata snapshots plus every live object's fields:
public plain, private as `debug:<field>`, `secret` fields still sealed.
Off by default, encapsulation is preserved:

```rc
O9DEBUG=1 /tmp/myapp &
mount /srv/o9.Counter.Counter.app /mnt/o9
cat /mnt/o9/state                    # metadata + live state (debug only)
```

## 9. Composition

`object` and `link` declarations record intent; `link replace a -> b`
binds b over a at startup, `link union` union-binds (read
fallback). Every mount/bind is mirrored in the app's namespace recipe —
your program's assembly, as replayable text.

## Current sharp edges

- implicit narrowing is rejected; use an explicit Plan 9 C scalar type
  (`int64`, `uint64`, `int32`, `uint32`, `int16`, `uint16`, `int8`,
  `uint8`, `int`, `uint`, `short`, `long`, `char`, `uchar`, `ushort`,
  `ulong`, `vlong`, `uvlong`) and convert intentionally. `intptr` and
  `uintptr` are reserved for raw-C function interop and are rejected on
  normal object APIs.
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
