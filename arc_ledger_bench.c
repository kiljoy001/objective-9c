/*
 * arc_ledger_bench.c - Prototype of Hashtable-based ARC Ledger
 */

#include <u.h>
#include <libc.h>
#include <thread.h>

typedef struct ArcEntry {
    ulong id;        
    long count;      
} ArcEntry;

typedef struct ArcLedger {
    ArcEntry entries[64]; 
} ArcLedger;

static uint
arc_hash(ulong id)
{
    return (id * 2654435761U) % 64;
}

void
arc_update(ArcLedger *l, ulong id)
{
    uint h = arc_hash(id);
    ArcEntry *e = &l->entries[h];

    if(e->id == 0) e->id = id;
    
    if(e->id == id){
        /* Use GCC builtin for prototype on Linux */
        __sync_fetch_and_add(&e->count, 1);
    }
}

void
threadmain(int argc, char **argv)
{
    ArcLedger *ledger;
    int i, niters = 10000000;
    vlong start, end;
    ulong my_id = getpid();

    ledger = malloc(sizeof(ArcLedger));
    memset(ledger, 0, sizeof(ArcLedger));

    print("--- Hashtable ARC Ledger Benchmark ---\n");
    print("Iterations: %d\n\n", niters);

    start = nsec();
    for(i = 0; i < niters; i++){
        arc_update(ledger, my_id);
    }
    end = nsec();

    print("Ledger Update: %lld ns/op (Atomic Hashtable)\n", (end - start) / niters);
    print("Total Refs for PID %ld: %ld\n", my_id, ledger->entries[arc_hash(my_id)].count);

    threadexitsall(nil);
}
