import re

with open('../objective-9c/o9c/o9_plan9.y', 'r') as f:
    content = f.read()

# 1. Add gen_dispatch_cases and gen_cleanup_props above gen_class_server
helpers = """
static ulong emitted_hashes[1024];
static int num_emitted = 0;

void gen_dispatch_cases(Node *c, char *childname) {
    Node *m;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod) {
            ulong h = o9_hash(m->name);
            int i, found = 0;
            for(i=0; i<num_emitted; i++) { if(emitted_hashes[i] == h) { found = 1; break; } }
            if(!found) {
                print("\\t\\tcase 0x%lux: o9_impl_%s_%s((%s_Internal*)self, m); break;\\n", h, c->name, m->name, c->name);
                emitted_hashes[num_emitted++] = h;
            }
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) {
            Node *p = find_class(m->name);
            if(p) gen_dispatch_cases(p, childname);
        }
    }
}

void gen_cleanup_props(Node *c, char *childname) {
    Node *m;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) {
            Node *p = find_class(m->name);
            if(p) gen_cleanup_props(p, childname);
        }
        if(m->type == NProp || m->type == NState) {
            char *t = map_type(m->typename);
            if(strcmp(t, "char*") == 0) {
                print("\\tfree(((%s_Internal*)self)->%s);\\n", childname, m->name);
            } else if(strcmp(t, "O9Dict") == 0) {
                print("\\to9_dict_free(&((%s_Internal*)self)->%s);\\n", childname, m->name);
            }
        }
    }
}

void
gen_class_server(Node *c)
"""
content = content.replace("void\ngen_class_server(Node *c)\n", helpers)

# 2. Update dispatch loop to use gen_dispatch_cases
old_dispatch = """    print("\\t\\tswitch(m->sel){\\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod)
            print("\\t\\tcase 0x%lux: o9_impl_%s_%s(self, m); break;\\n", o9_hash(m->name), c->name, m->name);
    }
    print("\\t\\tcase 0x%lux: o9_cleanup_%s(self); threadexits(nil); break;\\n", o9_hash("destroy"), c->name);"""

new_dispatch = """    print("\\t\\tswitch(m->sel){\\n");
    num_emitted = 0;
    gen_dispatch_cases(c, c->name);
    print("\\t\\tcase 0x%lux: o9_cleanup_%s(self); threadexits(nil); break;\\n", o9_hash("destroy"), c->name);"""
content = content.replace(old_dispatch, new_dispatch)

# 3. Update o9_cleanup_<Class> to call gen_cleanup_props
old_cleanup = """    print("static void o9_cleanup_%s(%s_Internal *self) {\\n", c->name, c->name);
    if (has_destruct) {
        print("\\to9_destruct_%s(self);\\n", c->name);
    }
    print("\\tchanfree(self->dispatch_chan);\\n");
    print("\\tfree(self);\\n");
    print("}\\n\\n");"""

new_cleanup = """    print("static void o9_cleanup_%s(%s_Internal *self) {\\n", c->name, c->name);
    if (has_destruct) {
        print("\\to9_destruct_%s(self);\\n", c->name);
    }
    gen_cleanup_props(c, c->name);
    print("\\tchanfree(self->dispatch_chan);\\n");
    print("\\tfree(self);\\n");
    print("}\\n\\n");"""
content = content.replace(old_cleanup, new_cleanup)

with open('../objective-9c/o9c/o9_plan9.y', 'w') as f:
    f.write(content)
