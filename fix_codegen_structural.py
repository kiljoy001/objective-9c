import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Pass 1: Codegen order
content = content.replace("    for(n = root; n; n = n->next){\n        if(n->type == NClass) {", 
"""    /* Pass 1: Structs */
    for(n = root; n; n = n->next)
        if(n->type == NStruct) gen_struct_def(n);
    
    /* Pass 2: Classes */
    for(n = root; n; n = n->next){
        if(n->type == NClass) {""")

# Pass 2: NPropRead structural support
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

# Pass 3: NAssign structural support
# (Already handled collections, now add struct/class shm support)
content = content.replace('if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){',
"""if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
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
        }""")

# Pass 4: gen_struct_def declaration
content = content.replace("void\ngen_class_header(Node *c)", 
"""void
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

void
gen_class_header(Node *c)""")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
