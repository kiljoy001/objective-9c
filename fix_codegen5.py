with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

import re

# 1. Properly implement NAssign in gen_expr (not typecheck!)
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
            if(cname != nil && find_class(cname)){
                if(find_class(cname)->type == NClass || find_class(cname)->type == NInterface) {
                    print("\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\n\t\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = ", cname, s->name);
                    {
                        char* t = get_sym_type(find_class(cname), s->name);
                        if (find_class(t) && find_class(t)->type == NStruct) {
                             gen_expr(s->right);
                        } else {
                             print("(vlong)("); gen_expr(s->right); print(")");
                        }
                    }
                    print("; } }\n");
                    break;
                } else if (find_class(cname)->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\n");
                    break;
                }
            }
        }
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;"""

# Identify the codegen NAssign block (it uses 's' as variable) vs typecheck NAssign block (it uses 'e' as variable)
content = re.sub(r'    case NAssign:\n\s+if\(s->left != nil && s->left->type == NArrayGet\)\{.*?break;\n\s+\}', new_assign, content, flags=re.DOTALL)

# 2. Fix the missing brace/mangled type_cast
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
content = re.sub(r'char\*\ntype_cast\(char \*t\)\n\{.*?\n\}', new_type_cast.strip(), content, flags=re.DOTALL)

# 3. Ensure NStruct is defined and handled in gen_stmt/gen_expr
# Struct members should be accessed via '.' 
new_prop_read = r"""    case NPropRead:
        if(e->left && e->left->type == NIdent && e->left->name != nil){
            char *cname = get_var_class(e->left->name);
            if(cname != nil && find_class(cname)){
                if(find_class(cname)->type == NStruct){
                     gen_expr(e->left); print(".%s", e->name);
                     break;
                }
                print("(*(%s*)o9_dispatch_data((o9_Object*)&", map_type(get_sym_type(find_class(cname), e->name)));
                gen_expr(e->left);
                print(", 0x%lux))", o9_hash(e->name));
                break;
            }
        }
        gen_expr(e->left); print(".%s", e->name);
        break;"""
content = re.sub(r'    case NPropRead:.*?        break;', new_prop_read, content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
