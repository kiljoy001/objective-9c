import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# I am going to use VERY targeted replacements to avoid the regex hell I just went through.

# 1. Add TSTRUCT token and AST Node
content = content.replace("%token TCLASS TINTERFACE TIMPORT", "%token TCLASS TINTERFACE TSTRUCT TIMPORT")
content = content.replace("NInterface,\n    NImport", "NInterface,\n    NStruct,\n    NImport")

# 2. Add struct_decl rule
content = content.replace("interface_decl:\n    TINTERFACE", "struct_decl:\n    TSTRUCT TIDENT '{' member_list '}'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;\n\ninterface_decl:\n    TINTERFACE")
content = content.replace("| interface_decl\n    | import_decl", "| interface_decl\n    | struct_decl\n    | import_decl")
content = content.replace("%type <node> program top_levels top_level class_decl interface_decl", "%type <node> program top_levels top_level class_decl interface_decl struct_decl")

# 3. Add struct code generation function
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

# 4. Trigger struct codegen
content = content.replace("if(n->type == NClass) {", "if(n->type == NStruct) gen_struct_def(n);\n        if(n->type == NClass) {")

# 5. Fix type mapping and class tracking
content = content.replace("is_iface ? NInterface : NClass", "is_iface ? NInterface : (name[0] == 's' ? NStruct : NClass)")
content = content.replace('if(strcmp(name, "class") == 0 || strcmp(name, "interface") == 0){', 'if(strcmp(name, "class") == 0 || strcmp(name, "interface") == 0 || strcmp(name, "struct") == 0){')
content = content.replace('if(strcmp(buf, "class") == 0) return TCLASS;', 'if(strcmp(buf, "class") == 0) return TCLASS;\n            if(strcmp(buf, "struct") == 0) return TSTRUCT;')

# 6. Fix is_primitive to allow structs
new_is_primitive = """int
is_primitive(char *t)
{
    if(t == nil) return 1;
    if(strcmp(t, "int64") == 0) return 1;
    if(strcmp(t, "uint64") == 0) return 1;
    if(strcmp(t, "int32") == 0) return 1;
    if(strcmp(t, "uint32") == 0) return 1;
    if(strcmp(t, "int16") == 0) return 1;
    if(strcmp(t, "uint16") == 0) return 1;
    if(strcmp(t, "int8") == 0) return 1;
    if(strcmp(t, "uint8") == 0) return 1;
    if(strcmp(t, "bool") == 0) return 1;
    if(strcmp(t, "string") == 0) return 1;
    if(strcmp(t, "int") == 0) return 1;
    if(strcmp(t, "char") == 0) return 1;
    if(strcmp(t, "vlong") == 0) return 1;
    if(strcmp(t, "uvlong") == 0) return 1;
    if(strcmp(t, "ulong") == 0) return 1;
    if(strcmp(t, "ushort") == 0) return 1;
    if(strcmp(t, "uchar") == 0) return 1;
    if(strcmp(t, "void") == 0) return 1;
    if(find_class(t) && find_class(t)->type == NStruct) return 1;
    return 0;
}"""
content = re.sub(r'int\nis_primitive\(char \*t\)\n\{.*?\n\}', new_is_primitive, content, flags=re.DOTALL)

# 7. Fix map_type for structs
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
content = re.sub(r'char\*\nmap_type\(char \*t\)\n\{.*?\n\}', new_map_type, content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
