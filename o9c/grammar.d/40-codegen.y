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

static void gen_msg_receiver_ref(Node *recv);

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
    gen_msg_receiver_ref(recv);
    print(")->shm_base");
    return 1;
}

static int
gen_class_ref_lvalue(Node *e)
{
    Type *rt;
    char *cn;
    Node *cnode;

    if(e == nil || e->type != NPropRead || e->name == nil)
        return 0;
    if(!type_is_class_ref(e->typeinfo))
        return 0;
    rt = e->left != nil ? e->left->typeinfo : nil;
    cn = rt != nil ? type_cname(rt) : nil;
    cnode = type_decl_node(rt);
    if(cn == nil || cnode == nil)
        return 0;
    if(cnode->type != NClass && cnode->type != NInterface)
        return 0;
    print("((%s_Internal*)((%s_Client*)&", cn, cn);
    if(!gen_class_ref_lvalue(e->left))
        gen_expr(e->left);
    print(")->shm_base)->%s", e->name);
    return 1;
}

static void
gen_msg_receiver_ref(Node *recv)
{
    if(type_is_class_ref(recv != nil ? recv->typeinfo : nil) && gen_class_ref_lvalue(recv))
        return;
    gen_expr(recv);
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
    gen_msg_receiver_ref(e->left);
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
    gen_msg_receiver_ref(e->left);
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
        ops[NMod] = " % ";
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
gen_func_call_expr(Node *e)
{
    gen_print_expr(e);
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

static Node*
discard_value_expr(Node *e)
{
    Node *ve;

    ve = e != nil ? e : nil;
    if(ve != nil && ve->type == NTry)
        ve = ve->left;
    return ve;
}

static int
discard_msgsend_is_cvoid(Node *ve)
{
    Type *lt;

    if(ve == nil || ve->type != NMsgSend || !type_is_void(ve->typeinfo))
        return 0;
    lt = ve->left != nil ? ve->left->typeinfo : nil;
    /* Normal object sends lower to a vlong dispatch expression even for
     * o9 void methods. Builtin handle methods can lower directly to C
     * void helpers. */
    return lt != nil && lt->kind == TyName && lt->name != nil &&
        (strcmp(lt->name, "Tabula") == 0 || strcmp(lt->name, "MountTable") == 0);
}

static int
discard_expr_is_cvoid(Node *e)
{
    Node *ve;

    ve = discard_value_expr(e);
    if(ve == nil)
        return 1;
    if(ve->type == NMsgSend)
        return discard_msgsend_is_cvoid(ve);
    return type_is_void(ve->typeinfo);
}

static void
gen_discard_value(Node *e)
{
    int id;

    id = new_tmp_id++;
    print("\t{ vlong __o9discard%d;\n\t__o9discard%d = (vlong)(", id, id);
    gen_expr(e);
    print(");\n\tUSED(__o9discard%d);\n\t}\n", id);
}

static void
gen_discard_expr_stmt(Node *e)
{
    if(e == nil){
        print("\t;\n");
        return;
    }
    if(discard_expr_is_cvoid(e)){
        print("\t");
        gen_expr(e);
        print(";\n");
        return;
    }
    gen_discard_value(e);
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

static void
gen_assign_table_name(char *tbl, int ntbl, char *varname, int is_field)
{
    if(is_field)
        snprint(tbl, ntbl, "__o9tbl%d", new_tmp_id);
    else
        snprint(tbl, ntbl, "%s_tbl", varname);
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
    dval = -1;
    nctor = node_arg_count(n->right);

    if(is_field)
        print("\to9_AsmTable %s;\n", tbl);
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

static int
gen_local_new_class_stmt(Node *s, char *cname, int is_new)
{
    if(!is_new || cname == nil)
        return 0;
    gen_local_new(s, cname, -1);
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

typedef int (*StateStoreFn)(char*, char*, char*, Type*);

static int
state_store_dict(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    if(!type_is_dict(type))
        return 0;
    print("\t{ char *__o9s = o9_dict_serialize(&%s); o9_state_set(%s, \"%s\", __o9s); free(__o9s); }\n",
        fieldexpr, stateexpr, name);
    return 1;
}

static int
state_store_collection(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    USED(stateexpr);
    USED(fieldexpr);
    USED(name);
    return type_is_list(type) || type_is_array(type);
}

static int
state_store_char_pointer(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    if(!type_is_char_pointer(type))
        return 0;
    print("\to9_state_set(%s, \"%s\", %s ? %s : \"\");\n",
        stateexpr, name, fieldexpr, fieldexpr);
    return 1;
}

static int
state_store_string(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    if(!type_is_string(type))
        return 0;
    print("\to9_state_set(%s, \"%s\", o9_string_data(%s));\n",
        stateexpr, name, fieldexpr);
    return 1;
}

static int
state_store_double(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    if(!type_is_double(type))
        return 0;
    print("\t{ char __o9dbuf[64]; snprint(__o9dbuf, sizeof __o9dbuf, \"%%g\", %s); o9_state_set(%s, \"%s\", __o9dbuf); }\n",
        fieldexpr, stateexpr, name);
    return 1;
}

static int
state_store_complex_decl(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    Node *d;

    USED(stateexpr);
    USED(fieldexpr);
    USED(name);
    d = type_decl_node(type);
    return d != nil && (d->type == NStruct || d->type == NClass || d->type == NInterface);
}

static void
state_store_int(char *stateexpr, char *fieldexpr, char *name)
{
    print("\to9_state_set_int(%s, \"%s\", (vlong)(%s));\n",
        stateexpr, name, fieldexpr);
}

static StateStoreFn state_store_handlers[] = {
    state_store_dict,
    state_store_collection,
    state_store_char_pointer,
    state_store_string,
    state_store_double,
    state_store_complex_decl,
};

void
gen_state_store_typed(char *stateexpr, char *fieldexpr, char *name, Type *type)
{
    int i;

    if(stateexpr == nil || fieldexpr == nil || name == nil || type == nil)
        return;
    for(i = 0; i < nelem(state_store_handlers); i++)
        if(state_store_handlers[i](stateexpr, fieldexpr, name, type))
            return;
    state_store_int(stateexpr, fieldexpr, name);
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

void gen_type_metadata_entries_buf(Node *c, char *bufname);

static int
metadata_is_field_member(Node *m)
{
    return m != nil && (m->type == NProp || m->type == NState ||
        m->type == NSecret || m->type == NCap);
}

static int
metadata_field_visible(Node *m)
{
    return metadata_is_field_member(m) && (m->flags & NFPrivate) == 0;
}

static int
metadata_method_visible(Node *c, Node *m)
{
    if(m == nil || m->type != NMethod)
        return 0;
    /* Facade-reachable status is external API, so private methods and
     * constructors must not appear. */
    if(m->flags & NFPrivate)
        return 0;
    if(m->name != nil && c != nil && c->name != nil && strcmp(m->name, c->name) == 0)
        return 0;
    return 1;
}

static void
gen_type_metadata_class_entry(Node *c, char *bufname)
{
    print("\t\tp += snprint(p, sizeof %s - (p-%s), \"class name=%s qname=%s cname=%s typename=%s\\n\");\n",
        bufname,
        bufname,
        c->name != nil ? c->name : "",
        c->qname != nil ? c->qname : "",
        c->cname != nil ? c->cname : "",
        metadata_typename(c));
}

static void
gen_type_metadata_field_entry(Node *m, char *bufname)
{
    char *typetext, *storage;

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

static void
gen_type_metadata_param_entry(Node *m, Node *a, char *bufname)
{
    char *typetext, *storage;

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

static void
gen_type_metadata_method_entry(Node *m, char *bufname)
{
    Node *a;
    char *typetext, *storage;
    int argc;

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
    for(a = m->right; a; a = a->next)
        gen_type_metadata_param_entry(m, a, bufname);
}

static void
gen_type_metadata_member(Node *c, Node *m, char *bufname)
{
    Node *p;

    if(m->type == NInherit){
        p = find_class(m->name);
        if(p != nil)
            gen_type_metadata_entries_buf(p, bufname);
        return;
    }
    if(metadata_field_visible(m)){
        gen_type_metadata_field_entry(m, bufname);
        return;
    }
    if(metadata_method_visible(c, m))
        gen_type_metadata_method_entry(m, bufname);
}

void
gen_type_metadata_entries_buf(Node *c, char *bufname)
{
    Node *m;

    if(c == nil)
        return;
    gen_type_metadata_class_entry(c, bufname);
    for(m = c->left; m; m = m->next)
        gen_type_metadata_member(c, m, bufname);
}

void
gen_type_metadata_entries(Node *c)
{
    gen_type_metadata_entries_buf(c, "typebuf");
}

static ulong emitted_hashes[1024];
static int num_emitted = 0;

void gen_dispatch_cases(Node *c, char *childname);

static int
dispatch_hash_seen(ulong h)
{
    int i;

    for(i = 0; i < num_emitted; i++)
        if(emitted_hashes[i] == h)
            return 1;
    return 0;
}

static void
dispatch_note_hash(ulong h)
{
    emitted_hashes[num_emitted++] = h;
}

static void
gen_dispatch_case(Node *c, Node *m, ulong h)
{
    print("\t\tcase 0x%lux: o9_impl_%s_%s((%s_Internal*)self, m); break;\n",
        h, c->name, m->name, c->name);
    dispatch_note_hash(h);
}

static int
dispatch_needs_ctor_alias(Node *c, Node *m, char *childname)
{
    if(childname == nil)
        return 0;
    return strcmp(m->name, c->name) == 0 && strcmp(c->name, childname) != 0;
}

static void
gen_dispatch_ctor_alias(Node *c, Node *m, char *childname)
{
    ulong h;

    if(!dispatch_needs_ctor_alias(c, m, childname))
        return;
    h = o9_hash(childname);
    if(dispatch_hash_seen(h))
        return;
    print("\t\tcase 0x%lux: o9_impl_%s_%s((%s_Internal*)self, m); break;\t/* inherited ctor as %s */\n",
        h, c->name, m->name, c->name, childname);
    dispatch_note_hash(h);
}

static void
gen_dispatch_method_case(Node *c, Node *m, char *childname)
{
    ulong h;

    if(m->type != NMethod || !method_has_body(m))
        return;
    gen_dispatch_ctor_alias(c, m, childname);
    h = o9_hash(m->name);
    if(!dispatch_hash_seen(h))
        gen_dispatch_case(c, m, h);
}

static void
gen_dispatch_member_cases(Node *c, char *childname)
{
    Node *m;

    for(m = c->left; m; m = m->next)
        gen_dispatch_method_case(c, m, childname);
}

static Node*
dispatch_parent_class(Node *m)
{
    Node *p;

    if(m->type != NInherit)
        return nil;
    p = find_class(m->name);
    if(p == nil || p->type != NClass || (p->flags & NFAbstract))
        return nil;
    return p;
}

static void
gen_dispatch_inherited_cases(Node *c, char *childname)
{
    Node *m, *p;

    for(m = c->left; m; m = m->next){
        p = dispatch_parent_class(m);
        if(p != nil)
            gen_dispatch_cases(p, childname);
    }
}

void
gen_dispatch_cases(Node *c, char *childname)
{
    if(c == nil)
        return;
    gen_dispatch_member_cases(c, childname);
    gen_dispatch_inherited_cases(c, childname);
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

static Node*
spawn_run_method(Node *c)
{
    Node *m;

    for(m = c->left; m != nil; m = m->next)
        if(m->type == NMethod && m->name != nil && strcmp(m->name, "run") == 0)
            return m;
    return nil;
}

static int
spawn_method_param_count(Node *m)
{
    Node *pn;
    int n;

    n = 0;
    for(pn = (m ? m->right : nil); pn; pn = pn->next)
        n++;
    return n;
}

static void
gen_spawn_context_type(Node *c)
{
    print("typedef struct O9SpawnCtx_%s { Channel *replyc; O9Task *task; %s_Internal *inst; } O9SpawnCtx_%s;\n",
        c->name, c->name, c->name);
}

static void
gen_spawn_forward_proc(Node *c)
{
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
}

static void
gen_spawn_signature(Node *c, Node *rm, int np)
{
    Node *pn;
    int pi;

    print("O9Task *o9_spawn_%s(", c->name);
    for(pn = (rm ? rm->right : nil), pi = 0; pn; pn = pn->next, pi++){
        if(pi) print(", ");
        print("%s __a%d", type_storage_for_codegen(pn->typeinfo), pi);
    }
    if(np == 0) print("void");
    print("){\n");
}

static void
gen_spawn_instance_setup(Node *c)
{
    char ptr[64];

    print("\tint __id = o9_spawn_id_%s++;\n", c->name);
    print("\tchar __nm[64]; snprint(__nm, sizeof __nm, \"%s#%%d\", __id);\n", c->name);
    print("\tO9Task *__task = o9_task_new(__id);\n");
    print("\t%s_Internal *__inst = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
    print("\tmemset(__inst, 0, sizeof(%s_Internal));\n", c->name);
    print("\t__inst->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\t__inst->distance = -1;\n");
    print("\t__inst->state = o9_state_create_path(o9app_root, \"%s\", __nm, o9_state_cols_%s, %d);\n",
        c->name, c->name, count_state_cols(c));
    snprint(ptr, sizeof ptr, "__inst");
    gen_init_internal_state(c, ptr);
    print("\t__inst->__spawn_index = __id;\n");
    print("\t__inst->__spawn_state = 1;\t/* running */\n");
    print("\tproccreate(%s_loop, __inst, 65536);\n", c->name);
    print("\t%s_record_instance(__nm, __inst);\n", c->name);
    print("\tChannel *__replyc = chancreate(sizeof(void*), 1);\n");
}

static void
gen_spawn_arg_pack(Node *rm, int np)
{
    Node *pn;
    int pi;

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
}

static void
gen_spawn_run_send(int np)
{
    print("\t{ O9Msg *__wm = mallocz(sizeof(O9Msg), 1);\n");
    print("\t  __wm->sel = 0x%lux; __wm->args = %s; __wm->nargs = %d; __wm->replyc = __replyc;\n",
        o9_hash("run"), np > 0 ? "__args" : "nil", np);
    print("\t  sendp(__inst->dispatch_chan, __wm); }\n");
}

static void
gen_spawn_forward_start(Node *c)
{
    print("\t{ O9SpawnCtx_%s *__ctx = mallocz(sizeof(O9SpawnCtx_%s), 1);\n", c->name, c->name);
    print("\t  __ctx->replyc = __replyc; __ctx->task = __task; __ctx->inst = __inst;\n");
    print("\t  proccreate(o9_spawn_forward_%s, __ctx, 32*1024); }\n", c->name);
}

static void
gen_class_spawn_helper(Node *c)
{
    Node *rm;
    int np;

    if((c->flags & NFFunction) == 0)
        return;
    rm = spawn_run_method(c);
    np = spawn_method_param_count(rm);
    gen_spawn_context_type(c);
    gen_spawn_forward_proc(c);
    gen_spawn_signature(c, rm, np);
    gen_spawn_instance_setup(c);
    gen_spawn_arg_pack(rm, np);
    gen_spawn_run_send(np);
    gen_spawn_forward_start(c);
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
gen_class_ctl_arity_check(Node *m, int np)
{
    /* ARITY (finding #5): a network boundary must not silently default
     * missing args to 0 or ignore extras. Require exactly np args after
     * `method Class.inst name` (tokens f[3..]). */
    print("\t\t\t\tif(nf - 3 != %d){ char __ab[96]; snprint(__ab, sizeof __ab, \"error: %s takes %d arg(s), got %%d\\n\", nf-3); o9app_put_status(r, __ab); o9app_put_result(r, \"\"); respond(r, nil); return; }\n",
        np, m->name, np);
}

static int
ctl_method_exported(Node *c, Node *m)
{
    if(m == nil || m->type != NMethod)
        return 0;
    if(m->name == nil || strcmp(m->name, "main") == 0)
        return 0;
    /* SECURITY: do not emit a ctl-dispatch case for private methods or
     * the constructor. They still have INTERNAL dispatch cases for
     * o9-to-o9 calls, super, and new. */
    if(m->flags & NFPrivate)
        return 0;
    if(c != nil && c->name != nil && strcmp(m->name, c->name) == 0)
        return 0;
    return 1;
}

static int
ctl_param_supported(Node *p)
{
    Type *t;

    t = p != nil ? p->typeinfo : nil;
    return !type_is_class_ref(t) && !o9_type_is_tabula(t);
}

static int
ctl_method_supported(Node *m)
{
    Node *p;

    for(p = m->right; p; p = p->next)
        if(!ctl_param_supported(p))
            return 0;
    return 1;
}

static int
ctl_method_arg_count(Node *m)
{
    Node *p;
    int np;

    np = 0;
    for(p = m->right; p; p = p->next)
        np++;
    return np;
}

static void
gen_class_ctl_arg_parse(Node *p, int idx)
{
    print("\t\t\t\tv = strchr(f[%d], '='); v = v ? v+1 : f[%d];\n", idx + 3, idx + 3);
    if(type_is_string(p->typeinfo)){
        print("\t\t\t\t__wargs[%d] = (vlong)(uintptr)o9_string_from_c(v);\n", idx);
    } else if(type_is_double(p->typeinfo)){
        print("\t\t\t\t__wargs[%d] = o9_double_pack(strtod(v, nil));\n", idx);
    } else {
        print("\t\t\t\t__wargs[%d] = strtoll(v, nil, 0);\n", idx);
    }
}

static void
gen_class_ctl_arg_parsing(Node *m, int np)
{
    Node *p;
    int pi;

    if(np <= 0)
        return;
    print("\t\t\t\tvlong __wargs[%d] = {0};\n", np);
    /* TYPED PARSING (finding #4): parse each arg per its declared AST
     * type, not blindly as strtoll. int-like -> strtoll; string -> an
     * O9String pointer; double -> packed double; object handles cannot
     * be marshaled over a text ctl line. */
    for(p = m->right, pi = 0; p; p = p->next, pi++)
        gen_class_ctl_arg_parse(p, pi);
}

static void
gen_class_ctl_send_and_recv(Node *m, int np)
{
    print("\t\t\t\t{ O9Msg __wm = {0x%lux, %s, %d, chancreate(sizeof(void*), 0)};\n",
        o9_hash(m->name), np > 0 ? "__wargs" : "nil", np);
    print("\t\t\t\tsendp(target->dispatch_chan, &__wm);\n");
    /* REQUEST CONCURRENCY: drop srv->slock while blocked on the actor's
     * reply so other client requests can run meanwhile. Safe now that
     * the session follows r instead of a global current session. */
    print("\t\t\t\tsrvrelease(r->srv);\n");
    print("\t\t\t\tO9Reply *__o9rep = recvp(__wm.replyc);\n");
    print("\t\t\t\tsrvacquire(r->srv);\n");
}

static void
gen_class_ctl_result_value(Node *m)
{
    char *fmt, *cast;

    if(type_is_void(m->typeinfo)){
        print("\t\t\t\t\to9app_put_result(r, \"\");\n");
        return;
    }
    fmt = type_fmt_for_codegen(m->typeinfo);
    cast = type_cast_for_codegen(m->typeinfo);
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

static void
gen_class_ctl_reply_handling(Node *m)
{
    /* Roles (docs/SESSIONS.md): success/error -> STATUS, return value ->
     * DATA. o9app_put_* route to the current session or root fallback. */
    print("\t\t\t\tif(__o9rep->err != nil){\n");
    print("\t\t\t\t\tchar __eb[256]; snprint(__eb, sizeof __eb, \"error: %%s\\n\", __o9rep->err);\n");
    print("\t\t\t\t\to9app_put_status(r, __eb); o9app_put_result(r, \"\");\n");
    print("\t\t\t\t} else {\n");
    print("\t\t\t\t\to9app_put_status(r, \"ok\\n\");\n");
    gen_class_ctl_result_value(m);
    print("\t\t\t\t}\n");
}

static void
gen_class_ctl_unsupported_method(Node *m)
{
    print("\t\t\t\to9app_put_status(r, \"error: %s: object arguments are not callable over ctl\\n\"); o9app_put_result(r, \"\"); respond(r, nil); return;\n", m->name);
    print("\t\t\t}\n");
}

static void
gen_class_ctl_method_case(Node *m)
{
    int np;

    np = ctl_method_arg_count(m);
    print("\t\t\tif(strcmp(f[2], \"%s\") == 0){\n", m->name);
    gen_class_ctl_arity_check(m, np);
    if(!ctl_method_supported(m)){
        gen_class_ctl_unsupported_method(m);
        return;
    }
    gen_class_ctl_arg_parsing(m, np);
    gen_class_ctl_send_and_recv(m, np);
    gen_class_ctl_reply_handling(m);
    print("\t\t\t\to9_reply_free(__o9rep); chanfree(__wm.replyc); }\n");
    print("\t\t\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t\t\t}\n");
}

static void
gen_class_ctl_method_cases(Node *c)
{
    Node *m;

    for(m = c->left; m; m = m->next)
        if(ctl_method_exported(c, m))
            gen_class_ctl_method_case(m);
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
