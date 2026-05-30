import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Declarations at the top
decls = """Node* mk(int type, char *name, char *typename, Node *l, Node *r);
char* map_type(char *t);
char* get_sym_type(Node *c, char *name);
char* get_expr_type(Node *e);
char* get_method_type(Node *c, char *name);
void add_type_sym(char *name, char *typename);
char* get_type_sym(char *name);
void clear_type_syms(void);
int is_subclass(char *sub, char *parent);
int is_type_compatible(char *target, char *actual);
"""
content = re.sub(r'Node\* mk\(int type, char \*name, char \*typename, Node \*l, Node \*r\);', decls, content)

# 2. Implementations
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
content = re.sub(r'char\*\nget_sym_type\(Node \*c, char \*name\)\n\{.*?\n\}', 
                 helpers + '\nchar* get_sym_type(Node *c, char *name) {\n    Node *m;\n    if(c == nil || name == nil) return nil;\n    for(m = c->left; m; m = m->next){\n        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0) return map_type(m->typename);\n        if(m->type == NInherit){ Node *p = find_class(m->name); if(p){ char *t = get_sym_type(p, name); if(t) return t; } }\n    }\n    return nil;\n}', 
                 content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
