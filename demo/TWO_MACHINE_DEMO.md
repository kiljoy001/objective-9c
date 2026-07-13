# Two-Machine Demo — verified on the rentonsoftworks grid, July 2026

A method executed on one machine, dispatched from another, through
nothing but a mounted pipe. No client library, no stubs, no
serialization code — the filesystem is the protocol.

## 1. Build the server (dev9p)

```rc
cd /mnt/term/home/scott/Repo/objective-9c
./o9c/o9c < o9c/test/demo_grid.o9 > /tmp/demo.c
6c -FVw -I. -o /tmp/demo.6 /tmp/demo.c
6l -o $home/tmp/o9demo /tmp/demo.6 libo9.a /$objtype/lib/libndb.a
```

## 2. Run it on babyFileserver

rcpu back-mounts the client namespace at /mnt/term, so the binary is
served across the network to the machine that executes it:

```rc
rcpu -h babyFileServer.rentonsoftworks.coin -c /mnt/term/usr/scott/tmp/o9demo
```

## 3. Drive it from dev9p

Self-mounts are session-private; the machine-global seam is the
idempotent `/srv` post. Import it and mount:

```rc
rimport babyFileServer.rentonsoftworks.coin /srv /n/bfsrv
mount /n/bfsrv/o9.Counter.Counter.Counter /mnt/o9
ls /mnt/o9
        /mnt/o9/ctl  /mnt/o9/data  /mnt/o9/methods  /mnt/o9/status
sed 3q /mnt/o9/status
        state running
        typename Counter
        qname Counter
echo 'method Counter inc arg0=23' > /mnt/o9/ctl
echo 'method Counter get' > /mnt/o9/ctl
cat /mnt/o9/data
        23
```

`23` is the class server's auto-instance (starts at 0). The program's
own `new Counter(100)` created a second instance, addressable by name
through the same two files:

```rc
echo 'method c get' > /mnt/o9/ctl
cat /mnt/o9/data
        100
```

## What this exercised

- idempotent `/srv/o9.<app>.<class>.<inst>` posts (phase 1) as the
  machine boundary
- the counted `method <inst> <name> argN=` ctl protocol with `data`
  readback
- per-instance dispatch through the CSP actor on the remote machine
- `/srv` import as the composition mechanism: the consumer assembles
  its own view in its own namespace

## Lesson captured

A server's self-mount at `/mnt/o9/...` is visible only inside its own
process namespace. The `/srv` post is the canonical publication point;
assembled `/mnt/o9/App` trees are built by *consumers* from the
namespace recipe, each in their own namespace. See ../docs/ARCHITECTURE.md.
