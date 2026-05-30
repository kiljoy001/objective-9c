with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

import re

# I need to completely replace the NAssign block because it is thoroughly mangled with literal newlines.
# Find the start and end of the NAssign block.
# We'll use regex to match from "case NAssign:" to the NEXT "case " or "default:"
pattern = re.compile(r'    case NAssign:.*?    (case NReturn:|default:)', re.DOTALL)

replacement = r"""    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
                print("\to9_dict_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
                print(");\n");
            } else {
                print("\to9_array_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
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
                    print(";\n\t\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = (", cname, s->name);
                    {
                        char* t = get_sym_type(find_class(cname), s->name);
                        if (find_class(t) && find_class(t)->type == NStruct) {
                             gen_expr(s->right);
                        } else {
                             print("vlong)(");
                             gen_expr(s->right);
                             print(")");
                        }
                    }
                    print("); } }\n");
                    break;
                } else if (find_class(cname)->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\n");
                    break;
                }
            }
        }
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;
    \1"""

content = pattern.sub(replacement, content)

# I also need to fix the stray %% issue which indicates a missing brace before the lexer section.
# A missing brace probably happened because of my earlier regex replacements in the AST or codegen blocks.
# Let's restore the entire file from git and just apply the correct replacements.
