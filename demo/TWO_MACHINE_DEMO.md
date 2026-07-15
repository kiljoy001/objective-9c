# Two-Machine Tabula Demo — network-first o9

This demo is the current o9 networking model:

- objects stay local to the app that owns them;
- `.tab` data crosses the machine boundary through the app facade;
- consumers mount or address `exports/` and `imports/`;
- receiving data does not execute code.

The provider runs on `babyFileServer` and publishes `orders.tab`. The consumer
runs on `dev9p`, reads the remote export with `near Tabula`, appends a local
record, and pushes the full Tabula back into the provider's inert `imports/`
directory.

## 1. Build the provider and consumer on dev9p

```rc
cd /mnt/term/home/scott/Repo/objective-9c

./o9c/o9c < demo/demo_grid_provider.o9 > /tmp/o9tabprov.c
6c -FVw -I. -o /tmp/o9tabprov.6 /tmp/o9tabprov.c
6l -o $home/tmp/o9tabdemo /tmp/o9tabprov.6 libo9.a /$objtype/lib/libndb.a

./o9c/o9c < demo/demo_grid_consumer.o9 > /tmp/o9tabcons.c
6c -FVw -I. -o /tmp/o9tabcons.6 /tmp/o9tabcons.c
6l -o /tmp/o9tabcons /tmp/o9tabcons.6 libo9.a /$objtype/lib/libndb.a
```

## 2. Run the provider on babyFileServer

`rcpu` back-mounts the client namespace at `/mnt/term`, so the binary linked
on `dev9p` is visible to the machine that executes it:

```rc
cd /
rcpu -h babyFileServer.rentonsoftworks.coin -c 'sleep 20 | /mnt/term/usr/scott/tmp/o9tabdemo o9tabdemo' >/tmp/o9tabdemo_provider.log >[2=1] &
provider=$apid
```

The app posts its 9P facade at:

```text
/srv/o9.o9tabdemo.o9tabdemo.app
```

## 3. Import the provider's `/srv` and run the consumer

```rc
rimport babyFileServer.rentonsoftworks.coin /srv /n/bfsrv

srv=/n/bfsrv/o9.o9tabdemo.o9tabdemo.app
/tmp/o9tabcons o9tabconsumer $srv
```

Expected consumer output:

```text
first 1
order widget 8 paid
paid 1 widget 8
push 0
```

`near Tabula orders = new Tabula("orders", "item,qty,status") @ srv;` opens
`$srv/exports/orders.tab`. `orders.push()` writes the serialized local copy
back to `$srv/imports/orders.tab`.

## 4. Inspect the mounted facade

```rc
mkdir /n/o9tabdemo >[2]/dev/null
mount -c $srv /n/o9tabdemo

ls /n/o9tabdemo
cat /n/o9tabdemo/exports/orders.tab
cat /n/o9tabdemo/imports/orders.tab
unmount /n/o9tabdemo
kill $provider
```

The import should contain the original exported records plus the consumer's
new `pushed` record. The provider has not executed a remote method on behalf
of the consumer; it has only accepted inert text data into `imports/`.

## What this exercises

- `/srv` as the machine boundary and `rimport` as the namespace bridge.
- `listener Tabula` publishing local data under `exports/orders.tab`.
- `near Tabula` reading a remote export through 9P.
- `Tabula.push()` depositing data into `imports/orders.tab`.
- The core o9 rule: data can cross the network; object behavior stays local.

## Why this replaced the old Counter demo

The old two-machine demo drove a remote `Counter` by writing method commands
through `ctl`. That still describes the app facade mechanically, but it is not
the language's network-first programming model. The model now is publication
and deposit:

```text
producer app -> exports/name.tab
consumer app -> reads/query data locally
consumer app -> imports/name.tab
producer app -> decides locally what imported data means
```

That is the safer and more Plan 9-shaped contract: text data with semantics
embedded, transported by namespaces and 9P, never remote object execution.
