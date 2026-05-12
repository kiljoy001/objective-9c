#ifndef _O9_H_
#define _O9_H_

/* Universal Message Model */
typedef struct O9Msg O9Msg;
typedef struct O9Reply O9Reply;

struct O9Msg {
    ulong sel;
    void *args;
    int nargs;
    void *replyc;		/* Channel* */
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

/* Dual Asm Table Structures */
typedef struct O9CacheEntry O9CacheEntry;
struct O9CacheEntry {
    u64int hash;
    void *ptr;
};

typedef struct o9_AsmTable {
    O9CacheEntry data_cache[64];
    O9CacheEntry ctrl_cache[64];
} o9_AsmTable;

/* Root Object Template
 *
 * WARNING: The asm dispatch (o9_dispatch.s) references fixed offsets:
 *   +0:  int fd
 *   +8:  void *shm_base
 *   +16: o9_AsmTable *table
 *   +24: long ref
 *   +32: void *dispatch_chan  (Channel*)
 * Do NOT reorder the first 5 fields.
 * srvname is appended at the end and is NOT asm-accessible.
 */
typedef struct o9_Object {
    int fd;
    void *shm_base;
    o9_AsmTable *table;
    long ref;           /* ARC — shared reference count */
    void *dispatch_chan;	/* Channel* */
    char srvname[64];		/* server name for /srv/ cache walk */
} o9_Object;

/* Runtime Functions */
extern int   o9_init_client(void *client, char *srvname, int size);
extern void* o9_dispatch_data(void *client, ulong hash);
extern void* o9_dispatch_call(void *client, ulong hash, void *args);
extern void  o9_cache_fill(void *client, ulong hash, int is_ctrl);
extern void  o9_ledger_update(void *client, ulong id, int delta);
extern long  o9_ledger_value(void *client, ulong id);
extern void  o9_clunk(int fd);
extern void* obj9_msgSend(void *receiver, ulong selector, void *args);

/* 9P-native Hashing (djb2) */
static ulong
o9_hash(char *s)
{
    ulong hash = 5381;
    int c;
    while ((c = *s++))
        hash = ((hash << 5) + hash) + c;
    return hash & 0xFFFFFFFFul;
}

/* Array operations — line-based dynamic arrays (one vlong per line) */
extern vlong  o9_array_get(char *data, vlong idx);
extern void   o9_array_set(char **data, vlong idx, vlong val);
extern vlong  o9_array_len(char *data);

#endif
