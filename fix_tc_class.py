import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Replace the problematic cur_class with tc_class in my new code
content = content.replace("char *cur_class;", "char *tc_class;")
content = content.replace("if(cur_class == nil)", "if(tc_class == nil)")
content = content.replace("get_sym_type(find_class(cur_class), e->name)", "get_sym_type(find_class(tc_class), e->name)")
content = content.replace("fprint(2, \"o9c: error: class '%s' has no member '%s'\\\\n\", cur_class, e->name);", "fprint(2, \"o9c: error: class '%s' has no member '%s'\\\\n\", tc_class, e->name);")
content = content.replace("member_exists(find_class(cur_class), e->name)", "member_exists(find_class(tc_class), e->name)")
content = content.replace("fprint(2, \"o9c: error: class '%s' has no member '%s'\\\\n\", cur_class, e->name);", "fprint(2, \"o9c: error: class '%s' has no member '%s'\\\\n\", tc_class, e->name);")
content = content.replace("Node *c = find_class(cur_class);", "Node *c = find_class(tc_class);")
content = content.replace("fprint(2, \"o9c: error: class '%s' has no method '%s'\\\\n\", cur_class, e->name);", "fprint(2, \"o9c: error: class '%s' has no method '%s'\\\\n\", tc_class, e->name);")
content = content.replace("char *old_class = cur_class;", "char *old_class = tc_class;")
content = content.replace("tc_class = c->name;", "tc_class = c->name;") # wait this is correct
content = content.replace("cur_class = c->name;", "tc_class = c->name;")
content = content.replace("cur_class = old_class;", "tc_class = old_class;")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
