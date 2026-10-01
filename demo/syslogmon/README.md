# syslogmon — 9front Syslog Monitor (Objective-9C)

`syslogmon` is an Objective-9C application that monitors system logs across all machines in the 9front grid (`dev9p`, `babyFileServer`, `Authomatic`, etc.).

Because it is built with **o9c**, the compiled binary is **automatically a 9P fileserver**. Calling `serve()` inside the application posts the actor and its published tabulae directly under `/srv`.

---

## Architecture & Features

* **Dual Tabulae Model:**
  * `exports/syslogs.tab`: Real-time structured log entries with schema `(id, machine, logname, timestamp, message)`.
  * `exports/machines.tab`: Machine inventory with schema `(id, status, lastseen, logcount)`.
* **Automatic 9P Fileserver:**
  * Runs as a daemon and registers under `/srv/syslogmon`.
  * Exposes standard o9 facade: `clone`, `ctl`, `data`, `methods`, `status`, `exports/`, and `imports/`.
* **Grid Ingestion:**
  * Can scan local and mounted remote log paths (`/sys/log`, `/n/babyFileServer.../sys/log`, `/n/Authomatic.../sys/log`).
  * Accepts remote log deposits via `imports/syslogs.tab` (`tabula.push()`).
  * Supports programmatic log ingestion via clone sessions.

---

## Building on 9front

From `dev9p` (or via `drawterm`):

```rc
cd /mnt/term/home/scott/Repo/objective-9c/demo/syslogmon
mk
```

Or using `o9build` directly:

```rc
o9build syslogmon.o9 syslogmon
```

---

## Running the Fileserver

Start the monitor as a background service:

```rc
./syslogmon &
```

The application initializes the log tables, scans known 9front log paths, and posts its 9P service to:

```text
/srv/syslogmon
```

---

## Accessing the Fileserver Across the 9front Grid

### 1. Mount Locally on the Host

```rc
mkdir /n/syslogmon
mount -c /srv/syslogmon /n/syslogmon
```

### 2. Read the Tabula Exports

View the active machine inventory:
```rc
cat /n/syslogmon/exports/machines.tab
```

View all ingested syslogs:
```rc
cat /n/syslogmon/exports/syslogs.tab
```

### 3. Query the Actor via Clone Sessions

```rc
sid=`{cat /n/syslogmon/clone}
echo 'method SyslogMonitor.m status' > /n/syslogmon/$sid/ctl
cat /n/syslogmon/$sid/data
echo close > /n/syslogmon/$sid/ctl
```

To ingest a new log line manually:
```rc
sid=`{cat /n/syslogmon/clone}
echo 'method SyslogMonitor.m ingest babyFileServer auth 1726830000 ''successful login''' > /n/syslogmon/$sid/ctl
cat /n/syslogmon/$sid/data
echo close > /n/syslogmon/$sid/ctl
```

---

## Remote Access Across Grid Nodes (`babyFileServer`, `Authomatic`)

From any remote 9front machine on the grid, import the `/srv` directory of the machine running `syslogmon`:

```rc
rimport dev9p.rentonsoftworks.coin /srv /n/devsrv
mount -c /n/devsrv/o9.syslogmon.syslogmon.app /n/syslogmon
cat /n/syslogmon/exports/syslogs.tab
```

Or run the provided `push_log.rc` script to forward local logs automatically:

```rc
./push_log.rc /srv/syslogmon
```
