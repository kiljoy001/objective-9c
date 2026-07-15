# Examples

These are small complete o9 programs. Use the compile/link commands from
[QUICKSTART.md](QUICKSTART.md) to run them on 9front.

## Counter

```o9
class Counter {
    int64 val;

    method Counter(int64 initial) {
        val = initial;
    }

    method void inc(int64 n) {
        val = val + n;
    }

    method int64 get() {
        return val;
    }
}

main {
    Counter c = new Counter(10);
    c.inc(32);
    print(c.get(), "\n");
}
```

## File Tool

```o9
import "file.o9";

class Note {
    File file;

    method Note(string path) {
        file = new File(path);
    }

    method void reset(string text) {
        file.write(text);
    }

    method void add(string text) {
        file.append(text);
    }

    method string read() {
        return file.read();
    }
}

main {
    Note n = new Note("/tmp/o9-note");
    n.reset("alpha\n");
    n.add("beta\n");
    print(n.read());
}
```

## Tabula Data Publisher

This app publishes a read-only `.tab` file under its mounted `exports/`
directory.

```o9
main {
    Tabula t = new Tabula("orders", "item,qty,status");
    t.write("a", "item", "widget");
    t.write("a", "qty", "5");
    t.write("a", "status", "paid");

    t.write("b", "item", "gadget");
    t.write("b", "qty", "3");
    t.write("b", "status", "open");

    export("orders.tab", t);
    serve();
}
```

A client can mount the app and read the data as text:

```rc
# assuming the binary was started with app name "publisher"
mount -c /srv/o9.publisher.publisher.app /mnt/o9
cat /mnt/o9/exports/orders.tab
```

Another o9 program can import the mounted file:

```o9
main {
    Tabula t = new Tabula("/mnt/o9/exports/orders.tab");
    Tabula paid = t.query("status", "paid");
    print(paid.first(), " ", paid.get("item"), "\n");
}
```

Clients can also deposit inert `.tab` data into `imports/`; the receiving app
decides later what the data means:

```rc
cat local-orders.tab > /mnt/o9/imports/local-orders.tab
```

Binary payloads stay text by using a `0x` column with hex from `Bytes`:

```o9
import "bytes.o9";

main {
    Bytes b = new Bytes("payload");
    Tabula file = new Tabula("file", "name,kind,0x");
    file.write("p", "name", "payload.bin");
    file.write("p", "kind", "application/octet-stream");
    file.write("p", "0x", b.hex());
}
```

## Namespace Setup

```o9
import "namespace.o9";

main {
    Namespace ns = new Namespace();

    print("root ", ns.root("/tmp/o9_namespace_root"), "\n");
    print("dir ", ns.dir("cache", 493), "\n");
    print("bind ", ns.bindReplace("/tmp", "tmp"), "\n");
    print("valid ", ns.validate(), "\n");

    writefile("/tmp/o9_namespace_probe", "ok");
    print("apply ", ns.apply(), "\n");
    print(readfile("/tmp/o9_namespace_root/tmp/o9_namespace_probe"), "\n");

    ns.save("/tmp/o9_namespace_spec.tab");
    ns.close();
}
```

`Namespace` is the normal API. `MountTable` is the lower-level Tabula-backed
representation for storing or sending mount/bind parameters.

## Draw Window

`DrawWindow` can render deterministic PNG snapshots for tests, or show a live
rio/libdraw surface for manual visual checks.

```o9
import "stdlib/draw.o9";

main {
    DrawWindow w = new DrawWindow("o9 libdraw demo", 420, 260);
    w.background(0x203040);
    w.accent(0xe0c040);
    w.snapshotPng("/tmp/o9_draw_snapshot.png");
}
```

Manual demo sources live under `demo/`; keep future live visual demos there
instead of in `stdlib/`. From a rio session, the built-in window demo opens a
separate window:

```rc
mk draw-window-demo
```

There is also a live button demo. It opens a libdraw window, changes the
visible status text each time the button is clicked, and exits on `q`, Esc, or
Del:

```rc
mk draw-button-demo
```

The text input demo opens a focused single-line field. Click the field, type,
use backspace/delete, and close with Esc or Ctrl-Q:

```rc
mk draw-textinput-demo
```

The table demo opens a fixed-column table with selectable rows. Click rows or
use `j`/`k` after the table has focus:

```rc
mk draw-table-demo
```

The menu demo shows the Plan 9 button-menu path for draw apps. Button 3 opens
a menu with snarf, paste, clear, and quit actions backed by `/dev/snarf`:

```rc
mk draw-menu-demo
```

The scrollbar demo uses `DrawScrollText`, a reactive text viewport with
integrated scrollbars. Drag either bar, resize the viewport, or use
`j`/`k`/`h`/`l` to move the visible text:

```rc
mk draw-scrollbar-demo
```

For headless visual interaction, render a frame, send a synthetic click, and
render the next frame:

```o9
import "stdlib/draw.o9";

main {
    DrawVisualProbe p = new DrawVisualProbe("probe", 128, 72);
    p.snapshotPng("/tmp/probe-before.png");
    p.click(64, 42);
    p.nextEvent();
    print("event ", p.eventType(), " ", p.eventX(), " ", p.eventY(), "\n");
    p.snapshotPng("/tmp/probe-after.png");
    print("clicks ", p.count(), "\n");
}
```

The lower-level event bus can be used directly:

```o9
import "stdlib/draw.o9";

main {
    DrawEventLoop loop = new DrawEventLoop();
    DrawEvent e;

    loop.start();
    loop.mouse(10, 20, 1);
    loop.key(65);
    loop.resize(320, 200);

    e = <- loop.events;
    print(e.kind, " ", e.x, " ", e.y, "\n");
    e = <- loop.events;
    print(e.kind, " ", e.key, "\n");
    e = <- loop.events;
    print(e.kind, " ", e.width, " ", e.height, "\n");
}
```

The first reusable widget object is `DrawButton`, which handles hit testing and
typed mouse events. Normal UI code adds widgets to a `DrawWindow`; the window
routes input through the widget tree and repaints through a batched `DrawFrame`.
`DrawCanvas` remains the low-level drawing surface for custom work:

```o9
import "stdlib/draw.o9";

main {
    DrawWindow win = new DrawWindow("widgets", 320, 160);
    DrawButton b = new DrawButton("ok", 10, 20, 64, 24);
    DrawLabel label = new DrawLabel("status", 10, 54, 120, 20);
    DrawTextInput input = new DrawTextInput("", 10, 86, 160, 28);
    DrawScrollText scroll = new DrawScrollText("alpha\nbeta\ngamma", 150, 20, 150, 80);
    DrawEvent e;

    b.position(10, 20);
    b.size(64, 24);
    b.color(0x466080, 0xffffff);
    label.color(0x203040, 0xffffff);
    input.setPlaceholder("name");
    scroll.setWrap(false);
    scroll.setValue(40);

    e.kind = 1;
    e.x = 16;
    e.y = 24;
    e.buttons = 1;
    b.handleMouse(e.x, e.y, e.buttons);
    label.setText("clicked");

    print(b.text(), " ", b.count(), " ", b.pressed(), " ", label.text(), "\n");

    win.add(b);
    win.add(label);
    win.add(input);
    win.add(scroll);
    if(win.open()) {
        win.update();
        label.setText("changed through reactive dirty state");
        win.update();
        win.close();
    }
}
```

## Raw C Wrapper

Raw C lives inside `function` bodies. This example uses Plan 9 `Biobuf`
through a constrained `use { bio }` dependency.

```o9
function countbytes(string path) int64 {
    use { bio }

    int64 n;
    c {
        Biobuf *b;
        char *cpath;

        n = 0;
        cpath = o9_string_cstr(path);
        b = cpath != nil ? Bopen(cpath, OREAD) : nil;
        free(cpath);
        if(b == nil)
            n = -1;
        else {
            while(Bgetc(b) >= 0)
                n++;
            Bterm(b);
        }
    }
    return n;
}

main {
    writefile("/tmp/o9_rawc_bio.txt", "abcde");
    Task<int64> t = spawn countbytes("/tmp/o9_rawc_bio.txt");
    print(t.await(), "\n");
}
```

## Spawned Task

```o9
function add(int64 a, int64 b) int64 {
    return a + b;
}

main {
    Task<int64> t = spawn add(20, 22);
    int64 v = t.await();
    print(v, "\n");
}
```

## Nested Function In A Class

```o9
class Worker {
    function addraw(int64 a, int64 b) int64 {
        int64 out;

        c {
            out = a + b;
        }
        return out;
    }

    method Worker() {
    }

    method int64 add(int64 a, int64 b) {
        Task<int64> t = spawn addraw(a, b);
        return t.await();
    }
}

main {
    Worker w = new Worker();
    print(w.add(20, 22), "\n");
}
```

## Session Method Calls

An app that calls `serve()` can be driven through the mounted 9P facade:

```o9
class Counter {
    int64 val;
    method Counter(int64 n) { val = n; }
    method void inc(int64 n) { val = val + n; }
    method int64 get() { return val; }
}

main {
    Counter c = new Counter(40);
    serve();
}
```

Shell client:

```rc
mount -c /srv/o9.Counter.Counter.app /mnt/o9
sid=`{cat /mnt/o9/clone}
echo 'method Counter.c inc arg0=2' > /mnt/o9/$sid/ctl
echo 'method Counter.c get' > /mnt/o9/$sid/ctl
cat /mnt/o9/$sid/data
echo close > /mnt/o9/$sid/ctl
```
