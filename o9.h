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
    uintptr ret;
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
 * srvname/cachepath/oid/gen are appended at the end and are NOT
 * asm-accessible.
 */
typedef struct o9_Object {
    int fd;
    void *shm_base;
    o9_AsmTable *table;
    long ref;           /* ARC — shared reference count */
    void *dispatch_chan;	/* Channel* */
    int  distance;		/* -1=same, 0=near/IL, 1=far/TCP */
    char srvname[64];		/* server name for /srv/ cache walk */
    char cachepath[128];	/* mounted object cache path */
    char oid[64];		/* registry object id for lookup handles */
    vlong gen;			/* registry generation for lookup handles */
} o9_Object;

/* Runtime Functions */
extern int   o9_ns_app_root(char *buf, int nbuf, char *app);
extern int   o9_ns_service_name(char *buf, int nbuf, char *app, char *type, char *inst);
extern int   o9_ns_object_path(char *buf, int nbuf, char *root, char *inst);
extern int   o9_ns_class_path(char *buf, int nbuf, char *root, char *type);
extern int   o9_ns_ensure_dir(char *path);
extern int   o9_ns_ensure_app(char *root);
extern int   o9_init_client(void *client, char *srvname, int size);
extern int   o9_init_client_path(void *client, char *path, char *srvname, int size);
extern int   o9_connect(void *client, char *addr, char *srvname, int distance);	/* near=0 IL, far=1 TCP */
extern void* o9_dispatch_data(void *client, ulong hash);
extern void* o9_dispatch_call(void *client, ulong hash, void *args);
extern void  o9_cache_fill(void *client, ulong hash, int is_ctrl);
extern void  o9_ledger_update(void *client, ulong id, int delta);
extern long  o9_ledger_value(void *client, ulong id);
extern void  o9_clunk(int fd);
extern void* obj9_msgSend(void *receiver, char *method, ulong selector, void *args);
extern void* obj9_msgSendN(void *receiver, char *method, ulong selector, void *args, int nargs);
extern ulong o9_hash(char *s);
/* Per-proc last-call error for `try` (procdata-backed; each object proc
 * has its own — see o9_runtime.c). NOT a global: parallel actors. */
extern void  o9_set_call_err(char *e);
extern char* o9_get_call_err(void);

/* O9String — immutable language-level string.
 *
 * Source-level `string` lowers to O9String*.  The backing data is kept
 * NUL-terminated for Plan 9 C interop, but len is authoritative.
 */
typedef struct O9String O9String;
struct O9String {
    char *data;
    vlong len;
    long ref;
};

extern O9String* o9_string_new(char *data, vlong len);
extern O9String* o9_string_from_c(char *s);
extern O9String* o9_string_take(char *s);
extern O9String* o9_string_retain(O9String *s);
extern void      o9_string_release(O9String *s);
extern char*     o9_string_data(O9String *s);
extern vlong     o9_string_len(O9String *s);
extern char*     o9_string_cstr(O9String *s);
extern vlong     o9_string_indexof(O9String *s, O9String *needle);
extern vlong     o9_string_startswith(O9String *s, O9String *prefix);
extern vlong     o9_string_endswith(O9String *s, O9String *suffix);
extern O9String* o9_string_slice(O9String *s, vlong start, vlong count);
extern O9String* o9_string_trim(O9String *s);
extern O9String* o9_string_lower(O9String *s);
extern O9String* o9_string_upper(O9String *s);

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
extern void   o9_slice_setgrow(O9Slice *s, vlong idx, void *val);
extern void   o9_slice_free(O9Slice *s);

/* Dict operations — chained hash table, serialized as "key:value\n" */
typedef struct O9DictEntry {
	O9String *key;
	void *val;		/* generic carrier */
	struct O9DictEntry *next;
} O9DictEntry;

typedef struct {
	O9DictEntry *buckets[64];
} O9Dict;

extern void*  o9_dict_get(O9Dict *d, char *key);
extern void   o9_dict_set(O9Dict *d, char *key, void *val);
extern int    o9_dict_has(O9Dict *d, char *key);
extern void*  o9_dict_gets(O9Dict *d, O9String *key);
extern void   o9_dict_sets(O9Dict *d, O9String *key, void *val);
extern int    o9_dict_hass(O9Dict *d, O9String *key);
extern char*  o9_dict_serialize(O9Dict *d);
extern void   o9_dict_deserialize(O9Dict *d, char *buf);
extern void   o9_dict_init(O9Dict *d);
extern void   o9_dict_free(O9Dict *d);

/* Object ledger backed by a private in-memory libtab.
 *
 * The ledger stores stable object identity and location metadata.  The
 * address column is an in-process cache hint, not portable authority; pair it
 * with the generation column before trusting a local pointer.  Persistence is
 * debug-only: generated apps expose sanitized read-only views, not the backing
 * table as a writable file.
 */
typedef struct O9ObjectStore O9ObjectStore;

extern O9ObjectStore* o9_object_store_create(char *path);
extern O9ObjectStore* o9_object_store_create_path(char *root, char *app);
extern void           o9_object_store_close(O9ObjectStore *s);
extern int            o9_object_record(O9ObjectStore *s, char *oid, char *typename,
                           char *class, char *state, char *value, void *addr,
                           vlong gen, char *ns, char *path, char *dial,
                           char *locality, char *owner, char *flags);
extern int            o9_object_register_local(O9ObjectStore *s, char *oid,
                           char *typename, char *class, void *addr,
                           char *ns, char *path);
extern int            o9_object_set_value(O9ObjectStore *s, char *oid, char *value);
extern int            o9_object_set_state(O9ObjectStore *s, char *oid, char *state);
extern char*          o9_object_get(O9ObjectStore *s, char *oid, char *col);
extern int            o9_object_store_serialize(O9ObjectStore *s, char *out, int nout);
extern void*          o9_object_addr(O9ObjectStore *s, char *oid, vlong gen);
extern vlong          o9_object_generation(O9ObjectStore *s, char *oid);

/* Registry actor — live handle table, single-writer via CSP.
 * oid is the universal identity; chan/addr are the in-process fast form,
 * valid only while gen matches. */
typedef struct O9Handle O9Handle;
struct O9Handle {
    char oid[64];
    char class[64];
    void *chan;      /* Channel* dispatch */
    void *addr;      /* Internal* */
    vlong gen;
};

extern int  o9_registry_start(void);
extern int  o9_registry_register(char *oid, char *class, void *chan, void *addr);
extern int  o9_registry_lookup(char *oid, O9Handle *out);
extern int  o9_registry_unregister(char *oid);
extern int  o9_lookup_client(void *client, O9String *oid, int size);
extern O9String* o9_send(void *client, O9String *line);
extern int  o9_selftest_9p_rpc_split(void);

/* Namespace assembly: recipe mirroring + object binds */
extern void o9_ns_recipe(char *root, char *app, char *line);
extern int  o9_ns_bind_obj(char *mount, char *root, char *inst);

/* Crypto stdlib — full practical monocypher surface: attestation
 * (Ed25519 sign/verify, BLAKE2b hash/mac) plus confidentiality
 * (XChaCha20-Poly1305 encrypt/decrypt, X25519 exchange).  Every
 * boundary value is lowercase hex — an encrypted value is still one
 * cat-able string, only its content is sealed. */
extern int  o9_randbytes(uchar *buf, int n);
extern int  o9_crypto_keypair(char *pub, char *sec);
extern int  o9_crypto_sign(char *sechex, uchar *msg, long nmsg, char *sig);
extern int  o9_crypto_verify(char *pubhex, uchar *msg, long nmsg, char *sighex);
extern int  o9_crypto_hash(uchar *msg, long nmsg, char *out);
/* Language builtins over the above: O9String in, O9String out. */
extern O9String* o9_keygen(void);
extern O9String* o9_pubkey(O9String *sec);
extern O9String* o9_sign(O9String *sec, O9String *msg);
extern vlong     o9_verify(O9String *pub, O9String *msg, O9String *sig);
extern O9String* o9_digest(O9String *msg);
extern O9String* o9_mac(O9String *key, O9String *msg);
extern O9String* o9_passkey(O9String *pass, O9String *salt);
extern O9String* o9_encrypt(O9String *key, O9String *msg);
extern O9String* o9_decrypt(O9String *key, O9String *blob);
extern O9String* o9_xpubkey(O9String *sec);
extern O9String* o9_exchange(O9String *sec, O9String *pub);

/* Text/Fs/IO builtins (len/cmp/cat/readfile/writefile/readline) */
extern vlong     o9_str_len(O9String *s);
extern vlong     o9_str_cmp(O9String *a, O9String *b);
extern O9String* o9_str_cat(O9String *a, O9String *b);
extern O9String* o9_readfile(O9String *path);
extern vlong     o9_writefile(O9String *path, O9String *s);
extern O9String* o9_readline(void);
extern void   o9_serve(void);	/* block forever, yielding, so the app keeps serving */

/* Process argv snapshot. Generated threadmain calls o9_process_set_args
 * before user main so stdlib/process.o9 can expose argc/arg safely. */
extern void      o9_process_set_args(int argc, char **argv);
extern vlong     o9_process_argc(void);
extern O9String* o9_process_arg(vlong index);

/* Method table backed by a private in-memory libtab — dispatch source of truth.
 *
 * One store per process; class servers register their methods (including
 * flattened inherited ones) at startup.  Identity columns can be exposed as
 * read-only status data; the thunk address is process-local and only trusted
 * while gen == getpid().
 */
typedef struct O9MethodStore O9MethodStore;

extern O9MethodStore* o9_method_store(void);
extern int            o9_method_store_init(char *root, char *app);
extern void           o9_method_store_close(void);
extern int            o9_method_register(char *class, char *method, ulong sel,
                           int argc, char *ret, char *sig, void *thunk);
extern void*          o9_method_thunk(char *class, ulong sel);
extern int            o9_method_serialize(char *class, char *buf, int nbuf);
extern int            o9_method_store_serialize(char *buf, int nbuf);

/* Class state ledger backed by libtab. */
typedef struct O9State O9State;

extern O9State* o9_state_create(char *classname, char *instname, char **cols, int ncols);
extern O9State* o9_state_create_path(char *root, char *classname, char *instname, char **cols, int ncols);
extern void     o9_state_close(O9State *s);
extern void     o9_state_set(O9State *s, char *col, char *value);
extern void     o9_state_set_int(O9State *s, char *col, vlong value);
extern char*    o9_state_get(O9State *s, char *col);
extern vlong    o9_state_get_int(O9State *s, char *col);
extern int      o9_state_flush(O9State *s, char *path);	/* explicit persist to disk */
extern int      o9_state_serialize(O9State *s, char *out, int nout);	/* debug: dump live tab */

/* Tabula — the language-level table type, over libtab. Text in/out. */
typedef struct O9Tabula O9Tabula;
extern O9Tabula* o9_tab_new(O9String *name, O9String *cols);	/* cols = "a,b,c" */
extern O9Tabula* o9_tab_open(O9String *path);
extern O9String* o9_tab_schema(O9Tabula *t);
extern int       o9_tab_has(O9Tabula *t, O9String *col);
extern int       o9_tab_add(O9Tabula *t, O9String *key);	/* append row, becomes current */
extern int       o9_tab_write(O9Tabula *t, O9String *id, O9String *col, O9String *val);
extern int       o9_tab_set(O9Tabula *t, O9String *col, O9String *val);
extern O9String* o9_tab_get(O9Tabula *t, O9String *col);
extern int       o9_tab_first(O9Tabula *t);	/* start iteration; 1 if a row */
extern int       o9_tab_next(O9Tabula *t);	/* advance; 1 if a row, 0 at end */
extern O9String* o9_tab_read(O9Tabula *t);	/* whole tab as text */
extern O9String* o9_tab_serialize(O9Tabula *t);	/* whole tab as text */
extern O9Tabula* o9_tab_query(O9Tabula *t, O9String *col, O9String *val);
extern int       o9_tab_flush(O9Tabula *t);
extern void      o9_tab_close(O9Tabula *t);

/* MountTable - trusted local interpreter for schema=mounts Tabulae. */
typedef struct O9MountTable O9MountTable;
extern O9MountTable* o9_mount_table_new(O9String *path);
extern int           o9_mount_table_allow_root(O9MountTable *m, O9String *root);
extern int           o9_mount_table_dir(O9MountTable *m, O9String *new, vlong mode);
extern int           o9_mount_table_bind(O9MountTable *m, O9String *old, O9String *new, vlong flag);
extern int           o9_mount_table_mountsrv(O9MountTable *m, O9String *fdsrc, O9String *old, vlong flag, O9String *aname);
extern O9String*     o9_mount_table_schema(O9MountTable *m);
extern int           o9_mount_table_has(O9MountTable *m, O9String *col);
extern O9String*     o9_mount_table_get(O9MountTable *m, O9String *col);
extern int           o9_mount_table_first(O9MountTable *m);
extern int           o9_mount_table_next(O9MountTable *m);
extern O9String*     o9_mount_table_read(O9MountTable *m);
extern O9String*     o9_mount_table_serialize(O9MountTable *m);
extern O9Tabula*     o9_mount_table_query(O9MountTable *m, O9String *col, O9String *val);
extern int           o9_mount_table_flush(O9MountTable *m);
extern int           o9_mount_table_validate(O9MountTable *m);
extern int           o9_mount_table_apply(O9MountTable *m);
extern void          o9_mount_table_close(O9MountTable *m);

/* Task<T> — a one-shot spawn join handle (channel-backed; the numbered
 * channel is internal). spawn returns it; t.await() joins. */
typedef struct O9Task O9Task;
extern O9Task*   o9_task_new(int id);
extern void*     o9_task_chan(O9Task *t);	/* internal: the done Channel* (as void*) */
extern vlong     o9_task_await(O9Task *t);	/* block; value, or per-proc err + 0 */
extern void      o9_task_close(O9Task *t);

#endif
