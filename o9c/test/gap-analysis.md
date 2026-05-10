# o9 Language Gap Analysis (May 9, 2026)

Structured inventory of what the transpiler, runtime, and test infrastructure are missing.
Use this as a checklist when picking the next feature to implement.

Priority scale: P0=blocker for real programs, P1=important missing feature, P2=polish/vision.

Last updated: May 9, 2026 — verified all P0/P1 items from gap analysis; many were already fixed.

---

## Language (Grammar & Parsing)

| Gap | Priority | Detail |
|-----|----------|--------|
| Property read syntax (`c.val` without parens) | P1 | `int64 x = c.val;` fails syntax error. `c.val()` works (treated as method call with no args). Need `expr '.' TIDENT` as a bare expression rule for property reads. |
| Self member access (`self->field`) | P2 | `->` is channel-send only. Accessing own fields must be by bare name (implicit self). |
| Channel type syntax | P2 | `chan int` parsed but no typed-channel codegen. Everything becomes `Channel*`. |
| Arrays / collections | P2 | No array type, no slice syntax, no map/dict. |
| Generics / parametric types | P2 | No template/parameterized class support. |
| Interfaces / abstract classes | P2 | No `interface` keyword. Inheritance exists but only struct embedding. |
| Enum types | P2 | No `enum` keyword. |
| Imports / modules / namespaces | P2 | No `import` or `using` — everything is one global scope. |
| Property accessors (`get`/`set`) | P3 | **Deferred indefinitely.** `get`/`set` are plain TIDENT, not keywords. |

## Codegen (Transpiler Output)

| Gap | Priority | Detail |
|-----|----------|--------|
| `func main()` test program exercising full lifecycle | P1 | No `.o9` test file exercises the complete entry point path with class vars + method calls + print. Need to write one and compile on 9front. |
| Global `o9_call_args` for return-value NMsgSend | P2 | `c.getValue()` packs via global buffer in comma-expression form. OK for single-threaded MVP, but blocks if multiple calls interleave. |

## Runtime (o9_runtime.c, o9.h, o9_dispatch.s)

| Gap | Priority | Detail |
|-----|----------|--------|
| `o9_dispatch_call` implementation | P1 | Declared in header but no implementation. Ctrl cache dispatch stubbed. The asm has `o9_dispatch_call` entry but it's not linked into libo9.a. |
| ARC lifecycle wired to ledger | P2 | `ArcLedger` declared, `o9_ledger_update()` declared, no code calls it. |
| Destructor trigger from user code | P2 | Dispatch loop has `case "destroy": o9_cleanup...` but no user syntax to trigger it. No `delete` keyword. |
| Error propagation from dispatch | P2 | `O9Reply.err` never set by method implementations. |
| Selective cache entry fill | P2 | `o9_cache_fill` re-parses entire /cache on every miss. |

## Infrastructure & Testing

| Gap | Priority | Detail |
|-----|----------|--------|
| End-to-end transpile pipeline test on 9front | P0 | The transpile works locally. The `.o9 → o9c → 6c → 6l → run` chain on real 9front hardware hasn't been cleanly demonstrated end-to-end. |

## Done (Fixed in this or prior sessions)

The following items from the original gap analysis are verified working:

**`func main()` class-typed var init (P0) — WORKS:**
- `Counter c = new Counter(42)` in `func main()` emits spawn code correctly: ealloc9p, chancreate, memset, proccreate, Counter_create_instance, constructor args dispatch
- `Counter c;` (bare class-typed var) emits `Counter_Client c;` with `o9_init_client`
- `c.inc(42)` method calls emit `obj9_msgSend` with args packed correctly
- `c.val = 42` property writes emit shm_base path: `((Counter_Internal*)__c->shm_base)->val = 42`

**`print()` writes to stdout (P1) — FIXED:**
Emits `fprint(1, ...)` on both platforms.

**`else if` chains (P2) — FIXED May 9, 2026:**
TELIF token approach with multi-char lexer pushback buffer.

**Rest from Done section unchanged.**
