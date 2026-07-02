%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>
#include "o9_type.h"

typedef struct Node Node;

enum {
    NClass,
    NProp,
    NState,
    NAtomic,
    NStream,
    NSecret,
    NCap,
    NInherit,
    NMethod,
    NDestructor,
    NIdent,
    NType,
    NChanSend,
    NChanRecv,
    NChanTry,
    NAssign,
    NReturn,
    NIntLit,
    NStringLit,
    NCharLit,
    NBoolLit,
    NAdd,
    NSub,
    NMul,
    NDiv,
    NMod,
    NEq,
    NNe,
    NLt,
    NLe,
    NGt,
    NGe,
    NAnd,
    NOr,
    NBitAnd,
    NBitOr,
    NBitXor,
    NLshift,
    NRshift,
    NNot,
    NBitNot,
    NNeg,
    NIf,
    NIfElse,
    NElse,
    NElseIf,
    NWhile,
    NLocalVar,
    NMsgSend,
    NPropRead,
    NFuncCall,
    NFor,
    NArrayGet,
    NArraySet,
    NInterface,
    NStruct,
    NEnum,
    NEnumVal,
    NImport,
    NObject,
    NLink,
    NModule,
    NTypeParam
};

struct Node {
    int type;
    char *name;
    char *typename;
    char *qname;
    char *cname;
    Type *typeinfo;
    Node *params;
    Node *left;
    Node *right;
    Node *next;
};

typedef struct ClassDef ClassDef;
typedef struct EnumSym EnumSym;
typedef struct ObjectSym ObjectSym;
struct ClassDef {
    char *name;
    Node *node;
    ClassDef *next;
};
ClassDef *classes;
static int semantic_errors;
static int in_prescan;              /* 1 during prescan phase, 0 during parse */

struct EnumSym {
    char *qname;
    char *membername;
    char *enumtype;
    char *cname;
    int value;
    EnumSym *next;
};
EnumSym *enum_syms;

struct ObjectSym {
    char *qname;
    char *cname;
    char *typename;
    Node *node;
    ObjectSym *next;
};
ObjectSym *object_syms;

void
add_class(char *name, Node *n)
{
    ClassDef *c;
    for(c = classes; c; c = c->next){
        if(strcmp(c->name, name) == 0){
            c->node = n;
            return;
        }
    }
    c = malloc(sizeof(ClassDef));
    c->name = strdup(name);
    c->node = n;
    c->next = classes;
    classes = c;
}

Node*
find_class(char *name)
{
    ClassDef *c;
    for(c = classes; c; c = c->next)
        if(strcmp(c->name, name) == 0) return c->node;
    return nil;
}

Node* mk(int type, char *name, char *typename, Node *l, Node *r);
Node* append_node(Node *list, Node *node);
char* map_type(char *t);
char* get_sym_type(Node *c, char *name);
char* get_sym_decl_type(Node *c, char *name);
char* get_method_type(Node *c, char *name);
char* get_expr_type(Node *e);
static Type* typeinfo_from_legacy(char *t);
static Type* get_typeinfo_sym(char *name);
static void add_type_sym_typed(char *name, char *typename, Type *typeinfo);
static char* type_slice(char *s, int n);
static char* qualify_type_name(char *name);
static char* qualify_source_name(char *module, char *name);
static char* mangle_source_name(char *name);
static int is_known_type_name(char *name);
static Type* type_from_name(char *name);
static Node* type_node(Type *type);
static Node* mk_typed(int type, char *name, Node *tn, Node *l, Node *r);
static void set_node_names(Node *n, char *qname, char *cname);
static char* legacy_type_name(Type *type);
static void push_module(char *name);
static void pop_module(void);
static void push_type_params(Node *params);
static void pop_type_params(void);
static void add_enum_sym(char *enumsrc, char *enumtype, char *name, int value);
static EnumSym* resolve_enum_sym(char *name);
static Node* enum_expr_or_ident(Node *n);
static void add_object_sym(Node *n);
static Node* object_ref(Node *n);
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);
ulong o9_hash(char *str);
void  add_var_class(char *varname, char *classname);
int   is_primitive(char *t);
static void scan_file(char *path);

void add_type_sym(char *name, char *typename);
char* get_type_sym(char *name);
void clear_type_syms(void);
int is_subclass(char *sub, char *parent);
int is_type_compatible(char *target, char *actual);

typedef struct TypeSym TypeSym;
struct TypeSym {
    char *name;
    char *typename;
    Type *typeinfo;
    TypeSym *next;
};
TypeSym *type_syms;

static void add_type_sym_typed(char *name, char *typename, Type *typeinfo) {
    TypeSym *s = malloc(sizeof(TypeSym));
    if(s == nil)
        sysfatal("malloc: add_type_sym");
    s->name = strdup(name);
    s->typename = strdup(typename);
    s->typeinfo = typeinfo;
    s->next = type_syms;
    type_syms = s;
}

void add_type_sym(char *name, char *typename) {
    add_type_sym_typed(name, typename, typeinfo_from_legacy(typename));
}

char* get_type_sym(char *name) {
    TypeSym *s;
    for(s = type_syms; s; s = s->next) if(strcmp(s->name, name) == 0) return s->typename;
    return nil;
}

static Type* get_typeinfo_sym(char *name) {
    TypeSym *s;
    for(s = type_syms; s; s = s->next) if(strcmp(s->name, name) == 0) return s->typeinfo;
    return nil;
}

void clear_type_syms(void) {
    TypeSym *s, *next;
    for(s = type_syms; s; s = next){ next = s->next; free(s->name); free(s->typename); free(s); }
    type_syms = nil;
}

static TypeSym*
mark_type_syms(void)
{
    return type_syms;
}

static void
restore_type_syms(TypeSym *mark)
{
    TypeSym *s;

    while(type_syms != mark){
        if(type_syms == nil)
            break;
        s = type_syms;
        type_syms = s->next;
        free(s->name);
        free(s->typename);
        free(s);
    }
}

int is_subclass(char *sub, char *parent) {
    Node *c, *m;
    if(sub == nil || parent == nil) return 0;
    if(strcmp(sub, parent) == 0) return 1;
    c = find_class(sub); if(c == nil) return 0;
    for(m = c->left; m; m = m->next) if(m->type == NInherit) { if(strcmp(m->name, parent) == 0) return 1; if(is_subclass(m->name, parent)) return 1; }
    return 0;
}

int is_type_compatible(char *target, char *actual) {
    if(target == nil || actual == nil) return 0;
    if(strcmp(target, actual) == 0) return 1;
    if(strcmp(target, "vlong") == 0 && (strcmp(actual, "int64") == 0 || strncmp(actual, "List:", 5) == 0)) return 1;
    if(is_subclass(actual, target)) return 1;
    return 0;
}

char* get_method_type(Node *c, char *name) {
    Node *m;
    if(c == nil || name == nil) return nil;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && m->name && strcmp(m->name, name) == 0) return m->typename;
        if(m->type == NInherit){ Node *p = find_class(m->name); if(p){ char *t = get_method_type(p, name); if(t) return t; } }
    }
    return nil;
}

char* get_expr_type(Node *e) {
    if(e == nil) return "void";
    if(e->type == NEnumVal && e->typename != nil) return e->typename;
    if(e->typeinfo != nil) return legacy_type_name(e->typeinfo);
    switch(e->type){
    case NIntLit: return "int64";
    case NStringLit: return "string";
    case NBoolLit: return "bool";
    case NClass: return e->name;
    case NEnumVal: return e->typename;
    case NIdent: { char *t = get_type_sym(e->name); if(t) return t; return "vlong"; }
    case NPropRead: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_sym_type(c, e->name); } return "vlong";
    case NMsgSend: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_method_type(c, e->name); } return "vlong";
    case NArrayGet: { char *lt = get_expr_type(e->left); if(strncmp(lt, "List:", 5) == 0) return lt + 5; if(strncmp(lt, "Dict:", 5) == 0) return strrchr(lt, ':') + 1; return "vlong"; }
    case NAdd: case NSub: case NMul: case NDiv: case NMod: return "int64";
    default: return "vlong";
    }
}

Node *ast_root;

static char *module_stack[32];
static int module_depth;
static char *current_module;
static Node *type_param_stack[32];
static int type_param_depth;

static char*
e_strdup(char *s)
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
node_list_len(Node *list)
{
    int n;

    n = 0;
    for(; list; list = list->next)
        n++;
    return n;
}

static int
type_param_in_list(Node *list, char *name)
{
    for(; list; list = list->next)
        if(list->name != nil && strcmp(list->name, name) == 0)
            return 1;
    return 0;
}

static int
is_type_param_name(char *name)
{
    int i;

    if(name == nil)
        return 0;
    for(i = type_param_depth - 1; i >= 0; i--)
        if(type_param_in_list(type_param_stack[i], name))
            return 1;
    return 0;
}

static void
push_type_params(Node *params)
{
    if(type_param_depth >= nelem(type_param_stack))
        sysfatal("type parameter nesting too deep");
    type_param_stack[type_param_depth++] = params;
}

static void
pop_type_params(void)
{
    if(type_param_depth <= 0)
        return;
    type_param_depth--;
}

static void
set_node_names(Node *n, char *qname, char *cname)
{
    if(n == nil)
        return;
    if(qname != nil)
        n->qname = e_strdup(qname);
    if(cname != nil)
        n->cname = e_strdup(cname);
}

static int
name_has_module(char *name)
{
    return name != nil && strchr(name, '.') != nil;
}

static char*
join_module_name(char *left, char *right)
{
    char *r;
    int n;

    if(left == nil || left[0] == 0)
        return e_strdup(right);
    if(right == nil || right[0] == 0)
        return e_strdup(left);
    n = strlen(left) + strlen(right) + 2;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: join_module_name");
    snprint(r, n, "%s.%s", left, right);
    return r;
}

static char*
qualify_source_name(char *module, char *name)
{
    if(name == nil)
        return nil;
    if(module == nil || module[0] == 0 || name_has_module(name))
        return e_strdup(name);
    return join_module_name(module, name);
}

static char*
mangle_source_name(char *name)
{
    Type *t;

    if(name == nil)
        return nil;
    t = type_name(name);
    return type_cname(t);
}

static int
is_known_type_name(char *name)
{
    char *q, *c;

    if(name == nil)
        return 0;
    if(type_is_builtin_name(name))
        return 1;
    if(is_type_param_name(name))
        return 1;
    q = qualify_source_name(current_module, name);
    c = mangle_source_name(q);
    if(find_class(c) != nil)
        return 1;
    if(name_has_module(name))
        return 0;
    c = mangle_source_name(name);
    return find_class(c) != nil;
}

static char*
append_str(char *left, char *right)
{
    char *r;
    int n;

    if(left == nil)
        left = "";
    if(right == nil)
        right = "";
    n = strlen(left) + strlen(right) + 1;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: append_str");
    snprint(r, n, "%s%s", left, right);
    return r;
}

static char*
legacy_type_name(Type *type)
{
    char *base, *args, *r;
    int n;

    if(type == nil)
        return nil;
    switch(type->kind){
    case TyName:
    case TyParam:
        return type_cname(type);
    case TyApply:
        if(strcmp(type->name, "List") == 0 && type_list_len(type->args) == 1){
            args = legacy_type_name(type->args->type);
            n = strlen(args) + 6;
            r = malloc(n);
            if(r == nil)
                sysfatal("malloc: legacy List");
            snprint(r, n, "List:%s", args);
            return r;
        }
        if(strcmp(type->name, "Dict") == 0 && type_list_len(type->args) == 2){
            char *k, *v;
            k = legacy_type_name(type->args->type);
            v = legacy_type_name(type->args->next->type);
            n = strlen(k) + strlen(v) + 7;
            r = malloc(n);
            if(r == nil)
                sysfatal("malloc: legacy Dict");
            snprint(r, n, "Dict:%s:%s", k, v);
            return r;
        }
        return type_cname(type);
    case TyPtr:
        base = legacy_type_name(type->base);
        r = append_str(base, "*");
        return r;
    case TyArray:
        base = legacy_type_name(type->base);
        r = append_str(base, "[]");
        return r;
    }
    return type_render(type);
}

static Type*
type_from_name(char *name)
{
    char *q;

    if(name == nil)
        return nil;
    if(type_is_builtin_name(name))
        return type_name(name);
    if(is_type_param_name(name))
        return type_param(name);
    q = qualify_source_name(current_module, name);
    return type_name(q);
}

static Node*
type_node(Type *type)
{
    Node *n;
    char *legacy, *rendered, *cname;

    legacy = legacy_type_name(type);
    rendered = type_render(type);
    cname = type_cname(type);
    n = mk(NType, legacy, legacy, nil, nil);
    n->typeinfo = type;
    set_node_names(n, rendered, cname);
    return n;
}

static Node*
mk_typed(int type, char *name, Node *tn, Node *l, Node *r)
{
    Node *n;

    n = mk(type, name, tn != nil ? tn->name : nil, l, r);
    if(tn != nil)
        n->typeinfo = tn->typeinfo;
    return n;
}

static Node*
object_ref(Node *n)
{
    Node *r;
    char *q, *c;

    if(n == nil || n->name == nil)
        return n;
    q = qualify_source_name(current_module, n->name);
    c = mangle_source_name(q);
    r = mk(NIdent, c, nil, nil, nil);
    set_node_names(r, q, c);
    return r;
}

static char*
enum_const_name(char *enumtype, char *name)
{
    char *r;
    int n;

    n = strlen(enumtype) + strlen(name) + 3;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: enum_const_name");
    snprint(r, n, "%s__%s", enumtype, name);
    return r;
}

static EnumSym*
find_enum_sym_exact(char *name)
{
    EnumSym *e;

    for(e = enum_syms; e; e = e->next)
        if(strcmp(e->qname, name) == 0 || strcmp(e->membername, name) == 0)
            return e;
    return nil;
}

static EnumSym*
resolve_enum_sym(char *name)
{
    EnumSym *e;
    char *q;

    if(name == nil)
        return nil;
    e = find_enum_sym_exact(name);
    if(e != nil)
        return e;
    if(current_module != nil && current_module[0] != 0){
        q = qualify_source_name(current_module, name);
        e = find_enum_sym_exact(q);
        if(e != nil)
            return e;
    }
    return nil;
}

static void
add_enum_sym(char *enumsrc, char *enumtype, char *name, int value)
{
    EnumSym *e;
    char *module, *dot;
    char qbuf[256], mbuf[256];

    if(enumsrc == nil || enumtype == nil || name == nil)
        return;
    module = nil;
    dot = strrchr(enumsrc, '.');
    if(dot != nil)
        module = type_slice(enumsrc, dot - enumsrc);
    if(module != nil)
        snprint(qbuf, sizeof qbuf, "%s.%s", module, name);
    else
        snprint(qbuf, sizeof qbuf, "%s", name);
    snprint(mbuf, sizeof mbuf, "%s.%s", enumsrc, name);
    e = find_enum_sym_exact(qbuf);
    if(e == nil)
        e = find_enum_sym_exact(mbuf);
    if(e != nil){
        if(strcmp(e->enumtype, enumtype) != 0 && !in_prescan){
            fprint(2, "o9c: error: duplicate enum value '%s'\n", qbuf);
            semantic_errors++;
        }
        return;
    }
    e = malloc(sizeof(EnumSym));
    if(e == nil)
        sysfatal("malloc: add_enum_sym");
    memset(e, 0, sizeof(EnumSym));
    e->qname = strdup(qbuf);
    e->membername = strdup(mbuf);
    e->enumtype = strdup(enumtype);
    e->cname = enum_const_name(enumtype, name);
    e->value = value;
    e->next = enum_syms;
    enum_syms = e;
}

static void
register_enum_values(char *enumsrc, char *enumtype, Node *vals)
{
    Node *v, *w;
    int value;

    for(v = vals; v; v = v->next){
        for(w = v->next; w; w = w->next){
            if(strcmp(v->name, w->name) == 0){
                fprint(2, "o9c: error: duplicate enum value '%s' in %s\n", v->name, enumtype);
                semantic_errors++;
            }
        }
    }
    value = 0;
    for(v = vals; v; v = v->next){
        add_enum_sym(enumsrc, enumtype, v->name, value);
        if(v->typename == nil)
            v->typename = enum_const_name(enumtype, v->name);
        value++;
    }
}

static Node*
enum_expr_or_ident(Node *n)
{
    EnumSym *e;

    if(n == nil || n->name == nil)
        return n;
    e = resolve_enum_sym(n->name);
    if(e == nil)
        return n;
    return mk(NEnumVal, e->cname, e->enumtype, nil, nil);
}

static ObjectSym*
find_object_sym_exact(char *qname)
{
    ObjectSym *o;

    for(o = object_syms; o; o = o->next)
        if(strcmp(o->qname, qname) == 0 || strcmp(o->cname, qname) == 0)
            return o;
    return nil;
}

static ObjectSym*
resolve_object_sym(char *name)
{
    ObjectSym *o;
    char *q;

    if(name == nil)
        return nil;
    o = find_object_sym_exact(name);
    if(o != nil)
        return o;
    if(current_module != nil && current_module[0] != 0){
        q = qualify_source_name(current_module, name);
        o = find_object_sym_exact(q);
        if(o != nil)
            return o;
    }
    return nil;
}

static void
add_object_sym(Node *n)
{
    ObjectSym *o;

    if(n == nil || n->qname == nil)
        return;
    o = find_object_sym_exact(n->qname);
    if(o != nil){
        if(!in_prescan){
            fprint(2, "o9c: error: duplicate object '%s'\n", n->qname);
            semantic_errors++;
        }
        return;
    }
    o = malloc(sizeof(ObjectSym));
    if(o == nil)
        sysfatal("malloc: add_object_sym");
    memset(o, 0, sizeof(ObjectSym));
    o->qname = e_strdup(n->qname);
    o->cname = e_strdup(n->cname != nil ? n->cname : n->name);
    o->typename = e_strdup(n->typename);
    o->node = n;
    o->next = object_syms;
    object_syms = o;
}

static char*
qualify_type_name(char *name)
{
    char *q, *c;

    q = qualify_source_name(current_module, name);
    c = mangle_source_name(q);
    return c;
}

static void
push_module(char *name)
{
    char *q;

    if(module_depth >= nelem(module_stack))
        sysfatal("module nesting too deep");
    q = qualify_source_name(current_module, name);
    module_stack[module_depth++] = current_module;
    current_module = q;
}

static void
pop_module(void)
{
    if(module_depth <= 0)
        return;
    current_module = module_stack[--module_depth];
}

char*
map_type(char *t)
{
    int len;
    Node *n;
    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
    if(strncmp(t, "List:", 5) == 0) return "O9Slice";
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0) return "char*";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "uint64") == 0) return "uvlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "uint32") == 0) return "ulong";
    if(strcmp(t, "int16") == 0) return "short";
    if(strcmp(t, "uint16") == 0) return "ushort";
    if(strcmp(t, "int8") == 0) return "char";
    if(strcmp(t, "uint8") == 0) return "uchar";
    if(strcmp(t, "bool") == 0) return "int";
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";

    n = find_class(t);
    if(n != nil && n->type == NEnum) return "int";
    if(n != nil && n->type == NStruct) return t;

    return t;
}

char*
c_type_fmt(char *t)
{
    if(strcmp(t, "vlong") == 0) return "%lld";
    if(strcmp(t, "uvlong") == 0) return "%llud";
    if(strcmp(t, "long") == 0) return "%ld";
    if(strcmp(t, "ulong") == 0) return "%lud";
    if(strcmp(t, "int") == 0) return "%d";
    if(strcmp(t, "uint") == 0) return "%ud";
    if(strcmp(t, "short") == 0) return "%d";
    if(strcmp(t, "ushort") == 0) return "%ud";
    if(strcmp(t, "char") == 0) return "%d";
    if(strcmp(t, "uchar") == 0) return "%ud";
    if(strcmp(t, "char*") == 0) return "%s";
    return "%lld"; /* fallback */
}

char*
type_cast(char *t)
{
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    if(find_class(t) && find_class(t)->type == NStruct) return "";
    return "vlong"; /* fallback */
}

int
is_primitive(char *t)
{
    if(t == nil) return 1;
    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;
    if(strcmp(t, "int64") == 0) return 1;
    if(strcmp(t, "uint64") == 0) return 1;
    if(strcmp(t, "int32") == 0) return 1;
    if(strcmp(t, "uint32") == 0) return 1;
    if(strcmp(t, "int16") == 0) return 1;
    if(strcmp(t, "uint16") == 0) return 1;
    if(strcmp(t, "int8") == 0) return 1;
    if(strcmp(t, "uint8") == 0) return 1;
    if(strcmp(t, "bool") == 0) return 1;
    if(strcmp(t, "string") == 0) return 1;
    if(strcmp(t, "int") == 0) return 1;
    if(strcmp(t, "char") == 0) return 1;
    if(strcmp(t, "vlong") == 0) return 1;
    if(strcmp(t, "uvlong") == 0) return 1;
    if(strcmp(t, "ulong") == 0) return 1;
    if(strcmp(t, "ushort") == 0) return 1;
    if(strcmp(t, "uchar") == 0) return 1;
    if(strcmp(t, "void") == 0) return 1;
    if(find_class(t) && find_class(t)->type == NEnum) return 1;
    if(find_class(t) && find_class(t)->type == NStruct) return 1;
    return 0;
}

char*
get_sym_type(Node *c, char *name)
{
    Node *m;
    if(c == nil || name == nil) return "vlong";
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            Node *p = find_class(m->name);
            if(p){
                char *t = get_sym_type(p, name);
                if(t && strcmp(t, "vlong") != 0) return t;
            }
        }
        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0){
            return map_type(m->typename);
        }
    }
    return "vlong";
}

char*
get_sym_decl_type(Node *c, char *name)
{
    Node *m;

    if(c == nil || name == nil)
        return nil;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            Node *p = find_class(m->name);
            char *t = get_sym_decl_type(p, name);
            if(t != nil)
                return t;
        }
        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0)
            return m->typename;
    }
    return nil;
}

int
is_enum_type(char *t)
{
    Node *n;

    if(t == nil)
        return 0;
    n = find_class(t);
    return n != nil && n->type == NEnum;
}

int
is_class_type(char *t)
{
    Node *n;
    if(t == nil) return 0;
    n = find_class(t);
    return n != nil && (n->type == NClass || n->type == NInterface);
}

char*
storage_type(char *t)
{
    char *s;
    if(is_class_type(t)){
        s = malloc(strlen(t) + 8);
        if(s == nil) sysfatal("malloc: storage_type");
        snprint(s, strlen(t) + 8, "%s_Client", t);
        return s;
    }
    return map_type(t);
}

static char*
type_slice(char *s, int n)
{
    char *r;

    r = malloc(n + 1);
    if(r == nil)
        sysfatal("malloc: type_slice");
    memmove(r, s, n);
    r[n] = 0;
    return r;
}

static Type*
typeinfo_from_legacy(char *t)
{
    Type *base;
    TypeList *args;
    char *left, *sep;
    int len;

    if(t == nil)
        return nil;
    if(strncmp(t, "List:", 5) == 0)
        return type_apply("List", type_list(typeinfo_from_legacy(t + 5)));
    if(strncmp(t, "Dict:", 5) == 0){
        sep = strchr(t + 5, ':');
        if(sep != nil){
            left = type_slice(t + 5, sep - (t + 5));
            args = type_list(typeinfo_from_legacy(left));
            args = type_list_append(args, typeinfo_from_legacy(sep + 1));
            free(left);
            return type_apply("Dict", args);
        }
    }
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0){
        left = type_slice(t, len - 2);
        base = typeinfo_from_legacy(left);
        free(left);
        return type_array(base);
    }
    if(len > 1 && t[len - 1] == '*'){
        left = type_slice(t, len - 1);
        base = typeinfo_from_legacy(left);
        free(left);
        return type_ptr(base);
    }
    return type_name(t);
}
%}

%union {
    Node *node;
    char *name;
    Type *type;
    TypeList *types;
}

%token <node> TIDENT TTYPE TQIDENT TTYPEIDENT TENUMIDENT
%token <name> TINTLIT TSTRINGLIT TCHARLIT
%token TCLASS TINTERFACE TSTRUCT TENUM TMODULE TIMPORT TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TLIST TNIL
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TOBJECT TLINK TREF TREPLICA TTRUE TFALSE TARROW
%token TEQ TADD TSUB TCHANSEND TCHANRECV TCHANTRY TEQEQ TNEQ TLE TGE
%token TAND TOR TLSHIFT TRSHIFT TFORSEMI

%left TEQ
%left TCHANSEND TCHANTRY
%right TCHANRECV
%left TOR
%left TAND
%left '|'
%left '^'
%left '&'
%left TEQEQ TNEQ
%left '<' '>' TLE TGE
%left TLSHIFT TRSHIFT
%left TADD TSUB
%left '*' '/' '%'
%right '!' '~' UMINUS
%left '.' '['
 
%type <node> program top_levels top_level class_decl class_head interface_decl interface_head struct_decl struct_head enum_decl enum_vals enum_val module_decl module_head import_decl object_decl link_decl member_list member var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename name_ref type_name_ref decl_name generic_name enum_name param_list param call_args call_arg func_top_level for_init for_cond for_step else_clause generic_opt generic_names link_kind
%type <type> type_expr type_primary
%type <types> type_args type_args_opt

%start program

%%

typename:
    type_expr { $$ = type_node($1); }
    ;

name_ref:
    TIDENT { $$ = $1; }
    | TQIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TENUMIDENT { $$ = $1; }
    ;

type_name_ref:
    TTYPEIDENT { $$ = $1; }
    ;

decl_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

generic_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

enum_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TENUMIDENT { $$ = $1; }
    ;

type_expr:
    type_primary { $$ = $1; }
    | type_expr '*' { $$ = type_ptr($1); }
    | type_expr '[' ']' { $$ = type_array($1); }
    ;

type_primary:
    type_name_ref type_args_opt
    {
        Type *base;

        base = type_from_name($1->name);
        if($2 != nil)
            $$ = type_apply(base->name, $2);
        else
            $$ = base;
    }
    | TTYPE { $$ = type_name($1->name); }
    | TLIST '<' type_args '>' { $$ = type_apply("List", $3); }
    | TDICT '<' type_args '>' { $$ = type_apply("Dict", $3); }
    | '(' type_expr ')' { $$ = $2; }
    ;

type_args_opt:
    /* empty */ { $$ = nil; }
    | '<' type_args '>' { $$ = $2; }
    ;

type_args:
    type_expr { $$ = type_list($1); }
    | type_args ',' type_expr { $$ = type_list_append($1, $3); }
    ;

program:
    /* empty */ { ast_root = nil; }
    | top_levels { ast_root = $1; }
    ;

top_levels:
    top_level { $$ = $1; }
    | top_levels top_level { 
        $$ = append_node($1, $2);
    }
    ;

top_level:
    class_decl
    | interface_decl
    | struct_decl
    | enum_decl
    | module_decl
    | import_decl
    | object_decl
    | link_decl
    | func_top_level
    ;

module_head:
    TMODULE name_ref '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        push_module($2->name);
        $$ = mk(NModule, name, nil, nil, nil);
        set_node_names($$, source, name);
    }
    ;

module_decl:
    module_head top_levels '}'
    {
        pop_module();
        $$ = $1;
        $$->left = $2;
    }
    | module_head '}'
    {
        pop_module();
        $$ = $1;
    }
    ;

import_decl:
    TIMPORT TSTRINGLIT ';'
    {
        $$ = mk(NImport, $2, nil, nil, nil);
    }
    ;

object_decl:
    TOBJECT typename TIDENT ';'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $3->name);
        name = mangle_source_name(source);
        $$ = mk_typed(NObject, name, $2, nil, nil);
        set_node_names($$, source, name);
        add_object_sym($$);
    }
    ;

link_kind:
    TREF { $$ = mk(NIdent, "ref", nil, nil, nil); }
    | TREPLICA { $$ = mk(NIdent, "replica", nil, nil, nil); }
    ;

link_decl:
    TLINK link_kind name_ref TCHANSEND name_ref ';'
    {
        Node *from, *to;

        from = object_ref($3);
        to = object_ref($5);
        $$ = mk(NLink, from->name, $2->name, from, to);
        set_node_names($$, from->qname, from->cname);
    }
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $6, nil);
    }
    ;

class_head:
    TCLASS decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        $$ = mk(NClass, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $3;
        push_type_params($3);
    }
    ;

class_decl:
    class_head member_list '}'
    {
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

interface_head:
    TINTERFACE decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        $$ = mk(NInterface, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $3;
        push_type_params($3);
    }
    ;

interface_decl:
    interface_head member_list '}'
    {
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

struct_head:
    TSTRUCT decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        $$ = mk(NStruct, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $3;
        push_type_params($3);
    }
    ;

struct_decl:
    struct_head member_list '}'
    {
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

generic_opt:
    /* empty */ { $$ = nil; }
    | '<' generic_names '>' { $$ = $2; }
    ;

generic_names:
    generic_name { $$ = mk(NTypeParam, $1->name, nil, nil, nil); }
    | generic_names ',' generic_name { $$ = append_node($1, mk(NTypeParam, $3->name, nil, nil, nil)); }
    ;

enum_decl:
    TENUM decl_name '{' enum_vals '}'
    {
        char *source = qualify_source_name(current_module, $2->name);
        char *name = qualify_type_name($2->name);
        $$ = mk(NEnum, name, nil, $4, nil);
        set_node_names($$, source, name);
        add_class(name, $$);
        register_enum_values(source, name, $4);
    }
    | TENUM decl_name '{' enum_vals ',' '}'
    {
        char *source = qualify_source_name(current_module, $2->name);
        char *name = qualify_type_name($2->name);
        $$ = mk(NEnum, name, nil, $4, nil);
        set_node_names($$, source, name);
        add_class(name, $$);
        register_enum_values(source, name, $4);
    }
    ;

enum_vals:
    enum_val { $$ = $1; }
    | enum_vals ',' enum_val { $$ = append_node($1, $3); }
    ;

enum_val:
    enum_name { $$ = mk(NEnumVal, $1->name, nil, nil, nil); }
    ;

member_list:
    /* empty */ { $$ = nil; }
    | member_list member { 
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

member:
    var_decl
    | func_decl
    | method_decl
    | state_decl
    | prop_decl
    | atomic_decl
    | stream_decl
    | secret_decl
    | cap_decl
    | inherit_decl
    | destructor_decl
    ;

state_decl:
    TSTATE typename TIDENT ';'
    {
        $$ = mk_typed(NState, $3->name, $2, nil, nil);
    }
    ;

prop_decl:
    TPROP typename TIDENT ';'
    {
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
    }
    ;

atomic_decl:
    TATOMIC typename TIDENT ';'
    {
        $$ = mk_typed(NAtomic, $3->name, $2, nil, nil);
    }
    ;

stream_decl:
    TSTREAM TIDENT ';'
    {
        $$ = mk(NStream, $2->name, nil, nil, nil);
    }
    ;

secret_decl:
    TSECRET typename TIDENT ';'
    {
        $$ = mk_typed(NSecret, $3->name, $2, nil, nil);
    }
    ;

cap_decl:
    TCAP typename TIDENT ';'
    {
        $$ = mk_typed(NCap, $3->name, $2, nil, nil);
    }
    ;

/* 
 * C#-style method declaration.
 * Return type first:  method int64 getValue() { return val; }
 * No return type (void implied):  method inc(int64 n) { val += n; }
 * Expression body:  method int64 double() => val * 2;
 * Backward compat:  method inc() { }
 */
method_decl:
    TMETHOD typename TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $3->name, $2, $8, $5);
    }
    | TMETHOD typename TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $8, nil);
        $$ = mk_typed(NMethod, $3->name, $2, body, $5);
    }
    | TMETHOD typename TIDENT '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $3->name, $2, nil, $5);
    }
    | TMETHOD TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $7, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $7, nil);
        $$ = mk(NMethod, $2->name, "void", body, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' ';'
    {
        $$ = mk(NMethod, $2->name, "void", nil, $4);
    }
    ;

inherit_decl:
    name_ref ';'
    {
        Node *tn;

        tn = type_node(type_from_name($1->name));
        $$ = mk_typed(NInherit, tn->name, tn, nil, nil);
    }
    ;

var_decl:
    typename TIDENT ';'
    {
        $$ = mk_typed(NProp, $2->name, $1, nil, nil);
    }
    | TCHAN TIDENT ';'
    {
        $$ = mk(NStream, $2->name, "chan", nil, nil);
    }
    ;

func_decl:
    TFUNC '(' typename TIDENT ')' TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        Node *params = $8;
        Node *stmts = $12;
        $$ = mk_typed(NMethod, $6->name, $10, stmts, params);
    }
    ;

param_list:
    /* empty */ { $$ = nil; }
    | param { $$ = $1; }
    | param_list ',' param {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

param:
    typename TIDENT
    {
        $$ = mk_typed(NProp, $2->name, $1, nil, nil);
    }
    ;

destructor_decl:
    '~' TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NDestructor, $2->name, nil, $6, nil);
    }
    ;

stmt_list:
    /* empty */ { $$ = nil; }
    | stmt_list stmt {
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

stmt:
    typename TIDENT ';' { $$ = mk_typed(NLocalVar, $2->name, $1, nil, nil); if(is_class_type($1->name)) add_var_class($2->name, $1->name); }
    | typename TIDENT TEQ expr ';' { $$ = mk_typed(NLocalVar, $2->name, $1, $4, nil); if(is_class_type($1->name)) add_var_class($2->name, $1->name); }
    | expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    | TPRINT '(' call_args ')' ';' {
        $$ = mk(NFuncCall, "print", nil, $3, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' { $$ = mk(NIf, nil, nil, $3, $6); }
    | TIF '(' expr ')' '{' stmt_list '}' TELSE '{' stmt_list '}' {
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElse, nil, nil, $10, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElseIf, nil, nil, $10, $13);
        if($15) $$->next->next = $15;
    }
    | TWHILE '(' expr ')' '{' stmt_list '}' { $$ = mk(NWhile, nil, nil, $3, $6); }
    | TFOR '(' for_init TFORSEMI for_cond TFORSEMI for_step ')' '{' stmt_list '}' { $$ = mk(NFor, nil, nil, $3, mk(NFor, nil, nil, $5, $7)); $$->right->next = $10; }
    ;

for_init:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_cond:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_step:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

else_clause:
    /* empty */ { $$ = nil; }
    | TELSE '{' stmt_list '}' { $$ = mk(NElse, nil, nil, $3, nil); }
    | TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NElseIf, nil, nil, $3, $6);
        $$->next = $8;
    }
    ;

expr:
    expr TCHANSEND expr { $$ = mk(NChanSend, nil, nil, $1, $3); }
    | expr TCHANTRY expr { $$ = mk(NChanTry, nil, nil, $1, $3); }
    | expr TEQ TCHANRECV expr { $$ = mk(NChanRecv, nil, nil, $1, $4); }
    | expr TEQ expr { $$ = mk(NAssign, nil, nil, $1, $3); }
    | expr TADD expr { $$ = mk(NAdd, nil, nil, $1, $3); }
    | expr TSUB expr { $$ = mk(NSub, nil, nil, $1, $3); }
    | expr '*' expr { $$ = mk(NMul, nil, nil, $1, $3); }
    | expr '/' expr { $$ = mk(NDiv, nil, nil, $1, $3); }
    | expr '%' expr { $$ = mk(NMod, nil, nil, $1, $3); }
    | expr TEQEQ expr { $$ = mk(NEq, nil, nil, $1, $3); }
    | expr TNEQ expr { $$ = mk(NNe, nil, nil, $1, $3); }
    | expr '<' expr { $$ = mk(NLt, nil, nil, $1, $3); }
    | expr TLE expr { $$ = mk(NLe, nil, nil, $1, $3); }
    | expr '>' expr { $$ = mk(NGt, nil, nil, $1, $3); }
    | expr TGE expr { $$ = mk(NGe, nil, nil, $1, $3); }
    | expr TAND expr { $$ = mk(NAnd, nil, nil, $1, $3); }
    | expr TOR expr { $$ = mk(NOr, nil, nil, $1, $3); }
    | expr '&' expr { $$ = mk(NBitAnd, nil, nil, $1, $3); }
    | expr '|' expr { $$ = mk(NBitOr, nil, nil, $1, $3); }
    | expr '^' expr { $$ = mk(NBitXor, nil, nil, $1, $3); }
    | expr TLSHIFT expr { $$ = mk(NLshift, nil, nil, $1, $3); }
    | expr TRSHIFT expr { $$ = mk(NRshift, nil, nil, $1, $3); }
    | '!' expr { $$ = mk(NNot, nil, nil, $2, nil); }
    | '~' expr { $$ = mk(NBitNot, nil, nil, $2, nil); }
    | TSUB expr %prec UMINUS { $$ = mk(NNeg, nil, nil, $2, nil); }
    | expr '.' TIDENT {
        $$ = mk(NPropRead, $3->name, nil, $1, nil);
    }
    | expr '.' TIDENT '(' call_args ')' {
        $$ = mk(NMsgSend, $3->name, nil, $1, $5);
    }
    | expr '[' expr ']' {
        $$ = mk(NArrayGet, nil, nil, $1, $3);
    }
    | TIDENT { $$ = enum_expr_or_ident($1); }
    | TQIDENT { $$ = enum_expr_or_ident($1); }
    | TENUMIDENT { $$ = enum_expr_or_ident($1); }
    | TINTLIT { $$ = mk(NIntLit, $1, nil, nil, nil); }
    | TSTRINGLIT { $$ = mk(NStringLit, $1, nil, nil, nil); }
    | TCHARLIT { $$ = mk(NCharLit, $1, nil, nil, nil); }
    | TTRUE { $$ = mk(NBoolLit, "1", nil, nil, nil); }
    | TFALSE { $$ = mk(NBoolLit, "0", nil, nil, nil); }
    | TNIL { $$ = mk(NBoolLit, "nil", nil, nil, nil); }
    | TNEW typename '(' call_args ')' {
        Node *n = mk(NClass, $2->name, "same", nil, nil);
        n->typeinfo = $2->typeinfo;
        n->left = $2;
        n->right = $4;
        $$ = n;
    }
    | TNEW TNEAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "near", nil, nil);
        n->typeinfo = $3->typeinfo;
        n->left = $3;
        n->right = $5;
        $$ = n;
    }
    | TNEW TFAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "far", nil, nil);
        n->typeinfo = $3->typeinfo;
        n->left = $3;
        n->right = $5;
        $$ = n;
    }
    | '(' expr ')' { $$ = $2; }
    ;

call_args:
    /* empty */ { $$ = nil; }
    | call_arg { $$ = $1; }
    | call_args ',' call_arg {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

call_arg:
    expr { $$ = $1; }
    ;

%%

Node*
append_node(Node *list, Node *node)
{
    Node *n;

    if(list == nil)
        return node;
    if(node == nil)
        return list;
    for(n = list; n->next; n = n->next)
        ;
    n->next = node;
    return list;
}

Node*
mk(int type, char *name, char *typename, Node *l, Node *r)
{
    Node *n = malloc(sizeof(Node));
    memset(n, 0, sizeof(Node));
    n->type = type;
    if(name){
        n->name = strdup(name);
        n->qname = strdup(name);
        n->cname = strdup(name);
    }
    if(typename){
        n->typename = strdup(typename);
        n->typeinfo = typeinfo_from_legacy(typename);
    }
    n->left = l;
    n->right = r;
    return n;
}

void
yyerror(char *s)
{
    fprint(2, "o9c: error: %s\n", s);
}

static char *input_buf;
static int input_pos;
static int input_len;
char *loaded_files[64];
int num_loaded_files = 0;

static int for_paren_depth = -1;	/* >=0 when inside for(...) — ';' returns TFORSEMI */
static int pushback[8];		/* multi-char pushback buffer */
static int npush = 0;

static int
lex_getc(void)
{
	if(npush > 0)
		return pushback[--npush];
	if(input_pos >= input_len)
		return Beof;
	return (unsigned char)input_buf[input_pos++];
}

static void
lex_ungetc(int c)
{
	if(npush < 8)
		pushback[npush++] = c;
}

int
yylex(void)
{
    int c;

    while((c = lex_getc()) != Beof){
        if(isspace(c))
            continue;
        /* Inside for(...): track paren depth, convert ';' to TFORSEMI */
        if(for_paren_depth >= 0){
            if(c == '(') { for_paren_depth++; return '('; }
            if(c == ')' && for_paren_depth > 0) { for_paren_depth--; return ')'; }
            if(c == ')' && for_paren_depth == 0) { for_paren_depth = -1; return ')'; }
            if(c == ';') return TFORSEMI;
        }
        if(c == '~')
            return '~';
        if(c == '='){
            if((c = lex_getc()) == '=') return TEQEQ;
            if(c == '>') return TARROW;
            lex_ungetc(c);
            return TEQ;
        }
        if(c == '&'){
            if((c = lex_getc()) == '&') return TAND;
            lex_ungetc(c);
            return '&';
        }
        if(c == '|'){
            if((c = lex_getc()) == '|') return TOR;
            lex_ungetc(c);
            return '|';
        }
        if(c == '!'){
            if((c = lex_getc()) == '=') return TNEQ;
            lex_ungetc(c);
            return '!';
        }
        if(c == '<'){
            if((c = lex_getc()) == '-') return TCHANRECV;
            if(c == '=') return TLE;
            if(c == '<') return TLSHIFT;
            lex_ungetc(c);
            return '<';
        }
        if(c == '>'){
            if((c = lex_getc()) == '=') return TGE;
            if(c == '>') return TRSHIFT;
            lex_ungetc(c);
            return '>';
        }
        if(c == '"'){
            char buf[1024];
            int i = 0;
            while((c = lex_getc()) != Beof && c != '"' && i < 1023) {
                if(c == '\\'){
                    if((c = lex_getc()) == Beof) break;
                    if(c == 'n') buf[i++] = '\n';
                    else if(c == 't') buf[i++] = '\t';
                    else buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TSTRINGLIT;
        }
        if(c == '\''){
            char buf[16];
            int i = 0;
            while((c = lex_getc()) != Beof && c != '\'' && i < 15) {
                if(c == '\\'){
                    if((c = lex_getc()) == Beof) break;
                    buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TCHARLIT;
        }
        if(c == '-'){
            if((c = lex_getc()) == '>'){
                if((c = lex_getc()) == '?') return TCHANTRY;
                lex_ungetc(c);
                return TCHANSEND;
            }
            lex_ungetc(c);
            return TSUB;
        }
        if(c == '/'){
            if((c = lex_getc()) == '/'){
                while((c = lex_getc()) != Beof && c != '\n');
                continue;
            }
            if(c == '*'){
                while((c = lex_getc()) != Beof){
                    if(c == '*'){
                        if((c = lex_getc()) == '/') break;
                        lex_ungetc(c);
                    }
                }
                continue;
            }
            lex_ungetc(c);
            return '/';
        }
        if(c == '+') return TADD;

        if(isdigit(c)){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            if(c == '0'){
                c = lex_getc();
                if(c == 'x' || c == 'X'){
                    buf[i++] = c;
                    while(isxdigit(c = lex_getc())) {
                        if(i < 63) buf[i++] = c;
                    }
                    lex_ungetc(c);
                    buf[i] = '\0';
                    yylval.name = strdup(buf);
                    return TINTLIT;
                }
                lex_ungetc(c);
            }
            while(isdigit(c = lex_getc())) {
                if(i < 63) buf[i++] = c;
            }
            lex_ungetc(c);
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TINTLIT;
        }

        if(isalpha(c) || c == '_'){
            char buf[128];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = lex_getc()) || c == '_') {
                if(i < sizeof(buf)-1) buf[i++] = c;
            }
            if(isupper((uchar)buf[0])){
                while(c == '.'){
                    int nc;

                    nc = lex_getc();
                    if(!(isalpha(nc) || nc == '_')){
                        lex_ungetc(nc);
                        lex_ungetc('.');
                        break;
                    }
                    if(i < sizeof(buf)-1)
                        buf[i++] = '.';
                    if(i < sizeof(buf)-1)
                        buf[i++] = nc;
                    while(isalnum(c = lex_getc()) || c == '_'){
                        if(i < sizeof(buf)-1)
                            buf[i++] = c;
                    }
                }
            }
            lex_ungetc(c);
            buf[i] = '\0';
            
            yylval.node = mk(NIdent, buf, nil, nil, nil);
            if(strchr(buf, '.') != nil){
                if(resolve_enum_sym(buf) != nil)
                    return TENUMIDENT;
                if(is_known_type_name(buf) || isupper((uchar)buf[0]))
                    return TTYPEIDENT;
                return TQIDENT;
            }
            
            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "struct") == 0) return TSTRUCT;
            if(strcmp(buf, "interface") == 0) return TINTERFACE;
            if(strcmp(buf, "enum") == 0) return TENUM;
            if(strcmp(buf, "module") == 0) return TMODULE;
            if(strcmp(buf, "import") == 0) return TIMPORT;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "far") == 0) return TFAR;
            if(strcmp(buf, "Dict") == 0) return TDICT;
            if(strcmp(buf, "method") == 0) return TMETHOD;
            if(strcmp(buf, "state") == 0) return TSTATE;
            if(strcmp(buf, "prop") == 0) return TPROP;
            if(strcmp(buf, "atomic") == 0) return TATOMIC;
            if(strcmp(buf, "stream") == 0) return TSTREAM;
            if(strcmp(buf, "secret") == 0) return TSECRET;
            if(strcmp(buf, "cap") == 0) return TCAP;
            if(strcmp(buf, "object") == 0) return TOBJECT;
            if(strcmp(buf, "link") == 0) return TLINK;
            if(strcmp(buf, "ref") == 0) return TREF;
            if(strcmp(buf, "replica") == 0) return TREPLICA;
            if(strcmp(buf, "chan") == 0) return TCHAN;
            if(strcmp(buf, "return") == 0) return TRETURN;
            if(strcmp(buf, "if") == 0) return TIF;
            if(strcmp(buf, "else") == 0){
                int nc = lex_getc();
                while(nc == ' ' || nc == '\t') nc = lex_getc();
                if(nc == 'i'){
                    int nc2 = lex_getc();
                    if(nc2 == 'f') return TELIF;
                    lex_ungetc(nc2);
                }
                lex_ungetc(nc);
                return TELSE;
            }
            if(strcmp(buf, "while") == 0) return TWHILE;
            if(strcmp(buf, "for") == 0){ for_paren_depth = 0; return TFOR; }
            if(strcmp(buf, "true") == 0) return TTRUE;
            if(strcmp(buf, "false") == 0) return TFALSE;
            if(strcmp(buf, "dict") == 0) return TDICT;
            if(strcmp(buf, "List") == 0) return TLIST;
            if(strcmp(buf, "nil") == 0) return TNIL;

            if(strcmp(buf, "print") == 0) return TPRINT;
            if(strcmp(buf, "bool") == 0) return TTYPE;
            if(strcmp(buf, "int64") == 0) return TTYPE;
            if(strcmp(buf, "uint64") == 0) return TTYPE;
            if(strcmp(buf, "int32") == 0) return TTYPE;
            if(strcmp(buf, "uint32") == 0) return TTYPE;
            if(strcmp(buf, "int16") == 0) return TTYPE;
            if(strcmp(buf, "uint16") == 0) return TTYPE;
            if(strcmp(buf, "int8") == 0) return TTYPE;
            if(strcmp(buf, "uint8") == 0) return TTYPE;
            if(strcmp(buf, "void") == 0) return TTYPE;
            if(strcmp(buf, "string") == 0) return TTYPE;
            if(strcmp(buf, "int") == 0) return TTYPE;
            if(strcmp(buf, "char") == 0) return TTYPE;
            if(strcmp(buf, "vlong") == 0) return TTYPE;
            if(strcmp(buf, "uvlong") == 0) return TTYPE;
            if(strcmp(buf, "ulong") == 0) return TTYPE;
            if(strcmp(buf, "ushort") == 0) return TTYPE;
            if(strcmp(buf, "uchar") == 0) return TTYPE;
            if(resolve_enum_sym(buf) != nil)
                return TENUMIDENT;
            if(is_known_type_name(buf) || isupper((uchar)buf[0]))
                return TTYPEIDENT;
            return TIDENT;
        }
        return c;
    }
    return 0;
}

/* --- Code Generator --- */

char *local_vars[128];
int num_locals = 0;
int in_class_context = 1;		/* 0 when generating top-level main() */
int in_method_body = 0;		/* 1 when generating inside a method impl */
int has_return = 0;			/* 1 when a return statement was emitted */
Node *cur_class;			/* current class being codegen'd, for type lookups */
int new_tmp_id = 0;

/* Variable-to-class symbol table */
typedef struct VarClass VarClass;
struct VarClass {
    char *varname;
    char *classname;
};
VarClass var_classes[128];
int num_var_classes = 0;

void
add_var_class(char *varname, char *classname)
{
    if(num_var_classes >= 128) return;
    var_classes[num_var_classes].varname = varname;
    var_classes[num_var_classes].classname = classname;
    num_var_classes++;
}

char*
get_var_class(char *varname)
{
    int i;
    for(i=0; i<num_var_classes; i++){
        if(strcmp(var_classes[i].varname, varname) == 0)
            return var_classes[i].classname;
    }
    return nil;
}

void
mark_locals(Node *n)
{
    if(n == nil) return;
    if(n->type == NLocalVar && n->name) {
        if(num_locals < 128) local_vars[num_locals++] = n->name;
    }
    mark_locals(n->left);
    mark_locals(n->right);
    mark_locals(n->next);
}

int
is_local(char *name)
{
    int i;
    for(i=0; i<num_locals; i++){
        if(strcmp(local_vars[i], name) == 0) return 1;
    }
    return 0;
}

void gen_expr(Node *e);

void
gen_expr(Node *e)
{
    if(e == nil) return;
    switch(e->type){
    case NIdent:
        if(is_local(e->name))
            print("%s", e->name);
        else if(in_class_context)
            print("self->%s", e->name);
        else
            print("%s", e->name);
        break;
    case NIntLit:
        print("%s", e->name);
        break;
    case NStringLit:
        {
            /* Re-escape special chars for C output */
            char *s;
            print("\"");
            for(s = e->name; *s; s++){
                if(*s == '\n') print("\\n");
                else if(*s == '\t') print("\\t");
                else if(*s == '\\') print("\\\\");
                else if(*s == '"') print("\\\"");
                else print("%c", *s);
            }
            print("\"");
        }
        break;
    case NCharLit:
        print("'%s'", e->name);
        break;
    case NBoolLit:
        print("%s", e->name);
        break;
    case NEnumVal:
        print("%s", e->name);
        break;
    case NMsgSend:
        {
            char *lt = get_expr_type(e->left);
            if(strncmp(lt, "List:", 5) == 0){
                if(strcmp(e->name, "Add") == 0){
                    char *et = lt + 5;
                    char *st = storage_type(et);
                    char *rt = get_expr_type(e->right);
                    if(is_class_type(et) && is_class_type(rt)){
                        print("({ %s __v; memmove(&__v, &", st); gen_expr(e->right);
                        print(", sizeof(%s)); o9_slice_append(&", st);
                    } else {
                        print("({ %s __v = ", st); gen_expr(e->right);
                        print("; o9_slice_append(&");
                    }
                    gen_expr(e->left); print(", &__v); (vlong)0; })");
                    break;
                }
                if(strcmp(e->name, "Length") == 0){
                    print("(vlong)("); gen_expr(e->left); print(".len)");
                    break;
                }
            }
            if(strncmp(lt, "Dict:", 5) == 0){
                if(strcmp(e->name, "Has") == 0){
                    print("o9_dict_has(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
                    break;
                }
            }
        }
        /* c.method(args...) -> try o9_dispatch_call (asm), fallback to obj9_msgSend (CSP/9P) */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            /* Pack: args[0]=shm_base (for ctrl thunk), args[1..N]=real args */
            print("(o9_call_args[0]=");
            if(e->left && e->left->type == NIdent && e->left->name){
                char *__cnx = get_var_class(e->left->name);
                if(__cnx) print("(vlong)((%s_Client*)&", __cnx);
                gen_expr(e->left);
                if(__cnx) print(")->shm_base");
            } else {
                print("(vlong)&");
                gen_expr(e->left);
            }
            {
                int i = 1;
                for(a = e->right; a; a = a->next){
                    char buf[64];
                    snprint(buf, sizeof buf, ", o9_call_args[%d]=", i);
                    print(buf);
                    gen_expr(a);
                    i++;
                }
            }
            /* Try asm dispatch first, fallback to CSP/9P with args+1 (skip shm_base) */
            print(", (vlong)o9_dispatch_call(&");
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args) || ", o9_hash(e->name));
            if(e->left && e->left->type == NIdent){
                /* Remote 9P path walks to "varname/methodname" in the instance tree */
                print("(vlong)obj9_msgSend(&");
                gen_expr(e->left);
                print(", \"%s/%s\", 0x%lux, o9_call_args+1))", e->left->name, e->name, o9_hash(e->name));
            } else {
                print("(vlong)obj9_msgSend(&");
                gen_expr(e->left);
                print(", \"%s\", 0x%lux, o9_call_args+1))", e->name, o9_hash(e->name));
            }
        }
        break;
    case NPropRead:
        {
            char *cn = get_expr_type(e->left);
            Node *cnode = find_class(cn);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface){
                    char *t = get_sym_type(cnode, e->name);
                    if(find_class(t) && find_class(t)->type == NStruct){
                        print("((%s_Internal*)((%s_Client*)&", cn, cn);
                        gen_expr(e->left);
                        print(")->shm_base)->%s", e->name);
                    } else if(strcmp(t, "char*") == 0 || strcmp(t, "O9Dict") == 0 || strcmp(t, "O9Slice") == 0){
                        print("((%s_Internal*)((%s_Client*)&", cn, cn);
                        gen_expr(e->left);
                        print(")->shm_base)->%s", e->name);
                    } else {
                        print("(vlong)((%s_Internal*)((%s_Client*)&", cn, cn);
                        gen_expr(e->left);
                        print(")->shm_base)->%s", e->name);
                    }
                    break;
                } else if(cnode->type == NStruct){
                    gen_expr(e->left);
                    print(".%s", e->name);
                    break;
                }
            }
            gen_expr(e->left);
            print(".%s", e->name);
        }
        break;
    case NAdd:
        print("("); gen_expr(e->left); print(" + "); gen_expr(e->right); print(")");
        break;
    case NSub:
        print("("); gen_expr(e->left); print(" - "); gen_expr(e->right); print(")");
        break;
    case NMul:
        print("("); gen_expr(e->left); print(" * "); gen_expr(e->right); print(")");
        break;
    case NDiv:
        print("("); gen_expr(e->left); print(" / "); gen_expr(e->right); print(")");
        break;
    case NMod:
        print("("); gen_expr(e->left); print(" %% "); gen_expr(e->right); print(")");
        break;
    case NEq:
        print("("); gen_expr(e->left); print(" == "); gen_expr(e->right); print(")");
        break;
    case NNe:
        print("("); gen_expr(e->left); print(" != "); gen_expr(e->right); print(")");
        break;
    case NLt:
        print("("); gen_expr(e->left); print(" < "); gen_expr(e->right); print(")");
        break;
    case NLe:
        print("("); gen_expr(e->left); print(" <= "); gen_expr(e->right); print(")");
        break;
    case NGt:
        print("("); gen_expr(e->left); print(" > "); gen_expr(e->right); print(")");
        break;
    case NGe:
        print("("); gen_expr(e->left); print(" >= "); gen_expr(e->right); print(")");
        break;
    case NAnd:
        print("("); gen_expr(e->left); print(" && "); gen_expr(e->right); print(")");
        break;
    case NOr:
        print("("); gen_expr(e->left); print(" || "); gen_expr(e->right); print(")");
        break;
    case NBitAnd:
        print("("); gen_expr(e->left); print(" & "); gen_expr(e->right); print(")");
        break;
    case NBitOr:
        print("("); gen_expr(e->left); print(" | "); gen_expr(e->right); print(")");
        break;
    case NBitXor:
        print("("); gen_expr(e->left); print(" ^ "); gen_expr(e->right); print(")");
        break;
    case NLshift:
        print("("); gen_expr(e->left); print(" << "); gen_expr(e->right); print(")");
        break;
    case NRshift:
        print("("); gen_expr(e->left); print(" >> "); gen_expr(e->right); print(")");
        break;
    case NNot:
        print("!"); gen_expr(e->left);
        break;
    case NBitNot:
        print("~"); gen_expr(e->left);
        break;
    case NNeg:
        print("-"); gen_expr(e->left);
        break;
    case NFuncCall:

        /* Built-in functions like print(...) */
        if(strcmp(e->name, "print") == 0){
            /* Emit fprint(1, "fmt", args...) */
            print("fprint(1, ");
            Node *a = e->left;
            if(a == nil){
                print("\"\"");
            } else if(a->type == NStringLit && a->next == nil){
                /* Single string literal — use as format directly */
                gen_expr(a);
            } else {
                /* First arg is our format string or the value itself */
                int first = 1;
                Node *first_arg = a;
                if(first_arg->type == NStringLit){
                    /* Format string provided */
                    gen_expr(first_arg);
                    first = 0;
                    for(a = first_arg->next; a; a = a->next){
                        if(!first) print(", ");
                        gen_expr(a);
                        first = 0;
                    }
                } else if(first_arg->next == nil){
                    /* Single non-string arg — use %lld as format */
                    print("\"%%lld\"");
                    print(", ");
                    gen_expr(first_arg);
                } else {
                    /* Multiple args, first not a string — print bare */
                    for(a = first_arg; a; a = a->next){
                        if(!first) print(", ");
                        gen_expr(a);
                        first = 0;
                    }
                }
            }
            print(")");
        } else {
            /* Unknown function call — just emit as-is */
            print("%s(", e->name);
            int first = 1;
            Node *a;
            for(a = e->left; a; a = a->next){
                if(!first) print(", ");
                gen_expr(a);
                first = 0;
            }
            print(")");
        }
        break;
    case NArrayGet:
        {
            char *lt = get_expr_type(e->left);
            if(strncmp(lt, "List:", 5) == 0){
                char *et = lt + 5;
                print("(*(%s*)o9_slice_get(&", storage_type(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
            } else if(strncmp(lt, "Dict:", 5) == 0){
                char *last = strrchr(lt, ':');
                char *vt = last ? last + 1 : "vlong";
                print("((%s)o9_dict_get(&", map_type(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
            } else if(e->right && e->right->type == NStringLit){
                /* Legacy dict access fallback */
                print("o9_dict_get(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
            } else {
                print("o9_array_get("); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
            }
        }
        break;
    }
}

void gen_stmt(Node *c, Node *s);
static int member_exists(Node *cnode, char *name);
int count_state_cols(Node *c);
void gen_init_internal_state(Node *c, char *ptr);
void gen_state_store(char *stateexpr, char *fieldexpr, char *name, char *typename);

void
gen_assign_new(char *varname, char *lhs_type, Node *n)
{
    char *cn, *dist;
    int dval, nctor, id, ai;
    Node *ca;

    if(varname == nil || lhs_type == nil || n == nil || n->name == nil)
        return;
    cn = n->name;
    dist = n->typename;
    dval = (dist && strcmp(dist, "near") == 0) ? 0 : (dist && strcmp(dist, "far") == 0) ? 1 : -1;
    nctor = 0;
    for(ca = n->right; ca; ca = ca->next)
        nctor++;

    if(dval >= 0 && n->right && n->right->type == NStringLit){
        Node *first_arg = n->right;
        int rest = nctor - 1;
        print("\tmemset(&%s, 0, sizeof(%s_Client));\n", varname, lhs_type);
        print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", varname);
        print("\t%s.table = &%s_tbl;\n", varname, varname);
        print("\t{\n\t\tchar __addr[128];\n\t\tsnprint(__addr, sizeof __addr, ");
        gen_expr(first_arg);
        print(");\n\t\to9_connect(&%s, __addr, \"%s\");\n", varname, cn);
        print("\t\t%s.distance = %d;\n", varname, dval);
        if(rest > 0){
            ai = 0;
            print("\t\tvlong __args_%s[%d];\n", varname, rest);
            for(ca = first_arg->next; ca; ca = ca->next){
                print("\t\t__args_%s[%d] = ", varname, ai);
                gen_expr(ca);
                print(";\n");
                ai++;
            }
            print("\t\tobj9_msgSend(&%s, \"%s\", 0x%lux, __args_%s);\n", varname, cn, o9_hash(cn), varname);
        }
        print("\t}\n");
        return;
    }

    id = new_tmp_id++;
    print("\t%s_Internal *__o9n%d = emalloc9p(sizeof(%s_Internal));\n", cn, id, cn);
    print("\tmemset(__o9n%d, 0, sizeof(%s_Internal));\n", id, cn);
    print("\t__o9n%d->dispatch_chan = chancreate(sizeof(void*), 10);\n", id);
    print("\t__o9n%d->distance = %d;\n", id, dval >= 0 ? dval : -1);
    print("\t__o9n%d->state = o9_state_create(\"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        id, cn, varname, cn, count_state_cols(find_class(cn)));
    {
        char ptr[64];
        snprint(ptr, sizeof ptr, "__o9n%d", id);
        gen_init_internal_state(find_class(cn), ptr);
    }
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", varname, lhs_type);
    print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", varname);
    print("\t%s.shm_base = __o9n%d;\n", varname, id);
    print("\t%s.dispatch_chan = __o9n%d->dispatch_chan;\n", varname, id);
    print("\t%s.table = &%s_tbl;\n", varname, varname);
    print("\t%s.distance = %d;\n", varname, dval >= 0 ? dval : -1);
    print("\tproccreate(%s_loop, __o9n%d, 8192);\n", cn, id);
    print("\t%s_create_instance(__o9n%d, \"%s\");\n", cn, id, varname);
    if(nctor > 0){
        ai = 0;
        print("\t{ vlong __args_%s_%d[%d];\n", varname, id, nctor);
        for(ca = n->right; ca; ca = ca->next){
            print("\t__args_%s_%d[%d] = ", varname, id, ai);
            gen_expr(ca);
            print(";\n");
            ai++;
        }
        print("\tobj9_msgSend(&%s, \"%s\", 0x%lux, __args_%s_%d); }\n",
            varname, cn, o9_hash(cn), varname, id);
    } else {
        print("\tobj9_msgSend(&%s, \"%s\", 0x%lux, nil);\n", varname, cn, o9_hash(cn));
    }
}

void
gen_local_new(Node *s, char *cn, int distance)
{
    Node *ca;
    int ai = 0, nctor = 0;
    for(ca = s->left->right; ca; ca = ca->next)
        nctor++;

    print("\t%s_Internal *__%s = emalloc9p(sizeof(%s_Internal));\n", cn, s->name, cn);
    print("\tmemset(__%s, 0, sizeof(%s_Internal));\n", s->name, cn);
    print("\t__%s->dispatch_chan = chancreate(sizeof(void*), 10);\n", s->name);
    print("\t%s_Client %s;\n", cn, s->name);
    print("\to9_AsmTable %s_tbl;\n", s->name);
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
    print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
    print("\t%s.shm_base = __%s;\n", s->name, s->name);
    print("\t%s.dispatch_chan = __%s->dispatch_chan;\n", s->name, s->name);
    print("\t%s.table = &%s_tbl;\n", s->name, s->name);
    print("\t__%s->distance = %d;\n", s->name, distance);
    print("\t%s.distance = %d;\n", s->name, distance);
    print("\t__%s->state = o9_state_create(\"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        s->name, cn, s->name, cn, count_state_cols(find_class(cn)));
    if(find_class(cn)){
        Node *cnode = find_class(cn);
        char ptr[128];
        snprint(ptr, sizeof ptr, "__%s", s->name);
        gen_init_internal_state(cnode, ptr);
    }
    print("\tproccreate(%s_loop, __%s, 8192);\n", cn, s->name);
    print("\t%s_create_instance(__%s, \"%s\");\n", cn, s->name, s->name);
    if(nctor > 0){
        print("\t{ vlong __args_%s[%d];\n", s->name, nctor);
        for(ca = s->left->right; ca; ca = ca->next){
            print("\t__args_%s[%d] = ", s->name, ai);
            gen_expr(ca);
            print(";\n");
            ai++;
        }
        print("\tobj9_msgSend(&%s, \"%s\", 0x%lux, __args_%s); }\n", s->name, cn, o9_hash(cn), s->name);
    } else {
        print("\tobj9_msgSend(&%s, \"%s\", 0x%lux, nil);\n", s->name, cn, o9_hash(cn));
    }
}

void
gen_stmt(Node *c, Node *s)
{
    Node *n;
    if(s == nil) return;
    switch(s->type){
    case NLocalVar:
        if(is_primitive(s->typename)){
            print("\t%s %s;\n", map_type(s->typename), s->name);
            if(strncmp(s->typename, "List:", 5) == 0){
                print("\to9_slice_init(&%s, sizeof(%s));\n", s->name, storage_type(s->typename+5));
            } else if(strncmp(s->typename, "Dict:", 5) == 0){
                print("\to9_dict_init(&%s);\n", s->name);
            } else if(s->left){
                print("\t%s = ", s->name); gen_expr(s->left); print(";\n");
            } else {
                print("\tmemset(&%s, 0, sizeof(%s));\n", s->name, map_type(s->typename));
            }
        } else {
            char *cname = find_class(s->typename) ? s->typename : nil;
            int is_new = (s->left && s->left->type == NClass && s->left->name);
            if(in_class_context || cname == nil){
                /* Plain local variable */
                print("\t%s %s", map_type(s->typename), s->name);
                if(s->left && !is_new){
                    print(" = "); gen_expr(s->left);
                }
                print(";\n");
            } else if(is_new && cname){
                /* Counter c = new Counter(...) -> spawn in-process server + client */
                char *cn = cname;
                char *dist = s->left->typename;
                int dval = (dist && strcmp(dist, "near") == 0) ? 0 : (dist && strcmp(dist, "far") == 0) ? 1 : -1;
                /* Count constructor args from TNEW node's call_args (s->left->right) */
                int nctor = 0;
                {
                    Node *ca;
                    for(ca = s->left->right; ca; ca = ca->next) nctor++;
                }
                if(dval >= 0 && s->left->right && s->left->right->type == NStringLit){
                    /* Remote: connect via IL/TCP, no local server */
                    Node *first_arg = s->left->right;
                    int rest = nctor - 1;
                    print("\t%s_Client %s;\n", cn, s->name);
                    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
                    /* First constructor arg is the address */
                    print("\t{\n");
                    if(first_arg){
                        print("\t\tchar __addr[128];\n");
                        print("\t\tsnprint(__addr, sizeof __addr, ");
                        gen_expr(first_arg);
                        print(");\n");
                        print("\t\to9_connect(&%s, __addr, \"%s\");\n", s->name, cn);
                    }
                    print("\t\t%s.distance = %d;\n", s->name, dval);
                    /* Send constructor args (skip address, send rest) */
                    if(rest > 0){
                        Node *ca;
                        int ai = 0;
                        print("\t\tvlong __args_%s[%d];\n", s->name, rest);
                        for(ca = first_arg->next; ca; ca = ca->next){
                            print("\t\t__args_%s[%d] = ", s->name, ai);
                            gen_expr(ca);
                            print(";\n");
                            ai++;
                        }
                        print("\t\tobj9_msgSend(&%s, \"%s\", 0x%lux, __args_%s);\n", s->name, cn, o9_hash(cname), s->name);
                    }
                    print("\t}\n");
                } else {
                    gen_local_new(s, cn, dval >= 0 ? dval : -1);
                }
            } else {
                /* Class-typed variable with client init (no new) */
                print("\t%s_Client %s;\n", cname, s->name);
                print("\to9_AsmTable %s_tbl;\n", s->name);
                print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cname);
                print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
                print("\t%s.table = &%s_tbl;\n", s->name, s->name);
                print("\to9_init_client(&%s, \"%s\", 4096);\n", s->name, cname);
            }
        }
        break;
        break;
    case NMsgSend:
        {
            char *lt = get_expr_type(s->left);
            if(strncmp(lt, "List:", 5) == 0 && strcmp(s->name, "Add") == 0){
                char *et = lt + 5;
                char *st = storage_type(et);
                char *rt = get_expr_type(s->right);
                if(is_class_type(et) && is_class_type(rt)){
                    print("\t{ %s __o9v; memmove(&__o9v, &", st);
                    gen_expr(s->right);
                    print(", sizeof(%s)); o9_slice_append(&", st);
                } else {
                    print("\t{ %s __o9v = ", st);
                    gen_expr(s->right);
                    print("; o9_slice_append(&");
                }
                gen_expr(s->left);
                print(", &__o9v); }\n");
                break;
            }
        }
        print("\t"); gen_expr(s); print(";\n");
        break;
    case NChanSend: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; sendp("); gen_expr(s->left); print(", __box); }\n");
        break;
    }
    case NChanTry: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; Alt __a[] = {{"); gen_expr(s->left); print(", __box, CHANSND}, {nil, nil, CHANNOBLK}, {nil, nil, CHANEND}}; if(alt(__a) == 1) free(__box); }\n");
        break;
    }
    case NChanRecv: {
        char *t = "vlong";
        if(s->left->type == NIdent) t = get_sym_type(c, s->left->name);
        print("\t{ %s *__box = recvp(", t); gen_expr(s->right); print("); if(__box){ "); gen_expr(s->left); print(" = *__box; free(__box); } }\n");
        break;
    }
    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            char *lt = get_expr_type(s->left->left);
            if(strncmp(lt, "List:", 5) == 0){
                char *et = lt + 5;
                char *st = storage_type(et);
                char *rt = get_expr_type(s->right);
                if(is_class_type(et) && is_class_type(rt)){
                    print("\t{ %s __v; memmove(&__v, &", st); gen_expr(s->right); print(", sizeof(%s)); o9_slice_set(&", st);
                } else {
                    print("\t{ %s __v = ", st); gen_expr(s->right); print("; o9_slice_set(&");
                }
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", &__v); }\n");
                break;
            } else if(strncmp(lt, "Dict:", 5) == 0){
                print("\to9_dict_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", (void*)("); gen_expr(s->right); print("));\n");
                break;
            } else if(s->left->right && s->left->right->type == NStringLit){
                print("\to9_dict_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\n");
            } else {
                print("\to9_array_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\n");
            }
            break;
        }
        if(s->left != nil && s->left->type == NIdent && s->left->name != nil &&
           s->right != nil && s->right->type == NClass && s->right->name != nil){
            char *lt = get_expr_type(s->left);
            if(lt == nil || strcmp(lt, "vlong") == 0)
                lt = get_var_class(s->left->name);
            if(lt != nil && is_class_type(lt) && is_subclass(s->right->name, lt)){
                gen_assign_new(s->left->name, lt, s->right);
                break;
            }
        }
        if(s->left != nil && s->left->type == NIdent && s->left->name != nil &&
           s->right != nil && s->right->type == NIdent && s->right->name != nil){
            char *lt = get_expr_type(s->left);
            char *rt = get_expr_type(s->right);
            if(lt != nil && rt != nil && is_class_type(lt) && is_class_type(rt) && is_subclass(rt, lt)){
                print("\tmemmove(&%s, &%s, sizeof(%s_Client));\n", s->left->name, s->right->name, lt);
                break;
            }
        }
        if(s->left != nil && s->left->type == NPropRead && s->left->name != nil && s->left->left != nil){
            char *owner = get_expr_type(s->left->left);
            Node *cnode = find_class(owner);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface){
                    print("\t{ %s_Client *__c = (%s_Client*)&", owner, owner);
                    gen_expr(s->left->left);
                    print(";\n\t\tif(__c->shm_base){ %s_Internal *__i = (%s_Internal*)__c->shm_base;\n", owner, owner);
                    {
                        char *t = get_sym_type(cnode, s->left->name);
                        char field[128];
                        snprint(field, sizeof field, "__i->%s", s->left->name);
                        if(strcmp(t, "char*") == 0){
                            print("\t\t\tfree(__i->%s);\n", s->left->name);
                            print("\t\t\t__i->%s = strdup(", s->left->name);
                            gen_expr(s->right);
                            print(");\n");
                        } else if(find_class(t) && find_class(t)->type == NStruct){
                            print("\t\t\t__i->%s = ", s->left->name);
                            gen_expr(s->right);
                            print(";\n");
                        } else {
                            print("\t\t\t__i->%s = (%s)(", s->left->name, type_cast(t));
                            gen_expr(s->right);
                            print(");\n");
                        }
                        gen_state_store("__i->state", field, s->left->name, t);
                    }
                    print("\t\t} }\n");
                    break;
                }
                if(cnode->type == NStruct){
                    print("\t");
                    gen_expr(s->left->left);
                    print(".%s = ", s->left->name);
                    gen_expr(s->right);
                    print(";\n");
                    break;
                }
            }
        }
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            char *cname = get_var_class(s->left->name);
            Node *cnode = find_class(cname);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface) {
                    print("\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\n\t\tif(__c->shm_base){ %s_Internal *__i = (%s_Internal*)__c->shm_base;\n", cname, cname);
                    {
                        char* t = get_sym_type(cnode, s->name);
                        char field[128];
                        snprint(field, sizeof field, "__i->%s", s->name);
                        if(strcmp(t, "char*") == 0){
                            print("\t\t\tfree(__i->%s);\n", s->name);
                            print("\t\t\t__i->%s = strdup(", s->name);
                            gen_expr(s->right);
                            print(");\n");
                        } else if(find_class(t) && find_class(t)->type == NStruct) {
                            print("\t\t\t__i->%s = ", s->name);
                            gen_expr(s->right);
                            print(";\n");
                        } else {
                            print("\t\t\t__i->%s = (%s)(", s->name, type_cast(t));
                            gen_expr(s->right);
                            print(");\n");
                        }
                        gen_state_store("__i->state", field, s->name, t);
                    }
                    print("\t\t} }\n");
                    break;
                } else if (cnode->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\n");
                    break;
                }
            }
        }
        if(in_class_context && c != nil && s->left != nil && s->left->type == NIdent &&
           s->left->name != nil && !is_local(s->left->name)){
            int mt = member_exists(c, s->left->name);
            if(mt == NProp || mt == NState || mt == NAtomic){
                char *t = get_sym_type(c, s->left->name);
                char field[128];
                if(strcmp(t, "char*") == 0){
                    print("\tfree(self->%s);\n", s->left->name);
                    print("\tself->%s = strdup(", s->left->name);
                    gen_expr(s->right);
                    print(");\n");
                } else if(find_class(t) && find_class(t)->type == NStruct){
                    print("\tself->%s = ", s->left->name);
                    gen_expr(s->right);
                    print(";\n");
                } else {
                    print("\tself->%s = (%s)(", s->left->name, type_cast(t));
                    gen_expr(s->right);
                    print(");\n");
                }
                snprint(field, sizeof field, "self->%s", s->left->name);
                gen_state_store("self->state", field, s->left->name, t);
                break;
            }
        }
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;
    case NReturn:
        if(in_method_body){
            has_return = 1;
            print("\tr->ret = (uintptr)("); gen_expr(s->left); print(");\n\tgoto done;\n");
        } else {
            print("\treturn "); gen_expr(s->left); print(";\n");
        }
        break;
    case NIf:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NIfElse:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        /* Walk the else/elseif chain via ->next */
        if(s->next){
            Node *tail = s->next;
            int closed = 0;
            while(tail){
                if(tail->type == NElseIf){
                    print("\t} else if("); gen_expr(tail->left); print("){\n");
                    for(n = tail->right; n; n = n->next) gen_stmt(c, n);
                } else if(tail->type == NElse){
                    print("\t} else {\n");
                    for(n = tail->left; n; n = n->next) gen_stmt(c, n);
                    print("\t}\n");
                    closed = 1;
                    break;
                }
                tail = tail->next;
            }
            if(!closed)
                print("\t}\n");
        } else {
            print("\t}\n");
        }
        break;
    case NElseIf:
        /* Should not be reached as a top-level statement — handled by NIfElse chain */
        break;
    case NWhile:
        print("\twhile("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NFor:
        /* s->left=init, s->right->left=cond, s->right->right=step, s->right->next=body */
        print("\tfor(");
        if(s->left) gen_expr(s->left);
        print("; ");
        if(s->right->left) gen_expr(s->right->left);
        print("; ");
        if(s->right->right) gen_expr(s->right->right);
        print("){\n");
        for(n = s->right->next; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    default:
        print("\t"); gen_expr(s); print(";\n");
        break;
    }
}

void
gen_enum_def(Node *e)
{
    Node *v;
    int value;

    if(e == nil)
        return;
    print("/* Generated Enum Definition for %s */\n", e->name);
    print("enum {\n");
    value = 0;
    for(v = e->left; v; v = v->next){
        print("\t%s = %d,\n", v->typename, value);
        value++;
    }
    print("};\n");
    print("typedef int %s;\n\n", e->name);
}

void
gen_struct_def(Node *c)
{
    Node *m;
    if(c == nil) return;
    print("/* Generated Struct Definition for %s */\n", c->name);
    print("typedef struct %s %s;\n", c->name, c->name);
    print("struct %s {\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NState)
            print("\t%s %s;\n", map_type(m->typename), m->name);
    }
    print("};\n\n");
}

void
gen_class_header(Node *c)
{
    if(c == nil) return;
    print("/* Generated Client Header for %s %s */\n", c->type == NInterface ? "interface" : "class", c->name);
    print("#ifndef _O9_GEN_%s_H_\n#define _O9_GEN_%s_H_\n\n", c->name, c->name);
    print("typedef struct %s_AsmTable {\n\tvoid *data_cache[64];\n\tvoid (*ctrl_cache[64])(void*);\n} %s_AsmTable;\n\n", c->name, c->name);
    print("typedef struct %s_Client {\n\tint fd;\n\tvoid *shm_base;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n\tchar srvname[64];\n\tchar cachepath[128];\n", c->name);
    print("} %s_Client;\n\n#endif\n\n", c->name);
}

void
gen_internal_fields(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_internal_fields(p);
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic)
            print("\t%s %s;\n", map_type(m->typename), m->name);
        if(m->type == NStream)
            print("\tChannel *%s;\n", m->name);
    }
}

int
count_state_cols(Node *c)
{
    Node *m, *p;
    int n = 0;
    if(c == nil) return 0;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) n += count_state_cols(p);
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic)
            n++;
    }
    return n;
}

void
gen_state_col_names(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_state_col_names(p);
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic)
            print("\"%s\", ", m->name);
    }
}

void
gen_state_store(char *stateexpr, char *fieldexpr, char *name, char *typename)
{
    char *t;
    if(stateexpr == nil || fieldexpr == nil || name == nil || typename == nil)
        return;
    t = map_type(typename);
    if(strcmp(t, "O9Dict") == 0){
        print("\t{ char *__o9s = o9_dict_serialize(&%s); o9_state_set(%s, \"%s\", __o9s); free(__o9s); }\n",
            fieldexpr, stateexpr, name);
    } else if(strcmp(t, "O9Slice") == 0 || (find_class(typename) && find_class(typename)->type == NStruct)){
        /* Complex in-memory values stay in the hot struct for now. */
    } else if(strcmp(t, "char*") == 0){
        print("\to9_state_set(%s, \"%s\", %s ? %s : \"\");\n",
            stateexpr, name, fieldexpr, fieldexpr);
    } else {
        print("\to9_state_set_int(%s, \"%s\", (vlong)(%s));\n",
            stateexpr, name, fieldexpr);
    }
}

static int
has_object_metadata(Node *root)
{
    Node *n;

    for(n = root; n; n = n->next){
        if(n->type == NModule && has_object_metadata(n->left))
            return 1;
        if(n->type == NObject || n->type == NLink)
            return 1;
    }
    return 0;
}

static char*
default_app_name(Node *root)
{
    Node *n;
    char *dot;

    for(n = root; n; n = n->next){
        if(n->type == NModule && n->qname != nil)
            return n->qname;
        if(n->qname != nil){
            dot = strchr(n->qname, '.');
            if(dot != nil)
                return type_slice(n->qname, dot - n->qname);
        }
        if(n->type == NModule && n->left != nil)
            return default_app_name(n->left);
    }
    return "o9app";
}

static void
gen_object_metadata_items(Node *root)
{
    Node *n;
    char *typetext;
    char *target;

    for(n = root; n; n = n->next){
        if(n->type == NModule){
            gen_object_metadata_items(n->left);
            continue;
        }
        if(n->type == NObject){
            typetext = n->typeinfo != nil ? type_render(n->typeinfo) : n->typename;
            print("\t\t{ O9State *__s = o9_state_create_path(__o9root, \"o9object\", \"%s\", __o9_obj_cols, 4);\n",
                n->cname != nil ? n->cname : n->name);
            print("\t\tif(__s){ o9_state_set(__s, \"qname\", \"%s\"); o9_state_set(__s, \"type\", \"%s\"); o9_state_set(__s, \"cname\", \"%s\"); o9_state_set(__s, \"status\", \"declared\"); o9_state_close(__s); } }\n",
                n->qname != nil ? n->qname : n->name,
                typetext != nil ? typetext : "",
                n->typename != nil ? n->typename : "");
        }
        if(n->type == NLink && n->left != nil && n->right != nil){
            target = n->right->qname != nil ? n->right->qname : n->right->name;
            print("\t\t{ O9State *__s = o9_state_create_path(__o9root, \"o9link\", \"%s__%s__%s\", __o9_link_cols, 3);\n",
                n->left->cname != nil ? n->left->cname : n->left->name,
                n->typename != nil ? n->typename : "link",
                n->right->cname != nil ? n->right->cname : n->right->name);
            print("\t\tif(__s){ o9_state_set(__s, \"kind\", \"%s\"); o9_state_set(__s, \"source\", \"%s\"); o9_state_set(__s, \"target\", \"%s\"); o9_state_close(__s); } }\n",
                n->typename != nil ? n->typename : "",
                n->left->qname != nil ? n->left->qname : n->left->name,
                target != nil ? target : "");
        }
    }
}

static void
gen_object_metadata(Node *root)
{
    char *app;

    if(!has_object_metadata(root))
        return;
    app = default_app_name(root);
    print("\t{\n");
    print("\t\tchar *__o9app = \"%s\";\n", app);
    print("\t\tchar __o9root[128];\n");
    print("\t\tchar *__o9_obj_cols[] = { \"qname\", \"type\", \"cname\", \"status\" };\n");
    print("\t\tchar *__o9_link_cols[] = { \"kind\", \"source\", \"target\" };\n");
    print("\t\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    print("\t\to9_ns_app_root(__o9root, sizeof __o9root, __o9app);\n");
    print("\t\to9_ns_ensure_app(__o9root);\n");
    gen_object_metadata_items(root);
    print("\t}\n");
}

void
gen_init_internal_state(Node *c, char *ptr)
{
    Node *m, *p;
    char field[256], state[256];
    if(c == nil || ptr == nil) return;
    snprint(state, sizeof state, "%s->state", ptr);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_init_internal_state(p, ptr);
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic){
            if(m->typename && strncmp(m->typename, "Dict:", 5) == 0)
                print("\to9_dict_init(&%s->%s);\n", ptr, m->name);
            else if(find_class(m->typename) && find_class(m->typename)->type == NStruct)
                print("\tmemset(&%s->%s, 0, sizeof(%s));\n", ptr, m->name, m->typename);
            else
                print("\t%s->%s = 0;\n", ptr, m->name);
            snprint(field, sizeof field, "%s->%s", ptr, m->name);
            gen_state_store(state, field, m->name, m->typename);
        }
    }
}

void
gen_cache_entries(Node *c, char *classname)
{
    /* Emits snprint statements that fill a runtime cache buffer */
    Node *m, *p;
    if(c == nil) return;
    print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"seg:%s\\n\");\n", classname);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_cache_entries(p, classname);
        }
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"d:%%ld:%%ld\\n\", %ldL, (long)o9_offsetof(%s_Internal, %s));\n", o9_hash(m->name), classname, m->name);
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"c:%%ld:%%p\\n\", %ldL, o9_ctrl_%s_%s);\n", o9_hash(m->name), c->name, m->name);
    }
}

void
gen_prop_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_handlers(p);
        }
        if(m->type == NProp){
            char *t = map_type(m->typename);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize to buf */
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&s->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s);\n", m->name);
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(strcmp(c_type_fmt(t), "%s") == 0){
                    /* String property */
                    print("\t\treadstr(r, s->%s ? s->%s : \"\");\n", m->name, m->name);
                } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                    print("\t\treadstr(r, \"<struct>\");\n");
                } else {
                    print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (vlong)s->%s);\n", c_type_fmt(t), m->name);
                    print("\t\treadstr(r, buf);\n");
                }
            }
            print("\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_write_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_write_handlers(p);
        }
        if(m->type == NProp){
            char *t = map_type(m->typename);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: deserialize from write data */
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\to9_dict_deserialize(&s->%s, r->ifcall.data);\n", m->name);
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(strcmp(c_type_fmt(t), "%s") == 0){
                    /* String property */
                    print("\t\tfree(s->%s);\n", m->name);
                    print("\t\ts->%s = strdup(r->ifcall.data);\n", m->name);
                } else {
                    print("\t\ts->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                }
            }
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_prop_create(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_create(p);
        }
        if(m->type == NProp) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    }
}


static ulong emitted_hashes[1024];
static int num_emitted = 0;

void gen_dispatch_cases(Node *c, char *childname) {
    Node *m;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod) {
            ulong h = o9_hash(m->name);
            int i, found = 0;
            for(i=0; i<num_emitted; i++) { if(emitted_hashes[i] == h) { found = 1; break; } }
            if(!found) {
                print("\t\tcase 0x%lux: o9_impl_%s_%s((%s_Internal*)self, m); break;\n", h, c->name, m->name, c->name);
                emitted_hashes[num_emitted++] = h;
            }
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) {
            Node *p = find_class(m->name);
            if(p) gen_dispatch_cases(p, childname);
        }
    }
}

void gen_cleanup_props(Node *c, char *childname) {
    Node *m;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) {
            Node *p = find_class(m->name);
            if(p) gen_cleanup_props(p, childname);
        }
        if(m->type == NProp || m->type == NState) {
            char *t = map_type(m->typename);
            if(strcmp(t, "char*") == 0) {
                print("\tfree(((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(strcmp(t, "O9Dict") == 0) {
                print("\to9_dict_free(&((%s_Internal*)self)->%s);\n", childname, m->name);
            }
        }
    }
}

void
gen_class_server(Node *c)
{
    Node *m, *s;
    int nstatecols;
    print("/* Implementation for class %s (Tiered CSP/9P Model) */\n", c->name);

    nstatecols = count_state_cols(c);
    print("static char *o9_state_cols_%s[] = { ", c->name);
    if(nstatecols > 0)
        gen_state_col_names(c);
    else
        print("nil ");
    print("};\n\n");

    /* 1. State Structure (internal authoritative state) */
    print("typedef struct %s_Internal %s_Internal;\n", c->name, c->name);
    print("struct %s_Internal {\n\tArcLedger ledger;\n\tlong ref;\t/* ARC reference count */\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n\tO9State *state;\n", c->name);
    gen_internal_fields(c);
    print("\tChannel *dispatch_chan;\n");
    print("};\n\n");

    int has_destruct = 0;
    /* 2. Method Implementations (as internal functions) */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod){
            num_locals = 0;
            mark_locals(m->left);
            /* Register param names as locals so gen_expr emits bare names */
            {
                Node *p;
                for(p = m->right; p; p = p->next){
                    if(num_locals < 128) local_vars[num_locals++] = p->name;
                }
            }
            print("static void o9_impl_%s_%s(%s_Internal *self, O9Msg *msg) {\n", c->name, m->name, c->name);
            print("\tO9Reply *r = mallocz(sizeof(O9Reply), 1);\n");
            /* Unpack params from msg->args (packed as vlong array for now) */
            {
                Node *p;
                int pi = 0;
                for(p = m->right; p; p = p->next){
                    print("\t%s %s = ((vlong*)msg->args)[%d];\n", map_type(p->typename), p->name, pi);
                    pi++;
                }
            }
            in_method_body = 1;
            has_return = 0;
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            in_method_body = 0;
            if(has_return) print("done:\n");
            print("\tr->ok = 1;\n\tsendp(msg->replyc, r);\n}\n\n");
			/* Ctrl dispatch thunk (void(*)(void*) for asm cache) */
			{
				int np = 0, pi;
				Node *pn;
				for(pn = m->right; pn; pn = pn->next) np++;
				print("static void o9_ctrl_%s_%s(void *__a){\n", c->name, m->name);
				print("\t%s_Internal *self = (%s_Internal*)((vlong*)__a)[0];\n", c->name, c->name);
				if(np > 0){
						for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
							print("\t%s __arg%d = ((vlong*)__a)[%d];\n", map_type(pn->typename), pi, pi+1);
						print("\tvlong __args[%d];\n", np);
						for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
							print("\t__args[%d] = __arg%d;\n", pi, pi);
					print("\tO9Msg __m = {0x%lux, __args, %d, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name), np);
				} else
					print("\tO9Msg __m = {0x%lux, nil, 0, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name));
				print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
				print("\t{ O9Reply *__r = recvp(__m.replyc); free(__r); }\n");
				print("\tchanfree(__m.replyc);\n}\n\n");
			}
        }
        if(m->type == NDestructor){
            has_destruct = 1;
            num_locals = 0;
            mark_locals(m->left);
            print("static void o9_destruct_%s(%s_Internal *self) {\n", c->name, c->name);
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            print("}\n\n");
        }
    }

    print("static void o9_cleanup_%s(%s_Internal *self) {\n", c->name, c->name);
    if (has_destruct) {
        print("\to9_destruct_%s(self);\n", c->name);
    }
    gen_cleanup_props(c, c->name);
    print("\to9_state_close(self->state);\n");
    print("\tchanfree(self->dispatch_chan);\n");
    print("\tfree(self);\n");
    print("}\n\n");

    /* 2b. ARC attach/destroyfid callbacks */
    {
        ulong _aid = o9_hash(c->name);
        print("static void o9_attach_%s(Req *r) {\n", c->name);
        print("\t%s_Internal *self = r->srv->aux;\n", c->name);
        print("\tself->ledger.entries[0x%lux & 63].count++;\n", _aid);
        print("#ifdef __GNUC__\n\t__sync_fetch_and_add(&self->ref, 1);\n#else\n\tainc(&self->ref);\n#endif\n");
        print("\trespond(r, nil);\n");
        print("}\n\n");
        print("static void o9_destroyfid_%s(Fid *f) {\n", c->name);
        print("\tUSED(f);\n");
        print("\t%s_Internal *self = f->pool->srv->aux;\n", c->name);
        print("\tself->ledger.entries[0x%lux & 63].count--;\n");
        print("#ifdef __GNUC__\n\tif(__sync_sub_and_fetch(&self->ref, 1) == 0){\n#else\n\tif(adec(&self->ref) == 0){\n#endif\n");
    }
    print("\t\tO9Msg *m = mallocz(sizeof(O9Msg), 1);\n");
    print("\t\tm->sel = 0x%lux;\n", o9_hash("destroy"));
    print("\t\tm->replyc = nil;\n");
    print("\t\tsendp(self->dispatch_chan, m);\n");
    print("\t}\n");
    print("}\n\n");

    /* 3. CSP Dispatch Loop */
    print("static void %s_loop(void *v) {\n", c->name);
    print("\t%s_Internal *self = v;\n\tO9Msg *m;\n", c->name);
    print("\tfor(;;){\n\t\tm = recvp(self->dispatch_chan);\n\t\tif(m == nil) continue;\n");
    print("\t\tswitch(m->sel){\n");
    num_emitted = 0;
    gen_dispatch_cases(c, c->name);
    print("\t\tcase 0x%lux: o9_cleanup_%s(self); threadexits(nil); break;\n", o9_hash("destroy"), c->name);
    print("\t\tdefault: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = \"bad selector\"; sendp(m->replyc, r); } break;\n");
    print("\t\t}\n\t}\n}\n\n");

    print("static char o9_app_root_%s[128];\n", c->name);
    print("static char o9_mount_%s[256];\n", c->name);
    print("static char o9_srv_%s[128];\n", c->name);

    /* 4. 9P Fileserver Facade — clone pattern */
    print("static void fsread_%s(Req *r) {\n", c->name);
    print("\tchar buf[1024];\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\t%s_Internal *inst = r->fid->file->aux;\n\n", c->name);
    print("\tif(strcmp(name, \"status\") == 0) { readstr(r, \"running\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ns\") == 0) {\n");
    print("\t\tsnprint(buf, sizeof buf, \"root %%s\\nmount %%s\\nsrv %%s\\nlegacy /srv/%s\\n\", o9_app_root_%s, o9_mount_%s, o9_srv_%s);\n", c->name, c->name, c->name, c->name);
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"__distance__\") == 0 && inst) { snprint(buf, sizeof buf, \"%%d\\n\", inst->distance); readstr(r, buf); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"cache\") == 0) {\n");
    print("\t\tchar cachebuf[4096];\n\t\tchar *p = cachebuf;\n");
    /* Call gen_cache_entries for this class */
    gen_cache_entries(c, c->name);
    print("\t\tUSED(p);\n");
    print("\t\treadstr(r, cachebuf); respond(r, nil); return;\n\t}\n");
    print("\tif(inst == nil) { respond(r, \"clone read\"); return; }\n\n");
    /* Method file reads: check for stored O9Reply in fid aux */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0 && strcmp(m->typename, "void") != 0){
            char *t = map_type(m->typename);
            char *fmt = c_type_fmt(t);
            char *cast = type_cast(t);
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            print("\t\tO9Reply *__o9rep = r->fid->aux;\n");
            print("\t\tif(__o9rep == nil){ respond(r, \"no pending reply\"); return; }\n");
            if(strcmp(fmt, "%s") == 0){
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", (char*) __o9rep->ret);\n");
            } else {
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
            }
            print("\t\tr->fid->aux = nil;\n");
            print("\t\tfree(__o9rep);\n");
            print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            char *fmt = c_type_fmt(t);
            char *cast = type_cast(t);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&inst->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s); respond(r, nil); return;\n\t}\n", m->name);
            } else if(strcmp(fmt, "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", inst->%s ? inst->%s : \"\");\n", m->name, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<struct>\"); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");

    print("static void fswrite_%s(Req *r) {\n", c->name);
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\t%s_Internal *inst = r->fid->file->aux;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) { /* TODO: parse ctl */ respond(r, nil); return; }\n");
    /* Method dispatch: write to method file triggers CSP call */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            int np = 0;
            Node *p;
            for(p = m->right; p; p = p->next) np++;
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            if(np > 0){
                print("\t\tvlong __wargs[%d] = {0};\n", np);
                print("\t\t__wargs[0] = strtoll(r->ifcall.data, nil, 0);\n");
            }
            /* Direct channel send — inst is the Internal struct with dispatch_chan */
            {
                char *a = np > 0 ? "__wargs" : "nil";
                print("\t\t{ O9Msg __wm = {0x%lux, %s, %d, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name), a, np);
                print("\t\tsendp(inst->dispatch_chan, &__wm);\n");
                if(strcmp(m->typename, "void") != 0){
                    /* Return-value method: store O9Reply in fid aux for readback */
                    print("\t\tO9Reply *__o9rep = recvp(__wm.replyc);\n");
                    print("\t\tr->fid->aux = __o9rep;\n");
                } else {
                    /* Void method: discard reply */
                    print("\t\trecvp(__wm.replyc);\n");
                }
                print("\t\tchanfree(__wm.replyc); }\n");
            }
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            if(strcmp(t, "O9Dict") == 0) {
                /* Dict property: deserialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\to9_dict_deserialize(&inst->%s, r->ifcall.data);\n", m->name);
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store("inst->state", field, m->name, m->typename);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else if(strcmp(c_type_fmt(t), "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tfree(inst->%s);\n", m->name);
                print("\t\tinst->%s = strdup(r->ifcall.data);\n", m->name);
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store("inst->state", field, m->name, m->typename);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                /* skip writing to structs via 9P for now */
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store("inst->state", field, m->name, m->typename);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"read only or not found\");\n}\n\n");
    print("Srv o9srv_%s;\n", c->name);
    print("static Tree *%s_tree;\n", c->name);
    print("int %s_create_instance(%s_Internal *inst, char *name) {\n", c->name, c->name);
    print("\tFile *dir = createfile(%s_tree->root, name, nil, 0755, nil);\n", c->name);
    print("\tif(dir == nil) return -1;\n");
    print("\tdir->aux = inst;\n");
    print("\tcreatefile(dir, \"status\", nil, 0444, nil);\n");
    print("\t{ File *__df = createfile(dir, \"__distance__\", nil, 0444, nil); if(__df) __df->aux = inst; }\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic)
            print("\t{ File *__f = createfile(dir, \"%s\", nil, 0666, nil); if(__f) __f->aux = inst; }\n", m->name);
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            char *perm = (strcmp(m->typename, "void") == 0) ? "0222" : "0644";
            print("\t{ File *__f = createfile(dir, \"%s\", nil, %s, nil); if(__f) __f->aux = inst; }\n", m->name, perm);
        }
    }
    print("\treturn 0;\n}\n");
    print("void o9_main_%s(int argc, char **argv) {\n", c->name);
    print("\tchar *__o9app = \"%s\";\n", c->name);
    print("\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    print("\to9_ns_app_root(o9_app_root_%s, sizeof o9_app_root_%s, __o9app);\n", c->name, c->name);
    print("\to9_ns_service_name(o9_srv_%s, sizeof o9_srv_%s, __o9app, \"%s\", \"%s\");\n", c->name, c->name, c->name, c->name);
    print("\to9_ns_object_path(o9_mount_%s, sizeof o9_mount_%s, o9_app_root_%s, \"%s\");\n", c->name, c->name, c->name, c->name);
    print("\to9_ns_ensure_app(o9_app_root_%s);\n", c->name);
    print("\t%s_Internal *s = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
    print("\tmemset(s, 0, sizeof(%s_Internal));\n", c->name);
    print("\ts->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\ts->state = o9_state_create_path(o9_app_root_%s, \"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        c->name, c->name, c->name, c->name, count_state_cols(c));
    gen_init_internal_state(c, "s");
    print("\to9srv_%s.read = fsread_%s;\n\to9srv_%s.write = fswrite_%s;\n", c->name, c->name, c->name, c->name);
    print("\to9srv_%s.aux = s;\n", c->name);
    print("\to9srv_%s.attach = o9_attach_%s;\n", c->name, c->name);
    print("\to9srv_%s.destroyfid = o9_destroyfid_%s;\n", c->name, c->name);
    print("\t%s_tree = alloctree(nil, nil, 0555, nil);\n\to9srv_%s.tree = %s_tree;\n", c->name, c->name, c->name);
    print("\tcreatefile(%s_tree->root, \"clone\", nil, 0222, nil);\n", c->name);
    print("\tcreatefile(%s_tree->root, \"status\", nil, 0444, nil);\n", c->name);
    print("\tcreatefile(%s_tree->root, \"ns\", nil, 0444, nil);\n", c->name);
    print("\tcreatefile(%s_tree->root, \"cache\", nil, 0444, nil);\n", c->name);
    print("\tproccreate(%s_loop, s, 8192);\n", c->name);
    print("\tif(o9_ns_ensure_dir(o9_mount_%s) == 0)\n", c->name);
    print("\t\tthreadpostmountsrv(&o9srv_%s, \"%s\", o9_mount_%s, MREPL);\n", c->name, c->name, c->name);
    print("\telse\n\t\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n}\n", c->name, c->name);
}

ulong
o9_hash(char *str)
{
    ulong hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    return hash & 0xFFFFFFFFul;
}

static void
gen_enums(Node *root)
{
    Node *n;

    for(n = root; n; n = n->next){
        if(n->type == NModule)
            gen_enums(n->left);
        else if(n->type == NEnum)
            gen_enum_def(n);
    }
}

static void
gen_structs(Node *root)
{
    Node *n;

    for(n = root; n; n = n->next){
        if(n->type == NModule)
            gen_structs(n->left);
        else if(n->type == NStruct && n->params == nil)
            gen_struct_def(n);
    }
}

static Node*
gen_classes(Node *root)
{
    Node *n, *last, *sub;

    last = nil;
    for(n = root; n; n = n->next){
        if(n->type == NModule){
            sub = gen_classes(n->left);
            if(sub != nil)
                last = sub;
        } else if(n->type == NClass && n->params == nil){
            gen_class_server(n);
            last = n;
        }
    }
    return last;
}

static Node*
find_main_func(Node *root)
{
    Node *n, *m;

    for(n = root; n; n = n->next){
        if(n->type == NModule){
            m = find_main_func(n->left);
            if(m != nil)
                return m;
        } else if(n->type == NMethod && n->name != nil && strcmp(n->name, "main") == 0)
            return n;
    }
    return nil;
}

static int
main_has_remote_new(Node *main_func)
{
    Node *st;

    if(main_func == nil)
        return 0;
    for(st = main_func->left; st; st = st->next){
        if(st->type == NLocalVar && st->left && st->left->type == NClass
           && st->left->typename
           && (strcmp(st->left->typename, "near") == 0
               || strcmp(st->left->typename, "far") == 0)
           && st->left->right && st->left->right->type == NStringLit)
            return 1;
    }
    return 0;
}

void
codegen(Node *root)
{
    Node *n;
    ClassDef *cd;

    print("/* Generated o9 Source */\n");
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include <o9.h>\n\n");
    print("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    print("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    print("vlong o9_call_args[64];\n");
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n");
    print("#endif\n\n");

    /* 1. Emit headers for ALL known classes/interfaces (local and imported) */
    for(cd = classes; cd; cd = cd->next){
        if(cd->node->params == nil && cd->node->type != NStruct && cd->node->type != NEnum)
            gen_class_header(cd->node);
    }
    Node *main_func = find_main_func(root);
    Node *last = nil;
    int has_remote_new = main_has_remote_new(main_func);

    gen_enums(root);
    gen_structs(root);
    last = gen_classes(root);

    print("void\nthreadmain(int argc, char **argv)\n{\n");
    print("\tUSED(argc); USED(argv);\n");
    gen_object_metadata(root);
    if(last && !has_remote_new){
        print("\to9_main_%s(argc, argv);\n", last->name);
    }
    if(main_func){
        num_locals = 0;
        mark_locals(main_func->left);
        in_class_context = 0;
        for(n = main_func->left; n; n = n->next)
            gen_stmt(nil, n);
    }
    /* Also need a global flag for class init tracking */
    if(main_func && last){
        /* The class server was started by o9_main_Counter above.
         * Variables declared in main() still need o9_Object init if
         * they are class-typed. The var_class table tracks which
         * variables map to which classes. This is a TODO for now. */
    }
    print("\tthreadexitsall(nil);\n}\n");
}

/* Two-pass parser: prescan registers all type names, then yyparse() resolves them */

static void
scan_buffer(char *buf, long len)
{
    long pos = 0;
    int c, i;
    char name[64];
    char *scan_modules[32];
    char *pending_module_name;
    int brace_modules[128];
    int scan_depth, brace_depth, pending_module;

    scan_depth = 0;
    brace_depth = 0;
    pending_module = 0;
    pending_module_name = nil;

    while(pos < len){
        c = (unsigned char)buf[pos++];
        if(c == '{'){
            if(brace_depth < nelem(brace_modules))
                brace_modules[brace_depth++] = pending_module;
            if(pending_module){
                if(scan_depth < nelem(scan_modules))
                    scan_modules[scan_depth++] = pending_module_name;
                pending_module = 0;
                pending_module_name = nil;
            }
            continue;
        }
        if(c == '}'){
            if(brace_depth > 0 && brace_modules[--brace_depth] && scan_depth > 0)
                scan_depth--;
            continue;
        }
        if(isspace(c) || c == ';' || c == '(' || c == ')')
            continue;
        /* Skip literals and comments */
        if(c == '"'){
            while(pos < len && buf[pos] != '"') pos++;
            if(pos < len) pos++;
            continue;
        }
        if(c == '\''){
            if(pos < len && buf[pos] == '\\') pos++;
            if(pos < len) pos++;
            if(pos < len) pos++;
            continue;
        }
        if(c == '/' && pos < len){
            if(buf[pos] == '/'){
                while(pos < len && buf[pos] != '\n') pos++;
                continue;
            }
            if(buf[pos] == '*'){
                pos++;
                while(pos + 1 < len && !(buf[pos] == '*' && buf[pos+1] == '/'))
                    pos++;
                if(pos + 1 < len) pos += 2;
                continue;
            }
        }
        if(isalpha(c) || c == '_'){
            i = 0; name[i++] = c;
            while(i < 63 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_'))
                name[i++] = buf[pos++];
            name[i] = '\0';
            
            if(strcmp(name, "module") == 0){
                char modname[128];
                char *cur, *q;

                while(pos < len && isspace((unsigned char)buf[pos])) pos++;
                i = 0;
                while(i < sizeof(modname)-1 && pos < len &&
                      (isalnum((unsigned char)buf[pos]) || buf[pos] == '_' || buf[pos] == '.'))
                    modname[i++] = buf[pos++];
                modname[i] = '\0';
                cur = scan_depth > 0 ? scan_modules[scan_depth-1] : nil;
                q = qualify_source_name(cur, modname);
                pending_module = 1;
                pending_module_name = q;
            } else if(strcmp(name, "enum") == 0){
                char enumname[64], valname[64];
                char *cur, *q, *cn;
                int depth, value;

                while(pos < len && isspace((unsigned char)buf[pos])) pos++;
                i = 0;
                while(i < sizeof(enumname)-1 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_'))
                    enumname[i++] = buf[pos++];
                enumname[i] = '\0';
                if(i > 0){
                    cur = scan_depth > 0 ? scan_modules[scan_depth-1] : nil;
                    q = qualify_source_name(cur, enumname);
                    cn = mangle_source_name(q);
                    Node *n = mk(NEnum, cn, nil, nil, nil);
                    add_class(cn, n);
                    while(pos < len && isspace((unsigned char)buf[pos])) pos++;
                    if(pos < len && buf[pos] == '{'){
                        pos++;
                        depth = 1;
                        value = 0;
                        while(pos < len && depth > 0){
                            c = (unsigned char)buf[pos++];
                            if(c == '{'){
                                depth++;
                                continue;
                            }
                            if(c == '}'){
                                depth--;
                                continue;
                            }
                            if(depth == 1 && (isalpha(c) || c == '_')){
                                i = 0;
                                valname[i++] = c;
                                while(i < sizeof(valname)-1 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_'))
                                    valname[i++] = buf[pos++];
                                valname[i] = '\0';
                                add_enum_sym(q, cn, valname, value++);
                            }
                        }
                    }
                }
            } else if(strcmp(name, "class") == 0 || strcmp(name, "interface") == 0 || strcmp(name, "struct") == 0){
                int type = (strcmp(name, "interface") == 0) ? NInterface : (strcmp(name, "struct") == 0) ? NStruct : NClass;
                char *cur, *q, *cn;
                while(pos < len && isspace((unsigned char)buf[pos])) pos++;
                i = 0;
                while(i < 63 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_'))
                    name[i++] = buf[pos++];
                name[i] = '\0';
                if(i > 0){
                    cur = scan_depth > 0 ? scan_modules[scan_depth-1] : nil;
                    q = qualify_source_name(cur, name);
                    cn = mangle_source_name(q);
                    Node *n = mk(type, cn, nil, nil, nil);
                    add_class(cn, n);
                }
            } else if(strcmp(name, "import") == 0){
                while(pos < len && buf[pos] != '"') pos++;
                if(pos < len){
                    pos++; /* skip " */
                    i = 0;
                    while(i < 63 && pos < len && buf[pos] != '"')
                        name[i++] = buf[pos++];
                    name[i] = '\0';
                    if(pos < len) pos++; /* skip " */
                    scan_file(name);
                }
            }
        }
    }
}

static void
scan_file(char *path)
{
    int fd;
    long n, total = 0, cap = 8192;
    char *buf;
    int i;

    /* Avoid circular imports */
    for(i=0; i<num_loaded_files; i++)
        if(strcmp(loaded_files[i], path) == 0) return;
    if(num_loaded_files >= 64) return;
    loaded_files[num_loaded_files++] = strdup(path);

    fd = open(path, OREAD);
    if(fd < 0) return;

    buf = malloc(cap);
    while((n = read(fd, buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            buf = realloc(buf, cap);
        }
    }
    close(fd);

    scan_buffer(buf, total);
}

static void
prescan(void)
{
    in_prescan = 1;
    num_loaded_files = 0;
    scan_buffer(input_buf, input_len);
    in_prescan = 0;
    input_pos = 0;
}

static Node*
type_decl_node(Type *t)
{
    char *c;

    if(t == nil)
        return nil;
    if(t->kind == TyName || t->kind == TyApply){
        if(t->name == nil)
            return nil;
        c = mangle_source_name(t->name);
        return find_class(c);
    }
    return nil;
}

static int
validate_type(Type *t, int *errs)
{
    Node *d;
    TypeList *a;
    char *s;
    int arity;

    if(t == nil)
        return 0;
    switch(t->kind){
    case TyName:
        if(type_is_builtin_name(t->name))
            return 0;
        if(is_type_param_name(t->name))
            return 0;
        d = type_decl_node(t);
        if(d == nil){
            s = type_render(t);
            fprint(2, "o9c: error: unknown type '%s'\n", s);
            (*errs)++;
            return -1;
        }
        if(d->params != nil){
            s = type_render(t);
            fprint(2, "o9c: error: generic type '%s' needs %d argument(s)\n",
                s, node_list_len(d->params));
            (*errs)++;
            return -1;
        }
        return 0;
    case TyParam:
        if(!is_type_param_name(t->name)){
            fprint(2, "o9c: error: type parameter '%s' is not in scope\n", t->name);
            (*errs)++;
            return -1;
        }
        return 0;
    case TyApply:
        if(strcmp(t->name, "List") == 0){
            if(type_list_len(t->args) != 1){
                fprint(2, "o9c: error: List needs 1 type argument\n");
                (*errs)++;
            }
        } else if(strcmp(t->name, "Dict") == 0){
            if(type_list_len(t->args) != 2){
                fprint(2, "o9c: error: Dict needs 2 type arguments\n");
                (*errs)++;
            }
        } else {
            d = type_decl_node(t);
            if(d == nil){
                s = type_render(t);
                fprint(2, "o9c: error: unknown generic type '%s'\n", s);
                (*errs)++;
            } else {
                arity = node_list_len(d->params);
                if(arity == 0){
                    s = type_render(t);
                    fprint(2, "o9c: error: type '%s' is not generic\n", s);
                    (*errs)++;
                } else if(arity != type_list_len(t->args)){
                    s = type_render(t);
                    fprint(2, "o9c: error: generic type '%s' needs %d argument(s)\n",
                        s, arity);
                    (*errs)++;
                }
            }
        }
        for(a = t->args; a; a = a->next)
            validate_type(a->type, errs);
        return 0;
    case TyPtr:
    case TyArray:
        return validate_type(t->base, errs);
    }
    return 0;
}

static int
type_is_object_ref(Type *t)
{
    Node *d;

    if(t == nil)
        return 0;
    if(t->kind == TyApply || t->kind == TyName){
        if(strcmp(t->name, "List") == 0 || strcmp(t->name, "Dict") == 0)
            return 0;
        d = type_decl_node(t);
        return d != nil && (d->type == NClass || d->type == NInterface);
    }
    return 0;
}

static Type*
decl_typeinfo(Node *n)
{
    if(n == nil)
        return nil;
    if(n->typeinfo != nil)
        return n->typeinfo;
    if(n->typename != nil)
        return typeinfo_from_legacy(n->typename);
    return nil;
}

static Type*
member_typeinfo(Node *cnode, char *name, int method)
{
    Node *m, *p;
    Type *t;

    if(cnode == nil || name == nil)
        return nil;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            t = member_typeinfo(p, name, method);
            if(t != nil)
                return t;
        }
        if(m->name == nil || strcmp(m->name, name) != 0)
            continue;
        if(method && m->type == NMethod)
            return decl_typeinfo(m);
        if(!method && (m->type == NProp || m->type == NState ||
           m->type == NAtomic || m->type == NSecret || m->type == NCap))
            return decl_typeinfo(m);
    }
    return nil;
}

static Type*
type_list_at(TypeList *list, int idx)
{
    int i;

    i = 0;
    for(; list; list = list->next){
        if(i == idx)
            return list->type;
        i++;
    }
    return nil;
}

static Type*
set_expr_type(Node *e, Type *t)
{
    if(e != nil && t != nil)
        e->typeinfo = t;
    return t;
}

static Type*
collection_get_type(Type *left, char *legacy)
{
    char *last;

    if(left != nil && left->kind == TyApply){
        if(strcmp(left->name, "List") == 0)
            return type_list_at(left->args, 0);
        if(strcmp(left->name, "Dict") == 0)
            return type_list_at(left->args, 1);
    }
    if(legacy != nil && strncmp(legacy, "List:", 5) == 0)
        return typeinfo_from_legacy(legacy + 5);
    if(legacy != nil && strncmp(legacy, "Dict:", 5) == 0){
        last = strrchr(legacy, ':');
        if(last != nil)
            return typeinfo_from_legacy(last + 1);
    }
    return nil;
}

static Type*
annotate_expr_type(Node *e, Node *scope_class)
{
    Node *cnode, *a;
    Type *lt, *rt, *t;
    char *legacy;

    if(e == nil)
        return type_name("void");
    switch(e->type){
    case NIntLit:
        return set_expr_type(e, type_name("int64"));
    case NStringLit:
        return set_expr_type(e, type_name("string"));
    case NCharLit:
        return set_expr_type(e, type_name("char"));
    case NBoolLit:
        return set_expr_type(e, type_name("bool"));
    case NEnumVal:
        if(e->typeinfo != nil)
            return e->typeinfo;
        if(e->typename != nil)
            return set_expr_type(e, typeinfo_from_legacy(e->typename));
        return nil;
    case NClass:
        for(a = e->right; a; a = a->next)
            annotate_expr_type(a, scope_class);
        if(e->typeinfo != nil)
            return e->typeinfo;
        if(e->name != nil)
            return set_expr_type(e, typeinfo_from_legacy(e->name));
        return nil;
    case NIdent:
        t = get_typeinfo_sym(e->name);
        if(t == nil)
            t = member_typeinfo(scope_class, e->name, 0);
        return set_expr_type(e, t);
    case NPropRead:
        lt = annotate_expr_type(e->left, scope_class);
        USED(lt);
        legacy = get_expr_type(e->left);
        cnode = find_class(legacy);
        return set_expr_type(e, member_typeinfo(cnode, e->name, 0));
    case NMsgSend:
        lt = annotate_expr_type(e->left, scope_class);
        for(a = e->right; a; a = a->next)
            annotate_expr_type(a, scope_class);
        legacy = get_expr_type(e->left);
        if(legacy != nil && strncmp(legacy, "List:", 5) == 0){
            if(strcmp(e->name, "Length") == 0)
                return set_expr_type(e, type_name("int64"));
            if(strcmp(e->name, "Add") == 0)
                return set_expr_type(e, type_name("void"));
        }
        if(legacy != nil && strncmp(legacy, "Dict:", 5) == 0 && strcmp(e->name, "Has") == 0)
            return set_expr_type(e, type_name("bool"));
        cnode = find_class(legacy);
        USED(lt);
        return set_expr_type(e, member_typeinfo(cnode, e->name, 1));
    case NArrayGet:
        lt = annotate_expr_type(e->left, scope_class);
        annotate_expr_type(e->right, scope_class);
        legacy = get_expr_type(e->left);
        return set_expr_type(e, collection_get_type(lt, legacy));
    case NAssign:
        lt = annotate_expr_type(e->left, scope_class);
        annotate_expr_type(e->right, scope_class);
        return set_expr_type(e, lt);
    case NReturn:
        return set_expr_type(e, annotate_expr_type(e->left, scope_class));
    case NFuncCall:
        for(a = e->left; a; a = a->next)
            annotate_expr_type(a, scope_class);
        if(e->name != nil && strcmp(e->name, "print") == 0)
            return set_expr_type(e, type_name("void"));
        return nil;
    case NChanSend:
    case NChanRecv:
    case NChanTry:
        annotate_expr_type(e->left, scope_class);
        annotate_expr_type(e->right, scope_class);
        return set_expr_type(e, type_name("void"));
    case NAdd:
    case NSub:
    case NMul:
    case NDiv:
    case NMod:
    case NBitAnd:
    case NBitOr:
    case NBitXor:
    case NLshift:
    case NRshift:
        annotate_expr_type(e->left, scope_class);
        annotate_expr_type(e->right, scope_class);
        return set_expr_type(e, type_name("int64"));
    case NNeg:
    case NBitNot:
        annotate_expr_type(e->left, scope_class);
        return set_expr_type(e, type_name("int64"));
    case NEq:
    case NNe:
    case NLt:
    case NLe:
    case NGt:
    case NGe:
    case NAnd:
    case NOr:
        annotate_expr_type(e->left, scope_class);
        annotate_expr_type(e->right, scope_class);
        return set_expr_type(e, type_name("bool"));
    case NNot:
        annotate_expr_type(e->left, scope_class);
        return set_expr_type(e, type_name("bool"));
    }
    rt = e->typeinfo;
    return rt;
}

static void
add_decl_type_sym(Node *n)
{
    if(n == nil || n->name == nil || n->typename == nil)
        return;
    add_type_sym_typed(n->name, n->typename, decl_typeinfo(n));
    if(is_class_type(n->typename))
        add_var_class(n->name, n->typename);
}

static void
add_decl_type_syms(Node *n)
{
    for(; n; n = n->next)
        add_decl_type_sym(n);
}

/* Type checker: walks the AST and validates all member references */
/* Returns number of errors (0 = clean) */

static int
member_exists(Node *cnode, char *name)
{
    Node *m, *p;
    if(cnode == nil) return -1;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p && member_exists(p, name) >= 0) return 2;
        }
        if(m->name && strcmp(m->name, name) == 0) return m->type;
    }
    return -1;
}

static void
typecheck_expr(Node *e, Node *scope_class, int *errs)
{
    if(e == nil) return;
    
    switch(e->type){
    case NProp:
    case NState:
    case NAtomic:
    case NSecret:
    case NCap:
    case NInherit:
        validate_type(e->typeinfo, errs);
        break;
    case NMethod:
        validate_type(e->typeinfo, errs);
        break;
    case NObject:
        validate_type(e->typeinfo, errs);
        if(!type_is_object_ref(e->typeinfo)){
            fprint(2, "o9c: error: object '%s' must have class or interface type\n",
                e->qname != nil ? e->qname : e->name);
            (*errs)++;
        }
        break;
    case NLink:
        if(e->left == nil || e->left->qname == nil || resolve_object_sym(e->left->qname) == nil){
            fprint(2, "o9c: error: link source '%s' is not a declared object\n",
                e->left && e->left->qname ? e->left->qname : e->name);
            (*errs)++;
        }
        if(e->right == nil || e->right->qname == nil || resolve_object_sym(e->right->qname) == nil){
            fprint(2, "o9c: error: link target '%s' is not a declared object\n",
                e->right && e->right->qname ? e->right->qname : "<nil>");
            (*errs)++;
        }
        break;
    case NPropRead:
        annotate_expr_type(e, scope_class);
        /* Check: prop read, must not be a method */
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            char *vt = get_expr_type(e->left);
            if(vt != nil && (strncmp(vt, "List:", 5) == 0 || strncmp(vt, "Dict:", 5) == 0))
                break;
            if(cn == nil && vt != nil && find_class(vt) != nil)
                cn = vt;
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\n", e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: '%s' is a method, not a property\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NMsgSend:
        annotate_expr_type(e, scope_class);
        /* Check: method call, must be a method, not a property */
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            char *vt = get_expr_type(e->left);
            if(vt != nil && strncmp(vt, "List:", 5) == 0){
                if(strcmp(e->name, "Add") != 0 && strcmp(e->name, "Length") != 0){
                    fprint(2, "o9c: error: List has no method '%s'\n", e->name);
                    (*errs)++;
                }
                break;
            }
            if(vt != nil && strncmp(vt, "Dict:", 5) == 0){
                if(strcmp(e->name, "Has") != 0){
                    fprint(2, "o9c: error: Dict has no method '%s'\n", e->name);
                    (*errs)++;
                }
                break;
            }
            if(cn == nil && vt != nil && find_class(vt) != nil)
                cn = vt;
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\n", e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt >= 0 && mt != NMethod){
                    fprint(2, "o9c: error: '%s' is a property, not a method\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NAssign:
        annotate_expr_type(e, scope_class);
        if(e->name != nil && e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            if(cn && find_class(cn)){
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: cannot assign to method '%s'\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        if(e->name == nil && e->left && e->left->type == NIdent && e->left->name && e->right){
            char *lt = get_expr_type(e->left);
            char *rt = nil;
            if(e->right->type == NIdent && e->right->name)
                rt = get_expr_type(e->right);
            else if(e->right->type == NClass && e->right->name)
                rt = e->right->name;
            else
                rt = get_expr_type(e->right);
            if(lt != nil && is_enum_type(lt) && (rt == nil || strcmp(lt, rt) != 0)){
                fprint(2, "o9c: error: cannot assign %s to enum %s\n", rt ? rt : "<unknown>", lt);
                (*errs)++;
            }
            if(lt != nil && rt != nil && is_class_type(lt) && is_class_type(rt) && !is_subclass(rt, lt)){
                fprint(2, "o9c: error: cannot assign %s to %s\n", rt, lt);
                (*errs)++;
            }
        }
        if(e->name == nil && e->left && e->left->type == NPropRead && e->left->left && e->right){
            char *owner = get_expr_type(e->left->left);
            Node *cnode = find_class(owner);
            char *lt = get_sym_decl_type(cnode, e->left->name);
            char *rt = get_expr_type(e->right);
            if(lt != nil && is_enum_type(lt) && (rt == nil || strcmp(lt, rt) != 0)){
                fprint(2, "o9c: error: cannot assign %s to enum %s\n", rt ? rt : "<unknown>", lt);
                (*errs)++;
            }
        }
        break;
    case NLocalVar:
        validate_type(e->typeinfo, errs);
        add_decl_type_sym(e);
        annotate_expr_type(e->left, scope_class);
        if(e->typename && e->left && is_enum_type(e->typename)){
            char *rt = get_expr_type(e->left);
            if(rt == nil || strcmp(e->typename, rt) != 0){
                fprint(2, "o9c: error: cannot initialize enum %s with %s\n",
                    e->typename, rt ? rt : "<unknown>");
                (*errs)++;
            }
        }
        /* Check legacy-only typename is a known type if no structured type was attached. */
        if(e->typeinfo == nil && e->typename && !is_primitive(e->typename) && find_class(e->typename) == nil){
            fprint(2, "o9c: error: unknown type '%s'\n", e->typename);
            (*errs)++;
        }
        break;
    default:
        annotate_expr_type(e, scope_class);
        break;
    }
}

static void
check_node(Node *n, Node *scope_class, int *errs)
{
    Node *c;
    TypeSym *mark;

    if(n == nil) return;
    /* Walk the next chain at this level */
    for(c = n; c; c = c->next){
        if(c->type == NModule){
            check_node(c->left, scope_class, errs);
            continue;
        }
        if(c->type == NEnum)
            continue;
        if(c->type == NClass || c->type == NStruct || c->type == NInterface){
            push_type_params(c->params);
            check_node(c->left, c, errs);
            pop_type_params();
            continue;
        }
        if(c->type == NMethod){
            typecheck_expr(c, scope_class, errs);
            check_node(c->right, scope_class, errs);
            mark = mark_type_syms();
            add_decl_type_syms(c->right);
            check_node(c->left, scope_class, errs);
            restore_type_syms(mark);
            continue;
        }
        typecheck_expr(c, scope_class, errs);
        check_node(c->left, scope_class, errs);
        check_node(c->right, scope_class, errs);
    }
}

static int
typecheck(Node *root)
{
    int errors = semantic_errors;
    
    check_node(root, nil, &errors);
    
    return errors;
}

static char*
node_kind(int type)
{
    switch(type){
    case NClass: return "NClass";
    case NProp: return "NProp";
    case NState: return "NState";
    case NAtomic: return "NAtomic";
    case NStream: return "NStream";
    case NSecret: return "NSecret";
    case NCap: return "NCap";
    case NInherit: return "NInherit";
    case NMethod: return "NMethod";
    case NDestructor: return "NDestructor";
    case NIdent: return "NIdent";
    case NType: return "NType";
    case NChanSend: return "NChanSend";
    case NChanRecv: return "NChanRecv";
    case NChanTry: return "NChanTry";
    case NAssign: return "NAssign";
    case NReturn: return "NReturn";
    case NIntLit: return "NIntLit";
    case NStringLit: return "NStringLit";
    case NCharLit: return "NCharLit";
    case NBoolLit: return "NBoolLit";
    case NAdd: return "NAdd";
    case NSub: return "NSub";
    case NMul: return "NMul";
    case NDiv: return "NDiv";
    case NMod: return "NMod";
    case NEq: return "NEq";
    case NNe: return "NNe";
    case NLt: return "NLt";
    case NLe: return "NLe";
    case NGt: return "NGt";
    case NGe: return "NGe";
    case NAnd: return "NAnd";
    case NOr: return "NOr";
    case NBitAnd: return "NBitAnd";
    case NBitOr: return "NBitOr";
    case NBitXor: return "NBitXor";
    case NLshift: return "NLshift";
    case NRshift: return "NRshift";
    case NNot: return "NNot";
    case NBitNot: return "NBitNot";
    case NNeg: return "NNeg";
    case NIf: return "NIf";
    case NIfElse: return "NIfElse";
    case NElse: return "NElse";
    case NElseIf: return "NElseIf";
    case NWhile: return "NWhile";
    case NLocalVar: return "NLocalVar";
    case NMsgSend: return "NMsgSend";
    case NPropRead: return "NPropRead";
    case NFuncCall: return "NFuncCall";
    case NFor: return "NFor";
    case NArrayGet: return "NArrayGet";
    case NArraySet: return "NArraySet";
    case NInterface: return "NInterface";
    case NStruct: return "NStruct";
    case NEnum: return "NEnum";
    case NEnumVal: return "NEnumVal";
    case NImport: return "NImport";
    case NObject: return "NObject";
    case NLink: return "NLink";
    case NModule: return "NModule";
    case NTypeParam: return "NTypeParam";
    }
    return "NUnknown";
}

static void
dump_indent(int depth)
{
    int i;

    for(i = 0; i < depth; i++)
        print("  ");
}

static void
dump_params(Node *params)
{
    Node *p;
    int first;

    if(params == nil)
        return;
    print(" params=");
    first = 1;
    for(p = params; p; p = p->next){
        if(!first)
            print(",");
        if(p->name != nil)
            print("%s", p->name);
        first = 0;
    }
}

static void
dump_node_line(Node *n, int depth, char *label)
{
    char *rendered, *dumped;

    dump_indent(depth);
    if(label != nil)
        print("%s ", label);
    print("%s", node_kind(n->type));
    if(n->name != nil)
        print(" name=%s", n->name);
    if(n->typename != nil)
        print(" typename=%s", n->typename);
    if(n->qname != nil)
        print(" qname=%s", n->qname);
    if(n->cname != nil)
        print(" cname=%s", n->cname);
    dump_params(n->params);
    if(n->typeinfo != nil){
        rendered = type_render(n->typeinfo);
        dumped = type_dump(n->typeinfo);
        print(" type=%s typedump=%s", rendered, dumped);
    }
    print("\n");
}

static void
dump_ast_nodes(Node *n, int depth, char *label)
{
    for(; n; n = n->next){
        dump_node_line(n, depth, label);
        if(n->left != nil)
            dump_ast_nodes(n->left, depth + 1, "left");
        if(n->right != nil)
            dump_ast_nodes(n->right, depth + 1, "right");
    }
}

static void
dump_ast(Node *root)
{
    dump_ast_nodes(root, 0, nil);
}

int
main(int argc, char **argv)
{
    long n, total = 0, cap = 8192;
    int dumpast, i;

    dumpast = 0;
    for(i = 1; i < argc; i++)
        if(strcmp(argv[i], "-ast") == 0)
            dumpast = 1;
    
    input_buf = malloc(cap);
    if(input_buf == nil) sysfatal("malloc: input buffer");
    while((n = read(0, input_buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            input_buf = realloc(input_buf, cap);
            if(input_buf == nil) sysfatal("realloc: input buffer");
        }
    }
    input_len = total;
    
    prescan();
    
    if(yyparse() == 0){
        if(typecheck(ast_root) == 0){
            if(dumpast)
                dump_ast(ast_root);
            else
                codegen(ast_root);
        }
    } else {
        fprint(2, "o9c: parse failed\n");
    }
    exits(nil);
    return 0;
}
