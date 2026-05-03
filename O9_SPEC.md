# o9 Language Specification (v0.2)

o9 is a Go-inspired, 9P-native object-oriented language designed for the Plan 9 ecosystem. It treats every object as a **9P Fileserver** and every method call as a **9P Transaction**, optimized via an **Asm Cache**.

## 1. Identity & Security
Identity in o9 is strictly grounded in the Plan 9 philosophy. **Factotum is the sole provider of identity truth.**

- **Object Ownership**: Every object instance is owned by a Plan 9 `uid`.
- **Authentication**: Object instantiation (`new`) and remote access are governed by the standard 9P authentication handshake mediated by `factotum`.
- **Encapsulation via Permissions**: Data hiding is enforced by standard Plan 9 mode bits (u/g/o).
    - `u`: Private state (0600).
    - `g`: Group-shared state (0660).
    - `o`: Public interface (0666).

## 2. Syntax Overview
The syntax is heavily inspired by Go but adds the `class` keyword to define 9P services.

```go
class Counter {
    val int64;          // Exported as /srv/Counter/<fid>/val
    
    // Methods use Go-style receivers
    func (c *Counter) inc(n int64) void {
        c.val = c.val + n;
    }
}

func main() {
    c := new Counter(); // 9P Tattach via Factotum auth
    c.inc(5);           // Dispatched via CSP or 9P Write
}
```

## 3. The 9P Mapping
| o9 Concept | 9P Reality |
| :--- | :--- |
| `class Name` | A background fileserver process registered at `/srv/Name`. |
| `new Name()` | `Tattach` with Factotum-provided auth ticket. |
| `obj.prop` | `Twalk` + `Tread`/`Twrite` to a member file. |
| `obj.method()`| `Twrite` to a synthetic control file. |
| `delete obj` | `Tclunk` (triggers ARC cleanup). |

## 4. Performance Tiers
o9 implements a tiered execution model based on object locality:
1. **Tier 1 (Asm Cache)**: Direct shared-memory access for properties (<1ns).
2. **Tier 2 (CSP Channel)**: `libthread` message passing for local methods (~50ns).
3. **Tier 3 (Standard 9P)**: Protocol fallback for remote/shell access (~2500ns).

## 5. Memory Management
o9 uses **ARC (Automatic Reference Counting)** tracked via an **Atomic Hashtable Ledger** inside each object.
- **Transparency**: Every object exports a `/ledger` file showing active reference holders.
- **Lifecycle**: Objects are automatically clunked when the ledger count hits zero.
