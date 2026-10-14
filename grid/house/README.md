# Mutation clearing house

`server.o9` is one Objective-9C service that owns the mutation work journal.
Each machine authenticates with its own AppUser RSA key in stock 9front
factotum. The verified key maps to a machine principal; the 9P clone number is
only a connection handle. Jobs, owners, attempt numbers, deadlines, and results
are stored in the controller's append-only journal.

The job manifest names a test path and a mutant file path. Workers must have
the corresponding source tree and mutation artifacts available in their own
namespace. `grid/o9muthousew.o9` authenticates, claims a job, runs the existing
`O9Mut` executor, renews the house lease while the gate runs, and submits the
executor's recorded result.

## Build and run

On 9front with Objective-9C installed:

```rc
o9build grid/house/server.o9 /tmp/house-server
o9build grid/house/client.o9 /tmp/house-client
o9build grid/o9muthousew.o9 /tmp/o9muthousew
/tmp/house-server house /path/on/disk/journal /path/machines.tsv /path/jobs.tsv
```

On the development host, `grid/house/build.sh server /tmp/house-server.c`
generates Plan 9 C. The script stages the stdlib because `o9c` confines
imports to the source directory. It also accepts `worker` to generate the
`o9muthousew` C source.

`machines.tsv` is trusted local administrator input, one tab-separated row per
machine: `principal`, RSA modulus `n`, RSA public exponent `ek`. The private
key stays in that machine's factotum with
`service=appuser app=o9mut hash=sha256`. The server refuses invalid or
duplicate public keys. `jobs.tsv` is also trusted local input, one row per
mutation: `task_id`, `test_path`, `mutant_path`. Keep the journal on persistent
storage. On restart the server replays it and checks that manifest entries
still describe the same jobs. Identifiers use ASCII letters, digits, `.`, `_`,
and `-`; test and mutant paths may also contain `/`.

On each worker, mount the house's 9P service and make the same source and
mutant paths visible. Load the matching RSA private key into stock factotum
and set the public modulus and exponent from that key. Use a trusted local
gate; the assignment provides data through `O9MUT_SOURCE` and `O9MUT_MUTANT`
environment variables, not a shell command. For example:

```rc
mount /srv/house /n/o9muthouse
o9muthousew houseworker /n/o9muthouse machine-a $n $ek \
    'rc /path/to/o9um_gate.rc' /tmp/o9mut-house 300000 0 1000 30000
```

The arguments after the gate are local queue directory, gate timeout in
milliseconds, maximum jobs (`0` runs continuously), idle poll interval, and
renewal interval. Keep the renewal interval below the 120 second lease. Each
assignment gets a separate local queue directory, retaining its gate log and
result for inspection. A failed lease renewal or rejected result stops the
worker, leaving that job available for a later lease attempt.

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

The supported outcomes are `killed`, `survived`, `timeout`, `build_error`,
`setup_error`, and `infra_fail`.
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
renews the lease, submits a result, and checks an unauthenticated session. It
also runs the automatic worker against a three second failing gate and checks
the local executor log, renewed lease, and submitted result.

For a two machine check, run:

```sh
python3 grid/house/test_house_multivm.py /path/to/9front.img
```

This makes disposable sparse disk copies and starts separate 9front VMs on
an isolated virtual Ethernet link. The server VM exports its mounted house
view over TCP; the worker VM mounts it with `srv`, signs into a new clone,
runs the gate, and submits its result. The check verifies the gate log in the
worker VM and the claim, renewal, and result in the server VM's journal.
