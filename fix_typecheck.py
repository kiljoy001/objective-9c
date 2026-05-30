with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix type cast logic to not cast structs to vlong
new_type_cast = """
char*
type_cast(char *t)
{
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    if(find_class(t) && find_class(t)->type == NStruct) return ""; /* Structs don't need cast */
    return "vlong"; /* fallback */
}
"""
import re
content = re.sub(r'char\*\ntype_cast\(char \*t\)\n\{.*?\n\}', new_type_cast.strip(), content, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
