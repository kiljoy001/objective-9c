# Controller-displayed views

An application posts one `/srv/<app>` 9P service. It can register one actor
with `viewController(controller)` before `serve()`. For each 9P attach, the
facade calls the controller's `display(id, caller)` method. The controller
returns the `FileTree` it wants that viewer to see at `/view`, or `nil` to
deny access to `/view`. It can build a new tree, return a shared tree, and
choose its contents from the caller's identity and application state.

`id` identifies the attach only inside the application. It is never a path,
ctl response, or file entry. The controller may use it to keep live file
state. `caller` is an authenticated identity only when the app's 9P auth path
established one; otherwise it is `anonymous`. Anonymous attaches can still
receive distinct views because `id` differs for each attach.

## 9P protocol

Mount the application service in each client's namespace, then use ordinary
file operations:

```rc
mount /srv/myapp /mnt/app
ls /mnt/app/view
cat /mnt/app/view/report
echo 'view close' > /mnt/app/ctl
```

The existing app `ctl` handles `view close` for that attach. It revokes that
attach's view; subsequent operations on its open view fids fail. A new attach
asks the controller to display a view again. There is no view-specific clone
file, token directory, or separate service. The `FileTree` root is initially
empty; only entries the controller adds appear in `/view`.

The controller owns the trees it returns. Closing one attach does not close a
tree that the controller also displays to other attaches. The controller
closes trees when it no longer needs them.

## Controller and FileTree

```o9
interface ViewController {
    internal method FileTree display(string id, string caller);
    internal method string readText(string id, string path);
    internal method int64 writeText(string id, string path,
                           int64 offset, string text, bool truncate);
}
```

`FileTree` supports `dir(path)`, `text(path, value, writable)`,
`live(path, writable)`, `remove(path)`, `register(sourceId)`,
`apply(mountTable)`, and `close()`. Paths are relative to the tree root.
Only the actor that created a tree may change its shape. A directory uses a
hash table of names. Replacing a text value keeps that entry's 9P ID;
removing and recreating a name gives it a new ID.

Stored text comes from the tree. A live file calls `readText` on each read.
Only files declared writable accept 9P writes; `writeText` receives the byte
offset, text, and a truncate flag. The controller updates stored text or
live state and returns the number of bytes accepted, or a negative value on
failure. `FileTree` text is UTF-8. Applications can encode binary data as
hex text.

Clients can walk, stat, list, open, and read normally. Direct 9P create,
remove, and rename operations cannot edit a view. A directory listing is
captured when its fid is opened. New walks see later changes to the tree.

## Composition inside one application

`FileTree.register(id)` gives another tree in the same application an
in-memory source ID. It does not post a service to `/srv`, start another
fileserver, or mount a component into the process namespace. The actors and
their trees remain part of the one app.
`MountTable.view(target, sourceId, mode)` adds a view mount row, and
`MountTable.unmount(target)` removes its mount stack. Mode `0` replaces,
`1` inserts before, and `2` inserts after the target directory's own
entries. `tree.apply(table)` resolves every source ID locally, checks the
mount graph for cycles, and commits the whole recipe at once. Missing IDs,
cycles, dial addresses, and `/srv` paths fail. A serialized table is inert
until the receiving process registers the source IDs and applies it.

Process namespace `MountTable.apply()` remains separate and rejects view
rows. A client mounts the one app service into its own namespace with normal
OS `mount` and `bind` commands.

See [view_app.o9](../o9c/test/view_app.o9) and
[run_view.rc](../o9c/test/run_view.rc) for a working 9front example.
