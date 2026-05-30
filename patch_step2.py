import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. top_level types
content = content.replace('%type <node> program top_levels top_level class_decl interface_decl import_decl', 
                          '%type <node> program top_levels top_level class_decl interface_decl struct_decl import_decl func_top_level')

# 2. top_level rules
content = content.replace('top_level:\n    class_decl\n    | interface_decl\n    | import_decl', 
                          'top_level:\n    class_decl\n    | interface_decl\n    | struct_decl\n    | import_decl\n    | func_top_level')

# 3. struct_decl and func_top_level
content = content.replace('interface_decl:\n    TINTERFACE TIDENT \'{\' member_list \'}\'\n    {\n        $$ = mk(NInterface, $2->name, nil, $4, nil);\n        add_class($2->name, $$);\n    }\n    ;',
"""interface_decl:
    TINTERFACE TIDENT '{' member_list '}'
    {
        $$ = mk(NInterface, $2->name, nil, $4, nil);
        add_class($2->name, $$);
    }
    ;

struct_decl:
    TSTRUCT TIDENT '{' member_list '}'
    {
        $$ = mk(NStruct, $2->name, nil, $4, nil);
        add_class($2->name, $$);
    }
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $6, nil);
    }
    ;""")

# 4. var_decl collections
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

# 5. stmt collections
content = content.replace('stmt:\n    typename TIDENT \';\' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }\n    | expr \';\' { $$ = $1; }',
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
    | expr ';' { $$ = $1; }""")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
