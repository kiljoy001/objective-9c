#include <u.h>
#include <libc.h>
#include "o9_type.h"

typedef struct Builtin Builtin;
struct Builtin {
	char *name;
	char *plan9;
	char *abi;
	char *fmt;
	char *zero;
};

static Builtin builtins[] = {
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
	{ "void", "void", "none", "", "" },
	{ "string", "O9String*", "pointer", "%p", "nil" },
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
	{ "Tabula", "O9Tabula*", "pointer", "%p", "nil" },	/* table handle */
	{ nil, nil, nil, nil, nil }
};

static void*
emalloc(ulong n)
{
	void *p;

	p = malloc(n);
	if(p == nil)
		sysfatal("malloc");
	memset(p, 0, n);
	return p;
}

static char*
estrdup(char *s)
{
	char *r;

	if(s == nil)
		return nil;
	r = strdup(s);
	if(r == nil)
		sysfatal("strdup");
	return r;
}

static char*
join2(char *a, char *b)
{
	char *r;
	int n;

	if(a == nil)
		a = "";
	if(b == nil)
		b = "";
	n = strlen(a) + strlen(b) + 1;
	r = emalloc(n);
	snprint(r, n, "%s%s", a, b);
	return r;
}

static char*
mangle_name(char *name)
{
	char *r;
	int i, j, n;

	if(name == nil)
		return estrdup("nil");
	n = strlen(name) * 2 + 1;
	r = emalloc(n);
	j = 0;
	for(i = 0; name[i]; i++){
		if(name[i] == '.'){
			r[j++] = '_';
			r[j++] = '_';
		}else if(name[i] == '*'){
			r[j++] = 'p';
		}else{
			r[j++] = name[i];
		}
	}
	r[j] = 0;
	return r;
}

Type*
type_name(char *name)
{
	Type *t;

	t = emalloc(sizeof(Type));
	t->kind = TyName;
	t->name = estrdup(name);
	return t;
}

Type*
type_param(char *name)
{
	Type *t;

	t = emalloc(sizeof(Type));
	t->kind = TyParam;
	t->name = estrdup(name);
	return t;
}

Type*
type_apply(char *name, TypeList *args)
{
	Type *t;

	t = emalloc(sizeof(Type));
	t->kind = TyApply;
	t->name = estrdup(name);
	t->args = args;
	return t;
}

Type*
type_ptr(Type *base)
{
	Type *t;

	t = emalloc(sizeof(Type));
	t->kind = TyPtr;
	t->base = base;
	return t;
}

Type*
type_array(Type *base)
{
	Type *t;

	t = emalloc(sizeof(Type));
	t->kind = TyArray;
	t->base = base;
	return t;
}

TypeList*
type_list(Type *type)
{
	TypeList *l;

	l = emalloc(sizeof(TypeList));
	l->type = type;
	return l;
}

TypeList*
type_list_append(TypeList *list, Type *type)
{
	TypeList *l;

	if(list == nil)
		return type_list(type);
	for(l = list; l->next; l = l->next)
		;
	l->next = type_list(type);
	return list;
}

int
type_list_len(TypeList *list)
{
	int n;

	n = 0;
	for(; list; list = list->next)
		n++;
	return n;
}

static Builtin*
find_builtin(char *name)
{
	Builtin *b;

	if(name == nil)
		return nil;
	for(b = builtins; b->name; b++)
		if(strcmp(b->name, name) == 0)
			return b;
	return nil;
}

int
type_builtin_count(void)
{
	int n;

	n = 0;
	while(builtins[n].name != nil)
		n++;
	return n;
}

char*
type_builtin_name(int idx)
{
	if(idx < 0 || idx >= type_builtin_count())
		return nil;
	return builtins[idx].name;
}

int
type_is_builtin_name(char *name)
{
	return find_builtin(name) != nil;
}

char*
type_builtin_plan9(char *name)
{
	Builtin *b;

	b = find_builtin(name);
	if(b == nil)
		return nil;
	return b->plan9;
}

char*
type_builtin_abi(char *name)
{
	Builtin *b;

	b = find_builtin(name);
	if(b == nil)
		return nil;
	return b->abi;
}

char*
type_builtin_fmt(char *name)
{
	Builtin *b;

	b = find_builtin(name);
	if(b == nil)
		return nil;
	return b->fmt;
}

char*
type_builtin_zero(char *name)
{
	Builtin *b;

	b = find_builtin(name);
	if(b == nil)
		return nil;
	return b->zero;
}

static char*
render_list(TypeList *list, char *sep, int dump)
{
	TypeList *l;
	char *r, *part, *old;
	int first;

	r = estrdup("");
	first = 1;
	for(l = list; l; l = l->next){
		part = dump ? type_dump(l->type) : type_render(l->type);
		if(!first){
			old = r;
			r = join2(r, sep);
			free(old);
		}
		old = r;
		r = join2(r, part);
		free(old);
		first = 0;
	}
	return r;
}

char*
type_render(Type *type)
{
	char *b, *args, *r;
	int n;

	if(type == nil)
		return estrdup("<nil>");
	switch(type->kind){
	case TyName:
	case TyParam:
		return estrdup(type->name);
	case TyApply:
		args = render_list(type->args, ",", 0);
		n = strlen(type->name) + strlen(args) + 3;
		r = emalloc(n);
		snprint(r, n, "%s<%s>", type->name, args);
		return r;
	case TyPtr:
		b = type_render(type->base);
		r = join2(b, "*");
		return r;
	case TyArray:
		b = type_render(type->base);
		r = join2(b, "[]");
		return r;
	}
	return estrdup("<badtype>");
}

char*
type_dump(Type *type)
{
	char *b, *args, *r;
	int n;

	if(type == nil)
		return estrdup("Nil");
	switch(type->kind){
	case TyName:
		n = strlen(type->name) + 8;
		r = emalloc(n);
		snprint(r, n, "Name(%s)", type->name);
		return r;
	case TyParam:
		n = strlen(type->name) + 9;
		r = emalloc(n);
		snprint(r, n, "Param(%s)", type->name);
		return r;
	case TyApply:
		args = render_list(type->args, ",", 1);
		n = strlen(type->name) + strlen(args) + 10;
		r = emalloc(n);
		snprint(r, n, "Apply(%s,%s)", type->name, args);
		return r;
	case TyPtr:
		b = type_dump(type->base);
		n = strlen(b) + 6;
		r = emalloc(n);
		snprint(r, n, "Ptr(%s)", b);
		return r;
	case TyArray:
		b = type_dump(type->base);
		n = strlen(b) + 8;
		r = emalloc(n);
		snprint(r, n, "Array(%s)", b);
		return r;
	}
	return estrdup("BadType");
}

static char*
mangle_list(TypeList *list)
{
	TypeList *l;
	char *r, *part, *old;
	int first;

	r = estrdup("");
	first = 1;
	for(l = list; l; l = l->next){
		part = type_cname(l->type);
		if(!first){
			old = r;
			r = join2(r, "__");
			free(old);
		}
		old = r;
		r = join2(r, part);
		free(old);
		first = 0;
	}
	return r;
}

char*
type_cname(Type *type)
{
	char *b, *args, *r, *bn;
	int n;

	if(type == nil)
		return estrdup("nil");
	switch(type->kind){
	case TyName:
	case TyParam:
		return mangle_name(type->name);
	case TyApply:
		bn = mangle_name(type->name);
		args = mangle_list(type->args);
		n = strlen(bn) + strlen(args) + 3;
		r = emalloc(n);
		snprint(r, n, "%s__%s", bn, args);
		return r;
	case TyPtr:
		b = type_cname(type->base);
		r = join2(b, "_ptr");
		return r;
	case TyArray:
		b = type_cname(type->base);
		r = join2(b, "_arr");
		return r;
	}
	return estrdup("badtype");
}

char*
type_storage(Type *type)
{
	char *n, *p, *r;
	int len;

	if(type == nil)
		return estrdup("void");
	if(type->kind == TyName){
		n = type->name;
		p = type_builtin_plan9(n);
		if(p != nil)
			return estrdup(p);
	}
	if(type->kind == TyPtr || type->kind == TyArray){
		p = type_storage(type->base);
		len = strlen(p) + 2;
		r = emalloc(len);
		snprint(r, len, "%s*", p);
		return r;
	}
	if(type->kind == TyApply)
		return type_cname(type);
	return type_render(type);
}

char*
type_plan9(Type *type)
{
	char *p;

	if(type == nil)
		return estrdup("void");
	if(type->kind == TyName){
		p = type_builtin_plan9(type->name);
		if(p != nil)
			return estrdup(p);
		return type_cname(type);
	}
	if(type->kind == TyParam)
		return estrdup("void*");
	if(type->kind == TyPtr)
		return type_storage(type);
	if(type->kind == TyArray)
		return estrdup("O9Slice");
	if(type->kind == TyApply)
		return type_cname(type);
	return type_storage(type);
}

char*
type_abi(Type *type)
{
	char *a;

	if(type == nil)
		return "none";
	if(type->kind == TyName){
		a = type_builtin_abi(type->name);
		if(a != nil)
			return a;
		return "named";
	}
	if(type->kind == TyParam)
		return "param";
	if(type->kind == TyPtr)
		return "pointer";
	if(type->kind == TyArray)
		return "slice";
	if(type->kind == TyApply)
		return "generic";
	return "unknown";
}

char*
type_fmt(Type *type)
{
	char *f;

	if(type != nil && type->kind == TyName){
		f = type_builtin_fmt(type->name);
		if(f != nil && f[0] != 0)
			return f;
	}
	if(type != nil && type->kind == TyParam)
		return "%p";
	return "%p";
}

char*
type_zero(Type *type)
{
	char *z;

	if(type != nil && type->kind == TyName){
		z = type_builtin_zero(type->name);
		if(z != nil && z[0] != 0)
			return z;
	}
	if(type != nil && (type->kind == TyPtr || type->kind == TyArray || type->kind == TyApply))
		return "nil";
	return "0";
}

int
type_equal(Type *a, Type *b)
{
	TypeList *la, *lb;

	if(a == nil || b == nil)
		return a == b;
	if(a->kind != b->kind)
		return 0;
	switch(a->kind){
	case TyName:
	case TyParam:
		return strcmp(a->name, b->name) == 0;
	case TyApply:
		if(strcmp(a->name, b->name) != 0)
			return 0;
		for(la = a->args, lb = b->args; la && lb; la = la->next, lb = lb->next)
			if(!type_equal(la->type, lb->type))
				return 0;
		return la == nil && lb == nil;
	case TyPtr:
	case TyArray:
		return type_equal(a->base, b->base);
	}
	return 0;
}

int
type_assignable(Type *target, Type *actual)
{
	return type_equal(target, actual);
}
