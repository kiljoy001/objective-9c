%{
#include <u.h>
#include <libc.h>
#include <ctype.h>
#include "o9_type.h"

typedef struct NameList NameList;
typedef struct Field Field;
typedef struct Item Item;
typedef struct TypeDef TypeDef;
typedef struct EnumSym EnumSym;
typedef struct ObjectSym ObjectSym;

enum {
	IType,
	IVar,
	IDecl,
	IModule,
	IObject,
	ILink
};

struct NameList {
	char *name;
	NameList *next;
};

struct Field {
	char *kind;
	char *name;
	Type *type;
	Field *next;
};

struct Item {
	int kind;
	char *declkind;
	char *name;
	char *init;
	NameList *params;
	NameList *enumvals;
	Field *fields;
	Type *type;
	Item *items;
	Item *next;
};

struct TypeDef {
	char *name;
	char *qname;
	char *ns;
	char *kind;
	int arity;
	NameList *params;
	TypeDef *next;
};

struct EnumSym {
	char *name;
	char *qname;
	char *membername;
	char *enumname;
	EnumSym *next;
};

struct ObjectSym {
	char *name;
	char *qname;
	Type *type;
	ObjectSym *next;
};

static Item *program_items;
static TypeDef *type_defs;
static EnumSym *enum_syms;
static ObjectSym *object_syms;
static int errors;
static int line_no = 1;
static char *input_buf;
static long input_pos;
static long input_len;

static void *emalloc(ulong n);
static char *estrdup(char *s);
static NameList *name_list(char *name);
static NameList *name_list_append(NameList *list, char *name);
static int name_list_len(NameList *list);
static int name_in_list(NameList *list, char *name);
static Field *field_new(char *kind, Type *type, char *name);
static Field *field_append(Field *list, Field *field);
static Item *item_append(Item *list, Item *item);
static Item *decl_item(char *kind, char *name, NameList *params, Field *fields);
static Item *module_item(char *name, Item *items);
static Item *enum_item(char *name, NameList *vals);
static Item *type_item(Type *type);
static Item *var_item(Type *type, char *name, char *init);
static Item *object_item(Type *type, char *name);
static Item *link_item(char *kind, char *from, char *to);
static void register_builtins(void);
static void collect_defs(Item *items, char *ns);
static void collect_enum_syms(Item *items, char *ns);
static void collect_object_syms(Item *items, char *ns);
static void validate_items(Item *items, char *ns);
static void dump_items(Item *items, char *ns);
static void yyerror(char *s);
static int yylex(void);
int yyparse(void);
%}

%union {
	char *s;
	Type *type;
	TypeList *types;
	NameList *names;
	Field *field;
	Item *item;
}

%token <s> TIDENT TTYPE
%token TCLASS TSTRUCT TINTERFACE TENUM TMODULE TPROP TSTATE TATOMIC TOBJECT TLINK TREF TREPLICA

%type <item> program items item decl_item type_stmt var_stmt object_stmt link_stmt class_decl struct_decl interface_decl enum_decl module_decl
%type <names> generic_opt ident_names enum_names
%type <field> field_list field
%type <s> field_prefix name_ref link_kind
%type <type> type_expr type_primary
%type <types> type_args

%start program

%%

program:
	/* empty */ { program_items = nil; $$ = nil; }
	| items { program_items = $1; $$ = $1; }
	;

items:
	item { $$ = $1; }
	| items item { $$ = item_append($1, $2); }
	;

item:
	decl_item
	| module_decl
	| type_stmt
	| var_stmt
	| object_stmt
	| link_stmt
	;

decl_item:
	class_decl
	| struct_decl
	| interface_decl
	| enum_decl
	;

class_decl:
	TCLASS TIDENT generic_opt '{' field_list '}' opt_semi
	{
		$$ = decl_item("class", $2, $3, $5);
	}
	;

struct_decl:
	TSTRUCT TIDENT generic_opt '{' field_list '}' opt_semi
	{
		$$ = decl_item("struct", $2, $3, $5);
	}
	;

interface_decl:
	TINTERFACE TIDENT generic_opt '{' field_list '}' opt_semi
	{
		$$ = decl_item("interface", $2, $3, $5);
	}
	;

enum_decl:
	TENUM TIDENT '{' enum_names opt_comma '}' opt_semi
	{
		$$ = enum_item($2, $4);
	}
	;

module_decl:
	TMODULE name_ref '{' items '}' opt_semi
	{
		$$ = module_item($2, $4);
	}
	;

name_ref:
	TIDENT { $$ = $1; }
	| name_ref '.' TIDENT
	{
		char *s;
		int n;
		n = strlen($1) + strlen($3) + 2;
		s = emalloc(n);
		snprint(s, n, "%s.%s", $1, $3);
		$$ = s;
	}
	;

generic_opt:
	/* empty */ { $$ = nil; }
	| '<' ident_names '>' { $$ = $2; }
	;

ident_names:
	TIDENT { $$ = name_list($1); }
	| ident_names ',' TIDENT { $$ = name_list_append($1, $3); }
	;

enum_names:
	TIDENT { $$ = name_list($1); }
	| enum_names ',' TIDENT { $$ = name_list_append($1, $3); }
	;

opt_comma:
	/* empty */
	| ','
	;

opt_semi:
	/* empty */
	| ';'
	;

field_list:
	/* empty */ { $$ = nil; }
	| field_list field { $$ = field_append($1, $2); }
	;

field:
	field_prefix type_expr TIDENT ';'
	{
		$$ = field_new($1, $2, $3);
	}
	;

field_prefix:
	/* empty */ { $$ = "field"; }
	| TPROP { $$ = "prop"; }
	| TSTATE { $$ = "state"; }
	| TATOMIC { $$ = "atomic"; }
	;

type_stmt:
	type_expr ';'
	{
		$$ = type_item($1);
	}
	;

var_stmt:
	type_expr TIDENT ';'
	{
		$$ = var_item($1, $2, nil);
	}
	| type_expr TIDENT '=' name_ref ';'
	{
		$$ = var_item($1, $2, $4);
	}
	;

object_stmt:
	TOBJECT type_expr TIDENT ';'
	{
		$$ = object_item($2, $3);
	}
	;

link_stmt:
	TLINK link_kind name_ref '-' '>' name_ref ';'
	{
		$$ = link_item($2, $3, $6);
	}
	;

link_kind:
	TREF { $$ = "ref"; }
	| TREPLICA { $$ = "replica"; }
	;

type_expr:
	type_primary { $$ = $1; }
	| type_expr '*' { $$ = type_ptr($1); }
	| type_expr '[' ']' { $$ = type_array($1); }
	;

type_primary:
	name_ref { $$ = type_name($1); }
	| TTYPE { $$ = type_name($1); }
	| name_ref '<' type_args '>' { $$ = type_apply($1, $3); }
	| '(' type_expr ')' { $$ = $2; }
	;

type_args:
	type_expr { $$ = type_list($1); }
	| type_args ',' type_expr { $$ = type_list_append($1, $3); }
	;

%%

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

static int
has_qualifier(char *name)
{
	if(name == nil)
		return 0;
	return strchr(name, '.') != nil;
}

static char*
qualify_name(char *ns, char *name)
{
	char *q;
	int n;

	if(name == nil)
		return nil;
	if(ns == nil || ns[0] == 0 || has_qualifier(name))
		return estrdup(name);
	n = strlen(ns) + strlen(name) + 2;
	q = emalloc(n);
	snprint(q, n, "%s.%s", ns, name);
	return q;
}

static char*
join_member(char *owner, char *member)
{
	char *q;
	int n;

	n = strlen(owner) + strlen(member) + 2;
	q = emalloc(n);
	snprint(q, n, "%s.%s", owner, member);
	return q;
}

static NameList*
name_list(char *name)
{
	NameList *n;

	n = emalloc(sizeof(NameList));
	n->name = estrdup(name);
	return n;
}

static NameList*
name_list_append(NameList *list, char *name)
{
	NameList *n;

	if(list == nil)
		return name_list(name);
	for(n = list; n->next; n = n->next)
		;
	n->next = name_list(name);
	return list;
}

static int
name_list_len(NameList *list)
{
	int n;

	n = 0;
	for(; list; list = list->next)
		n++;
	return n;
}

static int
name_in_list(NameList *list, char *name)
{
	for(; list; list = list->next)
		if(strcmp(list->name, name) == 0)
			return 1;
	return 0;
}

static Field*
field_new(char *kind, Type *type, char *name)
{
	Field *f;

	f = emalloc(sizeof(Field));
	f->kind = estrdup(kind);
	f->type = type;
	f->name = estrdup(name);
	return f;
}

static Field*
field_append(Field *list, Field *field)
{
	Field *f;

	if(list == nil)
		return field;
	for(f = list; f->next; f = f->next)
		;
	f->next = field;
	return list;
}

static Item*
item_append(Item *list, Item *item)
{
	Item *i;

	if(list == nil)
		return item;
	for(i = list; i->next; i = i->next)
		;
	i->next = item;
	return list;
}

static Item*
decl_item(char *kind, char *name, NameList *params, Field *fields)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = IDecl;
	i->declkind = estrdup(kind);
	i->name = estrdup(name);
	i->params = params;
	i->fields = fields;
	return i;
}

static Item*
module_item(char *name, Item *items)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = IModule;
	i->name = estrdup(name);
	i->items = items;
	return i;
}

static Item*
enum_item(char *name, NameList *vals)
{
	Item *i;

	i = decl_item("enum", name, nil, nil);
	i->enumvals = vals;
	return i;
}

static Item*
type_item(Type *type)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = IType;
	i->type = type;
	return i;
}

static Item*
var_item(Type *type, char *name, char *init)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = IVar;
	i->type = type;
	i->name = estrdup(name);
	i->init = estrdup(init);
	return i;
}

static Item*
object_item(Type *type, char *name)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = IObject;
	i->type = type;
	i->name = estrdup(name);
	return i;
}

static Item*
link_item(char *kind, char *from, char *to)
{
	Item *i;

	i = emalloc(sizeof(Item));
	i->kind = ILink;
	i->declkind = estrdup(kind);
	i->name = estrdup(from);
	i->init = estrdup(to);
	return i;
}

static TypeDef*
find_type_def_exact(char *qname)
{
	TypeDef *d;

	for(d = type_defs; d; d = d->next)
		if(strcmp(d->qname, qname) == 0)
			return d;
	return nil;
}

static TypeDef*
resolve_type_def(char *name, char *ns)
{
	TypeDef *d;
	char *q;

	if(name == nil)
		return nil;
	if(has_qualifier(name))
		return find_type_def_exact(name);
	if(ns != nil && ns[0] != 0){
		q = qualify_name(ns, name);
		d = find_type_def_exact(q);
		if(d != nil)
			return d;
	}
	return find_type_def_exact(name);
}

static void
add_type_def(char *ns, char *name, char *kind, NameList *params)
{
	TypeDef *d;
	char *qname;

	qname = qualify_name(ns, name);
	if(find_type_def_exact(qname) != nil){
		fprint(2, "o9type: error: duplicate type '%s'\n", qname);
		errors++;
		return;
	}
	d = emalloc(sizeof(TypeDef));
	d->name = estrdup(name);
	d->qname = qname;
	d->ns = estrdup(ns);
	d->kind = estrdup(kind);
	d->params = params;
	d->arity = name_list_len(params);
	d->next = type_defs;
	type_defs = d;
}

static EnumSym*
find_enum_sym_exact(char *qname)
{
	EnumSym *e;

	for(e = enum_syms; e; e = e->next)
		if(strcmp(e->qname, qname) == 0 || strcmp(e->membername, qname) == 0)
			return e;
	return nil;
}

static EnumSym*
resolve_enum_sym(char *name, char *ns)
{
	EnumSym *e;
	char *q;

	if(name == nil)
		return nil;
	if(has_qualifier(name))
		return find_enum_sym_exact(name);
	if(ns != nil && ns[0] != 0){
		q = qualify_name(ns, name);
		e = find_enum_sym_exact(q);
		if(e != nil)
			return e;
	}
	return find_enum_sym_exact(name);
}

static void
add_enum_sym(char *ns, char *enumname, char *name)
{
	EnumSym *e;
	char *qname, *membername;

	qname = qualify_name(ns, name);
	membername = join_member(enumname, name);
	if(find_enum_sym_exact(qname) != nil){
		fprint(2, "o9type: error: duplicate enum value '%s'\n", qname);
		errors++;
		return;
	}
	e = emalloc(sizeof(EnumSym));
	e->name = estrdup(name);
	e->qname = qname;
	e->membername = membername;
	e->enumname = estrdup(enumname);
	e->next = enum_syms;
	enum_syms = e;
}

static ObjectSym*
find_object_sym_exact(char *qname)
{
	ObjectSym *o;

	for(o = object_syms; o; o = o->next)
		if(strcmp(o->qname, qname) == 0)
			return o;
	return nil;
}

static ObjectSym*
resolve_object_sym(char *name, char *ns)
{
	ObjectSym *o;
	char *q;

	if(name == nil)
		return nil;
	if(has_qualifier(name))
		return find_object_sym_exact(name);
	if(ns != nil && ns[0] != 0){
		q = qualify_name(ns, name);
		o = find_object_sym_exact(q);
		if(o != nil)
			return o;
	}
	return find_object_sym_exact(name);
}

static void
add_object_sym(char *ns, Item *item)
{
	ObjectSym *o;
	char *qname;

	qname = qualify_name(ns, item->name);
	if(find_object_sym_exact(qname) != nil){
		fprint(2, "o9type: error: duplicate object '%s'\n", qname);
		errors++;
		return;
	}
	o = emalloc(sizeof(ObjectSym));
	o->name = estrdup(item->name);
	o->qname = qname;
	o->type = item->type;
	o->next = object_syms;
	object_syms = o;
}

static void
register_builtins(void)
{
	int i;

	for(i = 0; i < type_builtin_count(); i++)
		add_type_def(nil, type_builtin_name(i), "basic", nil);
}

static void
check_param_dups(NameList *params, char *owner)
{
	NameList *a, *b;

	for(a = params; a; a = a->next){
		for(b = a->next; b; b = b->next){
			if(strcmp(a->name, b->name) == 0){
				fprint(2, "o9type: error: duplicate generic parameter '%s' in %s\n", a->name, owner);
				errors++;
			}
		}
	}
}

static void
check_enum_dups(Item *item, char *ns)
{
	NameList *a, *b;
	char *enumname;

	enumname = qualify_name(ns, item->name);

	for(a = item->enumvals; a; a = a->next){
		for(b = a->next; b; b = b->next){
			if(strcmp(a->name, b->name) == 0){
				fprint(2, "o9type: error: duplicate enum value '%s' in %s\n", a->name, item->name);
				errors++;
			}
		}
		add_enum_sym(ns, enumname, a->name);
	}
}

static void
collect_defs(Item *items, char *ns)
{
	Item *i;
	char *childns;

	for(i = items; i; i = i->next){
		if(i->kind == IModule){
			childns = qualify_name(ns, i->name);
			collect_defs(i->items, childns);
			continue;
		}
		if(i->kind != IDecl)
			continue;
		check_param_dups(i->params, i->name);
		add_type_def(ns, i->name, i->declkind, i->params);
	}
}

static void
collect_enum_syms(Item *items, char *ns)
{
	Item *i;
	char *childns;

	for(i = items; i; i = i->next){
		if(i->kind == IModule){
			childns = qualify_name(ns, i->name);
			collect_enum_syms(i->items, childns);
			continue;
		}
		if(i->kind == IDecl && strcmp(i->declkind, "enum") == 0)
			check_enum_dups(i, ns);
	}
}

static void
collect_object_syms(Item *items, char *ns)
{
	Item *i;
	char *childns;

	for(i = items; i; i = i->next){
		if(i->kind == IModule){
			childns = qualify_name(ns, i->name);
			collect_object_syms(i->items, childns);
			continue;
		}
		if(i->kind == IObject)
			add_object_sym(ns, i);
	}
}

static void
resolve_type(Type *type, NameList *params, char *ns)
{
	TypeDef *d;
	TypeList *a;
	int argc;

	if(type == nil)
		return;
	switch(type->kind){
	case TyName:
		if(name_in_list(params, type->name)){
			type->kind = TyParam;
			return;
		}
		d = resolve_type_def(type->name, ns);
		if(d == nil){
			fprint(2, "o9type: error: unknown type '%s'\n", type->name);
			errors++;
		}else{
			type->name = estrdup(d->qname);
		}
		break;
	case TyParam:
		if(!name_in_list(params, type->name)){
			fprint(2, "o9type: error: unknown generic parameter '%s'\n", type->name);
			errors++;
		}
		break;
	case TyApply:
		if(name_in_list(params, type->name)){
			fprint(2, "o9type: error: generic parameter '%s' cannot take type arguments\n", type->name);
			errors++;
		}
		d = resolve_type_def(type->name, ns);
		if(d == nil){
			fprint(2, "o9type: error: unknown generic type '%s'\n", type->name);
			errors++;
		}else{
			type->name = estrdup(d->qname);
			argc = type_list_len(type->args);
			if(d->arity == 0){
				fprint(2, "o9type: error: type '%s' is not generic\n", type->name);
				errors++;
			}else if(argc != d->arity){
				fprint(2, "o9type: error: generic type '%s' expects %d argument(s), got %d\n",
					type->name, d->arity, argc);
				errors++;
			}
		}
		for(a = type->args; a; a = a->next)
			resolve_type(a->type, params, ns);
		break;
	case TyPtr:
	case TyArray:
		resolve_type(type->base, params, ns);
		break;
	}
}

static void
validate_var(Item *i, char *ns)
{
	EnumSym *e;

	resolve_type(i->type, nil, ns);
	if(i->init == nil)
		return;
	e = resolve_enum_sym(i->init, ns);
	if(e == nil){
		fprint(2, "o9type: error: unknown enum value '%s'\n", i->init);
		errors++;
		return;
	}
	if(i->type == nil || i->type->kind != TyName || strcmp(i->type->name, e->enumname) != 0){
		fprint(2, "o9type: error: enum value '%s' has type %s, not %s\n",
			i->init, e->enumname, i->type ? type_render(i->type) : "<nil>");
		errors++;
	}
}

static int
type_is_object_ref(Type *type)
{
	TypeDef *d;

	if(type == nil)
		return 0;
	if(type->kind == TyName || type->kind == TyApply){
		d = resolve_type_def(type->name, nil);
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0))
			return 1;
	}
	return 0;
}

static void
validate_object(Item *i, char *ns)
{
	char *r;

	resolve_type(i->type, nil, ns);
	if(type_is_object_ref(i->type))
		return;
	r = type_render(i->type);
	fprint(2, "o9type: error: object '%s' needs class/interface type, got %s\n",
		i->name, r);
	errors++;
}

static void
validate_link(Item *i, char *ns)
{
	ObjectSym *from, *to;

	from = resolve_object_sym(i->name, ns);
	to = resolve_object_sym(i->init, ns);
	if(from == nil){
		fprint(2, "o9type: error: link source object '%s' is not declared\n", i->name);
		errors++;
	}
	if(to == nil){
		fprint(2, "o9type: error: link target object '%s' is not declared\n", i->init);
		errors++;
	}
}

static void
validate_items(Item *items, char *ns)
{
	Item *i;
	Field *f;
	char *childns;

	for(i = items; i; i = i->next){
		switch(i->kind){
		case IModule:
			childns = qualify_name(ns, i->name);
			validate_items(i->items, childns);
			break;
		case IDecl:
			for(f = i->fields; f; f = f->next)
				resolve_type(f->type, i->params, ns);
			break;
		case IType:
			resolve_type(i->type, nil, ns);
			break;
		case IVar:
			validate_var(i, ns);
			break;
		case IObject:
			validate_object(i, ns);
			break;
		case ILink:
			validate_link(i, ns);
			break;
		}
	}
}

static void
append_client(char *base, char *buf, int n)
{
	snprint(buf, n, "%s_Client*", base);
}

static char*
type_plan9_resolved(Type *type)
{
	TypeDef *d;
	char *p, *c;
	char buf[256];

	if(type == nil)
		return "void";
	if(type->kind == TyName){
		p = type_builtin_plan9(type->name);
		if(p != nil)
			return p;
		d = resolve_type_def(type->name, nil);
		c = type_cname(type);
		if(d != nil && strcmp(d->kind, "enum") == 0)
			return "int";
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0)){
			append_client(c, buf, sizeof buf);
			return estrdup(buf);
		}
		return c;
	}
	if(type->kind == TyParam)
		return "void*";
	if(type->kind == TyPtr){
		p = type_plan9_resolved(type->base);
		snprint(buf, sizeof buf, "%s*", p);
		return estrdup(buf);
	}
	if(type->kind == TyArray)
		return "O9Slice";
	if(type->kind == TyApply){
		d = resolve_type_def(type->name, nil);
		c = type_cname(type);
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0)){
			append_client(c, buf, sizeof buf);
			return estrdup(buf);
		}
		return c;
	}
	return type_plan9(type);
}

static char*
type_abi_resolved(Type *type)
{
	TypeDef *d;
	char *a;

	if(type == nil)
		return "none";
	if(type->kind == TyName){
		a = type_builtin_abi(type->name);
		if(a != nil)
			return a;
		d = resolve_type_def(type->name, nil);
		if(d != nil && strcmp(d->kind, "enum") == 0)
			return "enum";
		if(d != nil && strcmp(d->kind, "struct") == 0)
			return "struct";
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0))
			return "object-ref";
		return "named";
	}
	if(type->kind == TyParam)
		return "param";
	if(type->kind == TyPtr)
		return "pointer";
	if(type->kind == TyArray)
		return "slice";
	if(type->kind == TyApply){
		d = resolve_type_def(type->name, nil);
		if(d != nil && strcmp(d->kind, "struct") == 0)
			return "generic-struct";
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0))
			return "generic-object-ref";
		return "generic";
	}
	return "unknown";
}

static char*
type_fmt_resolved(Type *type)
{
	TypeDef *d;

	if(type != nil && type->kind == TyName){
		if(type_builtin_fmt(type->name) != nil && type_builtin_fmt(type->name)[0] != 0)
			return type_builtin_fmt(type->name);
		d = resolve_type_def(type->name, nil);
		if(d != nil && strcmp(d->kind, "enum") == 0)
			return "%d";
	}
	return "%p";
}

static char*
type_zero_resolved(Type *type)
{
	TypeDef *d;

	if(type != nil && type->kind == TyName){
		if(type_builtin_zero(type->name) != nil && type_builtin_zero(type->name)[0] != 0)
			return type_builtin_zero(type->name);
		d = resolve_type_def(type->name, nil);
		if(d != nil && strcmp(d->kind, "enum") == 0)
			return "0";
		if(d != nil && strcmp(d->kind, "struct") == 0)
			return "{0}";
		if(d != nil && (strcmp(d->kind, "class") == 0 || strcmp(d->kind, "interface") == 0))
			return "nil";
	}
	if(type != nil && type->kind == TyArray)
		return "{0}";
	if(type != nil && type->kind == TyApply){
		d = resolve_type_def(type->name, nil);
		if(d != nil && strcmp(d->kind, "struct") == 0)
			return "{0}";
		return "nil";
	}
	if(type != nil && type->kind == TyPtr)
		return "nil";
	return "0";
}

static void
dump_type_line(char *prefix, Type *type)
{
	char *d, *r, *c, *p, *a, *z, *f;

	d = type_dump(type);
	r = type_render(type);
	c = type_cname(type);
	p = type_plan9_resolved(type);
	a = type_abi_resolved(type);
	z = type_zero_resolved(type);
	f = type_fmt_resolved(type);
	print("%s%s render=%s cname=%s plan9=%s abi=%s zero=%s fmt=%s\n",
		prefix, d, r, c, p, a, z, f);
}

static void
dump_params(NameList *params)
{
	NameList *n;
	int first;

	if(params == nil)
		return;
	print("<");
	first = 1;
	for(n = params; n; n = n->next){
		if(!first)
			print(",");
		print("%s", n->name);
		first = 0;
	}
	print(">");
}

static void
dump_items(Item *items, char *ns)
{
	Item *i;
	Field *f;
	NameList *n;
	ObjectSym *from, *to;
	char *qname, *childns;
	char prefix[256];

	for(i = items; i; i = i->next){
		switch(i->kind){
		case IModule:
			childns = qualify_name(ns, i->name);
			print("module %s\n", childns);
			dump_items(i->items, childns);
			break;
		case IDecl:
			qname = qualify_name(ns, i->name);
			print("decl %s %s", i->declkind, qname);
			dump_params(i->params);
			print("\n");
			for(f = i->fields; f; f = f->next){
				snprint(prefix, sizeof prefix, "  %s %s: ", f->kind, f->name);
				dump_type_line(prefix, f->type);
			}
			for(n = i->enumvals; n; n = n->next)
				print("  enum %s.%s\n", qname, n->name);
			break;
		case IType:
			dump_type_line("type ", i->type);
			break;
		case IVar:
			snprint(prefix, sizeof prefix, "var %s: ", i->name);
			dump_type_line(prefix, i->type);
			if(i->init != nil){
				EnumSym *e = resolve_enum_sym(i->init, ns);
				print("  init %s\n", e->membername);
			}
			break;
		case IObject:
			qname = qualify_name(ns, i->name);
			snprint(prefix, sizeof prefix, "object %s: ", qname);
			dump_type_line(prefix, i->type);
			break;
		case ILink:
			from = resolve_object_sym(i->name, ns);
			to = resolve_object_sym(i->init, ns);
			print("link %s %s -> %s\n",
				i->declkind,
				from != nil ? from->qname : i->name,
				to != nil ? to->qname : i->init);
			break;
		}
	}
}

static int
lex_getc(void)
{
	int c;

	if(input_pos >= input_len)
		return -1;
	c = input_buf[input_pos++];
	if(c == '\n')
		line_no++;
	return c;
}

static void
lex_ungetc(int c)
{
	if(c < 0 || input_pos <= 0)
		return;
	input_pos--;
	if(c == '\n')
		line_no--;
}

static int
is_basic_type(char *s)
{
	return strcmp(s, "bool") == 0
		|| strcmp(s, "int64") == 0
		|| strcmp(s, "uint64") == 0
		|| strcmp(s, "int32") == 0
		|| strcmp(s, "uint32") == 0
		|| strcmp(s, "int16") == 0
		|| strcmp(s, "uint16") == 0
		|| strcmp(s, "int8") == 0
		|| strcmp(s, "uint8") == 0
		|| strcmp(s, "void") == 0
		|| strcmp(s, "string") == 0
		|| strcmp(s, "int") == 0
		|| strcmp(s, "char") == 0
		|| strcmp(s, "vlong") == 0
		|| strcmp(s, "uvlong") == 0
		|| strcmp(s, "ulong") == 0
		|| strcmp(s, "ushort") == 0
		|| strcmp(s, "uchar") == 0;
}

static int
yylex(void)
{
	int c, nc;
	char buf[128];
	int i;

	for(;;){
		c = lex_getc();
		if(c < 0)
			return 0;
		if(c == ' ' || c == '\t' || c == '\r' || c == '\n')
			continue;
		if(c == '/'){
			nc = lex_getc();
			if(nc == '/'){
				while((c = lex_getc()) >= 0 && c != '\n')
					;
				continue;
			}
			if(nc == '*'){
				for(;;){
					c = lex_getc();
					if(c < 0)
						return 0;
					if(c == '*'){
						nc = lex_getc();
						if(nc == '/')
							break;
						lex_ungetc(nc);
					}
				}
				continue;
			}
			lex_ungetc(nc);
			return c;
		}
		break;
	}

	if(isalpha(c) || c == '_'){
		i = 0;
		buf[i++] = c;
		while((c = lex_getc()) >= 0 && (isalnum(c) || c == '_')){
			if(i < sizeof(buf)-1)
				buf[i++] = c;
		}
		lex_ungetc(c);
		buf[i] = 0;

		if(strcmp(buf, "class") == 0)
			return TCLASS;
		if(strcmp(buf, "struct") == 0)
			return TSTRUCT;
		if(strcmp(buf, "interface") == 0)
			return TINTERFACE;
		if(strcmp(buf, "enum") == 0)
			return TENUM;
		if(strcmp(buf, "module") == 0)
			return TMODULE;
		if(strcmp(buf, "prop") == 0)
			return TPROP;
		if(strcmp(buf, "state") == 0)
			return TSTATE;
		if(strcmp(buf, "atomic") == 0)
			return TATOMIC;
		if(strcmp(buf, "object") == 0)
			return TOBJECT;
		if(strcmp(buf, "link") == 0)
			return TLINK;
		if(strcmp(buf, "ref") == 0)
			return TREF;
		if(strcmp(buf, "replica") == 0)
			return TREPLICA;

		yylval.s = estrdup(buf);
		if(is_basic_type(buf))
			return TTYPE;
		return TIDENT;
	}

	return c;
}

static void
yyerror(char *s)
{
	fprint(2, "o9type: line %d: %s\n", line_no, s);
	errors++;
}

int
main(int argc, char **argv)
{
	long n, total, cap;

	USED(argc);
	USED(argv);

	total = 0;
	cap = 8192;
	input_buf = emalloc(cap);
	while((n = read(0, input_buf + total, cap - total)) > 0){
		total += n;
		if(total + 1024 >= cap){
			cap *= 2;
			input_buf = realloc(input_buf, cap);
			if(input_buf == nil)
				sysfatal("realloc");
		}
	}
	input_len = total;

	if(yyparse() != 0)
		errors++;
	register_builtins();
	collect_defs(program_items, nil);
	collect_enum_syms(program_items, nil);
	collect_object_syms(program_items, nil);
	validate_items(program_items, nil);
	if(errors != 0)
		exits("errors");

	dump_items(program_items, nil);
	exits(nil);
	return 0;
}
