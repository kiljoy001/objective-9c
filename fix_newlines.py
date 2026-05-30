import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Replace \\n with \n in the generated print statements
content = content.replace('; }\\\\n");', '; }\\n");')
content = content.replace('));\\\\n");', '));\\n");')
content = content.replace(');\\\\n");', ');\\n");')

# Also fix the precedence issue in NArrayGet
# Old: print("*(%s*)o9_slice_get(&", map_type(et));
# New: print("(*( %s *)o9_slice_get(&", map_type(et));
content = content.replace('print("*(%s*)o9_slice_get(&", map_type(et));', 'print("(*(%s*)o9_slice_get(&", map_type(et));')
content = content.replace('print(")");', 'print("))");') # Wait this is too broad

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
