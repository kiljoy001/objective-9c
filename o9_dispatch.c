#include <u.h>
#include <libc.h>
#include "o9.h"

/*
 * o9_dispatch.c -- C dispatch for o9 asm cache.
 *
 * Replaces o9_dispatch.s with a portable C implementation.
 * The .s file is kept as reference for an eventual assembly
 * optimization, but this C version is functionally identical.
 *
 * Plan 9 ABI note for future asm work:
 *   BP = 1st arg, 8(SP) = 2nd, 16(SP) = 3rd
 *   ulong is 32-bit even on amd64
 *   Callee-saved: BX, BP
 *   Cache entry: {u64int hash, void *ptr} = 16 bytes
 *   data_cache at offset 0, ctrl_cache at offset 1024
 */

extern void o9_cache_fill(void *client, ulong hash, int is_ctrl);

void*
o9_dispatch_data(void *client, ulong hash)
{
	o9_AsmTable *table;
	O9CacheEntry *entry;

	if(client == nil) return nil;
	table = ((o9_Object*)client)->table;
	if(table == nil) return nil;

	entry = &table->data_cache[hash & 63];
	if(entry->hash == (u64int)hash && entry->ptr != nil)
		return entry->ptr;

	/* Cache miss - try fill */
	o9_cache_fill(client, hash, 0);
	if(entry->hash == (u64int)hash && entry->ptr != nil)
		return entry->ptr;

	return nil;
}

void*
o9_dispatch_call(void *client, ulong hash, void *args)
{
	o9_AsmTable *table;
	O9CacheEntry *entry;
	void (*fn)(void*);

	if(client == nil) return nil;
	table = ((o9_Object*)client)->table;
	if(table == nil) return nil;

	entry = &table->ctrl_cache[hash & 63];
	if(entry->hash == (u64int)hash && entry->ptr != nil){
		fn = (void (*)(void*))entry->ptr;
		fn(args);
		return (void*)1;
	}

	/* Cache miss - try fill */
	o9_cache_fill(client, hash, 1);
	if(entry->hash == (u64int)hash && entry->ptr != nil){
		fn = (void (*)(void*))entry->ptr;
		fn(args);
		return (void*)1;
	}

	return nil;
}
