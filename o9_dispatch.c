#include <u.h>
#include <libc.h>
#include "o9.h"

/*
 * o9_dispatch.c -- C fallback for o9 asm dispatch.
 *
 * Only used when no o9_dispatch_<objtype>.s exists for the target
 * (e.g., a newly ported platform before its asm stub is written).
 * On amd64/386, o9_dispatch_amd64.s / o9_dispatch_386.s is linked
 * instead for L1 performance. Add a new platform by writing its
 * o9_dispatch_<objtype>.s; the mkfile picks it up via $objtype.
 *
 * The C versions are functionally identical:
 *   - o9_dispatch_data: hot hit returns ptr, cold miss calls cache_fill + retry
 *   - o9_dispatch_call: hot hit calls function, cold miss calls cache_fill + retry
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

	if(client == nil) return nil;
	table = ((o9_Object*)client)->table;
	if(table == nil) return nil;

	entry = &table->ctrl_cache[hash & 63];
	if(entry->hash == (u64int)hash && entry->ptr != nil){
		((void (*)(void*))entry->ptr)(args);
		return (void*)1;
	}

	o9_cache_fill(client, hash, 1);
	if(entry->hash == (u64int)hash && entry->ptr != nil){
		((void (*)(void*))entry->ptr)(args);
		return (void*)1;
	}

	return nil;
}
