%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>
#include "o9_type.h"

typedef struct Node Node;
typedef struct TypeBind TypeBind;
typedef struct TypedMember TypedMember;

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
    NTypeParam,
    NSelfCall,
    NDelete,
    NTry,
    NDefer
};

enum {
    NFAbstract = 1<<0,
    NFMethodDecl = 1<<1,
    NFSelfCalled = 1<<2,
    NFPrivate = 1<<3	/* class-scoped; not reachable through the app facade */
};

struct Node {
    int type;
    int flags;
    int line;
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

struct TypeBind {
    char *name;
    Type *type;
    TypeBind *next;
};

struct TypedMember {
    Node *node;
    Node *owner;
    int kind;
    Type *type;
    TypeBind *bindings;
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
static int cur_line = 1;            /* current source line for diagnostics */
static int sem_line;                /* line of the node being semantically checked */
static Node *gen_class;             /* class whose method body is being generated */
static char last_caps_ident[128];   /* capitalized ident not in type registry */
static int last_caps_line;

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
static Node* mk_secret_field(Node *tn, char *name);
static void o9_note_registered(char *name);
static int member_exists(Node *cnode, char *name);
Node* append_node(Node *list, Node *node);
char* map_type(char *t);
char* get_sym_type(Node *c, char *name);
char* get_sym_decl_type(Node *c, char *name);
char* get_method_type(Node *c, char *name);
char* get_expr_type(Node *e);
static Type* typeinfo_from_legacy(char *t);
static Node* type_decl_node(Type *t);
static Type* decl_typeinfo(Node *n);
static Node* member_node(Node *cnode, char *name, int method);
static int method_has_body(Node *m);
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
static Type* type_list_at(TypeList *list, int idx);
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
    int r;
    static int depth;
    if(sub == nil || parent == nil) return 0;
    if(strcmp(sub, parent) == 0) return 1;
    if(depth > 64) return 0;	/* inheritance cycle; reported by check_inheritance_contract */
    c = find_class(sub); if(c == nil) return 0;
    depth++;
    r = 0;
    for(m = c->left; m && !r; m = m->next) if(m->type == NInherit) { if(strcmp(m->name, parent) == 0 || is_subclass(m->name, parent)) r = 1; }
    depth--;
    return r;
}

/* Builtin functions lowered to runtime helpers.  Class methods of the
 * same name shadow these inside method bodies. */
typedef struct Builtin Builtin;
struct Builtin {
    char *name;
    char *runtime;
    int argc;
    char *ret;
    char *args[3];
};
static Builtin builtins[] = {
    {"len",       "o9_str_len",   1, "int64",  {"string", nil}},
    {"cmp",       "o9_str_cmp",   2, "int64",  {"string", "string"}},
    {"cat",       "o9_str_cat",   2, "string", {"string", "string"}},
    {"readfile",  "o9_readfile",  1, "string", {"string", nil}},
    {"writefile", "o9_writefile", 2, "int64",  {"string", "string"}},
    {"readline",  "o9_readline",  0, "string", {nil, nil}},
    {"serve",     "o9_serve",     0, "void",   {nil, nil}},
    /* Tabula constructors: new_tab(name, "cols") / open_tab(path) */
    {"new_tab",   "o9_tab_new",   2, "Tabula", {"string", "string"}},
    {"open_tab",  "o9_tab_open",  1, "Tabula", {"string", nil}},
    /* export(name, tab): publish a Tabula into the served-tree exports/
     * dir (mutable app file tree) — reachable through the mount. */
    {"export",    "o9_export_tab",2, "void",   {"string", "Tabula"}},
    /* fail(msg): error-as-value — sets the method error and returns.
     * Special-cased in gen_stmt (goto done); table entry is for typecheck. */
    {"fail",      "o9_fail",      1, "void",   {"string", nil}},
    {"lookup",    "o9_lookup_client", 1, "void", {"string", nil}},
    /* code as data: fire a shell-identical ctl line at any handle.
     * "object" marks a class-typed slot, passed by address. */
    {"send",      "o9_send",      2, "string", {"object", "string"}},
    /* crypto (monocypher): every key/sig/digest/blob is lowercase hex */
    {"keygen",    "o9_keygen",    0, "string", {nil, nil}},
    {"pubkey",    "o9_pubkey",    1, "string", {"string", nil}},
    {"sign",      "o9_sign",      2, "string", {"string", "string"}},
    {"verify",    "o9_verify",    3, "int64",  {"string", "string", "string"}},
    {"hash",      "o9_digest",    1, "string", {"string", nil}},
    {"mac",       "o9_mac",       2, "string", {"string", "string"}},
    {"passkey",   "o9_passkey",   2, "string", {"string", "string"}},
    {"encrypt",   "o9_encrypt",   2, "string", {"string", "string"}},
    {"decrypt",   "o9_decrypt",   2, "string", {"string", "string"}},
    {"xpubkey",   "o9_xpubkey",   1, "string", {"string", nil}},
    {"exchange",  "o9_exchange",  2, "string", {"string", "string"}},
};

static Builtin*
find_builtin(char *name)
{
    int i;
    if(name == nil)
        return nil;
    for(i = 0; i < nelem(builtins); i++)
        if(strcmp(builtins[i].name, name) == 0)
            return &builtins[i];
    return nil;
}

/* Class whose own members define a bodied method `name`, following the
 * inheritance chain from c.  The o9_self_ wrapper lives on that class. */
static Node*
method_owner(Node *c, char *name)
{
    Node *m, *p, *r;
    static int depth;

    if(c == nil || name == nil || depth > 64)
        return nil;
    for(m = c->left; m; m = m->next)
        if(m->type == NMethod && m->name != nil && strcmp(m->name, name) == 0 && method_has_body(m))
            return c;
    depth++;
    r = nil;
    for(m = c->left; m && r == nil; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            r = method_owner(p, name);
        }
    }
    depth--;
    return r;
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
    case NSelfCall: if(gen_class != nil) return get_method_type(gen_class, e->name); return "vlong";
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

/* Is name a module qualifier? True when any registered class lives under
 * name__ (bare or qualified against the current module). */
static int
is_module_prefix(char *name)
{
    ClassDef *cd;
    char pfx[256];
    char *q, *c;
    int n;

    if(name == nil || name[0] == '\0')
        return 0;
    n = snprint(pfx, sizeof pfx, "%s__", mangle_source_name(name));
    for(cd = classes; cd; cd = cd->next)
        if(strncmp(cd->name, pfx, n) == 0)
            return 1;
    q = qualify_source_name(current_module, name);
    c = mangle_source_name(q);
    n = snprint(pfx, sizeof pfx, "%s__", c);
    for(cd = classes; cd; cd = cd->next)
        if(strncmp(cd->name, pfx, n) == 0)
            return 1;
    return 0;
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
            fprint(2, "o9c: error: line %d: duplicate enum value '%s'\n", cur_line, qbuf);
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
                fprint(2, "o9c: error: line %d: duplicate enum value '%s' in %s\n", cur_line, v->name, enumtype);
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
            fprint(2, "o9c: error: line %d: duplicate object '%s'\n", cur_line, n->qname);
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
type_storage_for_codegen(Type *t)
{
    Node *d;
    char *p, *c, *r;
    int n;

    if(t == nil)
        return "void";
    if(t->kind == TyName){
        if(strcmp(t->name, "chan") == 0)
            return "Channel*";
        if(strcmp(t->name, "Tabula") == 0)
            return "O9Tabula*";	/* a handle, not an embedded value */
        p = type_builtin_plan9(t->name);
        if(p != nil)
            return p;
        d = type_decl_node(t);
        if(d != nil){
            if(d->type == NEnum)
                return "int";
            c = type_cname(t);
            if(d->type == NClass || d->type == NInterface){
                n = strlen(c) + 8;
                r = malloc(n);
                if(r == nil)
                    sysfatal("malloc: type_storage_for_codegen");
                snprint(r, n, "%s_Client", c);
                return r;
            }
            return c;
        }
        return type_cname(t);
    }
    if(t->kind == TyParam)
        return "void*";
    if(t->kind == TyApply){
        if(strcmp(t->name, "List") == 0)
            return "O9Slice";
        if(strcmp(t->name, "Dict") == 0)
            return "O9Dict";
        d = type_decl_node(t);
        c = type_cname(type_name(t->name));
        if(d != nil && (d->type == NClass || d->type == NInterface)){
            n = strlen(c) + 8;
            r = malloc(n);
            if(r == nil)
                sysfatal("malloc: generic storage");
            snprint(r, n, "%s_Client", c);
            return r;
        }
        if(d != nil && d->type == NEnum)
            return "int";
        return c;
    }
    if(t->kind == TyArray)
        return "O9Slice";
    if(t->kind == TyPtr){
        p = type_storage_for_codegen(t->base);
        n = strlen(p) + 2;
        r = malloc(n);
        if(r == nil)
            sysfatal("malloc: pointer storage");
        snprint(r, n, "%s*", p);
        return r;
    }
    return type_render(t);
}

static char*
type_fmt_for_codegen(Type *t)
{
    Node *d;
    char *f;

    if(t == nil)
        return "%lld";
    if(t->kind == TyName){
        f = type_builtin_fmt(t->name);
        if(f != nil && f[0] != 0)
            return f;
        d = type_decl_node(t);
        if(d != nil && d->type == NEnum)
            return "%d";
    }
    if(t->kind == TyParam || t->kind == TyPtr || t->kind == TyArray ||
       t->kind == TyApply)
        return "%p";
    return "%lld";
}

static char*
type_cast_for_codegen(Type *t)
{
    Node *d;
    char *s;

    if(t == nil)
        return "vlong";
    s = type_storage_for_codegen(t);
    if(strcmp(s, "char*") == 0)
        return "char*";
    if(strcmp(s, "vlong") == 0 || strcmp(s, "uvlong") == 0 ||
       strcmp(s, "long") == 0 || strcmp(s, "ulong") == 0 ||
       strcmp(s, "int") == 0 || strcmp(s, "uint") == 0 ||
       strcmp(s, "short") == 0 || strcmp(s, "ushort") == 0 ||
       strcmp(s, "char") == 0 || strcmp(s, "uchar") == 0)
        return s;
    d = type_decl_node(t);
    if(d != nil && d->type == NStruct)
        return "";
    return "vlong";
}

static int
type_is_collection(Type *t, char *name)
{
    return t != nil && t->kind == TyApply && t->name != nil &&
        strcmp(t->name, name) == 0;
}

static int
type_is_void(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "void") == 0;
}

static int
storage_pointerish(char *s)
{
    if(s == nil)
        return 0;
    return strcmp(s, "void*") == 0 || strcmp(s, "char*") == 0 ||
        strchr(s, '*') != nil;
}

static int
type_storage_pointerish(Type *t)
{
    return storage_pointerish(type_storage_for_codegen(t));
}

static int
type_is_class_ref(Type *t)
{
    Node *d;

    d = type_decl_node(t);
    return d != nil && (d->type == NClass || d->type == NInterface);
}

char*
map_type(char *t)
{
    return type_storage_for_codegen(typeinfo_from_legacy(t));
}

char*
c_type_fmt(char *t)
{
    if(t == nil) return "%lld";
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
    return type_fmt_for_codegen(typeinfo_from_legacy(t));
}

char*
type_cast(char *t)
{
    if(t == nil) return "vlong";
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    if(find_class(t) && find_class(t)->type == NStruct) return "";
    return type_cast_for_codegen(typeinfo_from_legacy(t));
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
    if(strcmp(t, "Tabula") == 0) return 1;	/* handle type, primitive-like decl */
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
            return type_storage_for_codegen(m->typeinfo);
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
%token TCLASS TINTERFACE TSTRUCT TENUM TMODULE TIMPORT TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TLIST TNIL TABSTRACT TDELETE
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TOBJECT TLINK TREF TREPLICA TTRUE TFALSE TARROW
%token TPUBLIC TPRIVATE
%token TTRY TDEFER
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
 
%type <node> program top_levels top_level class_decl class_head interface_decl interface_head struct_decl struct_head enum_decl enum_vals enum_val module_decl module_head import_decl object_decl link_decl member_list member member_body var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename name_ref type_name_ref decl_name generic_name enum_name member_name param_list param call_args call_arg func_top_level for_init for_cond for_step else_clause generic_opt generic_names link_kind abstract_opt
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

member_name:
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
    TOBJECT typename member_name ';'
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

abstract_opt:
    /* empty */ { $$ = nil; }
    | TABSTRACT { $$ = mk(NIdent, "abstract", nil, nil, nil); }
    ;

class_head:
    abstract_opt TCLASS decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $3->name);
        name = mangle_source_name(source);
        $$ = mk(NClass, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $4;
        if($1 != nil)
            $$->flags |= NFAbstract;
        push_type_params($4);
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
    member_body            { $$ = $1; }
    | TPUBLIC member_body  { $$ = $2; }  /* public is the default; explicit form */
    | TPRIVATE member_body {
        /* class-scoped: not reachable through the app facade, callable
         * only from the declaring class's own methods.  A secret field
         * desugars to a small list (blob + seal/open); mark every node
         * in it private so the accessors are private too. */
        Node *n;
        for(n = $2; n != nil; n = n->next)
            n->flags |= NFPrivate;
        $$ = $2;
    }
    ;

member_body:
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
    TSTATE typename member_name ';'
    {
        $$ = mk_typed(NState, $3->name, $2, nil, nil);
    }
    ;

prop_decl:
    TPROP typename member_name ';'
    {
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
    }
    ;

atomic_decl:
    TATOMIC typename member_name ';'
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
    TSECRET typename member_name ';'
    {
        $$ = mk_secret_field($2, $3->name);
    }
    ;

cap_decl:
    TCAP typename member_name ';'
    {
        /* `cap` is removed — and not reserved for later. Capabilities
         * are already provided one layer down: a 9P fid / namespace mount
         * IS an unforgeable handle to a resource, granted, delegated, and
         * attenuated by namespace composition, over pubkey identity. A
         * language-level `cap` field would duplicate (or fight) that OS
         * mechanism — un-o9. Authority to reach an object = whether it's
         * in your namespace; a bearer token = a `secret` field + a check.
         * There is no gap for a `cap` keyword to fill. */
        fprint(2, "o9c: error: 'cap' is not a language keyword. "
            "Capabilities in o9 are 9P fids / namespace mounts (an "
            "unforgeable handle granted by whoever mounts it), over "
            "pubkey identity — not a field type. Use a namespace mount "
            "for authority, or a `secret` field for a bearer token.\n");
        semantic_errors++;
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
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
    TABSTRACT TMETHOD typename member_name '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $4->name, $3, nil, $6);
        $$->flags |= NFAbstract|NFMethodDecl;
    }
    | TABSTRACT TMETHOD TIDENT '(' param_list ')' ';'
    {
        $$ = mk(NMethod, $3->name, "void", nil, $5);
        $$->flags |= NFAbstract|NFMethodDecl;
    }
    |
    TMETHOD typename member_name '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $3->name, $2, $8, $5);
    }
    | TMETHOD typename member_name '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $8, nil);
        $$ = mk_typed(NMethod, $3->name, $2, body, $5);
    }
    | TMETHOD typename member_name '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $3->name, $2, nil, $5);
        $$->flags |= NFMethodDecl;
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
        $$->flags |= NFMethodDecl;
    }
    | TMETHOD TTYPEIDENT '(' param_list ')' '{' stmt_list '}'
    {
        /* Constructor: class names lex as TTYPEIDENT (prescan registers them),
         * so method Counter(...) never matches the TIDENT rules above. */
        $$ = mk(NMethod, $2->name, "void", $7, $4);
    }
    ;

inherit_decl:
    typename ';'
    {
        $$ = mk_typed(NInherit, $1->name, $1, nil, nil);
    }
    ;

var_decl:
    typename member_name ';'
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
    typename member_name
    {
        $$ = mk_typed(NProp, $2->name, $1, nil, nil);
    }
    ;

destructor_decl:
    '~' TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NDestructor, $2->name, nil, $6, nil);
    }
    | '~' TTYPEIDENT '(' ')' '{' stmt_list '}'
    {
        /* Class names lex as TTYPEIDENT (prescan registers them) */
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
    typename member_name ';' { $$ = mk_typed(NLocalVar, $2->name, $1, nil, nil); if(is_class_type($1->name)) add_var_class($2->name, $1->name); }
    | typename member_name TEQ expr ';' { $$ = mk_typed(NLocalVar, $2->name, $1, $4, nil); if(is_class_type($1->name)) add_var_class($2->name, $1->name); }
    | expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    | TDEFER expr ';' { $$ = mk(NDefer, nil, nil, $2, nil); }
    | TDELETE TIDENT ';' { $$ = mk(NDelete, $2->name, nil, $2, nil); }
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
    | expr '.' member_name {
        $$ = mk(NPropRead, $3->name, nil, $1, nil);
    }
    | expr '.' member_name '(' call_args ')' {
        $$ = mk(NMsgSend, $3->name, nil, $1, $5);
    }
    | expr '[' expr ']' {
        $$ = mk(NArrayGet, nil, nil, $1, $3);
    }
    | TIDENT '(' call_args ')' {
        /* Bare call: sibling method on the enclosing class (implicit self) */
        $$ = mk(NSelfCall, $1->name, nil, nil, $3);
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
    | TTRY expr {
        /* try expr: propagate the callee's error out of this method */
        Node *n = mk(NTry, nil, nil, $2, nil);
        n->typeinfo = $2->typeinfo;	/* try yields the success value's type */
        $$ = n;
    }
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
    n->line = cur_line;
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

/* secret string N; — sealed storage plus key-armed accessors:
 *
 *   string N__blob;
 *   method void seal_N(string key, string v) { N__blob = encrypt(key, v); }
 *   method string open_N(string key) { return decrypt(key, N__blob); }
 *
 * The declared field never exists as plaintext storage and no plain
 * accessor is generated, so every visible form of the object — shm,
 * /srv data, persisted rows, send replies — carries the AEAD blob.
 * Key custody stays with the caller (passkey/exchange/keygen).
 * Non-string secrets stay NSecret; typecheck refuses them. */
static Node*
mk_secret_field(Node *tn, char *name)
{
    char blob[192], seal[200], open[200];
    Node *fld, *sealm, *openm, *params, *args, *body;

    if(tn == nil || tn->name == nil || strcmp(tn->name, "string") != 0)
        return mk_typed(NSecret, name, tn, nil, nil);

    snprint(blob, sizeof blob, "%s__blob", name);
    snprint(seal, sizeof seal, "seal_%s", name);
    snprint(open, sizeof open, "open_%s", name);

    fld = mk(NProp, blob, "string", nil, nil);

    params = mk(NProp, "key", "string", nil, nil);
    params->next = mk(NProp, "v", "string", nil, nil);
    args = mk(NIdent, "key", nil, nil, nil);
    args->next = mk(NIdent, "v", nil, nil, nil);
    body = mk(NAssign, nil, nil,
        mk(NIdent, blob, nil, nil, nil),
        mk(NSelfCall, "encrypt", nil, nil, args));
    sealm = mk(NMethod, seal, "void", body, params);

    params = mk(NProp, "key", "string", nil, nil);
    args = mk(NIdent, "key", nil, nil, nil);
    args->next = mk(NIdent, blob, nil, nil, nil);
    body = mk(NReturn, nil, nil,
        mk(NSelfCall, "decrypt", nil, nil, args), nil);
    openm = mk(NMethod, open, "string", body, params);

    fld->next = sealm;
    sealm->next = openm;
    return fld;
}

void
yyerror(char *s)
{
    if(last_caps_ident[0] != '\0' && last_caps_line >= cur_line - 1)
        fprint(2, "o9c: error: line %d: %s near '%s' ('%s' is not a declared type)\n",
            cur_line, s, last_caps_ident, last_caps_ident);
    else
        fprint(2, "o9c: error: line %d: %s\n", cur_line, s);
}

static char *input_buf;
static int input_pos;
static int input_len;
char *import_base_dir;	/* dir of the source file, for relative imports */
char *loaded_files[64];
int num_loaded_files = 0;

static int for_paren_depth = -1;	/* >=0 when inside for(...) — ';' returns TFORSEMI */
static int pushback[8];		/* multi-char pushback buffer */
static int npush = 0;

static int
lex_getc(void)
{
	int c;

	if(npush > 0)
		c = pushback[--npush];
	else if(input_pos >= input_len)
		return Beof;
	else
		c = (unsigned char)input_buf[input_pos++];
	if(c == '\n')
		cur_line++;
	return c;
}

static void
lex_ungetc(int c)
{
	if(npush < 8)
		pushback[npush++] = c;
	if(c == '\n')
		cur_line--;
}

int
yylex(void)
{
    int c;

    while((c = lex_getc()) != Beof){
        if(isspace(c))
            continue;
        /* Inside for(...): convert the header's ';' separators to
         * TFORSEMI so for_init/cond/step can be exprs.  for_paren_depth:
         * 0 after `for` (awaiting the header '('), 1 inside the header,
         * >1 in nested parens.  The ')' that closes the header (depth 1)
         * ends for-mode (-1); nested ')' just decrements. */
        if(for_paren_depth >= 0){
            if(c == '('){ for_paren_depth++; return '('; }
            if(c == ')'){
                for_paren_depth--;
                if(for_paren_depth <= 0)
                    for_paren_depth = -1;	/* header closed: leave for-mode */
                return ')';
            }
            if(c == ';' && for_paren_depth == 1)	/* only header ';' */
                return TFORSEMI;
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
            buf[i] = '\0';
            /* Only fold a dotted chain into one token when the head is a
             * registered type (enum access Color.Red) or module qualifier
             * (App.Counter); otherwise the dot is a property access and
             * belongs to the grammar. */
            if(isupper((uchar)buf[0]) && (is_known_type_name(buf) || is_module_prefix(buf))){
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
            if(strcmp(buf, "abstract") == 0) return TABSTRACT;
            if(strcmp(buf, "struct") == 0) return TSTRUCT;
            if(strcmp(buf, "interface") == 0) return TINTERFACE;
            if(strcmp(buf, "enum") == 0) return TENUM;
            if(strcmp(buf, "module") == 0) return TMODULE;
            if(strcmp(buf, "import") == 0) return TIMPORT;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "delete") == 0) return TDELETE;
            if(strcmp(buf, "far") == 0) return TFAR;
            if(strcmp(buf, "Dict") == 0) return TDICT;
            if(strcmp(buf, "method") == 0) return TMETHOD;
            if(strcmp(buf, "state") == 0) return TSTATE;
            if(strcmp(buf, "prop") == 0) return TPROP;
            if(strcmp(buf, "atomic") == 0) return TATOMIC;
            if(strcmp(buf, "stream") == 0) return TSTREAM;
            if(strcmp(buf, "secret") == 0) return TSECRET;
            if(strcmp(buf, "public") == 0) return TPUBLIC;
            if(strcmp(buf, "private") == 0) return TPRIVATE;
            if(strcmp(buf, "try") == 0) return TTRY;
            if(strcmp(buf, "defer") == 0) return TDEFER;
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
            if(is_known_type_name(buf))
                return TTYPEIDENT;
            if(isupper((uchar)buf[0])){
                /* Not a declared type: lex as a plain identifier so
                 * PascalCase members/locals work. Remember it for
                 * yyerror's undeclared-type hint. */
                strncpy(last_caps_ident, buf, sizeof last_caps_ident - 1);
                last_caps_ident[sizeof last_caps_ident - 1] = '\0';
                last_caps_line = cur_line;
            }
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
static int msg_depth;		/* lexical nesting depth of NMsgSend packing */
int has_return = 0;			/* 1 when a return statement was emitted */
int try_seen = 0;			/* 1 when a try expr needs the done: label */
Node *defer_list = nil;			/* deferred calls for the current method (LIFO) */
Node *cur_class;			/* current class being codegen'd, for type lookups */
int in_constructor_body = 0;		/* 1 while typechecking a constructor body */
char *ctor_class_name = nil;		/* the class whose ctor body is being checked */
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
    case NTry:
        /* At expression position, try just evaluates its call — the error
         * check is emitted at statement level (gen_try_check) since 6c has
         * no statement-expressions.  Bare `try f();` also lands here via
         * the expr-statement path, which emits the check after. */
        gen_expr(e->left);
        break;
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
    case NSelfCall:
        {
            /* Same-class call: direct wrapper invocation on self, no
             * dispatch machinery.  The owner may be an inherited class;
             * parent state is embedded first so the cast is valid (same
             * assumption as inheritance dispatch cases). */
            Node *owner = gen_class != nil ? method_owner(gen_class, e->name) : nil;
            Node *a;
            if(owner == nil){
                Builtin *bi = find_builtin(e->name);
                if(bi != nil){
                    int pi = 0;
                    print("%s(", bi->runtime);
                    for(a = e->right; a; a = a->next, pi++){
                        if(a != e->right) print(", ");
                        if(pi < bi->argc && bi->args[pi] != nil &&
                           strcmp(bi->args[pi], "object") == 0){
                            /* class-typed slot: pass the client by address */
                            print("&");
                            gen_expr(a);
                        } else if(pi < bi->argc && bi->args[pi] != nil &&
                           strcmp(bi->args[pi], "string") == 0 && a->type == NMsgSend){
                            /* dispatch expressions are vlong at the C level
                             * (frame slot); the method's o9 type is string,
                             * so re-pointer it for the builtin's prototype */
                            print("(char*)(uintptr)(");
                            gen_expr(a);
                            print(")");
                        } else
                            gen_expr(a);
                    }
                    print(")");
                    break;
                }
                print("0 /* unresolved self call: %s */", e->name);
                break;
            }
            print("o9_self_%s_%s((%s_Internal*)self", owner->name, e->name, owner->name);
            for(a = e->right; a; a = a->next){
                print(", ");
                gen_expr(a);
            }
            print(")");
        }
        break;
    case NMsgSend:
        {
            Type *lt = e->left != nil ? e->left->typeinfo : nil;
            /* Tabula methods: the receiver is an O9Tabula* handle, so
             * t.method(args) lowers to o9_tab_method(t, args). */
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "Tabula") == 0){
                char *fn = nil;
                if(strcmp(e->name, "add") == 0) fn = "o9_tab_add";
                else if(strcmp(e->name, "set") == 0) fn = "o9_tab_set";
                else if(strcmp(e->name, "get") == 0) fn = "o9_tab_get";
                else if(strcmp(e->name, "first") == 0) fn = "o9_tab_first";
                else if(strcmp(e->name, "next") == 0) fn = "o9_tab_next";
                else if(strcmp(e->name, "serialize") == 0) fn = "o9_tab_serialize";
                else if(strcmp(e->name, "close") == 0) fn = "o9_tab_close";
                if(fn != nil){
                    Node *a;
                    print("%s(", fn);
                    gen_expr(e->left);
                    for(a = e->right; a != nil; a = a->next){ print(", "); gen_expr(a); }
                    print(")");
                    break;
                }
            }
            if(type_is_collection(lt, "List")){
                if(strcmp(e->name, "Add") == 0){
                    Type *et = type_list_at(lt->args, 0);
                    Type *rt = e->right != nil ? e->right->typeinfo : nil;
                    char *st = type_storage_for_codegen(et);
                    if(type_is_class_ref(et) && type_is_class_ref(rt)){
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
            if(type_is_collection(lt, "Dict")){
                if(strcmp(e->name, "Has") == 0){
                    print("o9_dict_has(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
                    break;
                }
            }
        }
        /* c.method(args...) -> try o9_dispatch_call (asm), fallback to obj9_msgSend (CSP/9P) */
        {
            int nargs = 0, d;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            /* Each lexical nesting level packs into its own frame so nested
             * calls like a.set(b.get()) cannot clobber each other's args. */
            d = msg_depth++;
            if(d > 7) d = 7;
            /* Pack: frame[0]=shm_base (for ctrl thunk), frame[1..N]=real args */
            print("(__o9fr[%d][0]=", d);
            {
                /* The receiver's frame slot must hold its shm_base (the
                 * Internal*), not the Client struct.  Works for a local
                 * handle (NIdent) and a class-typed field (NPropRead). */
                char *rcls = e->left != nil ? get_expr_type(e->left) : nil;
                char *fcls = nil;
                /* class-typed field of the current class? (motor.rev() in a
                 * method, where motor is a field, parses as bare NIdent) */
                if(e->left && e->left->type == NIdent && e->left->name &&
                   in_method_body && gen_class != nil && !is_local(e->left->name) &&
                   member_exists(gen_class, e->left->name)){
                    Node *fn = member_node(gen_class, e->left->name, 0);
                    Type *ft = fn != nil ? decl_typeinfo(fn) : nil;
                    if(ft != nil && type_is_class_ref(ft))
                        fcls = fn->typename;	/* the field's declared class */
                }
                if(fcls != nil){
                    print("(vlong)((%s_Client*)&", fcls);
                    gen_expr(e->left);
                    print(")->shm_base");
                } else if(e->left && e->left->type == NIdent && e->left->name){
                    char *__cnx = get_var_class(e->left->name);
                    if(__cnx) print("(vlong)((%s_Client*)&", __cnx);
                    gen_expr(e->left);
                    if(__cnx) print(")->shm_base");
                } else if(rcls != nil && is_class_type(rcls)){
                    print("(vlong)((%s_Client*)&", rcls);
                    gen_expr(e->left);
                    print(")->shm_base");
                } else {
                    print("(vlong)&");
                    gen_expr(e->left);
                }
            }
            {
                int i = 1;
                for(a = e->right; a; a = a->next){
                    char buf[64];
                    snprint(buf, sizeof buf, ", __o9fr[%d][%d]=", d, i);
                    print(buf);
                    if(type_storage_pointerish(a->typeinfo)){
                        print("(vlong)(uintptr)(");
                        gen_expr(a);
                        print(")");
                    } else {
                        print("(vlong)(");
                        gen_expr(a);
                        print(")");
                    }
                    i++;
                }
            }
            /* Try asm dispatch first (thunk stores the return value in
             * frame[0]), fallback to CSP/9P with frame+1 (skip shm_base) */
            print(", o9_dispatch_call(&");
            gen_expr(e->left);
            print(", 0x%lux, __o9fr[%d]) != nil ? __o9fr[%d][0] : ", o9_hash(e->name), d, d);
            if(e->left && e->left->type == NIdent){
                /* Remote 9P path walks to "varname/methodname" in the instance tree */
                print("(vlong)obj9_msgSendN(&");
                gen_expr(e->left);
                print(", \"%s/%s\", 0x%lux, __o9fr[%d]+1, %d))", e->left->name, e->name, o9_hash(e->name), d, nargs);
            } else {
                print("(vlong)obj9_msgSendN(&");
                gen_expr(e->left);
                print(", \"%s\", 0x%lux, __o9fr[%d]+1, %d))", e->name, o9_hash(e->name), d, nargs);
            }
            msg_depth--;
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
            } else if(a->type == NStringLit && a->next == nil && strchr(a->name, '%') == nil){
                /* Single verb-free literal — use as format directly */
                gen_expr(a);
            } else if(a->type == NStringLit && a->next != nil && strchr(a->name, '%') != nil){
                /* Explicit format string with value args: pass through */
                gen_expr(a);
                for(a = a->next; a; a = a->next){
                    print(", ");
                    gen_expr(a);
                }
            } else {
                /* Auto-format: splice literals into the format, print
                 * string-typed values as %s and everything else as %lld */
                Node *a2;
                char *p;
                print("\"");
                for(a2 = a; a2; a2 = a2->next){
                    if(a2->type == NStringLit && a2->name != nil){
                        /* literal content is decoded; re-escape for C */
                        for(p = a2->name; *p; p++){
                            if(*p == '%') print("%%%%");
                            else if(*p == '\n') print("\\n");
                            else if(*p == '\t') print("\\t");
                            else if(*p == '\\') print("\\\\");
                            else if(*p == '"') print("\\\"");
                            else print("%c", *p);
                        }
                    } else if(strcmp(type_storage_for_codegen(a2->typeinfo), "char*") == 0)
                        print("%%s");
                    else
                        print("%%lld");
                }
                print("\"");
                for(a2 = a; a2; a2 = a2->next){
                    if(a2->type == NStringLit)
                        continue;
                    print(", ");
                    if(strcmp(type_storage_for_codegen(a2->typeinfo), "char*") == 0){
                        gen_expr(a2);
                    } else {
                        print("(vlong)(");
                        gen_expr(a2);
                        print(")");
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
            Type *lt = e->left != nil ? e->left->typeinfo : nil;
            if(type_is_collection(lt, "List")){
                Type *et = type_list_at(lt->args, 0);
                print("(*(%s*)o9_slice_get(&", type_storage_for_codegen(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
            } else if(type_is_collection(lt, "Dict")){
                Type *vt = type_list_at(lt->args, 1);
                print("((%s)o9_dict_get(&", type_storage_for_codegen(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
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
void gen_assign_new_to(char *varname, char *target, int is_field, char *lhs_type, Node *n);
void gen_state_store_typed(char *stateexpr, char *fieldexpr, char *name, Type *type);
void gen_state_store_flagged(char *stateexpr, char *fieldexpr, char *name, Type *type, int flags);
void gen_state_store(char *stateexpr, char *fieldexpr, char *name, char *typename);

void
gen_assign_new(char *varname, char *lhs_type, Node *n)
{
    gen_assign_new_to(varname, varname, 0, lhs_type, n);
}

/* target is the C lvalue to store the client into (e.g. "motor" for a
 * local, "self->motor" for a field).  is_field: don't declare a local
 * client/tbl; use a temp AsmTable and store into the field.  varname is
 * still the instance NAME (for create_instance and state). */
void
gen_assign_new_to(char *varname, char *target, int is_field, char *lhs_type, Node *n)
{
    char *cn, *dist;
    int dval, nctor, id, ai;
    Node *ca;
    char tbl[96];

    if(varname == nil || target == nil || lhs_type == nil || n == nil || n->name == nil)
        return;
    if(is_field){
        /* field target: its client struct is embedded in the Internal;
         * use a temp AsmTable rather than a `<var>_tbl` local. */
        snprint(tbl, sizeof tbl, "__o9tbl%d", new_tmp_id);
    } else {
        snprint(tbl, sizeof tbl, "%s_tbl", varname);
    }
    cn = n->name;
    dist = n->typename;
    dval = (dist && strcmp(dist, "near") == 0) ? 0 : (dist && strcmp(dist, "far") == 0) ? 1 : -1;
    nctor = 0;
    for(ca = n->right; ca; ca = ca->next)
        nctor++;

    if(is_field)
        print("\to9_AsmTable %s;\n", tbl);
    if(dval >= 0 && n->right && n->right->type == NStringLit){
        Node *first_arg = n->right;
        int rest = nctor - 1;
        print("\tmemset(&%s, 0, sizeof(%s_Client));\n", target, lhs_type);
        print("\tmemset(&%s, 0, sizeof(o9_AsmTable));\n", tbl);
        print("\t%s.table = &%s;\n", target, tbl);
        print("\t{\n\t\tchar __addr[128];\n\t\tsnprint(__addr, sizeof __addr, ");
        gen_expr(first_arg);
        print(");\n\t\to9_connect(&%s, __addr, \"%s\", %d);\n", target, cn, dval);
        print("\t\t%s.distance = %d;\n", target, dval);
        if(rest > 0){
            ai = 0;
            print("\t\tvlong __args_%s[%d];\n", varname, rest);
            for(ca = first_arg->next; ca; ca = ca->next){
                print("\t\t__args_%s[%d] = ", varname, ai);
                if(type_storage_pointerish(ca->typeinfo)){
                    print("(vlong)(uintptr)("); gen_expr(ca); print(")");
                } else
                    gen_expr(ca);
                print(";\n");
                ai++;
            }
            print("\t\tobj9_msgSendN(&%s, \"%s\", 0x%lux, __args_%s, %d);\n", target, cn, o9_hash(cn), varname, rest);
        }
        print("\t}\n");
        return;
    }

    id = new_tmp_id++;
    print("\t%s_Internal *__o9n%d = emalloc9p(sizeof(%s_Internal));\n", cn, id, cn);
    print("\tmemset(__o9n%d, 0, sizeof(%s_Internal));\n", id, cn);
    print("\t__o9n%d->dispatch_chan = chancreate(sizeof(void*), 10);\n", id);
    print("\t__o9n%d->distance = %d;\n", id, dval >= 0 ? dval : -1);
    print("\t__o9n%d->state = o9_state_create_path(o9app_root, \"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        id, cn, varname, cn, count_state_cols(find_class(cn)));
    {
        char ptr[64];
        snprint(ptr, sizeof ptr, "__o9n%d", id);
        gen_init_internal_state(find_class(cn), ptr);
    }
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", target, lhs_type);
    print("\tmemset(&%s, 0, sizeof(o9_AsmTable));\n", tbl);
    print("\t%s.shm_base = __o9n%d;\n", target, id);
    print("\t%s.dispatch_chan = __o9n%d->dispatch_chan;\n", target, id);
    print("\t%s.table = &%s;\n", target, tbl);
    print("\t%s.distance = %d;\n", target, dval >= 0 ? dval : -1);
    print("\tproccreate(%s_loop, __o9n%d, 65536);\n", cn, id);
    print("\t%s_create_instance(__o9n%d, \"%s\");\n", cn, id, varname);
    if(nctor > 0){
        ai = 0;
        print("\t{ vlong __args_%s_%d[%d];\n", varname, id, nctor);
        for(ca = n->right; ca; ca = ca->next){
            print("\t__args_%s_%d[%d] = ", varname, id, ai);
            if(type_storage_pointerish(ca->typeinfo)){
                print("(vlong)(uintptr)("); gen_expr(ca); print(")");
            } else
                gen_expr(ca);
            print(";\n");
            ai++;
        }
        print("\tobj9_msgSendN(&%s, \"%s\", 0x%lux, __args_%s_%d, %d); }\n",
            target, cn, o9_hash(cn), varname, id, nctor);
    } else {
        print("\tobj9_msgSendN(&%s, \"%s\", 0x%lux, nil, 0);\n", target, cn, o9_hash(cn));
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
    print("\t__%s->state = o9_state_create_path(o9app_root, \"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        s->name, cn, s->name, cn, count_state_cols(find_class(cn)));
    if(find_class(cn)){
        Node *cnode = find_class(cn);
        char ptr[128];
        snprint(ptr, sizeof ptr, "__%s", s->name);
        gen_init_internal_state(cnode, ptr);
    }
    print("\tproccreate(%s_loop, __%s, 65536);\n", cn, s->name);
    print("\t%s_create_instance(__%s, \"%s\");\n", cn, s->name, s->name);
    if(nctor > 0){
        print("\t{ vlong __args_%s[%d];\n", s->name, nctor);
        for(ca = s->left->right; ca; ca = ca->next){
            print("\t__args_%s[%d] = ", s->name, ai);
            if(type_storage_pointerish(ca->typeinfo)){
                print("(vlong)(uintptr)("); gen_expr(ca); print(")");
            } else
                gen_expr(ca);
            print(";\n");
            ai++;
        }
        print("\tobj9_msgSendN(&%s, \"%s\", 0x%lux, __args_%s, %d); }\n", s->name, cn, o9_hash(cn), s->name, nctor);
    } else {
        print("\tobj9_msgSendN(&%s, \"%s\", 0x%lux, nil, 0);\n", s->name, cn, o9_hash(cn));
    }
}

/* Emit the try error-propagation check for a statement whose RHS was a
 * `try`.  Must come AFTER the call's value has been assigned/used, so
 * the value is captured before we potentially goto done.  6c has no
 * statement-expressions, so try is a statement-level construct. */
static void
gen_try_check(void)
{
    try_seen = 1;
    print("\tif(o9_call_err != nil){ __o9r->err = o9_call_err; goto done; }\n");
}

/* True if e is a `try` wrapper (possibly the RHS of a stmt). */
static int
is_try(Node *e)
{
    return e != nil && e->type == NTry;
}

/* Emit a for-loop init/step clause (no leading tab, no trailing ;).
 * These are usually assignments (i = 0, i = i+1) which gen_expr does not
 * handle — emit "lhs = rhs" inline; otherwise fall through to gen_expr. */
void
gen_for_clause(Node *e)
{
    if(e == nil)
        return;
    if(e->type == NAssign && e->left != nil && e->right != nil){
        gen_expr(e->left);
        print(" = ");
        gen_expr(e->right);
        return;
    }
    gen_expr(e);
}

void
gen_stmt(Node *c, Node *s)
{
    Node *n;
    if(s == nil) return;
    /* fail("msg"): set the method's error and jump to the exit.  Reuses
     * the same done: mechanism as return — errors are values, no
     * unwinding.  Only meaningful inside a method body. */
    if(s->type == NSelfCall && s->name != nil && strcmp(s->name, "fail") == 0){
        if(in_method_body){
            has_return = 1;	/* ensure the done: label is emitted */
            print("\t__o9r->err = ");
            if(s->right != nil)
                gen_expr(s->right);
            else
                print("\"failed\"");
            print(";\n\tgoto done;\n");
        } else {
            /* outside a method: emit as a diagnostic + return */
            print("\tfprint(2, \"fail: %%s\\n\", ");
            if(s->right != nil) gen_expr(s->right); else print("\"failed\"");
            print(");\n");
        }
        return;
    }
    /* super(args): explicit parent-constructor chaining.  Calls the
     * nearest ancestor's constructor impl on THIS self (same object), so
     * every level of an Animal<-Mammal<-Cat chain initializes its own
     * fields.  Only valid inside a constructor body. */
    if(s->type == NSelfCall && s->name != nil && strcmp(s->name, "super") == 0){
        Node *parent = nil, *im;
        Node *ca;
        int na = 0;
        if(gen_class != nil){
            for(im = gen_class->left; im != nil; im = im->next)
                if(im->type == NInherit){ parent = find_class(im->name); break; }
        }
        if(parent == nil){
            fprint(2, "o9c: error: line %d: super() with no parent class\n", s->line);
            semantic_errors++;
            return;
        }
        for(ca = s->right; ca != nil; ca = ca->next) na++;
        /* pack args, build a message, call the parent ctor impl directly */
        print("\t{ ");
        if(na > 0){
            int ai2 = 0;
            print("vlong __superargs[%d]; ", na);
            for(ca = s->right; ca != nil; ca = ca->next){
                print("__superargs[%d] = ", ai2);
                if(type_storage_pointerish(ca->typeinfo)){ print("(vlong)(uintptr)("); gen_expr(ca); print(")"); }
                else { print("(vlong)("); gen_expr(ca); print(")"); }
                print("; ");
                ai2++;
            }
            print("O9Msg __superm = {0x%lux, __superargs, %d, chancreate(sizeof(void*), 1)}; ",
                o9_hash(parent->name), na);
        } else {
            print("O9Msg __superm = {0x%lux, nil, 0, chancreate(sizeof(void*), 1)}; ",
                o9_hash(parent->name));
        }
        print("o9_impl_%s_%s((%s_Internal*)self, &__superm); ", parent->name, parent->name, parent->name);
        print("{ O9Reply *__sr = recvp(__superm.replyc); free(__sr); } chanfree(__superm.replyc); }\n");
        return;
    }
    switch(s->type){
    case NLocalVar:
        if(is_primitive(s->typename)){
            print("\t%s %s;\n", type_storage_for_codegen(s->typeinfo), s->name);
            if(type_is_collection(s->typeinfo, "List")){
                print("\to9_slice_init(&%s, sizeof(%s));\n", s->name,
                    type_storage_for_codegen(type_list_at(s->typeinfo->args, 0)));
            } else if(type_is_collection(s->typeinfo, "Dict")){
                print("\to9_dict_init(&%s);\n", s->name);
            } else if(s->left){
                print("\t%s = ", s->name); gen_expr(s->left); print(";\n");
                if(is_try(s->left)) gen_try_check();
            } else {
                print("\tmemset(&%s, 0, sizeof(%s));\n", s->name, type_storage_for_codegen(s->typeinfo));
            }
        } else {
            char *cname = find_class(s->typename) ? s->typename : nil;
            int is_new = (s->left && s->left->type == NClass && s->left->name);
            if(cname != nil && s->left != nil && s->left->type == NSelfCall &&
               s->left->name != nil && strcmp(s->left->name, "lookup") == 0){
                /* Counter c = lookup("oid") — resolve through the rings:
                 * registry (in-process fast form) first, /srv fallback */
                print("\t%s_Client %s;\n", cname, s->name);
                print("\to9_lookup_client(&%s, ", s->name);
                gen_expr(s->left->right);
                print(", sizeof %s);\n", s->name);
                add_var_class(s->name, cname);
                break;
            }
            if(in_class_context || cname == nil){
                /* Plain local variable */
                print("\t%s %s", type_storage_for_codegen(s->typeinfo), s->name);
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
                        print("\t\to9_connect(&%s, __addr, \"%s\", %d);\n", s->name, cn, dval);
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
                        print("\t\tobj9_msgSendN(&%s, \"%s\", 0x%lux, __args_%s, %d);\n", s->name, cn, o9_hash(cname), s->name, rest);
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
            Type *lt = s->left != nil ? s->left->typeinfo : nil;
            if(type_is_collection(lt, "List") && strcmp(s->name, "Add") == 0){
                Type *et = type_list_at(lt->args, 0);
                Type *rt = s->right != nil ? s->right->typeinfo : nil;
                char *st = type_storage_for_codegen(et);
                if(type_is_class_ref(et) && type_is_class_ref(rt)){
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
    case NDelete:
        /* Run the destructor synchronously (actor replies after
         * teardown, then exits), then neutralize the client handle. */
        print("\tobj9_msgSendN(&%s, nil, 0x%lux, nil, 0);\n", s->name, o9_hash("destroy"));
        print("\to9_registry_unregister(\"%s\");\n", s->name);
        print("\tmemset(&%s, 0, sizeof %s);\n", s->name, s->name);
        print("\t%s.fd = -1;\n", s->name);
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
            Type *lt = s->left->left != nil ? s->left->left->typeinfo : nil;
            if(type_is_collection(lt, "List")){
                Type *et = type_list_at(lt->args, 0);
                Type *rt = s->right != nil ? s->right->typeinfo : nil;
                char *st = type_storage_for_codegen(et);
                if(type_is_class_ref(et) && type_is_class_ref(rt)){
                    print("\t{ %s __v; memmove(&__v, &", st); gen_expr(s->right); print(", sizeof(%s)); o9_slice_set(&", st);
                } else {
                    print("\t{ %s __v = ", st); gen_expr(s->right); print("; o9_slice_set(&");
                }
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", &__v); }\n");
                break;
            } else if(type_is_collection(lt, "Dict")){
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
                /* If the LHS is a class-typed FIELD (member of the current
                 * class, not a local), store into self->field, not a
                 * dangling local. */
                if(in_method_body && gen_class != nil && !is_local(s->left->name) &&
                   member_exists(gen_class, s->left->name)){
                    char tgt[128];
                    snprint(tgt, sizeof tgt, "self->%s", s->left->name);
                    gen_assign_new_to(s->left->name, tgt, 1, lt, s->right);
                } else {
                    gen_assign_new(s->left->name, lt, s->right);
                }
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
                        Node *fieldnode = member_node(cnode, s->left->name, 0);
                        Type *ft = decl_typeinfo(fieldnode);
                        char *t = type_storage_for_codegen(ft);
                        Node *d = type_decl_node(ft);
                        char field[128];
                        snprint(field, sizeof field, "__i->%s", s->left->name);
                        if(strcmp(t, "char*") == 0){
                            print("\t\t\tfree(__i->%s);\n", s->left->name);
                            print("\t\t\t__i->%s = strdup(", s->left->name);
                            gen_expr(s->right);
                            print(");\n");
                        } else if(d != nil && d->type == NStruct){
                            print("\t\t\t__i->%s = ", s->left->name);
                            gen_expr(s->right);
                            print(";\n");
                        } else if(type_storage_pointerish(ft)){
                            print("\t\t\t__i->%s = (%s)(uintptr)(", s->left->name, t);
                            gen_expr(s->right);
                            print(");\n");
                        } else {
                            print("\t\t\t__i->%s = (%s)(", s->left->name, type_cast_for_codegen(ft));
                            gen_expr(s->right);
                            print(");\n");
                        }
                        gen_state_store_flagged("__i->state", field, s->left->name, ft, fieldnode ? fieldnode->flags : 0);
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
                        Node *fieldnode = member_node(cnode, s->name, 0);
                        Type *ft = decl_typeinfo(fieldnode);
                        char *t = type_storage_for_codegen(ft);
                        Node *d = type_decl_node(ft);
                        char field[128];
                        snprint(field, sizeof field, "__i->%s", s->name);
                        if(strcmp(t, "char*") == 0){
                            print("\t\t\tfree(__i->%s);\n", s->name);
                            print("\t\t\t__i->%s = strdup(", s->name);
                            gen_expr(s->right);
                            print(");\n");
                        } else if(d != nil && d->type == NStruct) {
                            print("\t\t\t__i->%s = ", s->name);
                            gen_expr(s->right);
                            print(";\n");
                        } else if(type_storage_pointerish(ft)){
                            print("\t\t\t__i->%s = (%s)(uintptr)(", s->name, t);
                            gen_expr(s->right);
                            print(");\n");
                        } else {
                            print("\t\t\t__i->%s = (%s)(", s->name, type_cast_for_codegen(ft));
                            gen_expr(s->right);
                            print(");\n");
                        }
                        gen_state_store_flagged("__i->state", field, s->name, ft, fieldnode ? fieldnode->flags : 0);
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
                Node *fieldnode = member_node(c, s->left->name, 0);
                Type *ft = decl_typeinfo(fieldnode);
                char *t = type_storage_for_codegen(ft);
                Node *d = type_decl_node(ft);
                char field[128];
                /* atomic field: guard the read-modify-write with its QLock */
                if(mt == NAtomic)
                    print("\tqlock(&self->__lock_%s);\n", s->left->name);
                if(strcmp(t, "char*") == 0){
                    print("\tfree(self->%s);\n", s->left->name);
                    print("\tself->%s = strdup(", s->left->name);
                    gen_expr(s->right);
                    print(");\n");
                } else if(d != nil && d->type == NStruct){
                    print("\tself->%s = ", s->left->name);
                    gen_expr(s->right);
                    print(";\n");
                } else if(type_storage_pointerish(ft)){
                    print("\tself->%s = (%s)(uintptr)(", s->left->name, t);
                    gen_expr(s->right);
                    print(");\n");
                } else {
                    print("\tself->%s = (%s)(", s->left->name, type_cast_for_codegen(ft));
                    gen_expr(s->right);
                    print(");\n");
                }
                if(mt == NAtomic)
                    print("\tqunlock(&self->__lock_%s);\n", s->left->name);
                snprint(field, sizeof field, "self->%s", s->left->name);
                gen_state_store_flagged("self->state", field, s->left->name, ft, fieldnode ? fieldnode->flags : 0);
                break;
            }
        }
        if(s->left != nil && type_storage_pointerish(s->left->typeinfo)){
            print("\t"); gen_expr(s->left); print(" = (%s)(uintptr)(", type_storage_for_codegen(s->left->typeinfo)); gen_expr(s->right); print(");\n");
        } else {
            print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        }
        break;
    case NReturn:
        if(in_method_body){
            has_return = 1;
            if(is_try(s->left)){
                /* return try f(): capture, check error, then set ret */
                print("\t{ vlong __rv = (vlong)("); gen_expr(s->left); print(");\n");
                print("\tif(o9_call_err != nil){ __o9r->err = o9_call_err; goto done; }\n");
                print("\t__o9r->ret = (uintptr)__rv; }\n\tgoto done;\n");
            } else {
                print("\t__o9r->ret = (uintptr)("); gen_expr(s->left); print(");\n\tgoto done;\n");
            }
        } else {
            print("\treturn "); gen_expr(s->left); print(";\n");
        }
        break;
    case NDefer:
        /* Collect the deferred call; it is emitted at the method's done:
         * label so it runs on every exit path (LIFO: prepend). */
        {
            Node *dn = mk(NDefer, nil, nil, s->left, nil);
            dn->next = defer_list;
            defer_list = dn;
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
        /* s->left=init, s->right->left=cond, s->right->right=step, s->right->next=body.
         * init/step are expressions but are usually ASSIGNMENTS (i = 0;
         * i = i+1), which gen_expr does not emit — handle inline here. */
        print("\tfor(");
        gen_for_clause(s->left);
        print("; ");
        if(s->right->left) gen_expr(s->right->left);	/* cond is a plain expr */
        print("; ");
        gen_for_clause(s->right->right);
        print("){\n");
        for(n = s->right->next; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    default:
        print("\t"); gen_expr(s); print(";\n");
        if(is_try(s)) gen_try_check();	/* bare `try f();` */
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
            print("\t%s %s;\n", type_storage_for_codegen(m->typeinfo), m->name);
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
            print("\t%s %s;\n", type_storage_for_codegen(m->typeinfo), m->name);
        if(m->type == NAtomic)	/* companion QLock guarding atomic access.
             * QLock (not Lock): a spinlock in the cooperative CSP
             * scheduler would let a waiter busy-spin without ever yielding
             * to the holder — deadlock. QLock sleeps the waiter and is
             * safe to hold across a blocking RHS. */
            print("\tQLock __lock_%s;\n", m->name);
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
        /* class-typed fields are live handles, not persistable state */
        if((m->type == NProp || m->type == NState || m->type == NAtomic) &&
           !type_is_class_ref(m->typeinfo))
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
        if((m->type == NProp || m->type == NState || m->type == NAtomic) &&
           !type_is_class_ref(m->typeinfo)){
            if(m->flags & NFPrivate)
                print("\"debug:%s\", ", m->name);
            else
                print("\"%s\", ", m->name);
        }
    }
}

void
gen_state_store_typed(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    Node *d;
    char *t;

    if(stateexpr == nil || fieldexpr == nil || name == nil || type == nil)
        return;
    t = type_storage_for_codegen(type);
    if(strcmp(t, "O9Dict") == 0){
        print("\t{ char *__o9s = o9_dict_serialize(&%s); o9_state_set(%s, \"%s\", __o9s); free(__o9s); }\n",
            fieldexpr, stateexpr, name);
    } else if(strcmp(t, "O9Slice") == 0){
        /* Complex in-memory values stay in the hot struct for now. */
    } else if(strcmp(t, "char*") == 0){
        print("\to9_state_set(%s, \"%s\", %s ? %s : \"\");\n",
            stateexpr, name, fieldexpr, fieldexpr);
    } else if((d = type_decl_node(type)) != nil && (d->type == NStruct || d->type == NClass || d->type == NInterface)){
        /* Complex in-memory values stay in the hot struct for now. */
    } else {
        print("\to9_state_set_int(%s, \"%s\", (vlong)(%s));\n",
            stateexpr, name, fieldexpr);
    }
}

void
gen_state_store(char *stateexpr, char *fieldexpr, char *name, char *typename)
{
    gen_state_store_typed(stateexpr, fieldexpr, name, typeinfo_from_legacy(typename));
}

/* Like gen_state_store_typed, but private fields get a "debug:" column
 * prefix — present in the tab for debugging, not part of the public
 * contract.  Peers reading the state tab see "debug:val" and know it is
 * an implementation detail, not an advertised interface. */
void
gen_state_store_flagged(char *stateexpr, char *fieldexpr, char *name, Type *type, int flags)
{
    char colname[128];
    if(flags & NFPrivate)
        snprint(colname, sizeof colname, "debug:%s", name);
    else
        snprint(colname, sizeof colname, "%s", name);
    gen_state_store_typed(stateexpr, fieldexpr, colname, type);
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
            print("\t\tif(__o9objects) o9_object_record(__o9objects, \"%s\", \"%s\", \"%s\", \"declared\", \"\", nil, 0, __o9root, \"\", \"\", \"same\", \"\", \"declared\");\n",
                n->cname != nil ? n->cname : n->name,
                typetext != nil ? typetext : "",
                n->typename != nil ? n->typename : "");
        }
        if(n->type == NLink && n->left != nil && n->right != nil){
            char *sc = n->left->cname != nil ? n->left->cname : n->left->name;
            char *tc = n->right->cname != nil ? n->right->cname : n->right->name;
            char *mf = (n->typename != nil && strcmp(n->typename, "replica") == 0) ? "MBEFORE" : "MREPL";
            print("\t\t{ char __ls[300], __ld[300], __ll[640];\n");
            print("\t\tsnprint(__ls, sizeof __ls, \"%%s/obj/%s\", __o9root);\n", tc);
            print("\t\tsnprint(__ld, sizeof __ld, \"%%s/obj/%s\", __o9root);\n", sc);
            print("\t\to9_ns_ensure_dir(__ld);\n");
            print("\t\tbind(__ls, __ld, %s);\n", mf);
            print("\t\tsnprint(__ll, sizeof __ll, \"bind %s%%s %%s\", __ls, __ld);\n",
                strcmp(mf, "MBEFORE") == 0 ? "-b " : "");
            print("\t\to9_ns_recipe(__o9root, __o9app, __ll);\n\t\t}\n");
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
    print("\t\tO9ObjectStore *__o9objects;\n");
    print("\t\tchar *__o9_obj_cols[] = { \"qname\", \"type\", \"cname\", \"status\" };\n");
    print("\t\tchar *__o9_link_cols[] = { \"kind\", \"source\", \"target\" };\n");
    print("\t\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    print("\t\to9_ns_app_root(__o9root, sizeof __o9root, __o9app);\n");
    print("\t\to9_ns_ensure_app(__o9root);\n");
    print("\t\t__o9objects = o9_object_store_create_path(__o9root, __o9app);\n");
    gen_object_metadata_items(root);
    print("\t\to9_object_store_close(__o9objects);\n");
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
        if(m->type == NStream){
            /* CSP channel for object IPC: auto-created at construction so
             * the field is a live channel (both self-use and object-to-
             * object send/recv).  Buffered so a send need not rendezvous. */
            print("\t%s->%s = chancreate(sizeof(void*), 8);\n", ptr, m->name);
            continue;
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic){
            Node *d = type_decl_node(m->typeinfo);
            if(type_is_class_ref(m->typeinfo)){
                /* class-typed field: a live handle (embedded Client), not
                 * persistable state — zero it, no state column write. */
                print("\tmemset(&%s->%s, 0, sizeof(%s));\n", ptr, m->name, type_storage_for_codegen(m->typeinfo));
                continue;
            }
            if(type_is_collection(m->typeinfo, "Dict"))
                print("\to9_dict_init(&%s->%s);\n", ptr, m->name);
            else if(d != nil && d->type == NStruct)
                print("\tmemset(&%s->%s, 0, sizeof(%s));\n", ptr, m->name, type_storage_for_codegen(m->typeinfo));
            else
                print("\t%s->%s = 0;\n", ptr, m->name);
            snprint(field, sizeof field, "%s->%s", ptr, m->name);
            gen_state_store_flagged(state, field, m->name, m->typeinfo, m->flags);
        }
    }
}

void
gen_cache_entries_buf(Node *c, char *classname, char *bufname)
{
    /* Emits snprint statements that fill a runtime metadata/cache buffer. */
    Node *m, *p;
    if(c == nil) return;
    print("\t\tp += snprint(p, sizeof %s - (p-%s), \"seg:%s\\n\");\n", bufname, bufname, classname);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_cache_entries_buf(p, classname, bufname);
        }
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof %s - (p-%s), \"d:%%ld:%%ld\\n\", %ldL, (long)o9_offsetof(%s_Internal, %s));\n", bufname, bufname, o9_hash(m->name), classname, m->name);
        if(m->type == NMethod && method_has_body(m) &&
           c->type == NClass && (c->flags & NFAbstract) == 0){
            /* This cache table also lands in facade-reachable `status` —
             * don't expose private methods' or a constructor's handler
             * pointer there (it's not external API). */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;	/* constructor */
            print("\t\tp += snprint(p, sizeof %s - (p-%s), \"c:%%ld:%%p\\n\", %ldL, o9_ctrl_%s_%s);\n", bufname, bufname, o9_hash(m->name), c->name, m->name);
        }
    }
}

void
gen_cache_entries(Node *c, char *classname)
{
    gen_cache_entries_buf(c, classname, "cachebuf");
}

void
gen_method_registrations(Node *c, Node *concrete)
{
    /* Registers dispatchable methods in the process method store at class
     * server startup.  Mirrors gen_cache_entries_buf: inherited methods are
     * flattened onto the concrete class, reusing the parent's thunk. */
    Node *m, *p, *pn;
    char sig[256];
    int argc, n;

    if(c == nil || concrete == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_method_registrations(p, concrete);
        }
        if(m->type == NMethod && method_has_body(m) &&
           c->type == NClass && (c->flags & NFAbstract) == 0){
            /* Do NOT register private methods or constructors as callable
             * facade API: private is class-scoped (unreachable through the
             * mount, matching the compile-time check), and a constructor
             * must not be re-invokable on a live object over 9P. They
             * still get an INTERNAL dispatch case (gen_dispatch_cases) for
             * o9-to-o9 calls, super(), and new — this only gates the
             * external API surface (method store + /methods). */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;	/* constructor */
            argc = 0;
            n = 0;
            sig[0] = '\0';
            for(pn = m->right; pn; pn = pn->next){
                n += snprint(sig+n, sizeof sig - n, "%s%s",
                    argc ? "," : "", pn->typename != nil ? pn->typename : "vlong");
                argc++;
            }
            print("\to9_method_register(\"%s\", \"%s\", 0x%lux, %d, \"%s\", \"%s\", o9_ctrl_%s_%s);\n",
                concrete->name, m->name, o9_hash(m->name), argc,
                m->typename != nil ? m->typename : "void", sig, c->name, m->name);
        }
    }
}

static char*
metadata_member_kind(Node *m)
{
    if(m == nil)
        return "member";
    switch(m->type){
    case NProp: return "field";
    case NState: return "state";
    case NAtomic: return "atomic";
    case NSecret: return "secret";
    case NCap: return "cap";
    }
    return "member";
}

static char*
metadata_typename(Node *n)
{
    if(n == nil)
        return "";
    if(n->typename != nil)
        return n->typename;
    if(n->cname != nil)
        return n->cname;
    if(n->name != nil)
        return n->name;
    return "";
}

static char*
metadata_type_render(Node *n)
{
    if(n == nil)
        return "";
    if(n->typeinfo != nil)
        return type_render(n->typeinfo);
    if(n->typename != nil)
        return n->typename;
    return "";
}

void
gen_type_metadata_entries_buf(Node *c, char *bufname)
{
    Node *m, *p, *a;
    char *typetext, *storage;
    int argc;

    if(c == nil)
        return;
    print("\t\tp += snprint(p, sizeof %s - (p-%s), \"class name=%s qname=%s cname=%s typename=%s\\n\");\n",
        bufname,
        bufname,
        c->name != nil ? c->name : "",
        c->qname != nil ? c->qname : "",
        c->cname != nil ? c->cname : "",
        metadata_typename(c));
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p != nil)
                gen_type_metadata_entries_buf(p, bufname);
            continue;
        }
        if(m->type == NProp || m->type == NState || m->type == NAtomic ||
           m->type == NSecret || m->type == NCap){
            typetext = metadata_type_render(m);
            storage = type_storage_for_codegen(m->typeinfo);
            print("\t\tp += snprint(p, sizeof %s - (p-%s), \"%s name=%s typename=%s type=%s storage=%s\\n\");\n",
                bufname,
                bufname,
                metadata_member_kind(m),
                m->name != nil ? m->name : "",
                metadata_typename(m),
                typetext,
                storage);
        }
        if(m->type == NMethod){
            /* This metadata feeds the facade-reachable `status` surface,
             * so private methods and constructors must not appear (they
             * are not external API). */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;	/* constructor */
            typetext = metadata_type_render(m);
            storage = type_storage_for_codegen(m->typeinfo);
            argc = node_list_len(m->right);
            print("\t\tp += snprint(p, sizeof %s - (p-%s), \"method name=%s typename=%s type=%s storage=%s argc=%d\\n\");\n",
                bufname,
                bufname,
                m->name != nil ? m->name : "",
                metadata_typename(m),
                typetext,
                storage,
                argc);
            for(a = m->right; a; a = a->next){
                typetext = metadata_type_render(a);
                storage = type_storage_for_codegen(a->typeinfo);
                print("\t\tp += snprint(p, sizeof %s - (p-%s), \"param method=%s name=%s typename=%s type=%s storage=%s\\n\");\n",
                    bufname,
                    bufname,
                    m->name != nil ? m->name : "",
                    a->name != nil ? a->name : "",
                    metadata_typename(a),
                    typetext,
                    storage);
            }
        }
    }
}

void
gen_type_metadata_entries(Node *c)
{
    gen_type_metadata_entries_buf(c, "typebuf");
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
            char *t = type_storage_for_codegen(m->typeinfo);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize to buf */
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&s->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s);\n", m->name);
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(strcmp(c_type_fmt(t), "%s") == 0){
                    /* String property */
                    print("\t\treadstr(r, s->%s ? s->%s : \"\");\n", m->name, m->name);
                } else if(type_decl_node(m->typeinfo) != nil && type_decl_node(m->typeinfo)->type == NStruct) {
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
            char *t = type_storage_for_codegen(m->typeinfo);
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
        if(m->type == NMethod && method_has_body(m)) {
            ulong h = o9_hash(m->name);
            int i, found = 0;
            /* A constructor is a method whose name equals its defining
             * class.  When that class is an ANCESTOR (not the class being
             * constructed), `new <childname>(...)` dispatches under
             * hash(childname), not hash(ancestor) — so the inherited
             * constructor must ALSO be reachable under the child's hash,
             * however deep the chain.  Alias it to hash(childname). */
            if(childname != nil && strcmp(m->name, c->name) == 0 &&
               strcmp(c->name, childname) != 0){
                ulong ch = o9_hash(childname);
                int j, cfound = 0;
                for(j=0; j<num_emitted; j++) if(emitted_hashes[j] == ch){ cfound = 1; break; }
                if(!cfound){
                    print("\t\tcase 0x%lux: o9_impl_%s_%s((%s_Internal*)self, m); break;\t/* inherited ctor as %s */\n",
                        ch, c->name, m->name, c->name, childname);
                    emitted_hashes[num_emitted++] = ch;
                }
            }
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
            if(p && p->type == NClass && (p->flags & NFAbstract) == 0)
                gen_dispatch_cases(p, childname);
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
            char *t = type_storage_for_codegen(m->typeinfo);
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
    print("struct %s_Internal {\n\tArcLedger ledger;\n\tlong ref;\t/* ARC reference count */\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n\tO9State *state;\n\tchar data[4096];\n\tchar error[256];\n\tchar oid[64];\t/* instance name, for reap */\n\tvoid *objdir;\t/* File* of /<Class>/<oid>/, removed on reap */\n", c->name);
    gen_internal_fields(c);
    print("\tChannel *dispatch_chan;\n");
    print("};\n\n");

    /* Same-class call wrapper prototypes: bodies may bare-call methods
     * declared later in the class, so declare self-called wrappers up
     * front; definitions follow each method impl. */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && method_has_body(m) && (m->flags & NFSelfCalled)){
            Node *pn;
            char *rst = type_storage_for_codegen(m->typeinfo);
            print("static %s o9_self_%s_%s(%s_Internal *self",
                type_is_void(m->typeinfo) ? "void" : rst, c->name, m->name, c->name);
            for(pn = m->right; pn; pn = pn->next)
                print(", %s", type_storage_for_codegen(pn->typeinfo));
            print(");\n");
        }
    }
    print("\n");

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
            print("\tO9Reply *__o9r = mallocz(sizeof(O9Reply), 1);\n");
            print("\tvlong __o9fr[8][12];\n\tUSED(__o9fr);\n");
            /* Unpack params from msg->args (packed as vlong array for now) */
            {
                Node *p;
                int pi = 0;
                for(p = m->right; p; p = p->next){
                    char *st = type_storage_for_codegen(p->typeinfo);
                    if(storage_pointerish(st))
                        print("\t%s %s = (%s)(uintptr)((vlong*)msg->args)[%d];\n", st, p->name, st, pi);
                    else
                        print("\t%s %s = ((vlong*)msg->args)[%d];\n", st, p->name, pi);
                    pi++;
                }
            }
            in_method_body = 1;
            gen_class = c;
            has_return = 0;
            try_seen = 0;
            defer_list = nil;
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            /* Emit the exit label if any return/try/defer needs it. */
            if(has_return || try_seen || defer_list != nil) print("done:\n");
            /* Deferred cleanup runs on every exit path (normal, fail, try),
             * LIFO — list was prepended, emit in list order.  Still inside
             * the method body context so self-calls resolve. */
            {
                Node *dn;
                for(dn = defer_list; dn != nil; dn = dn->next){
                    print("\t"); gen_expr(dn->left); print(";\n");
                }
                defer_list = nil;
            }
            in_method_body = 0;
            gen_class = nil;
            print("\t__o9r->ok = 1;\n\tsendp(msg->replyc, __o9r);\n}\n\n");
			/* Ctrl dispatch thunk (void(*)(void*) for asm cache) */
			{
				int np = 0, pi;
				Node *pn;
				for(pn = m->right; pn; pn = pn->next) np++;
				print("static void o9_ctrl_%s_%s(void *__a){\n", c->name, m->name);
				print("\t%s_Internal *self = (%s_Internal*)((vlong*)__a)[0];\n", c->name, c->name);
				if(np > 0){
						for(pn = m->right, pi = 0; pn; pn = pn->next, pi++){
							char *st = type_storage_for_codegen(pn->typeinfo);
							if(storage_pointerish(st))
								print("\t%s __arg%d = (%s)(uintptr)((vlong*)__a)[%d];\n", st, pi, st, pi+1);
							else
								print("\t%s __arg%d = ((vlong*)__a)[%d];\n", st, pi, pi+1);
						}
						print("\tvlong __args[%d];\n", np);
						for(pn = m->right, pi = 0; pn; pn = pn->next, pi++){
							if(type_storage_pointerish(pn->typeinfo))
								print("\t__args[%d] = (vlong)(uintptr)__arg%d;\n", pi, pi);
							else
								print("\t__args[%d] = (vlong)__arg%d;\n", pi, pi);
						}
					/* buffered replyc: impl sends the reply from this same
					 * proc before we recvp — rendezvous would deadlock */
					print("\tO9Msg __m = {0x%lux, __args, %d, chancreate(sizeof(void*), 1)};\n", o9_hash(m->name), np);
				} else
					print("\tO9Msg __m = {0x%lux, nil, 0, chancreate(sizeof(void*), 1)};\n", o9_hash(m->name));
				print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
				print("\t{ O9Reply *__r = recvp(__m.replyc);\n");
				print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_call_err = __r->err; ((vlong*)__a)[0] = 0; }\n");
				print("\telse { o9_call_err = nil; ((vlong*)__a)[0] = (vlong)(uintptr)__r->ret; }\n");
				print("\tfree(__r); }\n");
				print("\tchanfree(__m.replyc);\n}\n\n");

				/* Same-class call wrapper for bare (implicit-self) calls */
				if(m->flags & NFSelfCalled){
					char *rst = type_storage_for_codegen(m->typeinfo);
					int isvoid = type_is_void(m->typeinfo);
					print("static %s o9_self_%s_%s(%s_Internal *self",
						isvoid ? "void" : rst, c->name, m->name, c->name);
					for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
						print(", %s __a%d", type_storage_for_codegen(pn->typeinfo), pi);
					print(") {\n");
					if(np > 0)
						print("\tvlong __args[%d];\n", np);
					print("\tO9Msg __m;\n\tO9Reply *__r;\n");
					if(!isvoid)
						print("\t%s __v;\n", rst);
					for(pn = m->right, pi = 0; pn; pn = pn->next, pi++){
						if(type_storage_pointerish(pn->typeinfo))
							print("\t__args[%d] = (vlong)(uintptr)__a%d;\n", pi, pi);
						else
							print("\t__args[%d] = (vlong)__a%d;\n", pi, pi);
					}
					print("\t__m.sel = 0x%lux;\n\t__m.args = %s;\n\t__m.nargs = %d;\n",
						o9_hash(m->name), np > 0 ? "__args" : "nil", np);
					print("\t__m.replyc = chancreate(sizeof(void*), 1);\n");
					print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
					print("\t__r = recvp(__m.replyc);\n");
					if(!isvoid){
						print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_call_err = __r->err; __v = 0; }\n");
						print("\telse { o9_call_err = nil; __v = (%s)__r->ret; }\n", rst);
					} else
						print("\tif(__r->err != nil) werrstr(\"%%s\", __r->err);\n");
					print("\tfree(__r);\n\tchanfree(__m.replyc);\n");
					if(!isvoid)
						print("\treturn __v;\n");
					print("}\n\n");
				}
			}
        }
        if(m->type == NDestructor){
            has_destruct = 1;
            num_locals = 0;
            mark_locals(m->left);
            print("static void o9_destruct_%s(%s_Internal *self) {\n", c->name, c->name);
            print("\tvlong __o9fr[8][12];\n\tUSED(__o9fr);\n");
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            print("}\n\n");
        }
    }

    print("static void %s_forget_instance(%s_Internal *inst);\n", c->name, c->name);
    print("static void o9_cleanup_%s(%s_Internal *self) {\n", c->name, c->name);
    if (has_destruct) {
        print("\to9_destruct_%s(self);\n", c->name);
    }
    print("\t%s_forget_instance(self);\t/* reap: tree dir + registry + list + tombstone */\n", c->name);
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
    /* destroy: replyc may be nil (ARC-reap sends destroy with no reply
     * channel) — only reply if a caller is waiting. */
    print("\t\tcase 0x%lux: o9_cleanup_%s(self); if(m->replyc != nil){ O9Reply *__dr = mallocz(sizeof(O9Reply), 1); __dr->ok = 1; sendp(m->replyc, __dr); } threadexits(nil); break;\n", o9_hash("destroy"), c->name);
    print("\t\tdefault: if(m->replyc != nil){ O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = \"bad selector\"; sendp(m->replyc, r); } break;\n");
    print("\t\t}\n\t}\n}\n\n");

    /* Per-app facade: root/mount/srv are shared app globals now.  Alias
     * the old per-class names so existing references resolve unchanged. */
    print("#define o9_app_root_%s o9app_root\n", c->name);
    print("#define o9_mount_%s o9app_mount\n", c->name);
    print("#define o9_srv_%s o9app_srvname\n", c->name);
    print("static O9ObjectStore *o9_objects_%s;\n", c->name);
    print("typedef struct %s_InstanceEntry %s_InstanceEntry;\n", c->name, c->name);
    print("struct %s_InstanceEntry { char name[64]; %s_Internal *inst; };\n", c->name, c->name);
    print("static %s_InstanceEntry %s_instances[128];\n", c->name, c->name);
    print("static int %s_ninstances;\n\n", c->name);
    print("static %s_Internal *%s_find_instance(char *name) {\n", c->name, c->name);
    print("\tint i;\n\tif(name == nil || name[0] == '\\0') return nil;\n");
    print("\tfor(i = 0; i < %s_ninstances; i++)\n", c->name);
    print("\t\tif(strcmp(%s_instances[i].name, name) == 0) return %s_instances[i].inst;\n", c->name, c->name);
    print("\treturn nil;\n}\n\n");
    /* Debug dumpstate: serialize every live instance's in-memory state
     * tab into out.  Returns bytes written.  Only reached when O9DEBUG. */
    print("static int %s_dumpstate(char *out, int nout){\n", c->name);
    print("\tint i, w = 0, n;\n");
    print("\tif(out == nil || nout <= 0) return 0;\n");
    print("\tout[0] = '\\0';\n");
    print("\tfor(i = 0; i < %s_ninstances && w < nout-1; i++){\n", c->name);
    print("\t\tn = snprint(out+w, nout-w, \"%%s:\\n\", %s_instances[i].name); w += n;\n", c->name);
    print("\t\tn = o9_state_serialize(%s_instances[i].inst->state, out+w, nout-w); w += n;\n", c->name);
    print("\t\tif(w < nout-1){ out[w++] = '\\n'; out[w] = '\\0'; }\n");
    print("\t}\n");
    print("\treturn w;\n}\n\n");
    /* Forward-declare the facade handlers: record_instance binds them into
     * each object dir's O9FileAux, but their bodies come further below. */
    print("static void fsread_%s(Req *r, void *instv);\n", c->name);
    print("static void fswrite_%s(Req *r, void *instv);\n", c->name);
    print("static int %s_record_instance(char *name, %s_Internal *inst) {\n", c->name, c->name);
    print("\t%s_Internal *old;\n\tif(name == nil || name[0] == '\\0' || inst == nil) return -1;\n", c->name);
    print("\told = %s_find_instance(name);\n\tif(old != nil) return 0;\n", c->name);
    print("\tif(%s_ninstances >= nelem(%s_instances)) return -1;\n", c->name, c->name);
    print("\tstrncpy(%s_instances[%s_ninstances].name, name, sizeof %s_instances[%s_ninstances].name-1);\n", c->name, c->name, c->name, c->name);
    print("\t%s_instances[%s_ninstances].inst = inst;\n", c->name, c->name);
    print("\t%s_ninstances++;\n", c->name);
    print("\to9_registry_register(name, \"%s\", inst->dispatch_chan, inst);\n", c->name);
    /* Flat facade: no per-object dir; just record the oid for reap/status. */
    print("\tstrncpy(inst->oid, name, sizeof inst->oid - 1);\n");
    print("\tif(o9_ns_bind_obj(o9_mount_%s, o9_app_root_%s, name) >= 0){\n", c->name, c->name);
    print("\t\tchar __ln[300];\n");
    print("\t\tsnprint(__ln, sizeof __ln, \"bind %%s/%%s %%s/obj/%%s\", o9_mount_%s, name, o9_app_root_%s, name);\n", c->name, c->name);
    print("\t\to9_ns_recipe(o9_app_root_%s, o9_app_root_%s[0] ? o9_app_root_%s + strlen(\"/mnt/o9/\") : \"app\", __ln);\n", c->name, c->name, c->name);
    print("\t}\n");
    print("\tif(o9_objects_%s != nil){\n", c->name);
    print("\t\tchar __path[256];\n");
    print("\t\tsnprint(__path, sizeof __path, \"%%s/%%s\", o9_mount_%s, name);\n", c->name);
    print("\t\to9_object_register_local(o9_objects_%s, name, \"%s\", \"%s\", inst, o9_app_root_%s, __path);\n",
        c->name,
        c->qname != nil ? c->qname : c->name,
        c->cname != nil ? c->cname : c->name,
        c->name);
    print("\t}\n");
    print("\treturn 0;\n}\n\n");

    /* Reap hygiene: no per-object dir to remove (flat tree); unregister,
     * de-list, tombstone the node row. */
    print("static void %s_forget_instance(%s_Internal *inst) {\n", c->name, c->name);
    print("\tint i;\n");
    print("\tif(inst == nil) return;\n");
    print("\tif(inst->oid[0] != '\\0'){\n");
    print("\t\to9_registry_unregister(inst->oid);\n");
    print("\t\tif(o9_objects_%s != nil) o9_object_set_state(o9_objects_%s, inst->oid, \"reaped\");\n", c->name, c->name);
    print("\t\tfor(i = 0; i < %s_ninstances; i++)\n", c->name);
    print("\t\t\tif(%s_instances[i].inst == inst){\n", c->name);
    print("\t\t\t\t%s_instances[i] = %s_instances[--%s_ninstances];\n", c->name, c->name, c->name);
    print("\t\t\t\tbreak;\n\t\t\t}\n");
    print("\t}\n");
    print("}\n\n");

    /* 4. 9P Fileserver Facade — clone pattern */
    print("static void fsread_%s(Req *r, void *instv) {\n", c->name);
    print("\tchar buf[1024];\n");
    print("\tUSED(buf);\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\t%s_Internal *inst = instv;\n\n", c->name);
    print("\tif(strcmp(name, \"status\") == 0) {\n");
    print("\t\tchar statusbuf[8192];\n\t\tchar *p = statusbuf;\n\t\tint i;\n");
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"state running\\n\");\n");
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"typename %s\\n\");\n", c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"qname %s\\n\");\n", c->qname != nil ? c->qname : c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"cname %s\\n\");\n", c->cname != nil ? c->cname : c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"root %%s\\nmount %%s\\nsrv %%s\\n\", o9_app_root_%s, o9_mount_%s, o9_srv_%s);\n", c->name, c->name, c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"objectstore %%s/state/%%s.objects.tab\\n\", o9_app_root_%s, o9_app_root_%s[0] ? o9_app_root_%s + strlen(\"/mnt/o9/\") : \"app\");\n", c->name, c->name, c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"instances\");\n");
    print("\t\tfor(i = 0; i < %s_ninstances; i++) p += snprint(p, sizeof statusbuf - (p-statusbuf), \" %%s\", %s_instances[i].name);\n", c->name, c->name);
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"\\n\");\n");
    gen_type_metadata_entries_buf(c, "statusbuf");
    gen_cache_entries_buf(c, c->name, "statusbuf");
    print("\t\tUSED(p);\n");
    print("\t\treadstr(r, statusbuf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"methods\") == 0) {\n");
    print("\t\tchar mbuf[8192];\n");
    print("\t\to9_method_serialize(\"%s\", mbuf, sizeof mbuf);\n", c->name);
    print("\t\treadstr(r, mbuf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"data\") == 0) { readstr(r, inst != nil ? inst->data : \"\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ctl\") == 0) { readstr(r, \"\"); respond(r, nil); return; }\n");
    print("\tif(inst == nil) { respond(r, \"no instance\"); return; }\n\n");
    /* Method file reads: check for stored O9Reply in fid aux */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0 && !type_is_void(m->typeinfo)){
            char *fmt = type_fmt_for_codegen(m->typeinfo);
            char *cast = type_cast_for_codegen(m->typeinfo);
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            print("\t\tO9Reply *__o9rep = r->fid->aux;\n");
            print("\t\tif(__o9rep == nil){ respond(r, \"no pending reply\"); return; }\n");
            print("\t\tif(__o9rep->err != nil)\n");
            print("\t\t\tsnprint(buf, sizeof buf, \"error: %%s\\n\", __o9rep->err);\n");
            print("\t\telse\n");
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
            char *t = type_storage_for_codegen(m->typeinfo);
            char *fmt = type_fmt_for_codegen(m->typeinfo);
            char *cast = type_cast_for_codegen(m->typeinfo);
            Node *d = type_decl_node(m->typeinfo);
            if(type_is_class_ref(m->typeinfo)){
                /* class-typed field is a live handle, not a readable value */
                print("\tif(strcmp(name, \"%s\") == 0){ readstr(r, \"<handle>\\n\"); respond(r, nil); return; }\n", m->name);
            } else if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&inst->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s); respond(r, nil); return;\n\t}\n", m->name);
            } else if(strcmp(fmt, "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", inst->%s ? inst->%s : \"\");\n", m->name, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else if(d != nil && d->type == NStruct) {
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

    print("static void fswrite_%s(Req *r, void *instv) {\n", c->name);
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\t%s_Internal *inst = instv;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) {\n");
    print("\t\tchar cmd[1024], *f[16], *v;\n\t\tint nf;\n\t\t%s_Internal *target;\n", c->name);
    print("\t\tUSED(v);\n");
    print("\t\tsnprint(cmd, sizeof cmd, \"%%.*s\", (int)r->ifcall.count, (char*)r->ifcall.data);\n");
    print("\t\tnf = tokenize(cmd, f, nelem(f));\n");
    print("\t\tif(inst != nil) inst->error[0] = '\\0';\n");
    print("\t\tif(nf <= 0){ respond(r, nil); return; }\n");
    /* Flat facade: f[1] may be Class.inst or bare inst — strip class prefix
     * so find_instance works with either addressing form. */
    print("\t\tif(nf > 1){\n");
    print("\t\t\tchar *__dot = strchr(f[1], '.');\n");
    print("\t\t\tif(__dot != nil && strncmp(f[1], \"%s\", %d) == 0) f[1] = __dot+1;\n", c->name, (int)strlen(c->name));
    print("\t\t}\n");
    print("\t\tif(strcmp(f[0], \"new\") == 0){\n");
    print("\t\t\tif(nf < 2){ if(inst) snprint(inst->error, sizeof inst->error, \"new needs instance name\"); respond(r, \"bad new\"); return; }\n");
    print("\t\t\ttarget = %s_find_instance(f[1]);\n", c->name);
    print("\t\t\tif(target == nil){\n");
    print("\t\t\t\ttarget = emalloc9p(sizeof(%s_Internal));\n", c->name);
    print("\t\t\t\tmemset(target, 0, sizeof(%s_Internal));\n", c->name);
    print("\t\t\t\ttarget->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\t\t\t\ttarget->state = o9_state_create_path(o9_app_root_%s, \"%s\", f[1], o9_state_cols_%s, %d);\n",
        c->name, c->name, c->name, count_state_cols(c));
    {
        char ptr[64];
        snprint(ptr, sizeof ptr, "target");
        gen_init_internal_state(c, ptr);
    }
    print("\t\t\t\t%s_record_instance(f[1], target);\n", c->name);
    print("\t\t\t\tproccreate(%s_loop, target, 65536);\n", c->name);
    print("\t\t\t}\n");
    print("\t\t\tsnprint(o9app_lastdata, sizeof o9app_lastdata, \"ok new %%s\\n\", f[1]);\n");
    print("\t\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t\t}\n");
    print("\t\tif(strcmp(f[0], \"method\") == 0){\n");
    print("\t\t\tif(nf < 3){ if(inst) snprint(inst->error, sizeof inst->error, \"method needs instance and name\"); respond(r, \"bad method\"); return; }\n");
    print("\t\t\ttarget = %s_find_instance(f[1]);\n", c->name);
    print("\t\t\tif(target == nil){ if(inst) snprint(inst->error, sizeof inst->error, \"unknown instance %%s\", f[1]); respond(r, \"unknown instance\"); return; }\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            int np = 0;
            Node *p;
            /* SECURITY: do not emit a ctl-dispatch case for private
             * methods or the constructor — this is the seam that made
             * `method Class.inst <private>` callable over the mount. The
             * method still has an INTERNAL dispatch case (o9-to-o9 calls,
             * super, new go through the actor loop, not this ctl path). */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;	/* constructor: not re-invokable over 9P */
            for(p = m->right; p; p = p->next) np++;
            print("\t\t\tif(strcmp(f[2], \"%s\") == 0){\n", m->name);
            if(np > 0){
                int pi;
                print("\t\t\t\tvlong __wargs[%d] = {0};\n", np);
                for(pi = 0; pi < np; pi++){
                    print("\t\t\t\tif(nf > %d){ v = strchr(f[%d], '='); __wargs[%d] = strtoll(v ? v+1 : f[%d], nil, 0); }\n",
                        pi+3, pi+3, pi, pi+3);
                }
            }
            print("\t\t\t\t{ O9Msg __wm = {0x%lux, %s, %d, chancreate(sizeof(void*), 0)};\n",
                o9_hash(m->name), np > 0 ? "__wargs" : "nil", np);
            print("\t\t\t\tsendp(target->dispatch_chan, &__wm);\n");
            print("\t\t\t\tO9Reply *__o9rep = recvp(__wm.replyc);\n");
            /* Flat facade: the ctl reply goes to the app-level data buffer
             * (o9app_lastdata), which the root `data` file returns — so an
             * external 9P caller reads its result there. */
            print("\t\t\t\tif(__o9rep->err != nil) snprint(o9app_lastdata, sizeof o9app_lastdata, \"error: %%s\\n\", __o9rep->err);\n");
            print("\t\t\t\telse\n");
            if(type_is_void(m->typeinfo)){
                print("\t\t\t\tsnprint(o9app_lastdata, sizeof o9app_lastdata, \"ok\\n\");\n");
            } else {
                char *fmt = type_fmt_for_codegen(m->typeinfo);
                char *cast = type_cast_for_codegen(m->typeinfo);
                if(strcmp(fmt, "%s") == 0)
                    print("\t\t\t\tsnprint(o9app_lastdata, sizeof o9app_lastdata, \"%%s\\n\", (char*)__o9rep->ret);\n");
                else
                    print("\t\t\t\tsnprint(o9app_lastdata, sizeof o9app_lastdata, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
            }
            print("\t\t\t\tfree(__o9rep); chanfree(__wm.replyc); }\n");
            print("\t\t\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t\t\t}\n");
        }
    }
    print("\t\t\tif(inst) snprint(inst->error, sizeof inst->error, \"unknown method %%s\", f[2]);\n");
    print("\t\t\trespond(r, \"unknown method\"); return;\n\t\t}\n");
    print("\t\tif(inst) snprint(inst->error, sizeof inst->error, \"unknown command %%s\", f[0]);\n");
    print("\t\trespond(r, \"unknown command\"); return;\n\t}\n");
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
                if(!type_is_void(m->typeinfo)){
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
            char *t = type_storage_for_codegen(m->typeinfo);
            Node *d = type_decl_node(m->typeinfo);
            if(type_is_class_ref(m->typeinfo)){
                /* class-typed field is a handle — not writable via 9P */
            } else if(strcmp(t, "O9Dict") == 0) {
                /* Dict property: deserialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\to9_dict_deserialize(&inst->%s, r->ifcall.data);\n", m->name);
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store_typed("inst->state", field, m->name, m->typeinfo);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else if(strcmp(type_fmt_for_codegen(m->typeinfo), "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tfree(inst->%s);\n", m->name);
                print("\t\tinst->%s = strdup(r->ifcall.data);\n", m->name);
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store_typed("inst->state", field, m->name, m->typeinfo);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else if(d != nil && d->type == NStruct) {
                /* skip writing to structs via 9P for now */
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                if(m->typeinfo != nil && m->typeinfo->kind == TyParam)
                    print("\t\tinst->%s = (void*)(uintptr)strtoll(r->ifcall.data, nil, 0);\n", m->name);
                else
                    print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast_for_codegen(m->typeinfo));
                {
                    char field[128];
                    snprint(field, sizeof field, "inst->%s", m->name);
                    gen_state_store_typed("inst->state", field, m->name, m->typeinfo);
                }
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"read only or not found\");\n}\n\n");
    print("int %s_create_instance(%s_Internal *inst, char *name) {\n", c->name, c->name);
    print("\treturn %s_record_instance(name, inst);\n}\n", c->name);
    /* Per-app facade: register this class INTO the shared app server.
     * No Srv/tree/post of its own — those are o9_app_start's job.  The
     * flat tree already exists; the class just registers its handlers and
     * creates its boot instance (recorded in the registry, no dir). */
    o9_note_registered(c->name);	/* boot calls o9_register_class_<C> */
    print("void o9_register_class_%s(void) {\n", c->name);
    print("\to9app_register_handler(\"%s\", fsread_%s, fswrite_%s, (void*(*)(char*))%s_find_instance, %s_dumpstate);\n", c->name, c->name, c->name, c->name, c->name);
    print("\to9_objects_%s = o9_object_store_create_path(o9app_root, o9app_name);\n", c->name);
    print("\to9_method_store_init(o9app_root, o9app_name);\n");
    gen_method_registrations(c, c);
    /* No boot instance created here — instances come from main()'s `new`
     * statements, which call the constructor and register with the variable
     * name.  The class loop proc is started per-instance by gen_local_new. */
    print("}\n");
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
        } else if(n->type == NClass && (n->flags & NFAbstract) == 0 && n->params == nil){
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

/* Monomorphization: every concrete instantiation of a user generic
 * (Box<int64>) becomes a real class/struct — a substituted deep copy of
 * the template, registered and generated like hand-written code.  The
 * templates themselves still emit nothing. */

static Node *mono_list;	/* instantiated decls, in discovery order */

/* Names of classes that got a gen_class_server (hence an
 * o9_register_class_<C>); the per-app boot calls register for each. */
static char *o9_registered[256];
static int o9_nregistered;
static void
o9_note_registered(char *name)
{
    int i;
    if(name == nil || o9_nregistered >= nelem(o9_registered))
        return;
    for(i = 0; i < o9_nregistered; i++)
        if(strcmp(o9_registered[i], name) == 0)
            return;
    o9_registered[o9_nregistered++] = strdup(name);
}

static void mono_scan_node(Node *n);
static Type* type_subst(Type *t, TypeBind *bindings);
static TypeBind* type_bindings_for(Node *decl, Type *receiver);

static char*
name_tail(char *s)
{
    char *p, *last;

    if(s == nil)
        return nil;
    last = s;
    p = strstr(s, "__");
    while(p != nil){
        last = p + 2;
        p = strstr(last, "__");
    }
    return last;
}

static Node*
copy_node_subst(Node *n, TypeBind *b)
{
    Node *c;

    if(n == nil)
        return nil;
    c = malloc(sizeof(Node));
    if(c == nil)
        sysfatal("malloc: copy_node_subst");
    memmove(c, n, sizeof(Node));
    if(n->typeinfo != nil){
        c->typeinfo = type_subst(n->typeinfo, b);
        c->typename = legacy_type_name(c->typeinfo);
    }
    c->params = copy_node_subst(n->params, b);
    c->left = copy_node_subst(n->left, b);
    c->right = copy_node_subst(n->right, b);
    c->next = copy_node_subst(n->next, b);
    return c;
}

static void
mono_instantiate(Node *tmpl, Type *app)
{
    Node *inst, *m;
    TypeBind *b;
    char *cn, *tail;

    cn = type_cname(app);
    if(cn == nil || find_class(cn) != nil)
        return;
    b = type_bindings_for(tmpl, app);
    inst = malloc(sizeof(Node));
    if(inst == nil)
        sysfatal("malloc: mono_instantiate");
    memmove(inst, tmpl, sizeof(Node));
    inst->name = cn;
    inst->cname = cn;
    inst->qname = type_render(app);
    inst->params = nil;
    inst->next = nil;
    inst->typeinfo = nil;
    inst->left = copy_node_subst(tmpl->left, b);
    /* the constructor keeps the source class name; retarget it so the
     * dispatch selector matches new <cname> */
    tail = name_tail(tmpl->cname != nil ? tmpl->cname : tmpl->name);
    for(m = inst->left; m; m = m->next){
        if(m->type == NMethod && m->name != nil && tail != nil && strcmp(m->name, tail) == 0){
            m->name = cn;
            m->qname = cn;
            m->cname = cn;
        }
    }
    add_class(cn, inst);
    if(mono_list == nil)
        mono_list = inst;
    else {
        for(m = mono_list; m->next; m = m->next)
            ;
        m->next = inst;
    }
    /* instantiations can require further instantiations */
    mono_scan_node(inst->left);
}

static void
mono_scan_type(Type *t)
{
    TypeList *a;
    Node *d;

    if(t == nil)
        return;
    if(t->kind == TyApply && t->name != nil &&
       strcmp(t->name, "List") != 0 && strcmp(t->name, "Dict") != 0){
        d = type_decl_node(t);
        if(d != nil && d->params != nil)
            mono_instantiate(d, t);
    }
    for(a = t->args; a; a = a->next)
        mono_scan_type(a->type);
    mono_scan_type(t->base);
}

static void
mono_scan_node(Node *n)
{
    for(; n; n = n->next){
        /* templates are scanned only when instantiated */
        if((n->type == NClass || n->type == NStruct || n->type == NInterface) &&
           n->params != nil)
            continue;
        mono_scan_type(n->typeinfo);
        mono_scan_node(n->params);
        mono_scan_node(n->left);
        mono_scan_node(n->right);
    }
}

void
codegen(Node *root)
{
    Node *n;
    ClassDef *cd;

    mono_scan_node(root);

    print("/* Generated o9 Source */\n");
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include <o9.h>\n\n");
    print("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    print("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n");
    /* Per-app facade: ONE Srv with a FLAT four-file tree, built once at
     * startup and never mutated at runtime.  No class/object dirs -> no
     * runtime createfile/walkfile (the source of the lib9p faults).  The
     * app has a uniform shape regardless of its classes.  ctl names its
     * target instance in the line (method Class.inst method arg...);
     * status/methods list the object graph and public surface by reading.
     *
     * Class handlers register themselves in a small table so the flat
     * ctl/read handler can route to any class's fsread/fswrite body. */
    print("typedef struct O9ClassH O9ClassH;\n");
    print("struct O9ClassH {\n");
    print("\tchar *name;\n");
    print("\tvoid (*read)(Req*, void*);\n");
    print("\tvoid (*write)(Req*, void*);\n");
    print("\tvoid *(*find)(char*);\t/* <C>_find_instance */\n");
    print("\tint (*dumpstate)(char*, int);\t/* <C>_dumpstate: debug */\n");
    print("};\n");
    print("extern O9ClassH o9app_classes[64];\n");
    print("extern int o9app_nclasses;\n");
    print("extern Srv o9app_srv;\n");
    print("extern Tree *o9app_tree;\n");
    print("extern char o9app_root[128];\n");
    print("extern char o9app_srvname[128];\n");
    print("extern char o9app_mount[256];\n");
    print("extern char o9app_name[64];\n");
    print("extern File *o9app_exports_dir;\t/* served-tree exports/ dir */\n");
    print("static void o9app_register_handler(char *name, void (*rd)(Req*,void*), void (*wr)(Req*,void*), void *(*find)(char*), int (*dump)(char*,int)){\n");
    print("\tif(o9app_nclasses >= nelem(o9app_classes)) return;\n");
    print("\to9app_classes[o9app_nclasses].name = name;\n");
    print("\to9app_classes[o9app_nclasses].read = rd;\n");
    print("\to9app_classes[o9app_nclasses].write = wr;\n");
    print("\to9app_classes[o9app_nclasses].find = find;\n");
    print("\to9app_classes[o9app_nclasses].dumpstate = dump;\n");
    print("\to9app_nclasses++;\n}\n");
    /* Debug gate: O9DEBUG env var exposes live object state via the
     * `state` file.  Off by default — encapsulation preserved. */
    print("extern int o9app_debug;\n");
    /* Split a "Class.inst" token; returns the class handler and writes
     * the bare instance name into instout.  nil if not found. */
    print("static O9ClassH *o9app_resolve(char *tok, char *instout, int n){\n");
    print("\tchar *dot; int i;\n");
    print("\tif(tok == nil) return nil;\n");
    print("\tdot = strchr(tok, '.');\n");
    print("\tif(dot != nil){\n");
    print("\t\tint clen = dot - tok;\n");
    print("\t\tsnprint(instout, n, \"%%s\", dot+1);\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++)\n");
    print("\t\t\tif(strncmp(o9app_classes[i].name, tok, clen) == 0 && o9app_classes[i].name[clen] == '\\0')\n");
    print("\t\t\t\treturn &o9app_classes[i];\n");
    print("\t\treturn nil;\n");
    print("\t}\n");
    /* No class prefix: search every class for an instance of that name */
    print("\tsnprint(instout, n, \"%%s\", tok);\n");
    print("\tfor(i = 0; i < o9app_nclasses; i++)\n");
    print("\t\tif(o9app_classes[i].find != nil && o9app_classes[i].find(tok) != nil)\n");
    print("\t\t\treturn &o9app_classes[i];\n");
    print("\treturn nil;\n}\n");
    print("#endif\n\n");
    /* Shared app-server globals (once per program). */
    print("O9ClassH o9app_classes[64];\n");
    print("int o9app_nclasses;\n");
    print("Srv o9app_srv;\n");
    print("Tree *o9app_tree;\n");
    print("char o9app_root[128];\n");
    print("char o9app_srvname[128];\n");
    print("char o9app_mount[256];\n");
    print("char o9app_name[64];\n");
    print("File *o9app_exports_dir;\t/* served-tree exports/ dir (mutable) */\n");
    print("int o9app_debug;\t/* set from O9DEBUG at startup */\n\n");
    /* One published Tabula: its serialized bytes live in the File's aux,
     * served ramfs-style on read.  This is the mutable part of the fs. */
    print("typedef struct O9Export O9Export;\n");
    print("struct O9Export { char *data; int ndata; };\n\n");

    /* exports/ is a served-tree DIRECTORY (part of the application file
     * tree, reachable through the mount) — NOT an on-disk directory.
     * Objects publish Tabulae into it at runtime via createfile; the
     * serialized bytes live in the child File's aux. */
    /* Flat root handlers.  The four files share these; ctl routes by the
     * line's Class.inst to a class handler, the rest aggregate. */
    print("static char o9app_lastdata[4096];\n");
    print("static void o9app_root_read(Req *r){\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\tchar buf[8192]; char *p = buf; int i;\n");
    /* Export file: its aux holds an O9Export with the serialized bytes.
     * Serve them ramfs-style (offset/count).  The fixed control files
     * were created with aux=nil, so a non-nil aux marks an export. */
    print("\tif(r->fid->file->aux != nil){\n");
    print("\t\tO9Export *__ex = r->fid->file->aux;\n");
    print("\t\tvlong __off = r->ifcall.offset; long __cnt = r->ifcall.count;\n");
    print("\t\tif(__off >= __ex->ndata){ r->ofcall.count = 0; respond(r, nil); return; }\n");
    print("\t\tif(__off + __cnt > __ex->ndata) __cnt = __ex->ndata - __off;\n");
    print("\t\tmemmove(r->ofcall.data, __ex->data + __off, __cnt);\n");
    print("\t\tr->ofcall.count = __cnt; respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"data\") == 0){ readstr(r, o9app_lastdata); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ctl\") == 0){ readstr(r, \"\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"status\") == 0){\n");
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"app %%s\\nstate running\\nclasses\", o9app_name);\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++) p += snprint(p, sizeof buf-(p-buf), \" %%s\", o9app_classes[i].name);\n");
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"methods\") == 0){\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tchar mb[4096]; o9_method_serialize(o9app_classes[i].name, mb, sizeof mb);\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"%%s\", mb);\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    /* state: DEBUG-only inspector.  Off by default (encapsulation);
     * O9DEBUG dumps every live object's serialized state tab. */
    print("\tif(strcmp(name, \"state\") == 0){\n");
    print("\t\tif(!o9app_debug){ readstr(r, \"debug disabled (set O9DEBUG)\\n\"); respond(r, nil); return; }\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tif(o9app_classes[i].dumpstate == nil) continue;\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"# %%s\\n\", o9app_classes[i].name);\n");
    print("\t\t\tp += o9app_classes[i].dumpstate(p, (int)(sizeof buf-(p-buf)));\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    print("\trespond(r, \"not found\");\n}\n");
    print("static void o9app_root_write(Req *r){\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\tchar cmd[1024], *f[16]; int nf; char inst[64]; O9ClassH *ch;\n");
    print("\tif(strcmp(name, \"ctl\") != 0){ respond(r, \"read only\"); return; }\n");
    print("\tsnprint(cmd, sizeof cmd, \"%%.*s\", (int)r->ifcall.count, (char*)r->ifcall.data);\n");
    print("\tnf = tokenize(cmd, f, nelem(f));\n");
    print("\tif(nf < 3 || strcmp(f[0], \"method\") != 0){ respond(r, \"want: method Class.inst name [argN=v]\"); return; }\n");
    /* f[1] is Class.inst (or bare inst); resolve to a class handler and
     * rewrite f[1] to the bare instance the class handler expects. */
    print("\tch = o9app_resolve(f[1], inst, sizeof inst);\n");
    print("\tif(ch == nil){ respond(r, \"unknown object\"); return; }\n");
    print("\tf[1] = inst;\n");
    print("\tch->write(r, nil);\t/* class fswrite: routes by f[1]=inst */\n");
    print("}\n\n");

    /* o9_export_tab: publish a Tabula into the served-tree exports/ dir at
     * runtime.  A single createfile into the stable exports parent (the
     * safe pattern); the serialized bytes go in the child File's aux.  If
     * a file of that name exists, its bytes are replaced (re-export). */
    print("void o9_export_tab(char *name, O9Tabula *t){\n");
    print("\tFile *f; O9Export *ex; char *bytes;\n");
    print("\tif(o9app_exports_dir == nil || name == nil || t == nil) return;\n");
    print("\tbytes = o9_tab_serialize(t);\n");
    print("\tf = createfile(o9app_exports_dir, name, \"o9\", 0444, nil);\n");
    print("\tif(f == nil){\t/* exists: replace its bytes */\n");
    print("\t\tf = walkfile(o9app_exports_dir, name);\n");
    print("\t\tif(f == nil){ free(bytes); return; }\n");
    print("\t}\n");
    print("\tex = f->aux;\n");
    print("\tif(ex == nil){ ex = mallocz(sizeof *ex, 1); f->aux = ex; }\n");
    print("\tfree(ex->data);\n");
    print("\tex->data = bytes; ex->ndata = bytes != nil ? strlen(bytes) : 0;\n");
    print("\tf->length = ex->ndata;\n");
    print("}\n\n");

    /* 1. Emit headers for ALL known classes/interfaces (local and imported) */
    for(cd = classes; cd; cd = cd->next){
        if(cd->node->type != NStruct && cd->node->type != NEnum)
            gen_class_header(cd->node);
    }
    Node *main_func = find_main_func(root);
    Node *last = nil;
    int has_remote_new = main_has_remote_new(main_func);

    gen_enums(root);
    gen_structs(root);
    for(n = mono_list; n; n = n->next)
        if(n->type == NStruct)
            gen_struct_def(n);
    for(n = mono_list; n; n = n->next)
        if(n->type == NClass && (n->flags & NFAbstract) == 0)
            gen_class_server(n);
    last = gen_classes(root);

    /* Per-app facade: one Srv/tree for the whole program.  o9_app_start
     * sets the app names, allocates the shared tree, and posts the single
     * /srv/o9.<app>; each class then registers INTO it. */
    print("static void o9_app_start(int argc, char **argv){\n");
    print("\tchar *__o9app = \"%s\";\n", last != nil ? last->name : "app");
    print("\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    print("\tsnprint(o9app_name, sizeof o9app_name, \"%%s\", __o9app);\n");
    print("\t{ char *__d = getenv(\"O9DEBUG\"); o9app_debug = (__d != nil && __d[0] != '\\0'); free(__d); }\n");
    print("\to9_ns_app_root(o9app_root, sizeof o9app_root, __o9app);\n");
    print("\to9_ns_service_name(o9app_srvname, sizeof o9app_srvname, __o9app, __o9app, \"app\");\n");
    print("\to9_ns_class_path(o9app_mount, sizeof o9app_mount, o9app_root, __o9app);\n");
    print("\to9_ns_ensure_app(o9app_root);\n");
    print("\to9app_tree = alloctree(nil, nil, DMDIR|0555, nil);\n");
    print("\to9app_srv.tree = o9app_tree;\n");
    print("\to9app_srv.read = o9app_root_read;\n\to9app_srv.write = o9app_root_write;\n");
    /* The four control files + state are a FIXED shape, built once, never
     * mutated (their content is live, their structure is frozen). */
    print("\tcreatefile(o9app_tree->root, \"ctl\", \"o9\", 0666, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"data\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"status\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"methods\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"state\", \"o9\", 0444, nil);\t/* debug inspector */\n");
    /* exports/ is a served-tree DIRECTORY inside the application file tree
     * (NOT on disk).  It is the one MUTABLE part: objects publish Tabulae
     * into it at runtime via a single createfile into this stable parent
     * dir (the authsrv/ramfs-proven safe pattern — no nested subtree, no
     * walkfile).  Reachable through the mount; ls reflects live objects. */
    print("\to9app_exports_dir = createfile(o9app_tree->root, \"exports\", \"o9\", DMDIR|0555, nil);\n");
    print("}\n");
    print("static void o9_app_post(void){\n");
    print("\t{ char __sp[160]; snprint(__sp, sizeof __sp, \"/srv/%%s\", o9app_srvname); remove(__sp); }\n");
    print("\t{ char __ln[300]; snprint(__ln, sizeof __ln, \"mount /srv/%%s %%s\", o9app_srvname, o9app_mount); o9_ns_recipe(o9app_root, o9app_name, __ln); }\n");
    print("\tif(o9_ns_ensure_dir(o9app_mount) == 0)\n");
    /* MREPL|MCREATE: the exports/ dir is mutable — objects createfile
     * into it at runtime — so the facade mount must permit creation
     * (this is exactly what ramfs uses: MREPL|MCREATE). */
    print("\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, o9app_mount, MREPL|MCREATE);\n");
    print("\telse\n\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, nil, MREPL|MCREATE);\n");
    print("}\n\n");

    print("int mainstacksize = 65536;\n\n");
    print("void\nthreadmain(int argc, char **argv)\n{\n");
    print("\tvlong __o9fr[8][12];\n");
    print("\tUSED(argc); USED(argv); USED(__o9fr);\n");
    /* Per-app namespace isolation MUST happen here — the very first thing
     * in threadmain, BEFORE o9_registry_start or any proccreate. Forking
     * the namespace group after procs exist disturbs the thread library's
     * proc/rendezvous group. RFNAMEG copies the namespace (isolation);
     * then re-bind the global #s (srv) device onto /srv so the app's post
     * stays reachable to other processes (facade) — the iostats.c /
     * lib/namespace pattern. Isolation for the app's own tree + shared
     * /srv for the post. Verified: mk export-test = export: OK. */
    print("\trfork(RFNAMEG);\n");
    print("\tbind(\"#s\", \"/srv\", MREPL|MCREATE);\n");
    print("\to9_registry_start();\n");
    gen_object_metadata(root);
    if(!has_remote_new){
        /* One app server; every class that got a class-server (generic
         * and non-generic alike) registers into it, then post once. */
        int __ri;
        print("\to9_app_start(argc, argv);\n");
        for(__ri = 0; __ri < o9_nregistered; __ri++)
            print("\to9_register_class_%s();\n", o9_registered[__ri]);
        print("\to9_app_post();\n");
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
            }
            /* NOTE: `import`/`from` are resolved by resolve_imports()
             * BEFORE prescan — the imported source is already spliced in,
             * so its real decls get registered here as ordinary text.
             * The old name-only scan_file() path is gone (it registered
             * member-less stubs -> "has no member"). */
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
            fprint(2, "o9c: error: line %d: unknown type '%s'\n", sem_line, s);
            (*errs)++;
            return -1;
        }
        if(d->params != nil){
            s = type_render(t);
            fprint(2, "o9c: error: line %d: generic type '%s' needs %d argument(s)\n", sem_line,
                s, node_list_len(d->params));
            (*errs)++;
            return -1;
        }
        return 0;
    case TyParam:
        if(!is_type_param_name(t->name)){
            fprint(2, "o9c: error: line %d: type parameter '%s' is not in scope\n", sem_line, t->name);
            (*errs)++;
            return -1;
        }
        return 0;
    case TyApply:
        if(strcmp(t->name, "List") == 0){
            if(type_list_len(t->args) != 1){
                fprint(2, "o9c: error: line %d: List needs 1 type argument\n", sem_line);
                (*errs)++;
            }
        } else if(strcmp(t->name, "Dict") == 0){
            if(type_list_len(t->args) != 2){
                fprint(2, "o9c: error: line %d: Dict needs 2 type arguments\n", sem_line);
                (*errs)++;
            }
        } else {
            d = type_decl_node(t);
            if(d == nil){
                s = type_render(t);
                fprint(2, "o9c: error: line %d: unknown generic type '%s'\n", sem_line, s);
                (*errs)++;
            } else {
                arity = node_list_len(d->params);
                if(arity == 0){
                    s = type_render(t);
                    fprint(2, "o9c: error: line %d: type '%s' is not generic\n", sem_line, s);
                    (*errs)++;
                } else if(arity != type_list_len(t->args)){
                    s = type_render(t);
                    fprint(2, "o9c: error: line %d: generic type '%s' needs %d argument(s)\n", sem_line,
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

static Type* type_subst(Type *t, TypeBind *bindings);

static TypeBind*
type_bind_cons(char *name, Type *type, TypeBind *next)
{
    TypeBind *b;

    if(name == nil || type == nil)
        return next;
    b = mallocz(sizeof *b, 1);
    if(b == nil)
        sysfatal("malloc: type binding");
    b->name = e_strdup(name);
    b->type = type;
    b->next = next;
    return b;
}

static Type*
type_bind_lookup(TypeBind *bindings, char *name)
{
    TypeBind *b;

    if(name == nil)
        return nil;
    for(b = bindings; b; b = b->next)
        if(b->name != nil && strcmp(b->name, name) == 0)
            return b->type;
    return nil;
}

static TypeList*
type_list_subst(TypeList *list, TypeBind *bindings)
{
    TypeList *out;

    out = nil;
    for(; list; list = list->next)
        out = type_list_append(out, type_subst(list->type, bindings));
    return out;
}

static Type*
type_subst(Type *t, TypeBind *bindings)
{
    Type *r;

    if(t == nil)
        return nil;
    switch(t->kind){
    case TyName:
        return type_name(t->name);
    case TyParam:
        r = type_bind_lookup(bindings, t->name);
        if(r != nil)
            return r;
        return type_param(t->name);
    case TyApply:
        return type_apply(t->name, type_list_subst(t->args, bindings));
    case TyPtr:
        return type_ptr(type_subst(t->base, bindings));
    case TyArray:
        return type_array(type_subst(t->base, bindings));
    }
    return t;
}

static TypeBind*
type_bindings_for(Node *decl, Type *receiver)
{
    Node *p;
    TypeList *a;
    TypeBind *bindings;

    bindings = nil;
    if(decl == nil || receiver == nil || receiver->kind != TyApply)
        return nil;
    for(p = decl->params, a = receiver->args; p && a; p = p->next, a = a->next)
        bindings = type_bind_cons(p->name, a->type, bindings);
    return bindings;
}

static Type*
inherit_type_with_bindings(Node *m, TypeBind *bindings)
{
    if(m == nil || m->type != NInherit)
        return nil;
    if(m->typeinfo != nil)
        return type_subst(m->typeinfo, bindings);
    if(m->name != nil)
        return type_name(m->name);
    return nil;
}

static int
typed_member_lookup_in(Node *cnode, TypeBind *bindings, char *name, int method, TypedMember *out)
{
    Node *m, *p;
    Type *pt;
    TypeBind *pb;

    if(cnode == nil || name == nil)
        return 0;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            pt = inherit_type_with_bindings(m, bindings);
            p = type_decl_node(pt);
            pb = type_bindings_for(p, pt);
            if(typed_member_lookup_in(p, pb, name, method, out))
                return 1;
        }
        if(m->name == nil || strcmp(m->name, name) != 0)
            continue;
        if(method && m->type == NMethod){
            if(out != nil){
                out->node = m;
                out->owner = cnode;
                out->kind = m->type;
                out->type = type_subst(decl_typeinfo(m), bindings);
                out->bindings = bindings;
            }
            return 1;
        }
        if(!method && (m->type == NProp || m->type == NState ||
           m->type == NAtomic || m->type == NSecret || m->type == NCap)){
            if(out != nil){
                out->node = m;
                out->owner = cnode;
                out->kind = m->type;
                out->type = type_subst(decl_typeinfo(m), bindings);
                out->bindings = bindings;
            }
            return 1;
        }
    }
    return 0;
}

static int
typed_member_lookup(Type *receiver, char *name, int method, TypedMember *out)
{
    Node *cnode;
    TypeBind *bindings;

    if(out != nil)
        memset(out, 0, sizeof *out);
    cnode = type_decl_node(receiver);
    bindings = type_bindings_for(cnode, receiver);
    return typed_member_lookup_in(cnode, bindings, name, method, out);
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

static Node*
member_node(Node *cnode, char *name, int method)
{
    Node *m, *p, *r;

    if(cnode == nil || name == nil)
        return nil;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            r = member_node(p, name, method);
            if(r != nil)
                return r;
        }
        if(m->name == nil || strcmp(m->name, name) != 0)
            continue;
        if(method && m->type == NMethod)
            return m;
        if(!method && (m->type == NProp || m->type == NState ||
           m->type == NAtomic || m->type == NSecret || m->type == NCap))
            return m;
    }
    return nil;
}

static int
type_scalar_builtin(Type *t)
{
    char *a;

    if(t == nil || t->kind != TyName)
        return 0;
    a = type_builtin_abi(t->name);
    return a != nil && strcmp(a, "scalar") == 0;
}

static int type_assignable_semantic(Type *target, Type *actual);

static int
type_is_nil(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "nil") == 0;
}

static int
type_accepts_nil(Type *t)
{
    Node *d;

    if(t == nil)
        return 1;
    if(t->kind == TyPtr || t->kind == TyArray)
        return 1;
    if(t->kind == TyApply)
        return 1;
    if(t->kind == TyName){
        if(strcmp(t->name, "string") == 0 || strcmp(t->name, "chan") == 0)
            return 1;
        d = type_decl_node(t);
        return d != nil && (d->type == NClass || d->type == NInterface);
    }
    return 0;
}

static int
type_is_bool(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "bool") == 0;
}

static int
type_numeric_scalar(Type *t)
{
    if(!type_scalar_builtin(t))
        return 0;
    return !type_is_bool(t);
}

static int
type_compatible_either(Type *a, Type *b)
{
    return type_assignable_semantic(a, b) || type_assignable_semantic(b, a);
}

static int
type_assignable_semantic(Type *target, Type *actual)
{
    Node *td, *ad;
    char *ts, *as, *tc, *ac;

    if(target == nil || actual == nil)
        return 1;
    if(type_is_nil(actual))
        return type_accepts_nil(target);
    if(type_is_nil(target))
        return type_is_nil(actual);
    if(type_equal(target, actual))
        return 1;
    td = type_decl_node(target);
    ad = type_decl_node(actual);
    if(td != nil && td == ad)
        return 1;
    if(type_is_class_ref(target) && type_is_class_ref(actual)){
        tc = type_cname(target);
        ac = type_cname(actual);
        if(is_subclass(ac, tc))
            return 1;
    }
    if(type_scalar_builtin(target) && type_scalar_builtin(actual)){
        ts = type_storage_for_codegen(target);
        as = type_storage_for_codegen(actual);
        if(strcmp(ts, as) == 0)
            return 1;
    }
    return 0;
}

static void
type_mismatch_error(char *what, Type *target, Type *actual, int *errs)
{
    char *ts, *as;

    ts = target != nil ? type_render(target) : "<unknown>";
    as = actual != nil ? type_render(actual) : "<unknown>";
    fprint(2, "o9c: error: line %d: cannot %s %s to %s\n", sem_line, what, as, ts);
    (*errs)++;
}

static char*
expr_op_name(int type)
{
    switch(type){
    case NAdd: return "+";
    case NSub: return "-";
    case NMul: return "*";
    case NDiv: return "/";
    case NMod: return "%";
    case NBitAnd: return "&";
    case NBitOr: return "|";
    case NBitXor: return "^";
    case NLshift: return "<<";
    case NRshift: return ">>";
    case NEq: return "==";
    case NNe: return "!=";
    case NLt: return "<";
    case NLe: return "<=";
    case NGt: return ">";
    case NGe: return ">=";
    case NAnd: return "&&";
    case NOr: return "||";
    case NNeg: return "-";
    case NBitNot: return "~";
    case NNot: return "!";
    }
    return "?";
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
    Node *a;
    TypedMember tm;
    Type *lt, *rt, *t;
    char *legacy;

    if(e == nil)
        return type_name("void");
    switch(e->type){
    case NTry:
        /* try yields the wrapped call's type */
        return set_expr_type(e, annotate_expr_type(e->left, scope_class));
    case NIntLit:
        return set_expr_type(e, type_name("int64"));
    case NStringLit:
        return set_expr_type(e, type_name("string"));
    case NCharLit:
        return set_expr_type(e, type_name("char"));
    case NBoolLit:
        if(e->name != nil && strcmp(e->name, "nil") == 0)
            return set_expr_type(e, type_name("nil"));
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
        if(typed_member_lookup(lt, e->name, 0, &tm))
            return set_expr_type(e, tm.type);
        return set_expr_type(e, nil);
    case NSelfCall:
        for(a = e->right; a; a = a->next)
            annotate_expr_type(a, scope_class);
        if(scope_class != nil){
            lt = scope_class->typeinfo;
            if(lt == nil)
                lt = type_from_name(scope_class->qname != nil ? scope_class->qname : scope_class->name);
            if(typed_member_lookup(lt, e->name, 1, &tm))
                return set_expr_type(e, tm.type);
        }
        {
            Builtin *b = find_builtin(e->name);
            if(b != nil)
                return set_expr_type(e, type_name(b->ret));
        }
        return set_expr_type(e, nil);
    case NMsgSend:
        lt = annotate_expr_type(e->left, scope_class);
        for(a = e->right; a; a = a->next)
            annotate_expr_type(a, scope_class);
        if(lt != nil && lt->kind == TyName && lt->name != nil &&
           strcmp(lt->name, "Tabula") == 0){
            if(strcmp(e->name, "get") == 0 || strcmp(e->name, "serialize") == 0)
                return set_expr_type(e, type_name("string"));
            if(strcmp(e->name, "close") == 0)
                return set_expr_type(e, type_name("void"));
            /* add/set/first/next return int64 (status / row-present) */
            return set_expr_type(e, type_name("int64"));
        }
        if(type_is_collection(lt, "List")){
            if(strcmp(e->name, "Length") == 0)
                return set_expr_type(e, type_name("int64"));
            if(strcmp(e->name, "Add") == 0)
                return set_expr_type(e, type_name("void"));
        }
        if(type_is_collection(lt, "Dict") && strcmp(e->name, "Has") == 0)
            return set_expr_type(e, type_name("bool"));
        if(typed_member_lookup(lt, e->name, 1, &tm))
            return set_expr_type(e, tm.type);
        return set_expr_type(e, nil);
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
    Type *t;
    Node *d;

    if(n == nil || n->name == nil || n->typename == nil)
        return;
    add_type_sym_typed(n->name, n->typename, decl_typeinfo(n));
    t = decl_typeinfo(n);
    d = type_decl_node(t);
    if(d != nil && (d->type == NClass || d->type == NInterface))
        add_var_class(n->name, d->name);
}

static void
add_decl_type_syms(Node *n)
{
    for(; n; n = n->next)
        add_decl_type_sym(n);
}

/* Type checker: walks the AST and validates all member references */
/* Returns number of errors (0 = clean) */

static Type *current_return_type;

static int
member_exists(Node *cnode, char *name)
{
    Node *m, *p;
    int mt;
    if(cnode == nil) return -1;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            mt = member_exists(p, name);
            if(mt >= 0) return mt;
        }
        if(m->name && strcmp(m->name, name) == 0) return m->type;
    }
    return -1;
}

static int
method_has_body(Node *m)
{
    return m != nil && (m->flags & (NFAbstract|NFMethodDecl)) == 0;
}

static int
method_signature_equal_bound(Node *a, TypeBind *abind, Node *b, TypeBind *bbind)
{
    Node *ap, *bp;
    Type *at, *bt;

    if(a == nil || b == nil)
        return 0;
    at = type_subst(decl_typeinfo(a), abind);
    bt = type_subst(decl_typeinfo(b), bbind);
    if(!type_equal(at, bt))
        return 0;
    if(node_list_len(a->right) != node_list_len(b->right))
        return 0;
    for(ap = a->right, bp = b->right; ap && bp; ap = ap->next, bp = bp->next){
        at = type_subst(decl_typeinfo(ap), abind);
        bt = type_subst(decl_typeinfo(bp), bbind);
        if(!type_equal(at, bt))
            return 0;
    }
    return 1;
}

static Node*
local_method_node(Node *cnode, char *name)
{
    Node *m;

    if(cnode == nil || name == nil)
        return nil;
    for(m = cnode->left; m; m = m->next)
        if(m->type == NMethod && m->name != nil && strcmp(m->name, name) == 0)
            return m;
    return nil;
}

static Node*
concrete_method_node(Node *cnode, char *name)
{
    Node *m, *p, *r;

    if(cnode == nil || name == nil)
        return nil;
    m = local_method_node(cnode, name);
    if(method_has_body(m))
        return m;
    for(m = cnode->left; m; m = m->next){
        if(m->type != NInherit)
            continue;
        p = find_class(m->name);
        if(p == nil || p->type == NInterface)
            continue;
        r = concrete_method_node(p, name);
        if(r != nil)
            return r;
    }
    return nil;
}

static void
require_method_impl_bound(Node *owner, Node *req, TypeBind *reqbind, int *errs)
{
    Node *impl;

    if(owner == nil || req == nil || req->name == nil)
        return;
    if(owner->line > 0)
        sem_line = owner->line;
    impl = concrete_method_node(owner, req->name);
    if(impl == nil){
        fprint(2, "o9c: error: line %d: class '%s' must implement method '%s'\n", sem_line,
            owner->name, req->name);
        (*errs)++;
        return;
    }
    if(!method_signature_equal_bound(impl, nil, req, reqbind)){
        fprint(2, "o9c: error: line %d: method '%s' implementation in '%s' does not match inherited signature\n", sem_line,
            req->name, owner->name);
        (*errs)++;
    }
}

static void
require_method_impl(Node *owner, Node *req, int *errs)
{
    require_method_impl_bound(owner, req, nil, errs);
}

static void
require_contract_methods_bound(Node *owner, Node *contract, TypeBind *bindings, int *errs)
{
    Node *m, *p;
    Type *pt;
    TypeBind *pb;
    static int depth;

    if(owner == nil || contract == nil)
        return;
    if(depth > 64)	/* inheritance cycle; reported by check_inheritance_contract */
        return;
    depth++;
    for(m = contract->left; m; m = m->next){
        if(m->type == NInherit){
            pt = inherit_type_with_bindings(m, bindings);
            p = type_decl_node(pt);
            pb = type_bindings_for(p, pt);
            require_contract_methods_bound(owner, p, pb, errs);
        } else if(m->type == NMethod && (contract->type == NInterface ||
                  (m->flags & NFAbstract) || (m->flags & NFMethodDecl))){
            require_method_impl_bound(owner, m, bindings, errs);
        }
    }
    depth--;
}

static void
check_local_member_conflicts(Node *cnode, int *errs)
{
    Node *a, *b;

    if(cnode == nil)
        return;
    for(a = cnode->left; a; a = a->next){
        if(a->name == nil || a->type == NInherit || a->type == NDestructor)
            continue;
        for(b = a->next; b; b = b->next){
            if(b->name != nil && b->type != NInherit && b->type != NDestructor && strcmp(a->name, b->name) == 0){
                if(b->line > 0)
                    sem_line = b->line;
                fprint(2, "o9c: error: line %d: duplicate member '%s' in '%s'\n", sem_line,
                    a->name, cnode->name);
                (*errs)++;
            }
        }
    }
}

static void
check_override_compat(Node *cnode, int *errs)
{
    Node *m, *p, *parent, *inherited;
    Type *pt;
    TypeBind *pb;

    if(cnode == nil)
        return;
    for(m = cnode->left; m; m = m->next){
        if(m->type != NMethod)
            continue;
        if(m->line > 0)
            sem_line = m->line;
        for(p = cnode->left; p; p = p->next){
            if(p->type != NInherit)
                continue;
            pt = inherit_type_with_bindings(p, nil);
            parent = type_decl_node(pt);
            pb = type_bindings_for(parent, pt);
            inherited = member_node(parent, m->name, 1);
            if(inherited != nil && !method_signature_equal_bound(m, nil, inherited, pb)){
                fprint(2, "o9c: error: line %d: method '%s' in '%s' does not match inherited signature\n", sem_line,
                    m->name, cnode->name);
                (*errs)++;
            }
        }
    }
}

static void
check_inheritance_contract(Node *cnode, int *errs)
{
    Node *m, *parent;
    Type *pt;
    TypeBind *pb;
    int classparents;

    if(cnode == nil || (cnode->type != NClass && cnode->type != NStruct && cnode->type != NInterface))
        return;

    check_local_member_conflicts(cnode, errs);
    classparents = 0;
    for(m = cnode->left; m; m = m->next){
        if(m->line > 0)
            sem_line = m->line;
        if(cnode->type == NInterface && m->type != NMethod && m->type != NInherit){
            fprint(2, "o9c: error: line %d: interface '%s' may only declare methods or inherit interfaces\n", sem_line,
                cnode->name);
            (*errs)++;
        }
        if(cnode->type == NInterface && m->type == NMethod && (m->flags & NFMethodDecl) == 0){
            fprint(2, "o9c: error: line %d: interface method '%s' cannot have a body\n", sem_line, m->name);
            (*errs)++;
        }
        if(m->type == NMethod && (m->flags & NFAbstract) && (m->flags & NFMethodDecl) == 0){
            fprint(2, "o9c: error: line %d: abstract method '%s' cannot have a body\n", sem_line, m->name);
            (*errs)++;
        }
        if(m->type != NInherit)
            continue;
        pt = inherit_type_with_bindings(m, nil);
        parent = type_decl_node(pt);
        if(parent == nil)
            continue;
        if(parent == cnode || is_subclass(parent->name, cnode->name)){
            fprint(2, "o9c: error: line %d: inheritance cycle involving '%s'\n", sem_line, cnode->name);
            (*errs)++;
        }
        if(cnode->type == NStruct){
            fprint(2, "o9c: error: line %d: struct '%s' cannot inherit '%s'\n", sem_line, cnode->name, m->name);
            (*errs)++;
        } else if(cnode->type == NInterface){
            if(parent->type != NInterface){
                fprint(2, "o9c: error: line %d: interface '%s' can only inherit interfaces\n", sem_line, cnode->name);
                (*errs)++;
            }
        } else if(parent->type == NStruct || parent->type == NEnum){
            fprint(2, "o9c: error: line %d: class '%s' cannot inherit non-class/interface '%s'\n", sem_line,
                cnode->name, m->name);
            (*errs)++;
        } else if(parent->type == NClass){
            classparents++;
            if(classparents > 1){
                fprint(2, "o9c: error: line %d: class '%s' cannot inherit more than one class\n", sem_line, cnode->name);
                (*errs)++;
            }
        }
    }
    check_override_compat(cnode, errs);
    if(cnode->type == NClass && (cnode->flags & NFAbstract) == 0){
        for(m = cnode->left; m; m = m->next){
            if(m->type == NMethod && ((m->flags & NFAbstract) || (m->flags & NFMethodDecl)))
                require_method_impl(cnode, m, errs);
            if(m->type == NInherit){
                pt = inherit_type_with_bindings(m, nil);
                parent = type_decl_node(pt);
                pb = type_bindings_for(parent, pt);
                require_contract_methods_bound(cnode, parent, pb, errs);
            }
        }
    }
}

static void
typecheck_expr(Node *e, Node *scope_class, int *errs)
{
    if(e == nil) return;
    if(e->line > 0)
        sem_line = e->line;

    switch(e->type){
    case NTry:
    case NDefer:
        /* try/defer wrap a call expression — typecheck the inner call */
        typecheck_expr(e->left, scope_class, errs);
        break;
    case NProp:
    case NState:
    case NAtomic:
    case NCap:
    case NInherit:
        validate_type(e->typeinfo, errs);
        break;
    case NSecret:
        /* string secrets were desugared at parse into blob + seal/open;
         * anything still NSecret is a non-string secret, refused in v1 */
        fprint(2, "o9c: error: line %d: secret field '%s' must be string\n",
            sem_line, e->name != nil ? e->name : "?");
        (*errs)++;
        break;
    case NMethod:
        validate_type(e->typeinfo, errs);
        break;
    case NClass:
        validate_type(e->typeinfo, errs);
        {
            Node *d = type_decl_node(e->typeinfo);
            if(d != nil){
                if(d->type == NInterface){
                    fprint(2, "o9c: error: line %d: cannot instantiate interface '%s'\n", sem_line, d->name);
                    (*errs)++;
                } else if(d->flags & NFAbstract){
                    fprint(2, "o9c: error: line %d: cannot instantiate abstract class '%s'\n", sem_line, d->name);
                    (*errs)++;
                }
            }
            if(in_constructor_body && ctor_class_name != nil && e->name != nil &&
               strcmp(e->name, ctor_class_name) == 0){
                fprint(2, "o9c: error: line %d: cannot 'new %s' inside %s's own constructor "
                    "(a class cannot construct itself while it is half-built; build it in a method or factory)\n",
                    sem_line, ctor_class_name, ctor_class_name);
                (*errs)++;
            }
        }
        break;
    case NObject:
        validate_type(e->typeinfo, errs);
        if(!type_is_object_ref(e->typeinfo)){
            fprint(2, "o9c: error: line %d: object '%s' must have class or interface type\n", sem_line,
                e->qname != nil ? e->qname : e->name);
            (*errs)++;
        }
        break;
    case NLink:
        if(e->left == nil || e->left->qname == nil || resolve_object_sym(e->left->qname) == nil){
            fprint(2, "o9c: error: line %d: link source '%s' is not a declared object\n", sem_line,
                e->left && e->left->qname ? e->left->qname : e->name);
            (*errs)++;
        }
        if(e->right == nil || e->right->qname == nil || resolve_object_sym(e->right->qname) == nil){
            fprint(2, "o9c: error: line %d: link target '%s' is not a declared object\n", sem_line,
                e->right && e->right->qname ? e->right->qname : "<nil>");
            (*errs)++;
        }
        break;
    case NPropRead:
        annotate_expr_type(e, scope_class);
        /* Check: prop read, must not be a method */
        if(e->left){
            Type *lt = e->left->typeinfo;
            Node *cnode = nil;
            TypedMember tm;
            if(type_is_collection(lt, "List") || type_is_collection(lt, "Dict"))
                break;
            cnode = type_decl_node(lt);
            if(cnode == nil && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                if(cn != nil)
                    cnode = find_class(cn);
            }
            if(cnode == nil){
                if(e->left->type == NIdent && e->left->name){
                    fprint(2, "o9c: error: line %d: unknown type for '%s'\n", sem_line, e->left->name);
                    (*errs)++;
                }
            } else {
                if(typed_member_lookup(lt, e->name, 1, &tm)){
                    fprint(2, "o9c: error: line %d: '%s' is a method, not a property\n", sem_line, e->name);
                    (*errs)++;
                } else if(!typed_member_lookup(lt, e->name, 0, &tm)){
                    fprint(2, "o9c: error: line %d: '%s' has no member '%s'\n", sem_line, cnode->name, e->name);
                    (*errs)++;
                } else if(tm.node != nil && (tm.node->flags & NFPrivate) &&
                          tm.owner != scope_class){
                    /* private field: class-scoped (C#-style). obj.field is
                     * legal only inside the DECLARING class's own methods
                     * (covers both read and write — NAssign's lhs lands
                     * here too). Subclasses and externals are rejected. */
                    fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
                        tm.owner != nil ? tm.owner->name : cnode->name, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NSelfCall:
        annotate_expr_type(e, scope_class);
        /* super(args): parent-ctor chaining — typecheck args and check
         * arity against the parent's constructor. */
        if(e->name != nil && strcmp(e->name, "super") == 0){
            Node *a;
            for(a = e->right; a != nil; a = a->next)
                typecheck_expr(a, scope_class, errs);
            if(scope_class != nil){
                Node *im, *parent = nil, *pctor = nil, *m;
                for(im = scope_class->left; im != nil; im = im->next)
                    if(im->type == NInherit){ parent = find_class(im->name); break; }
                if(parent == nil){
                    fprint(2, "o9c: error: line %d: super() with no parent class\n", sem_line);
                    (*errs)++;
                } else {
                    for(m = parent->left; m != nil; m = m->next)
                        if(m->type == NMethod && m->name != nil &&
                           strcmp(m->name, parent->name) == 0){ pctor = m; break; }
                    if(pctor == nil){
                        if(node_list_len(e->right) != 0){
                            fprint(2, "o9c: error: line %d: %s has no constructor; super() takes no arguments\n",
                                sem_line, parent->name);
                            (*errs)++;
                        }
                    } else {
                        int want = node_list_len(pctor->right), got = node_list_len(e->right);
                        if(want != got){
                            fprint(2, "o9c: error: line %d: super() calls %s(%d args), got %d\n",
                                sem_line, parent->name, want, got);
                            (*errs)++;
                        }
                    }
                }
            }
            break;
        }
        {
            Type *st = nil;
            TypedMember tm;
            Builtin *bi;
            int ismethod = 0;

            if(scope_class != nil){
                st = scope_class->typeinfo;
                if(st == nil)
                    st = type_from_name(scope_class->qname != nil ? scope_class->qname : scope_class->name);
                ismethod = typed_member_lookup(st, e->name, 1, &tm);
            }
            if(!ismethod && (bi = find_builtin(e->name)) != nil){
                Node *a;
                int pi;
                if(node_list_len(e->right) != bi->argc){
                    fprint(2, "o9c: error: line %d: builtin '%s' needs %d argument(s)\n", sem_line,
                        e->name, bi->argc);
                    (*errs)++;
                } else {
                    for(a = e->right, pi = 0; a != nil && pi < bi->argc; a = a->next, pi++){
                        if(strcmp(bi->args[pi], "object") == 0){
                            /* class-typed slot (send's handle) */
                            if(type_decl_node(a->typeinfo) == nil){
                                fprint(2, "o9c: error: line %d: argument %d to '%s' must be an object handle\n", sem_line,
                                    pi + 1, e->name);
                                (*errs)++;
                            }
                            continue;
                        }
                        if(!type_assignable_semantic(type_name(bi->args[pi]), a->typeinfo)){
                            fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n", sem_line,
                                pi + 1, e->name,
                                a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
                                bi->args[pi]);
                            (*errs)++;
                        }
                    }
                }
                break;
            }
            if(scope_class == nil){
                fprint(2, "o9c: error: line %d: unknown function '%s'\n", sem_line, e->name);
                (*errs)++;
                break;
            }
            if(!ismethod && typed_member_lookup(st, e->name, 0, &tm)){
                fprint(2, "o9c: error: line %d: '%s' is a property, not a method\n", sem_line, e->name);
                (*errs)++;
            } else if(!ismethod){
                fprint(2, "o9c: error: line %d: '%s' has no method '%s'\n", sem_line,
                    scope_class->qname != nil ? scope_class->qname : scope_class->name, e->name);
                (*errs)++;
            } else if(tm.node != nil){
                tm.node->flags |= NFSelfCalled;	/* emit the o9_self_ wrapper */
                /* class-scoped private: a bare self-call is legal only when
                 * the method is declared in this very class, not inherited
                 * private from an ancestor (C#-style) */
                if((tm.node->flags & NFPrivate) && tm.owner != scope_class)
                    fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
                        tm.owner != nil ? tm.owner->name : "?", e->name), (*errs)++;
                {
                Node *p, *a;
                Type *expected;
                int pi;
                if(node_list_len(tm.node->right) != node_list_len(e->right)){
                    fprint(2, "o9c: error: line %d: method '%s' needs %d argument(s)\n", sem_line,
                        e->name, node_list_len(tm.node->right));
                    (*errs)++;
                } else {
                    for(p = tm.node->right, a = e->right, pi = 0; p && a; p = p->next, a = a->next, pi++){
                        expected = type_subst(p->typeinfo, tm.bindings);
                        if(!type_assignable_semantic(expected, a->typeinfo)){
                            fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n", sem_line,
                                pi + 1, e->name,
                                a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
                                expected != nil ? type_render(expected) : "<unknown>");
                            (*errs)++;
                        }
                    }
                }
                }
            }
        }
        break;
    case NMsgSend:
        annotate_expr_type(e, scope_class);
        /* Check: method call, must be a method, not a property */
        if(e->left){
            Type *lt = e->left->typeinfo;
            Node *cnode = nil;
            TypedMember tm;
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "Tabula") == 0){
                Node *a;
                int want = -1, got = node_list_len(e->right);
                if(strcmp(e->name, "add") == 0) want = 1;
                else if(strcmp(e->name, "set") == 0) want = 2;
                else if(strcmp(e->name, "get") == 0) want = 1;
                else if(strcmp(e->name, "first") == 0) want = 0;
                else if(strcmp(e->name, "next") == 0) want = 0;
                else if(strcmp(e->name, "serialize") == 0) want = 0;
                else if(strcmp(e->name, "close") == 0) want = 0;
                if(want < 0){
                    fprint(2, "o9c: error: line %d: Tabula has no method '%s' "
                        "(add/set/get/first/next/serialize/close)\n", sem_line, e->name);
                    (*errs)++;
                } else if(got != want){
                    fprint(2, "o9c: error: line %d: Tabula.%s takes %d argument%s, got %d\n",
                        sem_line, e->name, want, want == 1 ? "" : "s", got);
                    (*errs)++;
                }
                for(a = e->right; a != nil; a = a->next)
                    typecheck_expr(a, scope_class, errs);
                break;
            }
            if(type_is_collection(lt, "List")){
                if(strcmp(e->name, "Add") != 0 && strcmp(e->name, "Length") != 0){
                    fprint(2, "o9c: error: line %d: List has no method '%s'\n", sem_line, e->name);
                    (*errs)++;
                } else if(strcmp(e->name, "Add") == 0){
                    if(node_list_len(e->right) != 1){
                        fprint(2, "o9c: error: line %d: List.Add needs 1 argument\n", sem_line);
                        (*errs)++;
                    } else if(!type_assignable_semantic(type_list_at(lt->args, 0), e->right->typeinfo))
                        type_mismatch_error("pass", type_list_at(lt->args, 0), e->right->typeinfo, errs);
                } else if(strcmp(e->name, "Length") == 0 && e->right != nil){
                    fprint(2, "o9c: error: line %d: List.Length needs 0 arguments\n", sem_line);
                    (*errs)++;
                }
                break;
            }
            if(type_is_collection(lt, "Dict")){
                if(strcmp(e->name, "Has") != 0){
                    fprint(2, "o9c: error: line %d: Dict has no method '%s'\n", sem_line, e->name);
                    (*errs)++;
                } else if(node_list_len(e->right) != 1){
                    fprint(2, "o9c: error: line %d: Dict.Has needs 1 argument\n", sem_line);
                    (*errs)++;
                } else if(!type_assignable_semantic(type_list_at(lt->args, 0), e->right->typeinfo))
                    type_mismatch_error("pass", type_list_at(lt->args, 0), e->right->typeinfo, errs);
                break;
            }
            cnode = type_decl_node(lt);
            if(cnode == nil && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                if(cn != nil)
                    cnode = find_class(cn);
            }
            if(cnode == nil){
                if(e->left->type == NIdent && e->left->name){
                    fprint(2, "o9c: error: line %d: unknown type for '%s'\n", sem_line, e->left->name);
                    (*errs)++;
                }
            } else {
                if(typed_member_lookup(lt, e->name, 0, &tm)){
                    fprint(2, "o9c: error: line %d: '%s' is a property, not a method\n", sem_line, e->name);
                    (*errs)++;
                } else if(!typed_member_lookup(lt, e->name, 1, &tm)){
                    fprint(2, "o9c: error: line %d: '%s' has no member '%s'\n", sem_line, cnode->name, e->name);
                    (*errs)++;
                } else if(tm.node != nil){
                    Node *p, *a;
                    Type *expected;
                    int pi;
                    /* private is class-scoped (C#-style): obj.method() is
                     * legal when the CALL SITE is inside the declaring
                     * class (same-class other.bump() ok); rejected from
                     * anywhere else, including subclasses. Matches the
                     * bare self-call rule (tm.owner != scope_class). */
                    if((tm.node->flags & NFPrivate) && tm.owner != scope_class)
                        fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
                            tm.owner != nil ? tm.owner->name : cnode->name, e->name), (*errs)++;
                    if(node_list_len(tm.node->right) != node_list_len(e->right)){
                        fprint(2, "o9c: error: line %d: method '%s' needs %d argument(s)\n", sem_line,
                            e->name, node_list_len(tm.node->right));
                        (*errs)++;
                    } else {
                        for(p = tm.node->right, a = e->right, pi = 0; p && a; p = p->next, a = a->next, pi++){
                            expected = type_subst(p->typeinfo, tm.bindings);
                            if(!type_assignable_semantic(expected, a->typeinfo)){
                                fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n", sem_line,
                                    pi + 1, e->name,
                                    a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
                                    expected != nil ? type_render(expected) : "<unknown>");
                                (*errs)++;
                            }
                        }
                    }
                }
            }
        }
        break;
    case NAssign:
        annotate_expr_type(e, scope_class);
        if(e->left != nil && e->right != nil &&
           !type_assignable_semantic(e->left->typeinfo, e->right->typeinfo))
            type_mismatch_error("assign", e->left->typeinfo, e->right->typeinfo, errs);
        break;
    case NDelete:
        if(e->left == nil || e->left->name == nil || get_var_class(e->left->name) == nil){
            fprint(2, "o9c: error: line %d: delete needs a class instance\n", sem_line);
            (*errs)++;
        }
        break;
    case NReturn:
        annotate_expr_type(e, scope_class);
        if(current_return_type != nil &&
           !type_assignable_semantic(current_return_type, e->typeinfo))
            type_mismatch_error("return", current_return_type, e->typeinfo, errs);
        break;
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
        annotate_expr_type(e, scope_class);
        if(e->left != nil && !type_numeric_scalar(e->left->typeinfo)){
            fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        if(e->right != nil && !type_numeric_scalar(e->right->typeinfo)){
            fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        break;
    case NAnd:
    case NOr:
        annotate_expr_type(e, scope_class);
        if((e->left != nil && !type_is_bool(e->left->typeinfo)) ||
           (e->right != nil && !type_is_bool(e->right->typeinfo))){
            fprint(2, "o9c: error: line %d: operator '%s' needs bool operands\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        break;
    case NEq:
    case NNe:
        annotate_expr_type(e, scope_class);
        if(e->left != nil && e->right != nil &&
           !type_compatible_either(e->left->typeinfo, e->right->typeinfo)){
            fprint(2, "o9c: error: line %d: operator '%s' needs compatible operands\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        break;
    case NLt:
    case NLe:
    case NGt:
    case NGe:
        annotate_expr_type(e, scope_class);
        if((e->left != nil && !type_numeric_scalar(e->left->typeinfo)) ||
           (e->right != nil && !type_numeric_scalar(e->right->typeinfo))){
            fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        break;
    case NNeg:
    case NBitNot:
        annotate_expr_type(e, scope_class);
        if(e->left != nil && !type_numeric_scalar(e->left->typeinfo)){
            fprint(2, "o9c: error: line %d: operator '%s' needs numeric operand\n", sem_line, expr_op_name(e->type));
            (*errs)++;
        }
        break;
    case NNot:
        annotate_expr_type(e, scope_class);
        if(e->left != nil && !type_is_bool(e->left->typeinfo)){
            fprint(2, "o9c: error: line %d: operator '!' needs bool operand\n", sem_line);
            (*errs)++;
        }
        break;
    case NLocalVar:
        validate_type(e->typeinfo, errs);
        add_decl_type_sym(e);
        annotate_expr_type(e->left, scope_class);
        if(e->left != nil && e->left->type == NClass){
            Node *d = type_decl_node(e->left->typeinfo);
            if(d != nil){
                if(d->type == NInterface){
                    fprint(2, "o9c: error: line %d: cannot instantiate interface '%s'\n", sem_line, d->name);
                    (*errs)++;
                } else if(d->flags & NFAbstract){
                    fprint(2, "o9c: error: line %d: cannot instantiate abstract class '%s'\n", sem_line, d->name);
                    (*errs)++;
                }
            }
            if(in_constructor_body && ctor_class_name != nil && e->left->name != nil &&
               strcmp(e->left->name, ctor_class_name) == 0){
                fprint(2, "o9c: error: line %d: cannot 'new %s' inside %s's own constructor "
                    "(a class cannot construct itself while it is half-built; build it in a method or factory)\n",
                    sem_line, ctor_class_name, ctor_class_name);
                (*errs)++;
            }
        }
        if(e->left != nil && e->left->type == NSelfCall && e->left->name != nil &&
           strcmp(e->left->name, "lookup") == 0){
            /* Counter c = lookup("oid") — result takes the declared type */
            if(type_decl_node(e->typeinfo) == nil){
                fprint(2, "o9c: error: line %d: lookup needs a class-typed target\n", sem_line);
                (*errs)++;
            }
        } else if(e->left != nil && !type_assignable_semantic(e->typeinfo, e->left->typeinfo))
            type_mismatch_error("initialize", e->typeinfo, e->left->typeinfo, errs);
        /* Check legacy-only typename is a known type if no structured type was attached. */
        if(e->typeinfo == nil && e->typename && !is_primitive(e->typename) && find_class(e->typename) == nil){
            fprint(2, "o9c: error: line %d: unknown type '%s'\n", sem_line, e->typename);
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
    if(n->line > 0)
        sem_line = n->line;
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
            check_inheritance_contract(c, errs);
            pop_type_params();
            continue;
        }
        if(c->type == NMethod){
            Type *saved_return;
            int saved_ctor;
            typecheck_expr(c, scope_class, errs);
            check_node(c->right, scope_class, errs);
            mark = mark_type_syms();
            add_decl_type_syms(c->right);
            saved_return = current_return_type;
            current_return_type = decl_typeinfo(c);
            /* A constructor is a method named after its class.  Constructing
             * an object inside a constructor is forbidden (half-built state
             * is hard to reason about); flag it so NClass can reject it. */
            saved_ctor = in_constructor_body;
            in_constructor_body = (scope_class != nil && c->name != nil &&
                scope_class->name != nil && strcmp(c->name, scope_class->name) == 0);
            if(in_constructor_body)
                ctor_class_name = scope_class->name;
            check_node(c->left, scope_class, errs);
            in_constructor_body = saved_ctor;
            if(!saved_ctor) ctor_class_name = nil;
            current_return_type = saved_return;
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
    case NTry: return "NTry";
    case NDefer: return "NDefer";
    case NBitNot: return "NBitNot";
    case NNeg: return "NNeg";
    case NIf: return "NIf";
    case NIfElse: return "NIfElse";
    case NElse: return "NElse";
    case NElseIf: return "NElseIf";
    case NWhile: return "NWhile";
    case NLocalVar: return "NLocalVar";
    case NMsgSend: return "NMsgSend";
    case NSelfCall: return "NSelfCall";
    case NDelete: return "NDelete";
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
    if(n->flags & NFAbstract)
        print(" abstract");
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
    if(n->line > 0)
        print(" line=%d", n->line);
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

/* ---- import resolution (see IMPORTS.md) ----
 *
 * Runs before prescan/parse. Scans the source for import lines, resolves
 * each to a real file within the project subtree, and splices the named
 * declarations' SOURCE into the input so the one parse produces full
 * class nodes (members + bodies), which then transpile normally.
 *
 *   import "path";              -> all top-level decls from path
 *   from "path" import A, B;    -> only decls named A, B (+ deps come
 *                                  along because the whole file's decls
 *                                  are spliced; unnamed ones are inert
 *                                  if unused — kept simple: splice all,
 *                                  selective names are advisory/dep hint)
 *
 * Path rule: resolved relative to import_base_dir, and MUST stay within
 * that dir's subtree (no .., no absolute). A project is self-contained.
 */

static char *imp_loaded[64];
static int imp_nloaded;

/* Canonicalize a/b/../c style path in place (fold . and ..). Returns -1
 * if a .. would climb above the start (escapes the subtree). */
static int
path_within_subtree(char *rel)
{
    char *parts[128];
    int np = 0, i, depth = 0;
    char *p, *save, out[1024];

    if(rel[0] == '/')
        return -1;	/* absolute: rejected */
    /* split on '/', track depth; a '..' at depth 0 escapes */
    for(p = rel; *p != '\0'; ){
        save = p;
        while(*p != '\0' && *p != '/') p++;
        if(*p == '/') *p++ = '\0';
        if(strcmp(save, "") == 0 || strcmp(save, ".") == 0)
            continue;
        if(strcmp(save, "..") == 0){
            if(depth == 0) return -1;	/* climbs above base */
            depth--; np--;
            continue;
        }
        if(np < nelem(parts)){ parts[np++] = save; depth++; }
    }
    out[0] = '\0';
    for(i = 0; i < np; i++){
        if(i > 0) strcat(out, "/");
        strcat(out, parts[i]);
    }
    strcpy(rel, out);
    return 0;
}

/* Read a whole file into a malloc'd NUL-terminated buffer; *len set. */
static char*
read_whole_file(char *path, long *len)
{
    int fd;
    long n, total = 0, cap = 8192;
    char *buf;

    fd = open(path, OREAD);
    if(fd < 0) return nil;
    buf = malloc(cap);
    while((n = read(fd, buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){ cap *= 2; buf = realloc(buf, cap); }
    }
    close(fd);
    buf[total] = '\0';
    *len = total;
    return buf;
}

/* Strip the `func main() { ... }` from imported source (only the root
 * file's main is the program entry). Balances braces from the first
 * `func main`. Edits in place. */
static void
strip_imported_main(char *src)
{
    char *m = strstr(src, "func main");
    char *p;
    int depth;
    if(m == nil) return;
    p = strchr(m, '{');
    if(p == nil) return;
    depth = 0;
    do {
        if(*p == '{') depth++;
        else if(*p == '}') depth--;
        p++;
    } while(depth > 0 && *p != '\0');
    /* blank out main..closing brace */
    while(m < p){ *m++ = ' '; }
}

/* Append imported source (main stripped, import lines are handled by the
 * outer scan) to the growing combined buffer. */
static char*
splice_append(char *dst, long *dlen, long *dcap, char *add, long addlen)
{
    if(*dlen + addlen + 2 >= *dcap){
        while(*dlen + addlen + 2 >= *dcap) *dcap *= 2;
        dst = realloc(dst, *dcap);
    }
    dst[(*dlen)++] = '\n';
    memmove(dst + *dlen, add, addlen);
    *dlen += addlen;
    dst[*dlen] = '\0';
    return dst;
}

/* Resolve one import path string to a full path within the subtree;
 * returns malloc'd full path or nil (with an error printed). */
static char*
resolve_import_path(char *rel, int line)
{
    char clean[1024], full[1200];

    strncpy(clean, rel, sizeof clean - 1);
    clean[sizeof clean - 1] = '\0';
    if(path_within_subtree(clean) < 0){
        fprint(2, "o9c: error: line %d: import path '%s' escapes the "
            "importing file's directory; imports must stay within the "
            "project subtree\n", line, rel);
        semantic_errors++;
        return nil;
    }
    snprint(full, sizeof full, "%s/%s", import_base_dir, clean);
    return strdup(full);
}

/* Pull imported files' declarations into input_buf. One level deep of
 * nested imports is handled by re-scanning the combined buffer. */
static void
resolve_imports(void)
{
    char *combined;
    long clen, ccap = 16384;
    char *p, *nl;
    int line = 0, any = 0;

    combined = malloc(ccap);
    clen = 0;
    combined[0] = '\0';

    /* Walk input line by line; import lines are resolved+spliced,
     * every other line is copied through. */
    for(p = input_buf; p != nil && *p != '\0'; p = (nl != nil ? nl + 1 : nil)){
        char *ls, *le, linebuf[1024];
        int llen;
        nl = strchr(p, '\n');
        le = nl != nil ? nl : p + strlen(p);
        llen = le - p;
        line++;
        if(llen >= (int)sizeof linebuf) llen = sizeof linebuf - 1;
        memmove(linebuf, p, llen);
        linebuf[llen] = '\0';

        /* detect leading `import "..."`.  `from "..." import ...` is
         * rejected: it would splice the whole file identically to
         * `import`, so the name list would be a lie.  One honest verb.
         * (A real filtering `from` can return when it actually filters.) */
        ls = linebuf;
        while(*ls == ' ' || *ls == '\t') ls++;
        if(strncmp(ls, "from ", 5) == 0){
            fprint(2, "o9c: error: line %d: 'from ... import' is not "
                "supported; use `import \"path\";` (it pulls the file's "
                "declarations). Selective import is not yet implemented.\n", line);
            semantic_errors++;
            continue;	/* drop the line */
        }
        if(strncmp(ls, "import ", 7) == 0){
            char *q1 = strchr(ls, '"'), *q2;
            if(q1 != nil && (q2 = strchr(q1 + 1, '"')) != nil){
                char path[1024], *full, *fsrc;
                long flen;
                int k, seen;
                *q2 = '\0';
                strncpy(path, q1 + 1, sizeof path - 1);
                path[sizeof path - 1] = '\0';
                full = resolve_import_path(path, line);
                if(full != nil){
                    /* dedup: each file spliced once */
                    seen = 0;
                    for(k = 0; k < imp_nloaded; k++)
                        if(strcmp(imp_loaded[k], full) == 0){ seen = 1; break; }
                    if(!seen && imp_nloaded < nelem(imp_loaded)){
                        imp_loaded[imp_nloaded++] = full;
                        fsrc = read_whole_file(full, &flen);
                        if(fsrc == nil){
                            fprint(2, "o9c: error: line %d: cannot open import '%s'\n", line, path);
                            semantic_errors++;
                        } else {
                            strip_imported_main(fsrc);
                            combined = splice_append(combined, &clen, &ccap, fsrc, strlen(fsrc));
                            free(fsrc);
                        }
                    }
                }
                any = 1;
            }
            /* drop the import line itself (do not copy it through) */
            continue;
        }
        /* ordinary line: copy through */
        combined = splice_append(combined, &clen, &ccap, linebuf, llen);
    }

    if(any){
        free(input_buf);
        input_buf = combined;
        input_len = clen;
    } else {
        free(combined);
    }
}

int
main(int argc, char **argv)
{
    long n, total = 0, cap = 8192;
    int dumpast, i, fd = 0;
    char *srcpath = nil;

    dumpast = 0;
    for(i = 1; i < argc; i++){
        if(strcmp(argv[i], "-ast") == 0)
            dumpast = 1;
        else if(argv[i][0] != '-')
            srcpath = argv[i];	/* optional source file (else stdin) */
    }

    /* Import resolution needs the importing file's directory. With a
     * source path, imports resolve relative to its dir; from stdin they
     * fall back to cwd (".") — existing `o9c < src` invocations keep
     * working, and the test tree's cwd is the project root. */
    if(srcpath != nil){
        char *slash;
        fd = open(srcpath, OREAD);
        if(fd < 0) sysfatal("open %s: %r", srcpath);
        import_base_dir = strdup(srcpath);
        slash = strrchr(import_base_dir, '/');
        if(slash != nil) *slash = '\0'; else strcpy(import_base_dir, ".");
    } else {
        import_base_dir = strdup(".");
    }

    input_buf = malloc(cap);
    if(input_buf == nil) sysfatal("malloc: input buffer");
    while((n = read(fd, input_buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            input_buf = realloc(input_buf, cap);
            if(input_buf == nil) sysfatal("realloc: input buffer");
        }
    }
    input_len = total;
    if(fd != 0) close(fd);

    resolve_imports();	/* splice imported decls into input_buf */
    if(semantic_errors > 0)	/* import errors: stop before parse cascades */
        exits("import");

    prescan();
    
    if(yyparse() == 0){
        if(typecheck(ast_root) == 0){
            if(dumpast)
                dump_ast(ast_root);
            else
                codegen(ast_root);
        } else
            exits("typecheck");
    } else {
        fprint(2, "o9c: parse failed\n");
        exits("parse");
    }
    exits(nil);
    return 0;
}
