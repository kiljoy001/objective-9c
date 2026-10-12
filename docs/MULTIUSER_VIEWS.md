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
python3 o9c/test/test_multiuser_auth_qemu.py /path/to/9front.img p9sk1
python3 o9c/test/test_multiuser_auth_qemu.py /path/to/9front.img dp9ik
```

Each command boots a disposable copy of the disk image. The first builds the
current runtime with 9front C, checks owner and generation rules, boots the
service, and confirms an unauthenticated attach is rejected. The second runs
an isolated keyfs and authsrv, installs separate factotum keys for Alice and
Bob, and mounts the generated service as each user with the selected protocol.
It checks each user's view identity and confirms that cross-user access fails
in both directions with `permission denied`. It also checks that `cat clone`
allocates one session. The auth VM test does not contact an external auth
server.
