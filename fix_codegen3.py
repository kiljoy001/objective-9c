with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix NAssign generation for struct assignments.
new_assign = """    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
                /* Dict set: dict["key"] = val -> o9_dict_set(&dict, "key", val) */
                print("\\to9_dict_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
                print(");\\n");
            } else {
                /* Array set: a[idx] = expr -> o9_array_set(&a, idx, expr) */
                print("\\to9_array_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
                print(");\\n");
            }
            break;
        }
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            /* Property write: obj.prop = expr */
            char *cname = get_var_class(s->left->name);
            if(cname != nil && find_class(cname)){
                /* Direct write via shm_base for classes */
                if(find_class(cname)->type == NClass || find_class(cname)->type == NInterface) {
                    print("\\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\\n\\t\\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = (", cname, s->name);
                    char* t = get_sym_type(find_class(cname), s->name);
                    if (find_class(t) && find_class(t)->type == NStruct) {
                         /* struct assignment needs no cast */
                         gen_expr(s->right);
                    } else {
                         print("vlong)(");
                         gen_expr(s->right);
                         print(")");
                    }
                    print("; } }\\n");
                    break;
                } else if (find_class(cname)->type == NStruct) {
                    /* Direct struct write: pt.x = 10 */
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\\n");
                    break;
                }
            }
        }
        print("\\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\\n");
        break;"""

import re
content = re.sub(r'    case NAssign:.*?        break;\n', new_assign + '\n', content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
