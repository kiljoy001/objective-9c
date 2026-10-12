# Owned clone views

`serveMultiuser()` opts an o9c application into authenticated, owned clone
sessions. The generated server requires 9P authentication at attach and uses
the identity established by `auth9p`/`authattach`; the unauthenticated
`login user password` command is unavailable in this mode.

The service root exposes `clone` and `methods`. Reading `clone` allocates a
session for that authenticated user and calls the registered `ViewController`.
The controller's `display(id, caller)` returns the tree served at that
session's `view` directory:

```text
/clone          read: allocate session, return its number
/17/ctl         session commands
/17/data        session result
/17/status      session status
/17/view/       controller-selected view for this session
```

The runtime checks the authenticated attach identity on walks, opens, reads,
writes, and stats beneath the clone directory. Session numbers are locators,
not credentials. Every reuse advances a generation so previously walked fids
cannot access the new occupant. Closing a session revokes its view. A fresh
clone gets a fresh view;
the application owns durable per-user state and may present it again on a
different device.

The current owner key is the authenticated 9P user name within one auth realm.
Services that accept multiple independent auth realms need a principal key
that also identifies the realm before those realms can share one process.

`serve()` retains the existing per-attach `/view` and unauthenticated clone
behavior for current applications. `serveMultiuser()` requires a registered
`ViewController`; clone allocation returns `view unavailable` if it cannot
produce a tree. The generated server denies walks into root `ctl`, imports,
exports, and diagnostic files in multiuser mode. The root directory lists
only `clone` and `methods`; the client gets its session number from `clone`.

## VM check

With a 9front disk image and the host o9c compiler built from this branch:

```sh
python3 o9c/test/test_multiuser_qemu.py /path/to/9front.img
```

This builds the current runtime with 9front C in an isolated VM, checks owner
and generation rules, boots the service, and confirms an unauthenticated attach
is rejected. A two-account factotum test is still needed before enabling the
feature for a remote multiuser service. It must exercise real `Tauth` and
`Tattach` for each account, then confirm that neither account can walk or use
the other's clone and that an old fid stays revoked after reuse.
