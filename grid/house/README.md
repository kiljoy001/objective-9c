# Mutation clearing house (first slice)

`server.o9` is one Objective-9C service that owns the mutation work journal.
Each machine authenticates with its own AppUser RSA key in stock 9front
factotum. The verified key maps to a machine principal; the 9P clone number is
only a connection handle. Jobs, owners, attempt numbers, deadlines, and results
are stored in the controller's append-only journal.

The current job manifest names a test path and a mutant ID. Workers must have
the corresponding source tree and mutation artifacts already available. The
automatic adapter from an assignment to `o9mutw` is still to be built; this
service currently handles discovery of work, leases, identity, and result
submission.

## Build and run

On 9front with Objective-9C installed:

```rc
o9build grid/house/server.o9 /tmp/house-server
o9build grid/house/client.o9 /tmp/house-client
/tmp/house-server house /path/on/disk/journal /path/machines.tsv /path/jobs.tsv
```

On the development host, `grid/house/build.sh server /tmp/house-server.c`
generates Plan 9 C. The script stages the stdlib because `o9c` confines
imports to the source directory.

`machines.tsv` is trusted local administrator input, one tab-separated row per
machine: `principal`, RSA modulus `n`, RSA public exponent `ek`. The private
key stays in that machine's factotum with
`service=appuser app=o9mut hash=sha256`. The server refuses invalid or
duplicate public keys. `jobs.tsv` is also trusted local input, one row per
mutation: `task_id`, `test_path`, `mutant_id`. Keep the journal on persistent
storage. On restart the server replays it and checks that manifest entries
still describe the same jobs. Identifiers use ASCII letters, digits, `.`, `_`,
and `-`; test paths may also contain `/`.

## Worker view

Mount `/srv/house`, read `clone`, and write `auth <principal>` to the clone's
`ctl`. The machine signs `challenge.tab` with `house-client` and writes the
generated response to `response.tab`. After `status.tab` says `verified`, the
private `view/` contains:

| File | Operation |
| --- | --- |
| `machine` | Read the verified machine principal. |
| `ready` | Write `1` followed by a newline to request a lease. |
| `assigned.tab` | Read the current assignment as a `mutation_assignment_v1` tabula. An empty table means no assignment. |
| `renew.tab` | Write a `mutation_renew_v1` tabula with `task_id` and `attempt` before the deadline. |
| `result.tab` | Write a `mutation_result_v1` tabula with `task_id`, `attempt`, and outcome. |

The supported outcomes are `killed`, `survived`, `timeout`, and `build_error`.
The lease is 120 seconds and can be renewed. A result or renewal must match
the verified machine, job, current attempt, and live lease. Expired work can
be assigned again with a higher attempt; a late result from the old worker is
rejected. A partition can still cause duplicate *execution* after expiry,
but it cannot make both results authoritative.

For example, a renewal record is:

```text
schema=mutation_renew_v1
	col=task_id
	col=attempt

task_id=m1
	attempt=1
```

A result record adds `col=outcome` and `outcome=killed` in the data row. The
server accepts one complete write of at most 256 bytes for each command file.
It tolerates the empty truncate write sent by ordinary `>` redirection.

## VM check

Run this against a disposable 9front disk image:

```sh
python3 grid/house/test_house_qemu.py /path/to/9front.img
```

The test runs two synthetic workers through the native controller, including
renewal, ownership checks, expiry, stale result rejection, restart, and repair
of a torn journal tail. It then runs the real server in the VM, signs with
stock factotum, mounts an AppUser session, parses `assigned.tab` with libtab,
renews the lease, submits a result, and checks the journal and an unauthenticated
second session.
