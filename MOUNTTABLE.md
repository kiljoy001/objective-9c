# MountTable - namespace control from Tabula data

`MountTable` is the trusted local interpreter for `schema=mounts`
Tabulae.  The Tabula is inert data; nothing happens when it is read.
Only local code that constructs a `MountTable`, sets policy, and calls
`apply()` mutates the namespace.

```o9
Tabula spec = new Tabula("mounts", "kind,source,target,flags,mode,aname");
spec.write("root", "kind", "dir");
spec.write("root", "target", ".");
spec.write("tmp", "kind", "bind");
spec.write("tmp", "source", "/tmp");
spec.write("tmp", "target", "tmp");
spec.write("tmp", "flags", "repl,create");

MountTable mt = new MountTable(spec);
mt.allowRoot("/tmp/appns");
mt.validate();
mt.apply();
```

The first implementation supports local namespace assembly:

- `kind=dir` creates a directory under the allowed root.
- `kind=bind` calls Plan 9 `bind(source, root/target, flags)`.
- `kind=mountsrv` opens a local `/srv/name` file and calls
  `mount(fd, -1, root/target, flags, aname)`.

Targets are always relative to the allowed root.  Absolute targets,
`..`, empty paths, and control bytes are rejected.  Bind sources must be
absolute paths or `#` device paths.  `mountsrv` sources must live under
`/srv/`.  Remote `dial()` mounts are intentionally not part of the first
cut; they need explicit network policy.

This complements the existing app facade:

- `exports/` publishes data outward as virtual files.
- `MountTable` arranges the current process namespace inward.
- Both use `Tabula` as the data format.
