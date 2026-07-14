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
        int ch;

        n = 0;
        cpath = o9_string_cstr(path);
        b = cpath != nil ? Bopen(cpath, OREAD) : nil;
        free(cpath);
        if(b == nil)
            n = -1;
        else {
            while((ch = Bgetc(b)) >= 0)
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
