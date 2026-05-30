import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Update map_type
content = content.replace('if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";',
                          'if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";\n    if(strncmp(t, "List:", 5) == 0) return "O9Slice";')

# 2. Update is_primitive
content = content.replace('if(t == nil) return 1;',
                          'if(t == nil) return 1;\n    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;')

# 3. Update lexer keywords
content = content.replace('if(strcmp(buf, "dict") == 0) return TDICT;',
                          'if(strcmp(buf, "dict") == 0) return TDICT;\n            if(strcmp(buf, "List") == 0) return TLIST;')

# 4. Add List to stmt grammar
content = content.replace('stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }',
                          'stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }\n    | TLIST \'<\' typename \'>\' TIDENT \';\' {\n        char buf[128];\n        snprint(buf, sizeof buf, "List:%s", $3->name);\n        $$ = mk(NLocalVar, $5->name, buf, nil, nil);\n    }\n    | TDICT \'<\' typename \',\' typename \'>\' TIDENT \';\' {\n        char buf[128];\n        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);\n        $$ = mk(NLocalVar, $7->name, buf, nil, nil);\n    }')

# 5. Add collection initialization to NLocalVar codegen
content = content.replace('if(is_primitive(s->typename)){\n            print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(s->left){',
                          'if(is_primitive(s->typename)){\n            print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(strncmp(s->typename, "List:", 5) == 0){\n                print("\\to9_slice_init(&%s, sizeof(%s));\\n", s->name, map_type(s->typename+5));\n            } else if(strncmp(s->typename, "Dict:", 5) == 0){\n                print("\\to9_dict_init(&%s);\\n", s->name);\n            } else if(s->left){')

# 6. Add collection access to NArrayGet codegen
content = content.replace('case NArrayGet:\n        if(e->right && e->right->type == NStringLit){',
                          'case NArrayGet:\n        {\n            char *lt = get_expr_type(e->left);\n            if(strncmp(lt, "Dict:", 5) == 0){\n                char *last = strrchr(lt, \':\');\n                char *vt = last ? last + 1 : "vlong";\n                print("((%s)o9_dict_get(&", map_type(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");\n                break;\n            } else if(strncmp(lt, "List:", 5) == 0){\n                char *et = lt + 5;\n                print("(*(%s*)o9_slice_get(&", map_type(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))");\n                break;\n            }\n        }\n        if(e->right && e->right->type == NStringLit){')

# 7. Add collection assignment to NAssign codegen
content = content.replace('case NAssign:\n        if(s->left != nil && s->left->type == NArrayGet){',
                          'case NAssign:\n        if(s->left != nil && s->left->type == NArrayGet){\n            char *lt = get_expr_type(s->left->left);\n            if(strncmp(lt, "Dict:", 5) == 0){\n                print("\\to9_dict_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", (void*)("); gen_expr(s->right); print("));\\n");\n                break;\n            } else if(strncmp(lt, "List:", 5) == 0){\n                char *et = lt + 5;\n                print("\\t{ %s __v = ", map_type(et)); gen_expr(s->right); print("; o9_slice_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", &__v); }\\n");\n                break;\n            }')

# 8. Add collection methods to NMsgSend codegen
content = content.replace('case NMsgSend:\n        /* c.method(args...)',
                          'case NMsgSend:\n        {\n            char *lt = get_expr_type(e->left);\n            if(strncmp(lt, "List:", 5) == 0){\n                if(strcmp(e->name, "Add") == 0){\n                    char *et = lt + 5;\n                    print("({ %s __v = ", map_type(et)); gen_expr(e->right);\n                    print("; o9_slice_append(&"); gen_expr(e->left); print(", &__v); (vlong)0; })");\n                    break;\n                }\n                if(strcmp(e->name, "Length") == 0){\n                    print("(vlong)("); gen_expr(e->left); print(".len)");\n                    break;\n                }\n            }\n        }\n        /* c.method(args...')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
