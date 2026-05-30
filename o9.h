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
    int  distance;		/* -1=same, 0=near/IL, 1=far/TCP */
    char srvname[64];		/* server name for /srv/ cache walk */
} o9_Object;

/* Runtime Functions */
extern int   o9_init_client(void *client, char *srvname, int size);
extern int   o9_connect(void *client, char *addr, char *srvname);
extern void* o9_dispatch_data(void *client, ulong hash);
extern void* o9_dispatch_call(void *client, ulong hash, void *args);
extern void  o9_cache_fill(void *client, ulong hash, int is_ctrl);
extern void  o9_ledger_update(void *client, ulong id, int delta);
extern long  o9_ledger_value(void *client, ulong id);
extern void  o9_clunk(int fd);
extern void* obj9_msgSend(void *receiver, char *method, ulong selector, void *args);

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

/* Slice — lightweight Tier 1 dynamic array */
typedef struct O9Slice O9Slice;
struct O9Slice {
    void *data;
    vlong len;
    vlong cap;
    int elemsize;
};

extern void   o9_slice_init(O9Slice *s, int elemsize);
extern void   o9_slice_append(O9Slice *s, void *val);
extern void*  o9_slice_get(O9Slice *s, vlong idx);
extern void   o9_slice_set(O9Slice *s, vlong idx, void *val);
extern void   o9_slice_free(O9Slice *s);

/* Dict operations — chained hash table, serialized as "key:value\n" */
typedef struct O9DictEntry {
	char *key;
	void *val;		/* generic carrier */
	struct O9DictEntry *next;
} O9DictEntry;

typedef struct {
	O9DictEntry *buckets[64];
} O9Dict;

extern void*  o9_dict_get(O9Dict *d, char *key);
extern void   o9_dict_set(O9Dict *d, char *key, void *val);
extern int    o9_dict_has(O9Dict *d, char *key);
extern char*  o9_dict_serialize(O9Dict *d);
extern void   o9_dict_deserialize(O9Dict *d, char *buf);
extern void   o9_dict_init(O9Dict *d);
extern void   o9_dict_free(O9Dict *d);

#endif
