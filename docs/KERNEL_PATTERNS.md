# Kernel Patterns For An o9c Rewrite

Status: analysis of 9front `/sys/src/9`, aimed at a kernel or driver written
in o9c. This is a different layer from the application stdlib: no libc, no
`spawn`-based actors, no 9P facade, and no hidden allocation.

## Scope And Caveat

o9c currently targets userland Plan 9 C with `libo9.a` and libc. A kernel
rewrite needs a **freestanding** target:

- no libc,
- an explicit allocator,
- a kernel scheduler (`newproc`, not `proccreate`),
- raw C or compiler-supported volatile MMIO,
- arch-specific MMU, trap, IRQ, and timer code.

The stdlib can still abstract the *interfaces* so a driver or subsystem does
not repeat the same C shapes. The architecture layer must stay explicit.

## Source Survey

9front has **68 `dev*.c` files** (34 in `port/`) and 22 port subsystems.
Frequent kernel patterns by file count in `port/`:

| Pattern | Files |
|---|---:|
| `waserror` / error unwinding | 63 |
| `qlock` | 46 |
| `sleep` | 34 |
| `wakeup` | 24 |
| `Chan` operations | 57 |
| `Block` queues | 24 |
| `Proc` lifecycle | 16 |

The `Dev` switch alone has **22 optional methods**:

```c
struct Dev {
    int dc;
    char *name;
    void (*reset)(void);
    void (*init)(void);
    void (*shutdown)(void);
    Chan* (*attach)(char*);
    Walkqid* (*walk)(Chan*, Chan*, char**, int);
    int (*stat)(Chan*, uchar*, int);
    Chan* (*open)(Chan*, int);
    Chan* (*create)(Chan*, char*, int, ulong);
    void (*close)(Chan*);
    long (*read)(Chan*, void*, long, vlong);
    Block* (*bread)(Chan*, long, ulong);
    long (*write)(Chan*, void*, long, vlong);
    long (*bwrite)(Chan*, Block*, ulong);
    void (*remove)(Chan*);
    int (*wstat)(Chan*, uchar*, int);
    void (*power)(int);
    int (*config)(int, char*, DevConf*);
};
```

## Patterns To Abstract

### 1. Device Switch

Every driver implements the same `Dev` shape, mostly with defaults:

- `attach`, `walk`, `stat`, `open`, `create`, `close`;
- byte or block I/O;
- `remove`, `wstat`, `power`, `config`;
- one-time `reset`/`init`/`shutdown`.

Proposed: `kernel/device.o9`

```o9
class Qid {
    method Qid(int64 path, int64 vers, int64 type);
}

class Dirtab {
    method Dirtab(string name, Qid qid, int64 length, int64 perm);
}

class Device {
    method Device(string name, int64 dc);
    method void add();                 // add to devtab
    method void reset() { }
    method void init() { }
    method void shutdown() { }

    method Chan attach(string spec) { return nil; }
    method Walkqid walk(Chan c, Chan clone, string[] names, int nname);
    method int stat(Chan c, uchar[] buf);
    method Chan open(Chan c, int mode);
    method Chan create(Chan c, string name, int mode, int64 perm);
    method void close(Chan c) { }
    method int64 read(Chan c, uchar[] buf, int64 offset);
    method int64 write(Chan c, uchar[] buf, int64 offset);
    method void remove(Chan c) { }
    method int wstat(Chan c, uchar[] buf);
    method int config(int on, string spec, DevConf d);
}
```

Start with `Device` defaults and two subclasses:

- `CharDevice`: `read`/`write` only.
- `BlockDevice`: `bread`/`bwrite` over `Block` pools.

`DirDevice` can add a `gen`-style directory iteration helper.

### 2. Chan And Fid Lifecycle

`Chan` is the kernel file object: qid, mode, offset, dev, iounit, mount state,
and per-device `aux`. `namec` walks names; `walk` clones; `open`/`create`
finalize.

Proposed: `kernel/chan.o9`

```o9
class Chan {
    method Qid qid();
    method int64 offset();
    method void seek(int64 off);
    method int mode();
    method void setMode(int mode);
    method int64 iounit();
    method void setIounit(int64 n);
    method void* aux();
    method void setAux(void* a);
    method Chan clone();
    method Chan walk(string name);
}

class Fid {
    method Chan chan();
    method int mode();
}
```

Keep `Chan` fields explicit. Do not hide the mount/union fields behind a
generic file object; kernel code needs them.

### 3. Locking And Rendezvous

The kernel's `Lock`, `QLock`, `RWLock`, and `Rendez` are small enough that the
repeated work is **scoping and ordering**, not the lock itself.

Patterns:

```c
qlock(&q);
...
qunlock(&q);

for(;;) {
    if(ready)
        break;
    sleep(&r, waitfn, arg);
}
wakeup(&r);
```

Proposed: `kernel/lock.o9`

```o9
class Lock {
    method void lock();
    method void unlock();
}

class QLock {
    method void qlock();
    method void qunlock();
}

class RWLock {
    method void rlock();
    method void runlock();
    method void wlock();
    method void wunlock();
}

class Rendez {
    method void sleep(WaitFn ready, void* arg);
    method void wakeup();
}
```

The useful abstraction is a scoped helper:

```o9
defer q.qunlock();
q.qlock();
```

Do not add an implicit lock to every method. Kernel lock ordering is explicit
and auditable.

### 4. Error Unwinding

`waserror`/`nexterror`/`error` are the kernel's non-local exit, using
`Proc.nerrlab`/`errlab[NERR]`. Drivers must restore locks and free buffers on
every path.

Proposed: `kernel/error.o9` or compiler-level `try`/`defer` support in
freestanding mode.

The mapping should be:

- `waserror()` -> establish a recovery point;
- `error("...")` -> `fail("...")`;
- `nexterror()` -> leave the recovery point;
- `defer`/scope cleanup -> unlock, kunmap, free, put block.

The compiler/runtime must support these without libc longjmp if the kernel
does not provide one. This is a prerequisite, not just a stdlib wrapper.

### 5. Memory, MMIO, DMA, Blocks

Repeated shapes:

- `mallocz`/`smalloc`/`free` for kernel objects;
- `Page`/`KMap`/`KUnmap` for page-cache and DMA;
- `Block`/`Bpool` queues for network and disk;
- `MMIO` reads/writes with barriers;
- DMA address translation and cache maintenance.

Proposed:

- `kernel/mem.o9`: `Page`, `KMap`, `KUnmap`, `Alloc`, `Free`.
- `kernel/mmio.o9`: typed `read32`/`write32`/`read64`/`write64` with barriers.
- `kernel/dma.o9`: `DmaBuffer`, `map`, `unmap`, `sync`.
- `kernel/block.o9`: `Block`, `Bpool`, `Blist`, `Queue`.

`Block` is especially valuable: `allocb`, `freeb`, `blen`, `BALLOC`,
`pullupblock`, and queue append/consume are repeated in every network and
storage driver.

### 6. Interrupts

Drivers register interrupt handlers, mask/unmask, and acknowledge the device.
The repeated work is handler registration and locking against process context.

Proposed: `kernel/irq.o9`

```o9
class Irq {
    method Irq(int vector, IntrHandler handler);
    method void enable();
    method void disable();
    method bool pending();
}

interface IntrHandler {
    method void interrupt(Ureg* ureg);
}
```

Keep `splhi`/`spllo` and per-arch interrupt controllers explicit. A generic
`Irq` class must not hide the arch vector table.

### 7. Proc And Scheduler

Kernel process patterns:

- `newproc`/`kproc` creation,
- `pexit`/`procwait`,
- `sleep`/`wakeup`,
- `postnote`/`killproc`,
- `Proc` state transitions.

Proposed: `kernel/proc.o9`

```o9
class Proc {
    method int64 pid();
    method string name();
    method void sleep(Rendez r, WaitFn ready, void* arg);
    method void wakeup();
    method void exit(string msg);
    method void note(string msg);
}
```

A kernel scheduler is not a generic actor runtime. Keep `Proc` explicit; do
not map `spawn` directly to `newproc` unless the scheduler semantics are
defined.

### 8. 9P Messages And Mounts

Kernel 9P is `Fcall` + `convM2S`/`convS2M` + `read9pmsg`, not the userland 9P
facade. Mounts add `Mount`/`Mnt`/`Mhead`, `namec`, `cmount`, and union walks.

Proposed:

- `kernel/ninep.o9`: `Fcall`, `convM2S`, `convS2M`, `read9pmsg`,
  `write9pmsg`.
- `kernel/mount.o9`: `Mount`, `Mnt`, `Mhead`, `cmount`, `unmount`.

These are low-level and should stay out of driver code unless the driver is a
9P server/client itself.

### 9. Hardware Drivers

Repeated init/shutdown/reset shapes:

- PCI: find device, map BAR, enable bus master, allocate IRQ.
- Virtio: feature negotiation, queue setup, descriptor rings, notify.
- UART: baud/format, FIFO, interrupt, console.
- SD/MMC: command/response, DMA, card init.
- USB: endpoint/transfer queues.

Proposed driver kit:

- `kernel/pci.o9`: `PciDev`, `PciBar`, `pcimatch`, `pcimap`.
- `kernel/virtio.o9`: `VirtioDev`, `VirtioQueue`, `VirtioDesc`.
- `kernel/uart.o9`: `Uart`, `UartConfig`.
- `kernel/sd.o9`: `SDHost`, `SDCard`.
- `kernel/usb.o9`: only if needed; USB is a large subsystem.

Start with PCI + Virtio + UART; those are the smallest useful driver set.

### 10. Syscall Dispatch

The kernel syscall table is `systab[]` plus `Sargs` and `dosyscall`. A
rewrite in o9c needs a way to declare numbers, names, and argument shapes
without hand-writing the table.

Proposed: `kernel/syscall.o9`

```o9
class Syscall {
    method Syscall(int number, string name, SyscallFn fn);
    method void add();
}

class Sargs {
    method int64 arg(int index);
    method void setResult(int64 value);
}
```

Keep the generated table auditable; do not hide the number-to-function map.

### 11. Console And Panic

`print`, `iprint`, `panic`, `consputc`, and `consread` are used everywhere.
A small `kernel/log.o9` with `printf`-like formatting, panic, and console
routing would remove repeated `sprint`/`snprint`/`consputc` shapes.

Do not use userland `Log`/`Service`/`Config` in the kernel.

### 12. Boot And Configuration

`main`, `reset`, `config`, `plan9.ini`, and arch-specific boot code have a
fixed order. A `kernel/boot.o9` can standardize:

- early console,
- memory/DTB/config parsing,
- arch init,
- device reset/init,
- scheduler start,
- root mount.

Keep the arch `main` explicit; the boot module should be a sequence helper,
not a hidden runtime.

## Proposed Kernel Stdlib Layout

```text
kernel/
    device.o9      Dev, Qid, Dirtab, Walkqid, CharDevice, BlockDevice
    chan.o9        Chan, Fid, walk/open/create/close
    lock.o9        Lock, QLock, RWLock, Rendez, sleep/wakeup
    error.o9       waserror/nexterror/error mapping, scoped cleanup
    mem.o9         Page, KMap, alloc/free
    mmio.o9        volatile register access and barriers
    dma.o9         DMA buffers and sync
    block.o9       Block, Bpool, Blist, Queue
    irq.o9         Irq registration and handlers
    proc.o9        Proc, sleep/wakeup, notes
    ninep.o9       Fcall, convM2S/S2M, read9pmsg
    mount.o9       Mount, Mnt, namec
    syscall.o9     syscall table and Sargs
    log.o9         print, panic, console
    boot.o9        boot/config sequence
    pci.o9         PCI discovery and BAR mapping
    virtio.o9      Virtio queues and devices
    uart.o9        UART setup and console
    sd.o9          SD/MMC host and card
```

## Priority

1. `device.o9` + `chan.o9` — every driver depends on them.
2. `lock.o9` + `error.o9` — every subsystem depends on them.
3. `mem.o9` + `mmio.o9` + `block.o9` — driver memory and I/O.
4. `irq.o9` + `pci.o9` + `virtio.o9` + `uart.o9` — first real drivers.
5. `proc.o9` + `syscall.o9` + `mount.o9` — kernel core.
6. `log.o9` + `boot.o9` — bring-up and diagnostics.
7. `sd.o9` / `usb.o9` — larger storage/device subsystems.

## Non-Goals

- Do not use userland `spawn`, `Task`, `Channel`, `FileTree`, `Service`, or
  `Config` in kernel code.
- Do not hide `Chan`, `Proc`, `Page`, `Block`, or `Dev` behind generic
  containers. Kernel code needs the real fields and lifetimes.
- Do not add implicit locks, implicit allocation, or implicit error recovery.
- Do not make arch code generic. MMU, trap, IRQ, timer, and console remain
  per-architecture.
- Do not start with USB or a full filesystem. PCI + Virtio + UART + a simple
  char device is the smallest useful path.
