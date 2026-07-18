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
    /* export(name, tab): publish a tabula into the served-tree exports/
     * dir (mutable app file tree) — reachable through the mount. */
    {"export",    "o9_export_tab",2, "void",   {"string", "tabula"}},
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
o9_type_name_is_tabula(char *name)
{
    return name != nil &&
        (strcmp(name, "tabula") == 0 || strcmp(name, "Tabula") == 0);
}

static int
o9_type_is_tabula(Type *t)
{
    return t != nil && t->kind == TyName && t->name != nil &&
        o9_type_name_is_tabula(t->name);
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
