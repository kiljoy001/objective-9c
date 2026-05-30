import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. ENUM
content = content.replace('NInterface,', 'NInterface,\n    NStruct,')

# 2. TOKENS
content = content.replace('%token TCLASS TINTERFACE TIMPORT', '%token TCLASS TINTERFACE TSTRUCT TIMPORT')
content = content.replace('TNEAR TFAR TDICT TNIL', 'TNEAR TFAR TDICT TLIST TNIL')

# 3. YYLEX
content = content.replace('if(strcmp(buf, "dict") == 0) return TDICT;',
                          'if(strcmp(buf, "dict") == 0) return TDICT;\n            if(strcmp(buf, "List") == 0) return TLIST;')

# 4. MAP_TYPE AND IS_PRIMITIVE
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

content = content.replace('if(t == nil) return 1;',
                          'if(t == nil) return 1;\n    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;')

# 5. GRAMMAR: var_decl
content = content.replace('    | TDICT \'<\' typename \',\' typename \'>\' TIDENT \';\'\n    {\n        /* Dict<K,V> name — store as \"Dict:keytype:valtype\" in typename for codegen */\n        char buf[128];\n        snprint(buf, sizeof buf, \"Dict:%s:%s\", $3->name, $5->name);\n        $$ = mk(NProp, $7->name, buf, nil, nil);\n    }',
                          """    | TDICT '<' typename ',' typename '>' TIDENT ';'
    {
        /* Dict<K,V> name — store as "Dict:keytype:valtype" in typename for codegen */
        char buf[128];
        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);
        $$ = mk(NProp, $7->name, buf, nil, nil);
    }
    | TLIST '<' typename '>' TIDENT ';'
    {
        /* List<T> name — store as "List:type" in typename */
        char buf[128];
        snprint(buf, sizeof buf, "List:%s", $3->name);
        $$ = mk(NProp, $5->name, buf, nil, nil);
    }""")

# 6. GRAMMAR: stmt
content = content.replace('    | typename TIDENT TEQ expr \';\' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }',
                          """    | typename TIDENT TEQ expr ';' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | TLIST '<' typename '>' TIDENT ';' {
        char buf[128];
        snprint(buf, sizeof buf, "List:%s", $3->name);
        $$ = mk(NLocalVar, $5->name, buf, nil, nil);
    }
    | TDICT '<' typename ',' typename '>' TIDENT ';' {
        char buf[128];
        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);
        $$ = mk(NLocalVar, $7->name, buf, nil, nil);
    }""")

# 7. CODEGEN: NLocalVar init
content = content.replace('print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(s->left){',
                          'print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(strncmp(s->typename, "List:", 5) == 0){\n                print("\\to9_slice_init(&%s, sizeof(%s));\\n", s->name, map_type(s->typename+5));\n            } else if(strncmp(s->typename, "Dict:", 5) == 0){\n                print("\\to9_dict_init(&%s);\\n", s->name);\n            } else if(s->left){')

# 8. CODEGEN: NMsgSend methods
content = content.replace('case NMsgSend:\n        /* c.method(args...) -> try o9_dispatch_call (asm), fallback to obj9_msgSend (CSP/9P) */',
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
        /* c.method(args...) -> try o9_dispatch_call (asm), fallback to obj9_msgSend (CSP/9P) */""")

# 9. CODEGEN: NArrayGet
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

# 10. CODEGEN: NAssign
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

# 11. TYPE CHECKER: update typecheck_expr
new_typecheck_expr = """static void
typecheck_expr(Node *e, int *errs)
{
    if(e == nil) return;
    
    switch(e->type){
    case NPropRead:
        if(e->left && e->left->type == NIdent && e->left->name){
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
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: '%s' is a method, not a property\\\\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\\\\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NMsgSend:
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_type_sym(e->left->name);
            if(cn == nil){
                fprint(2, "o9c: error: unknown variable '%s'\\\\n", e->left->name);
                (*errs)++;
            } else if(strncmp(cn, "List:", 5) == 0){
                if(strcmp(e->name, "Add") != 0 && strcmp(e->name, "Length") != 0){
                    fprint(2, "o9c: error: List has no method '%s'\\\\n", e->name);
                    (*errs)++;
                }
            } else if(strncmp(cn, "Dict:", 5) == 0){
                if(strcmp(e->name, "Has") != 0){
                    fprint(2, "o9c: error: Dict has no method '%s'\\\\n", e->name);
                    (*errs)++;
                }
            } else if(find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type '%s' for '%s'\\\\n", cn, e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt >= 0 && mt != NMethod){
                    fprint(2, "o9c: error: '%s' is a property, not a method\\\\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\\\\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NAssign:
        if(e->left && e->left->type == NIdent && e->left->name){
            char *lt = get_type_sym(e->left->name);
            char *rt = get_expr_type(e->right);
            if(!is_type_compatible(lt, rt)){
                fprint(2, "o9c: error: incompatible types in assignment: expected %s, got %s\\\\n", lt, rt);
                (*errs)++;
            }
        }
        break;
    case NLocalVar:
        if(e->typename && !is_primitive(e->typename) && find_class(e->typename) == nil){
            fprint(2, "o9c: error: unknown type '%s'\\\\n", e->typename);
            (*errs)++;
        }
        if(e->name) add_type_sym(e->name, e->typename);
        break;
    }
}"""
content = re.sub(r'static void\ntypecheck_expr\(Node \*e, int \*errs\)\n\{.*?\n\}', new_typecheck_expr, content, count=1, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
