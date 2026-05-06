#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

extern void* o9_dispatch_data(void *client, ulong hash);
extern void* o9_dispatch_call(void *client, ulong hash, void *args);

int pass, fail;
#define CHECK(cond, msg) do { if(cond) { pass++; print("PASS %s\n", msg); } else { fail++; print("FAIL %s\n", msg); } } while(0)

void method_inc(void *v) { *(vlong*)v = *(vlong*)v + 1; }

void
threadmain(int argc, char **argv)
{
	o9_Object client;
	o9_AsmTable table;
	ulong h_val, h_inc;
	int idx_val, idx_inc;
	void *ptr;
	vlong val;

	USED(argc); USED(argv);
	memset(&client, 0, sizeof(client));
	memset(&table, 0, sizeof(table));
	client.table = &table;
	val = 0;

	h_val = o9_hash("val");
	h_inc = o9_hash("inc");
	idx_val = h_val & 63;
	idx_inc = h_inc & 63;

	/* === data: hot hit === */
	table.data_cache[idx_val].hash = (u64int)h_val;
	table.data_cache[idx_val].ptr = &val;
	ptr = o9_dispatch_data(&client, h_val);
	CHECK(ptr == &val, "data hot hit");
	*(vlong*)ptr = 42;

	/* === data: cold miss (evict) === */
	table.data_cache[idx_val].hash = 0;
	table.data_cache[idx_val].ptr = nil;
	ptr = o9_dispatch_data(&client, h_val);
	CHECK(ptr == nil, "data cold miss returns nil");
	CHECK(val == 42, "val unchanged after miss");

	/* === data: refill === */
	table.data_cache[idx_val].hash = (u64int)h_val;
	table.data_cache[idx_val].ptr = &val;
	ptr = o9_dispatch_data(&client, h_val);
	CHECK(ptr == &val, "data refill works");
	CHECK(*(vlong*)ptr == 42, "val still 42 after refill");

	/* === ctrl: hot hit === */
	table.ctrl_cache[idx_inc].hash = (u64int)h_inc;
	table.ctrl_cache[idx_inc].ptr = (void*)method_inc;
	val = 0;
	o9_dispatch_call(&client, h_inc, &val);
	CHECK(val == 1, "ctrl call inc() -> val=1");
	o9_dispatch_call(&client, h_inc, &val);
	CHECK(val == 2, "ctrl call inc() -> val=2");

	/* === ctrl: cold miss === */
	table.ctrl_cache[idx_inc].hash = 0;
	table.ctrl_cache[idx_inc].ptr = nil;
	ptr = (void*)o9_dispatch_call(&client, h_inc, &val);
	CHECK(ptr == nil, "ctrl cold miss returns nil");
	CHECK(val == 2, "val unchanged after ctrl miss");

	/* === ctrl: refill === */
	table.ctrl_cache[idx_inc].hash = (u64int)h_inc;
	table.ctrl_cache[idx_inc].ptr = (void*)method_inc;
	o9_dispatch_call(&client, h_inc, &val);
	CHECK(val == 3, "ctrl refill -> val=3 after inc");

	print("\n=== RESULTS ===\n");
	print("%d passed, %d failed\n", pass, fail);
	if(fail == 0) print("ALL TESTS PASSED\n");
	threadexitsall(nil);
}
