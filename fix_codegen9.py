import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Fix NPropRead in gen_expr to avoid vlong cast for structs
old_propread = r"""    case NPropRead:
        /* obj.prop — property read via SHM */
        /* emit: (vlong)((ClassName_Internal*)((ClassName_Client*)&obj)->shm_base)->prop */
        {
            /* If left is an ident, try to look up its class */
            if(e->left && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                if(cn != nil){
                    print("(vlong)((%s_Internal*)((%s_Client*)&", cn, cn);
                    gen_expr(e->left);
                    print(")->shm_base)->%s", e->name);
                } else {
                    /* Fallback: direct struct access */
                    gen_expr(e->left);
                    print(".%s", e->name);
                }
            } else {
                gen_expr(e->left);
                print(".%s", e->name);
            }
        }
        break;"""

new_propread = r"""    case NPropRead:
        {
            if(e->left && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                Node *cnode = find_class(cn);
                if(cnode != nil){
                    if(cnode->type == NClass || cnode->type == NInterface){
                        char *t = get_sym_type(cnode, e->name);
                        if(find_class(t) && find_class(t)->type == NStruct){
                            /* Struct property: no vlong cast */
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

content = content.replace(old_propread, new_propread)

# 2. Fix property initialization in gen_class_server
# Find where props are initialized to 0
pattern = r'if\(m->typename && strncmp\(m->typename, "Dict:", 5\) == 0\)\n\s+print\("\\t\\to9_dict_init\(&__%s->%s\);\\n", s->name, m->name\);\n\s+else\n\s+print\("\\t__%s->%s = 0;\\n", s->name, m->name\);'
replacement = r"""if(m->typename && strncmp(m->typename, "Dict:", 5) == 0)
                                    print("\t\to9_dict_init(&__%s->%s);\n", s->name, m->name);
                                else if(find_class(m->typename) && find_class(m->typename)->type == NStruct)
                                    print("\tmemset(&__%s->%s, 0, sizeof(%s));\n", s->name, m->name, m->typename);
                                else
                                    print("\t__%s->%s = 0;\n", s->name, m->name);"""

content = re.sub(pattern, replacement, content)

# 3. Disable 9P read/write for structs in fileserver handlers for now to avoid aggregate formatting errors
old_gen_prop = r"""                } else {
                    print("\tsnprint(buf, sizeof buf, \"%s\\n\", (vlong)s->%s);\n", type_fmt(t), m->name);
                    print("\treadstr(r, buf);\n");
                }"""
new_gen_prop = r"""                } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                    print("\treadstr(r, \"<struct>\");\n");
                } else {
                    print("\tsnprint(buf, sizeof buf, \"%s\\n\", (vlong)s->%s);\n", type_fmt(t), m->name);
                    print("\treadstr(r, buf);\n");
                }"""
content = content.replace(old_gen_prop, new_gen_prop)

# Same for fsread in class server
old_fsread_prop = r"""            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }"""
new_fsread_prop = r"""            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\treadstr(r, \"<struct>\"); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }"""
content = content.replace(old_fsread_prop, new_fsread_prop)

# And fswrite
old_fswrite_prop = r"""            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }"""
new_fswrite_prop = r"""            } else if(find_class(m->typename) && find_class(m->typename)->type == NStruct) {
                /* skip writing to structs via 9P for now */
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }"""
content = content.replace(old_fswrite_prop, new_fswrite_prop)

# 4. Fix double break in NLocalVar
content = content.replace("break;\n        break;", "break;")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
