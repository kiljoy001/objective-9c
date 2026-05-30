import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. Add TypeSym struct and helper functions
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
    /* Map primitive aliases */
    char *t1 = map_type(target);
    char *t2 = map_type(actual);
    if(strcmp(t1, t2) == 0) return 1;
    /* Inheritance */
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
                if(strcmp(t, "void") != 0 && strcmp(t, "vlong") != 0) return t;
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
    case NAdd: case NSub: case NMul: case NDiv: case NMod:
    case NBitAnd: case NBitOr: case NBitXor: case NLshift: case NRshift:
        return "int64";
    case NEq: case NNe: case NLt: case NLe: case NGt: case NGe:
    case NAnd: case NOr: case NNot:
        return "bool";
    default: return "vlong";
    }
}
"""

# Insert helpers before get_sym_type (around line 200)
content = content.replace("char*\nget_sym_type(Node *c, char *name)", helpers + "\nchar*\nget_sym_type(Node *c, char *name)")

# 2. Update typecheck_expr to use get_expr_type and is_type_compatible
new_typecheck_expr = """
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
        if(c->type == NClass || c->type == NStruct){
            /* Entering class/struct scope - in a real compiler we'd have nested symtables */
            /* For now, just add class members to a global or ignore? */
            /* Actually, we need to track if we're inside a class for 'self' */
        }
        if(c->type == NMethod){
            Node *old_meth = cur_meth;
            cur_meth = c;
            /* Add params to symtable */
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
"""

# Replace old typecheck functions (at the end)
content = re.sub(r'static void\ntypecheck_expr\(Node \*e, int \*errs\)\n\{.*?\n\}', new_typecheck_expr, content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
