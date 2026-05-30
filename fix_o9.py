with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix NNeg
content = content.replace('print("-"); gen_expr(s->left);', 'print("-"); gen_expr(e->left);')

# Fix duplicate NPropRead.
# Let's split the content into an array of lines
lines = content.split('\n')
out = []
skip = False
for line in lines:
    if skip:
        if "break;" in line and "gen_expr(s->left); print(\".%s\", s->name);" in prev_line:
            skip = False
        prev_line = line
        continue
    
    if line.strip() == "case NPropRead:" and "/* obj.prop — property read via SHM */" in out[-1]:
        # This is the correct NPropRead, we keep it. Wait, the duplicate NPropRead has the exact same text or different?
        pass

# Let's just find the exact text of the duplicated one.
to_remove = """    case NPropRead:
        if(s->left && s->left->type == NIdent && s->left->name != nil){
            char *cname = get_var_class(s->left->name);
            if(cname != nil && find_class(cname)){
                print("(*(%s*)o9_dispatch_data((o9_Object*)&", map_type(get_sym_type(find_class(cname), s->name)));
                gen_expr(s->left);
                print(", 0x%lux))", o9_hash(s->name));
                break;
            }
        }
        /* Fallback if type resolution fails */
        gen_expr(s->left); print(".%s", s->name);
        break;"""

content = content.replace(to_remove, '')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
