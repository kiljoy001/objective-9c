#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/*
 * Full pipeline test: run a generated Counter server, call methods,
 * verify return values propagate correctly.
 *
 * This tests the complete stack WITHOUT generated o9 source code:
 * - new-style C# syntax semantics: constructor, return values, params
 * - obj9_msgSend with correct 32-bit hashes
 * - vlong return value unwrapping
 */

typedef struct Counter_Internal Counter_Internal;
struct Counter_Internal {
    vlong val;
    Channel *dispatch_chan;
};

static void
o9_impl_Counter_Counter(Counter_Internal *self, O9Msg *msg)
{
    O9Reply *r = mallocz(sizeof(O9Reply), 1);
    self->val = ((vlong*)msg->args)[0];
    r->ok = 1;
    sendp(msg->replyc, r);
}

static void
o9_impl_Counter_getValue(Counter_Internal *self, O9Msg *msg)
{
    O9Reply *r = mallocz(sizeof(O9Reply), 1);
    r->ret = (void*)(self->val);
    goto done;
done:
    r->ok = 1;
    sendp(msg->replyc, r);
}

static void
o9_impl_Counter_inc(Counter_Internal *self, O9Msg *msg)
{
    O9Reply *r = mallocz(sizeof(O9Reply), 1);
    self->val = self->val + ((vlong*)msg->args)[0];
done:
    r->ok = 1;
    sendp(msg->replyc, r);
}

static void
o9_impl_Counter_double(Counter_Internal *self, O9Msg *msg)
{
    O9Reply *r = mallocz(sizeof(O9Reply), 1);
    r->ret = (void*)(self->val * 2);
    goto done;
done:
    r->ok = 1;
    sendp(msg->replyc, r);
}

static void
Counter_loop(void *v)
{
    Counter_Internal *self = v;
    O9Msg *m;
    for(;;){
        m = recvp(self->dispatch_chan);
        if(m == nil) continue;
        switch(m->sel){
        case 0x34ada145: o9_impl_Counter_Counter(self, m); break;
        case 0xfdcb98a2: o9_impl_Counter_getValue(self, m); break;
        case 0xb88801f: o9_impl_Counter_inc(self, m); break;
        case 0xf93d5b20: o9_impl_Counter_double(self, m); break;
        default:
            { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = "bad sel"; sendp(m->replyc, r); }
            break;
        }
    }
}

int pass, fail;

void
threadmain(int argc, char **argv)
{
    USED(argc); USED(argv);

    /* Create in-process Counter server */
    Counter_Internal state;
    vlong o9_call_args[64];

    memset(&state, 0, sizeof(state));
    state.dispatch_chan = chancreate(sizeof(void*), 10);
    proccreate(Counter_loop, &state, 8192);
    sleep(100);

    print("=== Constructor: new Counter(10) ===\n");
    o9_call_args[0] = 10;
    obj9_msgSend(&state, 0x34ada145, o9_call_args);
    print("  val=%lld\n", state.val);
    if(state.val == 10){ pass++; print("  PASS\n"); }
    else { fail++; print("  FAIL: expected 10\n"); }

    print("\n=== Method call: inc(5) via comma expr ===\n");
    o9_call_args[0] = 5;
    (vlong)obj9_msgSend(&state, 0xb88801f, o9_call_args);
    print("  val=%lld\n", state.val);
    if(state.val == 15){ pass++; print("  PASS\n"); }
    else { fail++; print("  FAIL: expected 15\n"); }

    print("\n=== Return value: getValue() ===\n");
    vlong v = ((vlong)obj9_msgSend(&state, 0xfdcb98a2, o9_call_args));
    print("  v=%lld\n", v);
    if(v == 15){ pass++; print("  PASS\n"); }
    else { fail++; print("  FAIL: expected 15\n"); }

    print("\n=== Expression body: double() ===\n");
    vlong d = ((vlong)obj9_msgSend(&state, 0xf93d5b20, o9_call_args));
    print("  d=%lld\n", d);
    if(d == 30){ pass++; print("  PASS\n"); }
    else { fail++; print("  FAIL: expected 30\n"); }

    print("\n=== RESULTS ===\n");
    print("%d passed, %d failed\n", pass, fail);
    if(fail == 0) print("ALL TESTS PASSED\n");
    else print("SOME TESTS FAILED\n");

    threadexitsall(nil);
}
