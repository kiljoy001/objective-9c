import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix 1: NArrayGet precedence
# From: print("*(%s*)o9_slice_get(&", map_type(et));
# To:   print("(*(%s*)o9_slice_get(&", map_type(et));
# And add the closing paren
content = content.replace('print("*(%s*)o9_slice_get(&", map_type(et));', 'print("(*(%s*)o9_slice_get(&", map_type(et));')
# This is tricky because print(")") is used everywhere. 
# I will replace specific instances.

# Fix 2: Double )) in NAssign
content = content.replace('print("(vlong)("); gen_expr(s->right); print("))");', 'print("(vlong)("); gen_expr(s->right); print(")");')

# Fix 3: Newlines in NMsgSend and NAssign
content = content.replace('; (vlong)0; })");', '; (vlong)0; })\\n");')

# Fix 4: NArrayGet closing paren for slices
content = content.replace('gen_expr(e->right);\n                print(")");', 'gen_expr(e->right);\n                print("))");')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
