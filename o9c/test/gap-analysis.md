# o9 Language Gap Analysis (May 2026)

Structured inventory of what the transpiler, runtime, and test infrastructure are missing.
Use this as a checklist when picking the next feature to implement.

Priority scale: P0=blocker for real programs, P1=important missing feature, P2=polish/vision.

Last updated: May 8, 2026 — moved SHM, 9P dispatch, cache entries to Done.

---

## Language (Grammar & Parsing)

| Gap | Priority | Detail |
|-----|----------|--------|
| Self member access (`self->field`) | P2 | `->` is channel-send only. Accessing own fields must be by bare name (implicit self). |
| Channel type syntax | P2 | `chan int` parsed but no typed-channel codegen. Everything becomes `Channel*`. |
| Arrays / collections | P2 | No array type, no slice syntax, no map/dict. |
| Generics / parametric types | P2 | No template/parameterized class support. |
| Interfaces / abstract classes | P2 | No `interface` keyword. Inheritance exists but only struct embedding. |
| Enum types | P2 | No `enum` keyword. |
| Imports / modules / namespaces | P2 | No `import` or `using` — everything is one global scope. |
| `for` loop | P2 | Only `while` is implemented. |
| `else if` chain | P2 | Only `if/else` — chaining requires nested blocks. |
| Property accessors (`get`/`set`) | P3 | **Deferred indefinitely.** `get`/`set` are plain TIDENT, not keywords. The grammar rules were removed after multiple attempts failed due to conflicts with common method names like `set()`. If re-adding, match by string comparison in the grammar action, not separate lexer tokens. |

## Codegen (Transpiler Output)

| Gap | Priority | Detail |
|-----|----------|--------|
| `func main()` class-typed var init | P0 | Lines ~1190-1195 have `/* TODO */`: class-typed variables in top-level main() aren't fully wired through `gen_stmt`'s NLocalVar path with `in_class_context=0`. `Counter c = new Counter()` generates the right spawn code only when inside a class method body. The `threadmain` codegen's var init from `main_func->left` goes through `gen_stmt(nil, n)` which hits the plain-local path because `cname` is nil (no class context). |
| `func main()` emits wrong struct name | P1 | Top-level `Counter c;` emits `Counter c;` instead of `Counter_Client c;`. The `find_class` check in NLocalVar doesn't translate typename to generated struct name. |
| `c.inc(42)` in top-level may emit `&self->c` | P1 | `is_local()` table is empty at top level, so `NIdent` fallback with `in_class_context=0` should emit bare name... needs testing with a compile+link on 9front. |
| Pointer-to-property write | P1 | Generated `_Internal` for string `char*` does `free(0); s->field = strdup(data);` — free-of-nil is harmless, but no init to empty string means reads return "0" until first write. |
| Stream member codegen | P2 | `stream name;` parses but has no special codegen — no pipe/dynamic-file creation. |
| ArcLedger in Internal struct | P2 | Declared but never used — no `o9_ledger_update()` calls emitted by codegen. |
| `%format` in Bprint (optional) | P2 | Current `print()` double-escapes `%`. Switching to `Bprint(&bout, ...)` would eliminate this. |

## Runtime (o9_runtime.c, o9.h, o9_dispatch.s)

| Gap | Priority | Detail |
|-----|----------|--------|
| `o9_dispatch_call` implementation | P1 | Declared in header but no implementation. Ctrl cache dispatch stubbed. The asm has `o9_dispatch_call` entry but it's not linked into libo9.a. |
| ARC lifecycle wired to ledger | P2 | `ArcLedger` declared, `o9_ledger_update()` declared, no code calls it. No retain/release in generated code. |
| Destructor trigger from user code | P2 | Dispatch loop has `case "destroy": o9_cleanup...` but no user syntax to trigger it. No `delete` keyword. |
| Error propagation from dispatch | P2 | `O9Reply.err` never set by method implementations. `obj9_msgSend` returns nil on failure with no way to get the error string. |
| Selective cache entry fill | P2 | `o9_cache_fill` re-parses entire /cache on every miss instead of looking up just the missing entry. |
| Global `o9_call_args` still used for return-value calls | P2 | `c.getValue()` still packs via global buffer in comma-expression form. OK for single-threaded MVP, but blocks if multiple calls interleave. Fix: emit a local `vlong __tmp[N]` per NMsgSend call. |

## Infrastructure & Testing

| Gap | Priority | Detail |
|-----|----------|--------|
| `func main()` test program | P0 | No `.o9` file exercises the top-level entry point with class-typed variables. Need a full: `class Counter{} func main(){Counter c = new Counter(); c.inc(42);}` that compiles and runs. |
| End-to-end transpile pipeline test on 9front | P1 | The transpile works locally (verified with 9c on Linux). The `.o9 → o9c → 6c → 6l → run` chain on 9front hasn't been cleanly demonstrated. The **"silent runner"** (no output from transpiled binary) was found to be caused by Plan 9's `print()` writing to fd 2 (stderr) — combine stderr with `2>&1` or redirect stderr specifically. The generated C is correct and the runtime paths are proven by the C-language pipeline test (`full_pipeline_test.c`: 4/4 pass). |
| `o9c` output capture via drawterm | P2 | `o9c` uses `print()` which writes to fd 2 on 9front. Through drawterm PTY, both `>` and `2>` produce 0-byte files. Generated source must be synced via GitHub hget instead. |
| `print()` writes to stderr | P1 | Currently emits `print(...)` which goes to fd 2 on 9front. Should emit `fprint(1, ...)` for stdout output. |

## Done (Fixed in this or prior sessions)

**SHM mapping (May 8, 2026):**
- `o9_main_<Class>` allocates Internal via `segattach(0, nil, "o9/<class>", size)` instead of `emalloc9p`
- `/cache` file exported from generated server (0444), emits `seg:<class>` + `d:<hash>:<offset>` + `c:<hash>:<funcptr>`
- `o9_init_client` calls `segattach("o9/<class>")` after parsing /cache, maps SHM
- Post-process converts offset-based data_cache entries to absolute pointers

**9P out-of-process dispatch (May 8, 2026):**
- Method files: 0644 for return-value methods, 0222 for void methods — permissions encode semantics
- `fswrite_<Class>` stores `O9Reply` in `r->fid->aux` for return-value methods
- `fsread_<Class>` checks `r->fid->aux`, formats return value, frees it
- Cross-process dispatch works: `echo 5 > getValue` triggers dispatch, `cat getValue` reads reply
- Fid-based reply slots — concurrent callers don't clobber each other
- `o9_hash()` return type fixed (`void*` return on `obj9_msgSend`)

**In-process instantiation (May 2026):**
- `new Counter(10)` sets `client.shm_base = __c` (Internal pointer)
- Threadmain instance also has `client.shm_base = __c`

**C#-inspired syntax (May 2026):**
- Return values from methods: `r->ret = (void*)(expr); goto done;` with `done:` reply label
- Return type on `method`: `method int64 getValue()` (C# style, return type first)
- Method params on `method`: `method void inc(int64 n)` now works
- Expression-bodied methods: `method int64 double() => val * 2;` via TARROW token
- Constructor syntax: `method Counter(int64 n) { val = n; }` — detects method named after class
- Constructor args: `new Counter(42)` uses per-call stack-allocated `vlong __a[N]`, no global race

**Plan 9 C compatibility:**
- `o9_call_args[64]` global buffer instead of VLAs — avoids C99 requirement
- Comma expressions instead of GCC `({...})` statement expressions
- `0x%lux` format for unsigned hex (Plan 9's print convention)
- `o9_hash()` masks to `& 0xFFFFFFFFul` — portable 32-bit output across platforms
- `o9.h` hash function synced to djb2 (matches compiler)
- `done:` label only emitted when body has `return` — no warnings on void methods
- `USED()` for unused runtime params — `o9_cache_fill` compiles clean

**Primitive types as TTYPE keywords:**
`int64`, `uint64`, `int32`, `uint32`, `int16`, `uint16`, `int8`, `uint8`, `void`, `string`, `bool`, `int`, `char`, `vlong`, `uvlong`, `ulong`, `ushort`, `uchar` are all TTYPE tokens

**Zero grammar conflicts:**
- Removed dual ordering in `param` rule (TIDENT typename + typename TIDENT). Only `typename TIDENT` now.
- `func_decl` return type and receiver type changed from TIDENT to typename
- `%start program` directive prevents first-rule-as-start-symbol bug on Plan 9 yacc

**Test updates:**
- All 14 `.o9` test files pass
- `gen_cache_entries` fixed to reference `%s_Internal` (was `%s_State`)
- `mkfile` links `-lbio` for Bgetc/Bfdopen
