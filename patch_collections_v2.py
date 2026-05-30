import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Update map_type to handle prefixes AND classes correctly
new_map_type = """char*
map_type(char *t)
{
    int len;
    Node *n;
    static char buf[8][128];
    static int bi = 0;
    char *b = buf[bi++ % 8];

    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
    if(strncmp(t, "List:", 5) == 0) return "O9Slice";
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
    if(n != nil){
        if(n->type == NStruct) return t;
        snprint(b, 128, "%s_Client", t);
        return b;
    }
    return t;
}"""
content = re.sub(r'char\*\nmap_type\(char \*t\)\n\{.*?\n\}', new_map_type, content, flags=re.DOTALL)

# 2. Update is_primitive
content = content.replace('if(t == nil) return 1;',
                          'if(t == nil) return 1;\n    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;')

# 3. Update tokens and lexer
content = content.replace('%token TCLASS TINTERFACE TSTRUCT TIMPORT TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TNIL',
                          '%token TCLASS TINTERFACE TSTRUCT TIMPORT TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TLIST TNIL')

content = content.replace('if(strcmp(buf, "dict") == 0) return TDICT;',
                          'if(strcmp(buf, "dict") == 0) return TDICT;\n            if(strcmp(buf, "List") == 0) return TLIST;')

# 4. Add List to stmt and var_decl grammar
content = content.replace('stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }',
                          'stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }\n    | TLIST \'<\' typename \'>\' TIDENT \';\' {\n        char buf[128];\n        snprint(buf, sizeof buf, "List:%s", $3->name);\n        $$ = mk(NLocalVar, $5->name, buf, nil, nil);\n    }\n    | TDICT \'<\' typename \',\' typename \'>\' TIDENT \';\' {\n        char buf[128];\n        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);\n        $$ = mk(NLocalVar, $7->name, buf, nil, nil);\n    }')

content = content.replace('    | TCHAN TIDENT \';\'\n    {\n        $$ = mk(NStream, $2->name, "chan", nil, nil);\n    }\n    | typename \'[\' \']\' TIDENT \';\'',
                          """    | TCHAN TIDENT ';'
    {
        $$ = mk(NStream, $2->name, "chan", nil, nil);
    }
    | TDICT '<' typename ',' typename '>' TIDENT ';'
    {
        char buf[128];
        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);
        $$ = mk(NProp, $7->name, buf, nil, nil);
    }
    | TLIST '<' typename '>' TIDENT ';'
    {
        char buf[128];
        snprint(buf, sizeof buf, "List:%s", $3->name);
        $$ = mk(NProp, $5->name, buf, nil, nil);
    }
    | typename '[' ']' TIDENT ';'""")

# 5. CODEGEN: Initialization
content = content.replace('print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(s->left){',
                          'print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(strncmp(s->typename, "List:", 5) == 0){\n                print("\\to9_slice_init(&%s, sizeof(%s));\\n", s->name, map_type(s->typename+5));\n            } else if(strncmp(s->typename, "Dict:", 5) == 0){\n                print("\\to9_dict_init(&%s);\\n", s->name);\n            } else if(s->left){')

# 6. CODEGEN: NMsgSend methods
content = content.replace('case NMsgSend:\n        /* c.method(args...)',
"""case NMsgSend:
        {
            char *lt = get_expr_type(e->left);
            if(strncmp(lt, "List:", 5) == 0){
                if(strcmp(e->name, "Add") == 0){
                    char *et = lt + 5;
                    print("({ %s __v = ", map_type(et)); gen_expr(e->right);
                    print("; o9_slice_append(&"); gen_expr(e->left); print(", &__v); (vlong)0; })");
                    break;
                }
                if(strcmp(e->name, "Length") == 0){
                    print("(vlong)("); gen_expr(e->left); print(".len)");
                    break;
                }
            }
            if(strncmp(lt, "Dict:", 5) == 0){
                if(strcmp(e->name, "Has") == 0){
                    print("o9_dict_has(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")");
                    break;
                }
            }
        }
        /* c.method(args...)""")

# 7. CODEGEN: NArrayGet and NAssign
content = content.replace('case NArrayGet:\n        if(e->right && e->right->type == NStringLit){',
"""case NArrayGet:
        {
            char *lt = get_expr_type(e->left);
            if(strncmp(lt, "Dict:", 5) == 0){
                char *last = strrchr(lt, ':');
                char *vt = last ? last + 1 : "vlong";
                print("((%s)o9_dict_get(&", map_type(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
                break;
            } else if(strncmp(lt, "List:", 5) == 0){
                char *et = lt + 5;
                print("(*(%s*)o9_slice_get(&", map_type(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");
                break;
            }
        }
        if(e->right && e->right->type == NStringLit){""")

content = content.replace('case NAssign:\n        if(s->left != nil && s->left->type == NArrayGet){',
"""case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            char *lt = get_expr_type(s->left->left);
            if(strncmp(lt, "Dict:", 5) == 0){
                print("\\to9_dict_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", (void*)("); gen_expr(s->right); print("));\\n");
                break;
            } else if(strncmp(lt, "List:", 5) == 0){
                char *et = lt + 5;
                print("\\t{ %s __v = ", map_type(et)); gen_expr(s->right);
                print("; o9_slice_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right);
                print(", &__v); }\\n");
                break;
            } else if(s->left->right && s->left->right->type == NStringLit){""")

# 8. Type Safety updates for collections
content = content.replace('        } else if(e->left->type == NIdent && e->left->name){',
"""        } else if(e->left->type == NIdent && e->left->name){
            char *cn = get_type_sym(e->left->name);
            if(cn == nil){
                fprint(2, "o9c: error: unknown variable '%s'\\\\n", e->left->name);
                (*errs)++;
            } else if(strncmp(cn, "List:", 5) == 0){
                if(strcmp(e->name, "Length") != 0){
                    fprint(2, "o9c: error: List has no property '%s'\\\\n", e->name);
                    (*errs)++;
                }
            } else if(strncmp(cn, "Dict:", 5) == 0){
                fprint(2, "o9c: error: Dict has no properties\\\\n");
                (*errs)++;
            } else if(find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type '%s' for '%s'\\\\n", cn, e->left->name);
                (*errs)++;
            } else {""")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
