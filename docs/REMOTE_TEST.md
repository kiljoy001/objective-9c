# Tabula network facade test

o9 no longer supports remote object construction or remote object method
dispatch. Objects stay local; mounted applications exchange `.tab` data
through the generated app facade:

```text
/mnt/app/
    exports/    # app-owned published Tabula files
    imports/    # inert inbound Tabula deposits
```

Run the source-level Tabula transport regression from the repository root:

```rc
mk tabula-transport-test
```

That test builds a provider app and a consumer app. The provider declares
`listener Tabula`, publishes `exports/orders.tab`, and serves its app facade.
The consumer declares `near Tabula` against the provider's `/srv` post, reads
and queries the remote export, mutates its local copy, calls `push()`, and the
provider receives `imports/orders.tab`.

The lower-level facade regression is still:

```rc
mk export-test
```

It builds a small app, mounts its generated 9P facade from a separate
namespace, then verifies:

- `exports/orders.tab` is readable and not client-writable.
- `imports/` accepts only `.tab` files.
- import writes are staged per fid and become visible on clunk.
- concurrent import writes commit whole files, not interleaved bytes.
- failed oversized writes do not replace the last committed import.
- another o9 program can open the exported `.tab` with `new Tabula(path)`.

For source-level locality syntax, use only Tabula:

```o9
near Tabula lan = new Tabula("orders", "item,qty,status") @ "il!host!9999";
far Tabula wan = new Tabula("orders", "item,qty,status") @ "tcp!host!9999";
listener Tabula server = new Tabula("orders", "item,qty,status") @ "il!*!9999";
```
