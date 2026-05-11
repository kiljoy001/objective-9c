#!/usr/bin/env python3
import sys

with open("/home/scott/Repo/objective-9c/o9c/o9_plan9.y", "r") as f:
    content = f.read()

# Change 1: Add thunk after method impl
# The anchor is the print() call that sends reply and closes method body
old1 = '''\t\t\tprint("\\tr->ok = 1;\\n\\tsendp(msg->replyc, r);\\n}\\n\\n");
\t\t}
\t\tif(m->type == NDestructor){'''

new1 = '''\t\t\tprint("\\tr->ok = 1;\\n\\tsendp(msg->replyc, r);\\n}\\n\\n");
\t\t\t/* Ctrl dispatch thunk (void(*)(void*) for asm cache) */
\t\t\t{
\t\t\t\tint np = 0, pi;
\t\t\t\tNode *pn;
\t\t\t\tfor(pn = m->right; pn; pn = pn->next) np++;
\t\t\t\tprint("static void o9_ctrl_%s_%s(void *__a){\\n", c->name, m->name);
\t\t\t\tprint("\\t%s_Internal *self = (%s_Internal*)((vlong*)__a)[0];\\n", c->name, c->name);
\t\t\t\tif(np > 0){
\t\t\t\t\tfor(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
\t\t\t\t\t\tprint("\\t%s __%s = ((vlong*)__a)[%d];\\n", map_type(pn->typename), pn->name, pi+1);
\t\t\t\t\tprint("\\tvlong __args[%d];\\n", np);
\t\t\t\t\tfor(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
\t\t\t\t\t\tprint("\\t__args[%d] = __%s;\\n", pi, pn->name);
\t\t\t\t\tprint("\\tO9Msg __m = {0x%lux, __args, %d, chancreate(sizeof(void*), 0)};\\n", o9_hash(m->name), np);
\t\t\t\t} else
\t\t\t\t\tprint("\\tO9Msg __m = {0x%lux, nil, 0, chancreate(sizeof(void*), 0)};\\n", o9_hash(m->name));
\t\t\t\tprint("\\to9_impl_%s_%s(self, &__m);\\n", c->name, m->name);
\t\t\t\tprint("\\t{ O9Reply *__r = recvp(__m.replyc); free(__r); }\\n");
\t\t\t\tprint("\\tchanfree(__m.replyc);\\n}\\n\\n");
\t\t\t}
\t\t}
\t\tif(m->type == NDestructor){'''

if old1 not in content:
    print("FAIL: Change 1 anchor not found")
    sys.exit(1)
content = content.replace(old1, new1, 1)
print("Change 1: thunk added")

# Change 2: cache entries point to o9_ctrl instead of o9_impl
old2 = '''\t\tif(m->type == NMethod) print("\\t\\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \\"c:%ld:%p\\\\n\\", %ldL, o9_impl_%s_%s);\\n", o9_hash(m->name), c->name, m->name);
\t}
}

void
gen_prop_handlers'''

new2 = '''\t\tif(m->type == NMethod) print("\\t\\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \\"c:%ld:%p\\\\n\\", %ldL, o9_ctrl_%s_%s);\\n", o9_hash(m->name), c->name, m->name);
\t}
}

void
gen_prop_handlers'''

if old2 not in content:
    print("FAIL: Change 2 anchor not found")
    sys.exit(1)
content = content.replace(old2, new2)
print("Change 2: cache entries updated")

# Change 3: NMsgSend codegen to use o9_dispatch_call + fallback
old3 = '''    case NMsgSend:
        /* c.method(args...) -> obj9_msgSend(&c, hash, o9_call_args) */
        /* Plan 9 C-compatible: comma expressions for multi-arg, simple call for 0-arg */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            if(nargs > 0){
                /* Assign args to global buffer using comma ops */
                int i = 0;
                int first = 1;
                for(a = e->right; a; a = a->next){
                    if(first) print("(o9_call_args[%d]=", i);
                    else      print(", o9_call_args[%d]=", i);
                    gen_expr(a);
                    first = 0;
                    i++;
                }
                print(", (vlong)obj9_msgSend(&");
            } else {
                print("((vlong)obj9_msgSend(&");
            }
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args))", o9_hash(e->name));
        }
        break;'''

new3 = '''    case NMsgSend:
        /* c.method(args...) -> try o9_dispatch_call, fallback to obj9_msgSend */
        /* Pack: args[0]=shm_base (Internal*), then real args at [1..N] */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            /* Load args array: args[0]=shm_base, args[1..N]=real args */
            print("(o9_call_args[0]=");
            if(e->left && e->left->type == NIdent && e->left->name){
                char *__cnx = get_var_class(e->left->name);
                if(__cnx) print("(vlong)((%s_Client*)&", __cnx);
                gen_expr(e->left);
                if(__cnx) print(")->shm_base");
            } else {
                print("(vlong)&");
                gen_expr(e->left);
            }
            {
                int i = 1;
                for(a = e->right; a; a = a->next){
                    print(", o9_call_args[%d]=", i);
                    gen_expr(a);
                    i++;
                }
            }
            /* Try ctrl dispatch, fallback to CSP */
            print(", (vlong)o9_dispatch_call(&");
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args) || ", o9_hash(e->name));
            print("(vlong)obj9_msgSend(&");
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args))", o9_hash(e->name));
        }
        break;'''

if old3 not in content:
    print("FAIL: Change 3 anchor not found")
    sys.exit(1)
content = content.replace(old3, new3)
print("Change 3: NMsgSend codegen updated")

with open("/home/scott/Repo/objective-9c/o9c/o9_plan9.y", "w") as f:
    f.write(content)
print("File written OK")
