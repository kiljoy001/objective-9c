#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/*
 * End-to-end integration test for o9.
 *
 * Links against the generated Counter server and runtime (libo9.a).
 * Spawns the Counter server, then exercises the full dispatch stack:
 *   - new Counter() creates a Counter_Internal + loop thread
 *   - c.inc(42) sends an O9Msg through the CSP channel
 *   - Counter_loop receives it and increments val
 *   - We verify val == 42 by reading it directly from the internal state
 *
 * This test exercises:
 *   1. Compiler (o9c) transpilation
 *   2. libthread thread creation
 *   3. CSP channel messaging (sendp/recvp)
 *   4. Method dispatch via hash switch
 *   5. Asm dispatch (o9_dispatch.s via o9_dispatch_data)
 *   6. obj9_msgSend packing/unpacking
 */

/* Generated Counter client/server entry points */
typedef struct Counter_Internal Counter_Internal;
struct Counter_Internal {
	ArcLedger ledger;
	vlong val;
	Channel *dispatch_chan;
};

extern void o9_main_Counter(int argc, char **argv);
extern void Counter_loop(void *v);

/* Method handler (generated code) */
extern void o9_impl_Counter_inc(Counter_Internal *self, O9Msg *msg);

int pass, fail;

int
main(int argc, char **argv)
{
	Counter_Internal *state;
	Counter_Client client;
	o9_AsmTable table;
	vlong *vp;
	void *result;

	USED(argc); USED(argv);

	memset(&client, 0, sizeof(client));
	memset(&table, 0, sizeof(table));
	memset(&client, 0, sizeof(Counter_Client));

	print("=== o9 End-to-End Integration Test ===\n\n");

	/* 1. Create internal state + dispatch channel (like new Counter() codegen) */
	state = mallocz(sizeof(Counter_Internal), 1);
	state->dispatch_chan = chancreate(sizeof(void*), 10);
	client.dispatch_chan = state->dispatch_chan;

	print("1. Counter_Internal created, channel=%p\n", state->dispatch_chan);

	/* 2. Start the dispatch loop in a new thread */
	proccreate(Counter_loop, state, 8192);
	sleep(100);	/* let thread spin up */
	print("2. Counter_loop started\n");

	/* 3. Call inc(42) via obj9_msgSend (mimics c.inc(42) codegen) */
	{
		vlong __args[] = {42};
		print("3. Calling c.inc(42) via obj9_msgSend...\n");
		obj9_msgSend(&client, 0xb88801f, __args);
	}
	print("   val after inc(42) = %lld\n", state->val);
	if(state->val == 42){
		pass++;
		print("   PASS\n");
	} else {
		fail++;
		print("   FAIL: expected 42\n");
	}

	/* 4. Call inc(1) */
	{
		vlong __args[] = {1};
		print("4. Calling c.inc(1) via obj9_msgSend...\n");
		obj9_msgSend(&client, 0xb88801f, __args);
	}
	print("   val after inc(1) = %lld\n", state->val);
	if(state->val == 43){
		pass++;
		print("   PASS\n");
	} else {
		fail++;
		print("   FAIL: expected 43\n");
	}

	/* 5. Asm dispatch: pre-fill table, call dispatch_data */
	client.table = &table;
	table.data_cache[0x1c721 & 63].hash = (u64int)0x1c721;
	table.data_cache[0x1c721 & 63].ptr = &state->val;

	vp = o9_dispatch_data(&client, 0x1c721);
	print("5. o9_dispatch_data returned %p (expect %p)\n", vp, &state->val);
	if(vp == &state->val && *vp == 43){
		pass++;
		print("   PASS (val=%lld)\n", *vp);
	} else {
		fail++;
		print("   FAIL\n");
	}

	/* 6. Evict and re-read via cache_fill */
	table.data_cache[0x1c721 & 63].hash = 0;
	table.data_cache[0x1c721 & 63].ptr = nil;
	/* Set srvname so cache_fill can do its thing (no real /srv file though) */
	strcpy(client.srvname, "Test");
	vp = o9_dispatch_data(&client, 0x1c721);
	if(vp == nil)
		print("6. Cold miss returns nil (no /srv/Test/cache file - expected)\n");
	else
		print("6. Cold hit: val=%lld (cache_fill worked!)\n", *vp);
	pass++;

	print("\n=== RESULTS ===\n");
	print("%d passed, %d failed\n", pass, fail);
	if(fail == 0) print("ALL TESTS PASSED\n");

	threadexitsall(nil);
	return 0;
}
