/*
 * pbt_ledger.c - Property Based Test for the Hashtable ARC Ledger.
 * LAW 1: Global Reference Count must equal the sum of all ID-specific counts.
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
arc_update(ArcLedger *l, ulong id, int delta)
{
    uint h = arc_hash(id);
    ArcEntry *e = &l->entries[h];

    /* In a real implementation, handle collisions. Direct for PBT. */
    if(e->id == 0) e->id = id;
    if(e->id == id) {
        __sync_fetch_and_add(&e->count, delta);
    }
}

long
ledger_sum(ArcLedger *l)
{
    long total = 0;
    int i;
    for(i=0; i<64; i++) {
        total += l->entries[i].count;
    }
    return total;
}

void
test_worker(void *v)
{
    ArcLedger *l = v;
    ulong id = getpid() + (ulong)v; /* Random-ish ID */
    int i;

    for(i=0; i<100000; i++) {
        arc_update(l, id, 1);
        if(i % 10 == 0) arc_update(l, id, -1);
    }
}

void
threadmain(int argc, char **argv)
{
    ArcLedger *l;
    int i, nworkers = 16;
    
    l = malloc(sizeof(ArcLedger));
    memset(l, 0, sizeof(ArcLedger));

    print("PBT: Stress-testing ARC Ledger with %d workers...\n", nworkers);

    for(i=0; i<nworkers; i++) {
        proccreate(test_worker, l, 8192);
    }

    /* Wait for workers to finish (simple sleep for prototype) */
    sleep(2000);

    long final_sum = ledger_sum(l);
    print("Final Ledger Sum: %ld\n", final_sum);

    /* 
     * Property Check: 
     * Each worker does 100,000 increments and 10,000 decrements.
     * Expected sum per worker = 90,000.
     * Total expected = 90,000 * 16 = 1,440,000.
     */
    long expected = 90000 * nworkers;
    if(final_sum == expected) {
        print("PASS: Ledger Integrity Verified.\n");
    } else {
        fprint(2, "FAIL: Ledger Invariant Broken! Expected %ld, Got %ld\n", expected, final_sum);
        threadexitsall("fail");
    }

    threadexitsall(nil);
}
