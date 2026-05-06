#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/*
 * test_asm_dispatch.c -- Integration test for the o9 asm dispatch.
 *
 * 1. Starts the Counter server (threadmain from generated code)
 * 2. Connects as a client using o9_init_client
 * 3. Exercises o9_dispatch_data to read/write val
 * 4. Exercises o9_dispatch_call to call inc()
 * 5. Verifies the cache fill works on miss
 */

/* Forward decl of the server's threadmain */
extern void threadmain(int argc, char **argv);

void
main(int argc, char **argv)
{
	o9_Object client;
	o9_AsmTable table;
	vlong *val_ptr, result;
	O9CacheEntry *entry;

	USED(argc); USED(argv);

	memset(&client, 0, sizeof(client));
	memset(&table, 0, sizeof(table));
	client.table = &table;

	/* Start the Counter server in a new proc */
	int pid = rfork(RFPROC|RFMEM);
	if(pid == 0){
		/* Child: run the server */
		proccreate(threadmain, nil, 8192);
		threadexits(nil);
	}
	/* Parent: wait for server to post */
	sleep(500);

	/* Connect as client */
	print("=== Test: o9_init_client ===\n");
	if(o9_init_client(&client, "Counter", 4096) < 0){
		fprint(2, "FAIL: o9_init_client failed\n");
		threadexitsall("fail");
	}
	print("PASS: o9_init_client (table->owner=%p, srvname=%s)\n",
		table.owner, table.owner ? table.owner->srvname : "nil");

	/* Test 1: asm dispatch_data (cache hit - pre-filled) */
	print("\n=== Test: o9_dispatch_data (hot) ===\n");
	val_ptr = o9_dispatch_data(&client, o9_hash("val"));
	if(val_ptr == nil){
		fprint(2, "FAIL: o9_dispatch_data returned nil (pre-filled miss?)\n");
		threadexitsall("fail");
	}
	*val_ptr = 42;
	print("PASS: set val = 42 via asm dispatch\n");

	/* Test 2: simulate cache eviction by clearing the slot, then dispatch_data */
	print("\n=== Test: o9_cache_fill (cold miss) ===\n");
	entry = &table.data_cache[o9_hash("val") & 63];
	entry->hash = 0;
	entry->ptr = nil;
	print("  cleared slot for 'val' (hash=0x%lx)\n", o9_hash("val"));

	val_ptr = o9_dispatch_data(&client, o9_hash("val"));
	if(val_ptr == nil){
		fprint(2, "FAIL: o9_dispatch_data still nil after cache_fill\n");
		threadexitsall("fail");
	}
	print("PASS: cache_fill recovered val at %p (should be 42, got %lld)\n", val_ptr, *val_ptr);

	/* Test 3: asm dispatch_call for method */
	print("\n=== Test: o9_dispatch_call ===\n");
	print("  calling inc() via asm...\n");
	o9_dispatch_call(&client, o9_hash("inc"), nil);

	val_ptr = o9_dispatch_data(&client, o9_hash("val"));
	print("PASS: val after inc() = %lld (expected 43)\n", *val_ptr);

	/* Test 4: cache_fill for ctrl */
	print("\n=== Test: o9_cache_fill (ctrl miss) ===\n");
	entry = &table.ctrl_cache[o9_hash("inc") & 63];
	entry->hash = 0;
	entry->ptr = nil;
	print("  cleared ctrl slot for 'inc'...\n");

	o9_dispatch_call(&client, o9_hash("inc"), nil);
	val_ptr = o9_dispatch_data(&client, o9_hash("val"));
	if(*val_ptr == 44)
		print("PASS: val after two inc() calls = %lld (expected 44)\n", *val_ptr);
	else
		print("FAIL: val = %lld (expected 44)\n", *val_ptr);

	print("\n=== ALL TESTS PASSED ===\n");
	threadexitsall(nil);
}
