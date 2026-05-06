#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/* Generated Counter server entry point */
extern void o9_main_Counter(int argc, char **argv);

void
test_thread(void *arg)
{
	o9_Object client;
	o9_AsmTable table;
	vlong *vp;
	int i, fail;

	USED(arg);

	memset(&client, 0, sizeof(client));
	memset(&table, 0, sizeof(table));
	client.table = &table;

	print("=== 1. o9_init_client ===\n");
	if(o9_init_client(&client, "Counter", 4096) < 0){
		fprint(2, "FAIL: o9_init_client\n");
		threadexitsall("fail");
	}
	print("PASS: table->owner=%s\n", table.owner ? table.owner->srvname : "nil");

	/* 2. Populate via init, then write through dispatch */
	print("=== 2. o9_dispatch_data (hot) ===\n");
	vp = o9_dispatch_data(&client, o9_hash("val"));
	if(vp == nil){
		fprint(2, "FAIL: hot dispatch returned nil\n");
		threadexitsall("fail");
	}
	*vp = 42;
	print("PASS: val set to 42 via asm\n");

	/* 3. Evict the slot, read again (forces cache_fill) */
	print("=== 3. o9_cache_fill (cold) ===\n");
	table.data_cache[o9_hash("val") & 63].hash = 0;
	table.data_cache[o9_hash("val") & 63].ptr = nil;

	vp = o9_dispatch_data(&client, o9_hash("val"));
	if(vp == nil){
		fprint(2, "FAIL: cold dispatch returned nil\n");
		threadexitsall("fail");
	}
	print("PASS: cache_fill recovered val at %p = %lld\n", vp, *vp);

	/* 4. Call inc() method via ctrl dispatch */
	print("=== 4. o9_dispatch_call (inc method) ===\n");
	o9_dispatch_call(&client, o9_hash("inc"), nil);
	vp = o9_dispatch_data(&client, o9_hash("val"));
	print("PASS: val after inc = %lld (expected 43)\n", *vp);

	/* 5. Multiple calls */
	fail = 0;
	for(i = 0; i < 5; i++){
		o9_dispatch_call(&client, o9_hash("inc"), nil);
	}
	vp = o9_dispatch_data(&client, o9_hash("val"));
	if(*vp == 48)
		print("PASS: val after 5 more inc = %lld (expected 48)\n", *vp);
	else{
		print("FAIL: val after 5 inc = %lld (expected 48)\n", *vp);
		fail = 1;
	}

	if(!fail){
		print("\n=== ALL TESTS PASSED ===\n");
		threadexitsall(nil);
	} else {
		threadexitsall("fail");
	}
}

void
threadmain(int argc, char **argv)
{
	/* Start the Counter server */
	proccreate(o9_main_Counter, arg, 8192);
	sleep(500);	/* give server time to post */

	/* Run the test */
	proccreate(test_thread, nil, 8192);
	threadexitsall(nil);
}
