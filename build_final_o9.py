import re

with open('../objective-9c/o9c/o9_clean.y', 'r') as f:
    content = f.read()

# I will apply all patches in sequence using EXACT strings.

# --- 1. Structs Support ---
content = content.replace("NInterface,", "NInterface,\n    NStruct,")
content = content.replace("%token TCLASS TINTERFACE TIMPORT", "%token TCLASS TINTERFACE TSTRUCT TIMPORT")
content = content.replace("%type <node> program top_levels top_level class_decl interface_decl import_decl", "%type <node> program top_levels top_level class_decl interface_decl struct_decl import_decl")
content = content.replace('top_level:\n    class_decl\n    | interface_decl\n    | import_decl', 'top_level:\n    class_decl\n    | interface_decl\n    | struct_decl\n    | import_decl')
content = content.replace('add_class($2->name, $$);\n    }\n    ;', 'add_class($2->name, $$);\n    }\n    ;\n\nstruct_decl:\n    TSTRUCT TIDENT \'{\' member_list \'}\'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;')

# --- 2. Type System Enhancements ---
# add_type_sym helpers
helpers = """
typedef struct TypeSym TypeSym;
struct TypeSym {
    char *name;
    char *typename;
    TypeSym *next;
};
TypeSym *type_syms;

void
add_type_sym(char *name, char *typename)
{
    TypeSym *s = malloc(sizeof(TypeSym));
    s->name = strdup(name);
    s->typename = strdup(typename);
    s->next = type_syms;
    type_syms = s;
}

char*
get_type_sym(char *name)
{
    TypeSym *s;
    for(s = type_syms; s; s = s->next)
        if(strcmp(s->name, name) == 0) return s->typename;
    return nil;
}

void
clear_type_syms(void)
{
    TypeSym *s, *next;
    for(s = type_syms; s; s = next){
        next = s->next;
        free(s->name);
        free(s->typename);
        free(s);
    }
    type_syms = nil;
}

int
is_subclass(char *sub, char *parent)
{
    Node *c, *m;
    if(sub == nil || parent == nil) return 0;
    if(strcmp(sub, parent) == 0) return 1;
    c = find_class(sub);
    if(c == nil) return 0;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            if(strcmp(m->name, parent) == 0) return 1;
            if(is_subclass(m->name, parent)) return 1;
        }
    }
    return 0;
}

int
is_type_compatible(char *target, char *actual)
{
    if(target == nil || actual == nil) return 0;
    if(strcmp(target, actual) == 0) return 1;
    if(strcmp(target, "vlong") == 0 && strcmp(actual, "int64") == 0) return 1;
    if(strcmp(target, "int64") == 0 && strcmp(actual, "vlong") == 0) return 1;
    if(is_subclass(actual, target)) return 1;
    return 0;
}

char*
get_method_type(Node *c, char *name)
{
    Node *m;
    if(c == nil || name == nil) return "void";
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && m->name && strcmp(m->name, name) == 0)
            return m->typename;
        if(m->type == NInherit){
            Node *p = find_class(m->name);
            if(p){
                char *t = get_method_type(p, name);
                if(strcmp(t, "void") != 0) return t;
            }
        }
    }
    return "void";
}

char*
get_expr_type(Node *e)
{
    if(e == nil) return "void";
    switch(e->type){
    case NIntLit: return "int64";
    case NStringLit: return "string";
    case NBoolLit: return "bool";
    case NIdent:
        {
            char *t = get_type_sym(e->name);
            if(t) return t;
            return "vlong";
        }
    case NPropRead:
        if(e->left){
            char *lt = get_expr_type(e->left);
            Node *c = find_class(lt);
            if(c) return get_sym_type(c, e->name);
        }
        return "vlong";
    case NMsgSend:
        if(e->left){
            char *lt = get_expr_type(e->left);
            Node *c = find_class(lt);
            if(c) return get_method_type(c, e->name);
        }
        return "vlong";
    default: return "vlong";
    }
}
"""
content = content.replace("char*\nget_sym_type(Node *c, char *name)", helpers + "\nchar*\nget_sym_type(Node *c, char *name)")

# Update map_type for structs
new_map_type = """char*
map_type(char *t)
{
    int len;
    Node *n;
    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
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
    if(n != nil && n->type == NStruct) return t;
    return t;
}"""
content = re.sub(r'char\*\nmap_type\(char \*t\)\n\{.*?\n\}', new_map_type, content, flags=re.DOTALL)

# Update is_primitive for structs
new_is_primitive = """int
is_primitive(char *t)
{
    if(t == nil) return 1;
    if(strcmp(t, "int64") == 0 || strcmp(t, "uint64") == 0 ||
       strcmp(t, "int32") == 0 || strcmp(t, "uint32") == 0 ||
       strcmp(t, "int16") == 0 || strcmp(t, "uint16") == 0 ||
       strcmp(t, "int8") == 0 || strcmp(t, "uint8") == 0 ||
       strcmp(t, "bool") == 0 || strcmp(t, "string") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "char") == 0 ||
       strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "ulong") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "uchar") == 0 || strcmp(t, "void") == 0 ||
       strcmp(t, "chan") == 0) return 1;
    if(find_class(t) && find_class(t)->type == NStruct) return 1;
    return 0;
}"""
content = re.sub(r'int\nis_primitive\(char \*t\)\n\{.*?\n\}', new_is_primitive, content, flags=re.DOTALL)

# Update type_cast for structs
new_type_cast = """char*
type_cast(char *t)
{
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    if(find_class(t) && find_class(t)->type == NStruct) return "";
    return "vlong";
}"""
content = re.sub(r'char\*\ntype_cast\(char \*t\)\n\{.*?\n\}', new_type_cast, content, flags=re.DOTALL)

# --- 3. Lexer fix ---
content = content.replace('if(strcmp(buf, "class") == 0) return TCLASS;', 'if(strcmp(buf, "class") == 0) return TCLASS;\n            if(strcmp(buf, "struct") == 0) return TSTRUCT;')

# --- 4. Portability in generated code ---
content = content.replace('__sync_fetch_and_add(&self->ref, 1)', '#ifdef __GNUC__\\n\\t__sync_fetch_and_add(&self->ref, 1);\\n#else\\n\\tainc(&self->ref);\\n#endif')
content = content.replace('__sync_sub_and_fetch(&self->ref, 1) == 0', """#ifdef __GNUC__
                __sync_sub_and_fetch(&self->ref, 1)
#else
                adec(&self->ref)
#endif
                == 0""")
content = content.replace('r->fid->file->dir.name', '#ifdef __GNUC__\\n\\tr->fid->file->dir.name\\n#else\\n\\tr->fid->file->name\\n#endif')

# --- 5. Codegen order and NLocalVar/NAssign fixes ---
gen_struct_def = """
void
gen_struct_def(Node *c)
{
    Node *m;
    if(c == nil) return;
    print("/* Generated Struct Definition for %s */\\n", c->name);
    print("typedef struct %s %s;\\n", c->name, c->name);
    print("struct %s {\\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NState) 
            print("\\t%s %s;\\n", map_type(m->typename), m->name);
    }
    print("};\\n\\n");
}
"""
content = content.replace("void\ngen_class_header(Node *c)", gen_struct_def + "\nvoid\ngen_class_header(Node *c)")
content = content.replace("    for(n = root; n; n = n->next){\n        if(n->type == NClass) {", "    /* Pass 1: Structs */\n    for(n = root; n; n = n->next)\n        if(n->type == NStruct) gen_struct_def(n);\n    \n    /* Pass 2: Classes */\n    for(n = root; n; n = n->next){\n        if(n->type == NClass) {")

# NLocalVar fix
new_nlocalvar = """    case NLocalVar:
        if(is_primitive(s->typename)){
            print("\\t%s %s;\\n", map_type(s->typename), s->name);
            if(s->left){
                print("\\t%s = ", s->name); gen_expr(s->left); print(";\\n");
            } else {
                print("\\tmemset(&%s, 0, sizeof(%s));\\n", s->name, map_type(s->typename));
            }
        } else {"""
content = content.replace("    case NLocalVar:\n        {", new_nlocalvar)

# NAssign fix
new_nassign = """    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
                print("\\to9_dict_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\\n");
            } else {
                print("\\to9_array_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\\n");
            }
            break;
        }
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            char *cname = get_var_class(s->left->name);
            Node *cnode = find_class(cname);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface) {
                    print("\\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\\n\\t\\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = ", cname, s->name);
                    {
                        char* t = get_sym_type(cnode, s->name);
                        if (find_class(t) && find_class(t)->type == NStruct) {
                             gen_expr(s->right);
                        } else {
                             print("(vlong)("); gen_expr(s->right); print(")");
                        }
                    }
                    print("; } }\\n");
                    break;
                } else if (cnode->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\\n");
                    break;
                }
            }
        }
        print("\\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\\n");
        break;"""
content = re.sub(r'    case NAssign:.*?        break;', new_nassign, content, flags=re.DOTALL)

# NPropRead fix
new_npropread = """    case NPropRead:
        {
            if(e->left && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                Node *cnode = find_class(cn);
                if(cnode != nil){
                    if(cnode->type == NClass || cnode->type == NInterface){
                        char *t = get_sym_type(cnode, e->name);
                        if(find_class(t) && find_class(t)->type == NStruct){
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
            }
            gen_expr(e->left);
            print(".%s", e->name);
        }
        break;"""
content = re.sub(r'    case NPropRead:.*?        break;', new_npropread, content, flags=re.DOTALL)

# --- 6. Final Typecheck Implementation ---
typecheck_logic = """
Node *cur_meth;

static void
typecheck_expr(Node *e, int *errs)
{
    if(e == nil) return;
    
    switch(e->type){
    case NAssign:
        {
            char *lt = nil;
            if(e->left){
                if(e->left->type == NIdent) lt = get_type_sym(e->left->name);
                else if(e->left->type == NPropRead) lt = get_expr_type(e->left);
            }
            if(lt){
                char *rt = get_expr_type(e->right);
                if(!is_type_compatible(lt, rt)){
                    fprint(2, "o9c: error: incompatible types in assignment: expected %s, got %s\\n", lt, rt);
                    (*errs)++;
                }
            }
        }
        break;
    case NPropRead:
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_type_sym(e->left->name);
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\\n", e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: '%s' is a method, not a property\\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NMsgSend:
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_type_sym(e->left->name);
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\\n", e->left->name);
                (*errs)++;
            } else {
                Node *c = find_class(cn);
                int mt = member_exists(c, e->name);
                if(mt >= 0 && mt != NMethod){
                    fprint(2, "o9c: error: '%s' is a property, not a method\\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\\n", cn, e->name);
                    (*errs)++;
                } else {
                    /* Check arguments */
                    Node *meth = nil;
                    Node *walk;
                    for(walk = c->left; walk; walk = walk->next)
                        if(walk->type == NMethod && strcmp(walk->name, e->name) == 0) { meth = walk; break; }
                    
                    if(meth){
                        Node *param = meth->right;
                        Node *arg = e->right;
                        while(param && arg){
                            char *pt = param->typename;
                            char *at = get_expr_type(arg);
                            if(!is_type_compatible(pt, at)){
                                fprint(2, "o9c: error: method '%s' arg mismatch: expected %s, got %s\\n", e->name, pt, at);
                                (*errs)++;
                            }
                            param = param->next;
                            arg = arg->next;
                        }
                        if(param || arg){
                            fprint(2, "o9c: error: method '%s' argument count mismatch\\n", e->name);
                            (*errs)++;
                        }
                    }
                }
            }
        }
        break;
    case NReturn:
        if(cur_meth){
            char *rt = get_expr_type(e->left);
            if(!is_type_compatible(cur_meth->typename, rt)){
                fprint(2, "o9c: error: return type mismatch: expected %s, got %s\\n", cur_meth->typename, rt);
                (*errs)++;
            }
        }
        break;
    case NLocalVar:
        if(e->typename && !is_primitive(e->typename) && find_class(e->typename) == nil){
            fprint(2, "o9c: error: unknown type '%s'\\n", e->typename);
            (*errs)++;
        }
        if(e->name) add_type_sym(e->name, e->typename);
        break;
    }
}

static void
check_node(Node *n, int *errs)
{
    Node *c;
    if(n == nil) return;
    for(c = n; c; c = c->next){
        if(c->type == NMethod){
            Node *old_meth = cur_meth;
            cur_meth = c;
            Node *p;
            for(p = c->right; p; p = p->next) add_type_sym(p->name, p->typename);
            check_node(c->left, errs);
            cur_meth = old_meth;
            continue;
        }
        typecheck_expr(c, errs);
        check_node(c->left, errs);
        check_node(c->right, errs);
    }
}

static int
typecheck(Node *root)
{
    int errors = 0;
    clear_type_syms();
    check_node(root, &errors);
    return errors;
}
"""

pattern_typecheck = r'static void\ntypecheck_expr\(Node \*e, int \*errs\)\n\{.*?\n\}\n\nstatic void\ncheck_node\(Node \*n, int \*errs\)\n\{.*?\n\}\n\nstatic int\ntypecheck\(Node \*root\)\n\{.*?\n\}'
content = re.sub(pattern_typecheck, typecheck_logic, content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
