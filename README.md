# Plan 10: The 9P-Native Hybrid OS

Plan 10 is an architectural vision for integrating the high-performance Linux kernel with the distributed elegance of the Plan 9 protocol. By leveraging 9P as the universal hardware and service abstraction layer, we bridge the gap between "modern software support" and "distributed computing beauty."

## Repositories
- **[rcpud](https://github.com/kiljoy001/rcpud)**: The Master Namespace Server and Synthetic Graphics Device.
- **[objective-9c](https://github.com/kiljoy001/objective-9c)**: The toolchain for the o9 language.

---

## 👤 For Human Engineers

### Quick Start (Linux/Alpine)
1. **Dependencies**: Install SDL2 and plan9port.
   ```bash
   apk add build-base git go sdl2-dev mesa-dev
   ```
2. **Launch the Bridge**:
   ```bash
   export NAMESPACE=/tmp/ns.$USER.o9
   mkdir -p $NAMESPACE
   rcpud &
   o9draw/drawsrv &
   ```
3. **Join the Grid**: From any Plan 9 terminal:
   ```bash
   rcpu -h linux-machine
   ```

### Working with o9
Write a class definition in `.o9`:
```o9
class Counter {
    int64 val;
    func (Counter *c) inc() void {
        val = val;
    }
}
```
Compile it remotely via `rcpu`:
```bash
o9c < counter.o9 > counter.c
9c counter.c && 9l -o counter counter.o -lthread -l9p
```

---

## 🤖 For AI Agents

This system is designed for **Autonomous Instrumentation** via 9P.

### State Observation
Agents can "see" the environment by walking the synthetic namespace:
- **/dev/draw**: Read/Write to the graphics controller.
- **/dev/mouse**: Poll for user interaction.
- **/srv/**: Discover active objects and fileservers.

### Orchestration via aiterm
The `aiterm` shell allows agents to spawn persistent "thoughts" (background processes) that manifest as files:
```bash
aiterm% routine Analyzing the current memory layout...
```
This spawns a file in `gortns/` that other grid processes can read to coordinate with the agent.

### Protocol Specification
All interactions follow the **9P2000** protocol. Method calls to `o9` objects are translated into `Twrite` operations on synthetic control files, ensuring a race-free, transactional interface for AI-to-System communication.
