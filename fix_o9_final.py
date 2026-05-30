import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Base Support
content = content.replace("NInterface,\n    NImport", "NInterface,\n    NStruct,\n    NImport")
content = content.replace("%token TCLASS TINTERFACE TIMPORT", "%token TCLASS TINTERFACE TSTRUCT TIMPORT")
content = content.replace("%type <node> program top_levels top_level class_decl interface_decl import_decl", "%type <node> program top_levels top_level class_decl interface_decl struct_decl import_decl")
content = content.replace('top_level:\n    class_decl\n    | interface_decl\n    | import_decl', 'top_level:\n    class_decl\n    | interface_decl\n    | struct_decl\n    | import_decl')
content = content.replace("interface_decl:\n    TINTERFACE TIDENT '{' member_list '}'\n    {\n        $$ = mk(NInterface, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;", "interface_decl:\n    TINTERFACE TIDENT '{' member_list '}'\n    {\n        $$ = mk(NInterface, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;\n\nstruct_decl:\n    TSTRUCT TIDENT '{' member_list '}'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;")

# 2. Type System
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

new_is_primitive = """int
is_primitive(char *t)
{
    if(t == nil) return 1;
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
    if(find_class(t) && find_class(t)->type == NStruct) return 1;
    return 0;
}"""
content = re.sub(r'int\nis_primitive\(char \*t\)\n\{.*?\n\}', new_is_primitive, content, flags=re.DOTALL)

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

# 3. Lexer
content = content.replace('if(strcmp(buf, "class") == 0) return TCLASS;', 'if(strcmp(buf, "class") == 0) return TCLASS;\n            if(strcmp(buf, "struct") == 0) return TSTRUCT;')

# 4. Emitters
gen_struct_def = """void
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

# 5. Expr/Stmt Codegen
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

new_propread = """    case NPropRead:
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
content = re.sub(r'    case NPropRead:.*?        break;', new_propread, content, flags=re.DOTALL)

new_nassign = r"""    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
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
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            char *cname = get_var_class(s->left->name);
            Node *cnode = find_class(cname);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface) {
                    print("\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\n\t\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = ", cname, s->name);
                    {
                        char* t = get_sym_type(cnode, s->name);
                        if (find_class(t) && find_class(t)->type == NStruct) {
                             gen_expr(s->right);
                        } else {
                             print("(vlong)("); gen_expr(s->right); print(")");
                        }
                    }
                    print("; } }\n");
                    break;
                } else if (cnode->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\n");
                    break;
                }
            }
        }
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;"""
content = re.sub(r'    case NAssign:.*?        break;', new_nassign, content, flags=re.DOTALL)

# 6. Property Init and Portability
# Property init in class loop
pattern = r'if\(m->typename && strncmp\(m->typename, "Dict:", 5\) == 0\)\n\s+print\("\\t\\to9_dict_init\(&__%s->%s\);\\n", s->name, m->name\);\n\s+else\n\s+print\("\\t__%s->%s = 0;\\n", s->name, m->name\);'
replacement = r"""if(m->typename && strncmp(m->typename, "Dict:", 5) == 0)
                                    print("\t\to9_dict_init(&__%s->%s);\n", s->name, m->name);
                                else if(find_class(m->typename) && find_class(m->typename)->type == NStruct)
                                    print("\tmemset(&__%s->%s, 0, sizeof(%s));\n", s->name, m->name, m->typename);
                                else
                                    print("\t__%s->%s = 0;\n", s->name, m->name);"""
content = re.sub(pattern, replacement, content)

# 7. 9P Read/Write aggregators
old_fsread = r"""            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }"""
new_fsread = r"""            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<struct>\"); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }"""
content = content.replace(old_fsread, new_fsread)

old_fswrite = r"""            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }"""
new_fswrite = r"""            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                /* skip */
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }"""
content = content.replace(old_fswrite, new_fswrite)

# 8. Final Portability
content = content.replace("__sync_fetch_and_add(&self->ref, 1)", r'#ifdef __GNUC__\n\t__sync_fetch_and_add(&self->ref, 1);\n#else\n\tainc(&self->ref);\n#endif\n')
content = content.replace("__sync_sub_and_fetch(&self->ref, 1)", r'#ifdef __GNUC__\n\t\t__sync_sub_and_fetch(&self->ref, 1)\n#else\n\t\tadec(&self->ref)\n#endif\n')
content = content.replace("r->fid->file->name", r'#ifdef __GNUC__\n\tr->fid->file->dir.name\n#else\n\tr->fid->file->name\n#endif\n')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
