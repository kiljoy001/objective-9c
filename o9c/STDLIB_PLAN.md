# Objective-9C Plan 9 Namespace and Standard Library Roadmap

## Plan 9 Namespace Contract

In this project, "namespace" should mean the Plan 9 per-process file namespace: a composed view built from `bind`, `mount`, `/srv`, and 9P file trees. Source-level names such as `App.Counter` are modules/type qualifiers, not the application namespace.

An Objective-9C application should compose its objects under one Plan 9 namespace root, for example:

```text
/mnt/o9/App/
	ctl
	types/
		App__Counter
		App__Color
	obj/
		counter/
			ctl
			data
			status
	lib/
		text/
		fs/
		time/
```

Each object remains a 9P service. The runtime should be able to post it in `/srv`, then mount or bind it into the application namespace root:

```text
/srv/o9.App.Counter.counter
/mnt/o9/App/obj/counter
```

Object composition should happen by path, not by language-level namespace lookup. A client should prefer a mounted object path like `/mnt/o9/App/obj/counter`, with `/srv/o9.App.Counter.counter` as the service publication point.

## Type To Plan 9 C Contract

The type system still needs stable C lowering, but this is separate from Plan 9 namespace composition:

| Source type | C symbol base | Plan 9 C storage |
| --- | --- | --- |
| `int64` | `int64` | `vlong` |
| `string` | `string` | `char*` |
| `App.Color` | `App__Color` | `int` |
| `App.Point` | `App__Point` | `App__Point` |
| `App.Counter` | `App__Counter` | `App__Counter_Client*` |
| `App.Box<int64>` | `App__Box__int64` | `App__Box__int64_Client*` for classes |
| `App.Pair<string,App.Color>` | `App__Pair__string__App__Color` | concrete struct symbol for structs |

Module-qualified type names are compile-time identity. Plan 9 namespace paths are runtime composition identity.

## Runtime Direction

The runtime should grow an explicit namespace root concept:

- Default root: `/mnt/o9/<app>`.
- Service publication: `/srv/o9.<app>.<type>.<instance>`.
- Mounted class path: `<root>/class/<type>`.
- Type metadata path: `<root>/types/<type-symbol>`.
- Standard library path: `<root>/lib/<service>`.
- Generated class services use the three-file endpoint shape: `ctl` for commands, `data` for payload/reply text, and `status` for stable compiler identity, member schema, cache metadata, namespace paths, health, and live instance names.

Client initialization should eventually support both forms:

- service name: `o9.App.Counter.counter`
- mounted path: `/mnt/o9/App/class/App__Counter`

The runtime now has the first helper surface for this:

- `o9_ns_app_root` builds `/mnt/o9/<app>`.
- `o9_ns_service_name` builds `o9.<app>.<type>.<instance>`.
- `o9_ns_class_path` builds `<root>/class/<type>` for generated class servers.
- `o9_ns_ensure_dir` creates a namespace directory if it is missing.
- `o9_ns_ensure_app` creates `<root>`, `<root>/obj`, `<root>/lib`, and `<root>/types`.
- `o9_init_client_path` initializes a client from a mounted object path and records its cache path for later refresh.

The current generated code still mostly uses `srvname`; path-based namespace resolution should become first-class in codegen so objects can discover and compose peers through the process namespace.

## Box and Link AST Direction

The sidecar type AST now treats object identity and Plan B-inspired links as first-class declarations:

```text
object Box<int64> primary;
object Box<int64> mirror;
link ref primary -> mirror;
link replica mirror -> primary;
```

An `object` declaration is a named runtime resource handle whose type must resolve to a class or interface, including generic instantiations. It does not mean "box every C value"; native generated C can still use direct storage where possible.

A `link` declaration records namespace composition intent between declared objects. The first supported link kinds are:

- `ref`: the source should behave as a reference or redirection to the target.
- `replica`: the source should behave as a copy/snapshot/synchronized replica of the target.

This is compiler metadata for the future local box service. It gives codegen enough structure to publish object handles and link tables later without implementing the ring-buffer/channel transport or box coordinator inside the parser.

## Standard Library Shape

The standard library should be a set of ordinary Objective-9C modules plus Plan 9 namespace-visible services.

First library layers:

- `Core`: result/error conventions, object identity, memory helpers, and type metadata.
- `Text`: string length, compare, copy, split/join, integer formatting/parsing.
- `Fs`: file read/write/open helpers over Plan 9 file descriptors.
- `Time`: `vlong` time helpers and formatting.
- `IO`: buffered input/output and print helpers.
- `Net`: dial/listen wrappers after namespace-root resolution is stable.
- `Collections`: lists, dicts, sets, and iterators after user-defined generics are integrated into production `o9c`.

At runtime, these should be mountable/bindable under the application root, for example `<root>/lib/text` and `<root>/lib/fs`.

## Build Order

1. Keep `module` as the source-level type qualifier term; reserve "namespace" for Plan 9 namespace behavior.
2. Move the sidecar `Type` model into production `o9c` with `Type *typeinfo` beside existing `typename`.
3. Add module-qualified type parsing and C-safe symbol mangling.
4. Add enums as typed integer constants.
5. Add generic class/struct/interface declarations and arity checks.
6. Add runtime namespace-root helpers and path-based object lookup.
7. Change object publication from bare class names to stable `/srv/o9.<app>.<type>.<instance>` names.
8. Mount/bind object services under `<root>/obj/<instance>`.
9. Build the first stdlib services under `<root>/lib`.
10. Add collections once generic instantiation and namespace composition are both stable.

## Current Prototype Coverage

The `o9type` sidecar validates the compile-time half:

- Basic type to Plan 9 C mappings.
- Module-qualified class, struct, interface, and enum declarations.
- Module-aware type resolution.
- User-defined generic arity.
- Enum value ownership and assignment.
- C-safe type name mangling.
- ABI categories for scalar, string, enum, struct, object reference, generic struct, generic object reference, pointer, and slice.
- Object declarations for class/interface resources, including generic object references.
- `ref` and `replica` link declarations between module-qualified objects.

Production `o9c` now has the first module-aware parser path:

- `module App { ... }` wraps classes, interfaces, structs, and top-level functions.
- Bare type names inside a module are qualified against that module.
- Capitalized dotted type references such as `App.Counter` parse as type names without stealing ordinary property expressions such as `p.x`.
- Production codegen currently stores the C-safe symbol (`App__Counter`) as the compiler identity. The sidecar remains the reference model for preserving separate semantic names (`App.Counter`) and C symbols (`App__Counter`).

Production enums are also available:

- `enum Color { Red, Green, Blue }` declares a real type.
- Module-qualified enums lower to C-safe symbols such as `App__Color`.
- Enum values emit stable C constants such as `App__Color__Red`.
- Enum storage lowers to Plan 9 C `int`.
- Enum variable/property initialization rejects values from a different enum.

Production AST coverage now includes the first generic/object layer:

- `module` blocks are preserved as real production AST container nodes instead of being flattened away.
- `o9c -ast` dumps the production AST for direct parser/semantic regression tests.
- Generic class, struct, and interface declarations are parsed in production `o9c`.
- Structured `Type*` metadata is attached beside legacy C-lowering strings.
- Expression nodes are annotated with `Type*` metadata during semantic checking where the type can be resolved: literals, locals, parameters, class fields, property reads, message sends, `new`, collection indexing, assignments, returns, and common operators.
- Method parameters and locals are resolved through scoped type symbols during semantic checking, so generic parameters from one declaration do not leak into another method body.
- Production codegen now uses declaration-aware `Type*` lowering for local storage, list/dict operations, struct/internal fields, state persistence, method parameter unpacking, method return formatting, and property read/write casts.
- Production semantic checking now validates local initialization, assignment, return values, collection method arity/types, and class method arity/argument types through `Type*` compatibility.
- Production AST/type checking now supports `abstract class`, abstract method declarations, interface method declarations, inheritance target validation, override signature checks, and concrete implementation checks for inherited abstract/interface methods.
- Generated 9P class services now expose `ctl`, `data`, and `status`; `status` contains the C-safe type identity, `Type*`-derived class/member/method/parameter metadata, cache hints, namespace paths, and the live instance list.
- Remote client fallback now writes counted `method <instance> <name> argN=value ...` commands to `ctl` and reads method results from `data`.
- `List<T>` and `Dict<K,V>` parse as normal type applications while lowering to the existing runtime collection carriers.
- Generic arity is checked for user-defined generic types.
- Generic templates are intentionally skipped by C codegen until instantiation/monomorphization is implemented.
- `object` declarations and `link ref` / `link replica` declarations are parsed and type checked.
- Declared object/link metadata is written to libtab-backed state files under `<root>/state`.
- Class server state can now use stable namespace-root libtab files via `o9_state_create_path`.

The next runtime prototype should validate the live Plan 9 namespace half:

- Build an application root at `/mnt/o9/<app>`.
- Publish object services under `/srv/o9.<app>.<type>.<instance>`.
- Mount/bind object trees under `<root>/obj`.
- Resolve object references by path.
- Expose stdlib services under `<root>/lib`.
