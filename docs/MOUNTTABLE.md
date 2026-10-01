# MountTable - namespace control from syscall-shaped tabula data

`MountTable` is a tabula-backed namespace object. It owns a
`schema=mounts` tabula, but users do not build that table by hand.
They call typed methods that write the exact parameter cells needed to
replay the namespace operation later.

Most application code should use the higher-level `Namespace` object.
`MountTable` is the inert data layer: use it directly when you need to
inspect, transport, or deliberately work at the syscall-parameter level.

The serialized `.tab` is inert data. Nothing happens when it is read,
exported, queried, or sent to another machine. Only local code that
opens it as a `MountTable`, sets policy with `allowRoot()`, and calls
`apply()` mutates the current namespace.

```o9
MountTable mt = new MountTable();
mt.dir("cache", 493);          // create root/cache, mode 0755
mt.bind("/tmp", "tmp", 0);     // bind(old, new, flag)

mt.allowRoot("/tmp/appns");
mt.validate();
mt.apply();
```

For transport:

```o9
writefile("/tmp/app.mounts.tab", mt.read());

MountTable copy = new MountTable("/tmp/app.mounts.tab");
copy.allowRoot("/tmp/otherns");
copy.apply();
```

The stored cells are syscall-shaped:

- `call=bind`, `old=<source>`, `new=<target>`, `flag=<int>`
- `call=mountnear` (or `call=mountsrv`), `fd=/srv/name` or `il!addr`, `old=<target>`, `flag=<int>`,
  `aname=<string>`
- `call=mountfar` (or `call=mountnet`), `fd=tcp!addr` or `net!addr`, `old=<target>`, `flag=<int>`,
  `aname=<string>`
- `call=dir`, `new=<target>`, `mode=<int>`

Mount flags use the Plan 9 values: `MREPL=0`, `MBEFORE=1`, `MAFTER=2`,
`MCREATE=4`. `MBEFORE|MAFTER` (`3`) is rejected because a mount cannot be
both before and after in a union directory.

That keeps the tab useful to another program or another machine: it can
read ordinary data, inspect/query it, then replay it under its own
`allowRoot()` mapping.

The implementation supports namespace assembly through distance tiers:

- `dir(new, mode)` creates a directory under the allowed root.
- `bind(old, new, flag)` calls Plan 9 `bind(old, root/new, flag)`.
- `mountnear(fd, old, flag, aname)` mounts a local `/srv/name` or `il!`
  service and calls `mount(fd, -1, root/old, flag, aname)` (`mountsrv` is an alias).
- `mountfar(addr, old, flag, aname)` dials a remote network address (`tcp!`)
  and mounts the 9P service into `root/old` (`mountnet` is an alias).

Targets are always relative to the allowed root.  Absolute targets,
`..`, empty paths, and control bytes are rejected before they enter the
table and checked again during `validate()`. Bind sources must be
absolute paths or `#` device paths. `mountnear` sources live under `/srv/`
or use `il!`. `mountfar` sources dial network transports (`tcp!`, `net!`).

This complements the existing app facade:

- `exports/` publishes data outward as virtual files.
- `MountTable` arranges the current process namespace inward.
- Both use `tabula` as the data format.
