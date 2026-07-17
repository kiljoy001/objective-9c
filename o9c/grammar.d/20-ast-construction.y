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
