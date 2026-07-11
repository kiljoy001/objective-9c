# MountTable - namespace control from syscall-shaped Tabula data

`MountTable` is a Tabula-backed namespace object. It owns a
`schema=mounts` Tabula, but users do not build that table by hand.
They call typed methods that write the exact parameter cells needed to
replay the namespace operation later.

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
- `call=mountsrv`, `fd=/srv/name`, `old=<target>`, `flag=<int>`,
  `aname=<string>`
- `call=dir`, `new=<target>`, `mode=<int>`

That keeps the tab useful to another program or another machine: it can
read ordinary data, inspect/query it, then replay it under its own
`allowRoot()` mapping.

The first implementation supports local namespace assembly through:

- `dir(new, mode)` creates a directory under the allowed root.
- `bind(old, new, flag)` calls Plan 9 `bind(old, root/new, flag)`.
- `mountsrv(fd, old, flag, aname)` opens a local `/srv/name` file and
  calls `mount(fd, -1, root/old, flag, aname)`.

Targets are always relative to the allowed root.  Absolute targets,
`..`, empty paths, and control bytes are rejected before they enter the
table and checked again during `validate()`. Bind sources must be
absolute paths or `#` device paths. `mountsrv` fd sources must live under
`/srv/`. Remote `dial()` mounts are intentionally not part of the first
cut; they need explicit network policy.

This complements the existing app facade:

- `exports/` publishes data outward as virtual files.
- `MountTable` arranges the current process namespace inward.
- Both use `Tabula` as the data format.
