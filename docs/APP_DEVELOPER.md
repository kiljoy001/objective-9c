# Application Developer Guide

This is the short path from "I want to write an app" to a running o9 program.
It assumes you know the basics of files, processes, and 9P, but not Plan 9 C.

## The rule

Application code should not need raw C, `spawn`, or `await` for ordinary
scaffolding. The standard library hides those details. Raw C remains available
inside stdlib modules for system-level work, but an app author should be able
to start with `cli.o9`, `config.o9`, and `service.o9`.

## Your first CLI

```o9
import "cli.o9";
import "config.o9";

main {
    Args args = new Args(1);
    string configPath = args.opt("config", "/tmp/hello.conf");
    Config config = new Config(configPath);
    string name = args.opt("name", config.get("name", "world"));
    print("hello, ", name, "\n");
}
```

```sh
o9build hello_cli.o9
./hello_cli -name alice
./hello_cli -config /tmp/hello.conf
```

A runnable copy is `demo/hello_cli.o9`.

## Your first service

```o9
import "service.o9";

class HelloViews {
    ViewController;

    internal method FileTree display(string id, string caller) {
        FileTree root = new FileTree();
        root.text("status", "hello from o9\n", false);
        return root;
    }

    internal method string readText(string id, string path) { return ""; }
    internal method int64 writeText(string id, string path, int64 offset,
                                    string text, bool truncate) { return -1; }
}

main {
    HelloViews views = new HelloViews();
    Service service = new Service("helloservice");
    service.run(views);
}
```

```sh
o9build hello_service.o9
./hello_service helloservice &
mount /srv/helloservice /n/hello
cat /n/hello/status
```

A runnable copy is `demo/hello_service.o9`.

## Settings files

```o9
import "config.o9";

Config config = new Config("/tmp/app.conf");
config.set("name", "alice");
config.set("port", "6667");
config.save();

string port = config.get("port", "8080");
```

Use `setSeparator("\t")` for tab-separated records. For multi-row structured
data, use `tabula` instead.

## Command-line options

```o9
import "cli.o9";

main {
    Args args = new Args(1);
    if(!args.require(1, "usage: tool INPUT")) {
        return;
    }
    string input = args.at(0);
    string output = args.opt("output", "out.txt");
    bool verbose = args.flag("verbose");
    int64 limit = args.intOption("limit", 100);
    string home = args.env("HOME", "/tmp");
    print(input, " ", output, " ", verbose, " ", limit, " ", home, "\n");
}
```

## Drawing a window

```o9
import "draw.o9";

main {
    DrawWindow window = new DrawWindow("hello", 320, 200);
    DrawLabel label = new DrawLabel("hello, o9", 20, 20, 200, 20);
    window.add(label);
    if(window.open()) {
        window.update();
        while(true) {
            int64 kind = window.nextEvent();
            if(kind == 2 && window.eventKey() == 'q') {
                break;
            }
        }
        window.close();
    }
}
```

The `demo/demo_draw_*.o9` programs are small, complete examples of the widget
set, tables, text input, menus, scrollbars, and layout.

## Where the programs live

| Program | Path | What it is |
|---|---|---|
| IRC client | `o9irc/irc.o9` | terminal IRC client |
| IRC service | `o9irc/ircfs.o9` | 9P service with `networks/default/*` view |
| IRC Rio UI | `o9irc/gui.o9` | full Rio GUI for the IRC service |
| IRC history | `o9irc/history.o9` | bounded transcript archive |
| Mail service | `o9mail/mailfs.o9` | 9P mail service with AppUser auth |
| Mail sync | `o9mail/upas-sync.o9` | sync tool for mail files |
| Mutation engine | `grid/o9mutlib.o9` | mutation job engine over tabula |
| Mutation CLI | `grid/o9mutctl.o9` | control tool for the engine |
| Mutation replay | `grid/o9mutreplay.o9` | replay a mutation session |
| Zabbix agent | `grid/zabbix_agent.o9` | tiny Zabbix endpoint |
| Syslog monitor | `demo/syslogmon/syslogmon.o9` | tail logs into a tabula view |
| Auth facade | `stdlib/auth_facade_app.o9` | minimal auth-serving app |
| Hello CLI | `demo/hello_cli.o9` | smallest `Args` + `Config` app |
| Hello service | `demo/hello_service.o9` | smallest `Service` app |
| Draw demos | `demo/demo_draw_*.o9` | widget and layout examples |
| Property tests | `o9-testing/stdlib/property.o9` | deterministic property testing |
| App identity | `o9-testing/stdlib/appuser.o9` | AppUser RSA identities |
| House | `o9-testing/grid/house/house.o9` | service/UI example with records |

Some of these live in sibling repositories under `~/Repo` (`o9irc`, `o9mail`,
`o9-testing`). The core language, stdlib, demos, and grid tools live in
`objective-9c`.

## Standard library map

| Module | Use it for |
|---|---|
| `cli.o9` | argv, options, flags, environment, usage |
| `config.o9` | small key/value settings and profiles |
| `service.o9` | `viewController` + `serve` service bootstrap |
| `string.o9` | text search, trim, case, slice, replace |
| `bytes.o9`, `buffer.o9` | mutable binary/text builders |
| `format.o9`, `log.o9` | formatted text and leveled application logs |
| `result.o9` | explicit success/value/error returns |
| `collections.o9` | `list<T>`, `array<T>`, `dictionary<T>` |
| `file.o9`, `io.o9` | file operations, buffered streams, line readers |
| `dir.o9` | typed directory listings and tree walk/copy/remove |
| `path.o9` | Plan 9 path cleaning and decomposition |
| `process.o9` | argv/env/cwd, `Cmd`, and pipelines |
| `net.o9` | dial/listen, line reads, timeouts, factotum, TLS |
| `sync.o9` | mutex, wait group, semaphore, once, limiter |
| `rune.o9`, `9p.o9` | UTF-8 rune helpers and low-level 9P framing |
| `namespace.o9` | bind/mount and per-process namespaces |
| `draw.o9` | windows, widgets, layout, canvas, tables |
| `rtext.o9` | rich text, links, inline widgets |
| `view.o9` | `ViewController` and view trees |
| `testing.o9` | xUnit-style test harness |
| `time.o9`, `math.o9`, `random.o9` | time, math, randomness |

Full APIs are documented in `stdlib/README.md`. The language itself is in
`docs/LANGUAGE.md`; build and install details are in `docs/QUICKSTART.md`.

## Build and install

```sh
# create a new project (C-free cli/config template)
o9proj myapp
cd myapp
mk run

# build one program by hand
o9build hello_cli.o9

# install the toolchain and stdlib
mk install

# run a service and mount it
./hello_service helloservice &
mount /srv/helloservice /n/hello
```

## If you are adding a program

- Start from `demo/hello_cli.o9` or `demo/hello_service.o9`.
- Use `Args` instead of hand-parsing argv.
- Use `Config` instead of ad-hoc profile files.
- Use `Service` instead of repeating `viewController` + `serve`.
- Use `String`, `File`, `IOBuffer`, and `Collections` instead of new raw
  helpers.
- Keep raw C inside stdlib modules or a clearly named `*Raw` helper; do not
  make app authors cross the C boundary.
