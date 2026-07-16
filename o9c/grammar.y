%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>
#include "o9_type.h"

/* ========================================================================
 * AST TYPES AND GLOBAL STATE
 * ======================================================================== */

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
    NDoubleLit,
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
    NCast,
    NRawC,
    NUse,
    NAlt,
    NAltCase,
    NAltDefault,
    NTupleLit,
    NNodeKinds
};

enum {
    NFAbstract = 1<<0,
    NFMethodDecl = 1<<1,
    NFSelfCalled = 1<<2,
    NFPrivate = 1<<3,	/* class-scoped; not reachable through the app facade */
    NFFunction = 1<<4,	/* a synthesized function-class (fixed spawn template) */
    NFMain = 1<<5,	/* reserved top-level program bootstrap block */
    NFChanSendOnly = 1<<6,	/* public endpoint may send, not receive */
    NFChanRecvOnly = 1<<7	/* public endpoint may receive, not send */
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
static Type *gen_return_type;        /* method return type while emitting body */
static char *parse_class_stack[32];
static int parse_class_depth;
static char *current_parse_class_source;
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
static Node* synth_function_class(char *fname, Node *rettn, Node *params, Node *body);
static void o9_note_registered(char *name);
static int member_exists(Node *cnode, char *name);
Node* append_node(Node *list, Node *node);
static Node* type_decl_node(Type *t);
static int validate_type(Type *t, int *errs);
char* type_storage_for_codegen(Type *t);
static Type* decl_typeinfo(Node *n);
static Node* typed_node_from_name(char *name);
static Node* member_node(Node *cnode, char *name, int method);
static int typed_member_lookup(Type *receiver, char *name, int method, TypedMember *out);
static int method_has_body(Node *m);
static Type* get_typeinfo_sym(char *name);
static void add_type_sym_typed(char *name, Type *typeinfo);
static char* type_slice(char *s, int n);
static char* qualify_type_name(char *name);
static char* qualify_source_name(char *module, char *name);
static char* mangle_source_name(char *name);
static int is_known_type_name(char *name);
static Type* type_from_name(char *name);
static Node* type_node(Type *type);
static Node* mk_typed(int type, char *name, Node *tn, Node *l, Node *r);
static void set_channel_dir(Node *n, Node *dir);
static void set_node_names(Node *n, char *qname, char *cname);
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
static void load_builtin_cdeps(void);
static void load_project_cdeps(void);
static void use_cdep(char *name, int line, int *errs);
static void emit_cdeps(void);

int is_subclass(char *sub, char *parent);

/* ========================================================================
 * SYMBOL TABLES AND NAME QUALIFICATION
 * ======================================================================== */

typedef struct TypeSym TypeSym;
struct TypeSym {
    char *name;
    Type *typeinfo;
    TypeSym *next;
};
TypeSym *type_syms;

static void add_type_sym_typed(char *name, Type *typeinfo) {
    TypeSym *s = malloc(sizeof(TypeSym));
    if(s == nil)
        sysfatal("malloc: add_type_sym_typed");
    s->name = strdup(name);
    s->typeinfo = typeinfo;
    s->next = type_syms;
    type_syms = s;
}

static Type* get_typeinfo_sym(char *name) {
    TypeSym *s;
    for(s = type_syms; s; s = s->next) if(strcmp(s->name, name) == 0) return s->typeinfo;
    return nil;
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
    char *rendered, *cname;

    rendered = type_render(type);
    cname = type_cname(type);
    n = mk(NType, cname, rendered, nil, nil);
    n->typeinfo = type;
    set_node_names(n, rendered, cname);
    return n;
}

static Node*
typed_node_from_name(char *name)
{
    return type_node(type_name(name));
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

static int
o9_locality_kind(char *s)
{
    if(s == nil)
        return -1;
    if(strcmp(s, "near") == 0)
        return 0;
    if(strcmp(s, "far") == 0)
        return 1;
    if(strcmp(s, "listener") == 0)
        return 2;
    return -1;
}

static int
o9_locality_distance(char *s)
{
    int k;

    k = o9_locality_kind(s);
    if(k == 0)
        return 0;
    if(k == 1)
        return 1;
    return -1;
}

static int
o9_type_is_tabula(Type *t)
{
    return t != nil && t->kind == TyName && t->name != nil &&
        strcmp(t->name, "Tabula") == 0;
}

static void
set_channel_dir(Node *n, Node *dir)
{
    if(n == nil || dir == nil || dir->name == nil)
        return;
    if(strcmp(dir->name, "send") == 0){
        n->flags |= NFChanSendOnly;
        return;
    }
    if(strcmp(dir->name, "recv") == 0){
        n->flags |= NFChanRecvOnly;
        return;
    }
    fprint(2, "o9c: error: line %d: channel direction must be 'send' or 'recv', got '%s'\n",
        dir->line > 0 ? dir->line : cur_line, dir->name);
    semantic_errors++;
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
    Node *v;

    if(n == nil || n->name == nil)
        return n;
    e = resolve_enum_sym(n->name);
    if(e == nil)
        return n;
    v = mk(NEnumVal, e->cname, nil, nil, nil);
    v->typeinfo = type_name(e->enumtype);
    return v;
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

static void
push_parse_class(char *source)
{
    if(parse_class_depth >= nelem(parse_class_stack))
        sysfatal("class nesting too deep");
    parse_class_stack[parse_class_depth++] = current_parse_class_source;
    current_parse_class_source = source;
}

static void
pop_parse_class(void)
{
    if(parse_class_depth <= 0)
        return;
    current_parse_class_source = parse_class_stack[--parse_class_depth];
}

/* ========================================================================
 * TYPE HELPERS
 * ======================================================================== */

static char*
client_storage_name(Type *t, char *who)
{
    Node *d;
    char *c, *r;
    int n;

    d = type_decl_node(t);
    c = type_cname(t);
    if(d == nil)
        return c;
    if(d->type == NEnum)
        return "int";
    if(d->type != NClass && d->type != NInterface)
        return c;
    n = strlen(c) + 8;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: %s", who);
    snprint(r, n, "%s_Client", c);
    return r;
}

static char*
pointer_storage_name(Type *base)
{
    char *p, *r;
    int n;

    p = type_storage_for_codegen(base);
    n = strlen(p) + 2;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: pointer storage");
    snprint(r, n, "%s*", p);
    return r;
}

static char*
tuple_storage_name(Type *t)
{
    char *c, *r;
    int n;

    c = type_cname(t);
    n = strlen(c) + 2;
    r = malloc(n);
    if(r == nil)
        sysfatal("malloc: tuple storage");
    snprint(r, n, "%s*", c);
    return r;
}

static char*
named_storage_for_codegen(Type *t)
{
    char *p;

    if(strcmp(t->name, "chan") == 0)
        return "Channel*";
    p = type_builtin_plan9(t->name);
    if(p != nil)
        return p;
    return client_storage_name(t, "named storage");
}

static char*
apply_storage_for_codegen(Type *t)
{
    Type *base;

    if(strcmp(t->name, "List") == 0)
        return "O9Slice";
    if(strcmp(t->name, "Dict") == 0)
        return "O9Dict";
    if(strcmp(t->name, "Task") == 0)
        return "O9Task*";	/* handle; <T> only types await's return */
    if(strcmp(t->name, "Tuple") == 0)
        return tuple_storage_name(t);
    base = type_name(t->name);
    return client_storage_name(base, "generic storage");
}

char*
type_storage_for_codegen(Type *t)
{
    if(t == nil)
        return "void";
    switch(t->kind){
    case TyName:
        return named_storage_for_codegen(t);
    case TyParam:
        return "void*";
    case TyApply:
        return apply_storage_for_codegen(t);
    case TyArray:
        return "O9Slice";
    case TyPtr:
        return pointer_storage_name(t->base);
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
       strcmp(s, "double") == 0 ||
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
type_cast_target_is_bool(Type *t)
{
    return t != nil && t->kind == TyName && t->name != nil &&
        strcmp(t->name, "bool") == 0;
}

static int
type_is_collection(Type *t, char *name)
{
    return t != nil && t->kind == TyApply && t->name != nil &&
        strcmp(t->name, name) == 0;
}

static int
type_is_dict(Type *t)
{
    return type_is_collection(t, "Dict");
}

static int
type_is_list(Type *t)
{
    return type_is_collection(t, "List");
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
type_is_char_pointer(Type *t)
{
    return t != nil && t->kind == TyPtr && t->base != nil &&
        t->base->kind == TyName && strcmp(t->base->name, "char") == 0;
}

static int
type_is_double(Type *t)
{
    return t != nil && t->kind == TyName && strcmp(t->name, "double") == 0;
}

static char*
dict_kind_for_codegen(Type *t)
{
    char *a;

    if(type_is_string(t))
        return "O9DICT_STRING";
    if(type_is_char_pointer(t))
        return "O9DICT_CSTR";
    if(type_is_double(t))
        return "O9DICT_DOUBLE";
    if(t != nil && t->kind == TyName){
        a = type_builtin_abi(t->name);
        if(a != nil && strcmp(a, "scalar") == 0)
            return "O9DICT_INT";
    }
    return "O9DICT_RAW";
}

static void
gen_dict_init_expr(char *expr, Type *dict)
{
    Type *kt, *vt;

    kt = type_list_at(dict->args, 0);
    vt = type_list_at(dict->args, 1);
    print("\to9_dict_init_typed(&%s, sizeof(%s), sizeof(%s), %s, %s);\n",
        expr,
        type_storage_for_codegen(kt),
        type_storage_for_codegen(vt),
        dict_kind_for_codegen(kt),
        dict_kind_for_codegen(vt));
}

static int
type_is_tuple(Type *t)
{
    return t != nil && t->kind == TyApply && t->name != nil &&
        strcmp(t->name, "Tuple") == 0;
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

static int
type_declares_direct_storage(Type *t)
{
    if(t == nil)
        return 1;
    if(type_is_class_ref(t))
        return 0;
    return 1;
}

static void
note_var_class_type(char *varname, Type *t)
{
    if(varname == nil || !type_is_class_ref(t))
        return;
    add_var_class(varname, type_cname(t));
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

%}

/* ========================================================================
 * YACC TOKENS AND GRAMMAR
 * ======================================================================== */

%union {
    Node *node;
    char *name;
    Type *type;
    TypeList *types;
}

%token <node> TIDENT TTYPE TQIDENT TTYPEIDENT TENUMIDENT
%token <name> TINTLIT TSTRINGLIT TCHARLIT TRAWC
%token <name> TDOUBLELIT
%token TCLASS TINTERFACE TSTRUCT TENUM TMODULE TIMPORT TFUNC TFUNCTION TMAIN TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TLISTENER TDICT TLIST TTASK TNIL TABSTRACT TDELETE TSPAWN TCAST TUSE
%token TALT TCASE TDEFAULT
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
%right TTRY
%left '.' '['
 
%type <node> program top_levels top_level class_decl class_head interface_decl interface_head struct_decl struct_head enum_decl enum_vals enum_val module_decl module_head import_decl object_decl member_list member member_body var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename name_ref type_name_ref decl_name generic_name enum_name member_name spawn_name dep_name dep_list param_list param call_args call_arg main_decl func_top_level function_decl for_init for_cond for_step else_clause generic_opt generic_names abstract_opt alt_stmt alt_cases alt_case locality
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
    | '(' type_args ')' {
        if(type_list_len($2) == 1)
            $$ = $2->type;
        else
            $$ = type_apply("Tuple", $2);
    }
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
        $$ = mk_typed(NMethod, "main", typed_node_from_name("void"), $3, nil);
        $$->flags |= NFMain;
    }
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $6, nil);
    }
    ;

/* `function name(params) type { body }` — desugars to a templated class
 * (fixed spawn skeleton + the one user method `run`). See docs/CONCURRENCY.md. */
function_decl:
    TFUNCTION TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        char *fname = current_parse_class_source != nil ?
            join_module_name(current_parse_class_source, $2->name) : $2->name;
        $$ = synth_function_class(fname, $6, $4, $8);
    }
    | TFUNCTION TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        char *fname = current_parse_class_source != nil ?
            join_module_name(current_parse_class_source, $2->name) : $2->name;
        $$ = synth_function_class(fname, nil, $4, $7);
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
        push_parse_class(source);
    }
    ;

class_decl:
    class_head member_list '}'
    {
        pop_parse_class();
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
    | function_decl
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
    | TSTREAM '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $5->name, $3, nil, nil);
    }
    | TCHAN '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $5->name, $3, nil, nil);
    }
    | TIDENT TSTREAM TIDENT ';'
    {
        $$ = mk(NStream, $3->name, nil, nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TSTREAM '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $6->name, $4, nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TCHAN member_name ';'
    {
        $$ = mk_typed(NStream, $3->name, typed_node_from_name("chan"), nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TCHAN '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $6->name, $4, nil, nil);
        set_channel_dir($$, $1);
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
        $$ = mk_typed(NMethod, $3->name, typed_node_from_name("void"), nil, $5);
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
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $7, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $7, nil);
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), body, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), nil, $4);
        $$->flags |= NFMethodDecl;
    }
    | TMETHOD TTYPEIDENT '(' param_list ')' '{' stmt_list '}'
    {
        /* Constructor: class names lex as TTYPEIDENT (prescan registers them),
         * so method Counter(...) never matches the TIDENT rules above. */
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $7, $4);
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
        $$ = mk_typed(NStream, $2->name, typed_node_from_name("chan"), nil, nil);
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
    typename member_name ';' { $$ = mk_typed(NLocalVar, $2->name, $1, nil, nil); note_var_class_type($2->name, $1->typeinfo); }
    | typename member_name TEQ expr ';' { $$ = mk_typed(NLocalVar, $2->name, $1, $4, nil); note_var_class_type($2->name, $1->typeinfo); }
    | locality typename member_name TEQ expr '@' expr ';' {
        $$ = mk_typed(NLocalVar, $3->name, $2, $5, nil);
        $$->cname = strdup($1->name);	/* locality tag for this declaration */
        $$->params = $7;		/* address expression after @ */
        note_var_class_type($3->name, $2->typeinfo);
    }
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
    | alt_stmt { $$ = $1; }
    | TUSE '{' dep_list '}' { $$ = mk(NUse, nil, nil, $3, nil); }
    | TRAWC { $$ = mk(NRawC, $1, nil, nil, nil); }
    ;

alt_stmt:
    TALT '{' alt_cases '}'
    {
        $$ = mk(NAlt, nil, nil, $3, nil);
    }
    ;

alt_cases:
    alt_case { $$ = $1; }
    | alt_cases alt_case { $$ = append_node($1, $2); }
    ;

alt_case:
    TCASE expr TEQ TCHANRECV expr ':' stmt_list
    {
        $$ = mk(NAltCase, nil, nil, mk(NChanRecv, nil, nil, $2, $5), $7);
    }
    | TDEFAULT ':' stmt_list
    {
        $$ = mk(NAltDefault, nil, nil, $3, nil);
    }
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

locality:
    TNEAR { $$ = mk(NIdent, "near", nil, nil, nil); }
    | TFAR { $$ = mk(NIdent, "far", nil, nil, nil); }
    | TLISTENER { $$ = mk(NIdent, "listener", nil, nil, nil); }
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
    | TDOUBLELIT { $$ = mk(NDoubleLit, $1, nil, nil, nil); }
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
    | TCAST '<' type_expr '>' '(' expr ')' {
        Node *tn = type_node($3);
        $$ = mk_typed(NCast, "cast", tn, $6, nil);
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
    | '(' call_args ')' {
        if(node_list_len($2) == 1)
            $$ = $2;
        else
            $$ = mk(NTupleLit, nil, nil, $2, nil);
    }
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

/* ========================================================================
 * AST CONSTRUCTION
 * ======================================================================== */

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

    fld = mk_typed(NProp, blob, typed_node_from_name("string"), nil, nil);

    params = mk_typed(NProp, "key", typed_node_from_name("string"), nil, nil);
    params->next = mk_typed(NProp, "v", typed_node_from_name("string"), nil, nil);
    args = mk(NIdent, "key", nil, nil, nil);
    args->next = mk(NIdent, "v", nil, nil, nil);
    body = mk(NAssign, nil, nil,
        mk(NIdent, blob, nil, nil, nil),
        mk(NSelfCall, "encrypt", nil, nil, args));
    sealm = mk_typed(NMethod, seal, typed_node_from_name("void"), body, params);

    params = mk_typed(NProp, "key", typed_node_from_name("string"), nil, nil);
    args = mk(NIdent, "key", nil, nil, nil);
    args->next = mk(NIdent, blob, nil, nil, nil);
    body = mk(NReturn, nil, nil,
        mk(NSelfCall, "decrypt", nil, nil, args), nil);
    openm = mk_typed(NMethod, open, typed_node_from_name("string"), body, params);

    fld->next = sealm;
    sealm->next = openm;
    return fld;
}

/* Synthesize the templated class for a `function` (see docs/CONCURRENCY.md):
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
    members = mk_typed(NProp, "__spawn_index", typed_node_from_name("int64"), nil, nil);
    members->flags |= NFPrivate;
    members->next = mk_typed(NProp, "__spawn_state", typed_node_from_name("int64"), nil, nil);
    members->next->flags |= NFPrivate;
    /* __spawn_result is a chan (object-IPC endpoint, auto-created). */
    members->next->next = mk_typed(NStream, "__spawn_result", typed_node_from_name("chan"), nil, nil);
    members->next->next->flags |= NFPrivate;

    /* The one user method, named `run`. */
    if(rettn != nil)
        meth = mk_typed(NMethod, "run", rettn, body, params);
    else
        meth = mk_typed(NMethod, "run", typed_node_from_name("void"), body, params);
    meth->flags |= NFSelfCalled;	/* callable directly too */
    members->next->next->next = meth;

    cls->left = members;
    add_class(cls->name, cls);
    return cls;
}

static char*
spawn_function_cname(char *name, Node *scope_class)
{
    char *source, *cname, *outer;
    Node *fc;

    if(name == nil)
        return nil;
    if(scope_class != nil && !name_has_module(name)){
        outer = scope_class->qname != nil ? scope_class->qname : scope_class->name;
        if(outer != nil){
            source = join_module_name(outer, name);
            cname = mangle_source_name(source);
            fc = find_class(cname);
            if(fc != nil && (fc->flags & NFFunction))
                return cname;
        }
    }
    source = qualify_source_name(current_module, name);
    return mangle_source_name(source);
}

/* ========================================================================
 * LEXER
 * ======================================================================== */

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
            if(c == '.'){
                if(i < 63) buf[i++] = c;
                while(isdigit(c = lex_getc())) {
                    if(i < 63) buf[i++] = c;
                }
                if(c == 'e' || c == 'E'){
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                    if(c == '+' || c == '-'){
                        if(i < 63) buf[i++] = c;
                        c = lex_getc();
                    }
                    while(isdigit(c)) {
                        if(i < 63) buf[i++] = c;
                        c = lex_getc();
                    }
                }
                lex_ungetc(c);
                buf[i] = '\0';
                yylval.name = strdup(buf);
                return TDOUBLELIT;
            }
            if(c == 'e' || c == 'E'){
                if(i < 63) buf[i++] = c;
                c = lex_getc();
                if(c == '+' || c == '-'){
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                }
                while(isdigit(c)) {
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                }
                lex_ungetc(c);
                buf[i] = '\0';
                yylval.name = strdup(buf);
                return TDOUBLELIT;
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
            if(strcmp(buf, "alt") == 0) return TALT;
            if(strcmp(buf, "case") == 0) return TCASE;
            if(strcmp(buf, "default") == 0) return TDEFAULT;
            if(strcmp(buf, "cast") == 0) return TCAST;
            if(strcmp(buf, "use") == 0) return TUSE;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "listener") == 0) return TLISTENER;
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
            if(strcmp(buf, "double") == 0) return TTYPE;
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

/* ========================================================================
 * CODEGEN
 * ======================================================================== */

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
static int alt_tmp_id;

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
static char *node_kind(int type);

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

typedef void (*GenExprFn)(Node*);
typedef int (*GenMsgFn)(Node*, Type*);
typedef int (*GenArrayGetFn)(Node*, Type*);

typedef struct CMethod CMethod;
struct CMethod {
    char *name;
    char *cname;
};

static int
type_named(Type *t, char *name)
{
    if(t == nil)
        return 0;
    if(t->kind != TyName)
        return 0;
    if(t->name == nil)
        return 0;
    return strcmp(t->name, name) == 0;
}

static int
type_apply_named(Type *t, char *name)
{
    if(t == nil)
        return 0;
    if(t->kind != TyApply)
        return 0;
    if(t->name == nil)
        return 0;
    return strcmp(t->name, name) == 0;
}

static int
expr_name_is(Node *e, char *name)
{
    if(e == nil)
        return 0;
    if(e->name == nil)
        return 0;
    return strcmp(e->name, name) == 0;
}

static char*
lookup_cmethod(CMethod *m, int n, char *name)
{
    int i;

    if(name == nil)
        return nil;
    for(i = 0; i < n; i++)
        if(strcmp(m[i].name, name) == 0)
            return m[i].cname;
    return nil;
}

static void
gen_receiver_call_args(char *fn, Node *recv, Node *args)
{
    Node *a;

    print("%s(", fn);
    gen_expr(recv);
    for(a = args; a != nil; a = a->next){
        print(", ");
        gen_expr(a);
    }
    print(")");
}

static void
gen_try_expr(Node *e)
{
    gen_expr(e->left);
}

static void
gen_spawn_expr(Node *e)
{
    char *fc;
    Node *a;

    fc = spawn_function_cname(e->name, gen_class);
    print("o9_spawn_%s(", fc);
    for(a = e->right; a; a = a->next){
        if(a != e->right)
            print(", ");
        gen_expr(a);
    }
    print(")");
}

static void
gen_cast_expr(Node *e)
{
    if(type_cast_target_is_bool(e->typeinfo)){
        print("((");
        gen_expr(e->left);
        print(") != 0)");
        return;
    }
    print("((%s)(", type_cast_for_codegen(e->typeinfo));
    gen_expr(e->left);
    print("))");
}

static void
gen_ident_expr(Node *e)
{
    if(is_local(e->name)){
        print("%s", e->name);
        return;
    }
    if(in_class_context){
        print("self->%s", e->name);
        return;
    }
    print("%s", e->name);
}

static void
gen_name_expr(Node *e)
{
    print("%s", e->name);
}

static void
gen_string_lit_expr(Node *e)
{
    print("o9_string_new(");
    gen_c_string_literal(e->name);
    print(", %d)", strlen(e->name));
}

static void
gen_char_lit_expr(Node *e)
{
    print("'%s'", e->name);
}

static int
tuple_arg_needs_cast(TypeList *ta)
{
    if(ta == nil)
        return 0;
    return type_storage_pointerish(ta->type);
}

static void
gen_tuple_lit_expr(Node *e)
{
    Node *a;
    TypeList *ta;
    char *cn;
    int i;

    cn = type_cname(e->typeinfo);
    print("o9_tuple_new_%s(", cn);
    for(a = e->left, ta = e->typeinfo != nil ? e->typeinfo->args : nil, i = 0;
        a != nil; a = a->next, ta = ta != nil ? ta->next : nil, i++){
        if(i > 0)
            print(", ");
        if(tuple_arg_needs_cast(ta)){
            print("(%s)(uintptr)(", type_storage_for_codegen(ta->type));
            gen_expr(a);
            print(")");
            continue;
        }
        gen_expr(a);
    }
    print(")");
}

static int
gen_tabula_new_expr(Node *e)
{
    int argc;

    if(!type_named(e->typeinfo, "Tabula"))
        return 0;
    argc = node_list_len(e->right);
    if(argc == 1){
        print("o9_tab_open(");
        gen_expr(e->right);
        print(")");
        return 1;
    }
    if(argc == 2){
        print("o9_tab_new(");
        gen_expr(e->right);
        print(", ");
        gen_expr(e->right->next);
        print(")");
        return 1;
    }
    print("nil /* invalid Tabula constructor */");
    return 1;
}

static int
gen_mounttable_new_expr(Node *e)
{
    if(!type_named(e->typeinfo, "MountTable"))
        return 0;
    print("o9_mount_table_new(");
    if(e->right != nil)
        gen_expr(e->right);
    else
        print("nil");
    print(")");
    return 1;
}

static void
gen_class_expr(Node *e)
{
    if(gen_tabula_new_expr(e))
        return;
    if(gen_mounttable_new_expr(e))
        return;
    print("0 /* unsupported new expression: %s */", e->name != nil ? e->name : "?");
}

static int
builtin_arg_kind(Builtin *bi, int pi, char *kind)
{
    if(pi >= bi->argc)
        return 0;
    if(bi->args[pi] == nil)
        return 0;
    return strcmp(bi->args[pi], kind) == 0;
}

static void
gen_self_builtin_arg(Builtin *bi, int pi, Node *a)
{
    if(builtin_arg_kind(bi, pi, "object")){
        print("&");
        gen_expr(a);
        return;
    }
    if(builtin_arg_kind(bi, pi, "string")){
        if(a->type == NMsgSend){
            print("(O9String*)(uintptr)(");
            gen_expr(a);
            print(")");
            return;
        }
    }
    gen_expr(a);
}

static int
gen_self_builtin_expr(Node *e)
{
    Builtin *bi;
    Node *a;
    int pi;

    bi = find_builtin(e->name);
    if(bi == nil)
        return 0;
    pi = 0;
    print("%s(", bi->runtime);
    for(a = e->right; a; a = a->next, pi++){
        if(a != e->right)
            print(", ");
        gen_self_builtin_arg(bi, pi, a);
    }
    print(")");
    return 1;
}

static void
gen_self_call_expr(Node *e)
{
    Node *owner;
    Node *a;

    owner = gen_class != nil ? method_owner(gen_class, e->name) : nil;
    if(owner == nil){
        if(gen_self_builtin_expr(e))
            return;
        print("0 /* unresolved self call: %s */", e->name);
        return;
    }
    print("o9_self_%s_%s((%s_Internal*)self", owner->name, e->name, owner->name);
    for(a = e->right; a; a = a->next){
        print(", ");
        gen_expr(a);
    }
    print(")");
}

static int
gen_task_msg(Node *e, Type *lt)
{
    Type *at;
    char *rt;

    if(!type_apply_named(lt, "Task"))
        return 0;
    if(!expr_name_is(e, "await"))
        return 0;
    at = type_list_at(lt->args, 0);
    rt = type_storage_for_codegen(at);
    if(type_is_double(at))
        print("o9_task_await_double(");
    else
        print("(%s)o9_task_await(", rt);
    gen_expr(e->left);
    print(")");
    return 1;
}

static int
gen_mapped_handle_msg(Node *e, Type *lt, char *typename, CMethod *map, int nmap)
{
    char *fn;

    if(!type_named(lt, typename))
        return 0;
    fn = lookup_cmethod(map, nmap, e->name);
    if(fn == nil)
        return 0;
    gen_receiver_call_args(fn, e->left, e->right);
    return 1;
}

static int
gen_tabula_msg(Node *e, Type *lt)
{
    static CMethod map[] = {
        {"schema", "o9_tab_schema"},
        {"has", "o9_tab_has"},
        {"add", "o9_tab_add"},
        {"write", "o9_tab_write"},
        {"set", "o9_tab_set"},
        {"get", "o9_tab_get"},
        {"first", "o9_tab_first"},
        {"next", "o9_tab_next"},
        {"read", "o9_tab_read"},
        {"serialize", "o9_tab_serialize"},
        {"query", "o9_tab_query"},
        {"flush", "o9_tab_flush"},
        {"sync", "o9_tab_sync"},
        {"push", "o9_tab_push"},
        {"close", "o9_tab_close"},
    };

    return gen_mapped_handle_msg(e, lt, "Tabula", map, nelem(map));
}

static int
gen_mounttable_msg(Node *e, Type *lt)
{
    static CMethod map[] = {
        {"allowRoot", "o9_mount_table_allow_root"},
        {"dir", "o9_mount_table_dir"},
        {"bind", "o9_mount_table_bind"},
        {"mountsrv", "o9_mount_table_mountsrv"},
        {"schema", "o9_mount_table_schema"},
        {"has", "o9_mount_table_has"},
        {"get", "o9_mount_table_get"},
        {"first", "o9_mount_table_first"},
        {"next", "o9_mount_table_next"},
        {"read", "o9_mount_table_read"},
        {"serialize", "o9_mount_table_serialize"},
        {"query", "o9_mount_table_query"},
        {"flush", "o9_mount_table_flush"},
        {"validate", "o9_mount_table_validate"},
        {"apply", "o9_mount_table_apply"},
        {"close", "o9_mount_table_close"},
    };

    return gen_mapped_handle_msg(e, lt, "MountTable", map, nelem(map));
}

static int
gen_list_add_msg(Node *e, Type *lt)
{
    Type *et, *rt;
    char *st;

    if(!expr_name_is(e, "Add"))
        return 0;
    et = type_list_at(lt->args, 0);
    rt = e->right != nil ? e->right->typeinfo : nil;
    st = type_storage_for_codegen(et);
    if(type_is_class_ref(et) && type_is_class_ref(rt)){
        print("({ %s __v; memmove(&__v, &", st);
        gen_expr(e->right);
        print(", sizeof(%s)); o9_slice_append(&", st);
    } else {
        print("({ %s __v = ", st);
        gen_expr(e->right);
        print("; o9_slice_append(&");
    }
    gen_expr(e->left);
    print(", &__v); (vlong)0; })");
    return 1;
}

static int
gen_list_length_msg(Node *e, Type *lt)
{
    (void)lt;
    if(!expr_name_is(e, "Length"))
        return 0;
    print("(vlong)(");
    gen_expr(e->left);
    print(".len)");
    return 1;
}

static int
gen_list_msg(Node *e, Type *lt)
{
    if(!type_is_collection(lt, "List"))
        return 0;
    if(gen_list_add_msg(e, lt))
        return 1;
    if(gen_list_length_msg(e, lt))
        return 1;
    return 0;
}

static int
type_is_integral_dict_key(Type *t)
{
    char *a;

    if(t == nil || t->kind != TyName || type_is_string(t) || type_is_double(t))
        return 0;
    a = type_builtin_abi(t->name);
    return a != nil && strcmp(a, "scalar") == 0;
}

static int
gen_dict_key_call(char *stringfn, char *intfn, char *doublefn, Node *dict, Node *key, Type *kt)
{
    if(type_is_string(kt)){
        print("%s(&", stringfn);
        gen_expr(dict);
        print(", ");
        gen_expr(key);
        print(")");
        return 1;
    }
    if(type_is_double(kt)){
        print("%s(&", doublefn);
        gen_expr(dict);
        print(", ");
        gen_expr(key);
        print(")");
        return 1;
    }
    if(type_is_integral_dict_key(kt)){
        print("%s(&", intfn);
        gen_expr(dict);
        print(", (vlong)(");
        gen_expr(key);
        print("))");
        return 1;
    }
    print("O9_DICT_KEY_REQUIRES_STRING_OR_SCALAR");
    return 1;
}

static int
gen_dict_msg(Node *e, Type *lt)
{
    Type *kt;

    if(!type_is_collection(lt, "Dict"))
        return 0;
    if(!expr_name_is(e, "Has"))
        return 0;
    kt = type_list_at(lt->args, 0);
    gen_dict_key_call("o9_dict_hass", "o9_dict_hasi", "o9_dict_hasd",
        e->left, e->right, kt);
    return 1;
}

static int
msg_arg_count(Node *args)
{
    int n;
    Node *a;

    n = 0;
    for(a = args; a; a = a->next)
        n++;
    return n;
}

static int
msg_receiver_candidate(Node *recv)
{
    if(recv == nil)
        return 0;
    if(recv->type != NIdent)
        return 0;
    if(recv->name == nil)
        return 0;
    return 1;
}

static int
msg_receiver_field_scope(Node *recv)
{
    if(!in_method_body)
        return 0;
    if(gen_class == nil)
        return 0;
    if(is_local(recv->name))
        return 0;
    return member_exists(gen_class, recv->name);
}

static char*
field_decl_class(char *name)
{
    Node *fn;
    Type *ft;

    fn = member_node(gen_class, name, 0);
    if(fn == nil)
        return nil;
    ft = decl_typeinfo(fn);
    if(ft == nil)
        return nil;
    if(!type_is_class_ref(ft))
        return nil;
    return type_cname(ft);
}

static char*
msg_field_class(Node *recv)
{
    if(!msg_receiver_candidate(recv))
        return nil;
    if(!msg_receiver_field_scope(recv))
        return nil;
    return field_decl_class(recv->name);
}

static int
gen_msg_field_receiver(Node *recv)
{
    char *fcls;

    fcls = msg_field_class(recv);
    if(fcls == nil)
        return 0;
    print("(vlong)((%s_Client*)&", fcls);
    gen_expr(recv);
    print(")->shm_base");
    return 1;
}

static int
gen_msg_named_receiver(Node *recv)
{
    char *cn;

    if(!msg_receiver_candidate(recv))
        return 0;
    cn = get_var_class(recv->name);
    if(cn)
        print("(vlong)((%s_Client*)&", cn);
    gen_expr(recv);
    if(cn)
        print(")->shm_base");
    return 1;
}

static int
gen_msg_typed_receiver(Node *recv)
{
    Type *rtyp;
    char *rcls;

    rtyp = recv != nil ? recv->typeinfo : nil;
    rcls = type_is_class_ref(rtyp) ? type_cname(rtyp) : nil;
    if(rcls == nil)
        return 0;
    print("(vlong)((%s_Client*)&", rcls);
    gen_expr(recv);
    print(")->shm_base");
    return 1;
}

static void
gen_msg_receiver_frame(Node *recv)
{
    if(gen_msg_field_receiver(recv))
        return;
    if(gen_msg_named_receiver(recv))
        return;
    if(gen_msg_typed_receiver(recv))
        return;
    print("(vlong)&");
    gen_expr(recv);
}

static void
gen_msg_arg_value(Node *a)
{
    if(type_is_class_ref(a->typeinfo)){
        print("(vlong)(uintptr)&(");
        gen_expr(a);
        print(")");
        return;
    }
    if(type_is_double(a->typeinfo)){
        print("o9_double_pack(");
        gen_expr(a);
        print(")");
        return;
    }
    if(type_storage_pointerish(a->typeinfo)){
        print("(vlong)(uintptr)(");
        gen_expr(a);
        print(")");
        return;
    }
    print("(vlong)(");
    gen_expr(a);
    print(")");
}

static void
gen_msg_arg_frame(Node *args, int d)
{
    Node *a;
    int i;

    i = 1;
    for(a = args; a; a = a->next){
        print(", __o9fr[%d][%d]=", d, i);
        gen_msg_arg_value(a);
        i++;
    }
}

static void
gen_msg_return_prefix(char *retst, int retptr, int retdouble)
{
    if(retptr){
        if(!retdouble)
            print("(%s)(uintptr)(", retst);
    }
}

static void
gen_msg_return_suffix(int retptr, int retdouble)
{
    if(retptr){
        if(!retdouble)
            print(")");
    }
}

static void
gen_msg_fallback_call(Node *e, int d, int nargs, int retdouble)
{
    print(retdouble ? "obj9_msgSendDoubleN(&" : "(vlong)obj9_msgSendN(&");
    gen_expr(e->left);
    if(msg_receiver_candidate(e->left))
        print(", \"%s/%s\", 0x%lux, __o9fr[%d]+1, %d))",
            e->left->name, e->name, o9_hash(e->name), d, nargs);
    else
        print(", \"%s\", 0x%lux, __o9fr[%d]+1, %d))",
            e->name, o9_hash(e->name), d, nargs);
}

static void
gen_msg_dispatch_tail(Node *e, int d, int nargs, int retdouble)
{
    print(", o9_dispatch_call(&");
    gen_expr(e->left);
    if(retdouble)
        print(", 0x%lux, __o9fr[%d]) != nil ? o9_double_unpack(__o9fr[%d][0]) : ",
            o9_hash(e->name), d, d);
    else
        print(", 0x%lux, __o9fr[%d]) != nil ? __o9fr[%d][0] : ",
            o9_hash(e->name), d, d);
    gen_msg_fallback_call(e, d, nargs, retdouble);
}

static void
gen_object_msg_send(Node *e)
{
    char *retst;
    int retptr, retdouble, nargs, d;

    retst = nil;
    retptr = 0;
    retdouble = 0;
    if(e->typeinfo != nil){
        retst = type_storage_for_codegen(e->typeinfo);
        retptr = storage_pointerish(retst);
        retdouble = type_is_double(e->typeinfo);
    }
    nargs = msg_arg_count(e->right);
    gen_msg_return_prefix(retst, retptr, retdouble);
    d = msg_frame_alloc();
    print("(__o9fr[%d][0]=", d);
    gen_msg_receiver_frame(e->left);
    gen_msg_arg_frame(e->right, d);
    gen_msg_dispatch_tail(e, d, nargs, retdouble);
    gen_msg_return_suffix(retptr, retdouble);
}

static GenMsgFn gen_msg_handlers[] = {
    gen_task_msg,
    gen_tabula_msg,
    gen_mounttable_msg,
    gen_list_msg,
    gen_dict_msg,
    nil,
};

static void
gen_msg_send_expr(Node *e)
{
    Type *lt;
    int i;

    lt = e->left != nil ? e->left->typeinfo : nil;
    for(i = 0; gen_msg_handlers[i] != nil; i++)
        if(gen_msg_handlers[i](e, lt))
            return;
    if(type_is_class_ref(e->typeinfo)){
        print("O9_CLASS_RETURN_REQUIRES_OBJECT_TARGET");
        return;
    }
    gen_object_msg_send(e);
}

static void
gen_prop_internal_value(Node *e, char *cn, Type *mt, Node *member, Node *tn)
{
    if(tn != nil && tn->type == NStruct){
        print("((%s_Internal*)((%s_Client*)&", cn, cn);
        gen_expr(e->left);
        print(")->shm_base)->%s", e->name);
        return;
    }
    if((member != nil && member->type == NStream) ||
       type_is_string(mt) || type_is_char_pointer(mt) ||
       type_is_dict(mt) || type_is_list(mt) || type_is_array(mt) ||
       type_is_double(mt)){
        print("((%s_Internal*)((%s_Client*)&", cn, cn);
        gen_expr(e->left);
        print(")->shm_base)->%s", e->name);
        return;
    }
    print("(vlong)((%s_Internal*)((%s_Client*)&", cn, cn);
    gen_expr(e->left);
    print(")->shm_base)->%s", e->name);
}

static int
gen_prop_class_read(Node *e, Type *rt, char *cn)
{
    TypedMember tm;
    Type *mt;
    Node *tn;

    memset(&tm, 0, sizeof tm);
    mt = nil;
    tn = nil;
    if(typed_member_lookup(rt, e->name, 0, &tm)){
        mt = tm.type;
        tn = type_decl_node(mt);
    }
    gen_prop_internal_value(e, cn, mt, tm.node, tn);
    return 1;
}

static int
gen_prop_struct_read(Node *e)
{
    gen_expr(e->left);
    print(".%s", e->name);
    return 1;
}

static void
gen_prop_read_expr(Node *e)
{
    Type *rt;
    char *cn;
    Node *cnode;

    rt = e->left != nil ? e->left->typeinfo : nil;
    cn = rt != nil ? type_cname(rt) : nil;
    cnode = type_decl_node(rt);
    if(cnode != nil){
        if(cnode->type == NClass || cnode->type == NInterface){
            gen_prop_class_read(e, rt, cn);
            return;
        }
        if(cnode->type == NStruct){
            gen_prop_struct_read(e);
            return;
        }
    }
    gen_prop_struct_read(e);
}

static char*
expr_binary_op(int type)
{
    static char *ops[NNodeKinds];

    if(ops[NAdd] == nil){
        ops[NAdd] = " + ";
        ops[NSub] = " - ";
        ops[NMul] = " * ";
        ops[NDiv] = " / ";
        ops[NMod] = " %% ";
        ops[NEq] = " == ";
        ops[NNe] = " != ";
        ops[NLt] = " < ";
        ops[NLe] = " <= ";
        ops[NGt] = " > ";
        ops[NGe] = " >= ";
        ops[NAnd] = " && ";
        ops[NOr] = " || ";
        ops[NBitAnd] = " & ";
        ops[NBitOr] = " | ";
        ops[NBitXor] = " ^ ";
        ops[NLshift] = " << ";
        ops[NRshift] = " >> ";
    }
    if(type < 0 || type >= NNodeKinds)
        return nil;
    return ops[type];
}

static void
gen_binary_expr(Node *e)
{
    char *op;

    op = expr_binary_op(e->type);
    if(op == nil)
        return;
    print("(");
    gen_expr(e->left);
    print("%s", op);
    gen_expr(e->right);
    print(")");
}

static char*
expr_unary_op(int type)
{
    static char *ops[NNodeKinds];

    if(ops[NNot] == nil){
        ops[NNot] = "!";
        ops[NBitNot] = "~";
        ops[NNeg] = "-";
    }
    if(type < 0 || type >= NNodeKinds)
        return nil;
    return ops[type];
}

static void
gen_unary_expr(Node *e)
{
    print("%s", expr_unary_op(e->type));
    gen_expr(e->left);
}

static int
print_single_literal(Node *a)
{
    if(a == nil)
        return 0;
    if(a->type != NStringLit)
        return 0;
    if(a->next != nil)
        return 0;
    return strchr(a->name, '%') == nil;
}

static int
print_explicit_format(Node *a)
{
    if(a == nil)
        return 0;
    if(a->type != NStringLit)
        return 0;
    if(a->next == nil)
        return 0;
    return strchr(a->name, '%') != nil;
}

static void
gen_print_escaped_literal(char *s)
{
    char *p;

    for(p = s; *p; p++){
        if(*p == '%') print("%%%%");
        else if(*p == '\n') print("\\n");
        else if(*p == '\t') print("\\t");
        else if(*p == '\\') print("\\\\");
        else if(*p == '"') print("\\\"");
        else print("%c", *p);
    }
}

static void
gen_print_format_piece(Node *a)
{
    if(a->type == NStringLit && a->name != nil){
        gen_print_escaped_literal(a->name);
        return;
    }
    if(type_is_string(a->typeinfo)){
        print("%%s");
        return;
    }
    if(type_is_double(a->typeinfo)){
        print("%%g");
        return;
    }
    print("%%lld");
}

static void
gen_print_value_arg(Node *a)
{
    if(a->type == NStringLit)
        return;
    print(", ");
    if(type_is_string(a->typeinfo)){
        print("o9_string_data(");
        gen_expr(a);
        print(")");
        return;
    }
    if(type_is_double(a->typeinfo)){
        gen_expr(a);
        return;
    }
    print("(vlong)(");
    gen_expr(a);
    print(")");
}

static void
gen_print_explicit_args(Node *a)
{
    for(a = a->next; a; a = a->next){
        print(", ");
        if(type_is_string(a->typeinfo)){
            print("o9_string_data(");
            gen_expr(a);
            print(")");
            continue;
        }
        gen_expr(a);
    }
}

static void
gen_print_auto(Node *a)
{
    Node *a2;

    print("\"");
    for(a2 = a; a2; a2 = a2->next)
        gen_print_format_piece(a2);
    print("\"");
    for(a2 = a; a2; a2 = a2->next)
        gen_print_value_arg(a2);
}

static void
gen_print_expr(Node *e)
{
    Node *a;

    a = e->left;
    print("fprint(1, ");
    if(a == nil)
        print("\"\"");
    else if(print_single_literal(a))
        gen_c_string_literal(a->name);
    else if(print_explicit_format(a)){
        gen_c_string_literal(a->name);
        gen_print_explicit_args(a);
    } else
        gen_print_auto(a);
    print(")");
}

static void
gen_raw_func_call_expr(Node *e)
{
    Node *a;
    int first;

    first = 1;
    print("%s(", e->name);
    for(a = e->left; a; a = a->next){
        if(!first)
            print(", ");
        gen_expr(a);
        first = 0;
    }
    print(")");
}

static void
gen_func_call_expr(Node *e)
{
    if(expr_name_is(e, "print")){
        gen_print_expr(e);
        return;
    }
    gen_raw_func_call_expr(e);
}

static int
gen_array_list_get(Node *e, Type *lt)
{
    Type *et;

    if(!type_is_collection(lt, "List"))
        return 0;
    et = type_list_at(lt->args, 0);
    print("(*(%s*)o9_slice_get(&", type_storage_for_codegen(et));
    gen_expr(e->left);
    print(", ");
    gen_expr(e->right);
    print("))");
    return 1;
}

static int
gen_array_array_get(Node *e, Type *lt)
{
    Type *et;

    if(!type_is_array(lt))
        return 0;
    et = type_array_elem(lt);
    print("(*(%s*)o9_slice_get(&", type_storage_for_codegen(et));
    gen_expr(e->left);
    print(", ");
    gen_expr(e->right);
    print("))");
    return 1;
}

static int
gen_array_dict_get(Node *e, Type *lt)
{
    Type *kt, *vt;

    if(!type_is_collection(lt, "Dict"))
        return 0;
    kt = type_list_at(lt->args, 0);
    vt = type_list_at(lt->args, 1);
    print("(*(%s*)", type_storage_for_codegen(vt));
    gen_dict_key_call("o9_dict_getsk", "o9_dict_geti", "o9_dict_getd",
        e->left, e->right, kt);
    print(")");
    return 1;
}

static GenArrayGetFn gen_array_get_handlers[] = {
    gen_array_list_get,
    gen_array_array_get,
    gen_array_dict_get,
    nil,
};

static void
gen_array_get_expr(Node *e)
{
    Type *lt;
    int i;

    lt = e->left != nil ? e->left->typeinfo : nil;
    for(i = 0; gen_array_get_handlers[i] != nil; i++)
        if(gen_array_get_handlers[i](e, lt))
            return;
    print("o9_array_get(");
    gen_expr(e->left);
    print(", ");
    gen_expr(e->right);
    print(")");
}

static void
gen_expr_default(Node *e)
{
    print("0 /* unsupported expr: %s */", node_kind(e->type));
}

static GenExprFn gen_expr_handlers[NNodeKinds];

static void
init_gen_expr_handlers(void)
{
    if(gen_expr_handlers[NIdent] != nil)
        return;
    gen_expr_handlers[NTry] = gen_try_expr;
    gen_expr_handlers[NSpawn] = gen_spawn_expr;
    gen_expr_handlers[NCast] = gen_cast_expr;
    gen_expr_handlers[NIdent] = gen_ident_expr;
    gen_expr_handlers[NIntLit] = gen_name_expr;
    gen_expr_handlers[NDoubleLit] = gen_name_expr;
    gen_expr_handlers[NStringLit] = gen_string_lit_expr;
    gen_expr_handlers[NTupleLit] = gen_tuple_lit_expr;
    gen_expr_handlers[NCharLit] = gen_char_lit_expr;
    gen_expr_handlers[NBoolLit] = gen_name_expr;
    gen_expr_handlers[NEnumVal] = gen_name_expr;
    gen_expr_handlers[NClass] = gen_class_expr;
    gen_expr_handlers[NSelfCall] = gen_self_call_expr;
    gen_expr_handlers[NMsgSend] = gen_msg_send_expr;
    gen_expr_handlers[NPropRead] = gen_prop_read_expr;
    gen_expr_handlers[NAdd] = gen_binary_expr;
    gen_expr_handlers[NSub] = gen_binary_expr;
    gen_expr_handlers[NMul] = gen_binary_expr;
    gen_expr_handlers[NDiv] = gen_binary_expr;
    gen_expr_handlers[NMod] = gen_binary_expr;
    gen_expr_handlers[NEq] = gen_binary_expr;
    gen_expr_handlers[NNe] = gen_binary_expr;
    gen_expr_handlers[NLt] = gen_binary_expr;
    gen_expr_handlers[NLe] = gen_binary_expr;
    gen_expr_handlers[NGt] = gen_binary_expr;
    gen_expr_handlers[NGe] = gen_binary_expr;
    gen_expr_handlers[NAnd] = gen_binary_expr;
    gen_expr_handlers[NOr] = gen_binary_expr;
    gen_expr_handlers[NBitAnd] = gen_binary_expr;
    gen_expr_handlers[NBitOr] = gen_binary_expr;
    gen_expr_handlers[NBitXor] = gen_binary_expr;
    gen_expr_handlers[NLshift] = gen_binary_expr;
    gen_expr_handlers[NRshift] = gen_binary_expr;
    gen_expr_handlers[NNot] = gen_unary_expr;
    gen_expr_handlers[NBitNot] = gen_unary_expr;
    gen_expr_handlers[NNeg] = gen_unary_expr;
    gen_expr_handlers[NFuncCall] = gen_func_call_expr;
    gen_expr_handlers[NArrayGet] = gen_array_get_expr;
}

static GenExprFn
gen_expr_handler_for(int type)
{
    if(type < 0)
        return gen_expr_default;
    if(type >= NNodeKinds)
        return gen_expr_default;
    if(gen_expr_handlers[type] == nil)
        return gen_expr_default;
    return gen_expr_handlers[type];
}

void
gen_expr(Node *e)
{
    GenExprFn fn;

    if(e == nil)
        return;
    init_gen_expr_handlers();
    fn = gen_expr_handler_for(e->type);
    fn(e);
}

static void
gen_discard_expr_stmt(Node *e)
{
    Node *ve;
    Type *lt;
    int cvoid;

    ve = e;
    if(ve != nil && ve->type == NTry)
        ve = ve->left;
    lt = (ve != nil && ve->type == NMsgSend && ve->left != nil) ? ve->left->typeinfo : nil;
    cvoid = 0;
    if(ve == nil)
        cvoid = 1;
    else if(ve->type == NMsgSend){
        /* Normal object sends always lower to a vlong dispatch expression,
         * even when the o9 method type is void. Builtin handle methods
         * (Tabula/MountTable) lower directly to C helpers, and their void
         * methods are actual C void expressions. */
        if(lt != nil && lt->kind == TyName && lt->name != nil &&
           (strcmp(lt->name, "Tabula") == 0 || strcmp(lt->name, "MountTable") == 0) &&
           type_is_void(ve->typeinfo))
            cvoid = 1;
    } else
        cvoid = type_is_void(ve->typeinfo);

    if(e != nil && ve != nil && !cvoid &&
       (e->type == NMsgSend || e->type == NTry ||
       e->type == NSpawn ||
       (e->type == NFuncCall && e->name != nil && strcmp(e->name, "print") == 0))){
        int id = new_tmp_id++;
        print("\t{ vlong __o9discard%d = (vlong)(", id);
        gen_expr(e);
        print("); if(__o9discard%d){} }\n", id);
    } else {
        print("\t");
        gen_expr(e);
        print(";\n");
    }
}

void gen_stmt(Node *c, Node *s);
static int member_exists(Node *cnode, char *name);
int count_state_cols(Node *c);
void gen_init_internal_state(Node *c, char *ptr);
void gen_assign_new_to(char *varname, char *target, int is_field, char *lhs_type, Node *n);
void gen_state_store_typed(char *stateexpr, char *fieldexpr, char *name, Type *type);
void gen_state_store_flagged(char *stateexpr, char *fieldexpr, char *name, Type *type, int flags);
static void gen_msgsend_pack_arg(Node *a);

void
gen_assign_new(char *varname, char *lhs_type, Node *n)
{
    gen_assign_new_to(varname, varname, 0, lhs_type, n);
}

static int
node_arg_count(Node *n)
{
    int c;

    c = 0;
    for(; n != nil; n = n->next)
        c++;
    return c;
}

static void
gen_vlong_arg_array(char *tabs, char *array, Node *args, int nargs)
{
    Node *ca;
    int ai;

    if(nargs <= 0)
        return;
    print("%svlong %s[%d];\n", tabs, array, nargs);
    for(ca = args, ai = 0; ca != nil; ca = ca->next, ai++){
        print("%s%s[%d] = ", tabs, array, ai);
        gen_msgsend_pack_arg(ca);
        print(";\n");
    }
}

static void
gen_assign_connect_remote(char *varname, char *target, char *lhs_type,
    char *cn, char *tbl, int dval, Node *first_arg, int rest)
{
    char args[96];

    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", target, lhs_type);
    print("\tmemset(&%s, 0, sizeof(o9_AsmTable));\n", tbl);
    print("\t%s.table = &%s;\n", target, tbl);
    print("\t{\n\t\tchar __addr[128]; char *__addrp;\n\t\t__addrp = o9_string_cstr(");
    gen_expr(first_arg);
    print(");\n\t\tif(__addrp != nil){ snprint(__addr, sizeof __addr, \"%%s\", __addrp); free(__addrp); o9_connect(&%s, __addr, \"%s\", %d); }\n", target, cn, dval);
    print("\t\t%s.distance = %d;\n", target, dval);
    if(rest > 0){
        snprint(args, sizeof args, "__args_%s", varname);
        gen_vlong_arg_array("\t\t", args, first_arg->next, rest);
        print("\t\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, %s, %d);\n",
            target, cn, o9_hash(cn), args, rest);
    }
    print("\t}\n");
}

static void
gen_assign_alloc_local(char *varname, char *target, char *lhs_type,
    char *cn, char *tbl, int dval, Node *args, int nctor)
{
    int id;
    char ptr[64], argname[96];

    id = new_tmp_id++;
    print("\t%s_Internal *__o9n%d = emalloc9p(sizeof(%s_Internal));\n", cn, id, cn);
    print("\tmemset(__o9n%d, 0, sizeof(%s_Internal));\n", id, cn);
    print("\t__o9n%d->dispatch_chan = chancreate(sizeof(void*), 10);\n", id);
    print("\t__o9n%d->distance = %d;\n", id, dval >= 0 ? dval : -1);
    print("\t__o9n%d->state = o9_state_create_path(o9app_root, \"%s\", \"%s\", o9_state_cols_%s, %d);\n",
        id, cn, varname, cn, count_state_cols(find_class(cn)));
    snprint(ptr, sizeof ptr, "__o9n%d", id);
    gen_init_internal_state(find_class(cn), ptr);
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", target, lhs_type);
    print("\tmemset(&%s, 0, sizeof(o9_AsmTable));\n", tbl);
    print("\t%s.shm_base = __o9n%d;\n", target, id);
    print("\t%s.dispatch_chan = __o9n%d->dispatch_chan;\n", target, id);
    print("\t%s.table = &%s;\n", target, tbl);
    print("\t%s.distance = %d;\n", target, dval >= 0 ? dval : -1);
    print("\tproccreate(%s_loop, __o9n%d, 65536);\n", cn, id);
    print("\t%s_create_instance(__o9n%d, \"%s\");\n", cn, id, varname);
    if(nctor > 0){
        snprint(argname, sizeof argname, "__args_%s_%d", varname, id);
        print("\t{ ");
        gen_vlong_arg_array("", argname, args, nctor);
        print("\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, %s, %d); }\n",
            target, cn, o9_hash(cn), argname, nctor);
        return;
    }
    print("\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, nil, 0);\n", target, cn, o9_hash(cn));
}

static int
new_distance_value(char *dist)
{
    if(dist == nil)
        return -1;
    if(strcmp(dist, "near") == 0)
        return 0;
    if(strcmp(dist, "far") == 0)
        return 1;
    return -1;
}

static void
gen_assign_table_name(char *tbl, int ntbl, char *varname, int is_field)
{
    if(is_field)
        snprint(tbl, ntbl, "__o9tbl%d", new_tmp_id);
    else
        snprint(tbl, ntbl, "%s_tbl", varname);
}

static int
gen_assign_remote_new(char *varname, char *target, char *lhs_type,
    char *cn, char *tbl, int dval, Node *args, int nctor)
{
    if(dval < 0 || args == nil || args->type != NStringLit)
        return 0;
    gen_assign_connect_remote(varname, target, lhs_type, cn, tbl, dval,
        args, nctor - 1);
    return 1;
}

/* target is the C lvalue to store the client into (e.g. "motor" for a
 * local, "self->motor" for a field).  is_field: don't declare a local
 * client/tbl; use a temp AsmTable and store into the field.  varname is
 * still the instance NAME (for create_instance and state). */
void
gen_assign_new_to(char *varname, char *target, int is_field, char *lhs_type, Node *n)
{
    char *cn;
    int dval, nctor;
    char tbl[96];

    if(varname == nil || target == nil || lhs_type == nil || n == nil || n->name == nil)
        return;
    /* field target: its client struct is embedded in the Internal; use a
     * temp AsmTable rather than a `<var>_tbl` local. */
    gen_assign_table_name(tbl, sizeof tbl, varname, is_field);
    cn = n->name;
    dval = new_distance_value(n->typename);
    nctor = node_arg_count(n->right);

    if(is_field)
        print("\to9_AsmTable %s;\n", tbl);
    if(gen_assign_remote_new(varname, target, lhs_type, cn, tbl, dval, n->right, nctor))
        return;
    gen_assign_alloc_local(varname, target, lhs_type, cn, tbl, dval, n->right, nctor);
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
            if(type_is_double(ca->typeinfo)){
                print("o9_double_pack("); gen_expr(ca); print(")");
            } else if(type_storage_pointerish(ca->typeinfo)){
                print("(vlong)(uintptr)("); gen_expr(ca); print(")");
            } else
                gen_expr(ca);
            print(";\n");
            ai++;
        }
        print("\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, __args_%s, %d); }\n", s->name, cn, o9_hash(cn), s->name, nctor);
    } else {
        print("\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, nil, 0);\n", s->name, cn, o9_hash(cn));
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

static Type*
channel_elem_type(Node *c, Node *chanexpr)
{
    Node *m;
    Type *lt;
    TypedMember tm;

    if(chanexpr == nil)
        return nil;
    if(chanexpr->type == NIdent && chanexpr->name != nil){
        m = member_node(c, chanexpr->name, 0);
        if(m != nil && m->type == NStream && m->typename != nil &&
           strcmp(m->typename, "chan") != 0)
            return m->typeinfo;
    }
    if(chanexpr->type == NPropRead && chanexpr->left != nil){
        lt = chanexpr->left->typeinfo;
        if(typed_member_lookup(lt, chanexpr->name, 0, &tm) && tm.node != nil &&
           tm.node->type == NStream && tm.node->typename != nil &&
           strcmp(tm.node->typename, "chan") != 0)
            return tm.node->typeinfo;
    }
    return nil;
}

static Node*
channel_endpoint_member(Node *c, Node *chanexpr, int *public_endpoint)
{
    Type *lt;
    TypedMember tm;

    if(public_endpoint != nil)
        *public_endpoint = 0;
    if(chanexpr == nil)
        return nil;

    /* Bare field use inside the declaring object is the owner endpoint.
     * Direction protects the public endpoint reached through obj.field;
     * the owner still needs full access to feed recv-only events and
     * drain send-only commands. */
    if(chanexpr->type == NIdent && chanexpr->name != nil)
        return member_node(c, chanexpr->name, 0);

    if(chanexpr->type == NPropRead && chanexpr->left != nil){
        lt = chanexpr->left->typeinfo;
        if(typed_member_lookup(lt, chanexpr->name, 0, &tm) &&
           tm.node != nil && tm.node->type == NStream){
            if(public_endpoint != nil)
                *public_endpoint = 1;
            return tm.node;
        }
    }
    return nil;
}

static char*
channel_endpoint_name(Node *chanexpr)
{
    if(chanexpr == nil)
        return "?";
    if(chanexpr->name != nil)
        return chanexpr->name;
    if(chanexpr->type == NPropRead && chanexpr->name != nil)
        return chanexpr->name;
    return "?";
}

static void
check_channel_direction(Node *scope_class, Node *chanexpr, int recvop, int *errs)
{
    Node *m;
    int pub;

    m = channel_endpoint_member(scope_class, chanexpr, &pub);
    if(m == nil || m->type != NStream || !pub)
        return;
    if(!recvop && (m->flags & NFChanRecvOnly)){
        fprint(2, "o9c: error: line %d: cannot send to recv-only channel '%s'\n",
            sem_line, channel_endpoint_name(chanexpr));
        (*errs)++;
    }
    if(recvop && (m->flags & NFChanSendOnly)){
        fprint(2, "o9c: error: line %d: cannot receive from send-only channel '%s'\n",
            sem_line, channel_endpoint_name(chanexpr));
        (*errs)++;
    }
}

static Type*
channel_box_type(Node *c, Node *chanexpr, Node *fallback)
{
    Type *et;

    et = channel_elem_type(c, chanexpr);
    if(et != nil)
        return et;
    if(fallback != nil && fallback->typeinfo != nil)
        return fallback->typeinfo;
    if(fallback != nil && fallback->type == NIdent && fallback->name != nil)
        return get_typeinfo_sym(fallback->name);
    return nil;
}

static int
type_is_struct_value(Type *t)
{
    Node *d;

    d = type_decl_node(t);
    return d != nil && d->type == NStruct;
}

static int
type_is_slice_value(Type *t)
{
    return type_is_array(t) || type_is_collection(t, "List");
}

static int
channel_value_needs_memmove(Type *t)
{
    return type_is_class_ref(t) || type_is_struct_value(t) ||
        type_is_slice_value(t);
}

static void
gen_channel_value_temp(Node *expr, Type *value_type, char *storage, char *tmp)
{
    if(channel_value_needs_memmove(value_type)){
        print("%s %s; memmove(&%s, &", storage, tmp, tmp);
        gen_expr(expr);
        print(", sizeof(%s));", storage);
        return;
    }
    print("%s %s = (%s)", storage, tmp, storage);
    gen_expr(expr);
    print(";");
}

static void
gen_channel_pack_call(Type *value_type, char *tmp)
{
    if(type_is_string(value_type))
        print("o9_chan_pack_string(%s)", tmp);
    else if(type_is_slice_value(value_type))
        print("o9_chan_pack_slice(&%s)", tmp);
    else
        print("o9_chan_pack(&%s, sizeof(%s))", tmp, tmp);
}

static void
gen_channel_recv_assign(Node *target, char *boxname, char *storage, Type *boxtype)
{
    if(type_is_string(boxtype)){
        print("o9_string_release(");
        gen_expr(target);
        print("); ");
    } else if(type_is_slice_value(boxtype)){
        print("o9_slice_free(&");
        gen_expr(target);
        print("); ");
    }
    print("o9_chan_take(%s, &", boxname);
    gen_expr(target);
    print(", sizeof(%s));", storage);
}

static int
type_needs_reply_copy(Type *t)
{
    return type_is_class_ref(t) || type_is_struct_value(t) ||
        type_is_slice_value(t);
}

static int
tuple_field_is_object_handle(Node *e)
{
    if(e == nil)
        return 0;
    if(e->type == NTry)
        e = e->left;
    return e != nil && type_is_class_ref(e->typeinfo);
}

static Node*
try_value_expr(Node *e)
{
    if(e != nil && e->type == NTry)
        return e->left;
    return e;
}

static void
gen_msgsend_pack_arg(Node *a)
{
    if(type_is_class_ref(a->typeinfo)){
        print("(vlong)(uintptr)&(");
        gen_expr(a);
        print(")");
        return;
    }
    if(type_is_double(a->typeinfo)){
        print("o9_double_pack(");
        gen_expr(a);
        print(")");
        return;
    }
    if(type_storage_pointerish(a->typeinfo)){
        print("(vlong)(uintptr)(");
        gen_expr(a);
        print(")");
        return;
    }
    print("(vlong)(");
    gen_expr(a);
    print(")");
}

static char*
gen_msgsend_arg_array(Node *args, int id, int nargs, char *argbuf, int argbufsz)
{
    Node *a;
    int i;

    if(nargs <= 0)
        return "nil";
    snprint(argbuf, argbufsz, "__o9args%d", id);
    print("\t\tvlong __o9args%d[%d];\n", id, nargs);
    for(a = args, i = 0; a != nil; a = a->next, i++){
        print("\t\t__o9args%d[%d] = ", id, i);
        gen_msgsend_pack_arg(a);
        print(";\n");
    }
    return argbuf;
}

static void
gen_msgsend_object_call(Node *call, char *dest, char *argexpr, int nargs)
{
    print("\t\tobj9_msgSendObjectN(&");
    gen_expr(call->left);
    if(call->left != nil && call->left->type == NIdent)
        print(", \"%s/%s\", 0x%lux, %s, %d, &%s, sizeof(%s));\n",
            call->left->name, call->name, o9_hash(call->name),
            argexpr, nargs, dest, dest);
    else
        print(", \"%s\", 0x%lux, %s, %d, &%s, sizeof(%s));\n",
            call->name, o9_hash(call->name), argexpr, nargs, dest, dest);
}

static void
gen_msgsend_object_to(Node *call, char *dest)
{
    int id, nargs;
    char argbuf[64], *argexpr;

    if(call == nil || call->type != NMsgSend || dest == nil)
        return;
    id = new_tmp_id++;
    nargs = msg_arg_count(call->right);
    print("\t{\n");
    argexpr = gen_msgsend_arg_array(call->right, id, nargs, argbuf, sizeof argbuf);
    gen_msgsend_object_call(call, dest, argexpr, nargs);
    print("\t}\n");
}

static int
gen_reply_value_to(Node *expr, Type *type, char *dest)
{
    Node *e;

    if(expr == nil || type == nil || dest == nil)
        return 0;
    e = try_value_expr(expr);
    if(type_is_class_ref(type) && e != nil && e->type == NMsgSend){
        gen_msgsend_object_to(e, dest);
        return 1;
    }
    if(type_is_class_ref(type) && e != nil && e->type == NSelfCall){
        print("\t%s = ", dest);
        gen_expr(e);
        print(";\n");
        print("\t((o9_Object*)&%s)->table = nil;\n", dest);
        return 1;
    }
    print("\tmemmove(&%s, &", dest);
    gen_expr(e);
    print(", sizeof(%s));\n", dest);
    if(type_is_class_ref(type))
        print("\t((o9_Object*)&%s)->table = nil;\n", dest);
    return 1;
}

static void
gen_alt_stmt(Node *c, Node *s)
{
    Node *a, *n;
    int id, idx, rx;

    id = alt_tmp_id++;
    print("\t{\n");
    rx = 0;
    for(a = s->left; a != nil; a = a->next)
        if(a->type == NAltCase)
            print("\t\tvoid *__o9altbox_%d_%d = nil;\n", id, rx++);
    print("\t\tAlt __o9alt_%d[] = {\n", id);
    rx = 0;
    for(a = s->left; a != nil; a = a->next){
        if(a->type == NAltCase){
            print("\t\t\t{");
            gen_expr(a->left->right);
            print(", &__o9altbox_%d_%d, CHANRCV},\n", id, rx++);
        } else if(a->type == NAltDefault)
            print("\t\t\t{nil, nil, CHANNOBLK},\n");
    }
    print("\t\t\t{nil, nil, CHANEND}\n");
    print("\t\t};\n");
    print("\t\tswitch(alt(__o9alt_%d)){\n", id);
    idx = 0;
    rx = 0;
    for(a = s->left; a != nil; a = a->next){
        print("\t\tcase %d: {\n", idx++);
        if(a->type == NAltCase){
            Type *bt = channel_box_type(c, a->left->right, a->left->left);
            char *t = bt != nil ? type_storage_for_codegen(bt) : "vlong";
            print("\t\t\tif(__o9altbox_%d_%d != nil){ O9ChanMsg *__o9v = (O9ChanMsg*)__o9altbox_%d_%d; ",
                id, rx, id, rx);
            gen_channel_recv_assign(a->left->left, "__o9v", t, bt);
            print(" o9_chan_free(__o9v); }\n");
            rx++;
            for(n = a->right; n != nil; n = n->next)
                gen_stmt(c, n);
            print("\t\t\tbreak;\n\t\t}\n");
        } else if(a->type == NAltDefault){
            for(n = a->left; n != nil; n = n->next)
                gen_stmt(c, n);
            print("\t\t\tbreak;\n\t\t}\n");
        }
    }
    print("\t\t}\n");
    print("\t}\n");
}

static void
gen_fail_stmt(Node *s)
{
    if(in_method_body){
        has_return = 1;
        print("\t__o9r->err = ");
        if(s->right != nil){
            print("o9_string_data(");
            gen_expr(s->right);
            print(")");
        } else
            print("\"failed\"");
        print(";\n\tgoto done;\n");
    } else {
        print("\tfprint(2, \"fail: %%s\\n\", ");
        if(s->right != nil){
            print("o9_string_data(");
            gen_expr(s->right);
            print(")");
        } else print("\"failed\"");
        print(");\n");
    }
}

static void
gen_super_stmt(Node *s)
{
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
    print("\t{ ");
    if(na > 0){
        int ai2 = 0;
        print("vlong __superargs[%d]; ", na);
        for(ca = s->right; ca != nil; ca = ca->next){
            print("__superargs[%d] = ", ai2);
            if(type_is_double(ca->typeinfo)){
                print("o9_double_pack("); gen_expr(ca); print(")");
            } else if(type_storage_pointerish(ca->typeinfo)){
                print("(vlong)(uintptr)("); gen_expr(ca); print(")");
            } else {
                print("(vlong)("); gen_expr(ca); print(")");
            }
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
    print("{ O9Reply *__sr = recvp(__superm.replyc); o9_reply_free(__sr); } chanfree(__superm.replyc); }\n");
}

static void
gen_delete_stmt(Node *s)
{
    print("\to9_registry_unregister(\"%s\");\n", s->name);
    print("\t(void)obj9_msgSendN(&%s, nil, 0x%lux, nil, 0);\n", s->name, o9_hash("destroy"));
    print("\tmemset(&%s, 0, sizeof %s);\n", s->name, s->name);
    print("\t%s.fd = -1;\n", s->name);
}

static void
gen_channel_send_stmt(Node *c, Node *s, int nonblock)
{
    Type *bt = channel_box_type(c, s->left, s->right);
    char *t = bt != nil ? type_storage_for_codegen(bt) : "vlong";

    print("\t{ ");
    gen_channel_value_temp(s->right, bt, t, "__o9v");
    print(" O9ChanMsg *__box = ");
    gen_channel_pack_call(bt, "__o9v");
    if(nonblock){
        print("; Alt __a[] = {{");
        gen_expr(s->left);
        print(", __box, CHANSND}, {nil, nil, CHANNOBLK}, {nil, nil, CHANEND}}; if(alt(__a) == 1) o9_chan_free(__box); }\n");
    } else {
        print("; sendp(");
        gen_expr(s->left);
        print(", __box); }\n");
    }
}

static void
gen_channel_recv_stmt(Node *c, Node *s)
{
    Type *bt = channel_box_type(c, s->right, s->left);
    char *t = bt != nil ? type_storage_for_codegen(bt) : "vlong";

    print("\t{ O9ChanMsg *__box = recvp("); gen_expr(s->right); print("); if(__box){ ");
    gen_channel_recv_assign(s->left, "__box", t, bt);
    print(" o9_chan_free(__box); } }\n");
}

static void
gen_return_stmt(Node *s)
{
    if(in_method_body){
        has_return = 1;
        if(type_is_double(gen_return_type)){
            if(is_try(s->left)){
                print("\t{ double __rv = "); gen_expr(s->left); print(";\n");
                print("\t{ char *__ce = o9_get_call_err(); if(__ce != nil){ __o9r->err = __ce; goto done; } }\n");
                print("\t__o9r->dret = __rv; }\n\tgoto done;\n");
            } else {
                print("\t__o9r->dret = (double)("); gen_expr(s->left); print(");\n\tgoto done;\n");
            }
        } else if(type_needs_reply_copy(gen_return_type)){
            char *st = type_storage_for_codegen(gen_return_type);
            int id = new_tmp_id++;
            char dest[64];
            snprint(dest, sizeof dest, "__rv%d", id);
            print("\t{ %s __rv%d;\n", st, id);
            print("\tmemset(&__rv%d, 0, sizeof(__rv%d));\n", id, id);
            gen_reply_value_to(s->left, gen_return_type, dest);
            if(is_try(s->left))
                print("\t{ char *__ce = o9_get_call_err(); if(__ce != nil){ __o9r->err = __ce; goto done; } }\n");
            print("\t__o9r->retbuf = malloc(sizeof(__rv%d));\n", id);
            print("\tif(__o9r->retbuf == nil){ __o9r->err = \"out of memory\"; goto done; }\n");
            print("\tmemmove(__o9r->retbuf, &__rv%d, sizeof(__rv%d));\n", id, id);
            print("\t__o9r->retsz = sizeof(__rv%d); }\n\tgoto done;\n", id);
        } else if(is_try(s->left)){
            print("\t{ vlong __rv = (vlong)("); gen_expr(s->left); print(");\n");
            print("\t{ char *__ce = o9_get_call_err(); if(__ce != nil){ __o9r->err = __ce; goto done; } }\n");
            print("\t__o9r->ret = (uintptr)__rv; }\n\tgoto done;\n");
        } else {
            print("\t__o9r->ret = (uintptr)("); gen_expr(s->left); print(");\n\tgoto done;\n");
        }
    } else {
        print("\treturn "); gen_expr(s->left); print(";\n");
    }
}

static void
gen_defer_stmt(Node *s)
{
    Node *dn = mk(NDefer, nil, nil, s->left, nil);
    dn->next = defer_list;
    defer_list = dn;
}

static void
gen_if_stmt(Node *c, Node *s)
{
    Node *n;

    print("\tif("); gen_expr(s->left); print("){\n");
    for(n = s->right; n; n = n->next) gen_stmt(c, n);
    print("\t}\n");
}

static void
gen_ifelse_stmt(Node *c, Node *s)
{
    Node *n;

    print("\tif("); gen_expr(s->left); print("){\n");
    for(n = s->right; n; n = n->next) gen_stmt(c, n);
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
}

static void
gen_while_stmt(Node *c, Node *s)
{
    Node *n;

    print("\twhile("); gen_expr(s->left); print("){\n");
    for(n = s->right; n; n = n->next) gen_stmt(c, n);
    print("\t}\n");
}

static void
gen_for_stmt(Node *c, Node *s)
{
    Node *n;

    print("\tfor(");
    gen_for_clause(s->left);
    print("; ");
    if(s->right->left) gen_expr(s->right->left);
    print("; ");
    gen_for_clause(s->right->right);
    print("){\n");
    for(n = s->right->next; n; n = n->next) gen_stmt(c, n);
    print("\t}\n");
}

static int
gen_local_tabula_stmt(Node *s)
{
    Node *namearg;
    int dist;

    if(o9_locality_kind(s->cname) < 0 || !o9_type_is_tabula(s->typeinfo))
        return 0;
    namearg = s->left != nil ? s->left->right : nil;
    print("\tO9Tabula* %s;\n", s->name);
    if(strcmp(s->cname, "listener") == 0){
        print("\t%s = ", s->name);
        gen_expr(s->left);
        print(";\n");
        print("\to9_export_tab(o9_str_cat(");
        gen_expr(namearg);
        print(", o9_string_from_c(\".tab\")), %s);\n", s->name);
        print("\to9_app_listen(");
        gen_expr(s->params);
        print(");\n");
        return 1;
    }
    dist = o9_locality_distance(s->cname);
    print("\t%s = o9_tab_open_remote(", s->name);
    gen_expr(s->params);
    print(", ");
    gen_expr(namearg);
    print(", %d);\n", dist);
    return 1;
}

static void
gen_local_init_direct(Node *s)
{
    if(type_is_array(s->typeinfo)){
        print("\to9_slice_init(&%s, sizeof(%s));\n", s->name,
            type_storage_for_codegen(type_array_elem(s->typeinfo)));
        return;
    }
    if(type_is_collection(s->typeinfo, "List")){
        print("\to9_slice_init(&%s, sizeof(%s));\n", s->name,
            type_storage_for_codegen(type_list_at(s->typeinfo->args, 0)));
        return;
    }
    if(type_is_collection(s->typeinfo, "Dict")){
        gen_dict_init_expr(s->name, s->typeinfo);
        return;
    }
    print("\tmemset(&%s, 0, sizeof(%s));\n", s->name, type_storage_for_codegen(s->typeinfo));
}

static int
gen_local_direct_storage_stmt(Node *s)
{
    if(!type_declares_direct_storage(s->typeinfo) && !type_is_array(s->typeinfo))
        return 0;
    print("\t%s %s;\n", type_storage_for_codegen(s->typeinfo), s->name);
    if(type_is_array(s->typeinfo)){
        gen_local_init_direct(s);
        if(s->left != nil){
            print("\t%s = ", s->name);
            gen_expr(s->left);
            print(";\n");
            if(is_try(s->left))
                gen_try_check();
        }
        return 1;
    }
    if(s->left != nil && !type_is_collection(s->typeinfo, "List") &&
       !type_is_collection(s->typeinfo, "Dict")){
        print("\t%s = ", s->name);
        gen_expr(s->left);
        print(";\n");
        if(is_try(s->left))
            gen_try_check();
        return 1;
    }
    gen_local_init_direct(s);
    return 1;
}

static int
gen_local_lookup_stmt(Node *s, Node *cdecl, char *cname)
{
    if(cdecl == nil || cname == nil || s->left == nil || s->left->type != NSelfCall)
        return 0;
    if(s->left->name == nil || strcmp(s->left->name, "lookup") != 0)
        return 0;
    print("\t%s_Client %s;\n", cname, s->name);
    print("\to9_lookup_client(&%s, ", s->name);
    gen_expr(s->left->right);
    print(", sizeof %s);\n", s->name);
    add_var_class(s->name, cname);
    return 1;
}

static int
gen_local_object_return_stmt(Node *s, Node *cdecl, char *cname, int is_new)
{
    if(cdecl == nil || cname == nil || s->left == nil || is_new)
        return 0;
    if(!type_is_class_ref(s->typeinfo))
        return 0;
    print("\t%s_Client %s;\n", cname, s->name);
    print("\tmemset(&%s, 0, sizeof(%s));\n", s->name, s->name);
    gen_reply_value_to(s->left, s->typeinfo, s->name);
    if(is_try(s->left))
        gen_try_check();
    add_var_class(s->name, cname);
    return 1;
}

static void
gen_local_plain_decl_stmt(Node *s, int is_new)
{
    print("\t%s %s", type_storage_for_codegen(s->typeinfo), s->name);
    if(s->left != nil && !is_new){
        print(" = ");
        gen_expr(s->left);
    }
    print(";\n");
}

static void
gen_local_remote_new_stmt(Node *s, char *cname, int dval, int nctor)
{
    Node *first_arg;
    int rest;
    char args[96];

    first_arg = s->left->right;
    rest = nctor - 1;
    print("\t%s_Client %s;\n", cname, s->name);
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cname);
    print("\t{\n\t\tchar __addr[128]; char *__addrp;\n\t\t__addrp = o9_string_cstr(");
    gen_expr(first_arg);
    print(");\n");
    print("\t\tif(__addrp != nil){ snprint(__addr, sizeof __addr, \"%%s\", __addrp); free(__addrp); o9_connect(&%s, __addr, \"%s\", %d); }\n", s->name, cname, dval);
    print("\t\t%s.distance = %d;\n", s->name, dval);
    if(rest > 0){
        snprint(args, sizeof args, "__args_%s", s->name);
        gen_vlong_arg_array("\t\t", args, first_arg->next, rest);
        print("\t\t(void)obj9_msgSendN(&%s, \"%s\", 0x%lux, %s, %d);\n",
            s->name, cname, o9_hash(cname), args, rest);
    }
    print("\t}\n");
}

static int
gen_local_new_class_stmt(Node *s, char *cname, int is_new)
{
    char *dist;
    int dval, nctor;

    if(!is_new || cname == nil)
        return 0;
    dist = s->left->typename;
    dval = (dist && strcmp(dist, "near") == 0) ? 0 : (dist && strcmp(dist, "far") == 0) ? 1 : -1;
    nctor = node_arg_count(s->left->right);
    if(dval >= 0 && s->left->right && s->left->right->type == NStringLit)
        gen_local_remote_new_stmt(s, cname, dval, nctor);
    else
        gen_local_new(s, cname, dval >= 0 ? dval : -1);
    return 1;
}

static void
gen_local_init_client_stmt(Node *s, char *cname)
{
    print("\t%s_Client %s;\n", cname, s->name);
    print("\to9_AsmTable %s_tbl;\n", s->name);
    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cname);
    print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
    print("\t%s.table = &%s_tbl;\n", s->name, s->name);
    print("\to9_init_client(&%s, \"%s\", 4096);\n", s->name, cname);
}

static void
gen_local_object_stmt(Node *s)
{
    Node *cdecl;
    char *cname;
    int is_new;

    cdecl = type_decl_node(s->typeinfo);
    cname = type_is_class_ref(s->typeinfo) ? type_cname(s->typeinfo) : nil;
    is_new = s->left != nil && s->left->type == NClass && s->left->name != nil;
    if(gen_local_lookup_stmt(s, cdecl, cname))
        return;
    if(gen_local_object_return_stmt(s, cdecl, cname, is_new))
        return;
    if(in_class_context || cname == nil){
        gen_local_plain_decl_stmt(s, is_new);
        return;
    }
    if(gen_local_new_class_stmt(s, cname, is_new))
        return;
    gen_local_init_client_stmt(s, cname);
}

static void
gen_local_var_stmt(Node *s)
{
    if(gen_local_tabula_stmt(s))
        return;
    if(gen_local_direct_storage_stmt(s))
        return;
    gen_local_object_stmt(s);
}

static void
gen_msg_send_stmt(Node *s)
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
        return;
    }
    gen_discard_expr_stmt(s);
}

typedef int (*GenAssignFn)(Node*, Node*);

static int
assign_ident(Node *n)
{
    if(n == nil)
        return 0;
    if(n->type != NIdent)
        return 0;
    return n->name != nil;
}

static int
assign_propread(Node *n)
{
    if(n == nil)
        return 0;
    if(n->type != NPropRead)
        return 0;
    if(n->name == nil)
        return 0;
    return n->left != nil;
}

static int
assign_current_field(Node *n)
{
    if(!assign_ident(n))
        return 0;
    if(!in_method_body)
        return 0;
    if(gen_class == nil)
        return 0;
    if(is_local(n->name))
        return 0;
    return member_exists(gen_class, n->name);
}

static Type*
assign_ident_type(Node *n)
{
    if(!assign_ident(n))
        return nil;
    if(n->typeinfo != nil)
        return n->typeinfo;
    return get_typeinfo_sym(n->name);
}

static int
assign_rhs_object_value(Node *right)
{
    Node *rv;

    rv = try_value_expr(right);
    if(rv == nil)
        return 0;
    if(rv->type == NMsgSend || rv->type == NSelfCall)
        return 1;
    if(rv->type == NIdent || rv->type == NPropRead)
        return 1;
    return 0;
}

static void
assign_value_to_storage(char *prefix, char *name, Type *ft, Node *right)
{
    Node *d;
    char *t;

    d = type_decl_node(ft);
    if(type_is_char_pointer(ft)){
        print("\t\t\tfree(%s%s);\n", prefix, name);
        print("\t\t\t%s%s = strdup(", prefix, name);
        gen_expr(right);
        print(");\n");
        return;
    }
    if(d != nil && d->type == NStruct){
        print("\t\t\t%s%s = ", prefix, name);
        gen_expr(right);
        print(";\n");
        return;
    }
    if(type_storage_pointerish(ft)){
        t = type_storage_for_codegen(ft);
        print("\t\t\t%s%s = (%s)(uintptr)(", prefix, name, t);
        gen_expr(right);
        print(");\n");
        return;
    }
    print("\t\t\t%s%s = (%s)(", prefix, name, type_cast_for_codegen(ft));
    gen_expr(right);
    print(");\n");
}

static void
assign_field_on_internal(Node *fieldnode, char *state, char *prefix, char *name, Node *right)
{
    Type *ft;
    char field[128];

    ft = decl_typeinfo(fieldnode);
    snprint(field, sizeof field, "%s%s", prefix, name);
    assign_value_to_storage(prefix, name, ft, right);
    gen_state_store_flagged(state, field, name, ft, fieldnode ? fieldnode->flags : 0);
}

static int
gen_assign_tuple(Node *c, Node *s)
{
    Node *a;
    char *st;
    int i;

    (void)c;
    if(s->left == nil || s->left->type != NTupleLit)
        return 0;
    st = type_storage_for_codegen(s->right != nil ? s->right->typeinfo : nil);
    print("\t{ %s __o9tuple = ", st);
    gen_expr(s->right);
    print("; if(__o9tuple != nil){ ");
    for(a = s->left->left, i = 0; a != nil; a = a->next, i++){
        gen_expr(a);
        print(" = __o9tuple->v%d; ", i);
    }
    print("} }\n");
    return 1;
}

static void
gen_slice_set_assign(Node *left, Node *right, Type *et, char *fn)
{
    Type *rt;
    char *st;

    rt = right != nil ? right->typeinfo : nil;
    st = type_storage_for_codegen(et);
    if(type_is_class_ref(et) && type_is_class_ref(rt)){
        print("\t{ %s __v; memmove(&__v, &", st);
        gen_expr(right);
        print(", sizeof(%s)); %s(&", st, fn);
    } else {
        print("\t{ %s __v = ", st);
        gen_expr(right);
        print("; %s(&", fn);
    }
    gen_expr(left->left);
    print(", ");
    gen_expr(left->right);
    print(", &__v); }\n");
}

static int
gen_assign_array(Node *c, Node *s)
{
    Type *lt;

    (void)c;
    if(s->left == nil || s->left->type != NArrayGet)
        return 0;
    lt = s->left->left != nil ? s->left->left->typeinfo : nil;
    if(type_is_collection(lt, "List")){
        gen_slice_set_assign(s->left, s->right, type_list_at(lt->args, 0), "o9_slice_set");
        return 1;
    }
    if(type_is_array(lt)){
        gen_slice_set_assign(s->left, s->right, type_array_elem(lt), "o9_slice_setgrow");
        return 1;
    }
    if(type_is_collection(lt, "Dict")){
        Type *kt, *vt;

        kt = type_list_at(lt->args, 0);
        vt = type_list_at(lt->args, 1);
        print("\t{ %s __o9dk = ", type_storage_for_codegen(kt));
        gen_expr(s->left->right);
        print("; %s __o9dv = ", type_storage_for_codegen(vt));
        gen_expr(s->right);
        print("; o9_dict_setv(&");
        gen_expr(s->left->left);
        print(", &__o9dk, &__o9dv); }\n");
        return 1;
    }
    print("\to9_array_set(&");
    gen_expr(s->left->left);
    print(", ");
    gen_expr(s->left->right);
    print(", ");
    gen_expr(s->right);
    print(");\n");
    return 1;
}

static int
gen_assign_object_result(Node *c, Node *s)
{
    Type *ltinfo;
    char dest[128];

    (void)c;
    if(!assign_ident(s->left))
        return 0;
    if(s->right == nil || s->right->type == NClass)
        return 0;
    ltinfo = assign_ident_type(s->left);
    if((ltinfo == nil || !type_is_class_ref(ltinfo)) && assign_current_field(s->left))
        ltinfo = decl_typeinfo(member_node(gen_class, s->left->name, 0));
    if(ltinfo == nil || !type_is_class_ref(ltinfo))
        return 0;
    if(!assign_rhs_object_value(s->right))
        return 0;
    if(assign_current_field(s->left))
        snprint(dest, sizeof dest, "self->%s", s->left->name);
    else
        snprint(dest, sizeof dest, "%s", s->left->name);
    gen_reply_value_to(s->right, ltinfo, dest);
    if(is_try(s->right))
        gen_try_check();
    return 1;
}

static int
gen_assign_new_class(Node *c, Node *s)
{
    Type *ltinfo;
    char *lt;
    char tgt[128];

    (void)c;
    if(!assign_ident(s->left))
        return 0;
    if(s->right == nil || s->right->type != NClass || s->right->name == nil)
        return 0;
    ltinfo = assign_ident_type(s->left);
    lt = ltinfo != nil ? type_cname(ltinfo) : nil;
    if(ltinfo == nil || !type_is_class_ref(ltinfo) || !is_subclass(s->right->name, lt))
        return 0;
    if(assign_current_field(s->left)){
        snprint(tgt, sizeof tgt, "self->%s", s->left->name);
        gen_assign_new_to(s->left->name, tgt, 1, lt, s->right);
        return 1;
    }
    gen_assign_new(s->left->name, lt, s->right);
    return 1;
}

static int
gen_assign_subclass_copy(Node *c, Node *s)
{
    Type *ltinfo, *rtinfo;
    char *lt, *rt;

    (void)c;
    if(!assign_ident(s->left) || !assign_ident(s->right))
        return 0;
    ltinfo = assign_ident_type(s->left);
    rtinfo = assign_ident_type(s->right);
    lt = ltinfo != nil ? type_cname(ltinfo) : nil;
    rt = rtinfo != nil ? type_cname(rtinfo) : nil;
    if(ltinfo == nil || rtinfo == nil)
        return 0;
    if(!type_is_class_ref(ltinfo) || !type_is_class_ref(rtinfo))
        return 0;
    if(!is_subclass(rt, lt))
        return 0;
    print("\tmemmove(&%s, &%s, sizeof(%s_Client));\n", s->left->name, s->right->name, lt);
    return 1;
}

static int
gen_assign_propread(Node *c, Node *s)
{
    Type *ownertype;
    char *owner;
    Node *cnode, *fieldnode;

    (void)c;
    if(!assign_propread(s->left))
        return 0;
    ownertype = s->left->left->typeinfo;
    owner = ownertype != nil ? type_cname(ownertype) : nil;
    cnode = type_decl_node(ownertype);
    if(cnode == nil)
        return 0;
    if(cnode->type == NStruct){
        print("\t");
        gen_expr(s->left->left);
        print(".%s = ", s->left->name);
        gen_expr(s->right);
        print(";\n");
        return 1;
    }
    if(cnode->type != NClass && cnode->type != NInterface)
        return 0;
    print("\t{ %s_Client *__c = (%s_Client*)&", owner, owner);
    gen_expr(s->left->left);
    print(";\n\t\tif(__c->shm_base){ %s_Internal *__i = (%s_Internal*)__c->shm_base;\n", owner, owner);
    fieldnode = member_node(cnode, s->left->name, 0);
    assign_field_on_internal(fieldnode, "__i->state", "__i->", s->left->name, s->right);
    print("\t\t} }\n");
    return 1;
}

static int
gen_assign_named_field(Node *c, Node *s)
{
    char *cname;
    Node *cnode, *fieldnode;

    (void)c;
    if(s->name == nil || !assign_ident(s->left))
        return 0;
    cname = get_var_class(s->left->name);
    cnode = find_class(cname);
    if(cnode == nil)
        return 0;
    if(cnode->type == NStruct){
        gen_expr(s->left);
        print(".%s = ", s->name);
        gen_expr(s->right);
        print(";\n");
        return 1;
    }
    if(cnode->type != NClass && cnode->type != NInterface)
        return 0;
    print("\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
    gen_expr(s->left);
    print(";\n\t\tif(__c->shm_base){ %s_Internal *__i = (%s_Internal*)__c->shm_base;\n", cname, cname);
    fieldnode = member_node(cnode, s->name, 0);
    assign_field_on_internal(fieldnode, "__i->state", "__i->", s->name, s->right);
    print("\t\t} }\n");
    return 1;
}

static int
gen_assign_self_field(Node *c, Node *s)
{
    int mt;
    Node *fieldnode;

    if(!in_class_context || c == nil || !assign_ident(s->left))
        return 0;
    if(is_local(s->left->name))
        return 0;
    mt = member_exists(c, s->left->name);
    if(mt != NProp && mt != NState)
        return 0;
    fieldnode = member_node(c, s->left->name, 0);
    assign_field_on_internal(fieldnode, "self->state", "self->", s->left->name, s->right);
    return 1;
}

static void
gen_assign_default(Node *c, Node *s)
{
    (void)c;
    print("\t");
    gen_expr(s->left);
    if(s->left != nil && type_storage_pointerish(s->left->typeinfo)){
        print(" = (%s)(uintptr)(", type_storage_for_codegen(s->left->typeinfo));
        gen_expr(s->right);
        print(");\n");
        return;
    }
    print(" = ");
    gen_expr(s->right);
    print(";\n");
}

static GenAssignFn gen_assign_handlers[] = {
    gen_assign_tuple,
    gen_assign_array,
    gen_assign_object_result,
    gen_assign_new_class,
    gen_assign_subclass_copy,
    gen_assign_propread,
    gen_assign_named_field,
    gen_assign_self_field,
    nil,
};

static void
gen_assign_stmt(Node *c, Node *s)
{
    int i;

    for(i = 0; gen_assign_handlers[i] != nil; i++)
        if(gen_assign_handlers[i](c, s))
            return;
    gen_assign_default(c, s);
}

typedef void (*GenStmtFn)(Node*, Node*);
typedef struct GenStmtCase GenStmtCase;
struct GenStmtCase {
    int kind;
    GenStmtFn fn;
};

static void
gen_stmt_rawc(Node *c, Node *s)
{
    (void)c;
    print("\t/* raw C begin */\n");
    print("%s", s->name != nil ? s->name : "");
    print("\n\t/* raw C end */\n");
}

static void
gen_stmt_noop(Node *c, Node *s)
{
    (void)c;
    (void)s;
}

static void
gen_stmt_localvar(Node *c, Node *s)
{
    (void)c;
    gen_local_var_stmt(s);
}

static void
gen_stmt_msgsend(Node *c, Node *s)
{
    (void)c;
    gen_msg_send_stmt(s);
}

static void
gen_stmt_delete(Node *c, Node *s)
{
    (void)c;
    /* Run the destructor synchronously (actor replies after teardown, then
     * exits). Unregister first so new lookups cannot acquire a handle while
     * the actor is draining its destroy. */
    gen_delete_stmt(s);
}

static void
gen_stmt_chansend(Node *c, Node *s)
{
    gen_channel_send_stmt(c, s, 0);
}

static void
gen_stmt_chantry(Node *c, Node *s)
{
    gen_channel_send_stmt(c, s, 1);
}

static void
gen_stmt_chanrecv(Node *c, Node *s)
{
    gen_channel_recv_stmt(c, s);
}

static void
gen_stmt_assign(Node *c, Node *s)
{
    gen_assign_stmt(c, s);
}

static void
gen_stmt_return(Node *c, Node *s)
{
    (void)c;
    gen_return_stmt(s);
}

static void
gen_stmt_defer(Node *c, Node *s)
{
    (void)c;
    /* Collect the deferred call; it is emitted at the method's done: label
     * so it runs on every exit path (LIFO: prepend). */
    gen_defer_stmt(s);
}

static void
gen_stmt_if(Node *c, Node *s)
{
    gen_if_stmt(c, s);
}

static void
gen_stmt_ifelse(Node *c, Node *s)
{
    gen_ifelse_stmt(c, s);
}

static void
gen_stmt_while(Node *c, Node *s)
{
    gen_while_stmt(c, s);
}

static void
gen_stmt_for(Node *c, Node *s)
{
    gen_for_stmt(c, s);
}

static void
gen_stmt_alt(Node *c, Node *s)
{
    gen_alt_stmt(c, s);
}

static GenStmtCase gen_stmt_cases[] = {
    { NRawC, gen_stmt_rawc },
    { NUse, gen_stmt_noop },
    { NLocalVar, gen_stmt_localvar },
    { NMsgSend, gen_stmt_msgsend },
    { NDelete, gen_stmt_delete },
    { NChanSend, gen_stmt_chansend },
    { NChanTry, gen_stmt_chantry },
    { NChanRecv, gen_stmt_chanrecv },
    { NAlt, gen_stmt_alt },
    { NAssign, gen_stmt_assign },
    { NReturn, gen_stmt_return },
    { NDefer, gen_stmt_defer },
    { NIf, gen_stmt_if },
    { NIfElse, gen_stmt_ifelse },
    { NElseIf, gen_stmt_noop },
    { NWhile, gen_stmt_while },
    { NFor, gen_stmt_for },
    { -1, nil },
};

static int
gen_self_command_stmt(Node *s)
{
    if(s->type != NSelfCall || s->name == nil)
        return 0;
    /* fail("msg"): set the method's error and jump to the exit. Reuses the
     * same done: mechanism as return: errors are values, no unwinding. */
    if(strcmp(s->name, "fail") == 0){
        gen_fail_stmt(s);
        return 1;
    }
    /* super(args): explicit parent-constructor chaining. Calls the nearest
     * ancestor's constructor impl on THIS self, so every level initializes
     * its own fields. */
    if(strcmp(s->name, "super") == 0){
        gen_super_stmt(s);
        return 1;
    }
    return 0;
}

static void
gen_default_stmt(Node *s)
{
    gen_discard_expr_stmt(s);
    if(is_try(s))
        gen_try_check();	/* bare `try f();` */
}

void
gen_stmt(Node *c, Node *s)
{
    int i;

    if(s == nil)
        return;
    msg_frame_reset();
    if(gen_self_command_stmt(s))
        return;
    for(i = 0; gen_stmt_cases[i].kind >= 0; i++)
        if(gen_stmt_cases[i].kind == s->type){
            gen_stmt_cases[i].fn(c, s);
            return;
        }
    gen_default_stmt(s);
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

static char *emitted_tuple_types[256];
static int nemitted_tuple_types;

static int
tuple_type_emitted(char *name)
{
    int i;

    for(i = 0; i < nemitted_tuple_types; i++)
        if(strcmp(emitted_tuple_types[i], name) == 0)
            return 1;
    return 0;
}

static void emit_tuple_type(Type *t);

static void
emit_tuple_arg_types(TypeList *args)
{
    for(; args != nil; args = args->next)
        emit_tuple_type(args->type);
}

static void
emit_tuple_type(Type *t)
{
    TypeList *a;
    char *cn;
    int i;

    if(t == nil)
        return;
    if(t->kind == TyApply)
        emit_tuple_arg_types(t->args);
    else if(t->kind == TyArray || t->kind == TyPtr)
        emit_tuple_type(t->base);
    if(!type_is_tuple(t))
        return;
    cn = type_cname(t);
    if(tuple_type_emitted(cn))
        return;
    if(nemitted_tuple_types < nelem(emitted_tuple_types))
        emitted_tuple_types[nemitted_tuple_types++] = cn;
    print("typedef struct %s %s;\n", cn, cn);
    print("struct %s {\n", cn);
    for(a = t->args, i = 0; a != nil; a = a->next, i++)
        print("\t%s v%d;\n", type_storage_for_codegen(a->type), i);
    print("};\n\n");
    print("static %s* o9_tuple_new_%s(", cn, cn);
    for(a = t->args, i = 0; a != nil; a = a->next, i++){
        if(i > 0)
            print(", ");
        print("%s a%d", type_storage_for_codegen(a->type), i);
    }
    print("){\n");
    print("\t%s *t = mallocz(sizeof(*t), 1);\n", cn);
    for(a = t->args, i = 0; a != nil; a = a->next, i++)
        print("\tt->v%d = a%d;\n", i, i);
    print("\treturn t;\n");
    print("}\n\n");
}

static void
emit_tuple_types_node(Node *n)
{
    for(; n != nil; n = n->next){
        emit_tuple_type(n->typeinfo);
        emit_tuple_types_node(n->params);
        emit_tuple_types_node(n->left);
        emit_tuple_types_node(n->right);
    }
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

    if(stateexpr == nil || fieldexpr == nil || name == nil || type == nil)
        return;
    if(type_is_dict(type)){
        print("\t{ char *__o9s = o9_dict_serialize(&%s); o9_state_set(%s, \"%s\", __o9s); free(__o9s); }\n",
            fieldexpr, stateexpr, name);
    } else if(type_is_list(type) || type_is_array(type)){
        /* Complex in-memory values stay in the hot struct for now. */
    } else if(type_is_char_pointer(type)){
        print("\to9_state_set(%s, \"%s\", %s ? %s : \"\");\n",
            stateexpr, name, fieldexpr, fieldexpr);
    } else if(type_is_string(type)){
        print("\to9_state_set(%s, \"%s\", o9_string_data(%s));\n",
            stateexpr, name, fieldexpr);
    } else if(type_is_double(type)){
        print("\t{ char __o9dbuf[64]; snprint(__o9dbuf, sizeof __o9dbuf, \"%%g\", %s); o9_state_set(%s, \"%s\", __o9dbuf); }\n",
            fieldexpr, stateexpr, name);
    } else if((d = type_decl_node(type)) != nil && (d->type == NStruct || d->type == NClass || d->type == NInterface)){
        /* Complex in-memory values stay in the hot struct for now. */
    } else {
        print("\to9_state_set_int(%s, \"%s\", (vlong)(%s));\n",
            stateexpr, name, fieldexpr);
    }
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
            if(type_is_collection(m->typeinfo, "List"))
                print("\to9_slice_init(&%s->%s, sizeof(%s));\n", ptr, m->name,
                    type_storage_for_codegen(type_list_at(m->typeinfo->args, 0)));
            else if(type_is_collection(m->typeinfo, "Dict")){
                char field[256];
                snprint(field, sizeof field, "%s->%s", ptr, m->name);
                gen_dict_init_expr(field, m->typeinfo);
            }
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
            print("\tif(((%s_Internal*)self)->%s != nil){ O9ChanMsg *__box; while((__box = nbrecvp(((%s_Internal*)self)->%s)) != nil) o9_chan_free(__box); chanfree(((%s_Internal*)self)->%s); }\n",
                childname, m->name, childname, m->name, childname, m->name);
        }
        if(m->type == NProp || m->type == NState) {
            if(type_is_string(m->typeinfo)) {
                print("\to9_string_release(((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(type_is_char_pointer(m->typeinfo)) {
                print("\tfree(((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(type_is_dict(m->typeinfo)) {
                print("\to9_dict_free(&((%s_Internal*)self)->%s);\n", childname, m->name);
            } else if(type_is_list(m->typeinfo) || type_is_array(m->typeinfo)) {
                print("\to9_slice_free(&((%s_Internal*)self)->%s);\n", childname, m->name);
            }
        }
    }
}

static void
gen_class_state_layout(Node *c)
{
    int nstatecols;

    print("/* Implementation for class %s (Tiered CSP/9P Model) */\n", c->name);
    nstatecols = count_state_cols(c);
    print("static char *o9_state_cols_%s[] = { ", c->name);
    if(nstatecols > 0)
        gen_state_col_names(c);
    else
        print("nil ");
    print("};\n\n");
    print("typedef struct %s_Internal %s_Internal;\n", c->name, c->name);
    print("struct %s_Internal {\n\tArcLedger ledger;\n\tlong ref;\t/* ARC reference count */\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n\tO9State *state;\n\tchar data[4096];\n\tchar error[256];\n\tchar oid[64];\t/* instance name, for reap */\n\tvoid *objdir;\t/* File* of /<Class>/<oid>/, removed on reap */\n", c->name);
    gen_internal_fields(c);
    print("\tChannel *dispatch_chan;\n");
    print("};\n\n");
}

static void
gen_self_call_prototypes(Node *c)
{
    Node *m, *pn;
    char *rst;

    for(m = c->left; m; m = m->next){
        if(m->type != NMethod || !method_has_body(m) || (m->flags & NFSelfCalled) == 0)
            continue;
        rst = type_storage_for_codegen(m->typeinfo);
        print("static %s o9_self_%s_%s(%s_Internal *self",
            type_is_void(m->typeinfo) ? "void" : rst, c->name, m->name, c->name);
        for(pn = m->right; pn; pn = pn->next)
            print(", %s", type_storage_for_codegen(pn->typeinfo));
        print(");\n");
    }
    print("\n");
}

static void
gen_class_cleanup_impl(Node *c, int has_destruct)
{
    print("static void %s_forget_instance(%s_Internal *inst);\n", c->name, c->name);
    print("static void o9_cleanup_%s(%s_Internal *self) {\n", c->name, c->name);
    if(has_destruct)
        print("\to9_destruct_%s(self);\n", c->name);
    print("\t%s_forget_instance(self);\t/* reap: tree dir + registry + list + tombstone */\n", c->name);
    gen_cleanup_props(c, c->name);
    print("\to9_state_close(self->state);\n");
    print("\tchanfree(self->dispatch_chan);\n");
    print("\tfree(self);\n");
    print("}\n\n");
}

static void
gen_class_arc_callbacks(Node *c)
{
    ulong aid;

    aid = o9_hash(c->name);
    print("static void o9_attach_%s(Req *r) {\n", c->name);
    print("\t%s_Internal *self = r->srv->aux;\n", c->name);
    print("\tself->ledger.entries[0x%lux & 63].count++;\n", aid);
    print("#ifdef __GNUC__\n\t__sync_fetch_and_add(&self->ref, 1);\n#else\n\tainc(&self->ref);\n#endif\n");
    print("\trespond(r, nil);\n");
    print("}\n\n");
    print("static void o9_destroyfid_%s(Fid *f) {\n", c->name);
    print("\tUSED(f);\n");
    print("\t%s_Internal *self = f->pool->srv->aux;\n", c->name);
    print("\tself->ledger.entries[0x%lux & 63].count--;\n");
    print("#ifdef __GNUC__\n\tif(__sync_sub_and_fetch(&self->ref, 1) == 0){\n#else\n\tif(adec(&self->ref) == 0){\n#endif\n");
    print("\t\tO9Msg *m = mallocz(sizeof(O9Msg), 1);\n");
    print("\t\tm->sel = 0x%lux;\n", o9_hash("destroy"));
    print("\t\tm->replyc = nil;\n");
    print("\t\tsendp(self->dispatch_chan, m);\n");
    print("\t}\n");
    print("}\n\n");
}

static void
gen_class_dispatch_loop(Node *c)
{
    print("static void %s_loop(void *v) {\n", c->name);
    print("\tUSED(&v);\n");
    print("\t%s_Internal *self = v;\n\tO9Msg *m;\n", c->name);
    print("\to9_actor_enter(self->dispatch_chan, self->oid);\n");
    print("\tfor(;;){\n\t\tm = recvp(self->dispatch_chan);\n\t\tif(m == nil) continue;\n");
    print("\t\tswitch(m->sel){\n");
    num_emitted = 0;
    gen_dispatch_cases(c, c->name);
    print("\t\tcase 0x%lux: o9_cleanup_%s(self); if(m->replyc != nil){ O9Reply *__dr = mallocz(sizeof(O9Reply), 1); __dr->ok = 1; sendp(m->replyc, __dr); } threadexits(nil); break;\n", o9_hash("destroy"), c->name);
    print("\t\tdefault: if(m->replyc != nil){ O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = \"bad selector\"; sendp(m->replyc, r); } break;\n");
    print("\t\t}\n\t}\n}\n\n");
}

static void
gen_class_facade_aliases(Node *c)
{
    print("#define o9_app_root_%s o9app_root\n", c->name);
    print("#define o9_mount_%s o9app_mount\n", c->name);
    print("#define o9_srv_%s o9app_srvname\n", c->name);
    print("static O9ObjectStore *o9_objects_%s;\n", c->name);
    print("typedef struct %s_InstanceEntry %s_InstanceEntry;\n", c->name, c->name);
    print("struct %s_InstanceEntry { char name[64]; %s_Internal *inst; };\n", c->name, c->name);
    print("static %s_InstanceEntry %s_instances[128];\n", c->name, c->name);
    print("static int %s_ninstances;\n\n", c->name);
}

static void
gen_class_instance_lookup(Node *c)
{
    print("static %s_Internal *%s_find_instance(char *name) {\n", c->name, c->name);
    print("\tint i;\n\tif(name == nil || name[0] == '\\0') return nil;\n");
    print("\tfor(i = 0; i < %s_ninstances; i++)\n", c->name);
    print("\t\tif(strcmp(%s_instances[i].name, name) == 0) return %s_instances[i].inst;\n", c->name, c->name);
    print("\treturn nil;\n}\n\n");
}

static void
gen_class_dumpstate(Node *c)
{
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
}

static void
gen_class_listinstances(Node *c)
{
    print("static int %s_listinstances(char *out, int nout){\n", c->name);
    print("\tint i, w = 0, n;\n");
    print("\tif(out == nil || nout <= 0) return 0;\n");
    print("\tfor(i = 0; i < %s_ninstances && w < nout-1; i++){\n", c->name);
    print("\t\tn = snprint(out+w, nout-w, \" %%s\", %s_instances[i].name); w += n;\n", c->name);
    print("\t}\n");
    print("\treturn w;\n}\n\n");
}

static void
gen_class_record_instance(Node *c)
{
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
}

static void
gen_class_forget_instance(Node *c)
{
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
}

static void
gen_class_instance_helpers(Node *c)
{
    gen_class_facade_aliases(c);
    gen_class_instance_lookup(c);
    gen_class_dumpstate(c);
    gen_class_listinstances(c);
    gen_class_record_instance(c);
    gen_class_forget_instance(c);
}

static int
method_param_count(Node *m)
{
    Node *p;
    int n;

    n = 0;
    for(p = m->right; p; p = p->next)
        n++;
    return n;
}

static void
gen_method_scope_locals(Node *m)
{
    Node *p;

    num_locals = 0;
    mark_locals(m->left);
    for(p = m->right; p; p = p->next)
        if(num_locals < 128)
            local_vars[num_locals++] = p->name;
}

static void
gen_method_unpack_param(Node *p, int pi)
{
    char *st;

    st = type_storage_for_codegen(p->typeinfo);
    if(type_is_class_ref(p->typeinfo))
        print("\t%s %s = *(%s*)(uintptr)((vlong*)msg->args)[%d];\n", st, p->name, st, pi);
    else if(type_is_double(p->typeinfo))
        print("\t%s %s = o9_double_unpack(((vlong*)msg->args)[%d]);\n", st, p->name, pi);
    else if(storage_pointerish(st))
        print("\t%s %s = (%s)(uintptr)((vlong*)msg->args)[%d];\n", st, p->name, st, pi);
    else
        print("\t%s %s = ((vlong*)msg->args)[%d];\n", st, p->name, pi);
    print("\tUSED(&%s);\n", p->name);
}

static void
gen_method_unpack_params(Node *m)
{
    Node *p;
    int pi;

    pi = 0;
    for(p = m->right; p; p = p->next)
        gen_method_unpack_param(p, pi++);
}

static void
gen_method_body_emit(Node *c, Node *m)
{
    Node *s, *dn;

    in_method_body = 1;
    gen_class = c;
    gen_return_type = m->typeinfo;
    has_return = 0;
    try_seen = 0;
    defer_list = nil;
    for(s = m->left; s; s = s->next)
        gen_stmt(c, s);
    if(has_return || try_seen || defer_list != nil)
        print("done:\n");
    for(dn = defer_list; dn != nil; dn = dn->next){
        msg_frame_reset();
        gen_discard_expr_stmt(dn->left);
    }
    defer_list = nil;
    in_method_body = 0;
    gen_class = nil;
    gen_return_type = nil;
}

static void
gen_method_impl_artifact(Node *c, Node *m)
{
    gen_method_scope_locals(m);
    print("static void o9_impl_%s_%s(%s_Internal *self, O9Msg *msg) {\n", c->name, m->name, c->name);
    print("\tUSED(self);\n");
    print("\tO9Reply *__o9r = mallocz(sizeof(O9Reply), 1);\n");
    print("\tvlong __o9fr[%d][12];\n\tUSED(__o9fr);\n", O9_MSG_FRAMES);
    gen_method_unpack_params(m);
    gen_method_body_emit(c, m);
    print("\t__o9r->ok = 1;\n\tsendp(msg->replyc, __o9r);\n}\n\n");
}

static void
gen_ctrl_arg_decl(Node *pn, int pi)
{
    char *st;

    st = type_storage_for_codegen(pn->typeinfo);
    if(type_is_class_ref(pn->typeinfo))
        print("\t%s *__arg%d = (%s*)(uintptr)((vlong*)__a)[%d];\n", st, pi, st, pi+1);
    else if(type_is_double(pn->typeinfo))
        print("\t%s __arg%d = o9_double_unpack(((vlong*)__a)[%d]);\n", st, pi, pi+1);
    else if(storage_pointerish(st))
        print("\t%s __arg%d = (%s)(uintptr)((vlong*)__a)[%d];\n", st, pi, st, pi+1);
    else
        print("\t%s __arg%d = ((vlong*)__a)[%d];\n", st, pi, pi+1);
}

static void
gen_ctrl_arg_pack(Node *pn, int pi)
{
    if(type_is_double(pn->typeinfo))
        print("\t__args[%d] = o9_double_pack(__arg%d);\n", pi, pi);
    else if(type_is_class_ref(pn->typeinfo) || type_storage_pointerish(pn->typeinfo))
        print("\t__args[%d] = (vlong)(uintptr)__arg%d;\n", pi, pi);
    else
        print("\t__args[%d] = (vlong)__arg%d;\n", pi, pi);
}

static void
gen_ctrl_args(Node *m, int np)
{
    Node *pn;
    int pi;

    if(np <= 0)
        return;
    for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
        gen_ctrl_arg_decl(pn, pi);
    print("\tvlong __args[%d];\n", np);
    for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
        gen_ctrl_arg_pack(pn, pi);
}

static void
gen_ctrl_reply_store(Node *m)
{
    print("\t{ O9Reply *__r = recvp(__m.replyc);\n");
    print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_set_call_err(__r->err); ((vlong*)__a)[0] = 0; }\n");
    if(type_is_double(m->typeinfo))
        print("\telse { o9_set_call_err(nil); ((vlong*)__a)[0] = o9_double_pack(__r->dret); }\n");
    else
        print("\telse { o9_set_call_err(nil); ((vlong*)__a)[0] = (vlong)(uintptr)__r->ret; }\n");
    print("\to9_reply_free(__r); }\n");
}

static void
gen_method_ctrl_artifact(Node *c, Node *m, int np)
{
    print("static void o9_ctrl_%s_%s(void *__a){\n", c->name, m->name);
    print("\t%s_Internal *self = (%s_Internal*)((vlong*)__a)[0];\n", c->name, c->name);
    print("\tUSED(self);\n");
    gen_ctrl_args(m, np);
    if(np > 0)
        print("\tO9Msg __m = {0x%lux, __args, %d, chancreate(sizeof(void*), 1)};\n", o9_hash(m->name), np);
    else
        print("\tO9Msg __m = {0x%lux, nil, 0, chancreate(sizeof(void*), 1)};\n", o9_hash(m->name));
    print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
    gen_ctrl_reply_store(m);
    print("\tchanfree(__m.replyc);\n}\n\n");
}

static void
gen_self_arg_pack(Node *pn, int pi)
{
    if(type_is_double(pn->typeinfo))
        print("\t__args[%d] = o9_double_pack(__a%d);\n", pi, pi);
    else if(type_is_class_ref(pn->typeinfo))
        print("\t__args[%d] = (vlong)(uintptr)&__a%d;\n", pi, pi);
    else if(type_storage_pointerish(pn->typeinfo))
        print("\t__args[%d] = (vlong)(uintptr)__a%d;\n", pi, pi);
    else
        print("\t__args[%d] = (vlong)__a%d;\n", pi, pi);
}

static void
gen_self_args(Node *m)
{
    Node *pn;
    int pi;

    for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
        gen_self_arg_pack(pn, pi);
}

static void
gen_self_reply_value(Node *m, char *rst)
{
    if(type_needs_reply_copy(m->typeinfo)){
        print("\tmemset(&__v, 0, sizeof(__v));\n");
        print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_set_call_err(__r->err); }\n");
        print("\telse if(__r->retbuf == nil || __r->retsz > sizeof(__v)){ werrstr(\"object method returned no handle data\"); o9_set_call_err(\"object method returned no handle data\"); }\n");
        print("\telse { o9_set_call_err(nil); memmove(&__v, __r->retbuf, __r->retsz);");
        if(type_is_class_ref(m->typeinfo))
            print(" ((o9_Object*)&__v)->table = nil;");
        print(" }\n");
        return;
    }
    print("\tif(__r->err != nil){ werrstr(\"%%s\", __r->err); o9_set_call_err(__r->err); __v = 0; }\n");
    if(type_is_double(m->typeinfo))
        print("\telse { o9_set_call_err(nil); __v = __r->dret; }\n");
    else
        print("\telse { o9_set_call_err(nil); __v = (%s)__r->ret; }\n", rst);
}

static void
gen_method_self_artifact(Node *c, Node *m, int np)
{
    char *rst;
    int isvoid, pi;
    Node *pn;

    if((m->flags & NFSelfCalled) == 0)
        return;
    rst = type_storage_for_codegen(m->typeinfo);
    isvoid = type_is_void(m->typeinfo);
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
    gen_self_args(m);
    print("\t__m.sel = 0x%lux;\n\t__m.args = %s;\n\t__m.nargs = %d;\n",
        o9_hash(m->name), np > 0 ? "__args" : "nil", np);
    print("\t__m.replyc = chancreate(sizeof(void*), 1);\n");
    print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
    print("\t__r = recvp(__m.replyc);\n");
    if(!isvoid)
        gen_self_reply_value(m, rst);
    else
        print("\tif(__r->err != nil) werrstr(\"%%s\", __r->err);\n");
    print("\to9_reply_free(__r);\n\tchanfree(__m.replyc);\n");
    if(!isvoid)
        print("\treturn __v;\n");
    print("}\n\n");
}

static void
gen_method_artifacts(Node *c, Node *m)
{
    int np;

    np = method_param_count(m);
    gen_method_impl_artifact(c, m);
    gen_method_ctrl_artifact(c, m, np);
    gen_method_self_artifact(c, m, np);
}

static void
gen_destructor_artifact(Node *c, Node *m)
{
    Node *s;

    num_locals = 0;
    mark_locals(m->left);
    print("static void o9_destruct_%s(%s_Internal *self) {\n", c->name, c->name);
    print("\tUSED(self);\n");
    print("\tvlong __o9fr[%d][12];\n\tUSED(__o9fr);\n", O9_MSG_FRAMES);
    for(s = m->left; s; s = s->next)
        gen_stmt(c, s);
    print("}\n\n");
}

static int
gen_class_method_artifacts(Node *c)
{
    Node *m;
    int has_destruct;

    has_destruct = 0;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod)
            gen_method_artifacts(c, m);
        if(m->type == NDestructor){
            has_destruct = 1;
            gen_destructor_artifact(c, m);
        }
    }
    return has_destruct;
}

static void
gen_class_spawn_helper(Node *c)
{
    Node *rm, *pn;
    int np, pi;

    if((c->flags & NFFunction) == 0)
        return;
    rm = nil;
    np = 0;
    for(rm = c->left; rm != nil; rm = rm->next)
        if(rm->type == NMethod && rm->name != nil && strcmp(rm->name, "run") == 0)
            break;
    for(pn = (rm ? rm->right : nil); pn; pn = pn->next)
        np++;
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
    print("static int o9_spawn_id_%s;\n", c->name);
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
    print("\tChannel *__replyc = chancreate(sizeof(void*), 1);\n");
    if(np > 0){
        print("\tvlong *__args = malloc(%d*sizeof(vlong));\n", np);
        for(pn = (rm ? rm->right : nil), pi = 0; pn; pn = pn->next, pi++){
            if(type_is_double(pn->typeinfo))
                print("\t__args[%d] = o9_double_pack(__a%d);\n", pi, pi);
            else if(type_is_class_ref(pn->typeinfo) || type_storage_pointerish(pn->typeinfo))
                print("\t__args[%d] = (vlong)(uintptr)__a%d;\n", pi, pi);
            else
                print("\t__args[%d] = (vlong)__a%d;\n", pi, pi);
        }
    }
    print("\t{ O9Msg *__wm = mallocz(sizeof(O9Msg), 1);\n");
    print("\t  __wm->sel = 0x%lux; __wm->args = %s; __wm->nargs = %d; __wm->replyc = __replyc;\n",
        o9_hash("run"), np > 0 ? "__args" : "nil", np);
    print("\t  sendp(__inst->dispatch_chan, __wm); }\n");
    print("\t{ O9SpawnCtx_%s *__ctx = mallocz(sizeof(O9SpawnCtx_%s), 1);\n", c->name, c->name);
    print("\t  __ctx->replyc = __replyc; __ctx->task = __task; __ctx->inst = __inst;\n");
    print("\t  proccreate(o9_spawn_forward_%s, __ctx, 32*1024); }\n", c->name);
    print("\treturn __task;\n}\n");
}

static void
gen_class_register(Node *c)
{
    o9_note_registered(c->name);
    print("void o9_register_class_%s(void) {\n", c->name);
    print("\to9app_register_handler(\"%s\", fsread_%s, fswrite_%s, (void*(*)(char*))%s_find_instance, %s_dumpstate, %s_listinstances);\n", c->name, c->name, c->name, c->name, c->name, c->name);
    print("\to9_objects_%s = o9_object_store_create_path(o9app_root, o9app_name);\n", c->name);
    print("\to9_method_store_init(o9app_root, o9app_name);\n");
    gen_method_registrations(c, c);
    print("}\n");
}

static void
gen_class_fsread_status(Node *c)
{
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
}

static void
gen_class_fsread_method_files(Node *c)
{
    Node *m;

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
            } else if(type_is_double(m->typeinfo)){
                print("\t\tsnprint(buf, sizeof buf, \"%%g\\n\", __o9rep->dret);\n");
            } else if(strcmp(fmt, "%s") == 0){
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", (char*) __o9rep->ret);\n");
            } else if(strcmp(fmt, "%p") == 0){
                print("\t\tsnprint(buf, sizeof buf, \"%%p\\n\", (void*)__o9rep->ret);\n");
            } else {
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
            }
            print("\t\tr->fid->aux = nil;\n");
            print("\t\to9_reply_free(__o9rep);\n");
            print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
        }
    }
}

static void
gen_class_fsread_props(Node *c)
{
    Node *m;

    for(m = c->left; m; m = m->next){
        if(m->type == NProp){
            char *fmt, *cast;
            Node *d;
            /* SECURITY (#7): private fields must not be readable through a
             * per-class prop path. Latent (flat facade doesn't expose
             * these paths now), but defense-in-depth for if they return. */
            if(m->flags & NFPrivate)
                continue;
            fmt = type_fmt_for_codegen(m->typeinfo);
            cast = type_cast_for_codegen(m->typeinfo);
            d = type_decl_node(m->typeinfo);
            if(type_is_string(m->typeinfo)) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", o9_string_data(inst->%s));\n", m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else if(type_is_dict(m->typeinfo)){
                /* Dict property: serialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&inst->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s); respond(r, nil); return;\n\t}\n", m->name);
            } else if(type_is_list(m->typeinfo) || type_is_array(m->typeinfo)){
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<slice>\\n\"); respond(r, nil); return;\n\t}\n");
            } else if(type_is_class_ref(m->typeinfo) || type_storage_pointerish(m->typeinfo)){
                /* object/builtin handle field is live state, not a readable value */
                print("\tif(strcmp(name, \"%s\") == 0){ readstr(r, \"<handle>\\n\"); respond(r, nil); return; }\n", m->name);
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
}

static void
gen_class_fsread(Node *c)
{
    print("static void fsread_%s(Req *r, void *instv) {\n", c->name);
    print("\tchar buf[1024];\n");
    print("\tUSED(buf);\n");
    print("\tchar *name = r->fid->file->name;\n");
    print("\t%s_Internal *inst = instv;\n\n", c->name);
    gen_class_fsread_status(c);
    print("\tif(strcmp(name, \"methods\") == 0) {\n");
    print("\t\tchar mbuf[8192];\n");
    print("\t\to9_method_serialize(\"%s\", mbuf, sizeof mbuf);\n", c->name);
    print("\t\treadstr(r, mbuf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"data\") == 0) { readstr(r, inst != nil ? inst->data : \"\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ctl\") == 0) { readstr(r, \"\"); respond(r, nil); return; }\n");
    print("\tif(inst == nil) { respond(r, \"no instance\"); return; }\n\n");
    gen_class_fsread_method_files(c);
    gen_class_fsread_props(c);
    print("\trespond(r, \"not found\");\n}\n\n");
}

static void
gen_class_ctl_new(Node *c)
{
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
}

static void
gen_class_ctl_method_cases(Node *c)
{
    Node *m;

    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            int np = 0;
            int ctl_supported = 1;
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
            for(p = m->right; p; p = p->next){
                char *pt = p->typename != nil ? p->typename : "vlong";
                np++;
                if(type_is_class_ref(p->typeinfo) || strcmp(pt, "Tabula") == 0)
                    ctl_supported = 0;
            }
            print("\t\t\tif(strcmp(f[2], \"%s\") == 0){\n", m->name);
            /* ARITY (finding #5): a network boundary must not silently
             * default missing args to 0 or ignore extras. Require exactly
             * np args after `method Class.inst name` (tokens f[3..]). */
            print("\t\t\t\tif(nf - 3 != %d){ char __ab[96]; snprint(__ab, sizeof __ab, \"error: %s takes %d arg(s), got %%d\\n\", nf-3); o9app_put_status(r, __ab); o9app_put_result(r, \"\"); respond(r, nil); return; }\n",
                np, m->name, np);
            if(!ctl_supported){
                print("\t\t\t\to9app_put_status(r, \"error: %s: object arguments are not callable over ctl\\n\"); o9app_put_result(r, \"\"); respond(r, nil); return;\n", m->name);
                print("\t\t\t}\n");
                continue;
            }
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
                    if(strcmp(pt, "string") == 0){
                        print("\t\t\t\t__wargs[%d] = (vlong)(uintptr)o9_string_from_c(v);\n", pi);
                    } else if(strcmp(pt, "double") == 0){
                        print("\t\t\t\t__wargs[%d] = o9_double_pack(strtod(v, nil));\n", pi);
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
            /* Roles (docs/SESSIONS.md): success/error -> STATUS, the return
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
                else if(type_is_double(m->typeinfo))
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%%g\\n\", __o9rep->dret);\n");
                else if(strcmp(fmt, "%s") == 0)
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%%s\\n\", (char*)__o9rep->ret);\n");
                else if(strcmp(fmt, "%p") == 0)
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%%p\\n\", (void*)__o9rep->ret);\n");
                else
                    print("\t\t\t\t\tsnprint(__rb, sizeof __rb, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
                print("\t\t\t\t\to9app_put_result(r, __rb); }\n");
            }
            print("\t\t\t\t}\n");
            print("\t\t\t\to9_reply_free(__o9rep); chanfree(__wm.replyc); }\n");
            print("\t\t\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t\t\t}\n");
        }
    }
}

static void
gen_class_ctl_method(Node *c)
{
    print("\t\tif(strcmp(f[0], \"method\") == 0){\n");
    print("\t\t\tif(nf < 3){ if(inst) snprint(inst->error, sizeof inst->error, \"method needs instance and name\"); respond(r, \"bad method\"); return; }\n");
    print("\t\t\ttarget = %s_find_instance(f[1]);\n", c->name);
    print("\t\t\tif(target == nil){ if(inst) snprint(inst->error, sizeof inst->error, \"unknown instance %%s\", f[1]); respond(r, \"unknown instance\"); return; }\n");
    gen_class_ctl_method_cases(c);
    print("\t\t\tif(inst) snprint(inst->error, sizeof inst->error, \"unknown method %%s\", f[2]);\n");
    print("\t\t\trespond(r, \"unknown method\"); return;\n\t\t}\n");
}

static void
gen_class_method_file_writes(Node *c)
{
    Node *m;

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
                else if(m->right != nil && type_is_double(m->right->typeinfo))
                    print("\t\t__wargs[0] = o9_double_pack(strtod(r->ifcall.data, nil));\n");
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
                    print("\t\t{ O9Reply *__o9rep = recvp(__wm.replyc); o9_reply_free(__o9rep); }\n");
                }
                print("\t\tchanfree(__wm.replyc); }\n");
            }
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

static void
gen_class_prop_write(Node *m)
{
    Node *d;

    d = type_decl_node(m->typeinfo);
    if(type_is_string(m->typeinfo)) {
        print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
        print("\t\to9_string_release(inst->%s);\n", m->name);
        print("\t\tinst->%s = o9_string_new(r->ifcall.data, r->ifcall.count);\n", m->name);
        {
            char field[128];
            snprint(field, sizeof field, "inst->%s", m->name);
            gen_state_store_typed("inst->state", field, m->name, m->typeinfo);
        }
        print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
    } else if(type_is_dict(m->typeinfo)) {
        /* Dict property: deserialize */
        print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
        print("\t\to9_dict_deserialize(&inst->%s, r->ifcall.data);\n", m->name);
        {
            char field[128];
            snprint(field, sizeof field, "inst->%s", m->name);
            gen_state_store_typed("inst->state", field, m->name, m->typeinfo);
        }
        print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
    } else if(type_is_list(m->typeinfo) || type_is_array(m->typeinfo)) {
        print("\tif(strcmp(name, \"%s\") == 0){ respond(r, \"slice property not writable\"); return; }\n", m->name);
    } else if(type_is_class_ref(m->typeinfo) || type_storage_pointerish(m->typeinfo)){
        /* object/builtin handle field is not writable via textual 9P */
        print("\tif(strcmp(name, \"%s\") == 0){ respond(r, \"handle property not writable\"); return; }\n", m->name);
    } else if(d != nil && d->type == NStruct) {
        /* skip writing to structs via 9P for now */
    } else {
        print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
        if(type_is_double(m->typeinfo))
            print("\t\tinst->%s = strtod(r->ifcall.data, nil);\n", m->name);
        else if(m->typeinfo != nil && m->typeinfo->kind == TyParam)
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

static void
gen_class_prop_writes(Node *c)
{
    Node *m;

    for(m = c->left; m; m = m->next){
        if(m->type == NProp){
            /* SECURITY (#7): private fields not writable via a per-class
             * prop path. */
            if(m->flags & NFPrivate)
                continue;
            gen_class_prop_write(m);
        }
    }
}

static void
gen_class_fswrite(Node *c)
{
    print("static void fswrite_%s(Req *r, void *instv) {\n", c->name);
    print("\tchar *name = r->fid->file->name;\n");
    print("\t%s_Internal *inst = instv;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) {\n");
    print("\t\tchar cmd[1024], *f[16], *v;\n\t\tint nf;\n\t\t%s_Internal *target;\n", c->name);
    print("\t\tUSED(&v);\n");
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
    gen_class_ctl_new(c);
    gen_class_ctl_method(c);
    print("\t\tif(inst) snprint(inst->error, sizeof inst->error, \"unknown command %%s\", f[0]);\n");
    print("\t\trespond(r, \"unknown command\"); return;\n\t}\n");
    /* Method dispatch: write to method file triggers CSP call */
    gen_class_method_file_writes(c);
    gen_class_prop_writes(c);
    print("\trespond(r, \"read only or not found\");\n}\n\n");
}

void
gen_class_server(Node *c)
{
    gen_class_state_layout(c);
    gen_self_call_prototypes(c);

    int has_destruct = gen_class_method_artifacts(c);

    gen_class_cleanup_impl(c, has_destruct);
    gen_class_arc_callbacks(c);
    gen_class_dispatch_loop(c);
    gen_class_instance_helpers(c);

    /* 4. 9P Fileserver Facade — clone pattern */
    gen_class_fsread(c);
    gen_class_fswrite(c);
    print("int %s_create_instance(%s_Internal *inst, char *name) {\n", c->name, c->name);
    print("\treturn %s_record_instance(name, inst);\n}\n", c->name);

    gen_class_spawn_helper(c);
    gen_class_register(c);
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
            sub = gen_classes(n->left);
            if(sub != nil)
                last = sub;
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
        c->typename = type_render(c->typeinfo);
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

/* ========================================================================
 * APP FACADE GENERATION AND PROGRAM EMISSION
 * ======================================================================== */

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
    /* Per-app facade: ONE Srv with a fixed root shape, built once at
     * startup.  Root control files are stable; clone creates session dirs
     * and exports/ accepts published Tabulae. The served facade does not
     * compose the app from per-object fileservers. ctl names its target
     * instance in the line (method Class.inst method arg...);
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
    print("extern File *o9app_imports_dir;\t/* served-tree imports/ dir */\n");
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
    print("File *o9app_imports_dir;\t/* served-tree imports/ dir (mutable) */\n");
    print("int o9app_debug;\t/* set from O9DEBUG at startup */\n\n");
    /* One published Tabula: its serialized bytes live in the File's aux,
     * served ramfs-style on read.  This is the mutable part of the fs. */
    print("typedef struct O9Export O9Export;\n");
    print("typedef struct O9ImportStage O9ImportStage;\n");
    /* aux tag: both O9Export and O9Session live in File->aux; the first
     * field discriminates them (destroyfid only has the Fid). */
    print("enum { O9AUX_EXPORT = 1, O9AUX_SESSION = 2, O9AUX_IMPORT = 3, O9AUX_IMPORT_STAGE = 4 };\n");
    print("struct O9Export { int tag; QLock lock; char *data; int ndata; };\n\n");
    print("struct O9ImportStage { int tag; O9Export *file; QLock lock; char *data; int ndata; int wrote; int commit; int failed; };\n\n");
    print("static int o9app_export_name_ok(char *s){\n");
    print("\tuchar *p;\n");
    print("\tif(s == nil || s[0] == '\\0' || strcmp(s, \".\") == 0 || strcmp(s, \"..\") == 0) return 0;\n");
    print("\tfor(p = (uchar*)s; *p != '\\0'; p++)\n");
    print("\t\tif(*p < ' ' || *p == 0177 || *p == '/') return 0;\n");
    print("\treturn 1;\n");
    print("}\n\n");
    print("static int o9app_import_name_ok(char *s){\n");
    print("\tint n;\n");
    print("\tif(!o9app_export_name_ok(s)) return 0;\n");
    print("\tn = strlen(s);\n");
    print("\treturn n > 4 && strcmp(s+n-4, \".tab\") == 0;\n");
    print("}\n\n");

    /* exports/ is a served-tree DIRECTORY (part of the application file
     * tree, reachable through the mount) — NOT an on-disk directory.
     * Objects publish Tabulae into it at runtime via createfile; the
     * serialized bytes live in the child File's aux. */
    /* Flat root handlers.  The four files share these; ctl routes by the
     * line's Class.inst to a class handler, the rest aggregate. */
    /* Per-session conversation state (docs/SESSIONS.md). Fixes the per-caller
     * race: results/status live on the SESSION, not a global mailbox. A
     * session is allocated by reading `clone`; its dir + ctl/data/status
     * are createfile'd into the served root, each carrying the O9Session*
     * in File->aux. */
    /* Sessions: a GROW-AND-REUSE POOL (the Plan 9 /net clone model, with
     * List-style growth). Slot dirs <i>/{ctl,data,status} are created once
     * and NEVER removed — clone hands out a closed slot, and explicit
     * `close` marks it reusable. Fid clunks update diagnostic refs only.
     * This dissolves both the leak (slots are bounded by peak open
     * conversations, then recycled) and the reap re-entrancy fault
     * (nothing is ever removefile'd). */
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
    print("static O9ImportStage *o9app_import_stage_new(O9Export *imp, int copy){\n");
    print("\tO9ImportStage *st;\n");
    print("\tst = mallocz(sizeof *st, 1);\n");
    print("\tif(st == nil) return nil;\n");
    print("\tst->tag = O9AUX_IMPORT_STAGE;\n");
    print("\tst->file = imp;\n");
    print("\tif(copy && imp != nil){\n");
    print("\t\tqlock(&imp->lock);\n");
    print("\t\tif(imp->ndata > 0){\n");
    print("\t\t\tst->data = malloc(imp->ndata + 1);\n");
    print("\t\t\tif(st->data == nil){ qunlock(&imp->lock); free(st); return nil; }\n");
    print("\t\t\tmemmove(st->data, imp->data, imp->ndata);\n");
    print("\t\t\tst->data[imp->ndata] = '\\0';\n");
    print("\t\t\tst->ndata = imp->ndata;\n");
    print("\t\t}\n");
    print("\t\tqunlock(&imp->lock);\n");
    print("\t}\n");
    print("\treturn st;\n");
    print("}\n");
    print("static void o9app_import_commit(Fid *f){\n");
    print("\tO9ImportStage *st; O9Export *imp; char *old;\n");
    print("\tif(f == nil || f->aux == nil || *(int*)f->aux != O9AUX_IMPORT_STAGE) return;\n");
    print("\tst = f->aux; f->aux = nil;\n");
    print("\tqlock(&st->lock);\n");
    print("\tif(st->commit && !st->failed && st->file != nil){\n");
    print("\t\timp = st->file;\n");
    print("\t\tqlock(&imp->lock);\n");
    print("\t\told = imp->data;\n");
    print("\t\timp->data = st->data;\n");
    print("\t\timp->ndata = st->ndata;\n");
    print("\t\tst->data = nil;\n");
    print("\t\tif(f->file != nil) f->file->length = imp->ndata;\n");
    print("\t\tqunlock(&imp->lock);\n");
    print("\t\tfree(old);\n");
    print("\t}\n");
    print("\tqunlock(&st->lock);\n");
    print("\tfree(st->data);\n");
    print("\tfree(st);\n");
    print("}\n");
    print("static void o9app_import_write(Req *r){\n");
    print("\tO9ImportStage *st; O9Export *imp; vlong off; long count; int need; char *np;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil || r->fid->file->aux == nil){ respond(r, \"not import\"); return; }\n");
    print("\tif(*(int*)r->fid->file->aux != O9AUX_IMPORT){ respond(r, \"not import\"); return; }\n");
    print("\tif(r->fid->aux == nil || *(int*)r->fid->aux != O9AUX_IMPORT_STAGE){\n");
    print("\t\timp = r->fid->file->aux;\n");
    print("\t\tr->fid->aux = o9app_import_stage_new(imp, 1);\n");
    print("\t\tif(r->fid->aux == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t}\n");
    print("\tst = r->fid->aux;\n");
    print("\toff = r->ifcall.offset; count = r->ifcall.count;\n");
    print("\tqlock(&st->lock);\n");
    print("\tif(off < 0 || count < 0 || off + count > 4*1024*1024){ st->failed = 1; qunlock(&st->lock); respond(r, \"import too large\"); return; }\n");
    print("\tneed = (int)(off + count);\n");
    print("\tif(need + 1 > st->ndata + 1){\n");
    print("\t\tnp = realloc(st->data, need + 1);\n");
    print("\t\tif(np == nil){ st->failed = 1; qunlock(&st->lock); respond(r, \"no memory\"); return; }\n");
    print("\t\tif(off > st->ndata) memset(np + st->ndata, 0, (int)(off - st->ndata));\n");
    print("\t\tst->data = np;\n");
    print("\t}\n");
    print("\tif(count > 0) memmove(st->data + (int)off, r->ifcall.data, count);\n");
    print("\tif(need > st->ndata) st->ndata = need;\n");
    print("\tif(st->data != nil) st->data[st->ndata] = '\\0';\n");
    print("\tst->wrote = 1; st->commit = 1;\n");
    print("\tqunlock(&st->lock);\n");
    print("\tr->ofcall.count = count;\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    /* destroyfid: DIAGNOSTICS ONLY (ref count). Clunking a fid does NOT
     * end the conversation — the client owns it until an explicit close.
     * This is what makes echo>ctl; cat data safe (ctl clunks first). */
    print("static void o9app_destroyfid(Fid *f){\n");
    print("\to9app_import_commit(f);\n");
    print("\tif(f != nil && f->file != nil && f->file->aux != nil &&\n");
    print("\t   *(int*)f->file->aux == O9AUX_SESSION && f->omode != -1){\n");
    print("\t\tO9Session *s = f->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_sub_and_fetch(&s->ref, 1);\n#else\n\t\tadec(&s->ref);\n#endif\n");
    print("\t}\n");
    print("}\n");
    /* open: ref++ (diagnostics; balanced by destroyfid). */
    print("static void o9app_open(Req *r){\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    print("\t   *(int*)r->fid->file->aux == O9AUX_IMPORT){\n");
    print("\t\tint __m = r->ifcall.mode & 3;\n");
    print("\t\tif(__m == OWRITE || __m == ORDWR || (r->ifcall.mode & OTRUNC)){\n");
    print("\t\t\tO9ImportStage *__st = o9app_import_stage_new(r->fid->file->aux, (r->ifcall.mode & OTRUNC) ? 0 : 1);\n");
    print("\t\t\tif(__st == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t\t\tif(r->ifcall.mode & OTRUNC) __st->commit = 1;\n");
    print("\t\t\tr->fid->aux = __st;\n");
    print("\t\t}\n");
    print("\t}\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    print("\t   *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    print("\t\tO9Session *s = r->fid->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_fetch_and_add(&s->ref, 1);\n#else\n\t\tainc(&s->ref);\n#endif\n");
    print("\t}\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    print("static void o9app_create(Req *r){\n");
    print("\tFile *f; O9Export *imp; O9ImportStage *st;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil){ respond(r, \"bad fid\"); return; }\n");
    print("\tif(r->fid->file != o9app_imports_dir){ respond(r, \"create prohibited\"); return; }\n");
    print("\tif((r->ifcall.perm & DMDIR) != 0){ respond(r, \"imports accept files only\"); return; }\n");
    print("\tif(!o9app_import_name_ok(r->ifcall.name)){ respond(r, \"bad import name\"); return; }\n");
    print("\timp = mallocz(sizeof *imp, 1);\n");
    print("\tif(imp == nil){ respond(r, \"no memory\"); return; }\n");
    print("\timp->tag = O9AUX_IMPORT;\n");
    print("\tf = createfile(o9app_imports_dir, r->ifcall.name, \"o9\", 0666, imp);\n");
    print("\tif(f == nil){ free(imp); respond(r, \"file exists\"); return; }\n");
    print("\tst = o9app_import_stage_new(imp, 0);\n");
    print("\tif(st == nil){ removefile(f); respond(r, \"no memory\"); return; }\n");
    print("\tst->commit = 1;\n");
    print("\tr->fid->file = f;\n");
    print("\tr->fid->qid = f->qid;\n");
    print("\tr->fid->aux = st;\n");
    print("\tr->ofcall.qid = f->qid;\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    print("static void o9app_root_read(Req *r){\n");
    print("\tchar *name = r->fid->file->name;\n");
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
    /* Export/import file: its aux holds committed serialized bytes.
     * Serve them ramfs-style (offset/count). */
    print("\tif(r->fid->file->aux != nil && (*(int*)r->fid->file->aux == O9AUX_EXPORT || *(int*)r->fid->file->aux == O9AUX_IMPORT)){\n");
    print("\t\tO9Export *__ex = r->fid->file->aux;\n");
    print("\t\tvlong __off = r->ifcall.offset; long __cnt = r->ifcall.count;\n");
    print("\t\tqlock(&__ex->lock);\n");
    print("\t\tif(__off >= __ex->ndata){ qunlock(&__ex->lock); r->ofcall.count = 0; respond(r, nil); return; }\n");
    print("\t\tif(__off + __cnt > __ex->ndata) __cnt = __ex->ndata - __off;\n");
    print("\t\tmemmove(r->ofcall.data, __ex->data + (int)__off, __cnt);\n");
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
    print("\tchar *name = r->fid->file->name;\n");
    print("\tchar cmd[1024], *f[16]; int nf; char inst[64]; O9ClassH *ch;\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_IMPORT){ o9app_import_write(r); return; }\n");
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

    print("static void o9_app_listen(O9String *addr){\n");
    print("\tchar *caddr;\n");
    print("\tif(addr == nil) return;\n");
    print("\tcaddr = o9_string_cstr(addr);\n");
    print("\tif(caddr == nil || caddr[0] == '\\0'){ free(caddr); return; }\n");
    print("\tthreadlistensrv(&o9app_srv, caddr);\t/* caddr intentionally lives for process lifetime */\n");
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
    emit_tuple_types_node(root);
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
    print("\to9app_srv.create = o9app_create;\n");
    print("\to9app_srv.open = o9app_open;\n\to9app_srv.destroyfid = o9app_destroyfid;\t/* session fid diagnostics */\n");
    /* The four control files + state are a FIXED shape, built once, never
     * mutated (their content is live, their structure is frozen). */
    print("\tcreatefile(o9app_tree->root, \"ctl\", \"o9\", 0666, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"data\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"status\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"methods\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"state\", \"o9\", 0444, nil);\t/* debug inspector */\n");
    /* clone: reading it allocates a session <id>/ with session-local
     * ctl/data/status (docs/SESSIONS.md) — the /net/tcp/clone pattern that
     * gives concurrent callers a private, path-addressable conversation. */
    print("\tcreatefile(o9app_tree->root, \"clone\", \"o9\", 0444, nil);\n");
    /* exports/ is a served-tree DIRECTORY inside the application file tree
     * (NOT on disk).  It is the one MUTABLE part: objects publish Tabulae
     * into it at runtime via a single createfile into this stable parent
     * dir (the authsrv/ramfs-proven safe pattern — no nested subtree, no
     * walkfile).  Reachable through the mount; ls reflects live objects. */
    print("\to9app_exports_dir = createfile(o9app_tree->root, \"exports\", \"o9\", DMDIR|0555, nil);\n");
    print("\to9app_imports_dir = createfile(o9app_tree->root, \"imports\", \"o9\", DMDIR|0777, nil);\n");
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
    print("\to9_process_set_args(argc, argv);\n");
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

/* ========================================================================
 * PRESCAN AND TYPE REGISTRATION
 * ======================================================================== */
/* Two-pass parser: prescan registers all type names, then yyparse() resolves them */

typedef struct PrescanCtx PrescanCtx;
struct PrescanCtx {
    char *modules[32];
    char *pending_module_name;
    int brace_modules[128];
    int module_depth;
    int brace_depth;
    int pending_module;
};

static char*
scan_current_module(PrescanCtx *ctx)
{
    if(ctx->module_depth <= 0)
        return nil;
    return ctx->modules[ctx->module_depth-1];
}

static void
scan_open_brace(PrescanCtx *ctx)
{
    if(ctx->brace_depth < nelem(ctx->brace_modules))
        ctx->brace_modules[ctx->brace_depth++] = ctx->pending_module;
    if(ctx->pending_module && ctx->module_depth < nelem(ctx->modules))
        ctx->modules[ctx->module_depth++] = ctx->pending_module_name;
    ctx->pending_module = 0;
    ctx->pending_module_name = nil;
}

static void
scan_close_brace(PrescanCtx *ctx)
{
    if(ctx->brace_depth > 0 && ctx->brace_modules[--ctx->brace_depth] &&
       ctx->module_depth > 0)
        ctx->module_depth--;
}

static int
scan_brace(PrescanCtx *ctx, int c)
{
    if(c == '{'){
        scan_open_brace(ctx);
        return 1;
    }
    if(c == '}'){
        scan_close_brace(ctx);
        return 1;
    }
    return 0;
}

static int
scan_ignored_punct(int c)
{
    return isspace(c) || c == ';' || c == '(' || c == ')';
}

static void
scan_skip_string(char *buf, long len, long *pos)
{
    while(*pos < len && buf[*pos] != '"')
        (*pos)++;
    if(*pos < len)
        (*pos)++;
}

static void
scan_skip_charlit(char *buf, long len, long *pos)
{
    if(*pos < len && buf[*pos] == '\\')
        (*pos)++;
    if(*pos < len)
        (*pos)++;
    if(*pos < len)
        (*pos)++;
}

static int
scan_skip_comment(char *buf, long len, long *pos)
{
    if(*pos >= len)
        return 0;
    if(buf[*pos] == '/'){
        while(*pos < len && buf[*pos] != '\n')
            (*pos)++;
        return 1;
    }
    if(buf[*pos] == '*'){
        (*pos)++;
        while(*pos + 1 < len && !(buf[*pos] == '*' && buf[*pos+1] == '/'))
            (*pos)++;
        if(*pos + 1 < len)
            *pos += 2;
        return 1;
    }
    return 0;
}

static int
scan_literal_or_comment(char *buf, long len, long *pos, int c)
{
    if(c == '"'){
        scan_skip_string(buf, len, pos);
        return 1;
    }
    if(c == '\''){
        scan_skip_charlit(buf, len, pos);
        return 1;
    }
    if(c == '/')
        return scan_skip_comment(buf, len, pos);
    return 0;
}

static int
scan_read_ident(char *buf, long len, long *pos, int first, char *out, int outsz)
{
    int i;

    i = 0;
    out[i++] = first;
    while(i < outsz-1 && *pos < len &&
          (isalnum((unsigned char)buf[*pos]) || buf[*pos] == '_'))
        out[i++] = buf[(*pos)++];
    out[i] = '\0';
    return i;
}

static void
scan_skip_space(char *buf, long len, long *pos)
{
    while(*pos < len && isspace((unsigned char)buf[*pos]))
        (*pos)++;
}

static int
scan_read_qualified_name(char *buf, long len, long *pos, char *out, int outsz)
{
    int i;

    i = 0;
    while(i < outsz-1 && *pos < len &&
          (isalnum((unsigned char)buf[*pos]) || buf[*pos] == '_' || buf[*pos] == '.'))
        out[i++] = buf[(*pos)++];
    out[i] = '\0';
    return i;
}

static void
scan_module_decl(char *buf, long len, long *pos, PrescanCtx *ctx)
{
    char modname[128];
    char *q;

    scan_skip_space(buf, len, pos);
    scan_read_qualified_name(buf, len, pos, modname, sizeof modname);
    q = qualify_source_name(scan_current_module(ctx), modname);
    ctx->pending_module = 1;
    ctx->pending_module_name = q;
}

static void
scan_enum_values(char *buf, long len, long *pos, char *q, char *cn)
{
    char valname[64];
    int depth, value, c;

    depth = 1;
    value = 0;
    while(*pos < len && depth > 0){
        c = (unsigned char)buf[(*pos)++];
        if(c == '{'){
            depth++;
            continue;
        }
        if(c == '}'){
            depth--;
            continue;
        }
        if(depth == 1 && (isalpha(c) || c == '_')){
            scan_read_ident(buf, len, pos, c, valname, sizeof valname);
            add_enum_sym(q, cn, valname, value++);
        }
    }
}

static void
scan_enum_decl(char *buf, long len, long *pos, PrescanCtx *ctx)
{
    char enumname[64];
    char *q, *cn;
    Node *n;

    scan_skip_space(buf, len, pos);
    if(scan_read_qualified_name(buf, len, pos, enumname, sizeof enumname) <= 0)
        return;
    q = qualify_source_name(scan_current_module(ctx), enumname);
    cn = mangle_source_name(q);
    n = mk(NEnum, cn, nil, nil, nil);
    add_class(cn, n);
    scan_skip_space(buf, len, pos);
    if(*pos < len && buf[*pos] == '{'){
        (*pos)++;
        scan_enum_values(buf, len, pos, q, cn);
    }
}

static int
scan_decl_type(char *word)
{
    if(strcmp(word, "interface") == 0)
        return NInterface;
    if(strcmp(word, "struct") == 0)
        return NStruct;
    return NClass;
}

static void
scan_type_decl(char *buf, long len, long *pos, PrescanCtx *ctx, char *word)
{
    char name[64];
    char *q, *cn;
    Node *n;

    scan_skip_space(buf, len, pos);
    if(scan_read_qualified_name(buf, len, pos, name, sizeof name) <= 0)
        return;
    q = qualify_source_name(scan_current_module(ctx), name);
    cn = mangle_source_name(q);
    n = mk(scan_decl_type(word), cn, nil, nil, nil);
    add_class(cn, n);
}

static void
scan_decl_word(char *buf, long len, long *pos, PrescanCtx *ctx, char *word)
{
    if(strcmp(word, "module") == 0){
        scan_module_decl(buf, len, pos, ctx);
        return;
    }
    if(strcmp(word, "enum") == 0){
        scan_enum_decl(buf, len, pos, ctx);
        return;
    }
    if(strcmp(word, "class") == 0 || strcmp(word, "interface") == 0 ||
       strcmp(word, "struct") == 0)
        scan_type_decl(buf, len, pos, ctx, word);
}

static void
scan_buffer(char *buf, long len)
{
    PrescanCtx ctx;
    long pos;
    int c;
    char name[64];

    memset(&ctx, 0, sizeof ctx);
    pos = 0;
    while(pos < len){
        c = (unsigned char)buf[pos++];
        if(scan_brace(&ctx, c))
            continue;
        if(scan_ignored_punct(c))
            continue;
        if(scan_literal_or_comment(buf, len, &pos, c))
            continue;
        if(isalpha(c) || c == '_'){
            scan_read_ident(buf, len, &pos, c, name, sizeof name);
            scan_decl_word(buf, len, &pos, &ctx, name);
        }
    }
}

static void
prescan(void)
{
    in_prescan = 1;
    scan_buffer(input_buf, input_len);
    in_prescan = 0;
    input_pos = 0;
}

/* ========================================================================
 * TYPECHECK
 * ======================================================================== */

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
validate_name_type(Type *t, int *errs)
{
    Node *d;
    char *s;

    if(type_is_builtin_name(t->name) || is_type_param_name(t->name))
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
}

static int
validate_param_type(Type *t, int *errs)
{
    if(is_type_param_name(t->name))
        return 0;
    fprint(2, "o9c: error: line %d: type parameter '%s' is not in scope\n", sem_line, t->name);
    (*errs)++;
    return -1;
}

typedef struct TypeArityRule TypeArityRule;
struct TypeArityRule {
    char *name;
    int exact;
    int min;
    char *msg;
};

static TypeArityRule*
type_arity_rule(char *name)
{
    static TypeArityRule rules[] = {
        { "List", 1, 0, "List needs 1 type argument" },
        { "Task", 1, 0, "Task needs 1 type argument" },
        { "Dict", 2, 0, "Dict needs 2 type arguments" },
        { "Tuple", -1, 2, "tuple needs at least 2 type arguments" },
        { nil, 0, 0, nil }
    };
    int i;

    for(i = 0; rules[i].name != nil; i++)
        if(strcmp(name, rules[i].name) == 0)
            return &rules[i];
    return nil;
}

static int
type_arity_bad(TypeArityRule *r, int argc)
{
    if(r->exact >= 0)
        return argc != r->exact;
    return argc < r->min;
}

static int
validate_builtin_apply_type(Type *t, int *errs)
{
    TypeArityRule *r;
    Type *kt;

    r = type_arity_rule(t->name);
    if(r == nil)
        return 0;
    if(type_arity_bad(r, type_list_len(t->args))){
        fprint(2, "o9c: error: line %d: %s\n", sem_line, r->msg);
        (*errs)++;
        return 1;
    }
    if(strcmp(t->name, "Dict") == 0){
        kt = type_list_at(t->args, 0);
        if(!type_is_string(kt) && !type_is_double(kt) && !type_is_integral_dict_key(kt)){
            fprint(2, "o9c: error: line %d: Dict key type must be string or scalar\n",
                sem_line);
            (*errs)++;
        }
    }
    return 1;
}

static void
validate_user_apply_type(Type *t, int *errs)
{
    Node *d;
    char *s;
    int arity;

    d = type_decl_node(t);
    if(d == nil){
        s = type_render(t);
        fprint(2, "o9c: error: line %d: unknown generic type '%s'\n", sem_line, s);
        (*errs)++;
        return;
    }
    arity = node_list_len(d->params);
    if(arity == 0){
        s = type_render(t);
        fprint(2, "o9c: error: line %d: type '%s' is not generic\n", sem_line, s);
        (*errs)++;
        return;
    }
    if(arity != type_list_len(t->args)){
        s = type_render(t);
        fprint(2, "o9c: error: line %d: generic type '%s' needs %d argument(s)\n", sem_line,
            s, arity);
        (*errs)++;
    }
}

static void
validate_type_args(TypeList *args, int *errs)
{
    TypeList *a;

    for(a = args; a; a = a->next)
        validate_type(a->type, errs);
}

static int
validate_apply_type(Type *t, int *errs)
{
    if(!validate_builtin_apply_type(t, errs))
        validate_user_apply_type(t, errs);
    validate_type_args(t->args, errs);
    return 0;
}

static int
validate_ptr_type(Type *t, int *errs)
{
    char *s;

    s = type_render(t);
    fprint(2, "o9c: error: line %d: pointer type '%s' is not allowed in o9 declarations "
        "(keep raw pointers inside function c blocks and pass ordinary values through object methods/properties)\n",
        sem_line, s);
    (*errs)++;
    return -1;
}

static int
validate_type(Type *t, int *errs)
{
    if(t == nil)
        return 0;
    switch(t->kind){
    case TyName:
        return validate_name_type(t, errs);
    case TyParam:
        return validate_param_type(t, errs);
    case TyApply:
        return validate_apply_type(t, errs);
    case TyPtr:
        return validate_ptr_type(t, errs);
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
rawc_contains_any(char *id, char **words)
{
    int i;

    for(i = 0; words[i] != nil; i++)
        if(strstr(id, words[i]) != nil)
            return 1;
    return 0;
}

static int
rawc_prefix_any(char *id, char **words)
{
    int i;

    for(i = 0; words[i] != nil; i++)
        if(strncmp(id, words[i], strlen(words[i])) == 0)
            return 1;
    return 0;
}

static int
rawc_exact_any(char *id, char **words)
{
    int i;

    for(i = 0; words[i] != nil; i++)
        if(strcmp(id, words[i]) == 0)
            return 1;
    return 0;
}

static int
rawc_forbidden_ident(char *id, char **why)
{
    static char *contains[] = {
        "_Internal", "_Client", "_find_instance", "_record_instance",
        "_create_instance", "_forget_instance", "_instances",
        "_ninstances", nil
    };
    static char *prefixes[] = {
        "o9_impl_", "o9_self_", "o9_ctrl_", "o9_registry_",
        "o9_objects_", "o9app_", "obj9_", nil
    };
    static char *exact[] = {
        "O9Msg", "O9Reply", "O9ObjectStore", "O9State", "ArcLedger",
        "dispatch_chan", "shm_base", "objdir", nil
    };

    if(id == nil)
        return 0;
    if(rawc_contains_any(id, contains) || rawc_prefix_any(id, prefixes) ||
       rawc_exact_any(id, exact)){
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
    return n->typeinfo;
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
type_integral_scalar(Type *t)
{
    return type_numeric_scalar(t) && !type_is_double(t);
}

static int
type_compatible_either(Type *a, Type *b)
{
    return type_assignable_semantic(a, b) || type_assignable_semantic(b, a);
}

static int
type_castable_semantic(Type *target, Type *actual)
{
    if(target == nil || actual == nil)
        return 1;
    if(type_is_nil(target) || type_is_nil(actual))
        return 0;
    return type_scalar_builtin(target) && type_scalar_builtin(actual);
}

static int
type_assignable_semantic(Type *target, Type *actual)
{
    Node *td, *ad;
    char *tc, *ac;

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
type_cast_error(Type *target, Type *actual, int *errs)
{
    char *ts, *as;

    ts = target != nil ? type_render(target) : "<unknown>";
    as = actual != nil ? type_render(actual) : "<unknown>";
    fprint(2, "o9c: error: line %d: cannot cast %s to %s\n", sem_line, as, ts);
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
    static char *names[NNodeKinds];

    if(names[NAdd] == nil){
        names[NAdd] = "+";
        names[NSub] = "-";
        names[NMul] = "*";
        names[NDiv] = "/";
        names[NMod] = "%";
        names[NBitAnd] = "&";
        names[NBitOr] = "|";
        names[NBitXor] = "^";
        names[NLshift] = "<<";
        names[NRshift] = ">>";
        names[NEq] = "==";
        names[NNe] = "!=";
        names[NLt] = "<";
        names[NLe] = "<=";
        names[NGt] = ">";
        names[NGe] = ">=";
        names[NAnd] = "&&";
        names[NOr] = "||";
        names[NNeg] = "-";
        names[NBitNot] = "~";
        names[NNot] = "!";
    }
    if(type >= 0 && type < NNodeKinds && names[type] != nil)
        return names[type];
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
collection_get_type(Type *left)
{
    if(left != nil && left->kind == TyApply){
        if(strcmp(left->name, "List") == 0)
            return type_list_at(left->args, 0);
        if(strcmp(left->name, "Dict") == 0)
            return type_list_at(left->args, 1);
    }
    if(type_is_array(left))
        return type_array_elem(left);
    return nil;
}

typedef Type* (*AnnotateExprFn)(Node*, Node*);

static Type *annotate_expr_type(Node *e, Node *scope_class);

static void
annotate_expr_list(Node *n, Node *scope_class)
{
    for(; n != nil; n = n->next)
        annotate_expr_type(n, scope_class);
}

static Type*
annotate_default(Node *e, Node *scope_class)
{
    (void)scope_class;
    return e->typeinfo;
}

static Type*
annotate_try_expr(Node *e, Node *scope_class)
{
    return set_expr_type(e, annotate_expr_type(e->left, scope_class));
}

static Type*
annotate_spawn_expr(Node *e, Node *scope_class)
{
    Node *fc, *rm;
    Type *rt;
    char *fcn;

    rt = type_name("int64");
    fcn = spawn_function_cname(e->name, scope_class);
    annotate_expr_list(e->right, scope_class);
    fc = find_class(fcn);
    if(fc == nil)
        return set_expr_type(e, type_apply("Task", type_list(rt)));
    for(rm = fc->left; rm != nil; rm = rm->next)
        if(rm->type == NMethod && rm->name != nil && strcmp(rm->name, "run") == 0){
            if(rm->typeinfo != nil)
                rt = rm->typeinfo;
            break;
        }
    return set_expr_type(e, type_apply("Task", type_list(rt)));
}

static Type*
annotate_cast_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    return set_expr_type(e, e->typeinfo);
}

static Type*
annotate_int_lit(Node *e, Node *scope_class)
{
    (void)scope_class;
    return set_expr_type(e, type_name("int64"));
}

static Type*
annotate_double_lit(Node *e, Node *scope_class)
{
    (void)scope_class;
    return set_expr_type(e, type_name("double"));
}

static Type*
annotate_string_lit(Node *e, Node *scope_class)
{
    (void)scope_class;
    return set_expr_type(e, type_name("string"));
}

static Type*
annotate_char_lit(Node *e, Node *scope_class)
{
    (void)scope_class;
    return set_expr_type(e, type_name("char"));
}

static Type*
annotate_bool_lit(Node *e, Node *scope_class)
{
    (void)scope_class;
    if(e->name != nil && strcmp(e->name, "nil") == 0)
        return set_expr_type(e, type_name("nil"));
    return set_expr_type(e, type_name("bool"));
}

static Type*
annotate_enum_val(Node *e, Node *scope_class)
{
    (void)scope_class;
    return e->typeinfo;
}

static Type*
annotate_tuple_lit(Node *e, Node *scope_class)
{
    TypeList *tl;
    Type *t;
    Node *a;

    tl = nil;
    for(a = e->left; a != nil; a = a->next){
        t = annotate_expr_type(a, scope_class);
        tl = type_list_append(tl, t);
    }
    return set_expr_type(e, type_apply("Tuple", tl));
}

static Type*
annotate_class_expr(Node *e, Node *scope_class)
{
    annotate_expr_list(e->right, scope_class);
    if(e->typeinfo != nil)
        return e->typeinfo;
    if(e->name != nil)
        return set_expr_type(e, type_name(e->name));
    return nil;
}

static Type*
annotate_ident_expr(Node *e, Node *scope_class)
{
    Type *t;

    t = get_typeinfo_sym(e->name);
    if(t == nil)
        t = member_typeinfo(scope_class, e->name, 0);
    return set_expr_type(e, t);
}

static Type*
annotate_prop_read_expr(Node *e, Node *scope_class)
{
    Type *lt;
    TypedMember tm;

    lt = annotate_expr_type(e->left, scope_class);
    if(typed_member_lookup(lt, e->name, 0, &tm))
        return set_expr_type(e, tm.type);
    return set_expr_type(e, nil);
}

static Type*
annotate_self_scope_type(Node *scope_class)
{
    if(scope_class == nil)
        return nil;
    if(scope_class->typeinfo != nil)
        return scope_class->typeinfo;
    return type_from_name(scope_class->qname != nil ? scope_class->qname : scope_class->name);
}

static Type*
annotate_self_call_expr(Node *e, Node *scope_class)
{
    Builtin *b;
    TypedMember tm;
    Type *lt;

    annotate_expr_list(e->right, scope_class);
    lt = annotate_self_scope_type(scope_class);
    if(typed_member_lookup(lt, e->name, 1, &tm))
        return set_expr_type(e, tm.type);
    b = find_builtin(e->name);
    if(b != nil)
        return set_expr_type(e, type_name(b->ret));
    return set_expr_type(e, nil);
}

static Type*
annotate_handle_msg_type(Node *e, Type *lt)
{
    if(type_named(lt, "Tabula") || type_named(lt, "MountTable")){
        if(expr_name_is(e, "schema") || expr_name_is(e, "get") ||
           expr_name_is(e, "read") || expr_name_is(e, "serialize"))
            return type_name("string");
        if(expr_name_is(e, "query"))
            return type_name("Tabula");
        if(expr_name_is(e, "close"))
            return type_name("void");
        return type_name("int64");
    }
    return nil;
}

static Type*
annotate_collection_msg_type(Node *e, Type *lt)
{
    if(type_is_collection(lt, "List")){
        if(expr_name_is(e, "Length"))
            return type_name("int64");
        if(expr_name_is(e, "Add"))
            return type_name("void");
    }
    if(type_is_collection(lt, "Dict") && expr_name_is(e, "Has"))
        return type_name("bool");
    return nil;
}

static Type*
annotate_msg_send_expr(Node *e, Node *scope_class)
{
    Type *lt, *t;
    TypedMember tm;

    lt = annotate_expr_type(e->left, scope_class);
    annotate_expr_list(e->right, scope_class);
    if(type_apply_named(lt, "Task") && expr_name_is(e, "await"))
        return set_expr_type(e, type_list_at(lt->args, 0));
    t = annotate_handle_msg_type(e, lt);
    if(t != nil)
        return set_expr_type(e, t);
    t = annotate_collection_msg_type(e, lt);
    if(t != nil)
        return set_expr_type(e, t);
    if(typed_member_lookup(lt, e->name, 1, &tm))
        return set_expr_type(e, tm.type);
    return set_expr_type(e, nil);
}

static Type*
annotate_array_get_expr(Node *e, Node *scope_class)
{
    Type *lt;

    lt = annotate_expr_type(e->left, scope_class);
    annotate_expr_type(e->right, scope_class);
    return set_expr_type(e, collection_get_type(lt));
}

static Type*
annotate_assign_expr(Node *e, Node *scope_class)
{
    Type *lt;

    lt = annotate_expr_type(e->left, scope_class);
    annotate_expr_type(e->right, scope_class);
    return set_expr_type(e, lt);
}

static Type*
annotate_return_expr(Node *e, Node *scope_class)
{
    return set_expr_type(e, annotate_expr_type(e->left, scope_class));
}

static Type*
annotate_func_call_expr(Node *e, Node *scope_class)
{
    annotate_expr_list(e->left, scope_class);
    if(expr_name_is(e, "print"))
        return set_expr_type(e, type_name("void"));
    return nil;
}

static Type*
annotate_chan_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    annotate_expr_type(e->right, scope_class);
    return set_expr_type(e, type_name("void"));
}

static Type*
annotate_numeric_expr(Node *e, Node *scope_class)
{
    Type *lt, *rt;

    lt = annotate_expr_type(e->left, scope_class);
    rt = annotate_expr_type(e->right, scope_class);
    if(type_is_double(lt) || type_is_double(rt))
        return set_expr_type(e, type_name("double"));
    return set_expr_type(e, type_name("int64"));
}

static Type*
annotate_int_binary_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    annotate_expr_type(e->right, scope_class);
    return set_expr_type(e, type_name("int64"));
}

static Type*
annotate_neg_expr(Node *e, Node *scope_class)
{
    Type *lt;

    lt = annotate_expr_type(e->left, scope_class);
    if(type_is_double(lt))
        return set_expr_type(e, type_name("double"));
    return set_expr_type(e, type_name("int64"));
}

static Type*
annotate_bitnot_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    return set_expr_type(e, type_name("int64"));
}

static Type*
annotate_bool_result_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    annotate_expr_type(e->right, scope_class);
    return set_expr_type(e, type_name("bool"));
}

static Type*
annotate_not_expr(Node *e, Node *scope_class)
{
    annotate_expr_type(e->left, scope_class);
    return set_expr_type(e, type_name("bool"));
}

static AnnotateExprFn annotate_expr_handlers[NNodeKinds];

static void
init_annotate_expr_handlers(void)
{
    if(annotate_expr_handlers[NIdent] != nil)
        return;
    annotate_expr_handlers[NTry] = annotate_try_expr;
    annotate_expr_handlers[NSpawn] = annotate_spawn_expr;
    annotate_expr_handlers[NCast] = annotate_cast_expr;
    annotate_expr_handlers[NIntLit] = annotate_int_lit;
    annotate_expr_handlers[NDoubleLit] = annotate_double_lit;
    annotate_expr_handlers[NStringLit] = annotate_string_lit;
    annotate_expr_handlers[NTupleLit] = annotate_tuple_lit;
    annotate_expr_handlers[NCharLit] = annotate_char_lit;
    annotate_expr_handlers[NBoolLit] = annotate_bool_lit;
    annotate_expr_handlers[NEnumVal] = annotate_enum_val;
    annotate_expr_handlers[NClass] = annotate_class_expr;
    annotate_expr_handlers[NIdent] = annotate_ident_expr;
    annotate_expr_handlers[NPropRead] = annotate_prop_read_expr;
    annotate_expr_handlers[NSelfCall] = annotate_self_call_expr;
    annotate_expr_handlers[NMsgSend] = annotate_msg_send_expr;
    annotate_expr_handlers[NArrayGet] = annotate_array_get_expr;
    annotate_expr_handlers[NAssign] = annotate_assign_expr;
    annotate_expr_handlers[NReturn] = annotate_return_expr;
    annotate_expr_handlers[NFuncCall] = annotate_func_call_expr;
    annotate_expr_handlers[NChanSend] = annotate_chan_expr;
    annotate_expr_handlers[NChanRecv] = annotate_chan_expr;
    annotate_expr_handlers[NChanTry] = annotate_chan_expr;
    annotate_expr_handlers[NAdd] = annotate_numeric_expr;
    annotate_expr_handlers[NSub] = annotate_numeric_expr;
    annotate_expr_handlers[NMul] = annotate_numeric_expr;
    annotate_expr_handlers[NDiv] = annotate_numeric_expr;
    annotate_expr_handlers[NMod] = annotate_int_binary_expr;
    annotate_expr_handlers[NBitAnd] = annotate_int_binary_expr;
    annotate_expr_handlers[NBitOr] = annotate_int_binary_expr;
    annotate_expr_handlers[NBitXor] = annotate_int_binary_expr;
    annotate_expr_handlers[NLshift] = annotate_int_binary_expr;
    annotate_expr_handlers[NRshift] = annotate_int_binary_expr;
    annotate_expr_handlers[NNeg] = annotate_neg_expr;
    annotate_expr_handlers[NBitNot] = annotate_bitnot_expr;
    annotate_expr_handlers[NEq] = annotate_bool_result_expr;
    annotate_expr_handlers[NNe] = annotate_bool_result_expr;
    annotate_expr_handlers[NLt] = annotate_bool_result_expr;
    annotate_expr_handlers[NLe] = annotate_bool_result_expr;
    annotate_expr_handlers[NGt] = annotate_bool_result_expr;
    annotate_expr_handlers[NGe] = annotate_bool_result_expr;
    annotate_expr_handlers[NAnd] = annotate_bool_result_expr;
    annotate_expr_handlers[NOr] = annotate_bool_result_expr;
    annotate_expr_handlers[NNot] = annotate_not_expr;
}

static AnnotateExprFn
annotate_expr_handler_for(int type)
{
    if(type < 0)
        return annotate_default;
    if(type >= NNodeKinds)
        return annotate_default;
    if(annotate_expr_handlers[type] == nil)
        return annotate_default;
    return annotate_expr_handlers[type];
}

static Type*
annotate_expr_type(Node *e, Node *scope_class)
{
    if(e == nil)
        return type_name("void");
    init_annotate_expr_handlers();
    return annotate_expr_handler_for(e->type)(e, scope_class);
}

static void
add_decl_type_sym(Node *n)
{
    Type *t;
    Node *d;

    if(n == nil || n->name == nil || n->typename == nil)
        return;
    t = decl_typeinfo(n);
    add_type_sym_typed(n->name, t);
    d = type_decl_node(t);
    if(d != nil && (d->type == NClass || d->type == NInterface))
        add_var_class(n->name, type_cname(t));
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
        fprint(2, "o9c: error: line %d: remote Tabula uses declaration syntax: near/far/listener Tabula name = new Tabula(...) @ address\n",
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
typecheck_ident(Node *e, Node *scope_class, int *errs)
{
    Type *st;
    TypedMember tm;

    if(e->name == nil || get_typeinfo_sym(e->name) != nil)
        return;
    if(scope_class == nil){
        fprint(2, "o9c: error: line %d: unknown identifier '%s'\n",
            sem_line, e->name);
        (*errs)++;
        return;
    }
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

static void
typecheck_tuple_lit(Node *e, Node *scope_class, int *errs)
{
    Node *a;

    annotate_expr_type(e, scope_class);
    for(a = e->left; a != nil; a = a->next){
        if(a->line > 0)
            sem_line = a->line;
        typecheck_expr(a, scope_class, errs);
        if(tuple_field_is_object_handle(a)){
            fprint(2, "o9c: error: line %d: tuple field cannot be an object handle "
                "(bind the object to a named value and pass it separately; tuple payloads are data-only for now)\n",
                sem_line);
            (*errs)++;
        }
    }
}

static void
typecheck_class_new(Node *e, Node *scope_class, int *errs)
{
    Node *d;

    validate_type(e->typeinfo, errs);
    if(is_tabula_new(e)){
        typecheck_tabula_new(e, scope_class, errs);
        return;
    }
    if(is_mount_table_new(e)){
        typecheck_mount_table_new(e, scope_class, errs);
        return;
    }
    if(o9_locality_kind(e->typename) >= 0){
        fprint(2, "o9c: error: line %d: remote objects are not supported; only Tabula data may be declared near/far/listener with @\n",
            sem_line);
        (*errs)++;
    }
    d = type_decl_node(e->typeinfo);
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

static void
typecheck_prop_read(Node *e, Node *scope_class, int *errs)
{
    Type *lt;
    Node *cnode;
    TypedMember tm;

    annotate_expr_type(e, scope_class);
    if(e->left == nil)
        return;
    lt = e->left->typeinfo;
    cnode = nil;
    if(type_is_collection(lt, "List") || type_is_collection(lt, "Dict"))
        return;
    cnode = type_decl_node(lt);
    if(cnode == nil && e->left->type == NIdent && e->left->name != nil){
        char *cn = get_var_class(e->left->name);
        if(cn != nil)
            cnode = find_class(cn);
    }
    if(cnode == nil){
        if(e->left->type == NIdent && e->left->name != nil){
            fprint(2, "o9c: error: line %d: unknown type for '%s'\n", sem_line, e->left->name);
            (*errs)++;
        }
        return;
    }
    if(typed_member_lookup(lt, e->name, 1, &tm)){
        fprint(2, "o9c: error: line %d: '%s' is a method, not a property\n", sem_line, e->name);
        (*errs)++;
    } else if(!typed_member_lookup(lt, e->name, 0, &tm)){
        fprint(2, "o9c: error: line %d: '%s' has no member '%s'\n", sem_line, cnode->name, e->name);
        (*errs)++;
    } else if(tm.node != nil && (tm.node->flags & NFPrivate) &&
              tm.owner != scope_class){
        fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
            tm.owner != nil ? tm.owner->name : cnode->name, e->name);
        (*errs)++;
    }
}

static Node*
first_parent_class(Node *scope_class)
{
    Node *im;

    if(scope_class == nil)
        return nil;
    for(im = scope_class->left; im != nil; im = im->next)
        if(im->type == NInherit)
            return find_class(im->name);
    return nil;
}

static Node*
class_constructor(Node *c)
{
    Node *m;

    if(c == nil)
        return nil;
    for(m = c->left; m != nil; m = m->next)
        if(m->type == NMethod && m->name != nil && strcmp(m->name, c->name) == 0)
            return m;
    return nil;
}

static int
typecheck_super_call(Node *e, Node *scope_class, int *errs)
{
    Node *a, *parent, *pctor;
    int want, got;

    if(e->name == nil || strcmp(e->name, "super") != 0)
        return 0;
    for(a = e->right; a != nil; a = a->next)
        typecheck_expr(a, scope_class, errs);
    parent = first_parent_class(scope_class);
    if(parent == nil){
        fprint(2, "o9c: error: line %d: super() with no parent class\n", sem_line);
        (*errs)++;
        return 1;
    }
    pctor = class_constructor(parent);
    got = node_list_len(e->right);
    if(pctor == nil && got != 0){
        fprint(2, "o9c: error: line %d: %s has no constructor; super() takes no arguments\n",
            sem_line, parent->name);
        (*errs)++;
        return 1;
    }
    want = pctor != nil ? node_list_len(pctor->right) : 0;
    if(pctor != nil && want != got){
        fprint(2, "o9c: error: line %d: super() calls %s(%d args), got %d\n",
            sem_line, parent->name, want, got);
        (*errs)++;
    }
    return 1;
}

static void
typecheck_builtin_arg(Node *e, Builtin *bi, Node *a, int pi, int *errs)
{
    if(strcmp(bi->args[pi], "object") == 0){
        if(type_decl_node(a->typeinfo) == nil){
            fprint(2, "o9c: error: line %d: argument %d to '%s' must be an object handle\n",
                sem_line, pi + 1, e->name);
            (*errs)++;
        }
        return;
    }
    if(!type_assignable_semantic(type_name(bi->args[pi]), a->typeinfo)){
        fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n",
            sem_line, pi + 1, e->name,
            a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
            bi->args[pi]);
        (*errs)++;
    }
}

static int
typecheck_builtin_self_call(Node *e, Node *scope_class, int *errs)
{
    Builtin *bi;
    Node *a;
    int pi;

    (void)scope_class;
    bi = find_builtin(e->name);
    if(bi == nil)
        return 0;
    if(node_list_len(e->right) != bi->argc){
        fprint(2, "o9c: error: line %d: builtin '%s' needs %d argument(s)\n",
            sem_line, e->name, bi->argc);
        (*errs)++;
        return 1;
    }
    for(a = e->right, pi = 0; a != nil && pi < bi->argc; a = a->next, pi++)
        typecheck_builtin_arg(e, bi, a, pi, errs);
    return 1;
}

static Type*
self_scope_type(Node *scope_class)
{
    if(scope_class == nil)
        return nil;
    if(scope_class->typeinfo != nil)
        return scope_class->typeinfo;
    return type_from_name(scope_class->qname != nil ? scope_class->qname : scope_class->name);
}

static void
typecheck_missing_self_call(Node *e, Node *scope_class, int *errs)
{
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
}

static void
typecheck_self_method_args(Node *e, TypedMember *tm, int *errs)
{
    Node *p, *a;
    Type *expected;
    int pi;

    if(node_list_len(tm->node->right) != node_list_len(e->right)){
        fprint(2, "o9c: error: line %d: method '%s' needs %d argument(s)\n",
            sem_line, e->name, node_list_len(tm->node->right));
        (*errs)++;
        return;
    }
    for(p = tm->node->right, a = e->right, pi = 0; p && a; p = p->next, a = a->next, pi++){
        expected = type_subst(p->typeinfo, tm->bindings);
        if(!type_assignable_semantic(expected, a->typeinfo)){
            fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n",
                sem_line, pi + 1, e->name,
                a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
                expected != nil ? type_render(expected) : "<unknown>");
            (*errs)++;
        }
    }
}

static void
typecheck_resolved_self_method(Node *e, Node *scope_class, TypedMember *tm, int *errs)
{
    tm->node->flags |= NFSelfCalled;
    if((tm->node->flags & NFPrivate) && tm->owner != scope_class){
        fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
            tm->owner != nil ? tm->owner->name : "?", e->name);
        (*errs)++;
    }
    typecheck_self_method_args(e, tm, errs);
}

static void
typecheck_self_call(Node *e, Node *scope_class, int *errs)
{
    Type *st;
    TypedMember tm;
    int ismethod;

    annotate_expr_type(e, scope_class);
    if(typecheck_super_call(e, scope_class, errs))
        return;
    st = self_scope_type(scope_class);
    ismethod = st != nil && typed_member_lookup(st, e->name, 1, &tm);
    if(!ismethod && typecheck_builtin_self_call(e, scope_class, errs))
        return;
    if(scope_class == nil){
        fprint(2, "o9c: error: line %d: unknown function '%s'\n", sem_line, e->name);
        (*errs)++;
        return;
    }
    if(!ismethod && typed_member_lookup(st, e->name, 0, &tm)){
        fprint(2, "o9c: error: line %d: '%s' is a property, not a method\n", sem_line, e->name);
        (*errs)++;
        return;
    }
    if(!ismethod){
        typecheck_missing_self_call(e, scope_class, errs);
        return;
    }
    if(tm.node != nil)
        typecheck_resolved_self_method(e, scope_class, &tm, errs);
}

typedef struct MsgRule MsgRule;
struct MsgRule {
    char *name;
    int argc;
    int allstrings;
    int stringprefix;
    int intarg;
    int arg4string;
};

typedef int (*TypecheckMsgFn)(Node*, Node*, Type*, int*);

static MsgRule*
lookup_msg_rule(MsgRule *rules, int nrules, char *name)
{
    int i;

    if(name == nil)
        return nil;
    for(i = 0; i < nrules; i++)
        if(strcmp(rules[i].name, name) == 0)
            return &rules[i];
    return nil;
}

static void
typecheck_arg_values(Node *args, Node *scope_class, int *errs)
{
    Node *a;

    for(a = args; a != nil; a = a->next)
        typecheck_expr(a, scope_class, errs);
}

static void
msg_arity_error(char *owner, Node *e, int want, int got, int *errs)
{
    fprint(2, "o9c: error: line %d: %s.%s takes %d argument%s, got %d\n",
        sem_line, owner, e->name, want, want == 1 ? "" : "s", got);
    (*errs)++;
}

static int
msg_rule_arg_is_string(MsgRule *r, int pi)
{
    if(r->allstrings)
        return 1;
    if(pi < r->stringprefix)
        return 1;
    if(r->arg4string && pi == 3)
        return 1;
    return 0;
}

static void
typecheck_rule_arg(char *owner, Node *e, Node *a, MsgRule *r, int pi, int *errs)
{
    if(msg_rule_arg_is_string(r, pi)){
        if(!type_assignable_semantic(type_name("string"), a->typeinfo)){
            fprint(2, "o9c: error: line %d: %s.%s argument %d must be string\n",
                sem_line, owner, e->name, pi + 1);
            (*errs)++;
        }
    }
    if(pi == r->intarg){
        if(!type_assignable_semantic(type_name("int64"), a->typeinfo)){
            fprint(2, "o9c: error: line %d: %s.%s argument %d must be int64\n",
                sem_line, owner, e->name, pi + 1);
            (*errs)++;
        }
    }
}

static void
typecheck_rule_args(char *owner, Node *e, Node *scope_class, MsgRule *r, int *errs)
{
    Node *a;
    int got, pi;

    got = node_list_len(e->right);
    if(got != r->argc)
        msg_arity_error(owner, e, r->argc, got, errs);
    for(a = e->right, pi = 0; a != nil; a = a->next, pi++){
        typecheck_expr(a, scope_class, errs);
        if(got == r->argc)
            typecheck_rule_arg(owner, e, a, r, pi, errs);
    }
}

static int
typecheck_task_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    (void)scope_class;
    if(!type_apply_named(lt, "Task"))
        return 0;
    if(!expr_name_is(e, "await")){
        fprint(2, "o9c: error: line %d: Task has no method '%s' (only await)\n",
            sem_line, e->name);
        (*errs)++;
        return 1;
    }
    if(node_list_len(e->right) != 0){
        fprint(2, "o9c: error: line %d: Task.await takes no arguments\n", sem_line);
        (*errs)++;
    }
    return 1;
}

static int
typecheck_tabula_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    static MsgRule rules[] = {
        {"schema", 0, 0, 0, -1, 0},
        {"has", 1, 1, 0, -1, 0},
        {"add", 1, 1, 0, -1, 0},
        {"write", 3, 1, 0, -1, 0},
        {"set", 2, 1, 0, -1, 0},
        {"get", 1, 1, 0, -1, 0},
        {"first", 0, 0, 0, -1, 0},
        {"next", 0, 0, 0, -1, 0},
        {"read", 0, 0, 0, -1, 0},
        {"serialize", 0, 0, 0, -1, 0},
        {"query", 2, 1, 0, -1, 0},
        {"flush", 0, 0, 0, -1, 0},
        {"sync", 0, 0, 0, -1, 0},
        {"push", 0, 0, 0, -1, 0},
        {"close", 0, 0, 0, -1, 0},
    };
    MsgRule *r;

    if(!type_named(lt, "Tabula"))
        return 0;
    r = lookup_msg_rule(rules, nelem(rules), e->name);
    if(r == nil){
        fprint(2, "o9c: error: line %d: Tabula has no method '%s' "
            "(schema/has/add/write/set/get/first/next/read/serialize/query/flush/sync/push/close)\n",
            sem_line, e->name);
        (*errs)++;
        typecheck_arg_values(e->right, scope_class, errs);
        return 1;
    }
    typecheck_rule_args("Tabula", e, scope_class, r, errs);
    return 1;
}

static int
typecheck_mounttable_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    static MsgRule rules[] = {
        {"allowRoot", 1, 1, 0, -1, 0},
        {"dir", 2, 0, 1, 1, 0},
        {"bind", 3, 0, 2, 2, 0},
        {"mountsrv", 4, 0, 2, 2, 1},
        {"schema", 0, 0, 0, -1, 0},
        {"has", 1, 1, 0, -1, 0},
        {"get", 1, 1, 0, -1, 0},
        {"first", 0, 0, 0, -1, 0},
        {"next", 0, 0, 0, -1, 0},
        {"read", 0, 0, 0, -1, 0},
        {"serialize", 0, 0, 0, -1, 0},
        {"query", 2, 1, 0, -1, 0},
        {"flush", 0, 0, 0, -1, 0},
        {"validate", 0, 0, 0, -1, 0},
        {"apply", 0, 0, 0, -1, 0},
        {"close", 0, 0, 0, -1, 0},
    };
    MsgRule *r;

    if(!type_named(lt, "MountTable"))
        return 0;
    r = lookup_msg_rule(rules, nelem(rules), e->name);
    if(r == nil){
        fprint(2, "o9c: error: line %d: MountTable has no method '%s' "
            "(dir/bind/mountsrv/allowRoot/read/query/flush/validate/apply/close)\n",
            sem_line, e->name);
        (*errs)++;
        typecheck_arg_values(e->right, scope_class, errs);
        return 1;
    }
    typecheck_rule_args("MountTable", e, scope_class, r, errs);
    return 1;
}

static int
typecheck_list_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    (void)scope_class;
    if(!type_is_collection(lt, "List"))
        return 0;
    if(expr_name_is(e, "Length")){
        if(e->right != nil){
            fprint(2, "o9c: error: line %d: List.Length needs 0 arguments\n", sem_line);
            (*errs)++;
        }
        return 1;
    }
    if(!expr_name_is(e, "Add")){
        fprint(2, "o9c: error: line %d: List has no method '%s'\n", sem_line, e->name);
        (*errs)++;
        return 1;
    }
    if(node_list_len(e->right) != 1){
        fprint(2, "o9c: error: line %d: List.Add needs 1 argument\n", sem_line);
        (*errs)++;
        return 1;
    }
    if(!type_assignable_semantic(type_list_at(lt->args, 0), e->right->typeinfo))
        type_mismatch_error("pass", type_list_at(lt->args, 0), e->right->typeinfo, errs);
    return 1;
}

static int
typecheck_dict_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    (void)scope_class;
    if(!type_is_collection(lt, "Dict"))
        return 0;
    if(!expr_name_is(e, "Has")){
        fprint(2, "o9c: error: line %d: Dict has no method '%s'\n", sem_line, e->name);
        (*errs)++;
        return 1;
    }
    if(node_list_len(e->right) != 1){
        fprint(2, "o9c: error: line %d: Dict.Has needs 1 argument\n", sem_line);
        (*errs)++;
        return 1;
    }
    if(!type_assignable_semantic(type_list_at(lt->args, 0), e->right->typeinfo))
        type_mismatch_error("pass", type_list_at(lt->args, 0), e->right->typeinfo, errs);
    return 1;
}

static Node*
typecheck_receiver_class(Node *e, Type *lt)
{
    char *cn;
    Node *cnode;

    cnode = type_decl_node(lt);
    if(cnode != nil)
        return cnode;
    if(!assign_ident(e->left))
        return nil;
    cn = get_var_class(e->left->name);
    if(cn == nil)
        return nil;
    return find_class(cn);
}

static void
typecheck_generic_msg_args(Node *e, TypedMember *tm, int *errs)
{
    Node *p, *a;
    Type *expected;
    int pi;

    if(node_list_len(tm->node->right) != node_list_len(e->right)){
        fprint(2, "o9c: error: line %d: method '%s' needs %d argument(s)\n", sem_line,
            e->name, node_list_len(tm->node->right));
        (*errs)++;
        return;
    }
    for(p = tm->node->right, a = e->right, pi = 0; p && a; p = p->next, a = a->next, pi++){
        expected = type_subst(p->typeinfo, tm->bindings);
        if(!type_assignable_semantic(expected, a->typeinfo)){
            fprint(2, "o9c: error: line %d: argument %d to '%s' has type %s, expected %s\n", sem_line,
                pi + 1, e->name,
                a->typeinfo != nil ? type_render(a->typeinfo) : "<unknown>",
                expected != nil ? type_render(expected) : "<unknown>");
            (*errs)++;
        }
    }
}

static void
typecheck_generic_msg(Node *e, Node *scope_class, Type *lt, int *errs)
{
    Node *cnode;
    TypedMember tm;

    cnode = typecheck_receiver_class(e, lt);
    if(cnode == nil){
        if(assign_ident(e->left)){
            fprint(2, "o9c: error: line %d: unknown type for '%s'\n", sem_line, e->left->name);
            (*errs)++;
        }
        return;
    }
    if(typed_member_lookup(lt, e->name, 0, &tm)){
        fprint(2, "o9c: error: line %d: '%s' is a property, not a method\n", sem_line, e->name);
        (*errs)++;
        return;
    }
    if(!typed_member_lookup(lt, e->name, 1, &tm)){
        fprint(2, "o9c: error: line %d: '%s' has no member '%s'\n", sem_line, cnode->name, e->name);
        (*errs)++;
        return;
    }
    if(tm.node == nil)
        return;
    if((tm.node->flags & NFPrivate) && tm.owner != scope_class)
        fprint(2, "o9c: error: line %d: '%s.%s' is private\n", sem_line,
            tm.owner != nil ? tm.owner->name : cnode->name, e->name), (*errs)++;
    typecheck_generic_msg_args(e, &tm, errs);
}

static TypecheckMsgFn typecheck_msg_handlers[] = {
    typecheck_task_msg,
    typecheck_tabula_msg,
    typecheck_mounttable_msg,
    typecheck_list_msg,
    typecheck_dict_msg,
    nil,
};

static void
typecheck_msg_send(Node *e, Node *scope_class, int *errs)
{
    Type *lt;
    int i;

    annotate_expr_type(e, scope_class);
    if(e->left == nil)
        return;
    lt = e->left->typeinfo;
    for(i = 0; typecheck_msg_handlers[i] != nil; i++)
        if(typecheck_msg_handlers[i](e, scope_class, lt, errs))
            return;
    typecheck_generic_msg(e, scope_class, lt, errs);
}

typedef void (*TypecheckExprFn)(Node*, Node*, int*);

static void
typecheck_default(Node *e, Node *scope_class, int *errs)
{
    (void)errs;
    annotate_expr_type(e, scope_class);
}

static void
typecheck_try_defer(Node *e, Node *scope_class, int *errs)
{
    typecheck_expr(e->left, scope_class, errs);
}

static void
typecheck_cast_expr(Node *e, Node *scope_class, int *errs)
{
    validate_type(e->typeinfo, errs);
    typecheck_expr(e->left, scope_class, errs);
    annotate_expr_type(e, scope_class);
    if(!type_castable_semantic(e->typeinfo, e->left != nil ? e->left->typeinfo : nil))
        type_cast_error(e->typeinfo, e->left != nil ? e->left->typeinfo : nil, errs);
}

static void
typecheck_field_decl(Node *e, Node *scope_class, int *errs)
{
    validate_type(e->typeinfo, errs);
    if(type_is_object_boundary_scope(scope_class))
        reject_address_boundary_type(e->typeinfo, errs,
            e->type == NState ? "state field" : "field or parameter",
            e->name);
}

static void
typecheck_validate_only(Node *e, Node *scope_class, int *errs)
{
    (void)scope_class;
    validate_type(e->typeinfo, errs);
}

static void
typecheck_secret_expr(Node *e, Node *scope_class, int *errs)
{
    (void)scope_class;
    fprint(2, "o9c: error: line %d: secret field '%s' must be string\n",
        sem_line, e->name != nil ? e->name : "?");
    (*errs)++;
}

static void
typecheck_method_expr(Node *e, Node *scope_class, int *errs)
{
    validate_type(e->typeinfo, errs);
    if(type_is_object_boundary_scope(scope_class))
        reject_address_boundary_type(e->typeinfo, errs, "method return", e->name);
}

static void
typecheck_object_expr(Node *e, Node *scope_class, int *errs)
{
    (void)scope_class;
    validate_type(e->typeinfo, errs);
    if(!type_is_object_ref(e->typeinfo)){
        fprint(2, "o9c: error: line %d: object '%s' must have class or interface type\n", sem_line,
            e->qname != nil ? e->qname : e->name);
        (*errs)++;
    }
}

static void
typecheck_array_get_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    check_index_key(e, errs);
}

static void
typecheck_chan_send_expr(Node *e, Node *scope_class, int *errs)
{
    Type *et, *at;
    int bad;

    annotate_expr_type(e, scope_class);
    check_channel_direction(scope_class, e->left, 0, errs);
    et = channel_elem_type(scope_class, e->left);
    at = e->right != nil ? e->right->typeinfo : nil;
    bad = type_is_collection(et, "Dict") || type_is_collection(at, "Dict");
    if(bad){
        fprint(2, "o9c: error: line %d: Dict values cannot be sent over channels yet\n",
            sem_line);
        (*errs)++;
        return;
    }
    if(et != nil && !type_assignable_semantic(et, e->right != nil ? e->right->typeinfo : nil))
        type_mismatch_error("send", et, e->right != nil ? e->right->typeinfo : nil, errs);
}

static void
typecheck_chan_recv_expr(Node *e, Node *scope_class, int *errs)
{
    Type *et, *tt;
    int bad;

    annotate_expr_type(e, scope_class);
    check_channel_direction(scope_class, e->right, 1, errs);
    et = channel_elem_type(scope_class, e->right);
    tt = e->left != nil ? e->left->typeinfo : nil;
    bad = type_is_collection(et, "Dict") || type_is_collection(tt, "Dict");
    if(bad){
        fprint(2, "o9c: error: line %d: Dict values cannot be received over channels yet\n",
            sem_line);
        (*errs)++;
        return;
    }
    if(et != nil && !type_assignable_semantic(e->left != nil ? e->left->typeinfo : nil, et))
        type_mismatch_error("receive", e->left != nil ? e->left->typeinfo : nil, et, errs);
}

static void
typecheck_tuple_assign_fields(Node *left, TypeList *right, int *errs)
{
    TypeList *ra;
    Node *la;
    int li;

    for(la = left, ra = right, li = 0;
        la != nil && ra != nil; la = la->next, ra = ra->next, li++){
        if(!type_assignable_semantic(la->typeinfo, ra->type)){
            fprint(2, "o9c: error: line %d: tuple field %d has type %s, target is %s\n",
                sem_line, li + 1,
                ra->type != nil ? type_render(ra->type) : "<unknown>",
                la->typeinfo != nil ? type_render(la->typeinfo) : "<unknown>");
            (*errs)++;
        }
    }
}

static void
typecheck_tuple_assign_expr(Node *e, int *errs)
{
    Type *rt;

    rt = e->right != nil ? e->right->typeinfo : nil;
    if(!type_is_tuple(rt)){
        fprint(2, "o9c: error: line %d: destructuring assignment needs a tuple value\n", sem_line);
        (*errs)++;
        return;
    }
    if(node_list_len(e->left->left) != type_list_len(rt->args)){
        fprint(2, "o9c: error: line %d: tuple destructuring count mismatch\n", sem_line);
        (*errs)++;
        return;
    }
    typecheck_tuple_assign_fields(e->left->left, rt->args, errs);
}

static void
typecheck_plain_assign_expr(Node *e, int *errs)
{
    if(e->left != nil && e->right != nil &&
       !type_assignable_semantic(e->left->typeinfo, e->right->typeinfo))
        type_mismatch_error("assign", e->left->typeinfo, e->right->typeinfo, errs);
}

static void
typecheck_assign_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    check_index_key(e->left, errs);
    if(e->left != nil && e->left->type == NTupleLit)
        typecheck_tuple_assign_expr(e, errs);
    else
        typecheck_plain_assign_expr(e, errs);
}

static void
typecheck_delete_expr(Node *e, Node *scope_class, int *errs)
{
    (void)scope_class;
    if(e->left == nil || e->left->name == nil || get_var_class(e->left->name) == nil){
        fprint(2, "o9c: error: line %d: delete needs a class instance\n", sem_line);
        (*errs)++;
    }
}

static void
typecheck_rawc_expr(Node *e, Node *scope_class, int *errs)
{
    if(scope_class == nil || (scope_class->flags & NFFunction) == 0){
        fprint(2, "o9c: error: line %d: raw C blocks are only allowed inside function bodies\n", sem_line);
        (*errs)++;
    } else
        validate_rawc_boundary(e->name, errs);
}

static void
typecheck_use_expr(Node *e, Node *scope_class, int *errs)
{
    if(scope_class == nil || (scope_class->flags & NFFunction) == 0){
        fprint(2, "o9c: error: line %d: C dependency use blocks are only allowed inside function bodies\n", sem_line);
        (*errs)++;
    } else {
        Node *d;
        for(d = e->left; d != nil; d = d->next)
            use_cdep(d->name, sem_line, errs);
    }
}

static void
typecheck_return_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(current_return_type != nil &&
       !type_assignable_semantic(current_return_type, e->typeinfo))
        type_mismatch_error("return", current_return_type, e->typeinfo, errs);
}

static void
typecheck_numeric_binary(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && !type_numeric_scalar(e->left->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
    if(e->right != nil && !type_numeric_scalar(e->right->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_integral_binary(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && !type_integral_scalar(e->left->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs integer operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
    if(e->right != nil && !type_integral_scalar(e->right->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs integer operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_bool_binary(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if((e->left != nil && !type_is_bool(e->left->typeinfo)) ||
       (e->right != nil && !type_is_bool(e->right->typeinfo))){
        fprint(2, "o9c: error: line %d: operator '%s' needs bool operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_equality_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && e->right != nil &&
       !type_compatible_either(e->left->typeinfo, e->right->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs compatible operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_compare_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if((e->left != nil && !type_numeric_scalar(e->left->typeinfo)) ||
       (e->right != nil && !type_numeric_scalar(e->right->typeinfo))){
        fprint(2, "o9c: error: line %d: operator '%s' needs numeric operands\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_neg_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && !type_numeric_scalar(e->left->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs numeric operand\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_bitnot_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && !type_integral_scalar(e->left->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '%s' needs integer operand\n", sem_line, expr_op_name(e->type));
        (*errs)++;
    }
}

static void
typecheck_not_expr(Node *e, Node *scope_class, int *errs)
{
    annotate_expr_type(e, scope_class);
    if(e->left != nil && !type_is_bool(e->left->typeinfo)){
        fprint(2, "o9c: error: line %d: operator '!' needs bool operand\n", sem_line);
        (*errs)++;
    }
}

static void
typecheck_local_var_expr(Node *e, Node *scope_class, int *errs)
{
    validate_type(e->typeinfo, errs);
    add_decl_type_sym(e);
    annotate_expr_type(e->left, scope_class);
    if(o9_locality_kind(e->cname) >= 0){
        int got;

        typecheck_expr(e->params, scope_class, errs);
        if(e->params == nil || !type_assignable_semantic(type_name("string"), e->params->typeinfo)){
            fprint(2, "o9c: error: line %d: %s declaration requires a string address after @\n",
                sem_line, e->cname);
            (*errs)++;
        }
        if(!o9_type_is_tabula(e->typeinfo)){
            fprint(2, "o9c: error: line %d: remote objects are not supported; only Tabula data may be declared near/far/listener with @\n",
                sem_line);
            (*errs)++;
        }
        if(!is_tabula_new(e->left)){
            fprint(2, "o9c: error: line %d: %s Tabula declaration requires new Tabula(name, columns) @ address\n",
                sem_line, e->cname);
            (*errs)++;
        } else {
            got = node_list_len(e->left->right);
            if(got != 2){
                fprint(2, "o9c: error: line %d: %s Tabula declaration requires new Tabula(name, columns) @ address\n",
                    sem_line, e->cname);
                (*errs)++;
            }
        }
    }
    if(e->left != nil && e->left->type == NClass){
        typecheck_class_new(e->left, scope_class, errs);
    }
    if(e->left != nil && e->left->type == NSelfCall && e->left->name != nil &&
       strcmp(e->left->name, "lookup") == 0){
        if(type_decl_node(e->typeinfo) == nil){
            fprint(2, "o9c: error: line %d: lookup needs a class-typed target\n", sem_line);
            (*errs)++;
        }
    } else if(e->left != nil && !type_assignable_semantic(e->typeinfo, e->left->typeinfo))
        type_mismatch_error("initialize", e->typeinfo, e->left->typeinfo, errs);
}

static TypecheckExprFn typecheck_expr_handlers[NNodeKinds];

static void
init_typecheck_expr_handlers(void)
{
    if(typecheck_expr_handlers[NIdent] != nil)
        return;
    typecheck_expr_handlers[NIdent] = typecheck_ident;
    typecheck_expr_handlers[NTry] = typecheck_try_defer;
    typecheck_expr_handlers[NDefer] = typecheck_try_defer;
    typecheck_expr_handlers[NCast] = typecheck_cast_expr;
    typecheck_expr_handlers[NProp] = typecheck_field_decl;
    typecheck_expr_handlers[NState] = typecheck_field_decl;
    typecheck_expr_handlers[NCap] = typecheck_validate_only;
    typecheck_expr_handlers[NInherit] = typecheck_validate_only;
    typecheck_expr_handlers[NSecret] = typecheck_secret_expr;
    typecheck_expr_handlers[NMethod] = typecheck_method_expr;
    typecheck_expr_handlers[NTupleLit] = typecheck_tuple_lit;
    typecheck_expr_handlers[NClass] = typecheck_class_new;
    typecheck_expr_handlers[NObject] = typecheck_object_expr;
    typecheck_expr_handlers[NPropRead] = typecheck_prop_read;
    typecheck_expr_handlers[NSelfCall] = typecheck_self_call;
    typecheck_expr_handlers[NMsgSend] = typecheck_msg_send;
    typecheck_expr_handlers[NArrayGet] = typecheck_array_get_expr;
    typecheck_expr_handlers[NChanSend] = typecheck_chan_send_expr;
    typecheck_expr_handlers[NChanTry] = typecheck_chan_send_expr;
    typecheck_expr_handlers[NChanRecv] = typecheck_chan_recv_expr;
    typecheck_expr_handlers[NAssign] = typecheck_assign_expr;
    typecheck_expr_handlers[NDelete] = typecheck_delete_expr;
    typecheck_expr_handlers[NRawC] = typecheck_rawc_expr;
    typecheck_expr_handlers[NUse] = typecheck_use_expr;
    typecheck_expr_handlers[NReturn] = typecheck_return_expr;
    typecheck_expr_handlers[NAdd] = typecheck_numeric_binary;
    typecheck_expr_handlers[NSub] = typecheck_numeric_binary;
    typecheck_expr_handlers[NMul] = typecheck_numeric_binary;
    typecheck_expr_handlers[NDiv] = typecheck_numeric_binary;
    typecheck_expr_handlers[NMod] = typecheck_integral_binary;
    typecheck_expr_handlers[NBitAnd] = typecheck_integral_binary;
    typecheck_expr_handlers[NBitOr] = typecheck_integral_binary;
    typecheck_expr_handlers[NBitXor] = typecheck_integral_binary;
    typecheck_expr_handlers[NLshift] = typecheck_integral_binary;
    typecheck_expr_handlers[NRshift] = typecheck_integral_binary;
    typecheck_expr_handlers[NAnd] = typecheck_bool_binary;
    typecheck_expr_handlers[NOr] = typecheck_bool_binary;
    typecheck_expr_handlers[NEq] = typecheck_equality_expr;
    typecheck_expr_handlers[NNe] = typecheck_equality_expr;
    typecheck_expr_handlers[NLt] = typecheck_compare_expr;
    typecheck_expr_handlers[NLe] = typecheck_compare_expr;
    typecheck_expr_handlers[NGt] = typecheck_compare_expr;
    typecheck_expr_handlers[NGe] = typecheck_compare_expr;
    typecheck_expr_handlers[NNeg] = typecheck_neg_expr;
    typecheck_expr_handlers[NBitNot] = typecheck_bitnot_expr;
    typecheck_expr_handlers[NNot] = typecheck_not_expr;
    typecheck_expr_handlers[NLocalVar] = typecheck_local_var_expr;
}

static void
typecheck_expr(Node *e, Node *scope_class, int *errs)
{
    TypecheckExprFn fn;

    if(e == nil) return;
    if(e->line > 0)
        sem_line = e->line;
    init_typecheck_expr_handlers();
    fn = nil;
    if(e->type >= 0 && e->type < NNodeKinds)
        fn = typecheck_expr_handlers[e->type];
    if(fn == nil)
        fn = typecheck_default;
    fn(e, scope_class, errs);
}

static int
is_stored_member_decl(Node *n)
{
    return n != nil && (n->type == NProp || n->type == NState);
}

static int
member_type_is_declaring_class(Node *member, Node *owner)
{
    if(member == nil || owner == nil || member->typeinfo == nil ||
       member->typeinfo->kind != TyName || member->typeinfo->name == nil)
        return 0;
    if(owner->name != nil && strcmp(member->typeinfo->name, owner->name) == 0)
        return 1;
    if(owner->qname != nil && strcmp(member->typeinfo->name, owner->qname) == 0)
        return 1;
    return 0;
}

static void check_node(Node *n, Node *scope_class, int *errs);

static void
check_module_node(Node *c, Node *scope_class, int *errs)
{
    check_node(c->left, scope_class, errs);
}

static void
check_enum_node(Node *c, Node *scope_class, int *errs)
{
    (void)c;
    (void)scope_class;
    (void)errs;
}

static void
check_self_member_decl(Node *c, Node *m, int *errs)
{
    if(is_stored_member_decl(m) && member_type_is_declaring_class(m, c)){
        fprint(2, "o9c: error: line %d: class '%s' cannot directly contain itself as field '%s'\n",
            m->line > 0 ? m->line : sem_line,
            c->qname != nil ? c->qname : c->name,
            m->name != nil ? m->name : "?");
        (*errs)++;
    }
}

static void
check_self_member_decls(Node *c, int *errs)
{
    Node *m;

    for(m = c->left; m != nil; m = m->next)
        check_self_member_decl(c, m, errs);
}

static void
check_type_decl_node(Node *c, Node *scope_class, int *errs)
{
    (void)scope_class;
    push_type_params(c->params);
    check_self_member_decls(c, errs);
    check_node(c->left, c, errs);
    check_inheritance_contract(c, errs);
    pop_type_params();
}

static void
check_set_constructor_scope(Node *m, Node *scope_class, int *saved_ctor)
{
    *saved_ctor = in_constructor_body;
    in_constructor_body = (scope_class != nil && m->name != nil &&
        scope_class->name != nil && strcmp(m->name, scope_class->name) == 0);
    if(in_constructor_body)
        ctor_class_name = scope_class->name;
}

static void
check_restore_constructor_scope(int saved_ctor)
{
    in_constructor_body = saved_ctor;
    if(!saved_ctor)
        ctor_class_name = nil;
}

static void
check_method_node(Node *c, Node *scope_class, int *errs)
{
    TypeSym *mark;
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
    /* A constructor is a method named after its class. Constructing an object
     * inside a constructor is forbidden because half-built state is hard to
     * reason about; flag it so NClass can reject it. */
    check_set_constructor_scope(c, scope_class, &saved_ctor);
    check_node(c->left, scope_class, errs);
    check_restore_constructor_scope(saved_ctor);
    current_return_type = saved_return;
    restore_type_syms(mark);
}

static void
check_use_node(Node *c, Node *scope_class, int *errs)
{
    typecheck_expr(c, scope_class, errs);
}

static void
check_stream_node(Node *c, Node *scope_class, int *errs)
{
    (void)scope_class;
    if(c->typeinfo != nil && c->typename != nil &&
        strcmp(c->typename, "chan") != 0)
        validate_type(c->typeinfo, errs);
    if(type_is_collection(c->typeinfo, "Dict")){
        fprint(2, "o9c: error: line %d: Dict values cannot be used as channel payloads yet\n",
            c->line > 0 ? c->line : sem_line);
        (*errs)++;
    }
}

static void
check_alt_case_node(Node *a, Node *scope_class, int *errs, int *ndefault)
{
    if(a->line > 0)
        sem_line = a->line;
    if(a->type == NAltCase){
        typecheck_expr(a->left, scope_class, errs);
        check_node(a->right, scope_class, errs);
    } else if(a->type == NAltDefault){
        (*ndefault)++;
        check_node(a->left, scope_class, errs);
    }
}

static void
check_alt_node(Node *c, Node *scope_class, int *errs)
{
    Node *a;
    int ndefault;

    ndefault = 0;
    for(a = c->left; a != nil; a = a->next)
        check_alt_case_node(a, scope_class, errs, &ndefault);
    if(ndefault > 1){
        fprint(2, "o9c: error: line %d: alt has %d default cases; only one is allowed\n",
            sem_line, ndefault);
        (*errs)++;
    }
}

static void
check_default_node(Node *c, Node *scope_class, int *errs)
{
    typecheck_expr(c, scope_class, errs);
    check_node(c->left, scope_class, errs);
    check_node(c->right, scope_class, errs);
}

typedef void (*CheckNodeFn)(Node*, Node*, int*);
typedef struct CheckNodeCase CheckNodeCase;
struct CheckNodeCase {
    int kind;
    CheckNodeFn fn;
};

static CheckNodeCase check_node_cases[] = {
    { NModule, check_module_node },
    { NEnum, check_enum_node },
    { NClass, check_type_decl_node },
    { NStruct, check_type_decl_node },
    { NInterface, check_type_decl_node },
    { NMethod, check_method_node },
    { NUse, check_use_node },
    { NStream, check_stream_node },
    { NAlt, check_alt_node },
    { -1, nil },
};

static void
check_one_node(Node *c, Node *scope_class, int *errs)
{
    int i;

    for(i = 0; check_node_cases[i].kind >= 0; i++){
        if(check_node_cases[i].kind == c->type){
            check_node_cases[i].fn(c, scope_class, errs);
            return;
        }
    }
    check_default_node(c, scope_class, errs);
}

static void
check_node(Node *n, Node *scope_class, int *errs)
{
    Node *c;

    if(n == nil)
        return;
    if(n->line > 0)
        sem_line = n->line;
    for(c = n; c; c = c->next)
        check_one_node(c, scope_class, errs);
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

/* ========================================================================
 * AST DUMP
 * ======================================================================== */

static char*
node_kind(int type)
{
    static char *names[NNodeKinds] = {
        "NClass",
        "NProp",
        "NState",
        "NStream",
        "NSecret",
        "NCap",
        "NInherit",
        "NMethod",
        "NDestructor",
        "NIdent",
        "NType",
        "NChanSend",
        "NChanRecv",
        "NChanTry",
        "NAssign",
        "NReturn",
        "NIntLit",
        "NDoubleLit",
        "NStringLit",
        "NCharLit",
        "NBoolLit",
        "NAdd",
        "NSub",
        "NMul",
        "NDiv",
        "NMod",
        "NEq",
        "NNe",
        "NLt",
        "NLe",
        "NGt",
        "NGe",
        "NAnd",
        "NOr",
        "NBitAnd",
        "NBitOr",
        "NBitXor",
        "NLshift",
        "NRshift",
        "NNot",
        "NBitNot",
        "NNeg",
        "NIf",
        "NIfElse",
        "NElse",
        "NElseIf",
        "NWhile",
        "NLocalVar",
        "NMsgSend",
        "NPropRead",
        "NFuncCall",
        "NFor",
        "NArrayGet",
        "NArraySet",
        "NInterface",
        "NStruct",
        "NEnum",
        "NEnumVal",
        "NImport",
        "NObject",
        "NLink",
        "NModule",
        "NTypeParam",
        "NSelfCall",
        "NDelete",
        "NTry",
        "NDefer",
        "NSpawn",
        "NCast",
        "NRawC",
        "NUse",
        "NAlt",
        "NAltCase",
        "NAltDefault",
        "NTupleLit",
    };

    if(type >= 0 && type < NNodeKinds && names[type] != nil)
        return names[type];
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
    if(n->flags & NFChanSendOnly)
        print(" sendonly");
    if(n->flags & NFChanRecvOnly)
        print(" recvonly");
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

/* ========================================================================
 * IMPORT RESOLUTION
 * ======================================================================== */
/* ---- import resolution (see docs/IMPORTS.md) ----
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

/* ========================================================================
 * C DEPENDENCY LOADING
 * ======================================================================== */

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
    { "event",    "<event.h>",    nil, "draw" },
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

static int
project_deps_skip_line(char *s)
{
    if(s[0] == '\0' || s[0] == '#')
        return 1;
    return s[0] == '/' && s[1] == '/';
}

static int
project_deps_keyval(char *linebuf, char **key, char **val, int line)
{
    char *s, *eq;

    s = trim_ws(linebuf);
    if(project_deps_skip_line(s))
        return 0;
    eq = strchr(s, '=');
    if(eq == nil){
        fprint(2, "o9c: error: line %d: deps.tab line needs key=value\n", line);
        semantic_errors++;
        return 0;
    }
    *eq = '\0';
    *key = trim_ws(s);
    *val = unquote_value(eq + 1);
    return 1;
}

static char**
project_cdep_slot(CDep *cur, char *key)
{
    if(strcmp(key, "header") == 0)
        return &cur->header;
    if(strcmp(key, "include") == 0)
        return &cur->include;
    if(strcmp(key, "archive") == 0)
        return &cur->archive;
    if(strcmp(key, "source") == 0)
        return &cur->source;
    if(strcmp(key, "requires") == 0)
        return &cur->requires;
    return nil;
}

static int
project_cdep_bool(char *val)
{
    return strcmp(val, "true") == 0 || strcmp(val, "1") == 0 ||
        strcmp(val, "yes") == 0;
}

static int
project_cdep_set_field(CDep *cur, char *key, char *val, int line)
{
    char **slot;

    slot = project_cdep_slot(cur, key);
    if(slot != nil){
        *slot = strdup(val);
        return 1;
    }
    if(strcmp(key, "override") == 0){
        cur->override = project_cdep_bool(val);
        return 1;
    }
    if(strcmp(key, "kind") == 0){
        if(strcmp(val, "project") != 0){
            fprint(2, "o9c: error: line %d: deps.tab kind must be project\n", line);
            semantic_errors++;
        }
        return 1;
    }
    return 0;
}

static void
project_cdep_apply_line(CDep **cur, int *rowline, char *key, char *val, int line)
{
    if(strcmp(key, "name") == 0){
        finish_project_cdep(*cur, *rowline);
        *cur = new_cdep(val, 0);
        *rowline = line;
        return;
    }
    if(*cur == nil){
        fprint(2, "o9c: error: line %d: deps.tab field '%s' appears before name\n",
            line, key);
        semantic_errors++;
        return;
    }
    if(project_cdep_set_field(*cur, key, val, line))
        return;
    fprint(2, "o9c: error: line %d: deps.tab unknown field '%s'\n", line, key);
    semantic_errors++;
}

static void
load_project_cdeps(void)
{
    char path[1024], linebuf[1024], *buf, *p, *nl, *key, *val;
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
        if(project_deps_keyval(linebuf, &key, &val, line))
            project_cdep_apply_line(&cur, &rowline, key, val, line);
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
    if(d->requires != nil && d->requires[0] != '\0'){
        reqs = strdup(d->requires);
        for(p = reqs; *p != '\0'; p++)
            if(*p == ',')
                *p = ' ';
        for(tok = strtok(reqs, " \t\r\n"); tok != nil; tok = strtok(nil, " \t\r\n"))
            use_cdep_inner(tok, line, errs, depth + 1);
        free(reqs);
    }
    mark_cdep_used(d);
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
    int hasevent;

    hasevent = 0;
    for(d = used_cdeps; d != nil; d = d->usednext){
        if(strcmp(d->name, "event") == 0)
            hasevent = 1;
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
    if(hasevent)
        print("static int o9_draw_resized;\nstatic int o9_draw_width;\nstatic int o9_draw_height;\n\nvoid\neresized(int new)\n{\n\tif(new && getwindow(display, Refnone) < 0)\n\t\tsysfatal(\"cannot reattach draw window\");\n\tif(screen != nil){\n\t\to9_draw_resized = 1;\n\t\to9_draw_width = Dx(screen->r);\n\t\to9_draw_height = Dy(screen->r);\n\t}\n}\n\n");
}

/* ========================================================================
 * IMPORT RESOLUTION CONTINUED
 * ======================================================================== */

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

/* ========================================================================
 * COMPILER MAIN
 * ======================================================================== */

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
