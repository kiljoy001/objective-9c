# Property Corpora

`tools/o9prop.py` generates checked-in property cases.  Each case lowers the
same generated scalar expression program into:

- `case.o9`, compiled through `o9c`;
- `case.ref.c`, compiled directly as Plan 9 C.

The 9front harness runs both binaries and compares stdout.  Python generates
cases; Plan 9 C is the oracle.

Regenerate the scalar corpus from the host:

```sh
python3 tools/o9prop.py generate --cases 32 --seed 9009
```

Then test on 9front:

```rc
mk prop-test
```
