# objective-9c

objective-9c is a small 9front language that transpiles o9 source to Plan 9 C.

o9 is built for Plan 9-style programs: objects are CSP actors, public methods
can be served through a 9P facade, structured data moves as `.tab` text, and
raw Plan 9 C interop is isolated inside spawnable `function` blocks.

## Status

- Target: 9front.
- Output: generated C; no binary blob.
- Build: `mk` builds `o9c/o9c` and `libo9.a`.
- Tests: native 9front e2e tests under `o9c/test/` and `stdlib/e2e_*.o9`.
- Current focus: keeping the language small while growing useful stdlib
  objects and examples.

## Quick Build

From the repository root on 9front:

```rc
mk
o9c/o9c < source.o9 > output.c
6c -FVw -I. -o output.6 output.c
6l -o output output.6 libo9.a /$objtype/lib/libndb.a
```

`libo9.a` includes the o9 runtime plus libtab support from `../9lx/libtab`.

## A Small Program

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

## Mounted Method Call

An app that stays alive with `serve()` posts a 9P service under `/srv`. Use
clone sessions for result-bearing calls:

```rc
mount -c /srv/o9.Counter.Counter.app /mnt/o9
sid=`{cat /mnt/o9/clone}
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/data
echo close > /mnt/o9/$sid/ctl
```

## Docs

- [Quickstart](docs/QUICKSTART.md) - build and run a first app on 9front.
- [Language Guide](docs/LANGUAGE.md) - the canonical guide for writing o9.
- [Examples](docs/EXAMPLES.md) - small complete programs.
- [Standard Library](stdlib/README.md) - stdlib object reference.
- [Architecture](docs/ARCHITECTURE.md) and
  [Touchstone](docs/TOUCHSTONE.md) - design record and current direction.
