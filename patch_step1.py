import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. ENUM AND TOKENS (Match specifically)
content = content.replace('NInterface,\n    NImport', 'NInterface,\n    NStruct,\n    NImport')
content = content.replace('%token TCLASS TINTERFACE TIMPORT', '%token TCLASS TINTERFACE TSTRUCT TIMPORT')
content = content.replace('TNEAR TFAR TDICT TNIL', 'TNEAR TFAR TDICT TLIST TNIL')

# 2. YYLEX
content = content.replace('if(strcmp(buf, "dict") == 0) return TDICT;',
                          'if(strcmp(buf, "dict") == 0) return TDICT;\n            if(strcmp(buf, "List") == 0) return TLIST;')

# 3. MAP_TYPE AND IS_PRIMITIVE
new_map_type = """char*
map_type(char *t)
{
    int len;
    Node *n;
    static char buf[8][128];
    static int bi = 0;
    char *b = buf[bi++ % 8];

    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
    if(strncmp(t, "List:", 5) == 0) return "O9Slice";
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0) return "char*";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "uint64") == 0) return "uvlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "uint32") == 0) return "ulong";
    if(strcmp(t, "bool") == 0) return "int";
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";
    n = find_class(t);
    if(n != nil){
        if(n->type == NStruct) return t;
        snprint(b, 128, "%s_Client", t);
        return b;
    }
    return t;
}"""
content = re.sub(r'char\*\nmap_type\(char \*t\)\n\{.*?\n\}', new_map_type, content, flags=re.DOTALL)

content = content.replace('if(t == nil) return 1;',
                          'if(t == nil) return 1;\n    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
