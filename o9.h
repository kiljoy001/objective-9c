#ifndef _O9_H_
#define _O9_H_

#include <u.h>
#include <libc.h>
#include <thread.h>
#include <9p.h>

/* Universal Message Model */
typedef struct O9Msg O9Msg;
typedef struct O9Reply O9Reply;

struct O9Msg {
    ulong sel;
    void *args;
    int nargs;
    Channel *replyc;
};

struct O9Reply {
    int ok;
    void *ret;
    char *err;
};

/* Shared Memory ABI Header */
typedef struct O9Header O9Header;
struct O9Header {
    u32int magic;
    u16int version;
    u16int flags;
    u64int epoch;
    u64int object_id;
    u64int layout_hash;
};

#define O9_MAGIC 0x09090909

/* Root Object Template */
typedef struct o9_Object o9_Object;
struct o9_Object {
    int fd;
    void *shm_base;
    void *table;
    long ref;
    Channel *dispatch_chan;
};

/* Dual Asm Table Structures (True Hashtable with Verification) */
typedef struct O9CacheEntry O9CacheEntry;
struct O9CacheEntry {
    u64int hash;
    void *ptr;
};

typedef struct o9_AsmTable {
    O9CacheEntry data_cache[64];
    O9CacheEntry ctrl_cache[64];
} o9_AsmTable;

/* Runtime Functions */
extern int   o9_init_client(void *client, char *srvname, int size);
extern void* o9_dispatch_data(void *client, ulong hash);
extern void  o9_ledger_update(void *client, ulong id, int delta);
extern void  o9_clunk(int fd);
extern void* obj9_msgSend(void *receiver, ulong selector, void *args);

/* 9P-native Hashing */
static ulong
o9_hash(char *s)
{
    ulong h = 0;
    while(*s) h = h*31 + *s++;
    return h;
}

#endif
