#include <u.h>
#include <libc.h>
#include "o9_type.h"

typedef struct BuiltinExpect BuiltinExpect;
struct BuiltinExpect {
	char *name;
	char *plan9;
	char *abi;
	char *fmt;
	char *zero;
};

static BuiltinExpect builtins[] = {
	{ "bool", "int", "scalar", "%d", "0" },
	{ "int64", "vlong", "scalar", "%lld", "0" },
	{ "uint64", "uvlong", "scalar", "%llud", "0" },
	{ "int32", "long", "scalar", "%ld", "0" },
	{ "uint32", "ulong", "scalar", "%lud", "0" },
	{ "int16", "short", "scalar", "%d", "0" },
	{ "uint16", "ushort", "scalar", "%ud", "0" },
	{ "int8", "char", "scalar", "%d", "0" },
	{ "uint8", "uchar", "scalar", "%ud", "0" },
	{ "byte", "uchar", "scalar", "%ud", "0" },
	{ "double", "double", "scalar", "%g", "0.0" },
	{ "void", "void", "none", "", "" },
	{ "string", "O9String*", "pointer", "%p", "nil" },
	{ "function", "void*", "pointer", "%p", "nil" },
	{ "int", "int", "scalar", "%d", "0" },
	{ "uint", "uint", "scalar", "%ud", "0" },
	{ "short", "short", "scalar", "%d", "0" },
	{ "long", "long", "scalar", "%ld", "0" },
	{ "char", "char", "scalar", "%d", "0" },
	{ "intptr", "intptr", "scalar", "%lld", "0" },
	{ "uintptr", "uintptr", "scalar", "%llud", "0" },
	{ "vlong", "vlong", "scalar", "%lld", "0" },
	{ "uvlong", "uvlong", "scalar", "%llud", "0" },
	{ "ulong", "ulong", "scalar", "%lud", "0" },
	{ "ushort", "ushort", "scalar", "%ud", "0" },
	{ "uchar", "uchar", "scalar", "%ud", "0" },
	{ "tabula", "O9Tabula*", "pointer", "%p", "nil" },
	{ "MountTable", "O9MountTable*", "pointer", "%p", "nil" },
	{ nil, nil, nil, nil, nil },
};

static void
checkstr(char *name, char *got, char *want)
{
	if(got == nil || strcmp(got, want) != 0)
		sysfatal("%s: got %s want %s", name, got != nil ? got : "<nil>", want);
}

static void
check_builtin_table(void)
{
	BuiltinExpect *b;
	int i;

	for(i = 0; builtins[i].name != nil; i++){
		b = &builtins[i];
		checkstr("builtin name", type_builtin_name(i), b->name);
		if(!type_is_builtin_name(b->name))
			sysfatal("builtin missing: %s", b->name);
		checkstr(b->name, type_builtin_plan9(b->name), b->plan9);
		checkstr(b->name, type_builtin_abi(b->name), b->abi);
		checkstr(b->name, type_builtin_fmt(b->name), b->fmt);
		checkstr(b->name, type_builtin_zero(b->name), b->zero);
	}
	if(type_builtin_count() != i)
		sysfatal("builtin count: got %d want %d", type_builtin_count(), i);
	if(type_builtin_name(-1) != nil)
		sysfatal("builtin name -1 should be nil");
	if(type_builtin_name(i) != nil)
		sysfatal("builtin name past end should be nil");
	if(type_builtin_name(i + 1) != nil)
		sysfatal("builtin name beyond end should be nil");
	if(type_is_builtin_name(nil))
		sysfatal("nil should not be a builtin name");
	if(type_builtin_plan9(nil) != nil)
		sysfatal("nil builtin plan9 should be nil");
	if(type_builtin_abi(nil) != nil)
		sysfatal("nil builtin abi should be nil");
	if(type_builtin_fmt(nil) != nil)
		sysfatal("nil builtin fmt should be nil");
	if(type_builtin_zero(nil) != nil)
		sysfatal("nil builtin zero should be nil");
}

static void
check_type_alloc_zeroing(void)
{
	Type *n, *p, *a;
	TypeList *list;

	n = type_name("Example");
	if(n->kind != TyName || n->name == nil || strcmp(n->name, "Example") != 0)
		sysfatal("type_name fields");
	if(n->base != nil || n->args != nil)
		sysfatal("type_name allocation was not zeroed");

	n = type_name(nil);
	if(n->kind != TyName || n->name != nil)
		sysfatal("type_name nil fields");
	if(n->base != nil || n->args != nil)
		sysfatal("type_name nil allocation was not zeroed");

	p = type_ptr(type_name("int64"));
	if(p->kind != TyPtr || p->base == nil)
		sysfatal("type_ptr fields");
	if(p->name != nil || p->args != nil)
		sysfatal("type_ptr allocation was not zeroed");

	a = type_array(type_name("byte"));
	if(a->kind != TyArray || a->base == nil)
		sysfatal("type_array fields");
	if(a->name != nil || a->args != nil)
		sysfatal("type_array allocation was not zeroed");

	list = type_list(type_name("int64"));
	if(list->type == nil)
		sysfatal("type_list field");
	if(list->next != nil)
		sysfatal("type_list allocation was not zeroed");
}

static void
check_type_list_append(void)
{
	TypeList *list;

	list = nil;
	list = type_list_append(list, type_name("First"));
	list = type_list_append(list, type_name("Second"));
	list = type_list_append(list, type_name("Third"));
	if(type_list_len(list) != 3)
		sysfatal("type_list_append length: got %d want 3", type_list_len(list));
	if(list == nil || list->next == nil || list->next->next == nil)
		sysfatal("type_list_append chain");
	checkstr("type_list_append first", list->type->name, "First");
	checkstr("type_list_append second", list->next->type->name, "Second");
	checkstr("type_list_append third", list->next->next->type->name, "Third");
	if(list->next->next->next != nil)
		sysfatal("type_list_append tail");
}

static void
check_type_render_helpers(void)
{
	Type *i64, *bytes, *list, *pair, *empty, *noargs;
	TypeList *args;
	Type bad;

	i64 = type_name("int64");
	bytes = type_name("byte");
	memset(&bad, 0, sizeof bad);
	bad.kind = 99;
	checkstr("render nil", type_render(nil), "<nil>");
	checkstr("render badtype", type_render(&bad), "<badtype>");
	checkstr("dump nil", type_dump(nil), "Nil");
	checkstr("dump badtype", type_dump(&bad), "BadType");
	checkstr("cname nil", type_cname(nil), "nil");
	checkstr("cname badtype", type_cname(&bad), "badtype");
	checkstr("dump empty name", type_dump(type_name("")), "Name()");
	checkstr("dump empty param", type_dump(type_param("")), "Param()");
	checkstr("render ptr", type_render(type_ptr(i64)), "int64*");
	checkstr("render array", type_render(type_array(bytes)), "byte[]");
	checkstr("dump ptr", type_dump(type_ptr(type_name("int64"))), "Ptr(Name(int64))");
	checkstr("dump array", type_dump(type_array(type_name("byte"))), "Array(Name(byte))");
	checkstr("cname dotted", type_cname(type_name(".")), "__");
	checkstr("cname star", type_cname(type_name("Thing*")), "Thingp");
	checkstr("cname star middle", type_cname(type_name("Thing*Box")), "ThingpBox");
	checkstr("cname ptr", type_cname(type_ptr(type_name("int64"))), "int64_ptr");
	checkstr("cname array", type_cname(type_array(type_name("byte"))), "byte_arr");

	list = type_apply("List", type_list(type_name("int64")));
	checkstr("render apply", type_render(list), "List<int64>");
	checkstr("dump apply", type_dump(list), "Apply(List,Name(int64))");
	checkstr("cname apply", type_cname(list), "List__int64");
	list = type_apply("A", type_list(type_name("B")));
	checkstr("render apply short", type_render(list), "A<B>");

	args = nil;
	args = type_list_append(args, type_name("Left"));
	args = type_list_append(args, type_param("Right"));
	pair = type_apply("Pair", args);
	checkstr("render apply pair", type_render(pair), "Pair<Left,Right>");
	checkstr("dump apply pair", type_dump(pair), "Apply(Pair,Name(Left),Param(Right))");
	checkstr("cname apply pair", type_cname(pair), "Pair__Left__Right");
	empty = type_apply("", type_list(type_name("Arg")));
	checkstr("render empty apply", type_render(empty), "<Arg>");
	checkstr("dump empty apply", type_dump(empty), "Apply(,Name(Arg))");
	checkstr("cname empty apply", type_cname(empty), "__Arg");
	noargs = type_apply("Zero", nil);
	checkstr("render noargs apply", type_render(noargs), "Zero<>");
	checkstr("dump noargs apply", type_dump(noargs), "Apply(Zero,)");
	checkstr("cname noargs apply", type_cname(noargs), "Zero__");
}

static void
check_type_backend_helpers(void)
{
	Type *i64, *missing, *param, *tabparam, *ptr, *emptyptr, *array, *list, *later, *tabula;
	Type bad;

	i64 = type_name("int64");
	missing = type_name("MissingBuiltin");
	param = type_param("T");
	tabparam = type_param("tabula");
	ptr = type_ptr(type_name("int64"));
	emptyptr = type_ptr(type_param(""));
	array = type_array(type_name("byte"));
	list = type_apply("List", type_list(type_name("int64")));
	later = type_apply("zeta", type_list(type_name("int64")));
	tabula = type_apply("Tabula", nil);
	memset(&bad, 0, sizeof bad);
	bad.kind = -1;
	bad.name = "int64";

	checkstr("storage builtin", type_storage(i64), "vlong");
	checkstr("storage invalid negative", type_storage(&bad), "<badtype>");
	bad.kind = 99;
	checkstr("storage invalid positive", type_storage(&bad), "<badtype>");
	checkstr("storage named", type_storage(missing), "MissingBuiltin");
	checkstr("storage param", type_storage(param), "T");
	checkstr("storage tabula param", type_storage(tabparam), "tabula");
	checkstr("storage ptr", type_storage(ptr), "vlong*");
	checkstr("storage empty ptr", type_storage(emptyptr), "*");
	checkstr("storage array", type_storage(array), "uchar*");
	checkstr("storage apply", type_storage(list), "List__int64");
	checkstr("storage later apply", type_storage(later), "zeta__int64");
	checkstr("storage tabula apply", type_storage(tabula), "O9Tabula*");
	checkstr("storage nil", type_storage(nil), "void");

	checkstr("plan9 nil", type_plan9(nil), "void");
	checkstr("plan9 builtin", type_plan9(i64), "vlong");
	checkstr("plan9 named", type_plan9(missing), "MissingBuiltin");
	checkstr("plan9 param", type_plan9(param), "void*");
	checkstr("plan9 ptr", type_plan9(ptr), "vlong*");
	checkstr("plan9 array", type_plan9(array), "O9Slice");
	checkstr("plan9 apply", type_plan9(list), "List__int64");
	checkstr("plan9 tabula apply", type_plan9(tabula), "O9Tabula*");

	checkstr("abi nil", type_abi(nil), "none");
	checkstr("abi builtin", type_abi(i64), "scalar");
	checkstr("abi named", type_abi(missing), "named");
	checkstr("abi param", type_abi(param), "param");
	checkstr("abi ptr", type_abi(ptr), "pointer");
	checkstr("abi array", type_abi(array), "slice");
	checkstr("abi apply", type_abi(list), "generic");
	checkstr("abi tabula apply", type_abi(tabula), "pointer");

	checkstr("fmt nil", type_fmt(nil), "%p");
	checkstr("fmt builtin", type_fmt(i64), "%lld");
	checkstr("fmt void", type_fmt(type_name("void")), "%p");
	checkstr("fmt param", type_fmt(param), "%p");

	checkstr("bool type zero", type_zero(type_name("bool")), "0");
	checkstr("int64 type zero", type_zero(i64), "0");
	checkstr("string type zero", type_zero(type_name("string")), "nil");
	checkstr("double type zero", type_zero(type_name("double")), "0.0");
	checkstr("void type zero", type_zero(type_name("void")), "0");
	checkstr("unknown type zero", type_zero(missing), "0");
	checkstr("ptr type zero", type_zero(ptr), "nil");
	checkstr("array type zero", type_zero(array), "nil");
	checkstr("apply type zero", type_zero(list), "nil");
	checkstr("param type zero", type_zero(param), "0");
}

void
main(int, char**)
{
	check_builtin_table();
	check_type_alloc_zeroing();
	check_type_list_append();
	check_type_render_helpers();
	check_type_backend_helpers();

	print("o9_type_test: OK\n");
	exits(nil);
}
