import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# --- HEADER BLOCKS ---

# 1. Node Enum
content = content.replace('NInterface,', 'NInterface,\n    NStruct,')

# 2. Forward Declarations
content = content.replace('char* map_type(char *t);', 
                          'char* map_type(char *t);\nchar* get_expr_type(Node *e);\nchar* get_method_type(Node *c, char *name);')

# 3. TypeSym Helpers
helpers = """
typedef struct TypeSym TypeSym;
struct TypeSym {
    char *name;
    char *typename;
    TypeSym *next;
};
TypeSym *type_syms;

void add_type_sym(char *name, char *typename) {
    TypeSym *s = malloc(sizeof(TypeSym));
    s->name = strdup(name);
    s->typename = strdup(typename);
    s->next = type_syms;
    type_syms = s;
}

char* get_type_sym(char *name) {
    TypeSym *s;
    for(s = type_syms; s; s = s->next) if(strcmp(s->name, name) == 0) return s->typename;
    return nil;
}

void clear_type_syms(void) {
    TypeSym *s, *next;
    for(s = type_syms; s; s = next){ next = s->next; free(s->name); free(s->typename); free(s); }
    type_syms = nil;
}

int is_subclass(char *sub, char *parent) {
    Node *c, *m;
    if(sub == nil || parent == nil) return 0;
    if(strcmp(sub, parent) == 0) return 1;
    c = find_class(sub); if(c == nil) return 0;
    for(m = c->left; m; m = m->next) if(m->type == NInherit) { if(strcmp(m->name, parent) == 0) return 1; if(is_subclass(m->name, parent)) return 1; }
    return 0;
}

int is_type_compatible(char *target, char *actual) {
    if(target == nil || actual == nil) return 0;
    if(strcmp(target, actual) == 0) return 1;
    if(strcmp(target, "vlong") == 0 && (strcmp(actual, "int64") == 0 || strncmp(actual, "List:", 5) == 0)) return 1;
    if(is_subclass(actual, target)) return 1;
    return 0;
}

char* get_method_type(Node *c, char *name) {
    Node *m;
    if(c == nil || name == nil) return nil;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && m->name && strcmp(m->name, name) == 0) return m->typename;
        if(m->type == NInherit){ Node *p = find_class(m->name); if(p){ char *t = get_method_type(p, name); if(t) return t; } }
    }
    return nil;
}

char* get_expr_type(Node *e) {
    if(e == nil) return "void";
    switch(e->type){
    case NIntLit: return "int64";
    case NStringLit: return "string";
    case NBoolLit: return "bool";
    case NIdent: { char *t = get_type_sym(e->name); if(t) return t; return "vlong"; }
    case NPropRead: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_sym_type(c, e->name); } return "vlong";
    case NMsgSend: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_method_type(c, e->name); } return "vlong";
    case NClass: return e->name;
    case NArrayGet: { char *lt = get_expr_type(e->left); if(strncmp(lt, "List:", 5) == 0) return lt + 5; if(strncmp(lt, "Dict:", 5) == 0) return strrchr(lt, ':') + 1; return "vlong"; }
    case NAdd: case NSub: case NMul: case NDiv: case NMod: return "int64";
    default: return "vlong";
    }
}
"""
content = content.replace('char*\nget_sym_type(Node *c, char *name)\n{', 
                          helpers + '\nchar*\nget_sym_type(Node *c, char *name)\n{')

# 4. Update map_type
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

# 5. Update get_sym_type
content = content.replace('if(c == nil || name == nil) return "vlong";', 'if(c == nil || name == nil) return nil;')
content = content.replace('return "vlong";\n}', 'return nil;\n}')

# 6. Update is_primitive
content = content.replace('if(t == nil) return 1;',
                          'if(t == nil) return 1;\n    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;')

# --- GRAMMAR ---

# 7. Tokens
content = content.replace('%token TCLASS TINTERFACE TIMPORT', '%token TCLASS TINTERFACE TSTRUCT TIMPORT')
content = content.replace('TNEAR TFAR TDICT TNIL', 'TNEAR TFAR TDICT TLIST TNIL')

# 8. Rules: top_level
content = content.replace('top_level:\n    class_decl\n    | interface_decl\n    | import_decl', 
                          'top_level:\n    class_decl\n    | interface_decl\n    | struct_decl\n    | import_decl\n    | func_top_level')

# 9. Rules: struct_decl and func_top_level
content = content.replace('add_class($2->name, $$);\n    }\n    ;', 
                          'add_class($2->name, $$);\n    }\n    ;\n\nstruct_decl:\n    TSTRUCT TIDENT \'{\' member_list \'}\'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;\n\nfunc_top_level:\n    TFUNC TIDENT \'(\' \')\' \'{\' stmt_list \'}\'\n    {\n        $$ = mk(NMethod, $2->name, "void", $6, nil);\n    }\n    ;')

# 10. Rules: var_decl collections
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

# 11. Rules: stmt collections
content = content.replace('stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }\n    | typename TIDENT TEQ expr \';\' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }\n    | expr \'.\' TIDENT TEQ expr \';\' { $$ = mk(NAssign, $3->name, nil, $1, $5); }',
"""stmt:
    typename TIDENT ';' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | typename TIDENT TEQ expr ';' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | TLIST '<' typename '>' TIDENT ';' {
        char buf[128];
        snprint(buf, sizeof buf, "List:%s", $3->name);
        $$ = mk(NLocalVar, $5->name, buf, nil, nil);
    }
    | TDICT '<' typename ',' typename '>' TIDENT ';' {
        char buf[128];
        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);
        $$ = mk(NLocalVar, $7->name, buf, nil, nil);
    }
    | expr '.' TIDENT TEQ expr ';' { $$ = mk(NAssign, $3->name, nil, $1, $5); }""")

# --- CODEGEN ---

# 12. NLocalVar init
content = content.replace('print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(s->left){',
                          'print("\\t%s %s;\\n", map_type(s->typename), s->name);\n            if(strncmp(s->typename, "List:", 5) == 0){\n                print("\\to9_slice_init(&%s, sizeof(%s));\\n", s->name, map_type(s->typename+5));\n            } else if(strncmp(s->typename, "Dict:", 5) == 0){\n                print("\\to9_dict_init(&%s);\\n", s->name);\n            } else if(s->left){')

# 13. NMsgSend methods
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

# 14. NArrayGet
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

# 15. NAssign
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

# 16. Lexer keywords
content = content.replace('if(strcmp(buf, "class") == 0) return TCLASS;',
                          'if(strcmp(buf, "class") == 0) return TCLASS;\n            if(strcmp(buf, "struct") == 0) return TSTRUCT;\n            if(strcmp(buf, "List") == 0) return TLIST;\n            if(strcmp(buf, "dict") == 0) return TDICT;')

# --- TYPE CHECKER ---

# 17. Type check populated symbol table
content = content.replace('if(e->name) add_type_sym(e->name, e->typename);',
                          'if(e->name) add_type_sym(e->name, e->typename);') # actually already there in my mental model?

typecheck_impl = """
static void
typecheck_expr(Node *e, int *errs)
{
    if(e == nil) return;
    switch(e->type){
    case NLocalVar: if(e->name) add_type_sym(e->name, e->typename); break;
    case NAssign: { char *lt = get_expr_type(e->left); char *rt = get_expr_type(e->right); if(!is_type_compatible(lt, rt)){ fprint(2, "o9c: error: incompatible types in assignment: expected %s, got %s\\\\n", lt, rt); (*errs)++; } } break;
    }
}
"""
content = re.sub(r'static void\ntypecheck_expr\(Node \*e, int \*errs\)\n\{.*?\n\}', typecheck_impl, content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
