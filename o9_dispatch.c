#include <u.h>
#include <libc.h>
#include "o9.h"

/* C implementations of the asm dispatch functions.
 * o9_dispatch.s has the same logic but in Plan 9 amd64 assembly.
 * This C version is simpler and works regardless of asm struct layout. */

extern void o9_cache_fill(void *client, ulong hash, int is_ctrl);

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

    /* Cache miss - call fill passing client (has srvname + table) */
    o9_cache_fill(client, hash, 0);
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
        void (*fn)(void*) = entry->ptr;
        fn(args);
        return (void*)1;
    }

    /* Cache miss - call fill passing client */
    o9_cache_fill(client, hash, 1);
    if(entry->hash == hash && entry->ptr != nil){
        void (*fn)(void*) = entry->ptr;
        fn(args);
        return (void*)1;
    }

    return nil;
}
