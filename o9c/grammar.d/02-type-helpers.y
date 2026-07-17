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
