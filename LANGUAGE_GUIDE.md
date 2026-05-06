# o9 Language Guide

## Overview

**o9** is an experimental object-oriented programming language designed for Plan 9 and 9front environments. It combines the syntax familiarity of Go with the distributed, file-centric philosophy of Plan 9 (9P) and the concurrency model of Communicating Sequential Processes (CSP).

Every `class` in o9 compiles down into a standalone 9P fileserver and an internal CSP process network. The authoritative state of an object is protected by a central dispatch loop, and method calls are translated into asynchronous messages via `obj9_msgSend()`. 

## Current Implementation Status

**o9 is currently in an MVP (Minimum Viable Product) prototype stage.** 

- **What works:**
  - Defining classes (`class Name { ... }`).
  - Generating a 9P synthetic fileserver for the class.
  - Generating an internal CSP state-owner thread (`dispatch_chan`).
  - Defining properties (`prop Type name;` or `Type name;` or `chan name;`). They are automatically exported as read/write files under the 9P namespace.
  - Method generation and selector dispatch via Tier 2 local message passing.
  - Destructors (`~ClassName() { ... }`).
  - Channel operations (`->`, `->?`, `<-`).
  - **Expressions & Math:** Full support for `+`, `-`, `*`, `/`, `%`, and comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`).
  - **Control Flow:** Support for `if`, `else`, and `while` loop conditions.

- **What is incomplete:**
  - **Types:** The current primitive type mapping focuses heavily on 64-bit integers (`int64` -> `vlong`) and `chan` pointers. Type checking is non-existent.
  - **Remote 9P dispatch (Tier 3):** `obj9_msgSend()` handles local (Tier 2) dispatch, but remote network serialization across the 9P grid is stubbed out.

---

## Language Syntax

### 1. Class Declaration
A class defines both the 9P fileserver and the CSP object.

```o9
class Counter {
    int64 val;
    
    // Explicit visibility/concurrency modifiers are parsed (prop, atomic, state)
    prop int64 count;
    atomic int64 hot_count;

    // Destructor (called when the object is clunked or receives a destroy message)
    ~Counter() {
        val = 0;
    }
}
```

### 2. Methods, Math, and Control Flow
Methods define the operations on the object. In the underlying C code, these become asynchronous messages sent over the object's `dispatch_chan`. The o9 language supports standard binary operators and control flow blocks (`if`, `else`, `while`).

```o9
class FlowTest {
    int64 val;
    chan events;

    func (FlowTest *f) run() void {
        val = 0;
        while(val < 10) {
            if(val == 5) {
                events -> val;
            } else {
                val = val + 2;
            }
            
            if(val != 5) {
                val = val + 1;
            }
        }
    }
}
```

### 3. Channel Concurrency
o9 embraces CSP via channels, mapping directly to `libthread` primitives.

```o9
class Worker {
    chan events;

    func (Worker *w) trigger() void {
        events -> val;   // Blocking send
        events ->? val;  // Try-send (non-blocking)
        val = <- events; // Blocking receive
    }
}
```

### 4. Visibility and Semantic Modifiers

o9 introduces modifiers to describe the concurrency and visibility of fields. While fully parsed, the generation layers are still catching up to all of them.

- `state`: Private, authoritative state. Mutated only by the internal loop.
- `prop`: Readable/writable property. Accessible via 9P and caching.
- `atomic`: Shared memory field. Safe for hot local updates without messages.
- `stream`: An event stream (channel mapping to an event file).
- `secret`: Never exported to the shared memory cache.
- `cap`: A capability handle / authority token.

---

## How to Build and Use

### Prerequisites
- Plan 9 or 9front operating system (or `plan9port` on Unix/Linux).
- Standard Plan 9 C compiler toolchain (`9c`, `9l`, `mk`).

### Compiling the Compiler
```bash
cd o9c
mk clean
mk
```

### Generating C Code from o9
You can feed an `.o9` file directly into the compiler. It outputs standard Plan 9 C code.

```bash
./o9c < test/counter.o9 > counter_gen.c
```

The resulting `counter_gen.c` can be compiled using `9c` and will result in a binary that serves a 9P fileserver on execution.

```bash
9c counter_gen.c
9l -o counter_srv counter_gen.o
```

When you run `./counter_srv`, it posts itself to `/srv/Counter` and mounts its synthetic namespace, exposing `/ctl`, `/msg`, `/status`, and the defined properties.
