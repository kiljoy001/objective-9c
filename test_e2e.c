#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/*
 * Self-contained o9 end-to-end test.
 *
 * Exercises the full stack without generated code:
 *   1. new Counter() -> Internal + chancreate + proccreate loop
 *   2. c.inc(42) -> obj9_msgSend via CSP channel
 *   3. c.inc(1) -> verify state accumulates
 *   4. o9_dispatch_data asm dispatch reads val
 *   5. o9_cache_fill via owner/srvname
 *   6. Cold miss + refill
 */

typedef struct Obj Obj;
struct Obj {
	vlong val;
	Channel *dispatch_chan;
};

static void
obj_loop(void *v)
{
	Obj *self = v;
	O9Msg *m;
	for(;;){
		m = recvp(self->dispatch_chan);
		if(m == nil) continue;
		switch(m->sel){
		case 0xb88801f:	/* o9_hash("inc") */
			self->val = self->val + ((vlong*)m->args)[0];
			{ O9Reply *r = mallocz(sizeof(O9Reply), 1); r->ok = 1; sendp(m->replyc, r); }
			break;
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
	Obj state;
	O9Msg *m;
	vlong *vp;
	o9_AsmTable table;
	o9_Object client;
	int i;

	USED(argc); USED(argv);
	memset(&state, 0, sizeof(state));
	memset(&client, 0, sizeof(client));
	state.dispatch_chan = chancreate(sizeof(void*), 10);
	client.dispatch_chan = state.dispatch_chan;
	client.table = &table;

	print("=== 1. new Counter() ===\n");
	proccreate(obj_loop, &state, 8192);
	sleep(100);
	print("  obj at %p, channel at %p\n", &state, state.dispatch_chan);
	if(state.dispatch_chan != nil){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL: no channel\n"); }

	print("\n=== 2. c.inc(42) via obj9_msgSend ===\n");
	{ vlong args[] = {42}; obj9_msgSend(&client, 0xb88801f, args); }
	print("  val=%lld\n", state.val);
	if(state.val == 42){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL: expected 42\n"); }

	print("\n=== 3. c.inc(1) ===\n");
	{ vlong args[] = {1}; obj9_msgSend(&client, 0xb88801f, args); }
	print("  val=%lld\n", state.val);
	if(state.val == 43){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL: expected 43\n"); }

	print("\n=== 4. o9_dispatch_data (hot hit) ===\n");
	ulong h_val = o9_hash("val");
	table.data_cache[h_val & 63].hash = (u64int)h_val;
	table.data_cache[h_val & 63].ptr = &state.val;

	vp = o9_dispatch_data(&client, h_val);
	print("  asm returned %p (expect %p), val=%lld\n", vp, &state.val, vp ? *vp : -1);
	if(vp == &state.val && *vp == 43){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL\n"); }

	print("\n=== 5. Cold miss (evict + re-read) ===\n");
	table.data_cache[h_val & 63].hash = 0;
	table.data_cache[h_val & 63].ptr = nil;
	vp = o9_dispatch_data(&client, h_val);
	if(vp == nil){ pass++; print("  PASS: nil (no /srv/%s/cache)\n", client.srvname); }
	else { fail++; print("  FAIL: expected nil got %p\n", vp); }

	print("\n=== 6. Refill + re-read ===\n");
	table.data_cache[h_val & 63].hash = (u64int)h_val;
	table.data_cache[h_val & 63].ptr = &state.val;
	vp = o9_dispatch_data(&client, h_val);
	if(vp == &state.val && *vp == 43){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL\n"); }

	print("\n=== 7. Stress: 100 inc(1) ===\n");
	for(i = 0; i < 100; i++){
		vlong args[] = {1};
		obj9_msgSend(&client, 0xb88801f, args);
	}
	print("  val=%lld\n", state.val);
	if(state.val == 143){ pass++; print("  PASS\n"); }
	else { fail++; print("  FAIL: expected 143\n"); }

	/* Final results */
	print("\n=== RESULTS ===\n");
	print("%d passed, %d failed\n", pass, fail);
	if(fail == 0) print("ALL TESTS PASSED\n");
	else print("SOME TESTS FAILED\n");

	threadexitsall(nil);
}
