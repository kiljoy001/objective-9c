# Quickstart

This walks through building and running a first o9 app on 9front.

## Prerequisites

Run these commands from the repository root on 9front:

```rc
pwd
```

## Build The Toolchain

```rc
mk
mk install
```

That builds:

- `o9c/o9c` - the o9-to-C transpiler
- `libo9.a` - the runtime library linked with generated o9 programs
- `o9build` - the normal build wrapper for user programs
- `o9proj` - project scaffolding
- `o9plumb` - optional plumber setup for `.o9` build messages

## First Program

Create `/tmp/counter.o9`:

```o9
class Counter {
    int64 val;

    method Counter(int64 initial) {
        val = initial;
    }

    method void inc(int64 n) {
        val = val + n;
    }

    method int64 get() {
        return val;
    }
}

main {
    Counter c = new Counter(10);
    c.inc(5);
    print(c.get(), "\n");
}
```

Build and run:

```rc
o9build /tmp/counter.o9
/tmp/counter
```

Expected output:

```text
15
```

`o9build` keeps the generated Plan 9 C next to the binary, at
`/tmp/counter.c` for this example. Read that file to review the transpiler's
output. From the repository root, you can also run the transpiler alone:

```rc
./o9c/o9c < /tmp/counter.o9 > /tmp/counter.c
```

## Serve It Through 9P

Create `/tmp/countersrv.o9`:

```o9
class Counter {
    int64 val;

    method Counter(int64 initial) {
        val = initial;
    }

    method void inc(int64 n) {
        val = val + n;
    }

    method int64 get() {
        return val;
    }
}

main {
    Counter c = new Counter(40);
    serve();
}
```

Build and start it:

```rc
o9build /tmp/countersrv.o9
/tmp/countersrv &
srvpid=$apid
```

Without a command-line app name, this program posts its last class name,
`Counter`, under `/srv`. Mount it and call methods through a clone session:

```rc
mkdir /mnt/o9 >[2]/dev/null
mount -c /srv/Counter /mnt/o9

sid=`{cat /mnt/o9/clone}
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/data

echo 'method Counter.c inc arg0=2' > /mnt/o9/$sid/ctl
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/data

echo close > /mnt/o9/$sid/ctl
```

Expected output:

```text
40
42
```

Clean up:

```rc
unmount /mnt/o9
kill $srvpid
rm -f /srv/Counter
```

## Run The Tests

Run the full native 9front verification suite with:

```rc
mk verify
```

For a faster first check, run:

```rc
mk
mk ast-test
mk run-test
```

The positive factotum login branch of `auth-test` needs a configured account
for the current 9front user and `O9AUTH_TEST=required` with
`O9_TEST_PASSWORD` set for that account. The default `mk verify` run
exercises the other auth checks and reports that positive branch as skipped.

## Next Reading

Run `o9plumb` once to make plumbing an `.o9` file start an `o9build` build.

- [Language Guide](LANGUAGE.md)
- [Examples](EXAMPLES.md)
- [Standard Library](../stdlib/README.md)
