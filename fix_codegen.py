with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix NLocalVar generation
# If it's a struct, we should just emit `StructName varname;` and `memset(&varname, 0, sizeof(StructName));`
# Right now it emits `StructName_Client varname;` because it treats it like a class!
# In `gen_stmt` for `NLocalVar`:
# print("\t%s_Client %s;\n", s->typename, s->name);

new_localvar = """    case NLocalVar:
        if(is_primitive(s->typename) || (find_class(s->typename) && find_class(s->typename)->type == NStruct)){
            print("\t%s %s;\n", map_type(s->typename), s->name);
            if(s->left){
                print("\t%s = ", s->name); gen_expr(s->left); print(";\n");
            } else {
                print("\tmemset(&%s, 0, sizeof(%s));\n", s->name, map_type(s->typename));
            }
        } else {
            print("\t%s_Client %s;\n", s->typename, s->name);
            print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, s->typename);
"""

import re
content = re.sub(r'    case NLocalVar:\n\s+if\(is_primitive\(s->typename\)\)\{\n\s+print\("\\t%s %s;\\n", map_type\(s->typename\), s->name\);\n\s+if\(s->left\)\{\n\s+print\("\\t%s = ", s->name\); gen_expr\(s->left\); print\(";\\n"\);\n\s+\}\n\s+\} else \{\n\s+print\("\\t%s_Client %s;\\n", s->typename, s->name\);\n\s+print\("\\tmemset\(&%s, 0, sizeof\(%s_Client\)\);\\n", s->name, s->typename\);', new_localvar.strip('\n'), content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
