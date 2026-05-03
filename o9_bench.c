/*
 * o9_bench.c - Prototype of 9P-as-OOP with "Asm Cache"
 */

#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>

typedef struct Counter {
    volatile vlong val;
} Counter;

Counter *global_counter;

void
threadmain(int argc, char **argv)
{
    int i;
    vlong start, end, diff;
    int niters = 100000000; /* 100M */
    
    global_counter = emalloc9p(sizeof(Counter));
    global_counter->val = 0;

    print("--- 9P-as-OOP Performance Benchmark ---\n");
    print("Iterations: %d\n", niters);

    /* 1. NATIVE C BENCHMARK */
    start = nsec();
    for(i = 0; i < niters; i++){
        global_counter->val++;
    }
    end = nsec();
    diff = end - start;
    print("Native C:   %8lld ms, val=%lld\n", diff / 1000000, global_counter->val);

    /* 2. "ASM CACHE" BENCHMARK */
    volatile vlong *cached_val_ptr = &global_counter->val; 
    start = nsec();
    for(i = 0; i < niters; i++){
        (*cached_val_ptr)++; 
    }
    end = nsec();
    diff = end - start;
    print("Asm Cache:  %8lld ms, val=%lld\n", diff / 1000000, global_counter->val);

    /* Estimated Cold Path */
    print("9P Cold Path: ~250000 ms (Estimated for 100M iters at 2.5us/op)\n");

    threadexitsall(nil);
}
