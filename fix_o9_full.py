import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Fix map_type
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

# 2. Fix type_cast
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

# 3. Fix is_primitive
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

# 4. Fix NPropRead in gen_expr
new_prop_read = r"""    case NPropRead:
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
                    }
                }
            }
            gen_expr(e->left);
            print(".%s", e->name);
        }
        break;"""
content = re.sub(r'    case NPropRead:.*?        break;', new_prop_read, content, flags=re.DOTALL)

# 5. Fix NAssign in gen_stmt (wait, NAssign is using s-> not e->)
new_assign = r"""    case NAssign:
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
content = re.sub(r'    case NAssign:.*?        break;', new_assign, content, flags=re.DOTALL)

# 6. Fix class property initialization and 9P handlers stubs for structs
# Property init
pattern = r'if\(m->typename && strncmp\(m->typename, "Dict:", 5\) == 0\)\n\s+print\("\\t\\to9_dict_init\(&__%s->%s\);\\n", s->name, m->name\);\n\s+else\n\s+print\("\\t__%s->%s = 0;\\n", s->name, m->name\);'
replacement = r"""if(m->typename && strncmp(m->typename, "Dict:", 5) == 0)
                                    print("\t\to9_dict_init(&__%s->%s);\n", s->name, m->name);
                                else if(find_class(m->typename) && find_class(m->typename)->type == NStruct)
                                    print("\tmemset(&__%s->%s, 0, sizeof(%s));\n", s->name, m->name, m->typename);
                                else
                                    print("\t__%s->%s = 0;\n", s->name, m->name);"""
content = re.sub(pattern, replacement, content)

# fsread prop
pattern = r'\} else \{\n\s+print\("\\tif\(strcmp\(name, \\"%s\\"\) == 0\)\{\\n", m->name\);\n\s+print\("\\t\\tsnprint\(buf, sizeof buf, \\"%s\\\\n\\", \(%s\)inst->%s\);\\n", fmt, cast, m->name\);\n\s+print\("\\t\\treadstr\(r, buf\); respond\(r, nil\); return;\\n\\t\}\\n"\);'
replacement = r"""} else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<struct>\"); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");"""
content = re.sub(pattern, replacement, content)

# fswrite prop
pattern = r'\} else \{\n\s+print\("\\tif\(strcmp\(name, \\"%s\\"\) == 0\)\{\\n", m->name\);\n\s+print\("\\t\\tinst->%s = \(%s\)strtoll\(r->ifcall.data, nil, 0\);\\n", m->name, type_cast\(t\)\);\n\s+print\("\\t\\tr->ofcall.count = r->ifcall.count;\\n\\t\\trespond\(r, nil\);\\n\\t\\treturn;\\n\\t\}\\n"\);'
replacement = r"""} else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                /* skip */
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");"""
content = re.sub(pattern, replacement, content)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
