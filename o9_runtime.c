#include <u.h>
#include <libc.h>
#include <bio.h>
#include <thread.h>
#include "o9.h"
#include "libtab.h"

/* tab_serialize is a real libtab export declared in tab_internal.h (the
 * header split is packaging, not a privacy boundary); we use it to write
 * an in-memory state tab to a program-chosen path on explicit flush. */
extern char *tab_serialize(Tab *t, int *outlen);
extern void o9_tab_discard(Tab *t);

static int
o9_tab_serialize_into(Tab *tab, char *out, int nout)
{
	char *buf;
	int n;

	if(out == nil || nout <= 0)
		return 0;
	out[0] = '\0';
	if(tab == nil)
		return 0;
	buf = tab_serialize(tab, &n);
	if(buf == nil)
		return 0;
	if(n >= nout)
		n = nout - 1;
	memmove(out, buf, n);
	out[n] = '\0';
	free(buf);
	return n;
}

/* 9P encoding helpers — little-endian */
#define PUT2(p, v) do{ (p)[0]=(v)&0xff; (p)[1]=((v)>>8)&0xff; }while(0)
#define PUT4(p, v) do{ (p)[0]=(v)&0xff; (p)[1]=((v)>>8)&0xff; (p)[2]=((v)>>16)&0xff; (p)[3]=((v)>>24)&0xff; }while(0)
#define GET4(p) ((u32int)(p)[0] | ((u32int)(p)[1]<<8) | ((u32int)(p)[2]<<16) | ((u32int)(p)[3]<<24))
#define NOFID 0xFFFFFFFFu

/*
 * o9_runtime.c -- 9front native runtime for o9 objects.
 * Supports Tiered Performance Model:
 *   Tier 1: SHM direct pointer (segattach) via /cache d:<hash>:<offset>
 *   Tier 2: CSP channel dispatch (obj9_msgSend)
 *   Tier 3: 9P network dispatch (fid aux readback)
 */

/* Atomic helpers — 9front has ainc/adec in libc, no portable fallback needed */
static long
o9_atomic_inc(long *p)
{
#ifdef __GNUC__
	return __sync_add_and_fetch(p, 1);
#else
	return ainc(p);
#endif
}

static long
o9_atomic_dec(long *p)
{
#ifdef __GNUC__
	return __sync_sub_and_fetch(p, 1);
#else
	return adec(p);
#endif
}
void o9_cache_fill(void *client, ulong hash, int is_ctrl);

typedef struct O9ProcCtx O9ProcCtx;
struct O9ProcCtx {
	char *err;
	char errbuf[192];
	void *actor_chan;
	char actor_oid[64];
};

static O9ProcCtx*
o9_proc_ctx(void)
{
	O9ProcCtx **pp, *ctx;

	pp = (O9ProcCtx**)procdata();
	if(*pp == nil){
		ctx = mallocz(sizeof(O9ProcCtx), 1);
		if(ctx == nil)
			sysfatal("o9_proc_ctx: malloc");
		*pp = ctx;
	}
	return *pp;
}

/* Last-call error signal for `try`: set non-nil by a failed dispatch,
 * nil on success.  try checks it right after a call to decide whether to
 * propagate.  PER-PROC (via procdata()), NOT a global: every object is
 * its own proc (proccreate) and they run in PARALLEL on SMP 9front, so a
 * global would let two parallel actors' `try` clobber each other's error
 * signal.  The same proc context also records the current actor identity
 * so synchronous handle sends can reject same-actor deadlocks. */
void
o9_set_call_err(char *e)
{
	o9_proc_ctx()->err = e;
}

char*
o9_get_call_err(void)
{
	return o9_proc_ctx()->err;
}

void
o9_actor_enter(void *dispatch_chan, char *oid)
{
	O9ProcCtx *ctx;

	ctx = o9_proc_ctx();
	ctx->actor_chan = dispatch_chan;
	if(oid != nil)
		snprint(ctx->actor_oid, sizeof ctx->actor_oid, "%s", oid);
	else
		ctx->actor_oid[0] = '\0';
}

static int
o9_actor_self_send(void *dispatch_chan, char *method)
{
	O9ProcCtx *ctx;
	char err[192];

	ctx = o9_proc_ctx();
	if(dispatch_chan == nil || ctx->actor_chan == nil ||
	   dispatch_chan != ctx->actor_chan)
		return 0;
	snprint(err, sizeof err,
		"sync actor call to self%s%s%s; use a direct method call",
		method != nil ? " for " : "",
		method != nil ? method : "",
		method != nil ? "()" : "");
	werrstr("%s", err);
	snprint(ctx->errbuf, sizeof ctx->errbuf, "%s", err);
	ctx->err = ctx->errbuf;
	return 1;
}

ulong
o9_hash(char *s)
{
	ulong hash;
	int c;

	hash = 5381;
	while((c = *s++) != 0)
		hash = ((hash << 5) + hash) + c;
	return hash & 0xFFFFFFFFul;
}

int
o9_ns_app_root(char *buf, int nbuf, char *app)
{
	if(buf == nil || nbuf <= 0 || app == nil || app[0] == '\0')
		return -1;
	snprint(buf, nbuf, "/mnt/o9/%s", app);
	return 0;
}

int
o9_ns_service_name(char *buf, int nbuf, char *app, char *type, char *inst)
{
	if(buf == nil || nbuf <= 0 || app == nil || type == nil || inst == nil)
		return -1;
	if(app[0] == '\0' || type[0] == '\0' || inst[0] == '\0')
		return -1;
	snprint(buf, nbuf, "o9.%s.%s.%s", app, type, inst);
	return 0;
}

int
o9_ns_object_path(char *buf, int nbuf, char *root, char *inst)
{
	if(buf == nil || nbuf <= 0 || root == nil || inst == nil)
		return -1;
	if(root[0] == '\0' || inst[0] == '\0')
		return -1;
	snprint(buf, nbuf, "%s/obj/%s", root, inst);
	return 0;
}

int
o9_ns_class_path(char *buf, int nbuf, char *root, char *type)
{
	if(buf == nil || nbuf <= 0 || root == nil || type == nil)
		return -1;
	if(root[0] == '\0' || type[0] == '\0')
		return -1;
	snprint(buf, nbuf, "%s/class/%s", root, type);
	return 0;
}

int
o9_ns_ensure_dir(char *path)
{
	int fd;

	if(path == nil || path[0] == '\0')
		return -1;
	fd = open(path, OREAD);
	if(fd >= 0){
		close(fd);
		return 0;
	}
	fd = create(path, OREAD, DMDIR|0755);
	if(fd < 0)
		return -1;
	close(fd);
	return 0;
}

int
o9_ns_ensure_app(char *root)
{
	char path[256];

	if(root == nil || root[0] == '\0')
		return -1;
	if(o9_ns_ensure_dir("/mnt/o9") < 0)
		return -1;
	if(o9_ns_ensure_dir(root) < 0)
		return -1;
	snprint(path, sizeof path, "%s/obj", root);
	if(o9_ns_ensure_dir(path) < 0)
		return -1;
	snprint(path, sizeof path, "%s/class", root);
	if(o9_ns_ensure_dir(path) < 0)
		return -1;
	snprint(path, sizeof path, "%s/lib", root);
	if(o9_ns_ensure_dir(path) < 0)
		return -1;
	snprint(path, sizeof path, "%s/types", root);
	if(o9_ns_ensure_dir(path) < 0)
		return -1;
	snprint(path, sizeof path, "%s/state", root);
	if(o9_ns_ensure_dir(path) < 0)
		return -1;
	return 0;
}

struct O9ObjectStore {
	Tab *tab;
	char *path;
};

static char *o9_object_cols[] = {
	"oid",
	"typename",
	"class",
	"state",
	"value",
	"addr",
	"gen",
	"ns",
	"path",
	"dial",
	"locality",
	"owner",
	"flags",
};

static TabRow*
o9_object_find_row(O9ObjectStore *s, char *oid)
{
	TabIter *it;
	TabRow *row;

	if(s == nil || s->tab == nil || oid == nil)
		return nil;
	it = tab_search(s->tab, "oid", oid);
	if(it == nil)
		return nil;
	row = tab_iter_next(it);
	tab_iter_close(it);
	return row;
}

static TabRow*
o9_object_ensure_row(O9ObjectStore *s, char *oid)
{
	TabRow *row;

	row = o9_object_find_row(s, oid);
	if(row != nil)
		return row;
	if(s == nil || s->tab == nil || oid == nil || oid[0] == '\0')
		return nil;
	return tab_add_row(s->tab, "oid", oid);
}

static int
o9_object_set_col(O9ObjectStore *s, TabRow *row, char *col, char *val)
{
	if(s == nil || s->tab == nil || row == nil || col == nil)
		return -1;
	if(val == nil)
		val = "";
	return tab_set(s->tab, row, col, val);
}

static void
o9_object_addr_text(char *buf, int nbuf, void *addr)
{
	if(buf == nil || nbuf <= 0)
		return;
	if(addr == nil)
		buf[0] = '\0';
	else
		snprint(buf, nbuf, "0x%llux", (uvlong)(uintptr)addr);
}

static uintptr
o9_object_parse_addr(char *s)
{
	uintptr v;
	int c;

	if(s == nil)
		return 0;
	if(s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s += 2;
	v = 0;
	while((c = *s++) != 0){
		if(c >= '0' && c <= '9')
			c -= '0';
		else if(c >= 'a' && c <= 'f')
			c = c - 'a' + 10;
		else if(c >= 'A' && c <= 'F')
			c = c - 'A' + 10;
		else
			break;
		v = (v << 4) | c;
	}
	return v;
}

O9ObjectStore*
o9_object_store_create(char *path)
{
	O9ObjectStore *s;
	TabColSpec spec[nelem(o9_object_cols)];
	int i;

	if(path == nil || path[0] == '\0')
		return nil;
	s = mallocz(sizeof *s, 1);
	if(s == nil)
		return nil;
	s->path = strdup(path);
	if(s->path == nil){
		free(s);
		return nil;
	}
	memset(spec, 0, sizeof spec);
	for(i = 0; i < nelem(o9_object_cols); i++)
		spec[i].name = o9_object_cols[i];
	s->tab = tab_create(s->path, "o9objects", spec, nelem(spec));
	if(s->tab == nil){
		free(s->path);
		free(s);
		return nil;
	}
	return s;
}

O9ObjectStore*
o9_object_store_create_path(char *root, char *app)
{
	char path[256];

	if(root == nil || root[0] == '\0')
		return nil;
	if(app == nil || app[0] == '\0')
		app = "app";
	USED(root);
	snprint(path, sizeof path, "/dev/null/o9.%s.objects.tab", app);
	return o9_object_store_create(path);
}

void
o9_object_store_close(O9ObjectStore *s)
{
	if(s == nil)
		return;
	o9_tab_discard(s->tab);
	tab_close(s->tab);
	free(s->path);
	free(s);
}

int
o9_object_record(O9ObjectStore *s, char *oid, char *typename, char *class,
	char *state, char *value, void *addr, vlong gen, char *ns, char *path,
	char *dial, char *locality, char *owner, char *flags)
{
	TabRow *row;
	char buf[64];

	if(s == nil || oid == nil || oid[0] == '\0')
		return -1;
	row = o9_object_ensure_row(s, oid);
	if(row == nil)
		return -1;
	if(o9_object_set_col(s, row, "typename", typename) < 0 ||
	   o9_object_set_col(s, row, "class", class) < 0 ||
	   o9_object_set_col(s, row, "state", state != nil ? state : "live") < 0 ||
	   o9_object_set_col(s, row, "value", value) < 0 ||
	   o9_object_set_col(s, row, "ns", ns) < 0 ||
	   o9_object_set_col(s, row, "path", path) < 0 ||
	   o9_object_set_col(s, row, "dial", dial) < 0 ||
	   o9_object_set_col(s, row, "locality", locality != nil ? locality : "same") < 0 ||
	   o9_object_set_col(s, row, "owner", owner) < 0 ||
	   o9_object_set_col(s, row, "flags", flags) < 0)
		return -1;
	o9_object_addr_text(buf, sizeof buf, addr);
	if(o9_object_set_col(s, row, "addr", buf) < 0)
		return -1;
	snprint(buf, sizeof buf, "%lld", gen);
	if(o9_object_set_col(s, row, "gen", buf) < 0)
		return -1;
	return 0;
}

int
o9_object_register_local(O9ObjectStore *s, char *oid, char *typename,
	char *class, void *addr, char *ns, char *path)
{
	char owner[64];
	vlong gen;

	if(s == nil || oid == nil)
		return -1;
	gen = o9_object_generation(s, oid) + 1;
	snprint(owner, sizeof owner, "%ld", (long)getpid());
	return o9_object_record(s, oid, typename, class, "live", nil, addr,
		gen, ns, path, nil, "same", owner, "local");
}

int
o9_object_set_value(O9ObjectStore *s, char *oid, char *value)
{
	TabRow *row;

	row = o9_object_find_row(s, oid);
	if(row == nil)
		return -1;
	if(o9_object_set_col(s, row, "value", value) < 0)
		return -1;
	return 0;
}

/* Reap tombstone: libtab is append-only, so a reaped object marks its
 * node row state=reaped rather than deleting it (auditable history).
 * Graph views filter state=live; the object's tree dir is removed
 * separately by the facade. */
int
o9_object_set_state(O9ObjectStore *s, char *oid, char *state)
{
	TabRow *row;

	row = o9_object_find_row(s, oid);
	if(row == nil)
		return -1;
	if(o9_object_set_col(s, row, "state", state) < 0)
		return -1;
	return 0;
}

char*
o9_object_get(O9ObjectStore *s, char *oid, char *col)
{
	TabRow *row;
	const char *v;

	if(s == nil || oid == nil || col == nil)
		return nil;
	row = o9_object_find_row(s, oid);
	if(row == nil)
		return nil;
	v = tab_get(row, col);
	if(v == nil)
		return nil;
	return (char *)v;
}

int
o9_object_store_serialize(O9ObjectStore *s, char *out, int nout)
{
	if(s == nil)
		return o9_tab_serialize_into(nil, out, nout);
	return o9_tab_serialize_into(s->tab, out, nout);
}

vlong
o9_object_generation(O9ObjectStore *s, char *oid)
{
	char *v;

	v = o9_object_get(s, oid, "gen");
	if(v == nil || v[0] == '\0')
		return 0;
	return strtoll(v, nil, 0);
}

void*
o9_object_addr(O9ObjectStore *s, char *oid, vlong gen)
{
	char *v;

	if(gen != 0 && o9_object_generation(s, oid) != gen)
		return nil;
	v = o9_object_get(s, oid, "addr");
	if(v == nil || v[0] == '\0')
		return nil;
	return (void*)o9_object_parse_addr(v);
}

/* Registry actor — the intra-program bus hub (ARCHITECTURE.md).
 * One proc per app process owns the live handle table: single-writer by
 * construction, no locks.  Handles are CSP values; the object store is
 * the persisted view, the 9P obj/ tree the external one. */

enum { O9RegRegister, O9RegLookup, O9RegUnregister };

typedef struct O9RegReq O9RegReq;
struct O9RegReq {
	int op;
	O9Handle h;
	O9Handle result;
	int ok;
	Channel *replyc;	/* carries O9Handle* into caller storage, or nil */
};

static Channel *o9_regchan;
static O9Handle o9_reg_tab[256];
static int o9_reg_n;

static void
o9_registry_proc(void *v)
{
	O9RegReq *r;
	O9Handle *found, *freep;
	vlong oldgen;
	int i;

	USED(v);
	for(;;){
		r = recvp(o9_regchan);
		if(r == nil)
			continue;
		found = nil;
		freep = nil;
		for(i = 0; i < o9_reg_n; i++)
			if(strcmp(o9_reg_tab[i].oid, r->h.oid) == 0){
				found = &o9_reg_tab[i];
				break;
			}else if(freep == nil && o9_reg_tab[i].chan == nil)
				freep = &o9_reg_tab[i];
		switch(r->op){
		case O9RegRegister:
			if(found == nil && o9_reg_n < nelem(o9_reg_tab))
				found = &o9_reg_tab[o9_reg_n++];
			else if(found == nil)
				found = freep;
			if(found != nil){
				oldgen = found->gen;
				*found = r->h;
				found->gen = oldgen + 1;
				r->result = *found;
				r->ok = 1;
			}
			break;
		case O9RegLookup:
			if(found != nil && found->chan != nil){
				r->result = *found;
				r->ok = 1;
			}
			break;
		case O9RegUnregister:
			if(found != nil){
				found->class[0] = '\0';
				found->chan = nil;
				found->addr = nil;
				found = nil;
			}
			break;
		}
		sendp(r->replyc, r->ok ? &r->result : nil);
	}
}

int
o9_registry_start(void)
{
	if(o9_regchan != nil)
		return 0;
	o9_regchan = chancreate(sizeof(void*), 16);
	if(o9_regchan == nil)
		return -1;
	proccreate(o9_registry_proc, nil, 32768);
	return 0;
}

static O9Handle*
o9_registry_rpc(int op, O9Handle *h)
{
	O9RegReq r;
	O9Handle *res;

	if(o9_regchan == nil)
		return nil;
	memset(&r, 0, sizeof r);
	r.op = op;
	if(h != nil)
		r.h = *h;
	r.replyc = chancreate(sizeof(void*), 1);
	sendp(o9_regchan, &r);
	res = recvp(r.replyc);
	chanfree(r.replyc);
	return res;
}

int
o9_registry_register(char *oid, char *class, void *chan, void *addr)
{
	O9Handle h;

	if(oid == nil || oid[0] == '\0')
		return -1;
	memset(&h, 0, sizeof h);
	strncpy(h.oid, oid, sizeof h.oid - 1);
	if(class != nil)
		strncpy(h.class, class, sizeof h.class - 1);
	h.chan = chan;
	h.addr = addr;
	return o9_registry_rpc(O9RegRegister, &h) != nil ? 0 : -1;
}

int
o9_registry_lookup(char *oid, O9Handle *out)
{
	O9Handle q, *res;

	if(oid == nil || out == nil)
		return -1;
	memset(&q, 0, sizeof q);
	strncpy(q.oid, oid, sizeof q.oid - 1);
	res = o9_registry_rpc(O9RegLookup, &q);
	if(res == nil)
		return -1;
	*out = *res;
	return 0;
}

int
o9_registry_unregister(char *oid)
{
	O9Handle q;

	if(oid == nil)
		return -1;
	memset(&q, 0, sizeof q);
	strncpy(q.oid, oid, sizeof q.oid - 1);
	o9_registry_rpc(O9RegUnregister, &q);
	return 0;
}

/* lookup(oid) builtin: resolve a handle through the rings — registry
 * first (in-process fast form), /srv client init as fallback. */
int
o9_lookup_client(void *client, O9String *oid, int size)
{
	o9_Object *obj = client;
	O9Handle h;
	char *name;

	if(client == nil || oid == nil || size < sizeof(o9_Object))
		return -1;
	name = o9_string_cstr(oid);
	if(name == nil)
		return -1;
	if(o9_registry_lookup(name, &h) == 0){
		memset(client, 0, size);
		obj->dispatch_chan = h.chan;
		obj->shm_base = h.addr;
		obj->distance = -1;
		obj->fd = -1;
		strncpy(obj->srvname, name, sizeof obj->srvname - 1);
		strncpy(obj->oid, name, sizeof obj->oid - 1);
		obj->gen = h.gen;
		free(name);
		return 0;
	}
	if(o9_init_client(client, name, size) < 0){
		free(name);
		return -1;
	}
	free(name);
	return 0;
}

/* Namespace recipe: assembly as data.  Every mount/bind the process
 * performs is mirrored as a line in <root>/state/<app>.namespace so any
 * tool can inspect or replay the composition. */
void
o9_ns_recipe(char *root, char *app, char *line)
{
	char path[256];
	int fd;

	if(root == nil || root[0] == '\0' || line == nil)
		return;
	if(app == nil || app[0] == '\0')
		app = "app";
	snprint(path, sizeof path, "%s/state", root);
	o9_ns_ensure_dir(path);
	snprint(path, sizeof path, "%s/state/%s.namespace", root, app);
	fd = open(path, OWRITE);
	if(fd < 0)
		fd = create(path, OWRITE, 0644);
	else
		seek(fd, 0, 2);
	if(fd < 0)
		return;
	fprint(fd, "%s\n", line);
	close(fd);
}

/* Bind a served instance subtree into <root>/obj/<inst>; failures are
 * non-fatal (the recipe still records the intent). */
int
o9_ns_bind_obj(char *mount, char *root, char *inst)
{
	char src[256], dst[256];

	if(mount == nil || root == nil || inst == nil)
		return -1;
	snprint(src, sizeof src, "%s/%s", mount, inst);
	snprint(dst, sizeof dst, "%s/obj/%s", root, inst);
	if(o9_ns_ensure_dir(dst) < 0)
		return -1;
	return bind(src, dst, MREPL);
}

/* O9String / Text / Fs / IO builtins.  Source-level `string` lowers to
 * O9String*.  The payload is immutable and length-carrying; data is also
 * NUL-terminated so Plan 9 C APIs can be called through explicit helpers. */

O9String*
o9_string_new(char *data, vlong len)
{
	O9String *s;

	if(len < 0)
		len = data != nil ? strlen(data) : 0;
	s = mallocz(sizeof *s, 1);
	if(s == nil)
		return nil;
	s->data = malloc(len + 1);
	if(s->data == nil){
		free(s);
		return nil;
	}
	if(data != nil && len > 0)
		memmove(s->data, data, len);
	s->data[len] = '\0';
	s->len = len;
	s->ref = 1;
	return s;
}

O9String*
o9_string_from_c(char *s)
{
	return o9_string_new(s, s != nil ? strlen(s) : 0);
}

O9String*
o9_string_take(char *s)
{
	O9String *os;

	if(s == nil)
		return nil;
	os = mallocz(sizeof *os, 1);
	if(os == nil){
		free(s);
		return nil;
	}
	os->data = s;
	os->len = strlen(s);
	os->ref = 1;
	return os;
}

O9String*
o9_string_retain(O9String *s)
{
	if(s != nil)
		o9_atomic_inc(&s->ref);
	return s;
}

void
o9_string_release(O9String *s)
{
	if(s == nil)
		return;
	if(o9_atomic_dec(&s->ref) == 0){
		free(s->data);
		free(s);
	}
}

char*
o9_string_data(O9String *s)
{
	return s != nil && s->data != nil ? s->data : "";
}

vlong
o9_string_len(O9String *s)
{
	return s != nil ? s->len : 0;
}

char*
o9_string_cstr(O9String *s)
{
	char *p;
	vlong n;

	n = o9_string_len(s);
	p = malloc(n + 1);
	if(p == nil)
		return nil;
	if(n > 0)
		memmove(p, o9_string_data(s), n);
	p[n] = '\0';
	return p;
}

vlong
o9_str_len(O9String *s)
{
	return o9_string_len(s);
}

vlong
o9_str_cmp(O9String *a, O9String *b)
{
	char *ap, *bp;
	vlong an, bn, n;
	int c;

	ap = o9_string_data(a);
	bp = o9_string_data(b);
	an = o9_string_len(a);
	bn = o9_string_len(b);
	n = an < bn ? an : bn;
	c = n > 0 ? memcmp(ap, bp, n) : 0;
	if(c < 0)
		return -1;
	if(c > 0)
		return 1;
	if(an < bn)
		return -1;
	if(an > bn)
		return 1;
	return 0;
}

O9String*
o9_str_cat(O9String *a, O9String *b)
{
	O9String *out;
	vlong an, bn;

	an = o9_string_len(a);
	bn = o9_string_len(b);
	out = o9_string_new(nil, an + bn);
	if(out == nil)
		return nil;
	if(an > 0)
		memmove(out->data, o9_string_data(a), an);
	if(bn > 0)
		memmove(out->data + an, o9_string_data(b), bn);
	out->data[an + bn] = '\0';
	return out;
}

vlong
o9_string_indexof(O9String *s, O9String *needle)
{
	char *sp, *np;
	vlong sn, nn, i;

	sp = o9_string_data(s);
	np = o9_string_data(needle);
	sn = o9_string_len(s);
	nn = o9_string_len(needle);
	if(nn == 0)
		return 0;
	if(nn > sn)
		return -1;
	for(i = 0; i <= sn - nn; i++)
		if(memcmp(sp + i, np, nn) == 0)
			return i;
	return -1;
}

vlong
o9_string_startswith(O9String *s, O9String *prefix)
{
	vlong sn, pn;

	sn = o9_string_len(s);
	pn = o9_string_len(prefix);
	return pn <= sn && memcmp(o9_string_data(s), o9_string_data(prefix), pn) == 0;
}

vlong
o9_string_endswith(O9String *s, O9String *suffix)
{
	vlong sn, xn;

	sn = o9_string_len(s);
	xn = o9_string_len(suffix);
	return xn <= sn && memcmp(o9_string_data(s) + sn - xn, o9_string_data(suffix), xn) == 0;
}

O9String*
o9_string_slice(O9String *s, vlong start, vlong count)
{
	vlong n;

	n = o9_string_len(s);
	if(start < 0)
		start = 0;
	if(start > n)
		start = n;
	if(count < 0)
		count = 0;
	if(start + count > n)
		count = n - start;
	return o9_string_new(o9_string_data(s) + start, count);
}

O9String*
o9_string_trim(O9String *s)
{
	char *p;
	vlong a, b;

	p = o9_string_data(s);
	a = 0;
	b = o9_string_len(s);
	while(a < b && (p[a] == ' ' || p[a] == '\t' || p[a] == '\n' || p[a] == '\r'))
		a++;
	while(b > a && (p[b-1] == ' ' || p[b-1] == '\t' || p[b-1] == '\n' || p[b-1] == '\r'))
		b--;
	return o9_string_new(p + a, b - a);
}

O9String*
o9_string_lower(O9String *s)
{
	O9String *out;
	char *p;
	vlong i, n;

	n = o9_string_len(s);
	p = o9_string_data(s);
	out = o9_string_new(nil, n);
	if(out == nil)
		return nil;
	for(i = 0; i < n; i++)
		out->data[i] = p[i] >= 'A' && p[i] <= 'Z' ? p[i] + ('a' - 'A') : p[i];
	out->data[n] = '\0';
	return out;
}

O9String*
o9_string_upper(O9String *s)
{
	O9String *out;
	char *p;
	vlong i, n;

	n = o9_string_len(s);
	p = o9_string_data(s);
	out = o9_string_new(nil, n);
	if(out == nil)
		return nil;
	for(i = 0; i < n; i++)
		out->data[i] = p[i] >= 'a' && p[i] <= 'z' ? p[i] - ('a' - 'A') : p[i];
	out->data[n] = '\0';
	return out;
}

O9String*
o9_readfile(O9String *path)
{
	int fd;
	long n, total, cap;
	char *buf, *nb, *p;

	if(path == nil)
		return nil;
	p = o9_string_cstr(path);
	if(p == nil)
		return nil;
	fd = open(p, OREAD);
	free(p);
	if(fd < 0)
		return nil;
	cap = 8192;
	total = 0;
	buf = malloc(cap);
	if(buf == nil){
		close(fd);
		return nil;
	}
	while((n = read(fd, buf + total, cap - total - 1)) > 0){
		total += n;
		if(total + 1 >= cap){
			cap *= 2;
			nb = realloc(buf, cap);
			if(nb == nil)
				break;
			buf = nb;
		}
	}
	close(fd);
	buf[total] = '\0';
	return o9_string_take(buf);
}

vlong
o9_writefile(O9String *path, O9String *s)
{
	int fd;
	char *p;
	vlong n;

	if(path == nil || s == nil)
		return -1;
	p = o9_string_cstr(path);
	if(p == nil)
		return -1;
	fd = create(p, OWRITE, 0644);
	free(p);
	if(fd < 0)
		return -1;
	n = o9_string_len(s);
	if(write(fd, o9_string_data(s), n) != n){
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

O9String*
o9_readline(void)
{
	char buf[4096];
	int i, n;
	char c;

	i = 0;
	while(i < sizeof buf - 1){
		n = read(0, &c, 1);
		if(n <= 0){
			if(i == 0)
				return nil;
			break;
		}
		if(c == '\n')
			break;
		buf[i++] = c;
	}
	buf[i] = '\0';
	return o9_string_new(buf, i);
}

static int o9_argc;
static char **o9_argv;

void
o9_process_set_args(int argc, char **argv)
{
	int i;

	if(o9_argv != nil){
		for(i = 0; i < o9_argc; i++)
			free(o9_argv[i]);
		free(o9_argv);
		o9_argv = nil;
		o9_argc = 0;
	}
	if(argc <= 0 || argv == nil)
		return;
	o9_argv = malloc(argc * sizeof(char*));
	if(o9_argv == nil)
		return;
	for(i = 0; i < argc; i++)
		o9_argv[i] = argv[i] != nil ? strdup(argv[i]) : strdup("");
	o9_argc = argc;
}

vlong
o9_process_argc(void)
{
	return o9_argc;
}

O9String*
o9_process_arg(vlong index)
{
	if(index < 0 || index >= o9_argc || o9_argv == nil)
		return o9_string_new("", 0);
	return o9_string_from_c(o9_argv[index]);
}

/* Block the calling thread forever, yielding the CPU, so a posted 9P
 * server keeps serving.  Unlike `while(true){}` (which spins and starves
 * the server proc under the cooperative thread scheduler), this receives
 * on a channel that never fires — zero CPU, fully yielded. */
void
o9_serve(void)
{
	Channel *idle;
	void *v;

	idle = chancreate(sizeof(void*), 0);
	if(idle == nil){
		/* fall back to a yielding sleep loop if alloc fails */
		for(;;)
			sleep(1000);
	}
	for(;;)
		v = recvp(idle);	/* never returns; keeps the server alive */
	USED(v);
}

/* Method table backed by an in-memory libtab — the dispatch source of truth.
 *
 * One store per process: every generated class server registers its methods
 * (including flattened inherited ones) at startup.  Identity columns are
 * stable enough to expose as read-only status data; thunk addresses are
 * in-process cache hints guarded by gen == getpid(). */

struct O9MethodStore {
	Tab *tab;
	char *path;
};

static O9MethodStore *o9_methods;

static char *o9_method_cols[] = {
	"key",
	"class",
	"method",
	"sel",
	"argc",
	"ret",
	"sig",
	"addr",
	"gen",
};

O9MethodStore*
o9_method_store(void)
{
	return o9_methods;
}

int
o9_method_store_init(char *root, char *app)
{
	O9MethodStore *s;
	TabColSpec spec[nelem(o9_method_cols)];
	char path[256];
	int i;

	if(o9_methods != nil)
		return 0;
	if(root == nil || root[0] == '\0')
		return -1;
	if(app == nil || app[0] == '\0')
		app = "app";
	USED(root);
	snprint(path, sizeof path, "/dev/null/o9.%s.methods.tab", app);

	s = mallocz(sizeof *s, 1);
	if(s == nil)
		return -1;
	s->path = strdup(path);
	if(s->path == nil){
		free(s);
		return -1;
	}
	memset(spec, 0, sizeof spec);
	for(i = 0; i < nelem(o9_method_cols); i++)
		spec[i].name = o9_method_cols[i];
	s->tab = tab_create(s->path, "o9methods", spec, nelem(spec));
	if(s->tab == nil){
		free(s->path);
		free(s);
		return -1;
	}
	o9_methods = s;
	return 0;
}

void
o9_method_store_close(void)
{
	if(o9_methods == nil)
		return;
	o9_tab_discard(o9_methods->tab);
	tab_close(o9_methods->tab);
	free(o9_methods->path);
	free(o9_methods);
	o9_methods = nil;
}

static TabRow*
o9_method_row(char *class, ulong sel)
{
	TabIter *it;
	TabRow *row;
	char key[160];

	if(o9_methods == nil || o9_methods->tab == nil || class == nil)
		return nil;
	snprint(key, sizeof key, "%s/0x%lux", class, sel);
	it = tab_search(o9_methods->tab, "key", key);
	if(it == nil)
		return nil;
	row = tab_iter_next(it);
	tab_iter_close(it);
	return row;
}

int
o9_method_register(char *class, char *method, ulong sel, int argc,
	char *ret, char *sig, void *thunk)
{
	TabRow *row;
	char key[160], buf[64];

	if(o9_methods == nil || class == nil || method == nil)
		return -1;
	row = o9_method_row(class, sel);
	if(row == nil){
		snprint(key, sizeof key, "%s/0x%lux", class, sel);
		row = tab_add_row(o9_methods->tab, "key", key);
	}
	if(row == nil)
		return -1;
	snprint(buf, sizeof buf, "0x%lux", sel);
	if(tab_set(o9_methods->tab, row, "class", class) < 0 ||
	   tab_set(o9_methods->tab, row, "method", method) < 0 ||
	   tab_set(o9_methods->tab, row, "sel", buf) < 0 ||
	   tab_set(o9_methods->tab, row, "ret", ret != nil ? ret : "void") < 0 ||
	   tab_set(o9_methods->tab, row, "sig", sig != nil ? sig : "") < 0)
		return -1;
	snprint(buf, sizeof buf, "%d", argc);
	if(tab_set(o9_methods->tab, row, "argc", buf) < 0)
		return -1;
	o9_object_addr_text(buf, sizeof buf, thunk);
	if(tab_set(o9_methods->tab, row, "addr", buf) < 0)
		return -1;
	snprint(buf, sizeof buf, "%ld", (long)getpid());
	if(tab_set(o9_methods->tab, row, "gen", buf) < 0)
		return -1;
	return 0;
}

void*
o9_method_thunk(char *class, ulong sel)
{
	TabRow *row;
	const char *v;

	row = o9_method_row(class, sel);
	if(row == nil)
		return nil;
	v = tab_get(row, "gen");
	if(v == nil || strtol((char*)v, nil, 0) != (long)getpid())
		return nil;	/* row from an earlier run; address is stale */
	v = tab_get(row, "addr");
	if(v == nil || v[0] == '\0')
		return nil;
	return (void*)o9_object_parse_addr((char*)v);
}

int
o9_method_serialize(char *class, char *buf, int nbuf)
{
	TabIter *it;
	TabRow *row;
	const char *m, *sel, *argc, *ret, *sig;
	char *p;

	if(buf == nil || nbuf <= 0)
		return -1;
	buf[0] = '\0';
	if(o9_methods == nil || o9_methods->tab == nil || class == nil)
		return -1;
	p = buf;
	it = tab_search(o9_methods->tab, "class", class);
	if(it == nil)
		return 0;
	while((row = tab_iter_next(it)) != nil){
		m = tab_get(row, "method");
		sel = tab_get(row, "sel");
		argc = tab_get(row, "argc");
		ret = tab_get(row, "ret");
		sig = tab_get(row, "sig");
		p += snprint(p, buf+nbuf-p, "method %s sel %s argc %s ret %s sig %s\n",
			m != nil ? m : "", sel != nil ? sel : "",
			argc != nil ? argc : "0", ret != nil ? ret : "void",
			sig != nil ? sig : "");
	}
	tab_iter_close(it);
	return p - buf;
}

int
o9_method_store_serialize(char *buf, int nbuf)
{
	if(o9_methods == nil)
		return o9_tab_serialize_into(nil, buf, nbuf);
	return o9_tab_serialize_into(o9_methods->tab, buf, nbuf);
}

struct O9State {
	Tab *tab;
	TabRow *row;
	char *path;
};

static int
o9_state_col_seen(char **cols, int ncols, char *name)
{
	int i;

	if(name == nil)
		return 1;
	for(i = 0; i < ncols; i++)
		if(cols[i] != nil && strcmp(cols[i], name) == 0)
			return 1;
	return 0;
}

static int
o9_state_tab_has_col(Tab *tab, char *name)
{
	int i, n;
	const char *col;

	if(tab == nil || name == nil)
		return 0;
	n = tab_ncolumns(tab);
	for(i = 0; i < n; i++){
		col = tab_colname(tab, i);
		if(col != nil && strcmp(col, name) == 0)
			return 1;
	}
	return 0;
}

static int
o9_state_schema_matches(Tab *tab, char **cols, int ncols)
{
	int i;

	if(tab == nil)
		return 0;
	if(!o9_state_tab_has_col(tab, "id"))
		return 0;
	for(i = 0; i < ncols; i++)
		if(cols[i] != nil && !o9_state_col_seen(cols, i, cols[i]) &&
		   !o9_state_tab_has_col(tab, cols[i]))
			return 0;
	return 1;
}

static TabRow*
o9_state_find_row(Tab *tab, char *instname)
{
	TabIter *it;
	TabRow *row;

	if(tab == nil || instname == nil)
		return nil;
	it = tab_search(tab, "id", instname);
	if(it == nil)
		return nil;
	row = tab_iter_next(it);
	tab_iter_close(it);
	return row;
}

static O9State*
o9_state_create_common(char *root, char *classname, char *instname, char **cols, int ncols)
{
	O9State *s;
	TabColSpec *spec;
	char path[256], dir[256];
	int i, outcols;

	if(classname == nil || classname[0] == '\0')
		classname = "object";
	if(instname == nil || instname[0] == '\0')
		instname = classname;

	outcols = 1;
	for(i = 0; i < ncols; i++)
		if(cols[i] != nil && !o9_state_col_seen(cols, i, cols[i]))
			outcols++;

	spec = mallocz(outcols * sizeof *spec, 1);
	if(spec == nil)
		return nil;
	spec[0].name = "id";
	outcols = 1;
	for(i = 0; i < ncols; i++){
		if(cols[i] == nil || o9_state_col_seen(cols, i, cols[i]))
			continue;
		spec[outcols++].name = cols[i];
	}

	s = mallocz(sizeof *s, 1);
	if(s == nil){
		free(spec);
		return nil;
	}
	USED(dir);
	/* Nominal path only — a label identifying the tab and the default
	 * target for an explicit o9_state_flush.  NOTHING is read from or
	 * written to disk here: object state is a live in-memory tab, not a
	 * file.  root, when present, just names where a flush would default. */
	if(root != nil && root[0] != '\0')
		snprint(path, sizeof path, "%s/state/%s.%s.tab", root, classname, instname);
	else
		snprint(path, sizeof path, "%s.%s.tab", classname, instname);
	s->path = strdup(path);
	if(s->path == nil){
		free(spec);
		free(s);
		return nil;
	}
	/* tab_create builds the tab in memory; the path is where tab_commit
	 * WOULD write, but we never commit unless o9_state_flush is called. */
	s->tab = tab_create(s->path, classname, spec, outcols);
	free(spec);
	if(s->tab == nil){
		free(s->path);
		free(s);
		return nil;
	}
	s->row = o9_state_find_row(s->tab, instname);
	if(s->row == nil)
		s->row = tab_add_row(s->tab, "id", instname);
	if(s->row == nil){
		tab_close(s->tab);
		free(s->path);
		free(s);
		return nil;
	}
	tab_commit(s->tab);
	return s;
}

O9State*
o9_state_create(char *classname, char *instname, char **cols, int ncols)
{
	return o9_state_create_common(nil, classname, instname, cols, ncols);
}

O9State*
o9_state_create_path(char *root, char *classname, char *instname, char **cols, int ncols)
{
	return o9_state_create_common(root, classname, instname, cols, ncols);
}

void
o9_state_close(O9State *s)
{
	if(s == nil)
		return;
	tab_close(s->tab);
	free(s->path);
	free(s);
}

/* In-memory only: mutate the live tab, do NOT touch disk.  Object state
 * is not tied to a file — persistence is an explicit act (o9_state_flush)
 * the program chooses when it wants durability. */
void
o9_state_set(O9State *s, char *col, char *value)
{
	if(s == nil || s->tab == nil || s->row == nil || col == nil)
		return;
	if(value == nil)
		value = "";
	tab_set(s->tab, s->row, col, value);
}

/* Explicit persistence: serialize the in-memory state tab to `path`
 * (a .tab file the program chooses).  This is the opt-in "write my
 * state to disk" primitive — nothing writes automatically.  Returns 0
 * on success, -1 on failure. */
int
o9_state_flush(O9State *s, char *path)
{
	char *buf;
	int n, fd;

	if(s == nil || s->tab == nil || path == nil || path[0] == '\0')
		return -1;
	buf = tab_serialize(s->tab, &n);
	if(buf == nil)
		return -1;
	fd = create(path, OWRITE, 0644);
	if(fd < 0){
		free(buf);
		return -1;
	}
	if(write(fd, buf, n) != n){
		close(fd);
		free(buf);
		return -1;
	}
	close(fd);
	free(buf);
	return 0;
}

void
o9_state_set_int(O9State *s, char *col, vlong value)
{
	char buf[64];

	snprint(buf, sizeof buf, "%lld", value);
	o9_state_set(s, col, buf);
}

/* Serialize the live in-memory state tab into out (debug inspection).
 * Returns bytes written (excluding the terminator), or 0 on failure.
 * Public fields appear plain, private as debug:<field>, secret sealed. */
int
o9_state_serialize(O9State *s, char *out, int nout)
{
	if(s == nil || s->tab == nil)
		return o9_tab_serialize_into(nil, out, nout);
	return o9_tab_serialize_into(s->tab, out, nout);
}

/* ---- Tabula: the language-level table type, over libtab ----
 *
 * A Tabula is a thin wrapper: a Tab plus a "current row" cursor for the
 * add/set build style and an iterator for reading.  o9 exposes it with
 * method syntax (t.write(id, col, val); t.query(col, val); t.read();
 * t.flush()) while keeping the lower-level add/set/get/first/next calls
 * available. Every value in/out is a string — the o9 boundary is text.
 */
struct O9Tabula {
	Tab *tab;
	TabRow *cur;	/* current row: target of set/get, advanced by next */
	TabIter *it;	/* active read iterator */
	char *path;	/* nominal path (where a flush would write) */
};

static int
o9_tab_has_col(O9Tabula *t, char *col)
{
	int i, n;
	const char *name;

	if(t == nil || t->tab == nil || col == nil)
		return 0;
	n = tab_ncolumns(t->tab);
	for(i = 0; i < n; i++){
		name = tab_colname(t->tab, i);
		if(name != nil && strcmp(name, col) == 0)
			return 1;
	}
	return 0;
}

static TabRow*
o9_tab_find_row(O9Tabula *t, char *col, char *val)
{
	TabIter *it;
	TabRow *r;

	if(t == nil || t->tab == nil || col == nil || val == nil)
		return nil;
	it = tab_search(t->tab, col, val);
	if(it == nil)
		return nil;
	r = tab_iter_next(it);
	tab_iter_close(it);
	return r;
}

/* Runtime backing for `new Tabula(name, "col1,col2,...")`: create an
 * in-memory Tabula with the given comma-separated columns. nil on failure. */
O9Tabula*
o9_tab_new(O9String *name, O9String *cols)
{
	O9Tabula *t;
	TabColSpec spec[64];
	char buf[512], *p, *q, *cname, *ccols;
	int n;

	cname = o9_string_cstr(name);
	ccols = o9_string_cstr(cols);
	if(cname == nil || cname[0] == '\0'){
		free(cname);
		cname = strdup("tab");
	}
	t = mallocz(sizeof *t, 1);
	if(t == nil){
		free(cname);
		free(ccols);
		return nil;
	}
	/* column 0 is always "id" — the row head attr tab_add_row keys on,
	 * matching the state-tab schema.  User columns follow. */
	memset(&spec[0], 0, sizeof spec[0]);
	spec[0].name = "id";
	n = 1;
	if(ccols != nil && ccols[0] != '\0'){
		strncpy(buf, ccols, sizeof buf - 1);
		buf[sizeof buf - 1] = '\0';
		p = buf;
		while(p != nil && *p != '\0' && n < nelem(spec)){
			q = strchr(p, ',');
			if(q != nil)
				*q++ = '\0';
			while(*p == ' ') p++;
			if(strcmp(p, "id") == 0){ p = q; continue; }	/* no dup id */
			memset(&spec[n], 0, sizeof spec[n]);
			spec[n].name = strdup(p);
			n++;
			p = q;
		}
	}
	/* nominal path — never written unless the program flushes it */
	{
		char pbuf[128];
		snprint(pbuf, sizeof pbuf, "%s.tab", cname);
		t->path = strdup(pbuf);
	}
	t->tab = tab_create(t->path, cname, spec, n);
	free(cname);
	free(ccols);
	if(t->tab == nil){
		free(t->path);
		free(t);
		return nil;
	}
	return t;
}

/* Runtime backing for `new Tabula(path)`: read an existing .tab file. */
O9Tabula*
o9_tab_open(O9String *path)
{
	O9Tabula *t;
	char *cpath;

	if(path == nil)
		return nil;
	cpath = o9_string_cstr(path);
	if(cpath == nil || cpath[0] == '\0'){
		free(cpath);
		return nil;
	}
	t = mallocz(sizeof *t, 1);
	if(t == nil){
		free(cpath);
		return nil;
	}
	t->tab = tab_open(cpath);
	if(t->tab == nil){
		free(t);
		free(cpath);
		return nil;
	}
	t->path = strdup(cpath);
	free(cpath);
	return t;
}

/* t.schema() — return the schema name carried by the Tabula. */
O9String*
o9_tab_schema(O9Tabula *t)
{
	const char *s;

	if(t == nil || t->tab == nil)
		return o9_string_from_c("");
	s = tab_schema_name(t->tab);
	return o9_string_from_c(s != nil ? (char*)s : "");
}

/* t.has(col) — true when col is present in the schema. */
int
o9_tab_has(O9Tabula *t, O9String *col)
{
	char *ccol;
	int ok;

	if(t == nil || t->tab == nil || col == nil)
		return 0;
	ccol = o9_string_cstr(col);
	if(ccol == nil)
		return 0;
	ok = o9_tab_has_col(t, ccol);
	free(ccol);
	return ok;
}

/* t.add(key) — append a row keyed by "id"=key; it becomes the current
 * row for subsequent set().  Returns 0 / -1. */
int
o9_tab_add(O9Tabula *t, O9String *key)
{
	char *ckey;
	int ok;

	if(t == nil || t->tab == nil || key == nil)
		return -1;
	ckey = o9_string_cstr(key);
	if(ckey == nil)
		return -1;
	t->cur = tab_add_row(t->tab, "id", ckey);
	ok = t->cur != nil ? 0 : -1;
	free(ckey);
	return ok;
}

/* t.write(id, col, val) — update an existing id row or create it.
 * The id is the row identity; writing the id column itself is rejected
 * unless the value matches the row id. */
int
o9_tab_write(O9Tabula *t, O9String *id, O9String *col, O9String *val)
{
	TabRow *r;
	char *cid, *ccol, *cval;
	const char *head;
	int rv;

	if(t == nil || t->tab == nil || id == nil || col == nil || val == nil)
		return -1;
	cid = o9_string_cstr(id);
	ccol = o9_string_cstr(col);
	cval = o9_string_cstr(val);
	if(cid == nil || ccol == nil || cval == nil){
		free(cid);
		free(ccol);
		free(cval);
		return -1;
	}
	if(cid[0] == '\0' || !o9_tab_has_col(t, ccol)){
		free(cid);
		free(ccol);
		free(cval);
		return -1;
	}
	head = tab_colname(t->tab, 0);
	if(head == nil)
		head = "id";
	if(strcmp(ccol, head) == 0 && strcmp(cid, cval) != 0){
		free(cid);
		free(ccol);
		free(cval);
		return -1;
	}
	r = o9_tab_find_row(t, (char*)head, cid);
	if(r == nil)
		r = tab_add_row(t->tab, head, cid);
	if(r == nil){
		free(cid);
		free(ccol);
		free(cval);
		return -1;
	}
	rv = strcmp(ccol, head) == 0 ? 0 : tab_set(t->tab, r, ccol, cval);
	t->cur = r;
	free(cid);
	free(ccol);
	free(cval);
	return rv;
}

/* t.set(col, val) — set a cell on the current row. */
int
o9_tab_set(O9Tabula *t, O9String *col, O9String *val)
{
	char *ccol, *cval;
	int r;

	if(t == nil || t->tab == nil || t->cur == nil || col == nil)
		return -1;
	ccol = o9_string_cstr(col);
	cval = o9_string_cstr(val);
	if(ccol == nil || cval == nil){
		free(ccol);
		free(cval);
		return -1;
	}
	r = tab_set(t->tab, t->cur, ccol, cval);
	free(ccol);
	free(cval);
	return r;
}

/* t.get(col) — read a cell from the current row (empty string if none). */
O9String*
o9_tab_get(O9Tabula *t, O9String *col)
{
	const char *v;
	char *ccol;

	if(t == nil || t->cur == nil || col == nil)
		return o9_string_from_c("");
	ccol = o9_string_cstr(col);
	if(ccol == nil)
		return o9_string_from_c("");
	v = tab_get(t->cur, ccol);
	free(ccol);
	return o9_string_from_c(v != nil ? (char*)v : "");
}

/* t.first() — start iteration; sets current row to the first, or nil.
 * Returns 1 if there is a row, 0 if empty. */
int
o9_tab_first(O9Tabula *t)
{
	if(t == nil || t->tab == nil)
		return 0;
	if(t->it != nil)
		tab_iter_close(t->it);
	t->it = tab_iter(t->tab);
	if(t->it == nil){
		t->cur = nil;
		return 0;
	}
	t->cur = tab_iter_next(t->it);
	return t->cur != nil ? 1 : 0;
}

/* t.next() — advance to the next row.  Returns 1 if a row is now
 * current, 0 at end (iterator closed). */
int
o9_tab_next(O9Tabula *t)
{
	if(t == nil || t->it == nil)
		return 0;
	t->cur = tab_iter_next(t->it);
	if(t->cur == nil){
		tab_iter_close(t->it);
		t->it = nil;
		return 0;
	}
	return 1;
}

/* t.read()/t.serialize() — the whole tab as text bytes. This is the
 * on-the-wire / exportable form. */
O9String*
o9_tab_read(O9Tabula *t)
{
	char *buf;
	int n;
	if(t == nil || t->tab == nil)
		return o9_string_from_c("");
	buf = tab_serialize(t->tab, &n);
	if(buf == nil)
		return o9_string_from_c("");
	return o9_string_take(buf);
}

O9String*
o9_tab_serialize(O9Tabula *t)
{
	return o9_tab_read(t);
}

/* t.query(col, val) — return a new Tabula containing rows where
 * col == val.  This is a direct wrapper over libtab's tab_search. */
O9Tabula*
o9_tab_query(O9Tabula *t, O9String *col, O9String *val)
{
	O9Tabula *out;
	TabColSpec *spec;
	TabIter *it;
	TabRow *r, *nr;
	char *ccol, *cval;
	const char *schema, *head, *hv, *cv;
	int i, n;

	if(t == nil || t->tab == nil || col == nil || val == nil)
		return nil;
	ccol = o9_string_cstr(col);
	cval = o9_string_cstr(val);
	if(ccol == nil || cval == nil){
		free(ccol);
		free(cval);
		return nil;
	}
	if(!o9_tab_has_col(t, ccol)){
		free(ccol);
		free(cval);
		return nil;
	}
	n = tab_ncolumns(t->tab);
	if(n <= 0){
		free(ccol);
		free(cval);
		return nil;
	}
	spec = mallocz(n * sizeof *spec, 1);
	if(spec == nil){
		free(ccol);
		free(cval);
		return nil;
	}
	for(i = 0; i < n; i++){
		spec[i].name = tab_colname(t->tab, i);
		spec[i].type = tab_coltype(t->tab, i);
		spec[i].algo = tab_col_attr(t->tab, spec[i].name, "algo");
		spec[i].signer = tab_col_attr(t->tab, spec[i].name, "signer");
	}
	out = mallocz(sizeof *out, 1);
	if(out == nil){
		free(spec);
		free(ccol);
		free(cval);
		return nil;
	}
	schema = tab_schema_name(t->tab);
	if(schema == nil)
		schema = "tab";
	out->path = smprint("%s.query.tab", schema);
	if(out->path == nil){
		free(out);
		free(spec);
		free(ccol);
		free(cval);
		return nil;
	}
	out->tab = tab_create(out->path, schema, spec, n);
	free(spec);
	if(out->tab == nil){
		free(out->path);
		free(out);
		free(ccol);
		free(cval);
		return nil;
	}
	head = tab_colname(t->tab, 0);
	if(head == nil)
		head = "id";
	it = tab_search(t->tab, ccol, cval);
	if(it != nil){
		while((r = tab_iter_next(it)) != nil){
			hv = tab_get(r, head);
			if(hv == nil)
				hv = "";
			nr = tab_add_row(out->tab, head, hv);
			if(nr == nil)
				continue;
			for(i = 1; i < n; i++){
				cv = tab_get(r, tab_colname(t->tab, i));
				if(cv != nil)
					tab_set(out->tab, nr, tab_colname(t->tab, i), cv);
			}
		}
		tab_iter_close(it);
	}
	free(ccol);
	free(cval);
	return out;
}

/* t.flush() — persist the in-memory Tabula to its backing path. */
int
o9_tab_flush(O9Tabula *t)
{
	if(t == nil || t->tab == nil)
		return -1;
	return tab_commit(t->tab);
}

void
o9_tab_close(O9Tabula *t)
{
	if(t == nil)
		return;
	if(t->it != nil)
		tab_iter_close(t->it);
	if(t->tab != nil){
		/* o9 Tabula persistence is explicit: write/query mutate memory,
		 * flush persists, and close discards unflushed changes. */
		o9_tab_discard(t->tab);
		tab_close(t->tab);
	}
	free(t->path);
	free(t);
}

/* ---- MountTable: Tabula-backed namespace syscall parameter table ----
 *
 * MountTable owns a schema=mounts Tabula. Users add entries through
 * typed methods that mirror the namespace calls:
 *   bind(old, new, flag)       -> call=bind old=... new=... flag=...
 *   mountsrv(fd, old, flag, aname) -> call=mountsrv fd=/srv/... old=...
 *   dir(new, mode)             -> call=dir new=... mode=...
 *
 * The serialized tab is inert transport data. apply() validates it and
 * interprets the cells against an allowRoot(), so the same tab can be
 * replayed under a different receiver-side namespace root. */
struct O9MountTable {
	O9Tabula *spec;
	char *root;
	vlong seq;
};

static char *o9_mt_cols = "call,fd,old,new,flag,aname,mode";

static int
o9_mt_bad_text0(char *s, int emptyok)
{
	uchar *p;

	if(s == nil)
		return 1;
	if(!emptyok && s[0] == '\0')
		return 1;
	for(p = (uchar*)s; *p != 0; p++)
		if(*p < 0x20 || *p == 0x7f)
			return 1;
	return 0;
}

static int
o9_mt_bad_text(char *s)
{
	return o9_mt_bad_text0(s, 0);
}

static int
o9_mt_has_dotdot(char *s)
{
	char *p;
	int atseg;

	if(s == nil)
		return 1;
	atseg = 1;
	for(p = s; ; p++){
		if(atseg && p[0] == '.' && p[1] == '.' &&
		   (p[2] == '/' || p[2] == '\0'))
			return 1;
		if(*p == '\0')
			break;
		atseg = *p == '/';
	}
	return 0;
}

static int
o9_mt_target_ok(char *target)
{
	if(o9_mt_bad_text(target))
		return 0;
	if(target[0] == '/')
		return 0;
	if(strcmp(target, ".") == 0)
		return 1;
	return !o9_mt_has_dotdot(target);
}

static int
o9_mt_source_ok(char *source)
{
	if(o9_mt_bad_text(source))
		return 0;
	if(source[0] != '/' && source[0] != '#')
		return 0;
	return !o9_mt_has_dotdot(source);
}

static int
o9_mt_srv_source_ok(char *source)
{
	if(!o9_mt_source_ok(source))
		return 0;
	return strncmp(source, "/srv/", 5) == 0;
}

static int
o9_mt_flag_ok(vlong flag)
{
	vlong place;

	if(flag < 0 || (flag & ~7) != 0)
		return 0;
	place = flag & 3;
	if(place == 3)
		return 0;
	return 1;
}

static int
o9_mt_mode_ok(vlong mode)
{
	return mode >= 0 && mode <= 0777;
}

static int
o9_mt_parse_vlong(char *s, vlong *out)
{
	char *end;
	vlong v;

	if(out == nil || o9_mt_bad_text(s))
		return -1;
	v = strtoll(s, &end, 0);
	if(end == s || *end != '\0')
		return -1;
	*out = v;
	return 0;
}

static int
o9_mt_join(char *out, int nout, char *root, char *target)
{
	if(out == nil || nout <= 0 || root == nil || target == nil)
		return -1;
	if(!o9_mt_target_ok(target))
		return -1;
	if(strcmp(target, ".") == 0)
		snprint(out, nout, "%s", root);
	else
		snprint(out, nout, "%s/%s", root, target);
	return 0;
}

static int
o9_mt_ensure_dir_mode(char *path, vlong mode)
{
	char buf[512], *p;
	int fd;

	if(o9_mt_bad_text(path) || !o9_mt_mode_ok(mode))
		return -1;
	snprint(buf, sizeof buf, "%s", path);
	for(p = buf + 1; *p != '\0'; p++){
		if(*p != '/')
			continue;
		*p = '\0';
		if(o9_ns_ensure_dir(buf) < 0)
			return -1;
		*p = '/';
	}
	fd = open(buf, OREAD);
	if(fd >= 0){
		close(fd);
		return 0;
	}
	fd = create(buf, OREAD, DMDIR|(int)mode);
	if(fd < 0)
		return -1;
	close(fd);
	return 0;
}

static int
o9_mt_ensure_dir_p(char *path)
{
	char buf[512], *p;

	if(o9_mt_bad_text(path))
		return -1;
	snprint(buf, sizeof buf, "%s", path);
	for(p = buf + 1; *p != '\0'; p++){
		if(*p != '/')
			continue;
		*p = '\0';
		if(o9_ns_ensure_dir(buf) < 0)
			return -1;
		*p = '/';
	}
	return o9_ns_ensure_dir(buf);
}

static int
o9_mt_parse_flag(char *s, int *out)
{
	vlong v;

	if(out == nil)
		return -1;
	if(o9_mt_parse_vlong(s, &v) < 0 || !o9_mt_flag_ok(v))
		return -1;
	*out = (int)v;
	return 0;
}

static O9Tabula*
o9_mt_tab_new(void)
{
	O9String *name, *cols;
	O9Tabula *t;

	name = o9_string_from_c("mounts");
	cols = o9_string_from_c(o9_mt_cols);
	t = o9_tab_new(name, cols);
	o9_string_release(name);
	o9_string_release(cols);
	return t;
}

static int
o9_mt_schema_ok(O9Tabula *t)
{
	const char *schema;

	if(t == nil || t->tab == nil)
		return 0;
	schema = tab_schema_name(t->tab);
	if(schema == nil || strcmp(schema, "mounts") != 0)
		return 0;
	return o9_tab_has_col(t, "call") &&
		o9_tab_has_col(t, "fd") &&
		o9_tab_has_col(t, "old") &&
		o9_tab_has_col(t, "new") &&
		o9_tab_has_col(t, "flag") &&
		o9_tab_has_col(t, "aname") &&
		o9_tab_has_col(t, "mode");
}

static void
o9_mt_seed_seq(O9MountTable *m)
{
	TabIter *it;

	if(m == nil || m->spec == nil || m->spec->tab == nil)
		return;
	it = tab_iter(m->spec->tab);
	if(it == nil)
		return;
	while(tab_iter_next(it) != nil)
		m->seq++;
	tab_iter_close(it);
}

O9MountTable*
o9_mount_table_new(O9String *path)
{
	O9MountTable *m;

	m = mallocz(sizeof *m, 1);
	if(m == nil)
		return nil;
	if(path == nil)
		m->spec = o9_mt_tab_new();
	else
		m->spec = o9_tab_open(path);
	if(!o9_mt_schema_ok(m->spec)){
		if(m->spec != nil)
			o9_tab_close(m->spec);
		free(m);
		return nil;
	}
	o9_mt_seed_seq(m);
	return m;
}

static int
o9_mt_add_entry(O9MountTable *m, char *call, char *fd, char *old,
	char *new, vlong flag, char *aname, vlong mode)
{
	TabRow *r;
	char id[32], fbuf[32], mbuf[32];
	int tries;

	if(m == nil || m->spec == nil || m->spec->tab == nil || call == nil)
		return -1;
	for(tries = 0; tries < 1000000; tries++){
		snprint(id, sizeof id, "m%lld", m->seq++);
		if(o9_tab_find_row(m->spec, "id", id) == nil)
			break;
	}
	if(tries >= 1000000)
		return -1;
	r = tab_add_row(m->spec->tab, "id", id);
	if(r == nil)
		return -1;
	snprint(fbuf, sizeof fbuf, "%lld", flag);
	snprint(mbuf, sizeof mbuf, "%lld", mode);
	if(tab_set(m->spec->tab, r, "call", call) < 0)
		return -1;
	if(fd != nil && fd[0] != '\0' && tab_set(m->spec->tab, r, "fd", fd) < 0)
		return -1;
	if(old != nil && old[0] != '\0' && tab_set(m->spec->tab, r, "old", old) < 0)
		return -1;
	if(new != nil && new[0] != '\0' && tab_set(m->spec->tab, r, "new", new) < 0)
		return -1;
	if(tab_set(m->spec->tab, r, "flag", fbuf) < 0)
		return -1;
	if(aname != nil && aname[0] != '\0' && tab_set(m->spec->tab, r, "aname", aname) < 0)
		return -1;
	if(mode >= 0 && tab_set(m->spec->tab, r, "mode", mbuf) < 0)
		return -1;
	return 0;
}

int
o9_mount_table_allow_root(O9MountTable *m, O9String *root)
{
	char *r;

	if(m == nil || root == nil)
		return -1;
	r = o9_string_cstr(root);
	if(r == nil)
		return -1;
	if(r[0] != '/' || o9_mt_has_dotdot(r) || o9_mt_bad_text(r)){
		free(r);
		return -1;
	}
	if(o9_mt_ensure_dir_p(r) < 0){
		free(r);
		return -1;
	}
	free(m->root);
	m->root = r;
	return 0;
}

int
o9_mount_table_dir(O9MountTable *m, O9String *new, vlong mode)
{
	char *cnew;
	int rv;

	if(m == nil || new == nil || !o9_mt_mode_ok(mode))
		return -1;
	cnew = o9_string_cstr(new);
	if(cnew == nil)
		return -1;
	if(!o9_mt_target_ok(cnew)){
		free(cnew);
		return -1;
	}
	rv = o9_mt_add_entry(m, "dir", nil, nil, cnew, 0, nil, mode);
	free(cnew);
	return rv;
}

int
o9_mount_table_bind(O9MountTable *m, O9String *old, O9String *new, vlong flag)
{
	char *cold, *cnew;
	int rv;

	if(m == nil || old == nil || new == nil || !o9_mt_flag_ok(flag))
		return -1;
	cold = o9_string_cstr(old);
	cnew = o9_string_cstr(new);
	if(cold == nil || cnew == nil){
		free(cold);
		free(cnew);
		return -1;
	}
	if(!o9_mt_source_ok(cold) || !o9_mt_target_ok(cnew)){
		free(cold);
		free(cnew);
		return -1;
	}
	rv = o9_mt_add_entry(m, "bind", nil, cold, cnew, flag, nil, -1);
	free(cold);
	free(cnew);
	return rv;
}

int
o9_mount_table_mountsrv(O9MountTable *m, O9String *fdsrc, O9String *old,
	vlong flag, O9String *aname)
{
	char *cfd, *cold, *caname;
	int rv;

	if(m == nil || fdsrc == nil || old == nil || aname == nil ||
	   !o9_mt_flag_ok(flag))
		return -1;
	cfd = o9_string_cstr(fdsrc);
	cold = o9_string_cstr(old);
	caname = o9_string_cstr(aname);
	if(cfd == nil || cold == nil || caname == nil){
		free(cfd);
		free(cold);
		free(caname);
		return -1;
	}
	if(!o9_mt_srv_source_ok(cfd) || !o9_mt_target_ok(cold) ||
	   o9_mt_bad_text0(caname, 1)){
		free(cfd);
		free(cold);
		free(caname);
		return -1;
	}
	rv = o9_mt_add_entry(m, "mountsrv", cfd, cold, nil, flag, caname, -1);
	free(cfd);
	free(cold);
	free(caname);
	return rv;
}

O9String*
o9_mount_table_schema(O9MountTable *m)
{
	return o9_tab_schema(m != nil ? m->spec : nil);
}

int
o9_mount_table_has(O9MountTable *m, O9String *col)
{
	return o9_tab_has(m != nil ? m->spec : nil, col);
}

O9String*
o9_mount_table_get(O9MountTable *m, O9String *col)
{
	return o9_tab_get(m != nil ? m->spec : nil, col);
}

int
o9_mount_table_first(O9MountTable *m)
{
	return o9_tab_first(m != nil ? m->spec : nil);
}

int
o9_mount_table_next(O9MountTable *m)
{
	return o9_tab_next(m != nil ? m->spec : nil);
}

O9String*
o9_mount_table_read(O9MountTable *m)
{
	return o9_tab_read(m != nil ? m->spec : nil);
}

O9String*
o9_mount_table_serialize(O9MountTable *m)
{
	return o9_mount_table_read(m);
}

O9Tabula*
o9_mount_table_query(O9MountTable *m, O9String *col, O9String *val)
{
	return o9_tab_query(m != nil ? m->spec : nil, col, val);
}

int
o9_mount_table_flush(O9MountTable *m)
{
	return o9_tab_flush(m != nil ? m->spec : nil);
}

int
o9_mount_table_validate(O9MountTable *m)
{
	TabIter *it;
	TabRow *r;
	const char *call, *fdsrc, *old, *new, *flag, *aname, *mode;
	vlong mv;
	int f;

	if(m == nil || m->spec == nil || m->spec->tab == nil || m->root == nil)
		return -1;
	if(!o9_mt_schema_ok(m->spec))
		return -1;
	it = tab_iter(m->spec->tab);
	if(it == nil)
		return -1;
	while((r = tab_iter_next(it)) != nil){
		call = tab_get(r, "call");
		fdsrc = tab_get(r, "fd");
		old = tab_get(r, "old");
		new = tab_get(r, "new");
		flag = tab_get(r, "flag");
		aname = tab_get(r, "aname");
		mode = tab_get(r, "mode");
		if(call == nil)
			goto bad;
		if(strcmp(call, "dir") == 0){
			if(!o9_mt_target_ok((char*)new) ||
			   o9_mt_parse_vlong((char*)mode, &mv) < 0 ||
			   !o9_mt_mode_ok(mv))
				goto bad;
			continue;
		}
		if(strcmp(call, "bind") == 0){
			if(!o9_mt_source_ok((char*)old) ||
			   !o9_mt_target_ok((char*)new) ||
			   o9_mt_parse_flag((char*)flag, &f) < 0)
				goto bad;
			continue;
		}
		if(strcmp(call, "mountsrv") == 0){
			if(!o9_mt_srv_source_ok((char*)fdsrc) ||
			   !o9_mt_target_ok((char*)old) ||
			   o9_mt_parse_flag((char*)flag, &f) < 0 ||
			   (aname != nil && o9_mt_bad_text0((char*)aname, 1)))
				goto bad;
			continue;
		}
		goto bad;
	}
	tab_iter_close(it);
	return 0;
bad:
	tab_iter_close(it);
	return -1;
}

int
o9_mount_table_apply(O9MountTable *m)
{
	TabIter *it;
	TabRow *r;
	const char *call, *fdsrc, *old, *new, *flag, *aname, *mode;
	char dst[512];
	int f, fd, rv;
	vlong mv;

	if(o9_mount_table_validate(m) < 0)
		return -1;
	if(o9_mt_ensure_dir_p(m->root) < 0)
		return -1;
	it = tab_iter(m->spec->tab);
	if(it == nil)
		return -1;
	while((r = tab_iter_next(it)) != nil){
		call = tab_get(r, "call");
		fdsrc = tab_get(r, "fd");
		old = tab_get(r, "old");
		new = tab_get(r, "new");
		flag = tab_get(r, "flag");
		aname = tab_get(r, "aname");
		mode = tab_get(r, "mode");
		if(strcmp(call, "dir") == 0){
			if(o9_mt_join(dst, sizeof dst, m->root, (char*)new) < 0)
				goto bad;
			if(o9_mt_parse_vlong((char*)mode, &mv) < 0)
				goto bad;
			if(o9_mt_ensure_dir_mode(dst, mv) < 0)
				goto bad;
			continue;
		}
		if(strcmp(call, "bind") == 0){
			if(o9_mt_join(dst, sizeof dst, m->root, (char*)new) < 0)
				goto bad;
			if(o9_mt_parse_flag((char*)flag, &f) < 0)
				goto bad;
			if(o9_mt_ensure_dir_p(dst) < 0)
				goto bad;
			if(bind((char*)old, dst, f) < 0)
				goto bad;
			continue;
		}
		if(strcmp(call, "mountsrv") == 0){
			if(o9_mt_join(dst, sizeof dst, m->root, (char*)old) < 0)
				goto bad;
			if(o9_mt_parse_flag((char*)flag, &f) < 0)
				goto bad;
			if(o9_mt_ensure_dir_p(dst) < 0)
				goto bad;
			fd = open((char*)fdsrc, ORDWR);
			if(fd < 0)
				goto bad;
			rv = mount(fd, -1, dst, f, aname != nil ? (char*)aname : "");
			close(fd);
			if(rv < 0)
				goto bad;
			continue;
		}
		goto bad;
	}
	tab_iter_close(it);
	return 0;
bad:
	tab_iter_close(it);
	return -1;
}

void
o9_mount_table_close(O9MountTable *m)
{
	if(m == nil)
		return;
	free(m->root);
	if(m->spec != nil)
		o9_tab_close(m->spec);
	free(m);
}

/* ---- Task<T>: a one-shot spawn JOIN HANDLE (see CONCURRENCY.md) ----
 *
 * spawn f(args) returns a Task<T>. Internally channel-backed (the
 * "numbered channel" — compiler/runtime plumbing, never user-facing): a
 * forwarder proc puts the spawned method's O9Reply (value+error) into
 * `done`. t.await() blocks on it, sets the caller's PER-PROC call-error
 * on failure (so `try t.await()` propagates), and returns the value.
 * Result carries value AND error, so spawned failures never route
 * through a global.
 */
struct O9Task {
	int id;			/* spawn index (the "number") */
	Channel *done;		/* forwarder sends the O9Reply* here */
	O9Reply *reply;		/* cached after first await */
};

O9Task*
o9_task_new(int id)
{
	O9Task *t = mallocz(sizeof *t, 1);
	if(t == nil)
		return nil;
	t->id = id;
	t->done = chancreate(sizeof(void*), 1);	/* buffered: forwarder need not rendezvous */
	return t;
}

/* The forwarder (or the method, later) delivers the result here.
 * Returned as void* so o9.h needn't reference Channel (thread.h). */
void*
o9_task_chan(O9Task *t)
{
	return t != nil ? t->done : nil;
}

/* Block for the spawned result. On error, set the per-proc call-error so
 * `try t.await()` propagates; return 0. Else return the value. Idempotent
 * (caches the reply — await twice is safe). */
vlong
o9_double_pack(double d)
{
	vlong v;

	v = 0;
	memmove(&v, &d, sizeof d);
	return v;
}

double
o9_double_unpack(vlong v)
{
	double d;

	d = 0.0;
	memmove(&d, &v, sizeof d);
	return d;
}

vlong
o9_task_await(O9Task *t)
{
	if(t == nil){
		o9_set_call_err("await of nil task");
		return 0;
	}
	if(t->reply == nil)
		t->reply = recvp(t->done);
	if(t->reply == nil){
		o9_set_call_err("task produced no result");
		return 0;
	}
	if(t->reply->err != nil){
		o9_set_call_err(t->reply->err);
		return 0;
	}
	o9_set_call_err(nil);
	return (vlong)t->reply->ret;
}

double
o9_task_await_double(O9Task *t)
{
	if(t == nil){
		o9_set_call_err("await of nil task");
		return 0.0;
	}
	if(t->reply == nil)
		t->reply = recvp(t->done);
	if(t->reply == nil){
		o9_set_call_err("task produced no result");
		return 0.0;
	}
	if(t->reply->err != nil){
		o9_set_call_err(t->reply->err);
		return 0.0;
	}
	o9_set_call_err(nil);
	return t->reply->dret;
}

void
o9_task_close(O9Task *t)
{
	if(t == nil)
		return;
	if(t->done != nil)
		chanfree(t->done);
	free(t->reply);
	free(t);
}

char*
o9_state_get(O9State *s, char *col)
{
	const char *v;

	if(s == nil || s->row == nil || col == nil)
		return nil;
	v = tab_get(s->row, col);
	if(v == nil)
		return nil;
	return (char *)v;
}

vlong
o9_state_get_int(O9State *s, char *col)
{
	char *v;

	v = o9_state_get(s, col);
	if(v == nil)
		return 0;
	return strtoll(v, nil, 0);
}

static void
o9_fill_from_buf(o9_AsmTable *table, Biobuf *bp)
{
	char *p, *key, *val, *l;

	while((l = Brdstr(bp, '\n', 1)) != nil){
		p = strchr(l, ':');
		if(p == nil) { free(l); continue; }
		*p++ = 0;
		key = l;
		val = p;

		if(key[0] == 'd'){
			ulong h = strtoul(key+1, nil, 10);
			long off = strtol(val, nil, 10);
			if(table){
				table->data_cache[h & 63].hash = h;
				table->data_cache[h & 63].ptr = (void*)(intptr)off;
			}
		}
		if(key[0] == 'c'){
			ulong h = strtoul(key+1, nil, 10);
			void *ptr = (void*)strtoul(val, nil, 16);
			if(table){
				table->ctrl_cache[h & 63].hash = h;
				table->ctrl_cache[h & 63].ptr = ptr;
			}
		}
		/* 'seg:' line is informational only — client derives seg tag from srvname */
		free(l);
	}
}

static int
o9_init_client_cache(void *client, char *cachepath, char *srvname, int size)
{
	o9_Object *obj = client;
	o9_AsmTable *table;
	Biobuf *bp;
	char tag[64];
	int fd;

	USED(size);

	if(client == nil || cachepath == nil || srvname == nil)
		return -1;

	strncpy(obj->srvname, srvname, sizeof(obj->srvname)-1);
	obj->srvname[sizeof(obj->srvname)-1] = '\0';
	strncpy(obj->cachepath, cachepath, sizeof(obj->cachepath)-1);
	obj->cachepath[sizeof(obj->cachepath)-1] = '\0';
	table = obj->table;

	fd = open(cachepath, OREAD);
	if(fd < 0) return -1;
	obj->fd = fd;

	if(table == nil) return 0;

	bp = Bfdopen(fd, OREAD);
	if(bp == nil) return -1;

	o9_fill_from_buf(table, bp);

	Bterm(bp);
	close(fd);
	obj->fd = -1;

	/* Map shared memory segment — server creates as o9/<classname> */
	snprint(tag, sizeof tag, "o9/%s", srvname);
#ifdef __GNUC__
	obj->shm_base = nil; /* TODO: Linux SHM support */
#else
	obj->shm_base = segattach(0, nil, tag, 0);
#endif
	if(obj->shm_base == (void*)-1)
		obj->shm_base = nil;	/* fall back to CSP-only dispatch */

	/* Convert data_cache offsets to absolute pointers for Tier 1 access */
	if(obj->shm_base != nil){
		int i;
		for(i = 0; i < 64; i++){
			if(table->data_cache[i].ptr != nil)
				table->data_cache[i].ptr = (char*)obj->shm_base + (intptr)table->data_cache[i].ptr;
		}
	}

	return 0;
}

int
o9_init_client(void *client, char *srvname, int size)
{
	char path[256];

	if(srvname == nil)
		return -1;
	snprint(path, sizeof path, "/srv/%s/status", srvname);
	return o9_init_client_cache(client, path, srvname, size);
}

int
o9_init_client_path(void *client, char *path, char *srvname, int size)
{
	char cachepath[256];

	if(path == nil || srvname == nil)
		return -1;
	snprint(cachepath, sizeof cachepath, "%s/status", path);
	return o9_init_client_cache(client, cachepath, srvname, size);
}

void
o9_cache_fill(void *client, ulong hash, int is_ctrl)
{
    o9_Object *obj = client;
    char path[256];
    Biobuf *bp;
    int fd;
    void *thunk;

	if(obj == nil || obj->srvname[0] == '\0') return;

	/* Method store first: exact (class, selector) lookup, and the pid-gen
	 * guard means a hit is always a thunk registered by this process.
	 * Misses (remote objects, older servers) fall back to status text. */
	if(is_ctrl && obj->table != nil){
		thunk = o9_method_thunk(obj->srvname, hash);
		if(thunk != nil){
			obj->table->ctrl_cache[hash & 63].hash = hash;
			obj->table->ctrl_cache[hash & 63].ptr = thunk;
			return;
		}
	}

	if(obj->cachepath[0] != '\0')
		strncpy(path, obj->cachepath, sizeof(path)-1);
	else
		snprint(path, sizeof path, "/srv/%s/status", obj->srvname);
	path[sizeof(path)-1] = '\0';
	fd = open(path, OREAD);
	if(fd < 0) return;

	bp = Bfdopen(fd, OREAD);
	if(bp == nil){ close(fd); return; }

	o9_fill_from_buf(obj->table, bp);

	Bterm(bp);
	close(fd);
}

static int
o9_write_full(int fd, uchar *buf, int nbuf)
{
	int n, off;

	off = 0;
	while(off < nbuf){
		n = write(fd, buf + off, nbuf - off);
		if(n <= 0)
			return -1;
		off += n;
	}
	return 0;
}

static int
o9_drain(int fd, int nleft)
{
	uchar tmp[512];
	int n, want;

	while(nleft > 0){
		want = nleft < sizeof tmp ? nleft : sizeof tmp;
		n = read(fd, tmp, want);
		if(n <= 0)
			return -1;
		nleft -= n;
	}
	return 0;
}

static int
o9_9p_rpc(int fd, uchar *tx, int ntx, uchar *rx, int nrx, int want)
{
	u32int size;
	int n, r;

	if(fd < 0 || tx == nil || rx == nil)
		return -1;
	if(o9_write_full(fd, tx, ntx) < 0)
		return -1;
	n = read(fd, rx, nrx);
	if(n <= 0)
		return -1;
	while(n < 4){
		r = read(fd, rx + n, nrx - n);
		if(r <= 0)
			return -1;
		n += r;
	}
	size = GET4(rx);
	if(size < 5)
		return -1;
	if(size > (u32int)nrx){
		while(n < nrx){
			r = read(fd, rx + n, nrx - n);
			if(r <= 0)
				return -1;
			n += r;
		}
		o9_drain(fd, size - nrx);
		return -1;
	}
	while(n < (int)size){
		r = read(fd, rx + n, size - n);
		if(r <= 0)
			return -1;
		n += r;
	}
	if(n < 5)
		return -1;
	if(rx[4] == 107)	/* Rerror */
		return -1;
	if(want != 0 && rx[4] != want)
		return -1;
	return size;
}

typedef struct O9SplitRpc O9SplitRpc;
struct O9SplitRpc {
	int fd;
	Channel *done;
};

static void
o9_split_rpc_server(void *v)
{
	O9SplitRpc *s;
	uchar req[64], resp[32];
	int n;

	s = v;
	n = read(s->fd, req, sizeof req);
	if(n <= 0){
		sendul(s->done, 1);
		close(s->fd);
		free(s);
		return;
	}

	PUT4(resp, 19);
	resp[4] = 101;		/* Rversion */
	resp[5] = req[5];
	resp[6] = req[6];
	PUT4(resp+7, 4096);
	PUT2(resp+11, 6);
	memmove(resp+13, "9P2000", 6);

	/* Split across the 4-byte size header and body. */
	if(write(s->fd, resp, 2) != 2 ||
	   (sleep(5), write(s->fd, resp+2, 1) != 1) ||
	   (sleep(5), write(s->fd, resp+3, 16) != 16))
		sendul(s->done, 1);
	else
		sendul(s->done, 0);
	close(s->fd);
	free(s);
}

int
o9_selftest_9p_rpc_split(void)
{
	O9SplitRpc *s;
	Channel *done;
	uchar tx[32], rx[32];
	int p[2], n, bad;

	if(pipe(p) < 0)
		return -1;
	done = chancreate(sizeof(ulong), 1);
	if(done == nil){
		close(p[0]);
		close(p[1]);
		return -1;
	}
	s = mallocz(sizeof *s, 1);
	if(s == nil){
		chanfree(done);
		close(p[0]);
		close(p[1]);
		return -1;
	}
	s->fd = p[1];
	s->done = done;
	proccreate(o9_split_rpc_server, s, 8192);

	PUT4(tx, 19);
	tx[4] = 100;		/* Tversion */
	tx[5] = 0;
	tx[6] = 0;
	PUT4(tx+7, 4096);
	PUT2(tx+11, 6);
	memmove(tx+13, "9P2000", 6);

	n = o9_9p_rpc(p[0], tx, 19, rx, sizeof rx, 101);
	close(p[0]);
	bad = recvul(done);
	chanfree(done);
	if(bad != 0 || n != 19 || rx[4] != 101 || GET4(rx+7) != 4096)
		return -1;
	return 0;
}

static int
o9_9p_walk1(int fd, u32int fid, u32int newfid, char *name)
{
	uchar tx[256], rx[256];
	int n, m;

	if(name == nil)
		return -1;
	n = strlen(name);
	if(n > 200)
		return -1;
	PUT4(tx, 19+n);
	tx[4] = 110;	/* Twalk */
	tx[5] = 0; tx[6] = 0;
	PUT4(tx+7, fid);
	PUT4(tx+11, newfid);
	PUT2(tx+15, 1);
	PUT2(tx+17, n);
	memmove(tx+19, name, n);
	m = o9_9p_rpc(fd, tx, 19+n, rx, sizeof rx, 111);
	return m < 0 ? -1 : 0;
}

static int
o9_9p_open(int fd, u32int fid, int mode)
{
	uchar tx[32], rx[256];
	int n;

	PUT4(tx, 12);
	tx[4] = 112;	/* Topen */
	tx[5] = 0; tx[6] = 0;
	PUT4(tx+7, fid);
	tx[11] = mode;
	n = o9_9p_rpc(fd, tx, 12, rx, sizeof rx, 113);
	return n < 0 ? -1 : 0;
}

static int
o9_9p_clunk(int fd, u32int fid)
{
	uchar tx[16], rx[64];
	int n;

	PUT4(tx, 11);
	tx[4] = 120;	/* Tclunk */
	tx[5] = 0; tx[6] = 0;
	PUT4(tx+7, fid);
	n = o9_9p_rpc(fd, tx, 11, rx, sizeof rx, 121);
	return n < 0 ? -1 : 0;
}

static int
o9_9p_write_all(int fd, u32int fid, char *s)
{
	uchar tx[8192], rx[256];
	int n, m;

	if(s == nil)
		s = "";
	n = strlen(s);
	if(n > (int)sizeof tx - 23)
		n = sizeof tx - 23;
	PUT4(tx, 23+n);
	tx[4] = 118;	/* Twrite */
	tx[5] = 0; tx[6] = 0;
	PUT4(tx+7, fid);
	PUT4(tx+11, 0);
	PUT4(tx+15, 0);
	PUT4(tx+19, n);
	memmove(tx+23, s, n);
	m = o9_9p_rpc(fd, tx, 23+n, rx, sizeof rx, 119);
	return m < 0 ? -1 : 0;
}

static int
o9_9p_read_all(int fd, u32int fid, char *buf, int nbuf)
{
	uchar tx[32], rx[8192];
	u32int cnt;
	int n, max;

	if(buf == nil || nbuf <= 0)
		return -1;
	buf[0] = '\0';
	max = nbuf - 1;
	if(max > (int)sizeof rx - 12)
		max = sizeof rx - 12;
	PUT4(tx, 23);
	tx[4] = 116;	/* Tread */
	tx[5] = 0; tx[6] = 0;
	PUT4(tx+7, fid);
	PUT4(tx+11, 0);
	PUT4(tx+15, 0);
	PUT4(tx+19, max);
	n = o9_9p_rpc(fd, tx, 23, rx, sizeof rx, 117);
	if(n < 11)
		return -1;
	cnt = rx[7] | (rx[8]<<8) | (rx[9]<<16) | (rx[10]<<24);
	if(cnt > (u32int)max)
		cnt = max;
	if(n < 11+(int)cnt)
		return -1;
	memmove(buf, rx+11, cnt);
	buf[cnt] = '\0';
	return cnt;
}

static int
o9_remote_ctl_data(o9_Object *obj, char *cmd, char *data, int ndata)
{
	static QLock lock;
	static u32int nextfid = 10;
	enum { Rootfid = 1 };
	u32int ctlfid, datafid;
	int rv, havectl, havedata;

	if(obj == nil || obj->fd < 0 || cmd == nil)
		return -1;
	if(data != nil && ndata > 0)
		data[0] = '\0';
	qlock(&lock);
	if(nextfid > 0xfffffff0U)
		nextfid = 10;
	ctlfid = nextfid++;
	datafid = nextfid++;
	rv = -1;
	havectl = 0;
	havedata = 0;
	if(o9_9p_walk1(obj->fd, Rootfid, ctlfid, "ctl") < 0)
		goto out;
	havectl = 1;
	if(o9_9p_open(obj->fd, ctlfid, OWRITE) < 0)
		goto out;
	if(o9_9p_write_all(obj->fd, ctlfid, cmd) < 0)
		goto out;
	if(o9_9p_walk1(obj->fd, Rootfid, datafid, "data") < 0)
		goto out;
	havedata = 1;
	if(o9_9p_open(obj->fd, datafid, OREAD) < 0)
		goto out;
	if(o9_9p_read_all(obj->fd, datafid, data, ndata) < 0)
		goto out;
	rv = 0;
out:
	if(havectl)
		o9_9p_clunk(obj->fd, ctlfid);
	if(havedata)
		o9_9p_clunk(obj->fd, datafid);
	qunlock(&lock);
	return rv;
}

static void
o9_remote_method_cmd(o9_Object *obj, char *method, void *args, int nargs, char *cmd, int ncmd)
{
	char path[128], inst[64], mname[64], *slash;
	char *p;
	vlong *argv;
	int i;

	if(cmd == nil || ncmd <= 0)
		return;
	if(method == nil)
		method = "";
	strncpy(path, method, sizeof path-1);
	path[sizeof path-1] = '\0';
	slash = strchr(path, '/');
	if(slash != nil){
		*slash++ = '\0';
		strncpy(inst, path, sizeof inst-1);
		inst[sizeof inst-1] = '\0';
		strncpy(mname, slash, sizeof mname-1);
		mname[sizeof mname-1] = '\0';
	}else{
		if(obj != nil && obj->srvname[0] != '\0')
			strncpy(inst, obj->srvname, sizeof inst-1);
		else
			strncpy(inst, "main", sizeof inst-1);
		inst[sizeof inst-1] = '\0';
		strncpy(mname, path, sizeof mname-1);
		mname[sizeof mname-1] = '\0';
	}
	if(obj != nil && obj->srvname[0] != '\0' && strcmp(mname, obj->srvname) == 0){
		snprint(cmd, ncmd, "new %s", inst);
		return;
	}
	p = cmd;
	p += snprint(p, ncmd - (p-cmd), "method %s %s", inst, mname);
	if(args != nil && nargs > 0){
		argv = args;
		for(i = 0; i < nargs && p < cmd+ncmd-1; i++)
			p += snprint(p, cmd+ncmd-p, " arg%d=%lld", i, argv[i]);
	}
}

void*
obj9_msgSendN(void *receiver, char *method, ulong selector, void *args, int nargs)
{
    o9_Object *obj = receiver;
    O9Handle h;
    O9Msg *m;
    O9Reply *r;
    void *ret;
    char cmd[1024], data[8192];

    if(obj->dispatch_chan != nil){
        if(o9_actor_self_send(obj->dispatch_chan, method))
            return nil;
        if(obj->oid[0] != '\0' && obj->gen != 0){
            if(o9_registry_lookup(obj->oid, &h) < 0 ||
               h.gen != obj->gen || h.chan != obj->dispatch_chan){
                werrstr("stale object handle");
                o9_set_call_err("stale object handle");
                return nil;
            }
        }
        m = mallocz(sizeof(O9Msg), 1);
        m->sel = selector;
        m->args = args;
        m->nargs = nargs;
        m->replyc = chancreate(sizeof(void*), 0);
        sendp(obj->dispatch_chan, m);
        r = recvp(m->replyc);
        if(r->err != nil){
            werrstr("%s", r->err);
            o9_set_call_err(r->err);	/* for try: last-call error signal */
            ret = nil;
        } else {
            o9_set_call_err(nil);
            ret = (void*)r->ret;
        }
        chanfree(m->replyc);
        free(r);
        free(m);
        return ret;
    }

    /* Fall through to remote 9P dispatch if connected.
     * Like the channel path above, the return value itself travels in the
     * pointer (callers cast it back to vlong); no static buffer to clobber. */
    if(obj->fd >= 0 && method != nil && obj->distance >= 0){
        o9_remote_method_cmd(obj, method, args, nargs, cmd, sizeof cmd);
        if(o9_remote_ctl_data(obj, cmd, data, sizeof data) == 0){
            if(strncmp(data, "error: ", 7) == 0){
                char *nl = strchr(data, '\n');
                if(nl != nil)
                    *nl = '\0';
                werrstr("%s", data + 7);
                o9_set_call_err("remote call failed");
                return nil;
            }
            o9_set_call_err(nil);
            return (void*)(uintptr)strtoll(data, nil, 0);
        }
    }

    return nil;
}

double
obj9_msgSendDoubleN(void *receiver, char *method, ulong selector, void *args, int nargs)
{
    o9_Object *obj = receiver;
    O9Handle h;
    O9Msg *m;
    O9Reply *r;
    double ret;
    char cmd[1024], data[8192];

    ret = 0.0;
    if(obj->dispatch_chan != nil){
        if(o9_actor_self_send(obj->dispatch_chan, method))
            return 0.0;
        if(obj->oid[0] != '\0' && obj->gen != 0){
            if(o9_registry_lookup(obj->oid, &h) < 0 ||
               h.gen != obj->gen || h.chan != obj->dispatch_chan){
                werrstr("stale object handle");
                o9_set_call_err("stale object handle");
                return 0.0;
            }
        }
        m = mallocz(sizeof(O9Msg), 1);
        m->sel = selector;
        m->args = args;
        m->nargs = nargs;
        m->replyc = chancreate(sizeof(void*), 0);
        sendp(obj->dispatch_chan, m);
        r = recvp(m->replyc);
        if(r->err != nil){
            werrstr("%s", r->err);
            o9_set_call_err(r->err);
        } else {
            o9_set_call_err(nil);
            ret = r->dret;
        }
        chanfree(m->replyc);
        free(r);
        free(m);
        return ret;
    }

    if(obj->fd >= 0 && method != nil && obj->distance >= 0){
        o9_remote_method_cmd(obj, method, args, nargs, cmd, sizeof cmd);
        if(o9_remote_ctl_data(obj, cmd, data, sizeof data) == 0){
            if(strncmp(data, "error: ", 7) == 0){
                char *nl = strchr(data, '\n');
                if(nl != nil)
                    *nl = '\0';
                werrstr("%s", data + 7);
                o9_set_call_err("remote call failed");
                return 0.0;
            }
            o9_set_call_err(nil);
            return strtod(data, nil);
        }
    }

    return 0.0;
}

void*
obj9_msgSend(void *receiver, char *method, ulong selector, void *args)
{
	return obj9_msgSendN(receiver, method, selector, args, args != nil ? 1 : 0);
}

/* First method-table row matching a method name; the ret column tells
 * send() whether a dispatch result is text or a number. */
static char*
o9_method_ret_type(char *method)
{
	O9MethodStore *s = o9_method_store();
	TabIter *it;
	TabRow *row;
	const char *v;

	if(s == nil || s->tab == nil || method == nil)
		return nil;
	it = tab_search(s->tab, "method", method);
	if(it == nil)
		return nil;
	row = tab_iter_next(it);
	tab_iter_close(it);
	if(row == nil)
		return nil;
	v = tab_get(row, "ret");
	return (char*)v;
}

/* send(handle, line) builtin: code as text.  The line is the same one
 * the shell writes — "method <inst> <name> arg0=5 ..." — fired at a
 * handle from inside the language, reply back as a string.  Far
 * handles get the raw line written to ctl and the data file read back
 * verbatim; in-process handles parse it into the same selector+frame
 * the compiled call sites use. */
O9String*
o9_send(void *client, O9String *line)
{
	o9_Object *obj = client;
	char buf[1024], data[8192];
	char *f[16], *v, *ret, *cline;
	vlong args[8], rv;
	int nf, i, nargs;

	if(client == nil || line == nil)
		return nil;
	cline = o9_string_cstr(line);
	if(cline == nil)
		return nil;
	if(obj->dispatch_chan == nil && obj->fd >= 0){
		/* far: text in, text out, exactly the shell's path */
		strncpy(buf, cline, sizeof buf - 1);
		buf[sizeof buf - 1] = '\0';
		free(cline);
		if(o9_remote_ctl_data(obj, buf, data, sizeof data) < 0)
			return nil;
		return o9_string_from_c(data);
	}
	strncpy(buf, cline, sizeof buf - 1);
	buf[sizeof buf - 1] = '\0';
	free(cline);
	nf = tokenize(buf, f, nelem(f));
	if(nf < 3 || strcmp(f[0], "method") != 0)
		return o9_string_take(smprint("error: send wants 'method <inst> <name> [argN=v ...]'"));
	nargs = 0;
	for(i = 3; i < nf && nargs < nelem(args); i++){
		v = strchr(f[i], '=');
		args[nargs] = strtoll(v != nil ? v+1 : f[i], nil, 0);
		nargs++;
	}
	rv = (vlong)(uintptr)obj9_msgSendN(obj, f[2], o9_hash(f[2]),
		nargs > 0 ? args : nil, nargs);
	ret = o9_method_ret_type(f[2]);
	if(ret != nil && (strcmp(ret, "string") == 0 || strcmp(ret, "O9String*") == 0)){
		if(rv == 0)
			return o9_string_from_c("");
		return o9_string_retain((O9String*)(uintptr)rv);
	}
	return o9_string_take(smprint("%lld", rv));
}

/*
 * obj9_msgSend_name — remote 9P dispatch over fd.
 * Compatibility wrapper around the counted ctl/data dispatch path.
 * Used when distance >= 0 (no dispatch_chan).
 */
void*
obj9_msgSend_name(void *receiver, char *method, ulong selector, void *args)
{
	USED(selector);
	return obj9_msgSendN(receiver, method, selector, args, args != nil ? 1 : 0);
}

void
o9_ledger_update(void *client, ulong id, int delta)
{
	o9_Object *obj = client;
	USED(id);
	if(obj == nil) return;
	if(delta > 0){
		while(delta--) o9_atomic_inc(&obj->ref);
	} else {
		while(delta++) o9_atomic_dec(&obj->ref);
	}
}

long
o9_ledger_value(void *client, ulong id)
{
	o9_Object *obj = client;
	USED(id);
	if(obj == nil) return 0;
	return obj->ref;
}

void
o9_clunk(int fd)
{
	close(fd);
}

/*
 * o9_connect — dial and 9P handshake.
 *
 * Distance selects the transport (o9 is a Plan 9 / 9front language):
 *   near (0) -> IL   (reliable sequenced datagrams, built for 9P; the
 *                     low-latency LAN-realm transport)
 *   far  (1) -> TCP  (wide area)
 * If addr already carries a transport (has a '!' before the host, or is
 * a /srv path), it is dialed as-is.  Otherwise the distance's transport
 * is prepended: "host!service" -> "il!host!service" for near.
 */
int
o9_connect(void *client, char *addr, char *srvname, int distance)
{
	o9_Object *obj = client;
	char dialaddr[256], uname[64], *u;
	uchar buf[256], rbuf[256], *p;
	int fd, n, msize, ulen, alen;

	if(addr == nil) return -1;

	/* Prepend the distance's transport unless one is already given. */
	if(addr[0] == '/' || strncmp(addr, "il!", 3) == 0 ||
	   strncmp(addr, "tcp!", 4) == 0 || strncmp(addr, "net!", 4) == 0){
		snprint(dialaddr, sizeof dialaddr, "%s", addr);
	} else if(distance == 0){
		snprint(dialaddr, sizeof dialaddr, "il!%s", addr);	/* near = IL */
	} else {
		snprint(dialaddr, sizeof dialaddr, "tcp!%s", addr);	/* far = TCP */
	}

	if(addr[0] == '/')
		fd = open(dialaddr, ORDWR);
	else
		fd = dial(dialaddr, nil, nil, nil);
	if(fd < 0) return -1;

	obj->fd = fd;
	if(srvname)
		strncpy(obj->srvname, srvname, sizeof(obj->srvname)-1);

	/* Tversion */
	msize = 4096;
	buf[0] = 0; buf[1] = 0; buf[2] = 0; buf[3] = 0; /* len (fill later) */
	buf[4] = 100; /* Tversion */
	buf[5] = 0; buf[6] = 0; /* tag = 0 */
	PUT4(buf+7, msize);
	n = strlen("9P2000");
	buf[11] = n; buf[12] = 0; /* string len */
	memmove(buf+13, "9P2000", n);
	PUT4(buf, 13+n);
	if(o9_9p_rpc(fd, buf, 13+n, rbuf, sizeof rbuf, 101) < 0)
		goto fail;

	/* Tattach root fid 1. */
	PUT4(buf, 0); /* len */
	buf[4] = 104; /* Tattach */
	buf[5] = 0; buf[6] = 0; /* tag */
	PUT4(buf+7, 1); /* fid */
	PUT4(buf+11, NOFID); /* afid */
	u = getuser();
	if(u == nil || u[0] == '\0')
		u = "none";
	snprint(uname, sizeof uname, "%s", u);
	ulen = strlen(uname);
	alen = 1;
	p = buf + 15;
	PUT2(p, ulen);
	p += 2;
	memmove(p, uname, ulen);
	p += ulen;
	PUT2(p, alen);
	p += 2;
	*p++ = '/';
	PUT4(buf, p - buf);
	if(o9_9p_rpc(fd, buf, p - buf, rbuf, sizeof rbuf, 105) < 0)
		goto fail;

	obj->shm_base = nil;
	obj->table = nil;
	obj->dispatch_chan = nil;
	obj->distance = distance;
	return 0;

fail:
	close(fd);
	obj->fd = -1;
	return -1;
}

/*
 * o9_array_get — read vlong at line index idx from line-based data.
 * Lines are separated by '\\n'. Returns 0 if idx out of range.
 */
vlong
o9_array_get(char *data, vlong idx)
{
	vlong i;
	char *p, *end;
	long v;

	if(data == nil) return 0;
	p = data;
	for(i = 0; i < idx; i++){
		p = strchr(p, '\n');
		if(p == nil) return 0;
		p++;
	}
	v = strtol(p, &end, 0);
	return (vlong)v;
}

/*
 * o9_array_set — set vlong at line index idx.
 * Always rebuilds the buffer (correct, O(n)).
 */
void
o9_array_set(char **data, vlong idx, vlong val)
{
	char buf[32];
	char *dp, *new, *p, *line;
	vlong i, curlen, newsize;

	if(data == nil) return;
	dp = *data;

	/* Count lines; a trailing newline terminates the last line, it does
	 * not start a new one */
	if(dp == nil || dp[0] == '\0')
		curlen = 0;
	else {
		curlen = 0;
		for(p = dp; *p; p++)
			if(*p == '\n') curlen++;
		if(p[-1] != '\n') curlen++;
	}

	snprint(buf, sizeof buf, "%lld\n", val);

	if(idx < curlen){
		/* Replace — rebuild line by line without mutating the old buffer */
		char *q;
		int linelen;

		newsize = strlen(dp) + strlen(buf) + 2;
		new = mallocz(newsize, 1);
		q = new;
		p = dp;
		for(i = 0; i < curlen; i++){
			line = strchr(p, '\n');
			linelen = line ? line - p : strlen(p);
			if(i == idx){
				memmove(q, buf, strlen(buf));
				q += strlen(buf);
			} else {
				memmove(q, p, linelen);
				q += linelen;
				*q++ = '\n';
			}
			p = line ? line + 1 : p + linelen;
		}
		*q = '\0';
		free(dp);
		*data = new;
	} else {
		/* Extend: pad with empty lines, then append */
		int need = (int)(idx - curlen + 1);
		newsize = (dp ? strlen(dp) : 0) + need * 2 + 32;
		new = mallocz(newsize, 1);
		if(dp)
			strcpy(new, dp);
		else
			new[0] = '\0';
		p = new + strlen(new);
		if(p > new && p[-1] != '\n')
			*p++ = '\n';
		for(i = curlen; i < idx; i++){
			strcpy(p, "\n");
			p++;
		}
		strcpy(p, buf);
		if(dp) free(dp);
		*data = new;
	}
}

/*
 * o9_array_len — count lines in data.
 */
vlong
o9_array_len(char *data)
{
	vlong n;
	char *p;

	if(data == nil || data[0] == '\0') return 0;
	n = 0;
	for(p = data; *p; p++)
		if(*p == '\n') n++;
	if(p[-1] != '\n') n++;
	return n;
}

/*
 * o9_slice_init — initialize slice with element size.
 */
void
o9_slice_init(O9Slice *s, int elemsize)
{
	memset(s, 0, sizeof(O9Slice));
	s->elemsize = elemsize;
}

/*
 * o9_slice_append — append value to slice, expanding cap if needed.
 */
void
o9_slice_append(O9Slice *s, void *val)
{
	if(s->len >= s->cap){
		s->cap = s->cap ? s->cap * 2 : 8;
		s->data = realloc(s->data, s->cap * s->elemsize);
	}
	memmove((char*)s->data + (s->len * s->elemsize), val, s->elemsize);
	s->len++;
}

/*
 * o9_slice_get — get pointer to element at idx.
 */
void*
o9_slice_get(O9Slice *s, vlong idx)
{
	if(idx < 0 || idx >= s->len) return nil;
	return (char*)s->data + (idx * s->elemsize);
}

/*
 * o9_slice_set — copy value to element at idx.
 */
void
o9_slice_set(O9Slice *s, vlong idx, void *val)
{
	if(idx < 0 || idx >= s->len) return;
	memmove((char*)s->data + (idx * s->elemsize), val, s->elemsize);
}

/*
 * o9_slice_setgrow — set element at idx, growing and zero-filling gaps.
 * This backs fixed-looking TyArray syntax (`a[2] = 9`) while keeping the
 * storage representation the same O(1) slice used by List<T>.
 */
void
o9_slice_setgrow(O9Slice *s, vlong idx, void *val)
{
	vlong oldcap, newcap;
	void *ndata;

	if(s == nil || val == nil || idx < 0 || s->elemsize <= 0)
		return;
	if(idx >= s->cap){
		oldcap = s->cap;
		newcap = oldcap > 0 ? oldcap : 8;
		while(idx >= newcap)
			newcap *= 2;
		ndata = realloc(s->data, newcap * s->elemsize);
		if(ndata == nil)
			return;
		s->data = ndata;
		memset((char*)s->data + oldcap * s->elemsize, 0,
			(newcap - oldcap) * s->elemsize);
		s->cap = newcap;
	}
	if(idx >= s->len){
		memset((char*)s->data + s->len * s->elemsize, 0,
			(idx + 1 - s->len) * s->elemsize);
		s->len = idx + 1;
	}
	memmove((char*)s->data + idx * s->elemsize, val, s->elemsize);
}

/*
 * o9_slice_free — free slice data.
 */
void
o9_slice_free(O9Slice *s)
{
	if(s) free(s->data);
}

/*
 * o9_dict_init — initialize dict to empty.
 */
void
o9_dict_init(O9Dict *d)
{
	memset(d, 0, sizeof(O9Dict));
}

/*
 * o9_dict_free — free all entries.
 */
void
o9_dict_free(O9Dict *d)
{
	int i;
	O9DictEntry *e, *next;
	for(i = 0; i < 64; i++){
		for(e = d->buckets[i]; e; e = next){
			next = e->next;
			o9_string_release(e->key);
			/* Note: generic val is NOT freed, caller must manage if it's a pointer */
			free(e);
		}
	}
}

static ulong
o9_dict_hash_bytes(char *s, vlong n)
{
	ulong h = 5381;
	vlong i;

	if(s == nil)
		return 0;
	for(i = 0; i < n; i++)
		h = ((h << 5) + h) + (uchar)s[i];
	return h & 63;
}

static ulong
o9_dict_hashs(O9String *s)
{
	return o9_dict_hash_bytes(o9_string_data(s), o9_string_len(s));
}

static int
o9_dict_keyeq(O9String *a, O9String *b)
{
	vlong n;

	n = o9_string_len(a);
	return n == o9_string_len(b) &&
		memcmp(o9_string_data(a), o9_string_data(b), n) == 0;
}

/*
 * o9_dict_get — get value for key. Returns nil if not found.
 */
void*
o9_dict_gets(O9Dict *d, O9String *key)
{
	O9DictEntry *e;
	if(d == nil || key == nil) return nil;
	for(e = d->buckets[o9_dict_hashs(key)]; e; e = e->next)
		if(o9_dict_keyeq(e->key, key))
			return e->val;
	return nil;
}

/*
 * o9_dict_set — set key=val, replacing existing if present.
 */
void
o9_dict_sets(O9Dict *d, O9String *key, void *val)
{
	ulong h;
	O9DictEntry *e;
	if(d == nil || key == nil) return;
	h = o9_dict_hashs(key);
	for(e = d->buckets[h]; e; e = e->next){
		if(o9_dict_keyeq(e->key, key)){
			e->val = val;
			return;
		}
	}
	e = mallocz(sizeof(O9DictEntry), 1);
	e->key = o9_string_retain(key);
	e->val = val;
	e->next = d->buckets[h];
	d->buckets[h] = e;
}

/*
 * o9_dict_has — check if key exists.
 */
int
o9_dict_hass(O9Dict *d, O9String *key)
{
	O9DictEntry *e;
	if(d == nil || key == nil) return 0;
	for(e = d->buckets[o9_dict_hashs(key)]; e; e = e->next)
		if(o9_dict_keyeq(e->key, key)) return 1;
	return 0;
}

void*
o9_dict_get(O9Dict *d, char *key)
{
	O9String tmp;

	if(key == nil)
		return nil;
	memset(&tmp, 0, sizeof tmp);
	tmp.data = key;
	tmp.len = strlen(key);
	tmp.ref = 1;
	return o9_dict_gets(d, &tmp);
}

void
o9_dict_set(O9Dict *d, char *key, void *val)
{
	O9String *tmp;

	if(key == nil)
		return;
	tmp = o9_string_from_c(key);
	if(tmp == nil)
		return;
	o9_dict_sets(d, tmp, val);
	o9_string_release(tmp);
}

int
o9_dict_has(O9Dict *d, char *key)
{
	O9String tmp;

	if(key == nil)
		return 0;
	memset(&tmp, 0, sizeof tmp);
	tmp.data = key;
	tmp.len = strlen(key);
	tmp.ref = 1;
	return o9_dict_hass(d, &tmp);
}

/*
 * o9_dict_deserialize — parse "key:val\nkey:val\n" into dict.
 * Merges with existing dict (replaces keys, keeps non-conflicting).
 */
void
o9_dict_deserialize(O9Dict *d, char *buf)
{
	char *l, *next, *p;
	if(d == nil || buf == nil) return;
	for(l = buf; *l; l = next){
		next = strchr(l, '\n');
		if(next) *next++ = '\0';
		else next = l + strlen(l);
		p = strchr(l, ':');
		if(p == nil) continue;
		*p++ = '\0';
		o9_dict_set(d, l, p);
	}
}

/*
 * o9_dict_serialize — produce "key:val\nkey:val\n" string.
 * Caller must free the result.
 */
char*
o9_dict_serialize(O9Dict *d)
{
	char *buf, *p;
	int i, len;
	O9DictEntry *e;
	if(d == nil) return strdup("");
	len = 1;
	for(i = 0; i < 64; i++)
		for(e = d->buckets[i]; e; e = e->next)
			len += o9_string_len(e->key) + 1 + strlen(e->val) + 1;
	buf = mallocz(len, 1);
	p = buf;
	for(i = 0; i < 64; i++){
		for(e = d->buckets[i]; e; e = e->next){
			memmove(p, o9_string_data(e->key), o9_string_len(e->key));
			p += o9_string_len(e->key);
			*p++ = ':';
			memmove(p, e->val, strlen(e->val));
			p += strlen(e->val);
			*p++ = '\n';
		}
	}
	*p = '\0';
	return buf;
}
