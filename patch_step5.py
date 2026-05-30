import re

with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# 1. NAssign
content = content.replace('case NAssign:\n        if(s->left != nil && s->left->type == NArrayGet){',
"""case NAssign:
        if(s->left != nil && s->left->type == NArrayGet){
            char *lt = get_expr_type(s->left->left);
            if(strncmp(lt, "Dict:", 5) == 0){
                print("\\to9_dict_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right); print(", (void*)("); gen_expr(s->right); print("));\\n");
                break;
            } else if(strncmp(lt, "List:", 5) == 0){
                char *et = lt + 5;
                print("\\t{ %s __v = ", map_type(et)); gen_expr(s->right);
                print("; o9_slice_set(&"); gen_expr(s->left->left); print(", "); gen_expr(s->left->right);
                print(", &__v); }\\n");
                break;
            } else if(s->left->right && s->left->right->type == NStringLit){""")

# 2. Type Checker (Surgical replace of implementation)
new_typecheck_expr = """static void
typecheck_expr(Node *e, int *errs)
{
    if(e == nil) return;
    switch(e->type){
    case NLocalVar: 
        if(e->name) add_type_sym(e->name, e->typename); 
        break;
    case NAssign: 
        if(e->left){
            char *lt = get_expr_type(e->left);
            char *rt = get_expr_type(e->right);
            if(!is_type_compatible(lt, rt)){
                fprint(2, "o9c: error: incompatible types in assignment: expected %s, got %s\\\\n", lt, rt);
                (*errs)++;
            }
        }
        break;
    }
}"""

# Match the old typecheck_expr exactly
content = re.sub(r'static void\ntypecheck_expr\(Node \*e, int \*errs\)\n\{.*?\n\}', new_typecheck_expr, content, count=1, flags=re.DOTALL)

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
