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
    NDefer,
    NSpawn,
    NRawC,
    NUse
};

enum {
    NFAbstract = 1<<0,
    NFMethodDecl = 1<<1,
    NFSelfCalled = 1<<2,
    NFPrivate = 1<<3,	/* class-scoped; not reachable through the app facade */
    NFFunction = 1<<4,	/* a synthesized function-class (fixed spawn template) */
    NFMain = 1<<5	/* reserved top-level program bootstrap block */
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
typedef struct CDep CDep;
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

struct CDep {
    char *name;
    char *header;
    char *include;
    char *archive;
    char *source;
    char *requires;
    int system;
    int override;
    int used;
    CDep *next;
    CDep *usednext;
};
CDep *cdeps;
CDep *used_cdeps;
CDep *used_cdeps_tail;
char *project_root = ".";

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
static void load_builtin_cdeps(void);
static void load_project_cdeps(void);
static void use_cdep(char *name, int line, int *errs);
static void emit_cdeps(void);

void add_type_sym(char *name, char *typename);
char* get_type_sym(char *name);
void clear_type_syms(void);
int is_subclass(char *sub, char *parent);

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
        if(strcmp(t->name, "MountTable") == 0)
            return "O9MountTable*";	/* namespace policy/apply handle */
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
        if(strcmp(t->name, "Task") == 0)
            return "O9Task*";	/* handle; <T> only types await's return */
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

static int storage_is_o9string(char *s);

static char*
type_cast_for_codegen(Type *t)
{
    Node *d;
    char *s;

    if(t == nil)
        return "vlong";
    s = type_storage_for_codegen(t);
    if(strcmp(s, "char*") == 0 || storage_is_o9string(s))
        return s;
    if(strcmp(s, "vlong") == 0 || strcmp(s, "uvlong") == 0 ||
       strcmp(s, "long") == 0 || strcmp(s, "ulong") == 0 ||
       strcmp(s, "int") == 0 || strcmp(s, "uint") == 0 ||
       strcmp(s, "intptr") == 0 || strcmp(s, "uintptr") == 0 ||
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
type_is_array(Type *t)
{
    return t != nil && t->kind == TyArray;
}

static Type*
type_array_elem(Type *t)
{
    return type_is_array(t) ? t->base : nil;
}

static int
type_is_void(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "void") == 0;
}

static int
type_is_string(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "string") == 0;
}

static int
storage_is_o9string(char *s)
{
    return s != nil && strcmp(s, "O9String*") == 0;
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
    if(strcmp(t, "O9String*") == 0) return "%p";
    return type_fmt_for_codegen(typeinfo_from_legacy(t));
}

char*
type_cast(char *t)
{
    if(t == nil) return "vlong";
    if(strcmp(t, "char*") == 0 || strcmp(t, "O9String*") == 0) return t;
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
    int len;

    if(t == nil) return 1;
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0) return 1;
    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;
    if(strcmp(t, "int64") == 0) return 1;
    if(strcmp(t, "uint64") == 0) return 1;
    if(strcmp(t, "int32") == 0) return 1;
    if(strcmp(t, "uint32") == 0) return 1;
    if(strcmp(t, "int16") == 0) return 1;
    if(strcmp(t, "uint16") == 0) return 1;
    if(strcmp(t, "int8") == 0) return 1;
    if(strcmp(t, "uint8") == 0) return 1;
    if(strcmp(t, "byte") == 0) return 1;
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
    if(strcmp(t, "MountTable") == 0) return 1;	/* handle type, primitive-like decl */
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
        if((m->type == NProp || m->type == NState) && m->name && strcmp(m->name, name) == 0){
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
        if((m->type == NProp || m->type == NState) && m->name && strcmp(m->name, name) == 0)
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
%token <name> TINTLIT TSTRINGLIT TCHARLIT TRAWC
%token TCLASS TINTERFACE TSTRUCT TENUM TMODULE TIMPORT TFUNC TFUNCTION TMAIN TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TLIST TTASK TNIL TABSTRACT TDELETE TSPAWN TUSE
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TOBJECT TTRUE TFALSE TARROW
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
 
%type <node> program top_levels top_level class_decl class_head interface_decl interface_head struct_decl struct_head enum_decl enum_vals enum_val module_decl module_head import_decl object_decl member_list member member_body var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename name_ref type_name_ref decl_name generic_name enum_name member_name spawn_name dep_name dep_list param_list param call_args call_arg main_decl func_top_level function_decl for_init for_cond for_step else_clause generic_opt generic_names abstract_opt
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

spawn_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

dep_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TSTRINGLIT { $$ = mk(NIdent, $1, nil, nil, nil); }
    ;

dep_list:
    /* empty */ { $$ = nil; }
    | dep_list dep_name { $$ = append_node($1, mk(NIdent, $2->name, nil, nil, nil)); }
    | dep_list ',' { $$ = $1; }
    | dep_list ';' { $$ = $1; }
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
    | TTASK '<' type_args '>' { $$ = type_apply("Task", $3); }
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
    | main_decl
    | func_top_level
    | function_decl
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

main_decl:
    TMAIN '{' stmt_list '}'
    {
        $$ = mk(NMethod, "main", "void", $3, nil);
        $$->flags |= NFMain;
    }
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $6, nil);
    }
    ;

/* `function name(params) type { body }` — desugars to a templated class
 * (fixed spawn skeleton + the one user method `run`). See CONCURRENCY.md. */
function_decl:
    TFUNCTION TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        $$ = synth_function_class($2->name, $6, $4, $8);
    }
    | TFUNCTION TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = synth_function_class($2->name, nil, $4, $7);
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
        /* `atomic` is not a user-facing field type. The runtime uses
         * 9front atomics internally for ARC/tasks/counters, but language
         * concurrency is actors, spawn/Task, streams, and 9P sessions. */
        fprint(2, "o9c: error: 'atomic' is not a language keyword. "
            "Use object dispatch/streams/spawn for concurrency; low-level "
            "atomics are internal runtime machinery or raw C in a function.\n");
        semantic_errors++;
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
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
    | TUSE '{' dep_list '}' { $$ = mk(NUse, nil, nil, $3, nil); }
    | TRAWC { $$ = mk(NRawC, $1, nil, nil, nil); }
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
    /* spawn f(args): run function-class f concurrently; evaluates to a
     * Task<T> (join handle). name = function, right = args. */
    | TSPAWN spawn_name '(' call_args ')' {
        Node *n = mk(NSpawn, $2->name, nil, nil, $4);
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

/* Synthesize the templated class for a `function` (see CONCURRENCY.md):
 * a fixed, user-uneditable skeleton (3 framework props) + the user's one
 * method named `run`. Desugars to a normal NClass so the whole existing
 * class pipeline (struct, dispatch loop, proccreate, ARC) handles it.
 *   fname   = the function's source name (becomes the class identity)
 *   rettn   = return typename node (nil -> void)
 *   params  = the method's param list
 *   body    = the method body (stmt_list)
 */
static Node*
synth_function_class(char *fname, Node *rettn, Node *params, Node *body)
{
    char *source, *name;
    Node *cls, *members, *meth;

    source = qualify_source_name(current_module, fname);
    name = mangle_source_name(source);
    cls = mk(NClass, name, nil, nil, nil);
    set_node_names(cls, source, name);
    cls->flags |= NFFunction;	/* marks a function-class: template invariant enforced */

    /* Fixed framework-owned props — the standardized envelope. Order is
     * stable; the runtime spawn/teardown reads them by name. */
    members = mk(NProp, "__spawn_index", "int64", nil, nil);
    members->flags |= NFPrivate;
    members->next = mk(NProp, "__spawn_state", "int64", nil, nil);
    members->next->flags |= NFPrivate;
    /* __spawn_result is a chan (object-IPC endpoint, auto-created). */
    members->next->next = mk(NStream, "__spawn_result", "chan", nil, nil);
    members->next->next->flags |= NFPrivate;

    /* The one user method, named `run`. */
    if(rettn != nil)
        meth = mk_typed(NMethod, "run", rettn, body, params);
    else
        meth = mk(NMethod, "run", "void", body, params);
    meth->flags |= NFSelfCalled;	/* callable directly too */
    members->next->next->next = meth;

    cls->left = members;
    add_class(cls->name, cls);
    return cls;
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

static void
raw_append(char **buf, int *len, int *cap, int c)
{
    char *nb;

    if(*len + 2 >= *cap){
        *cap *= 2;
        nb = realloc(*buf, *cap);
        if(nb == nil)
            sysfatal("realloc: raw c block");
        *buf = nb;
    }
    (*buf)[(*len)++] = c;
    (*buf)[*len] = '\0';
}

static int
try_raw_c_block(char **out)
{
    int save_pos, save_npush, save_push[8], save_line;
    int c, depth, mode, esc, len, cap;
    char *buf;

    save_pos = input_pos;
    save_npush = npush;
    memmove(save_push, pushback, sizeof pushback);
    save_line = cur_line;

    do
        c = lex_getc();
    while(c != Beof && isspace(c));
    if(c != '{'){
        input_pos = save_pos;
        npush = save_npush;
        memmove(pushback, save_push, sizeof pushback);
        cur_line = save_line;
        return 0;
    }

    cap = 256;
    len = 0;
    buf = malloc(cap);
    if(buf == nil)
        sysfatal("malloc: raw c block");
    buf[0] = '\0';

    depth = 1;
    mode = 0;	/* 0 normal, 1 string, 2 char, 3 line comment, 4 block comment */
    esc = 0;
    while((c = lex_getc()) != Beof){
        if(mode == 0){
            if(c == '"'){
                mode = 1;
                raw_append(&buf, &len, &cap, c);
                continue;
            }
            if(c == '\''){
                mode = 2;
                raw_append(&buf, &len, &cap, c);
                continue;
            }
            if(c == '/'){
                int nc = lex_getc();
                if(nc == '/'){
                    mode = 3;
                    raw_append(&buf, &len, &cap, c);
                    raw_append(&buf, &len, &cap, nc);
                    continue;
                }
                if(nc == '*'){
                    mode = 4;
                    raw_append(&buf, &len, &cap, c);
                    raw_append(&buf, &len, &cap, nc);
                    continue;
                }
                if(nc != Beof)
                    lex_ungetc(nc);
                raw_append(&buf, &len, &cap, c);
                continue;
            }
            if(c == '{'){
                depth++;
                raw_append(&buf, &len, &cap, c);
                continue;
            }
            if(c == '}'){
                depth--;
                if(depth == 0){
                    *out = buf;
                    return 1;
                }
                raw_append(&buf, &len, &cap, c);
                continue;
            }
            raw_append(&buf, &len, &cap, c);
            continue;
        }
        if(mode == 1 || mode == 2){
            raw_append(&buf, &len, &cap, c);
            if(esc){
                esc = 0;
                continue;
            }
            if(c == '\\'){
                esc = 1;
                continue;
            }
            if((mode == 1 && c == '"') || (mode == 2 && c == '\''))
                mode = 0;
            continue;
        }
        if(mode == 3){
            raw_append(&buf, &len, &cap, c);
            if(c == '\n')
                mode = 0;
            continue;
        }
        if(mode == 4){
            raw_append(&buf, &len, &cap, c);
            if(c == '*'){
                int nc = lex_getc();
                if(nc == '/'){
                    raw_append(&buf, &len, &cap, nc);
                    mode = 0;
                } else if(nc != Beof)
                    lex_ungetc(nc);
            }
        }
    }
    *out = buf;
    return 1;
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

            if(strcmp(buf, "c") == 0){
                char *raw;
                if(try_raw_c_block(&raw)){
                    yylval.name = raw;
                    return TRAWC;
                }
            }
            
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
            if(strcmp(buf, "function") == 0) return TFUNCTION;
            if(strcmp(buf, "main") == 0) return TMAIN;
            if(strcmp(buf, "spawn") == 0) return TSPAWN;
            if(strcmp(buf, "use") == 0) return TUSE;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "delete") == 0) return TDELETE;
            if(strcmp(buf, "far") == 0) return TFAR;
            if(strcmp(buf, "Dict") == 0) return TDICT;
            if(strcmp(buf, "Task") == 0) return TTASK;	/* dedicated token, like List/Dict */
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
            if(strcmp(buf, "byte") == 0) return TTYPE;
            if(strcmp(buf, "void") == 0) return TTYPE;
            if(strcmp(buf, "string") == 0) return TTYPE;
            if(strcmp(buf, "int") == 0) return TTYPE;
            if(strcmp(buf, "uint") == 0) return TTYPE;
            if(strcmp(buf, "short") == 0) return TTYPE;
            if(strcmp(buf, "long") == 0) return TTYPE;
            if(strcmp(buf, "char") == 0) return TTYPE;
            if(strcmp(buf, "intptr") == 0) return TTYPE;
            if(strcmp(buf, "uintptr") == 0) return TTYPE;
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
enum { O9_MSG_FRAMES = 64 };
static int msg_frame_next;		/* compiler-assigned NMsgSend frames per statement */
int has_return = 0;			/* 1 when a return statement was emitted */
int try_seen = 0;			/* 1 when a try expr needs the done: label */
Node *defer_list = nil;			/* deferred calls for the current method (LIFO) */
Node *cur_class;			/* current class being codegen'd, for type lookups */
int in_constructor_body = 0;		/* 1 while typechecking a constructor body */
char *ctor_class_name = nil;		/* the class whose ctor body is being checked */
int new_tmp_id = 0;

static void
msg_frame_reset(void)
{
    msg_frame_next = 0;
}

static int
msg_frame_alloc(void)
{
    if(msg_frame_next >= O9_MSG_FRAMES)
        sysfatal("too many method-send expressions in one statement");
    return msg_frame_next++;
}

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

static void
gen_c_string_literal(char *text)
{
    char *s;

    print("\"");
    for(s = text; s != nil && *s; s++){
        if(*s == '\n') print("\\n");
        else if(*s == '\t') print("\\t");
        else if(*s == '\\') print("\\\\");
        else if(*s == '"') print("\\\"");
        else print("%c", *s);
    }
    print("\"");
}

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
    case NSpawn:
        /* spawn f(args) -> o9_spawn_<f>(args). Returns O9Task*. The
         * per-function helper (emitted with the function-class) owns
         * construction + forwarder + non-blocking dispatch. */
        {
            char *fq = qualify_source_name(current_module, e->name);
            char *fc = mangle_source_name(fq);
            Node *a;
            print("o9_spawn_%s(", fc);
            for(a = e->right; a; a = a->next){
                if(a != e->right) print(", ");
                gen_expr(a);
            }
            print(")");
        }
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
            print("o9_string_new(");
            gen_c_string_literal(e->name);
            print(", %d)", strlen(e->name));
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
    case NClass:
        if(e->typeinfo != nil && e->typeinfo->kind == TyName &&
           e->typeinfo->name != nil && strcmp(e->typeinfo->name, "Tabula") == 0){
            int argc = node_list_len(e->right);
            if(argc == 1){
                print("o9_tab_open(");
                gen_expr(e->right);
                print(")");
            } else if(argc == 2){
                print("o9_tab_new(");
                gen_expr(e->right);
                print(", ");
                gen_expr(e->right->next);
                print(")");
            } else
                print("nil /* invalid Tabula constructor */");
            break;
        }
        if(e->typeinfo != nil && e->typeinfo->kind == TyName &&
           e->typeinfo->name != nil && strcmp(e->typeinfo->name, "MountTable") == 0){
            print("o9_mount_table_new(");
            if(e->right != nil)
                gen_expr(e->right);
            else
                print("nil");
            print(")");
            break;
        }
        print("0 /* unsupported new expression: %s */", e->name != nil ? e->name : "?");
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
                            print("(O9String*)(uintptr)(");
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
            /* Task<T> methods: t.await() -> o9_task_await(t). The receiver
             * is an O9Task* handle. await returns T (value), sets per-proc
             * error on a spawned failure (so `try t.await()` propagates). */
            if(lt != nil && lt->kind == TyApply && lt->name != nil &&
               strcmp(lt->name, "Task") == 0 && strcmp(e->name, "await") == 0){
                char *rt = type_storage_for_codegen(type_list_at(lt->args, 0));
                print("(%s)o9_task_await(", rt); gen_expr(e->left); print(")");
                break;
            }
            /* Tabula methods: the receiver is an O9Tabula* handle, so
             * t.method(args) lowers to o9_tab_method(t, args). */
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "Tabula") == 0){
                char *fn = nil;
                if(strcmp(e->name, "schema") == 0) fn = "o9_tab_schema";
                else if(strcmp(e->name, "has") == 0) fn = "o9_tab_has";
                else if(strcmp(e->name, "add") == 0) fn = "o9_tab_add";
                else if(strcmp(e->name, "write") == 0) fn = "o9_tab_write";
                else if(strcmp(e->name, "set") == 0) fn = "o9_tab_set";
                else if(strcmp(e->name, "get") == 0) fn = "o9_tab_get";
                else if(strcmp(e->name, "first") == 0) fn = "o9_tab_first";
                else if(strcmp(e->name, "next") == 0) fn = "o9_tab_next";
                else if(strcmp(e->name, "read") == 0) fn = "o9_tab_read";
                else if(strcmp(e->name, "serialize") == 0) fn = "o9_tab_serialize";
                else if(strcmp(e->name, "query") == 0) fn = "o9_tab_query";
                else if(strcmp(e->name, "flush") == 0) fn = "o9_tab_flush";
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
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "MountTable") == 0){
                char *fn = nil;
                if(strcmp(e->name, "allowRoot") == 0) fn = "o9_mount_table_allow_root";
                else if(strcmp(e->name, "dir") == 0) fn = "o9_mount_table_dir";
                else if(strcmp(e->name, "bind") == 0) fn = "o9_mount_table_bind";
                else if(strcmp(e->name, "mountsrv") == 0) fn = "o9_mount_table_mountsrv";
                else if(strcmp(e->name, "schema") == 0) fn = "o9_mount_table_schema";
                else if(strcmp(e->name, "has") == 0) fn = "o9_mount_table_has";
                else if(strcmp(e->name, "get") == 0) fn = "o9_mount_table_get";
                else if(strcmp(e->name, "first") == 0) fn = "o9_mount_table_first";
                else if(strcmp(e->name, "next") == 0) fn = "o9_mount_table_next";
                else if(strcmp(e->name, "read") == 0) fn = "o9_mount_table_read";
                else if(strcmp(e->name, "serialize") == 0) fn = "o9_mount_table_serialize";
                else if(strcmp(e->name, "query") == 0) fn = "o9_mount_table_query";
                else if(strcmp(e->name, "flush") == 0) fn = "o9_mount_table_flush";
                else if(strcmp(e->name, "validate") == 0) fn = "o9_mount_table_validate";
                else if(strcmp(e->name, "apply") == 0) fn = "o9_mount_table_apply";
                else if(strcmp(e->name, "close") == 0) fn = "o9_mount_table_close";
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
                    print("o9_dict_hass(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
                    break;
                }
            }
        }
        /* c.method(args...) -> try o9_dispatch_call (asm), fallback to obj9_msgSend (CSP/9P) */
        {
            char *retst = nil;
            int retptr = 0;
            int nargs = 0, d;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            if(e->typeinfo != nil){
                retst = type_storage_for_codegen(e->typeinfo);
                retptr = storage_pointerish(retst);
            }
            if(retptr)
                print("(%s)(uintptr)(", retst);
            /* Every method send in a source statement gets a compiler-owned
             * frame.  C does not guarantee sibling argument evaluation order,
             * so depth alone is not enough: f(a.get(), b.get()) must not
             * reuse __o9fr[0] for both calls. */
            d = msg_frame_alloc();
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
                    if(type_is_class_ref(a->typeinfo)){
                        /* class-typed arg: pass a pointer to the Client
                         * (the impl derefs it into a local value). */
                        print("(vlong)(uintptr)&(");
                        gen_expr(a);
                        print(")");
                    } else if(type_storage_pointerish(a->typeinfo)){
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
            if(retptr)
                print(")");
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
                    } else if(strcmp(t, "char*") == 0 || storage_is_o9string(t) ||
                              strcmp(t, "O9Dict") == 0 || strcmp(t, "O9Slice") == 0){
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
                gen_c_string_literal(a->name);
            } else if(a->type == NStringLit && a->next != nil && strchr(a->name, '%') != nil){
                /* Explicit format string with value args: pass through */
                gen_c_string_literal(a->name);
                for(a = a->next; a; a = a->next){
                    print(", ");
                    if(type_is_string(a->typeinfo)){
                        print("o9_string_data("); gen_expr(a); print(")");
                    } else {
                        gen_expr(a);
                    }
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
                    } else if(type_is_string(a2->typeinfo))
                        print("%%s");
                    else
                        print("%%lld");
                }
                print("\"");
                for(a2 = a; a2; a2 = a2->next){
                    if(a2->type == NStringLit)
                        continue;
                    print(", ");
                    if(type_is_string(a2->typeinfo)){
                        print("o9_string_data("); gen_expr(a2); print(")");
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
            } else if(type_is_array(lt)){
                Type *et = type_array_elem(lt);
                print("(*(%s*)o9_slice_get(&", type_storage_for_codegen(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
            } else if(type_is_collection(lt, "Dict")){
                Type *vt = type_list_at(lt->args, 1);
                print("((%s)o9_dict_gets(&", type_storage_for_codegen(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
            } else if(e->right && e->right->type == NStringLit){
                /* Legacy dict access fallback */
                print("o9_dict_gets(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
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
        print("\t{\n\t\tchar __addr[128]; char *__addrp;\n\t\t__addrp = o9_string_cstr(");
        gen_expr(first_arg);
        print(");\n\t\tif(__addrp != nil){ snprint(__addr, sizeof __addr, \"%%s\", __addrp); free(__addrp); o9_connect(&%s, __addr, \"%s\", %d); }\n", target, cn, dval);
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
    print("\t{ char *__ce = o9_get_call_err(); if(__ce != nil){ __o9r->err = __ce; goto done; } }\n");
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
    msg_frame_reset();
    /* fail("msg"): set the method's error and jump to the exit.  Reuses
     * the same done: mechanism as return — errors are values, no
     * unwinding.  Only meaningful inside a method body. */
    if(s->type == NSelfCall && s->name != nil && strcmp(s->name, "fail") == 0){
        if(in_method_body){
            has_return = 1;	/* ensure the done: label is emitted */
            print("\t__o9r->err = ");
            if(s->right != nil){
                print("o9_string_data(");
                gen_expr(s->right);
                print(")");
            } else
                print("\"failed\"");
            print(";\n\tgoto done;\n");
        } else {
            /* outside a method: emit as a diagnostic + return */
            print("\tfprint(2, \"fail: %%s\\n\", ");
            if(s->right != nil){
                print("o9_string_data(");
                gen_expr(s->right);
                print(")");
            } else print("\"failed\"");
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
    case NRawC:
        print("\t/* raw C begin */\n");
        print("%s", s->name != nil ? s->name : "");
        print("\n\t/* raw C end */\n");
        break;
    case NUse:
        break;
    case NLocalVar:
        if(is_primitive(s->typename) || type_is_array(s->typeinfo)){
            print("\t%s %s;\n", type_storage_for_codegen(s->typeinfo), s->name);
            if(type_is_array(s->typeinfo)){
                print("\to9_slice_init(&%s, sizeof(%s));\n", s->name,
                    type_storage_for_codegen(type_array_elem(s->typeinfo)));
                if(s->left){
                    print("\t%s = ", s->name); gen_expr(s->left); print(";\n");
                    if(is_try(s->left)) gen_try_check();
                }
            } else if(type_is_collection(s->typeinfo, "List")){
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
                        print("\t\tchar __addr[128]; char *__addrp;\n");
                        print("\t\t__addrp = o9_string_cstr(");
                        gen_expr(first_arg);
                        print(");\n");
                        print("\t\tif(__addrp != nil){ snprint(__addr, sizeof __addr, \"%%s\", __addrp); free(__addrp); o9_connect(&%s, __addr, \"%s\", %d); }\n", s->name, cn, dval);
                    }
                    print("\t\t%s.distance = %d;\n", s->name, dval);
                    /* Send constructor args (skip address, send rest) */
                    if(rest > 0){
                        Node *ca;
                        int ai = 0;
                        print("\t\tvlong __args_%s[%d];\n", s->name, rest);
                        for(ca = first_arg->next; ca; ca = ca->next){
                            print("\t\t__args_%s[%d] = ", s->name, ai);
                            if(type_storage_pointerish(ca->typeinfo)){
                                print("(vlong)(uintptr)("); gen_expr(ca); print(")");
                            } else
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
         * teardown, then exits). Unregister first so new lookups cannot
         * acquire a handle while the actor is draining its destroy. */
        print("\to9_registry_unregister(\"%s\");\n", s->name);
        print("\tobj9_msgSendN(&%s, nil, 0x%lux, nil, 0);\n", s->name, o9_hash("destroy"));
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
            } else if(type_is_array(lt)){
                Type *et = type_array_elem(lt);
                Type *rt = s->right != nil ? s->right->typeinfo : nil;
                char *st = type_storage_for_codegen(et);
                if(type_is_class_ref(et) && type_is_class_ref(rt)){
                    print("\t{ %s __v; memmove(&__v, &", st); gen_expr(s->right); print(", sizeof(%s)); o9_slice_setgrow(&", st);
                } else {
                    print("\t{ %s __v = ", st); gen_expr(s->right); print("; o9_slice_setgrow(&");
                }
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", &__v); }\n");
                break;
            } else if(type_is_collection(lt, "Dict")){
                print("\to9_dict_sets(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", (void*)("); gen_expr(s->right); print("));\n");
                break;
            } else if(s->left->right && s->left->right->type == NStringLit){
                print("\to9_dict_sets(&");
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
            if(mt == NProp || mt == NState){
                Node *fieldnode = member_node(c, s->left->name, 0);
                Type *ft = decl_typeinfo(fieldnode);
                char *t = type_storage_for_codegen(ft);
                Node *d = type_decl_node(ft);
                char field[128];
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
                print("\t{ char *__ce = o9_get_call_err(); if(__ce != nil){ __o9r->err = __ce; goto done; } }\n");
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
    print("typedef o9_AsmTable %s_AsmTable;\n\n", c->name);
    print("typedef struct %s_Client {\n\tint fd;\n\tvoid *shm_base;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n\tchar srvname[64];\n\tchar cachepath[128];\n\tchar oid[64];\n\tvlong gen;\n", c->name);
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
        if(m->type == NProp || m->type == NState)
            print("\t%s %s;\n", type_storage_for_codegen(m->typeinfo), m->name);
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
        if((m->type == NProp || m->type == NState) &&
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
        if((m->type == NProp || m->type == NState) &&
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
    } else if(storage_is_o9string(t)){
        print("\to9_state_set(%s, \"%s\", o9_string_data(%s));\n",
            stateexpr, name, fieldexpr);
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
        if(n->type == NObject)
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
        if(m->type == NProp || m->type == NState){
            Node *d = type_decl_node(m->typeinfo);
            if(type_is_class_ref(m->typeinfo)){
                /* class-typed field: a live handle (embedded Client), not
                 * persistable state — zero it, no state column write. */
                print("\tmemset(&%s->%s, 0, sizeof(%s));\n", ptr, m->name, type_storage_for_codegen(m->typeinfo));
                continue;
            }
            if(type_is_collection(m->typeinfo, "Dict"))
                print("\to9_dict_init(&%s->%s);\n", ptr, m->name);
            else if(type_is_array(m->typeinfo))
                print("\to9_slice_init(&%s->%s, sizeof(%s));\n", ptr, m->name,
                    type_storage_for_codegen(type_array_elem(m->typeinfo)));
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
        /* private field: don't expose its offset in the facade-reachable
         * status cache (#7). */
        if(m->type == NProp && !(m->flags & NFPrivate)) print("\t\tp += snprint(p, sizeof %s - (p-%s), \"d:%%ld:%%ld\\n\", %ldL, (long)o9_offsetof(%s_Internal, %s));\n", bufname, bufname, o9_hash(m->name), classname, m->name);
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
        if(m->type == NProp || m->type == NState ||
           m->type == NSecret || m->type == NCap){
            /* private field: not part of the facade-reachable status
             * surface (#7). */
            if(m->flags & NFPrivate)
                continue;
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
            } else if(strcmp(t, "O9Slice") == 0){
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<slice>\\n\");\n");
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(storage_is_o9string(t)){
                    print("\t\treadstr(r, o9_string_data(s->%s));\n", m->name);
                } else if(strcmp(c_type_fmt(t), "%s") == 0){
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
            } else if(strcmp(t, "O9Slice") == 0){
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\trespond(r, \"slice property not writable\"); return;\n");
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(storage_is_o9string(t)){
                    print("\t\to9_string_release(s->%s);\n", m->name);
                    print("\t\ts->%s = o9_string_new(r->ifcall.data, r->ifcall.count);\n", m->name);
                } else if(strcmp(c_type_fmt(t), "%s") == 0){
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
        if(m->type == NStream) {
            print("\tif(((%s_Internal*)self)->%s != nil){ void *__box; while((__box = nbrecvp(((%s_Internal*)self)->%s)) != nil) free(__box); chanfree(((%s_Internal*)self)->%s); }\n",
                childname, m->name, childname, m->name, childname, m->name);
        }
        if(m->type == NProp || m->type == NState) {
            char *t = type_storage_for_codegen(m->typeinfo);
            if(storage_is_o9string(t)) {
                print("\to9_string_release(((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(strcmp(t, "char*") == 0) {
                print("\tfree(((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(strcmp(t, "O9Dict") == 0) {
                print("\to9_dict_free(&((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(strcmp(t, "O9Slice") == 0) {
                print("\to9_slice_free(&((%s_Internal*)self)->%s);\n", childname, m->name);
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
            print("\tvlong __o9fr[%d][12];\n\tUSED(__o9fr);\n", O9_MSG_FRAMES);
            /* Unpack params from msg->args (packed as vlong array for now) */
            {
                Node *p;
                int pi = 0;
                for(p = m->right; p; p = p->next){
                    char *st = type_storage_for_codegen(p->typeinfo);
                    if(type_is_class_ref(p->typeinfo))
                        /* class-typed param: the caller packs a pointer to
                         * its Client (the fat struct can't be one vlong).
                         * Deref into a local VALUE so the param behaves
                         * exactly like a class-typed local — every
                         * receiver-use site (&param) then works unchanged. */
                        print("\t%s %s = *(%s*)(uintptr)((vlong*)msg->args)[%d];\n", st, p->name, st, pi);
                    else if(storage_pointerish(st))
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
                    msg_frame_reset();
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
							if(type_is_class_ref(pn->typeinfo))
								print("\t%s *__arg%d = (%s*)(uintptr)((vlong*)__a)[%d];\n", st, pi, st, pi+1);
							else if(storage_pointerish(st))
								print("\t%s __arg%d = (%s)(uintptr)((vlong*)__a)[%d];\n", st, pi, st, pi+1);
							else
								print("\t%s __arg%d = ((vlong*)__a)[%d];\n", st, pi, pi+1);
						}
						print("\tvlong __args[%d];\n", np);
						for(pn = m->right, pi = 0; pn; pn = pn->next, pi++){
							if(type_is_class_ref(pn->typeinfo) || type_storage_pointerish(pn->typeinfo))
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
				print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_set_call_err(__r->err); ((vlong*)__a)[0] = 0; }\n");
				print("\telse { o9_set_call_err(nil); ((vlong*)__a)[0] = (vlong)(uintptr)__r->ret; }\n");
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
						print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_set_call_err(__r->err); __v = 0; }\n");
						print("\telse { o9_set_call_err(nil); __v = (%s)__r->ret; }\n", rst);
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
            print("\tvlong __o9fr[%d][12];\n\tUSED(__o9fr);\n", O9_MSG_FRAMES);
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
    print("\tn = snprint(out+w, nout-w, \"objects:\\n\"); w += n;\n");
    print("\tn = o9_object_store_serialize(o9_objects_%s, out+w, nout-w); w += n;\n", c->name);
    print("\tif(w < nout-1){ out[w++] = '\\n'; out[w] = '\\0'; }\n");
    print("\tfor(i = 0; i < %s_ninstances && w < nout-1; i++){\n", c->name);
    print("\t\tn = snprint(out+w, nout-w, \"%%s:\\n\", %s_instances[i].name); w += n;\n", c->name);
    print("\t\tn = o9_state_serialize(%s_instances[i].inst->state, out+w, nout-w); w += n;\n", c->name);
    print("\t\tif(w < nout-1){ out[w++] = '\\n'; out[w] = '\\0'; }\n");
    print("\t}\n");
    print("\treturn w;\n}\n\n");
    /* listinstances (#8): append \" <name>\" per live instance so the root
     * status can list instances, not just classes. */
    print("static int %s_listinstances(char *out, int nout){\n", c->name);
    print("\tint i, w = 0, n;\n");
    print("\tif(out == nil || nout <= 0) return 0;\n");
    print("\tfor(i = 0; i < %s_ninstances && w < nout-1; i++){\n", c->name);
    print("\t\tn = snprint(out+w, nout-w, \" %%s\", %s_instances[i].name); w += n;\n", c->name);
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
    print("\t\tp += snprint(p, sizeof statusbuf - (p-statusbuf), \"objectstore private\\n\");\n");
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
            char *fmt, *cast;
            /* SECURITY (#7): the per-class handler must also skip private
             * methods + the constructor. Latent today (the flat facade
             * doesn't expose these per-method files as paths), but if
             * object paths return, private members must not become
             * readable — same rule as the ctl/facade seams. */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;	/* constructor */
            fmt = type_fmt_for_codegen(m->typeinfo);
            cast = type_cast_for_codegen(m->typeinfo);
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            print("\t\tO9Reply *__o9rep = r->fid->aux;\n");
            print("\t\tif(__o9rep == nil){ respond(r, \"no pending reply\"); return; }\n");
            print("\t\tif(__o9rep->err != nil)\n");
            print("\t\t\tsnprint(buf, sizeof buf, \"error: %%s\\n\", __o9rep->err);\n");
            print("\t\telse\n");
            if(type_is_string(m->typeinfo)){
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", o9_string_data((O9String*)__o9rep->ret));\n");
            } else if(strcmp(fmt, "%s") == 0){
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
        if(m->type == NProp){
            char *t, *fmt, *cast;
            Node *d;
            /* SECURITY (#7): private fields must not be readable through a
             * per-class prop path. Latent (flat facade doesn't expose
             * these paths now), but defense-in-depth for if they return. */
            if(m->flags & NFPrivate)
                continue;
            t = type_storage_for_codegen(m->typeinfo);
            fmt = type_fmt_for_codegen(m->typeinfo);
            cast = type_cast_for_codegen(m->typeinfo);
            d = type_decl_node(m->typeinfo);
            if(type_is_class_ref(m->typeinfo)){
                /* class-typed field is a live handle, not a readable value */
                print("\tif(strcmp(name, \"%s\") == 0){ readstr(r, \"<handle>\\n\"); respond(r, nil); return; }\n", m->name);
            } else if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&inst->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s); respond(r, nil); return;\n\t}\n", m->name);
            } else if(strcmp(t, "O9Slice") == 0){
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<slice>\\n\"); respond(r, nil); return;\n\t}\n");
            } else if(storage_is_o9string(t)) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", o9_string_data(inst->%s));\n", m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
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
    print("\t\t\t{ char __nb[128]; snprint(__nb, sizeof __nb, \"ok new %%s\\n\", f[1]); o9app_put_status(r, __nb); o9app_put_result(r, __nb); }\n");
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
            /* ARITY (finding #5): a network boundary must not silently
             * default missing args to 0 or ignore extras. Require exactly
             * np args after `method Class.inst name` (tokens f[3..]). */
            print("\t\t\t\tif(nf - 3 != %d){ char __ab[96]; snprint(__ab, sizeof __ab, \"error: %s takes %d arg(s), got %%d\\n\", nf-3); o9app_put_status(r, __ab); o9app_put_result(r, \"\"); respond(r, nil); return; }\n",
                np, m->name, np);
            if(np > 0){
                int pi;
                print("\t\t\t\tvlong __wargs[%d] = {0};\n", np);
                /* TYPED PARSING (finding #4): parse each arg per its
                 * DECLARED type, not blindly as strtoll. int-like ->
                 * strtoll; string -> the string pointer (as vlong);
                 * class/Tabula handles cannot be marshaled over a text
                 * ctl line -> reject. */
                for(p = m->right, pi = 0; p; p = p->next, pi++){
                    char *pt = p->typename != nil ? p->typename : "vlong";
                    print("\t\t\t\tv = strchr(f[%d], '='); v = v ? v+1 : f[%d];\n", pi+3, pi+3);
                    if(type_is_class_ref(p->typeinfo)){
                        print("\t\t\t\t{ o9app_put_status(r, \"error: %s: object-handle args not callable over ctl\\n\"); o9app_put_result(r, \"\"); respond(r, nil); return; }\n", m->name);
                    } else if(strcmp(pt, "string") == 0){
                        print("\t\t\t\t__wargs[%d] = (vlong)(uintptr)o9_string_from_c(v);\n", pi);
                    } else if(strcmp(pt, "Tabula") == 0){
                        print("\t\t\t\t{ o9app_put_status(r, \"error: %s: Tabula args not callable over ctl\\n\"); o9app_put_result(r, \"\"); respond(r, nil); return; }\n", m->name);
                    } else {
                        print("\t\t\t\t__wargs[%d] = strtoll(v, nil, 0);\n", pi);
                    }
                }
            }
            print("\t\t\t\t{ O9Msg __wm = {0x%lux, %s, %d, chancreate(sizeof(void*), 0)};\n",
                o9_hash(m->name), np > 0 ? "__wargs" : "nil", np);
            print("\t\t\t\tsendp(target->dispatch_chan, &__wm);\n");
            /* REQUEST CONCURRENCY: drop srv->slock while blocked on the
             * actor's reply so OTHER client requests can run meanwhile
             * (the lib9p srvrelease/srvacquire idiom). Without this the
             * whole app serializes on one slow call. Safe now that the
             * session follows r (no global cur_session to clobber). */
            print("\t\t\t\tsrvrelease(r->srv);\n");
            print("\t\t\t\tO9Reply *__o9rep = recvp(__wm.replyc);\n");
            print("\t\t\t\tsrvacquire(r->srv);\n");
            /* Roles (SESSIONS.md): success/error -> STATUS, the return
             * value -> DATA. o9app_put_* route to the current session
             * (or o9app_lastdata for the root-ctl path). */
            print("\t\t\t\tif(__o9rep->err != nil){\n");
            print("\t\t\t\t\tchar __eb[256]; snprint(__eb, sizeof __eb, \"error: %%s\\n\", __o9rep->err);\n");
            print("\t\t\t\t\to9app_put_status(r, __eb); o9app_put_result(r, \"\");\n");
            print("\t\t\t\t} else {\n");
            print("\t\t\t\t\to9app_put_status(r, \"ok\\n\");\n");
            if(type_is_void(m->typeinfo)){
                print("\t\t\t\t\to9app_put_result(r, \"\");\n");
            } else {
                char *fmt = type_fmt_for_codegen(m->typeinfo);
                char *cast = type_cast_for_codegen(m->typeinfo);
                print("\t\t\t\t\t{ char __rb[4096];\n");
                if(type_is_string(m->typeinfo))
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%%s\\n\", o9_string_data((O9String*)__o9rep->ret));\n");
                else if(strcmp(fmt, "%s") == 0)
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%%s\\n\", (char*)__o9rep->ret);\n");
                else
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
                print("\t\t\t\t\to9app_put_result(r, __rb); }\n");
            }
            print("\t\t\t\t}\n");
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
            /* SECURITY (#7): no per-method write file for private methods
             * or the constructor. */
            if(m->flags & NFPrivate)
                continue;
            if(m->name != nil && c->name != nil && strcmp(m->name, c->name) == 0)
                continue;
            for(p = m->right; p; p = p->next) np++;
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            if(np > 0){
                print("\t\tvlong __wargs[%d] = {0};\n", np);
                if(m->right != nil && type_is_string(m->right->typeinfo))
                    print("\t\t__wargs[0] = (vlong)(uintptr)o9_string_new(r->ifcall.data, r->ifcall.count);\n");
                else
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
        if(m->type == NProp){
            char *t;
            Node *d;
            /* SECURITY (#7): private fields not writable via a per-class
             * prop path. */
            if(m->flags & NFPrivate)
                continue;
            t = type_storage_for_codegen(m->typeinfo);
            d = type_decl_node(m->typeinfo);
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
            } else if(strcmp(t, "O9Slice") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){ respond(r, \"slice property not writable\"); return; }\n", m->name);
            } else if(storage_is_o9string(t)) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\to9_string_release(inst->%s);\n", m->name);
                print("\t\tinst->%s = o9_string_new(r->ifcall.data, r->ifcall.count);\n", m->name);
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

    /* Spawn helper for a function-class: o9_spawn_<C>(typed args) ->
     * O9Task*. Constructs a one-shot instance, sends run(args) WITHOUT
     * waiting, and starts a forwarder proc that owns the wait (recvp the
     * reply, push it into the task's channel, reap the instance). NSpawn
     * lowers to a call of this. See CONCURRENCY.md. */
    if(c->flags & NFFunction){
        Node *rm = nil, *pn;
        int np = 0, pi;
        for(rm = c->left; rm != nil; rm = rm->next)
            if(rm->type == NMethod && rm->name != nil && strcmp(rm->name, "run") == 0)
                break;
        for(pn = (rm ? rm->right : nil); pn; pn = pn->next) np++;
        /* forwarder context + proc */
        print("typedef struct O9SpawnCtx_%s { Channel *replyc; O9Task *task; %s_Internal *inst; } O9SpawnCtx_%s;\n",
            c->name, c->name, c->name);
        print("static void o9_spawn_forward_%s(void *v){\n", c->name);
        print("\tO9SpawnCtx_%s *ctx = v;\n", c->name);
        print("\tO9Reply *__r = recvp(ctx->replyc);\n");
        print("\tsendp((Channel*)o9_task_chan(ctx->task), __r);\t/* deliver value+error to the Task */\n");
        print("\t/* reap the one-shot instance */\n");
        print("\t{ O9Msg *__dm = mallocz(sizeof(O9Msg), 1); __dm->sel = 0x%lux; __dm->replyc = nil;\n", o9_hash("destroy"));
        print("\t  sendp(ctx->inst->dispatch_chan, __dm); }\n");
        print("\tchanfree(ctx->replyc); free(ctx);\n");
        print("}\n");
        /* per-function spawn-id counter */
        print("static int o9_spawn_id_%s;\n", c->name);
        /* the helper: signature from run's params */
        print("O9Task *o9_spawn_%s(", c->name);
        for(pn = (rm ? rm->right : nil), pi = 0; pn; pn = pn->next, pi++){
            if(pi) print(", ");
            print("%s __a%d", type_storage_for_codegen(pn->typeinfo), pi);
        }
        if(np == 0) print("void");
        print("){\n");
        print("\tint __id = o9_spawn_id_%s++;\n", c->name);
        print("\tchar __nm[64]; snprint(__nm, sizeof __nm, \"%s#%%d\", __id);\n", c->name);
        print("\tO9Task *__task = o9_task_new(__id);\n");
        /* construct the one-shot instance (mirrors gen_local_new) */
        print("\t%s_Internal *__inst = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
        print("\tmemset(__inst, 0, sizeof(%s_Internal));\n", c->name);
        print("\t__inst->dispatch_chan = chancreate(sizeof(void*), 10);\n");
        print("\t__inst->distance = -1;\n");
        print("\t__inst->state = o9_state_create_path(o9app_root, \"%s\", __nm, o9_state_cols_%s, %d);\n",
            c->name, c->name, count_state_cols(c));
        { char ptr[64]; snprint(ptr, sizeof ptr, "__inst"); gen_init_internal_state(c, ptr); }
        print("\t__inst->__spawn_index = __id;\n");
        print("\t__inst->__spawn_state = 1;\t/* running */\n");
        print("\tproccreate(%s_loop, __inst, 65536);\n", c->name);
        print("\t%s_record_instance(__nm, __inst);\n", c->name);
        /* pack args + send run() with a private replyc (non-blocking) */
        print("\tChannel *__replyc = chancreate(sizeof(void*), 1);\n");
        if(np > 0){
            print("\tvlong *__args = malloc(%d*sizeof(vlong));\n", np);
            for(pn = (rm ? rm->right : nil), pi = 0; pn; pn = pn->next, pi++){
                if(type_is_class_ref(pn->typeinfo) || type_storage_pointerish(pn->typeinfo))
                    print("\t__args[%d] = (vlong)(uintptr)__a%d;\n", pi, pi);
                else
                    print("\t__args[%d] = (vlong)__a%d;\n", pi, pi);
            }
        }
        print("\t{ O9Msg *__wm = mallocz(sizeof(O9Msg), 1);\n");
        print("\t  __wm->sel = 0x%lux; __wm->args = %s; __wm->nargs = %d; __wm->replyc = __replyc;\n",
            o9_hash("run"), np > 0 ? "__args" : "nil", np);
        print("\t  sendp(__inst->dispatch_chan, __wm); }\n");
        /* forwarder owns the wait */
        print("\t{ O9SpawnCtx_%s *__ctx = mallocz(sizeof(O9SpawnCtx_%s), 1);\n", c->name, c->name);
        print("\t  __ctx->replyc = __replyc; __ctx->task = __task; __ctx->inst = __inst;\n");
        print("\t  proccreate(o9_spawn_forward_%s, __ctx, 32*1024); }\n", c->name);
        print("\treturn __task;\n}\n");
    }
    /* Per-app facade: register this class INTO the shared app server.
     * No Srv/tree/post of its own — those are o9_app_start's job.  The
     * flat tree already exists; the class just registers its handlers and
     * creates its boot instance (recorded in the registry, no dir). */
    o9_note_registered(c->name);	/* boot calls o9_register_class_<C> */
    print("void o9_register_class_%s(void) {\n", c->name);
    print("\to9app_register_handler(\"%s\", fsread_%s, fswrite_%s, (void*(*)(char*))%s_find_instance, %s_dumpstate, %s_listinstances);\n", c->name, c->name, c->name, c->name, c->name, c->name);
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
        if(n->type == NMethod && n->name != nil && strcmp(n->name, "main") == 0 &&
                  (n->flags & NFMain))
            return n;
    }
    for(n = root; n; n = n->next){
        if(n->type == NModule){
            m = find_main_func(n->left);
            if(m != nil)
                return m;
        }
    }
    return nil;
}

static int
count_root_main_blocks(Node *root)
{
    Node *n;
    int nmain;

    nmain = 0;
    for(n = root; n; n = n->next){
        if(n->type == NMethod && n->name != nil && strcmp(n->name, "main") == 0 &&
                (n->flags & NFMain))
            nmain++;
    }
    return nmain;
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
    emit_cdeps();
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
    print("\tint (*listinst)(char*, int);\t/* <C>_listinstances: append \" name\" per live instance */\n");
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
    print("static void o9app_register_handler(char *name, void (*rd)(Req*,void*), void (*wr)(Req*,void*), void *(*find)(char*), int (*dump)(char*,int), int (*listinst)(char*,int)){\n");
    print("\tif(o9app_nclasses >= nelem(o9app_classes)) return;\n");
    print("\to9app_classes[o9app_nclasses].name = name;\n");
    print("\to9app_classes[o9app_nclasses].read = rd;\n");
    print("\to9app_classes[o9app_nclasses].write = wr;\n");
    print("\to9app_classes[o9app_nclasses].find = find;\n");
    print("\to9app_classes[o9app_nclasses].dumpstate = dump;\n");
    print("\to9app_classes[o9app_nclasses].listinst = listinst;\n");
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
    /* aux tag: both O9Export and O9Session live in File->aux; the first
     * field discriminates them (destroyfid only has the Fid). */
    print("enum { O9AUX_EXPORT = 1, O9AUX_SESSION = 2 };\n");
    print("struct O9Export { int tag; QLock lock; char *data; int ndata; };\n\n");
    print("static int o9app_export_name_ok(char *s){\n");
    print("\tuchar *p;\n");
    print("\tif(s == nil || s[0] == '\\0' || strcmp(s, \".\") == 0 || strcmp(s, \"..\") == 0) return 0;\n");
    print("\tfor(p = (uchar*)s; *p != '\\0'; p++)\n");
    print("\t\tif(*p < ' ' || *p == 0177 || *p == '/') return 0;\n");
    print("\treturn 1;\n");
    print("}\n\n");

    /* exports/ is a served-tree DIRECTORY (part of the application file
     * tree, reachable through the mount) — NOT an on-disk directory.
     * Objects publish Tabulae into it at runtime via createfile; the
     * serialized bytes live in the child File's aux. */
    /* Flat root handlers.  The four files share these; ctl routes by the
     * line's Class.inst to a class handler, the rest aggregate. */
    /* Per-session conversation state (SESSIONS.md). Fixes the per-caller
     * race: results/status live on the SESSION, not a global mailbox. A
     * session is allocated by reading `clone`; its dir + ctl/data/status
     * are createfile'd into the served root, each carrying the O9Session*
     * in File->aux. */
    /* Sessions: a GROW-AND-REUSE POOL (the Plan 9 /net clone model, with
     * List-style growth). Slot dirs <i>/{ctl,data,status} are created once
     * and NEVER removed — clone hands out a free slot, a slot frees when
     * its client's fids clunk (flag flip, no tree mutation). This dissolves
     * both the leak (slots are bounded by peak concurrency, then recycled)
     * and the reap re-entrancy fault (nothing is ever removefile'd). */
    print("typedef struct O9Session O9Session;\n");
    /* QLock per session guards data/status against concurrent request
     * handlers (once srvrelease lets requests interleave). */
    print("struct O9Session { int tag; int id; File *dir; QLock lock; long ref; int inuse; char data[4096]; char status[256]; };\n");
    print("static O9Session **o9app_sessions;\t/* the pool (grows) */\n");
    print("static int o9app_nsessions;\t/* slots created */\n");
    print("static int o9app_sessions_cap;\n");
    print("static QLock o9app_pool_lock;\t/* guards pool alloc/reuse */\n");
    print("static char o9app_lastdata[4096];\t/* root-ctl fire-and-forget reply */\n");
    /* NO global cur_session. The session is DYNAMIC REQUEST STATE — it
     * follows the Req*, derived from r->fid->file->aux. A global would be
     * clobbered by a concurrent request while the first is inside
     * ch->write (blocked on the actor's reply). */
    print("static O9Session *o9app_req_session(Req *r){\n");
    print("\tvoid *aux;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil) return nil;\n");
    print("\taux = r->fid->file->aux;\n");
    print("\tif(aux != nil && *(int*)aux == O9AUX_SESSION) return aux;\n");
    print("\treturn nil;\n");
    print("}\n");
    print("static void o9app_put_result(Req *r, char *s){\n");
    print("\tO9Session *sess = o9app_req_session(r);\n");
    print("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->data, sizeof sess->data, \"%%s\", s); qunlock(&sess->lock); }\n");
    print("\telse snprint(o9app_lastdata, sizeof o9app_lastdata, \"%%s\", s);\t/* root-ctl fire-and-forget */\n");
    print("}\n");
    print("static void o9app_put_status(Req *r, char *s){\n");
    print("\tO9Session *sess = o9app_req_session(r);\n");
    print("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->status, sizeof sess->status, \"%%s\", s); qunlock(&sess->lock); }\n");
    print("}\n");
    /* Create one new pool slot: <i>/{ctl,data,status} into the stable root
     * (single createfile-into-stable-parent — the safe pattern; done at
     * GROWTH only, never destroyed). */
    print("static O9Session *o9app_grow_session(void){\n");
    print("\tO9Session *s; char nm[32]; File *dir;\n");
    print("\tif(o9app_nsessions >= o9app_sessions_cap){\n");
    print("\t\tint ncap = o9app_sessions_cap ? o9app_sessions_cap*2 : 8;\n");
    print("\t\tO9Session **np = realloc(o9app_sessions, ncap*sizeof(O9Session*));\n");
    print("\t\tif(np == nil) return nil;\n");
    print("\t\to9app_sessions = np; o9app_sessions_cap = ncap;\n");
    print("\t}\n");
    print("\ts = mallocz(sizeof *s, 1);\n");
    print("\tif(s == nil) return nil;\n");
    print("\ts->tag = O9AUX_SESSION;\n");
    print("\ts->id = o9app_nsessions;\n");
    print("\tsnprint(nm, sizeof nm, \"%%d\", s->id);\n");
    print("\tdir = createfile(o9app_tree->root, nm, \"o9\", DMDIR|0555, s);\n");
    print("\tif(dir == nil){ free(s); return nil; }\n");
    print("\ts->dir = dir;\n");
    print("\tcreatefile(dir, \"ctl\", \"o9\", 0222, s);\n");
    print("\tcreatefile(dir, \"data\", \"o9\", 0444, s);\n");
    print("\tcreatefile(dir, \"status\", \"o9\", 0444, s);\n");
    print("\to9app_sessions[o9app_nsessions++] = s;\n");
    print("\treturn s;\n}\n");
    /* clone: a session is an EXPLICIT CONVERSATION owned by the client
     * until they `echo close > <id>/ctl` — NOT an open-fid lifetime. That
     * is the whole point of path-visible clone (shell use: echo>ctl then
     * cat data are separate opens; the session must persist between them).
     * Reuse a CLOSED slot (inuse==0), else grow. Clear its buffers on
     * (re)alloc. Pool-locked. */
    print("static O9Session *o9app_alloc_session(void){\n");
    print("\tint i; O9Session *s = nil;\n");
    print("\tqlock(&o9app_pool_lock);\n");
    print("\tfor(i = 0; i < o9app_nsessions; i++)\n");
    print("\t\tif(o9app_sessions[i]->inuse == 0){ s = o9app_sessions[i]; break; }\n");
    print("\tif(s == nil) s = o9app_grow_session();\n");
    print("\tif(s == nil){ qunlock(&o9app_pool_lock); return nil; }\n");
    print("\ts->inuse = 1; s->ref = 0;\n");
    print("\tqlock(&s->lock);\n");
    print("\ts->data[0] = '\\0';\n");
    print("\tsnprint(s->status, sizeof s->status, \"ready\\n\");\n");
    print("\tqunlock(&s->lock);\n");
    print("\tqunlock(&o9app_pool_lock);\n");
    print("\treturn s;\n}\n");
    /* close: the ONLY thing that ends a conversation — marks the slot
     * reusable. `echo close > <id>/ctl`. */
    print("static void o9app_close_session(O9Session *s){\n");
    print("\tif(s == nil) return;\n");
    print("\tqlock(&o9app_pool_lock);\n");
    print("\ts->inuse = 0;\n");
    print("\tqlock(&s->lock); snprint(s->status, sizeof s->status, \"closed\\n\"); s->data[0] = '\\0'; qunlock(&s->lock);\n");
    print("\tqunlock(&o9app_pool_lock);\n");
    print("}\n");
    /* destroyfid: DIAGNOSTICS ONLY (ref count). Clunking a fid does NOT
     * end the conversation — the client owns it until an explicit close.
     * This is what makes echo>ctl; cat data safe (ctl clunks first). */
    print("static void o9app_destroyfid(Fid *f){\n");
    print("\tif(f != nil && f->file != nil && f->file->aux != nil &&\n");
    print("\t   *(int*)f->file->aux == O9AUX_SESSION && f->omode != -1){\n");
    print("\t\tO9Session *s = f->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_sub_and_fetch(&s->ref, 1);\n#else\n\t\tadec(&s->ref);\n#endif\n");
    print("\t}\n");
    print("}\n");
    /* open: ref++ (diagnostics; balanced by destroyfid). */
    print("static void o9app_open(Req *r){\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    print("\t   *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    print("\t\tO9Session *s = r->fid->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_fetch_and_add(&s->ref, 1);\n#else\n\t\tainc(&s->ref);\n#endif\n");
    print("\t}\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    print("static void o9app_root_read(Req *r){\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\tchar buf[8192]; char *p = buf; int i;\n");
    /* clone: reading allocates a session and returns its id. */
    print("\tif(strcmp(name, \"clone\") == 0){\n");
    print("\t\tO9Session *__s = o9app_alloc_session();\n");
    print("\t\tchar __idb[16];\n");
    print("\t\tif(__s == nil){ respond(r, \"no session\"); return; }\n");
    print("\t\tsnprint(__idb, sizeof __idb, \"%%d\\n\", __s->id);\n");
    print("\t\treadstr(r, __idb); respond(r, nil); return;\n\t}\n");
    /* Session-local data/status: the file's aux is the O9Session; serve
     * that session's private result/status (the per-caller fix). Named
     * data/status distinguishes them from exports (arbitrary names). */
    print("\tif(r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    print("\t\tO9Session *__s = r->fid->file->aux;\n");
    print("\t\tchar __sb[4096];\n");
    print("\t\tqlock(&__s->lock); snprint(__sb, sizeof __sb, \"%%s\", strcmp(name, \"data\") == 0 ? __s->data : __s->status); qunlock(&__s->lock);\n");
    print("\t\treadstr(r, __sb); respond(r, nil); return;\n\t}\n");
    /* Export file: its aux holds an O9Export with the serialized bytes.
     * Serve them ramfs-style (offset/count). */
    print("\tif(r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_EXPORT){\n");
    print("\t\tO9Export *__ex = r->fid->file->aux;\n");
    print("\t\tvlong __off = r->ifcall.offset; long __cnt = r->ifcall.count;\n");
    print("\t\tqlock(&__ex->lock);\n");
    print("\t\tif(__off >= __ex->ndata){ qunlock(&__ex->lock); r->ofcall.count = 0; respond(r, nil); return; }\n");
    print("\t\tif(__off + __cnt > __ex->ndata) __cnt = __ex->ndata - __off;\n");
    print("\t\tmemmove(r->ofcall.data, __ex->data + __off, __cnt);\n");
    print("\t\tqunlock(&__ex->lock);\n");
    print("\t\tr->ofcall.count = __cnt; respond(r, nil); return;\n\t}\n");
    /* Root data: only the root-ctl (fire-and-forget/debug) reply. */
    print("\tif(strcmp(name, \"data\") == 0){ readstr(r, o9app_lastdata); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ctl\") == 0){ readstr(r, \"\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"status\") == 0){\n");
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"app %%s\\nstate running\\nclasses\", o9app_name);\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++) p += snprint(p, sizeof buf-(p-buf), \" %%s\", o9app_classes[i].name);\n");
    /* #8: list instances per class (docs say classes AND instances). */
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"instances %%s\", o9app_classes[i].name);\n");
    print("\t\t\tif(o9app_classes[i].listinst != nil) p += o9app_classes[i].listinst(p, (int)(sizeof buf-(p-buf)));\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"methods\") == 0){\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tchar mb[4096]; o9_method_serialize(o9app_classes[i].name, mb, sizeof mb);\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"%%s\", mb);\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    /* state: DEBUG-only inspector.  Off by default (encapsulation);
     * O9DEBUG dumps read-only metadata snapshots plus live state tabs. */
    print("\tif(strcmp(name, \"state\") == 0){\n");
    print("\t\tif(!o9app_debug){ readstr(r, \"debug disabled (set O9DEBUG)\\n\"); respond(r, nil); return; }\n");
    print("\t\t{ char *__dbuf = mallocz(32768, 1); char *__dp;\n");
    print("\t\tif(__dbuf == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t\t__dp = __dbuf;\n");
    print("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# methods\\n\");\n");
    print("\t\t__dp += o9_method_store_serialize(__dp, (int)(32768-(__dp-__dbuf)));\n");
    print("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"\\n\");\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tif(o9app_classes[i].dumpstate == nil) continue;\n");
    print("\t\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# %%s\\n\", o9app_classes[i].name);\n");
    print("\t\t\t__dp += o9app_classes[i].dumpstate(__dp, (int)(32768-(__dp-__dbuf)));\n");
    print("\t\t}\n");
    print("\t\treadstr(r, __dbuf); free(__dbuf); respond(r, nil); return; }\n\t}\n");
    print("\trespond(r, \"not found\");\n}\n");
    print("static void o9app_root_write(Req *r){\n");
    print("#ifdef __GNUC__\n\tchar *name = r->fid->file->dir.name;\n#else\n\tchar *name = r->fid->file->name;\n#endif\n");
    print("\tchar cmd[1024], *f[16]; int nf; char inst[64]; O9ClassH *ch;\n");
    print("\tif(strcmp(name, \"ctl\") != 0){ respond(r, \"read only\"); return; }\n");
    /* No global cur_session: the session is derived from r inside the
     * put_result/put_status helpers (o9app_req_session(r)), so concurrent
     * requests each route to their OWN session. */
    print("\tsnprint(cmd, sizeof cmd, \"%%.*s\", (int)r->ifcall.count, (char*)r->ifcall.data);\n");
    print("\tnf = tokenize(cmd, f, nelem(f));\n");
    /* `close`: end THIS conversation (a session ctl only) — mark the slot
     * reusable. The explicit release that ends a session's lifetime. */
    print("\tif(nf >= 1 && strcmp(f[0], \"close\") == 0){\n");
    print("\t\tO9Session *__cs = o9app_req_session(r);\n");
    print("\t\tif(__cs != nil) o9app_close_session(__cs);\n");
    print("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    print("\tif(nf < 3 || (strcmp(f[0], \"method\") != 0 && strcmp(f[0], \"new\") != 0)){ respond(r, \"want: method Class.inst name | new Class inst | close\"); return; }\n");
    /* Resolve to a class handler. new Class inst -> resolve by CLASS name
     * (f[1] is the class). method Class.inst -> resolve by Class.inst.
     * The class fswrite re-tokenizes r->ifcall.data itself and handles
     * both new and method, so we only need to pick the right handler. */
    print("\tif(strcmp(f[0], \"new\") == 0){\n");
    print("\t\tint __ci; ch = nil;\n");
    print("\t\tfor(__ci = 0; __ci < o9app_nclasses; __ci++)\n");
    print("\t\t\tif(strcmp(o9app_classes[__ci].name, f[1]) == 0){ ch = &o9app_classes[__ci]; break; }\n");
    print("\t\tif(ch == nil){ respond(r, \"unknown class\"); return; }\n");
    print("\t} else {\n");
    print("\t\tch = o9app_resolve(f[1], inst, sizeof inst);\n");
    print("\t\tif(ch == nil){ respond(r, \"unknown object\"); return; }\n");
    print("\t}\n");
    print("\tch->write(r, nil);\t/* class fswrite re-parses r->ifcall.data */\n");
    print("}\n\n");

    /* o9_export_tab: publish a Tabula into the served-tree exports/ dir at
     * runtime.  A single createfile into the stable exports parent (the
     * safe pattern); the serialized bytes go in the child File's aux.  If
     * a file of that name exists, its bytes are replaced (re-export). */
    print("void o9_export_tab(O9String *name, O9Tabula *t){\n");
    print("\tFile *f; O9Export *ex; O9String *bytes; char *cname, *cbytes, *old;\n");
    print("\tif(o9app_exports_dir == nil || name == nil || t == nil) return;\n");
    print("\tcname = o9_string_cstr(name);\n");
    print("\tif(cname == nil) return;\n");
    print("\tif(!o9app_export_name_ok(cname)){ free(cname); return; }\n");
    print("\tbytes = o9_tab_serialize(t);\n");
    print("\tcbytes = o9_string_cstr(bytes);\n");
    print("\tif(cbytes == nil){ free(cname); o9_string_release(bytes); return; }\n");
    print("\tf = createfile(o9app_exports_dir, cname, \"o9\", 0444, nil);\n");
    print("\tif(f == nil){\t/* exists: replace its bytes */\n");
    print("\t\tf = walkfile(o9app_exports_dir, cname);\n");
    print("\t\tif(f == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    print("\t}\n");
    print("\tex = f->aux;\n");
    print("\tif(ex != nil && ex->tag != O9AUX_EXPORT){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    print("\tif(ex == nil){ ex = mallocz(sizeof *ex, 1); if(ex == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; } ex->tag = O9AUX_EXPORT; f->aux = ex; }\n");
    print("\tqlock(&ex->lock);\n");
    print("\told = ex->data;\n");
    print("\tex->data = cbytes; ex->ndata = bytes != nil ? o9_string_len(bytes) : 0;\n");
    print("\tf->length = ex->ndata;\n");
    print("\tqunlock(&ex->lock);\n");
    print("\tfree(old);\n");
    print("\tfree(cname); o9_string_release(bytes);\n");
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
    print("\to9app_srv.open = o9app_open;\n\to9app_srv.destroyfid = o9app_destroyfid;\t/* session reap */\n");
    /* The four control files + state are a FIXED shape, built once, never
     * mutated (their content is live, their structure is frozen). */
    print("\tcreatefile(o9app_tree->root, \"ctl\", \"o9\", 0666, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"data\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"status\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"methods\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"state\", \"o9\", 0444, nil);\t/* debug inspector */\n");
    /* clone: reading it allocates a session <id>/ with session-local
     * ctl/data/status (SESSIONS.md) — the /net/tcp/clone pattern that
     * gives concurrent callers a private, path-addressable conversation. */
    print("\tcreatefile(o9app_tree->root, \"clone\", \"o9\", 0444, nil);\n");
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
    print("\tvlong __o9fr[%d][12];\n", O9_MSG_FRAMES);
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
        } else if(strcmp(t->name, "Task") == 0){	/* Task<T>: spawn join handle */
            if(type_list_len(t->args) != 1){
                fprint(2, "o9c: error: line %d: Task needs 1 type argument\n", sem_line);
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
        s = type_render(t);
        fprint(2, "o9c: error: line %d: pointer type '%s' is not allowed in o9 declarations "
            "(keep raw pointers inside function c blocks and pass ordinary values through object methods/properties)\n",
            sem_line, s);
        (*errs)++;
        return -1;
    case TyArray:
        return validate_type(t->base, errs);
    }
    return 0;
}

static int
type_contains_address_scalar(Type *t)
{
    TypeList *a;

    if(t == nil)
        return 0;
    switch(t->kind){
    case TyName:
        return t->name != nil &&
            (strcmp(t->name, "intptr") == 0 || strcmp(t->name, "uintptr") == 0);
    case TyApply:
        for(a = t->args; a != nil; a = a->next)
            if(type_contains_address_scalar(a->type))
                return 1;
        return 0;
    case TyArray:
        return type_contains_address_scalar(t->base);
    case TyPtr:
    case TyParam:
        return 0;
    }
    return 0;
}

static int
type_is_object_boundary_scope(Node *scope_class)
{
    return scope_class != nil &&
        (scope_class->type == NClass || scope_class->type == NStruct ||
         scope_class->type == NInterface) &&
        (scope_class->flags & NFFunction) == 0;
}

static void
reject_address_boundary_type(Type *t, int *errs, char *kind, char *name)
{
    char *s;

    if(!type_contains_address_scalar(t))
        return;
    s = type_render(t);
    fprint(2, "o9c: error: line %d: %s '%s' cannot use address-carrying type '%s' "
        "on an object boundary (keep raw addresses inside function c blocks and pass ordinary values)\n",
        sem_line, kind, name != nil ? name : "?", s);
    (*errs)++;
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

static int
node_contains_type(Node *n, int type)
{
    for(; n != nil; n = n->next){
        if(n->type == type)
            return 1;
        if(node_contains_type(n->left, type) || node_contains_type(n->right, type))
            return 1;
    }
    return 0;
}

static void
reject_rawc_object_locals(Node *n, int *errs)
{
    int saved;

    for(; n != nil; n = n->next){
        saved = sem_line;
        if(n->line > 0)
            sem_line = n->line;
        if(n->type == NLocalVar && type_is_object_ref(n->typeinfo)){
            fprint(2, "o9c: error: line %d: raw C functions cannot declare object handle '%s' "
                "(pass ordinary values into c blocks; object mutation must go through o9 methods/properties)\n",
                sem_line, n->name != nil ? n->name : "?");
            (*errs)++;
        }
        reject_rawc_object_locals(n->left, errs);
        reject_rawc_object_locals(n->right, errs);
        sem_line = saved;
    }
}

static void
reject_rawc_object_handles(Node *method, int *errs)
{
    Node *p;
    int saved;

    if(method == nil || !node_contains_type(method->left, NRawC))
        return;
    for(p = method->right; p != nil; p = p->next){
        saved = sem_line;
        if(p->line > 0)
            sem_line = p->line;
        if(type_is_object_ref(p->typeinfo)){
            fprint(2, "o9c: error: line %d: raw C functions cannot take object handle '%s' "
                "(pass ordinary values into c blocks; object mutation must go through o9 methods/properties)\n",
                sem_line, p->name != nil ? p->name : "?");
            (*errs)++;
        }
        sem_line = saved;
    }
    reject_rawc_object_locals(method->left, errs);
}

static int
rawc_forbidden_ident(char *id, char **why)
{
    if(id == nil)
        return 0;
    if(strstr(id, "_Internal") != nil ||
       strstr(id, "_Client") != nil ||
       strstr(id, "_find_instance") != nil ||
       strstr(id, "_record_instance") != nil ||
       strstr(id, "_create_instance") != nil ||
       strstr(id, "_forget_instance") != nil ||
       strstr(id, "_instances") != nil ||
       strstr(id, "_ninstances") != nil){
        *why = id;
        return 1;
    }
    if(strncmp(id, "o9_impl_", 8) == 0 ||
       strncmp(id, "o9_self_", 8) == 0 ||
       strncmp(id, "o9_ctrl_", 8) == 0 ||
       strncmp(id, "o9_registry_", 12) == 0 ||
       strncmp(id, "o9_objects_", 11) == 0 ||
       strncmp(id, "o9app_", 6) == 0 ||
       strncmp(id, "obj9_", 5) == 0){
        *why = id;
        return 1;
    }
    if(strcmp(id, "O9Msg") == 0 ||
       strcmp(id, "O9Reply") == 0 ||
       strcmp(id, "O9ObjectStore") == 0 ||
       strcmp(id, "O9State") == 0 ||
       strcmp(id, "ArcLedger") == 0 ||
       strcmp(id, "dispatch_chan") == 0 ||
       strcmp(id, "shm_base") == 0 ||
       strcmp(id, "objdir") == 0){
        *why = id;
        return 1;
    }
    return 0;
}

static void
validate_rawc_boundary(char *src, int *errs)
{
    int i, mode, esc, j;
    char id[256], *why;

    if(src == nil)
        return;
    mode = 0;	/* 0 normal, 1 string, 2 char, 3 line comment, 4 block comment */
    esc = 0;
    for(i = 0; src[i] != '\0'; i++){
        if(mode == 0){
            if(src[i] == '"'){
                mode = 1;
                esc = 0;
                continue;
            }
            if(src[i] == '\''){
                mode = 2;
                esc = 0;
                continue;
            }
            if(src[i] == '/' && src[i+1] == '/'){
                mode = 3;
                i++;
                continue;
            }
            if(src[i] == '/' && src[i+1] == '*'){
                mode = 4;
                i++;
                continue;
            }
            if(isalpha((uchar)src[i]) || src[i] == '_'){
                j = 0;
                do {
                    if(j < sizeof id - 1)
                        id[j++] = src[i];
                    i++;
                } while(isalnum((uchar)src[i]) || src[i] == '_');
                id[j] = '\0';
                i--;
                why = nil;
                if(rawc_forbidden_ident(id, &why)){
                    fprint(2, "o9c: error: line %d: raw C block uses forbidden o9 internal symbol '%s' "
                        "(raw C may use Plan 9 C and local values, not generated object internals)\n",
                        sem_line, why);
                    (*errs)++;
                }
                continue;
            }
            continue;
        }
        if(mode == 1 || mode == 2){
            if(esc){
                esc = 0;
                continue;
            }
            if(src[i] == '\\'){
                esc = 1;
                continue;
            }
            if((mode == 1 && src[i] == '"') || (mode == 2 && src[i] == '\''))
                mode = 0;
            continue;
        }
        if(mode == 3){
            if(src[i] == '\n')
                mode = 0;
            continue;
        }
        if(mode == 4){
            if(src[i] == '*' && src[i+1] == '/'){
                mode = 0;
                i++;
            }
            continue;
        }
    }
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
           m->type == NStream ||
           m->type == NSecret || m->type == NCap)){
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
           m->type == NStream ||
           m->type == NSecret || m->type == NCap))
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
           m->type == NStream ||
           m->type == NSecret || m->type == NCap))
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
    if(t->kind == TyArray)
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
        /* Numeric width conversion: any integer/char scalar is assignable
         * to any other (C's implicit integer conversions — an int64
         * literal into an int8, etc.). Keep bool strict: an int is not a
         * bool. Makes the width types (int8..uint64, char, uchar, ...)
         * actually usable — a literal is int64, and every width would
         * otherwise reject it. */
        if(!type_is_bool(target) && !type_is_bool(actual))
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

static void
check_index_key(Node *e, int *errs)
{
    Type *lt, *kt;

    if(e == nil || e->type != NArrayGet || e->left == nil || e->right == nil)
        return;
    lt = e->left->typeinfo;
    if(type_is_collection(lt, "Dict")){
        kt = type_list_at(lt->args, 0);
        if(!type_assignable_semantic(kt, e->right->typeinfo))
            type_mismatch_error("index", kt, e->right->typeinfo, errs);
    }
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
    if(type_is_array(left))
        return type_array_elem(left);
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
    case NSpawn:
        /* spawn f(...) : Task<T> where T is f.run's return type. */
        {
            Node *a, *fc, *rm;
            Type *rt = type_name("int64");	/* default */
            char *fq = qualify_source_name(current_module, e->name);
            char *fcn = mangle_source_name(fq);
            for(a = e->right; a; a = a->next)
                annotate_expr_type(a, scope_class);
            fc = find_class(fcn);
            if(fc != nil)
                for(rm = fc->left; rm != nil; rm = rm->next)
                    if(rm->type == NMethod && rm->name != nil && strcmp(rm->name, "run") == 0){
                        if(rm->typeinfo != nil) rt = rm->typeinfo;
                        break;
                    }
            return set_expr_type(e, type_apply("Task", type_list(rt)));
        }
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
        /* Task<T>.await() : T */
        if(lt != nil && lt->kind == TyApply && lt->name != nil &&
           strcmp(lt->name, "Task") == 0 && strcmp(e->name, "await") == 0)
            return set_expr_type(e, type_list_at(lt->args, 0));
        if(lt != nil && lt->kind == TyName && lt->name != nil &&
           strcmp(lt->name, "Tabula") == 0){
            if(strcmp(e->name, "schema") == 0 ||
               strcmp(e->name, "get") == 0 ||
               strcmp(e->name, "read") == 0 ||
               strcmp(e->name, "serialize") == 0)
                return set_expr_type(e, type_name("string"));
            if(strcmp(e->name, "query") == 0)
                return set_expr_type(e, type_name("Tabula"));
            if(strcmp(e->name, "close") == 0)
                return set_expr_type(e, type_name("void"));
            /* has/add/write/set/first/next/flush return int64 (status / row-present) */
            return set_expr_type(e, type_name("int64"));
        }
        if(lt != nil && lt->kind == TyName && lt->name != nil &&
           strcmp(lt->name, "MountTable") == 0){
            if(strcmp(e->name, "schema") == 0 ||
               strcmp(e->name, "get") == 0 ||
               strcmp(e->name, "read") == 0 ||
               strcmp(e->name, "serialize") == 0)
                return set_expr_type(e, type_name("string"));
            if(strcmp(e->name, "query") == 0)
                return set_expr_type(e, type_name("Tabula"));
            if(strcmp(e->name, "close") == 0)
                return set_expr_type(e, type_name("void"));
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

static int
member_has_generated_storage(Node *m)
{
    return m != nil && (m->type == NProp || m->type == NState ||
        m->type == NStream ||
        m->type == NSecret || m->type == NCap);
}

static int
generated_internal_field_name(char *name)
{
    static char *names[] = {
        "ledger", "ref", "distance", "state", "data", "error",
        "oid", "objdir", "dispatch_chan", nil
    };
    int i;

    if(name == nil)
        return 0;
    for(i = 0; names[i] != nil; i++)
        if(strcmp(name, names[i]) == 0)
            return 1;
    return 0;
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
        if(member_has_generated_storage(a) && generated_internal_field_name(a->name)){
            if(a->line > 0)
                sem_line = a->line;
            fprint(2, "o9c: error: line %d: field name '%s' is reserved by generated runtime storage in '%s'\n",
                sem_line, a->name, cnode->name);
            (*errs)++;
        }
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

static void typecheck_expr(Node *e, Node *scope_class, int *errs);

static int
is_tabula_new(Node *e)
{
    return e != nil && e->type == NClass &&
        e->typeinfo != nil && e->typeinfo->kind == TyName &&
        e->typeinfo->name != nil && strcmp(e->typeinfo->name, "Tabula") == 0;
}

static int
is_mount_table_new(Node *e)
{
    return e != nil && e->type == NClass &&
        e->typeinfo != nil && e->typeinfo->kind == TyName &&
        e->typeinfo->name != nil && strcmp(e->typeinfo->name, "MountTable") == 0;
}

static void
typecheck_tabula_new(Node *e, Node *scope_class, int *errs)
{
    Node *a;
    int got;

    if(!is_tabula_new(e))
        return;
    got = node_list_len(e->right);
    if(e->typename != nil && strcmp(e->typename, "same") != 0){
        fprint(2, "o9c: error: line %d: Tabula does not support near/far construction\n",
            sem_line);
        (*errs)++;
    }
    if(got != 1 && got != 2){
        fprint(2, "o9c: error: line %d: Tabula constructor takes 1 path argument or 2 schema arguments, got %d\n",
            sem_line, got);
        (*errs)++;
    }
    for(a = e->right; a != nil; a = a->next){
        typecheck_expr(a, scope_class, errs);
        if(!type_assignable_semantic(type_name("string"), a->typeinfo)){
            fprint(2, "o9c: error: line %d: Tabula constructor arguments must be string\n",
                sem_line);
            (*errs)++;
        }
    }
}

static void
typecheck_mount_table_new(Node *e, Node *scope_class, int *errs)
{
    int got;

    if(!is_mount_table_new(e))
        return;
    got = node_list_len(e->right);
    if(e->typename != nil && strcmp(e->typename, "same") != 0){
        fprint(2, "o9c: error: line %d: MountTable does not support near/far construction\n",
            sem_line);
        (*errs)++;
    }
    if(got != 0 && got != 1){
        fprint(2, "o9c: error: line %d: MountTable constructor takes 0 arguments for a new table or 1 path argument, got %d\n",
            sem_line, got);
        (*errs)++;
        return;
    }
    if(got == 1){
        typecheck_expr(e->right, scope_class, errs);
        if(!type_assignable_semantic(type_name("string"), e->right->typeinfo)){
            fprint(2, "o9c: error: line %d: MountTable constructor path must be string\n",
                sem_line);
            (*errs)++;
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
    case NIdent:
        /* Bare identifier: if it resolves to a private MEMBER owned by an
         * ANCESTOR (not scope_class itself), reject — private is
         * declaring-class-only (strict C#). A subclass cannot read its
         * parent's private via a bare field access (inheritance flattens
         * the struct, so the field is physically reachable — the check
         * must be here). Locals/params and same-class privates are fine. */
        if(e->name != nil && get_typeinfo_sym(e->name) == nil){
            Type *st;
            TypedMember tm;
            if(scope_class == nil){
                fprint(2, "o9c: error: line %d: unknown identifier '%s'\n",
                    sem_line, e->name);
                (*errs)++;
            } else {
                st = scope_class->typeinfo;
                if(st == nil)
                    st = type_from_name(scope_class->qname != nil ? scope_class->qname : scope_class->name);
                if(!typed_member_lookup(st, e->name, 0, &tm)){
                    if(scope_class->flags & NFFunction)
                        fprint(2, "o9c: error: line %d: function '%s' cannot resolve '%s' "
                            "(function bodies do not capture outer variables; pass it as a parameter)\n",
                            sem_line,
                            scope_class->qname != nil ? scope_class->qname : scope_class->name,
                            e->name);
                    else
                        fprint(2, "o9c: error: line %d: '%s' has no member '%s'\n",
                            sem_line,
                            scope_class->qname != nil ? scope_class->qname : scope_class->name,
                            e->name);
                    (*errs)++;
                } else if(tm.node != nil && (tm.node->flags & NFPrivate) && tm.owner != scope_class){
                    fprint(2, "o9c: error: line %d: '%s.%s' is private "
                        "(a subclass cannot access an inherited private member)\n",
                        sem_line, tm.owner != nil ? tm.owner->name : "?", e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NTry:
    case NDefer:
        /* try/defer wrap a call expression — typecheck the inner call */
        typecheck_expr(e->left, scope_class, errs);
        break;
    case NProp:
    case NState:
        validate_type(e->typeinfo, errs);
        if(type_is_object_boundary_scope(scope_class))
            reject_address_boundary_type(e->typeinfo, errs,
                e->type == NState ? "state field" : "field or parameter",
                e->name);
        break;
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
        if(type_is_object_boundary_scope(scope_class))
            reject_address_boundary_type(e->typeinfo, errs, "method return", e->name);
        break;
    case NClass:
        validate_type(e->typeinfo, errs);
        if(is_tabula_new(e)){
            typecheck_tabula_new(e, scope_class, errs);
            break;
        }
        if(is_mount_table_new(e)){
            typecheck_mount_table_new(e, scope_class, errs);
            break;
        }
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
    /* NLink removed: `link` (object-as-fileserver namespace composition)
     * is retired — the keyword is gone from the grammar, so NLink can no
     * longer be produced. See NAMESPACE.md (namespace control reframed as
     * organizing produced output, not object composition). */
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
                if(scope_class->flags & NFFunction)
                    fprint(2, "o9c: error: line %d: function '%s' cannot resolve call '%s' "
                        "(function bodies do not capture outer methods; pass an object handle or value)\n",
                        sem_line,
                        scope_class->qname != nil ? scope_class->qname : scope_class->name,
                        e->name);
                else
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
            /* Task<T>: only await() (no args). */
            if(lt != nil && lt->kind == TyApply && lt->name != nil &&
               strcmp(lt->name, "Task") == 0){
                if(strcmp(e->name, "await") != 0){
                    fprint(2, "o9c: error: line %d: Task has no method '%s' (only await)\n",
                        sem_line, e->name);
                    (*errs)++;
                } else if(node_list_len(e->right) != 0){
                    fprint(2, "o9c: error: line %d: Task.await takes no arguments\n", sem_line);
                    (*errs)++;
                }
                break;
            }
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "Tabula") == 0){
                Node *a;
                int want = -1, got = node_list_len(e->right);
                if(strcmp(e->name, "schema") == 0) want = 0;
                else if(strcmp(e->name, "has") == 0) want = 1;
                else if(strcmp(e->name, "add") == 0) want = 1;
                else if(strcmp(e->name, "write") == 0) want = 3;
                else if(strcmp(e->name, "set") == 0) want = 2;
                else if(strcmp(e->name, "get") == 0) want = 1;
                else if(strcmp(e->name, "first") == 0) want = 0;
                else if(strcmp(e->name, "next") == 0) want = 0;
                else if(strcmp(e->name, "read") == 0) want = 0;
                else if(strcmp(e->name, "serialize") == 0) want = 0;
                else if(strcmp(e->name, "query") == 0) want = 2;
                else if(strcmp(e->name, "flush") == 0) want = 0;
                else if(strcmp(e->name, "close") == 0) want = 0;
                if(want < 0){
                    fprint(2, "o9c: error: line %d: Tabula has no method '%s' "
                        "(schema/has/add/write/set/get/first/next/read/serialize/query/flush/close)\n", sem_line, e->name);
                    (*errs)++;
                } else if(got != want){
                    fprint(2, "o9c: error: line %d: Tabula.%s takes %d argument%s, got %d\n",
                        sem_line, e->name, want, want == 1 ? "" : "s", got);
                    (*errs)++;
                }
                for(a = e->right; a != nil; a = a->next){
                    typecheck_expr(a, scope_class, errs);
                    if(want > 0 && got == want &&
                       !type_assignable_semantic(type_name("string"), a->typeinfo)){
                        fprint(2, "o9c: error: line %d: Tabula.%s arguments must be string\n",
                            sem_line, e->name);
                        (*errs)++;
                    }
                }
                break;
            }
            if(lt != nil && lt->kind == TyName && lt->name != nil &&
               strcmp(lt->name, "MountTable") == 0){
                Node *a;
                int want = -1, got = node_list_len(e->right);
                int stringargs = 0, intarg = -1;
                if(strcmp(e->name, "allowRoot") == 0) want = 1;
                else if(strcmp(e->name, "dir") == 0){ want = 2; stringargs = 1; intarg = 1; }
                else if(strcmp(e->name, "bind") == 0){ want = 3; stringargs = 2; intarg = 2; }
                else if(strcmp(e->name, "mountsrv") == 0){ want = 4; stringargs = 2; intarg = 2; }
                else if(strcmp(e->name, "schema") == 0) want = 0;
                else if(strcmp(e->name, "has") == 0) want = 1;
                else if(strcmp(e->name, "get") == 0) want = 1;
                else if(strcmp(e->name, "first") == 0) want = 0;
                else if(strcmp(e->name, "next") == 0) want = 0;
                else if(strcmp(e->name, "read") == 0) want = 0;
                else if(strcmp(e->name, "serialize") == 0) want = 0;
                else if(strcmp(e->name, "query") == 0) want = 2;
                else if(strcmp(e->name, "flush") == 0) want = 0;
                else if(strcmp(e->name, "validate") == 0) want = 0;
                else if(strcmp(e->name, "apply") == 0) want = 0;
                else if(strcmp(e->name, "close") == 0) want = 0;
                if(want < 0){
                    fprint(2, "o9c: error: line %d: MountTable has no method '%s' "
                        "(dir/bind/mountsrv/allowRoot/read/query/flush/validate/apply/close)\n", sem_line, e->name);
                    (*errs)++;
                } else if(got != want){
                    fprint(2, "o9c: error: line %d: MountTable.%s takes %d argument%s, got %d\n",
                        sem_line, e->name, want, want == 1 ? "" : "s", got);
                    (*errs)++;
                }
                for(a = e->right; a != nil; a = a->next){
                    int pi = 0;
                    Node *b;
                    for(b = e->right; b != nil && b != a; b = b->next)
                        pi++;
                    typecheck_expr(a, scope_class, errs);
                    if(got != want)
                        continue;
                    if((strcmp(e->name, "allowRoot") == 0 ||
                        strcmp(e->name, "has") == 0 ||
                        strcmp(e->name, "get") == 0 ||
                        strcmp(e->name, "query") == 0 ||
                        pi < stringargs) &&
                       !type_assignable_semantic(type_name("string"), a->typeinfo)){
                        fprint(2, "o9c: error: line %d: MountTable.%s argument %d must be string\n",
                            sem_line, e->name, pi + 1);
                        (*errs)++;
                    }
                    if(pi == intarg && !type_assignable_semantic(type_name("int64"), a->typeinfo)){
                        fprint(2, "o9c: error: line %d: MountTable.%s argument %d must be int64\n",
                            sem_line, e->name, pi + 1);
                        (*errs)++;
                    }
                    if(strcmp(e->name, "mountsrv") == 0 && pi == 3 &&
                       !type_assignable_semantic(type_name("string"), a->typeinfo)){
                        fprint(2, "o9c: error: line %d: MountTable.mountsrv argument 4 must be string\n",
                            sem_line);
                        (*errs)++;
                    }
                }
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
    case NArrayGet:
        annotate_expr_type(e, scope_class);
        check_index_key(e, errs);
        break;
    case NAssign:
        annotate_expr_type(e, scope_class);
        check_index_key(e->left, errs);
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
    case NRawC:
        if(scope_class == nil || (scope_class->flags & NFFunction) == 0){
            fprint(2, "o9c: error: line %d: raw C blocks are only allowed inside function bodies\n", sem_line);
            (*errs)++;
        } else
            validate_rawc_boundary(e->name, errs);
        break;
    case NUse:
        if(scope_class == nil || (scope_class->flags & NFFunction) == 0){
            fprint(2, "o9c: error: line %d: C dependency use blocks are only allowed inside function bodies\n", sem_line);
            (*errs)++;
        } else {
            Node *d;
            for(d = e->left; d != nil; d = d->next)
                use_cdep(d->name, sem_line, errs);
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
            if(is_tabula_new(e->left))
                typecheck_tabula_new(e->left, scope_class, errs);
            if(is_mount_table_new(e->left))
                typecheck_mount_table_new(e->left, scope_class, errs);
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
            if(scope_class != nil && (scope_class->flags & NFFunction))
                reject_rawc_object_handles(c, errs);
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
        if(c->type == NUse){
            typecheck_expr(c, scope_class, errs);
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
    int nmain;

    nmain = count_root_main_blocks(root);
    if(nmain > 1){
        fprint(2, "o9c: error: program has %d main blocks; only one main block is allowed\n", nmain);
        errors++;
    }
    
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
    case NSpawn: return "NSpawn";
    case NRawC: return "NRawC";
    case NUse: return "NUse";
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

typedef struct CDepSpec CDepSpec;
struct CDepSpec {
    char *name;
    char *header;
    char *archive;
    char *requires;
};

static CDepSpec builtin_cdep_specs[] = {
    { "9p",       "<9p.h>",       "/$objtype/lib/lib9p.a", nil },
    { "String",   "<String.h>",   "/$objtype/lib/libString.a", nil },
    { "aml",      "<aml.h>",      "/$objtype/lib/libaml.a", nil },
    { "auth",     "<auth.h>",     "/$objtype/lib/libauth.a", nil },
    { "authsrv",  "<authsrv.h>",  "/$objtype/lib/libauthsrv.a", "auth sec" },
    { "avl",      "<avl.h>",      "/$objtype/lib/libavl.a", nil },
    { "bin",      "<bin.h>",      "/$objtype/lib/libbin.a", nil },
    { "bio",      "<bio.h>",      "/$objtype/lib/libbio.a", nil },
    { "complete", "<complete.h>", "/$objtype/lib/libcomplete.a", nil },
    { "control",  "<control.h>",  "/$objtype/lib/libcontrol.a", nil },
    { "disk",     "<disk.h>",     "/$objtype/lib/libdisk.a", nil },
    { "draw",     "<draw.h>",     "/$objtype/lib/libdraw.a", nil },
    { "dtracy",   "<dtracy.h>",   "/$objtype/lib/libdtracy.a", nil },
    { "fis",      "<fis.h>",      "/$objtype/lib/libfis.a", nil },
    { "flate",    "<flate.h>",    "/$objtype/lib/libflate.a", nil },
    { "frame",    "<frame.h>",    "/$objtype/lib/libframe.a", "draw" },
    { "geometry", "<geometry.h>", "/$objtype/lib/libgeometry.a", nil },
    { "html",     "<html.h>",     "/$objtype/lib/libhtml.a", nil },
    { "httpd",    "<httpd.h>",    "/$objtype/lib/libhttpd.a", nil },
    { "ip",       "<ip.h>",       "/$objtype/lib/libip.a", nil },
    { "json",     "<json.h>",     "/$objtype/lib/libjson.a", nil },
    { "mach",     "<mach.h>",     "/$objtype/lib/libmach.a", nil },
    { "memdraw",  "<memdraw.h>",  "/$objtype/lib/libmemdraw.a", "draw" },
    { "memlayer", "<memlayer.h>", "/$objtype/lib/libmemlayer.a", "memdraw draw" },
    { "mp",       "<mp.h>",       "/$objtype/lib/libmp.a", nil },
    { "ndb",      "<ndb.h>",      "/$objtype/lib/libndb.a", nil },
    { "pcm",      "<pcm.h>",      "/$objtype/lib/libpcm.a", nil },
    { "plumb",    "<plumb.h>",    "/$objtype/lib/libplumb.a", nil },
    { "regexp",   "<regexp.h>",   "/$objtype/lib/libregexp.a", nil },
    { "sat",      "<sat.h>",      "/$objtype/lib/libsat.a", nil },
    { "scribble", "<scribble.h>", "/$objtype/lib/libscribble.a", nil },
    { "sec",      "<libsec.h>",   "/$objtype/lib/libsec.a", "mp" },
    { "stdio",    "<stdio.h>",    "/$objtype/lib/libstdio.a", nil },
    { "sunrpc",   "<sunrpc.h>",   "/$objtype/lib/libsunrpc.a", nil },
    { "thread",   "<thread.h>",   "/$objtype/lib/libthread.a", nil },
    { "ttf",      "<ttf.h>",      "/$objtype/lib/libttf.a", nil },
    { "venti",    "<venti.h>",    "/$objtype/lib/libventi.a", nil },
    { nil, nil, nil, nil }
};

static char*
trim_ws(char *s)
{
    char *e;

    while(*s != '\0' && isspace((uchar)*s))
        s++;
    e = s + strlen(s);
    while(e > s && isspace((uchar)e[-1]))
        *--e = '\0';
    return s;
}

static char*
unquote_value(char *s)
{
    int n;

    s = trim_ws(s);
    n = strlen(s);
    if(n >= 2 && ((s[0] == '"' && s[n-1] == '"') || (s[0] == '\'' && s[n-1] == '\''))){
        s[n-1] = '\0';
        return s + 1;
    }
    return s;
}

static int
safe_dep_name(char *s)
{
    char *p;

    if(s == nil || s[0] == '\0' || !(isalpha((uchar)s[0]) || s[0] == '_'))
        return 0;
    for(p = s; *p != '\0'; p++)
        if(!(isalnum((uchar)*p) || *p == '_'))
            return 0;
    return 1;
}

static int
safe_project_chars(char *s, int allowobj)
{
    char *p;

    for(p = s; *p != '\0'; p++){
        if(isalnum((uchar)*p) || *p == '_' || *p == '.' || *p == '/' || *p == '-')
            continue;
        if(*p == '$' && allowobj && strncmp(p, "$objtype", 8) == 0){
            p += 7;
            continue;
        }
        return 0;
    }
    return 1;
}

static char*
clean_project_dep_path(char *val, int allowobj, int line, char *field)
{
    char clean[1024];

    if(val == nil)
        return nil;
    val = unquote_value(val);
    if(val[0] == '<' || val[0] == '"' || val[0] == '/' ||
       !safe_project_chars(val, allowobj)){
        fprint(2, "o9c: error: line %d: deps.tab %s path '%s' is not project-relative\n",
            line, field, val);
        semantic_errors++;
        return nil;
    }
    strncpy(clean, val, sizeof clean - 1);
    clean[sizeof clean - 1] = '\0';
    if(path_within_subtree(clean) < 0){
        fprint(2, "o9c: error: line %d: deps.tab %s path '%s' escapes the project root\n",
            line, field, val);
        semantic_errors++;
        return nil;
    }
    return strdup(clean);
}

static CDep*
find_cdep(char *name)
{
    CDep *d;

    for(d = cdeps; d != nil; d = d->next)
        if(strcmp(d->name, name) == 0)
            return d;
    return nil;
}

static CDep*
new_cdep(char *name, int system)
{
    CDep *d;

    d = mallocz(sizeof *d, 1);
    if(d == nil)
        sysfatal("malloc: cdep");
    d->name = strdup(name);
    d->system = system;
    return d;
}

static void
add_builtin_cdep(char *name, char *header, char *archive, char *requires)
{
    CDep *d;

    d = new_cdep(name, 1);
    d->header = header != nil ? strdup(header) : nil;
    d->archive = archive != nil ? strdup(archive) : nil;
    d->requires = requires != nil ? strdup(requires) : nil;
    d->next = cdeps;
    cdeps = d;
}

static void
load_builtin_cdeps(void)
{
    int i;

    if(cdeps != nil)
        return;
    for(i = 0; builtin_cdep_specs[i].name != nil; i++)
        add_builtin_cdep(builtin_cdep_specs[i].name,
            builtin_cdep_specs[i].header,
            builtin_cdep_specs[i].archive,
            builtin_cdep_specs[i].requires);
}

static void
cdep_replace(CDep *old, CDep *n)
{
    old->header = n->header;
    old->include = n->include;
    old->archive = n->archive;
    old->source = n->source;
    old->requires = n->requires;
    old->system = 0;
}

static void
finish_project_cdep(CDep *d, int line)
{
    CDep *old;

    if(d == nil)
        return;
    if(!safe_dep_name(d->name)){
        fprint(2, "o9c: error: line %d: deps.tab dependency name '%s' is not a simple identifier\n",
            line, d->name != nil ? d->name : "");
        semantic_errors++;
        return;
    }
    if(d->header != nil)
        d->header = clean_project_dep_path(d->header, 0, line, "header");
    if(d->include != nil)
        d->include = clean_project_dep_path(d->include, 0, line, "include");
    if(d->source != nil)
        d->source = clean_project_dep_path(d->source, 0, line, "source");
    if(d->archive != nil)
        d->archive = clean_project_dep_path(d->archive, 1, line, "archive");
    if(semantic_errors > 0)
        return;

    old = find_cdep(d->name);
    if(old != nil){
        if(!d->override){
            fprint(2, "o9c: error: line %d: deps.tab dependency '%s' already exists; set override=true to replace it\n",
                line, d->name);
            semantic_errors++;
            return;
        }
        cdep_replace(old, d);
        return;
    }
    d->system = 0;
    d->next = cdeps;
    cdeps = d;
}

static void
load_project_cdeps(void)
{
    char path[1024], linebuf[1024], *buf, *p, *nl, *s, *eq, *key, *val;
    long len;
    int line, rowline;
    CDep *cur;

    snprint(path, sizeof path, "%s/deps.tab", project_root);
    buf = read_whole_file(path, &len);
    if(buf == nil)
        return;

    cur = nil;
    rowline = 0;
    line = 0;
    for(p = buf; p != nil && *p != '\0'; p = (nl != nil ? nl + 1 : nil)){
        nl = strchr(p, '\n');
        if(nl != nil)
            *nl = '\0';
        line++;
        strncpy(linebuf, p, sizeof linebuf - 1);
        linebuf[sizeof linebuf - 1] = '\0';
        s = trim_ws(linebuf);
        if(s[0] == '\0' || s[0] == '#')
            continue;
        if(s[0] == '/' && s[1] == '/')
            continue;
        eq = strchr(s, '=');
        if(eq == nil){
            fprint(2, "o9c: error: line %d: deps.tab line needs key=value\n", line);
            semantic_errors++;
            continue;
        }
        *eq = '\0';
        key = trim_ws(s);
        val = unquote_value(eq + 1);
        if(strcmp(key, "name") == 0){
            finish_project_cdep(cur, rowline);
            cur = new_cdep(val, 0);
            rowline = line;
            continue;
        }
        if(cur == nil){
            fprint(2, "o9c: error: line %d: deps.tab field '%s' appears before name\n",
                line, key);
            semantic_errors++;
            continue;
        }
        if(strcmp(key, "header") == 0)
            cur->header = strdup(val);
        else if(strcmp(key, "include") == 0)
            cur->include = strdup(val);
        else if(strcmp(key, "archive") == 0)
            cur->archive = strdup(val);
        else if(strcmp(key, "source") == 0)
            cur->source = strdup(val);
        else if(strcmp(key, "requires") == 0)
            cur->requires = strdup(val);
        else if(strcmp(key, "override") == 0)
            cur->override = (strcmp(val, "true") == 0 || strcmp(val, "1") == 0 || strcmp(val, "yes") == 0);
        else if(strcmp(key, "kind") == 0){
            if(strcmp(val, "project") != 0){
                fprint(2, "o9c: error: line %d: deps.tab kind must be project\n", line);
                semantic_errors++;
            }
        } else {
            fprint(2, "o9c: error: line %d: deps.tab unknown field '%s'\n", line, key);
            semantic_errors++;
        }
    }
    finish_project_cdep(cur, rowline);
    free(buf);
}

static void
mark_cdep_used(CDep *d)
{
    if(d->used)
        return;
    d->used = 1;
    if(used_cdeps_tail != nil)
        used_cdeps_tail->usednext = d;
    else
        used_cdeps = d;
    used_cdeps_tail = d;
}

static void
use_cdep_inner(char *name, int line, int *errs, int depth)
{
    CDep *d;
    char *reqs, *tok, *p;

    if(name == nil)
        return;
    if(depth > 32){
        fprint(2, "o9c: error: line %d: C dependency '%s' has a recursive requires chain\n",
            line, name);
        (*errs)++;
        return;
    }
    d = find_cdep(name);
    if(d == nil){
        fprint(2, "o9c: error: line %d: unknown C dependency '%s'\n", line, name);
        (*errs)++;
        return;
    }
    mark_cdep_used(d);
    if(d->requires == nil || d->requires[0] == '\0')
        return;
    reqs = strdup(d->requires);
    for(p = reqs; *p != '\0'; p++)
        if(*p == ',')
            *p = ' ';
    for(tok = strtok(reqs, " \t\r\n"); tok != nil; tok = strtok(nil, " \t\r\n"))
        use_cdep_inner(tok, line, errs, depth + 1);
    free(reqs);
}

static void
use_cdep(char *name, int line, int *errs)
{
    use_cdep_inner(name, line, errs, 0);
}

static char*
expand_objtype(char *s)
{
    char *obj, *p, out[1024];
    int n;

    if(s == nil)
        return nil;
    obj = getenv("objtype");
    if(obj == nil || obj[0] == '\0')
        obj = getenv("OBJTYPE");
    if(obj == nil || obj[0] == '\0')
        obj = "unknown";
    out[0] = '\0';
    n = 0;
    for(p = s; *p != '\0' && n < sizeof out - 1; p++){
        if(strncmp(p, "$objtype", 8) == 0){
            n += snprint(out + n, sizeof out - n, "%s", obj);
            p += 7;
        } else
            out[n++] = *p;
    }
    out[n] = '\0';
    return strdup(out);
}

static void
emit_cdeps(void)
{
    CDep *d;
    char *x;

    for(d = used_cdeps; d != nil; d = d->usednext){
        print("/* o9: dep %s %s */\n", d->system ? "system" : "project", d->name);
        if(d->include != nil)
            print("/* o9: include %s */\n", d->include);
        if(d->source != nil)
            print("/* o9: source %s */\n", d->source);
        if(d->archive != nil){
            x = expand_objtype(d->archive);
            print("/* o9: archive %s */\n", x);
            free(x);
        }
    }
    for(d = used_cdeps; d != nil; d = d->usednext){
        if(d->header == nil)
            continue;
        if(d->header[0] == '<' || d->header[0] == '"')
            print("#include %s\n", d->header);
        else
            print("#include \"%s\"\n", d->header);
    }
    if(used_cdeps != nil)
        print("\n");
}

static int
o9_ident_char(int c)
{
    return isalnum(c) || c == '_';
}

static char*
find_main_block_start(char *src)
{
    char *m, *p;

    if(src == nil)
        return nil;
    for(m = src; (m = strstr(m, "main")) != nil; m += 4){
        if((m > src && o9_ident_char((uchar)m[-1])) || o9_ident_char((uchar)m[4]))
            continue;
        p = m + 4;
        while(*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
            p++;
        if(*p == '{')
            return m;
    }
    return nil;
}

/* Strip imported program entries (only the root file owns the entry).
 * Supports the current `main { ... }` form.  Legacy `func main() { ... }`
 * is intentionally not stripped, so imported stale syntax still fails.
 * Balances braces from the entry block and edits in place. */
static void
strip_imported_main(char *src)
{
    char *m = find_main_block_start(src);
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

/* Pull imported files' declarations into input_buf. Returns non-zero when
 * at least one import line was consumed; callers rescan until the combined
 * source is import-free so stdlib modules can depend on each other. */
static int
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
        return 1;
    } else {
        free(combined);
        return 0;
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

    load_builtin_cdeps();
    load_project_cdeps();
    if(semantic_errors > 0)
        exits("deps");

    for(i = 0; i < 32 && resolve_imports(); i++)
        ;
    if(i >= 32){
        fprint(2, "o9c: error: import nesting too deep or cyclic\n");
        semantic_errors++;
    }
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
