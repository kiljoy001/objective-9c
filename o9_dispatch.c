#include <u.h>
#include <libc.h>
#include "o9.h"

/* C implementations of the dispatch functions for testing.
 * Replaces the asm stubs in o9_dispatch.s until the asm ABI is sorted. */

extern void o9_cache_fill(o9_AsmTable *table, ulong hash, int is_ctrl);

void*
o9_dispatch_data(void *client, ulong hash)
{
    o9_Object *obj = client;
    o9_AsmTable *table;
    O9CacheEntry *entry;

    if(obj == nil) return nil;
    table = obj->table;
    if(table == nil) return nil;

    entry = &table->data_cache[hash & 63];
    if(entry->hash == hash && entry->ptr != nil)
        return entry->ptr;

    /* Cache miss - call fill and retry */
    o9_cache_fill(table, hash, 0);
    if(entry->hash == hash && entry->ptr != nil)
        return entry->ptr;

    return nil;
}

void*
o9_dispatch_call(void *client, ulong hash, void *args)
{
    o9_Object *obj = client;
    o9_AsmTable *table;
    O9CacheEntry *entry;

    if(obj == nil) return nil;
    table = obj->table;
    if(table == nil) return nil;

    entry = &table->ctrl_cache[hash & 63];
    if(entry->hash == hash && entry->ptr != nil){
        /* Call the cached function pointer */
        void (*fn)(void*) = entry->ptr;
        fn(args);
        return (void*)1;
    }

    /* Cache miss - call fill and retry */
    o9_cache_fill(table, hash, 1);
    if(entry->hash == hash && entry->ptr != nil){
        void (*fn)(void*) = entry->ptr;
        fn(args);
        return (void*)1;
    }

    return nil;
}
