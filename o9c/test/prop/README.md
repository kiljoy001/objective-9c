# Property Corpora

`tools/o9prop.py` generates checked-in property cases.  Each case lowers the
same generated program into:

- `case.o9`, compiled through `o9c`;
- `case.ref.c`, compiled directly as Plan 9 C.

The 9front harness runs both binaries and compares stdout.  Python generates
cases; Plan 9 C is the oracle.

Regenerate the checked-in corpora from the host:

```sh
python3 tools/o9prop.py generate --cases 32 --seed 9009
python3 tools/o9prop.py generate --kind width --out o9c/test/prop/width --cases 32 --seed 9010
```

Then test on 9front:

```rc
mk prop-test
```
