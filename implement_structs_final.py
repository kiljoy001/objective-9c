import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# This is the exact safe replacement logic that avoids regex backslash/newline issues.

content = content.replace("%token TCLASS TINTERFACE TIMPORT", "%token TCLASS TINTERFACE TSTRUCT TIMPORT")
content = content.replace("NInterface,\n    NImport", "NInterface,\n    NStruct,\n    NImport")

content = content.replace("interface_decl:\n    TINTERFACE", "struct_decl:\n    TSTRUCT TIDENT '{' member_list '}'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;\n\ninterface_decl:\n    TINTERFACE")
content = content.replace("| interface_decl\n    | import_decl", "| interface_decl\n    | struct_decl\n    | import_decl")
content = content.replace("%type <node> program top_levels top_level class_decl interface_decl", "%type <node> program top_levels top_level class_decl interface_decl struct_decl")

codegen_struct = """
void
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
"""
content = content.replace("void\ngen_class_header(Node *c)", codegen_struct + "\nvoid\ngen_class_header(Node *c)")

content = content.replace("if(n->type == NClass) {\n            gen_class_server(n);\n            last = n;\n        }", "if(n->type == NStruct) {\n            gen_struct_def(n);\n        }\n        if(n->type == NClass) {\n            gen_class_server(n);\n            last = n;\n        }")

content = content.replace("is_iface ? NInterface : NClass", "is_iface ? NInterface : (name[0] == 's' ? NStruct : NClass)")
content = content.replace('if(strcmp(name, "class") == 0 || strcmp(name, "interface") == 0){', 'if(strcmp(name, "class") == 0 || strcmp(name, "interface") == 0 || strcmp(name, "struct") == 0){')
content = content.replace('if(strcmp(buf, "class") == 0) return TCLASS;', 'if(strcmp(buf, "class") == 0) return TCLASS;\n            if(strcmp(buf, "struct") == 0) return TSTRUCT;')

new_map_type = """char*
map_type(char *t)
{
    int len;
    Node *n;
    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
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
    if(n != nil && n->type == NStruct) return t;
    
    return t;
}"""
content = re.sub(r'char\*\nmap_type\(char \*t\)\n\{.*?\n\}', new_map_type.strip(), content, flags=re.DOTALL)

old_assign = """    case NAssign:
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
                /* Direct struct write via shm_base */
                print("\\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                gen_expr(s->left);
                print(";\\n\\t\\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = (vlong)(", cname, s->name);
                gen_expr(s->right);
                print("); } }\\n");
                break;
            }
        }
        print("\\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\\n");
        break;"""

new_assign = """    case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
                print("\\to9_dict_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\\n");
            } else {
                print("\\to9_array_set(&");
                gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", "); gen_expr(s->right);
                print(");\\n");
            }
            break;
        }
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            char *cname = get_var_class(s->left->name);
            if(cname != nil && find_class(cname)){
                if(find_class(cname)->type == NClass || find_class(cname)->type == NInterface) {
                    print("\\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                    gen_expr(s->left);
                    print(";\\n\\t\\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = ", cname, s->name);
                    {
                        char* t = get_sym_type(find_class(cname), s->name);
                        if (find_class(t) && find_class(t)->type == NStruct) {
                             gen_expr(s->right);
                        } else {
                             print("(vlong)("); gen_expr(s->right); print(")");
                        }
                    }
                    print("; } }\\n");
                    break;
                } else if (find_class(cname)->type == NStruct) {
                    gen_expr(s->left); print(".%s = ", s->name); gen_expr(s->right); print(";\\n");
                    break;
                }
            }
        }
        print("\\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\\n");
        break;"""

content = content.replace(old_assign, new_assign)

old_localvar = """    case NLocalVar:
        if(is_primitive(s->typename)){
            print("\\t%s %s;\\n", map_type(s->typename), s->name);
            if(s->left){
                print("\\t%s = ", s->name); gen_expr(s->left); print(";\\n");
            }
        } else {
            print("\\t%s_Client %s;\\n", s->typename, s->name);
            print("\\tmemset(&%s, 0, sizeof(%s_Client));\\n", s->name, s->typename);
            if(s->left){
"""

new_localvar = """    case NLocalVar:
        if(is_primitive(s->typename) || (find_class(s->typename) && find_class(s->typename)->type == NStruct)){
            print("\\t%s %s;\\n", map_type(s->typename), s->name);
            if(s->left){
                print("\\t%s = ", s->name); gen_expr(s->left); print(";\\n");
            } else {
                print("\\tmemset(&%s, 0, sizeof(%s));\\n", s->name, map_type(s->typename));
            }
        } else {
            print("\\t%s_Client %s;\\n", s->typename, s->name);
            print("\\tmemset(&%s, 0, sizeof(%s_Client));\\n", s->name, s->typename);
            if(s->left){
"""
content = content.replace(old_localvar, new_localvar)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
