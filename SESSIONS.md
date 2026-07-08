# o9 sessions — clone/session facade design (July 2026)

Status: DESIGN (not built). Fixes the per-caller data race: today all
callers share one global o9app_lastdata mailbox, so concurrent clients
read each other's results. This doc is the agreed design.

## Why clone (not just fid->aux)

fid->aux is per-open state — perfect for ONE opened file (write a
command, read the reply from the SAME fid). But the flat API spans TWO
opens:

    echo 'method Counter.c get' > /mnt/o9/ctl   # fid A: write, close
    cat /mnt/o9/data                            # fid B: read

Those are separate opens, usually separate processes -> separate fids.
The server cannot infer that fid B's data-read belongs to fid A's earlier
ctl-write: a fid is not a user-visible, path-addressable session name.

So the interaction needs a shared, NAMED conversation object. That is
what clone provides — the /net/tcp/clone pattern. A custom 9P client
knows its fid; a shell user does not, so the session id lives in the
PATH.

## Layout

    /mnt/o9/
        clone        # read -> "17\n", allocates session 17
        methods      # GLOBAL: public API surface (describes the service)
        status       # GLOBAL: app/service state (running, classes) — the SERVICE
        exports/     # GLOBAL: published .tab data products
        17/          # a session (created by reading clone)
            ctl      # write-only: this session's commands
            data     # read-only: this session's result (NO race — owned by the session)
            status   # read-only: THIS conversation's success/error/pending

Only the CONVERSATION is cloned. methods/status/exports stay global —
they describe the service and its data products. ctl/data/status become
session-local because they carry per-client interaction.

## File roles (strict)

- ctl    — WRITE ONLY. Commands in. Nothing is read from ctl.
- data   — READ ONLY. The method's RESULT (return value) only. No error
           text mixed in (that was the old bug — errors were stuffed into
           the data buffer).
- status — READ ONLY. Success/error of the last call, or pending. Errors
           live HERE, not in data.

Two files named `status`, disambiguated by PATH (Plan 9 idiom — ctl/
status recur at different levels):
- root  /status      = the SERVICE (app running? classes?). Stable.
- session <id>/status = MY conversation (did my call succeed? error?).
  Per-client, changes each call.

## Usage (shell ergonomics preserved)

    sid=`{cat /mnt/o9/clone}
    echo 'method Counter.c get' > /mnt/o9/$sid/ctl
    cat /mnt/o9/$sid/status      # ok / error: ...
    cat /mnt/o9/$sid/data        # the result value

## Root ctl (optional, restricted)

A root write-only ctl MAY remain, but ONLY for app-wide / fire-and-forget
commands (create object, shutdown, reload, debug toggle) — never for
result-bearing calls (those have no session to route the reply to). Any
call that returns a value goes through a session.

## Implementation notes

- clone: a served file whose READ allocates a new session (id counter),
  createfiles the session dir + its ctl/data/status into the served tree
  (createfile into the stable root — the authsrv/ramfs-proven pattern,
  same as exports/), and returns the id string.
- Per-session state (last result, last status) lives on the session —
  keyed by the session dir's files' aux, NOT a global. Reads of
  <id>/data and <id>/status serve that session's aux.
- Session teardown: a session dir + its state should be reaped when the
  client is done (clunk/remove, or an idle timeout). removefile on the
  session dir.
- fid->aux is still the right per-open mechanism WITHIN a session's files;
  the session dir is the cross-file conversation identity fids alone
  can't give.

## Migration / compatibility

- The flat root ctl/data (current) races under concurrency. Options at
  build time: keep it as a documented single-client DEBUG convenience, or
  remove it and require clone+session. (Decide at build; the tutorial and
  tests currently use the flat form, so removing it is a blast radius.)

## Build order

1. This doc.
2. clone file: read allocates a session, creates <id>/{ctl,data,status}.
3. Route ctl writes + data/status reads to per-session aux (kill the
   global o9app_lastdata for result-bearing calls).
4. Session teardown (reap on clunk/idle).
5. Tests: two concurrent sessions must not see each other's results
   (the race regression); result in data, error in status.
