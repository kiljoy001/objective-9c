#ifndef _O9_H_
#define _O9_H_

#include <u.h>
#include <libc.h>
#include <thread.h>
#include <9p.h>

/* Root Object Template */
typedef struct o9_Object o9_Object;
struct o9_Object {
    int fd;
    void *shm_base;
    void *table;
    Ref ref;
};

/* Dual Asm Table Structures */
typedef struct o9_AsmTable {
    void *data_cache[64];
    void (*ctrl_cache[64])(void*);
} o9_AsmTable;

/* Runtime Functions */
extern void* o9_map(char *srvname, char *propname, long *offset_out);
extern void  o9_ledger_update(void *client, ulong id, int delta);
extern void  o9_clunk(int fd);

/* 9P-native Hashing */
static ulong
o9_hash(char *s)
{
    ulong h = 0;
    while(*s) h = h*31 + *s++;
    return h % 64;
}

#endif
