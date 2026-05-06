#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

extern void* o9_dispatch_data(void *client, ulong hash);

void
threadmain(int argc, char **argv)
{
	o9_Object client;
	o9_AsmTable table;
	ulong h_val;
	int idx;
	void *result;

	USED(argc); USED(argv);
	memset(&client, 0, sizeof(client));
	memset(&table, 0, sizeof(table));
	client.table = &table;

	h_val = o9_hash("val");
	idx = h_val & 63;
	table.data_cache[idx].hash = h_val;
	table.data_cache[idx].ptr = (void*)0xBEEF;

	result = o9_dispatch_data(&client, h_val);
	if(result == (void*)0xBEEF)
		print("PASS: hot dispatch returned 0xBEEF\n");
	else
		print("FAIL: got %p expected 0xBEEF\n", result);

	table.data_cache[idx].hash = 0;
	table.data_cache[idx].ptr = nil;
	result = o9_dispatch_data(&client, h_val);
	print("after evict: %p\n", result);

	table.data_cache[idx].hash = h_val;
	table.data_cache[idx].ptr = (void*)0xCAFE;
	result = o9_dispatch_data(&client, h_val);
	if(result == (void*)0xCAFE)
		print("PASS: re-filled returned 0xCAFE\n");
	else
		print("FAIL: got %p expected 0xCAFE\n", result);

	print("DONE\n");
	threadexitsall(nil);
}
