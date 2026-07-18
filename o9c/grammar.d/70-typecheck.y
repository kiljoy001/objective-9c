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

static int
rawc_ident_start(int c)
{
    return isalpha((uchar)c) || c == '_';
}

static int
rawc_ident_char(int c)
{
    return isalnum((uchar)c) || c == '_';
}

static int
rawc_scan_boundary_normal(char *src, int *i, int *mode, int *esc)
{
    int c;

    c = src[*i];
    if(c == '"'){
        *mode = RawString;
        *esc = 0;
        return 1;
    }
    if(c == '\''){
        *mode = RawChar;
        *esc = 0;
        return 1;
    }
    if(c == '/' && src[*i+1] == '/'){
        *mode = RawLineComment;
        (*i)++;
        return 1;
    }
    if(c == '/' && src[*i+1] == '*'){
        *mode = RawBlockComment;
        (*i)++;
        return 1;
    }
    return 0;
}

static int
rawc_scan_boundary_quote(char *src, int *i, int *mode, int *esc)
{
    int c;

    c = src[*i];
    if(*esc){
        *esc = 0;
        return 1;
    }
    if(c == '\\'){
        *esc = 1;
        return 1;
    }
    if((*mode == RawString && c == '"') || (*mode == RawChar && c == '\''))
        *mode = RawNormal;
    return 1;
}

static int
rawc_scan_boundary_comment(char *src, int *i, int *mode)
{
    int c;

    c = src[*i];
    if(*mode == RawLineComment){
        if(c == '\n')
            *mode = RawNormal;
        return 1;
    }
    if(c == '*' && src[*i+1] == '/'){
        *mode = RawNormal;
        (*i)++;
    }
    return 1;
}

static int
rawc_scan_boundary_mode(char *src, int *i, int *mode, int *esc)
{
    switch(*mode){
    case RawNormal:
        return rawc_scan_boundary_normal(src, i, mode, esc);
    case RawString:
    case RawChar:
        return rawc_scan_boundary_quote(src, i, mode, esc);
    case RawLineComment:
    case RawBlockComment:
        return rawc_scan_boundary_comment(src, i, mode);
    }
    return 0;
}

static void
rawc_copy_ident(char *src, int *i, char *id, int nid)
{
    int j;

    j = 0;
    do {
        if(j < nid - 1)
            id[j++] = src[*i];
        (*i)++;
    } while(rawc_ident_char((uchar)src[*i]));
    id[j] = '\0';
    (*i)--;
}

static void
rawc_check_ident(char *id, int *errs)
{
    char *why;

    why = nil;
    if(rawc_forbidden_ident(id, &why)){
        fprint(2, "o9c: error: line %d: raw C block uses forbidden o9 internal symbol '%s' "
            "(raw C may use Plan 9 C and local values, not generated object internals)\n",
            sem_line, why);
        (*errs)++;
    }
}

static void
validate_rawc_boundary(char *src, int *errs)
{
    int i, mode, esc;
    char id[256];

    if(src == nil)
        return;
    mode = RawNormal;
    esc = 0;
    for(i = 0; src[i] != '\0'; i++){
        if(rawc_scan_boundary_mode(src, &i, &mode, &esc))
            continue;
        if(rawc_ident_start((uchar)src[i])){
            rawc_copy_ident(src, &i, id, sizeof id);
            rawc_check_ident(id, errs);
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
    return set_expr_type(e, type_name("void"));
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
check_interface_member_contract(Node *cnode, Node *m, int *errs)
{
    if(cnode == nil || m == nil || cnode->type != NInterface)
        return;
    if(m->type != NMethod && m->type != NInherit){
        fprint(2, "o9c: error: line %d: interface '%s' may only declare methods or inherit interfaces\n", sem_line,
            cnode->name);
        (*errs)++;
        return;
    }
    if(m->type == NMethod && (m->flags & NFMethodDecl) == 0){
        fprint(2, "o9c: error: line %d: interface method '%s' cannot have a body\n", sem_line, m->name);
        (*errs)++;
    }
}

static void
check_inherit_member_contract(Node *cnode, Node *m, int *classparents, int *errs)
{
    Node *parent;
    Type *pt;

    if(cnode == nil || m == nil || m->type != NInherit)
        return;
    pt = inherit_type_with_bindings(m, nil);
    parent = type_decl_node(pt);
    if(parent == nil)
        return;
    if(parent == cnode || is_subclass(parent->name, cnode->name)){
        fprint(2, "o9c: error: line %d: inheritance cycle involving '%s'\n", sem_line, cnode->name);
        (*errs)++;
    }
    if(cnode->type == NStruct){
        fprint(2, "o9c: error: line %d: struct '%s' cannot inherit '%s'\n", sem_line, cnode->name, m->name);
        (*errs)++;
        return;
    }
    if(cnode->type == NInterface){
        if(parent->type != NInterface){
            fprint(2, "o9c: error: line %d: interface '%s' can only inherit interfaces\n", sem_line, cnode->name);
            (*errs)++;
        }
        return;
    }
    if(parent->type == NStruct || parent->type == NEnum){
        fprint(2, "o9c: error: line %d: class '%s' cannot inherit non-class/interface '%s'\n", sem_line,
            cnode->name, m->name);
        (*errs)++;
        return;
    }
    if(parent->type == NClass){
        (*classparents)++;
        if(*classparents > 1){
            fprint(2, "o9c: error: line %d: class '%s' cannot inherit more than one class\n", sem_line, cnode->name);
            (*errs)++;
        }
    }
}

static void
check_concrete_contract_impls(Node *cnode, int *errs)
{
    Node *m, *parent;
    Type *pt;
    TypeBind *pb;

    if(cnode == nil || cnode->type != NClass || (cnode->flags & NFAbstract) != 0)
        return;
    for(m = cnode->left; m; m = m->next){
        if(m->line > 0)
            sem_line = m->line;
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

static void
check_inheritance_contract(Node *cnode, int *errs)
{
    Node *m;
    int classparents;

    if(cnode == nil || (cnode->type != NClass && cnode->type != NStruct && cnode->type != NInterface))
        return;

    check_local_member_conflicts(cnode, errs);
    classparents = 0;
    for(m = cnode->left; m; m = m->next){
        if(m->line > 0)
            sem_line = m->line;
        check_interface_member_contract(cnode, m, errs);
        check_inherit_member_contract(cnode, m, &classparents, errs);
    }
    check_override_compat(cnode, errs);
    check_concrete_contract_impls(cnode, errs);
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
typecheck_typed_member_args(Node *e, TypedMember *tm, int *errs)
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
    typecheck_typed_member_args(e, tm, errs);
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
    typecheck_typed_member_args(e, &tm, errs);
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
    if(e->left->type == NMsgSend && type_is_class_ref(e->left->typeinfo)){
        typecheck_expr(e->left, scope_class, errs);
        fprint(2, "o9c: error: line %d: object-return method result cannot be used as a receiver "
            "(bind it to a named value first)\n", sem_line);
        (*errs)++;
        return;
    }
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
typecheck_locality_addr(Node *e, Node *scope_class, int *errs)
{
    typecheck_expr(e->params, scope_class, errs);
    if(e->params == nil || !type_assignable_semantic(type_name("string"), e->params->typeinfo)){
        fprint(2, "o9c: error: line %d: %s declaration requires a string address after @\n",
            sem_line, e->cname);
        (*errs)++;
    }
}

static void
typecheck_locality_tabula_type(Node *e, int *errs)
{
    if(!o9_type_is_tabula(e->typeinfo)){
        fprint(2, "o9c: error: line %d: remote objects are not supported; only Tabula data may be declared near/far/listener with @\n",
            sem_line);
        (*errs)++;
    }
}

static void
typecheck_locality_tabula_ctor(Node *e, int *errs)
{
    int got;

    if(!is_tabula_new(e->left)){
        fprint(2, "o9c: error: line %d: %s Tabula declaration requires new Tabula(name, columns) @ address\n",
            sem_line, e->cname);
        (*errs)++;
        return;
    }
    got = node_list_len(e->left->right);
    if(got != 2){
        fprint(2, "o9c: error: line %d: %s Tabula declaration requires new Tabula(name, columns) @ address\n",
            sem_line, e->cname);
        (*errs)++;
    }
}

static void
typecheck_locality_decl(Node *e, Node *scope_class, int *errs)
{
    if(o9_locality_kind(e->cname) < 0)
        return;
    typecheck_locality_addr(e, scope_class, errs);
    typecheck_locality_tabula_type(e, errs);
    typecheck_locality_tabula_ctor(e, errs);
}

static void
typecheck_lookup_target(Node *e, int *errs)
{
    if(e->left == nil || e->left->type != NSelfCall || e->left->name == nil)
        return;
    if(strcmp(e->left->name, "lookup") != 0)
        return;
    if(type_decl_node(e->typeinfo) == nil){
        fprint(2, "o9c: error: line %d: lookup needs a class-typed target\n", sem_line);
        (*errs)++;
    }
}

static void
typecheck_local_initializer(Node *e, int *errs)
{
    if(e->left == nil)
        return;
    if(e->left->type == NSelfCall && e->left->name != nil &&
       strcmp(e->left->name, "lookup") == 0)
        return;
    if(!type_assignable_semantic(e->typeinfo, e->left->typeinfo))
        type_mismatch_error("initialize", e->typeinfo, e->left->typeinfo, errs);
}

static void
typecheck_local_var_expr(Node *e, Node *scope_class, int *errs)
{
    validate_type(e->typeinfo, errs);
    add_decl_type_sym(e);
    annotate_expr_type(e->left, scope_class);
    typecheck_locality_decl(e, scope_class, errs);
    if(e->left != nil && e->left->type == NClass)
        typecheck_class_new(e->left, scope_class, errs);
    typecheck_lookup_target(e, errs);
    typecheck_local_initializer(e, errs);
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
