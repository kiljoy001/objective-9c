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

## 5. Handles — lookup by identity

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
