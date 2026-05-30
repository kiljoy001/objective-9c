with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Add TSTRUCT token
content = content.replace("%token TCLASS TINTERFACE TIMPORT", "%token TCLASS TINTERFACE TSTRUCT TIMPORT")
# Add NStruct AST type
content = content.replace("NInterface,\n    NImport", "NInterface,\n    NStruct,\n    NImport")
# Add struct_decl rule
content = content.replace("interface_decl:\n    TINTERFACE", "struct_decl:\n    TSTRUCT TIDENT '{' member_list '}'\n    {\n        $$ = mk(NStruct, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;\n\ninterface_decl:\n    TINTERFACE")
content = content.replace("| interface_decl\n    | import_decl", "| interface_decl\n    | struct_decl\n    | import_decl")
content = content.replace("%type <node> program top_levels top_level class_decl interface_decl", "%type <node> program top_levels top_level class_decl interface_decl struct_decl")

# Update codegen to handle NStruct
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
content = content.replace("if(strcmp(name, \"class\") == 0 || strcmp(name, \"interface\") == 0){", "if(strcmp(name, \"class\") == 0 || strcmp(name, \"interface\") == 0 || strcmp(name, \"struct\") == 0){")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)

with open('../objective-9c/o9c/o9.l', 'r') as f:
    content = f.read()
content = content.replace('\"class\"             { return TCLASS; }', '\"class\"             { return TCLASS; }\n\"struct\"            { return TSTRUCT; }')
with open('../objective-9c/o9c/o9.l', 'w') as f:
    f.write(content)

