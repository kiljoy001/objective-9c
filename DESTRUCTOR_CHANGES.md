# Destructor Support Added to o9c

## Date: 2026-05-04

## Changes Made

### 1. node.h
Added `NDestructor` to the node type enum (line 11).

### 2. o9c/o9.y
- Added `destructor_decl` to type declarations
- Added destructor support to `member` rule
- New grammar rule for destructor syntax:
  ```yacc
  destructor_decl:
      '~' TIDENT '(' ')' '{' stmt_list '}'
      {
          $$ = mk(NDestructor, $2->name, nil, $6, nil);
      }
      ;
  ```

### 3. Lexer (o9.l)
No changes needed - the catch-all rule already handles `~`.

## New Syntax Supported

```o9
class ClassName {
    // fields

    // methods

    ~ClassName() {
        // destructor body - cleanup code
    }
}
```

## Design: Destructors in o9

Destructors will be implemented as Plan 9 syscalls:
- Every object gets a `/srv/object.X/destroy` file
- Writing to `destroy` triggers:
  1. `unmount()` - undo inheritance binds
  2. Parent destructor call (if inherited)
  3. User-defined cleanup code
  4. `remove()` - remove fileserver
  5. `free()` - deallocate memory

### Philosophy
**Destructor cleanup = filesystem cleanup**
- `rm /srv/object.X` destroys the object
- Kernel tracks file handles for automatic refcounting
- Everything observable via `ls /srv`

## Status

✅ Grammar compiles successfully
✅ Parser recognizes destructor syntax
⚠️ Code generator needs implementation (currently will segfault on Linux)
🎯 Next: Develop on native Plan 9 via grid

## Testing on 9front Grid

1. Connect: `drawterm -G -h 192.168.2.202 -a 192.168.2.249 -u scott`
2. Export Linux filesystem via v9fs
3. Mount and rebuild natively on Plan 9
4. Implement destructor code generation

## Build Commands

```bash
cd /home/scott/Repo/objective-9c/o9c
PLAN9=/usr/local/plan9 mk clean
PLAN9=/usr/local/plan9 mk
```

---

**Note**: This implements one of the three OOP pillars needed for o9:
1. ✅ **Encapsulation** - via file permissions
2. ⚠️ **Inheritance** - via `bind()` syscalls (planned)
3. ✅ **Polymorphism** - via filesystem structure (duck typing)
