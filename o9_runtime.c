#include <u.h>
#include <libc.h>
#include <bio.h>
#include <thread.h>
#include "o9.h"
#include "libtab.h"

/* 9P encoding helpers — little-endian */
#define PUT2(p, v) do{ (p)[0]=(v)&0xff; (p)[1]=((v)>>8)&0xff; }while(0)
#define PUT4(p, v) do{ (p)[0]=(v)&0xff; (p)[1]=((v)>>8)&0xff; (p)[2]=((v)>>16)&0xff; (p)[3]=((v)>>24)&0xff; }while(0)
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

static int
o9_tab_has_col(Tab *tab, char *name)
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
o9_object_schema_matches(Tab *tab)
{
	int i;

	if(tab == nil)
		return 0;
	for(i = 0; i < nelem(o9_object_cols); i++)
		if(!o9_tab_has_col(tab, o9_object_cols[i]))
			return 0;
	return 1;
}

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
	s->tab = tab_open(s->path);
	if(s->tab != nil && !o9_object_schema_matches(s->tab)){
		tab_close(s->tab);
		s->tab = nil;
		remove(s->path);
	}
	if(s->tab == nil){
		memset(spec, 0, sizeof spec);
		for(i = 0; i < nelem(o9_object_cols); i++)
			spec[i].name = o9_object_cols[i];
		s->tab = tab_create(s->path, "o9objects", spec, nelem(spec));
	}
	if(s->tab == nil){
		free(s->path);
		free(s);
		return nil;
	}
	tab_commit(s->tab);
	return s;
}

O9ObjectStore*
o9_object_store_create_path(char *root, char *app)
{
	char dir[256], path[256];

	if(root == nil || root[0] == '\0')
		return nil;
	if(app == nil || app[0] == '\0')
		app = "app";
	o9_ns_ensure_app(root);
	snprint(dir, sizeof dir, "%s/state", root);
	o9_ns_ensure_dir(dir);
	snprint(path, sizeof path, "%s/%s.objects.tab", dir, app);
	return o9_object_store_create(path);
}

void
o9_object_store_close(O9ObjectStore *s)
{
	if(s == nil)
		return;
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
	return tab_commit(s->tab);
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
	return tab_commit(s->tab);
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

/* Text/Fs/IO builtins — lowered from len/cmp/cat/readfile/writefile/readline.
 * Strings returned here are malloc'd and, for now, live until process exit
 * (no lifecycle yet). */

vlong
o9_str_len(char *s)
{
	if(s == nil)
		return 0;
	return strlen(s);
}

vlong
o9_str_cmp(char *a, char *b)
{
	if(a == nil) a = "";
	if(b == nil) b = "";
	return strcmp(a, b);
}

char*
o9_str_cat(char *a, char *b)
{
	if(a == nil) a = "";
	if(b == nil) b = "";
	return smprint("%s%s", a, b);
}

char*
o9_readfile(char *path)
{
	int fd;
	long n, total, cap;
	char *buf, *nb;

	if(path == nil)
		return nil;
	fd = open(path, OREAD);
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
	return buf;
}

vlong
o9_writefile(char *path, char *s)
{
	int fd;
	long n;

	if(path == nil || s == nil)
		return -1;
	fd = create(path, OWRITE, 0644);
	if(fd < 0)
		return -1;
	n = strlen(s);
	if(write(fd, s, n) != n){
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

char*
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
	return strdup(buf);
}

/* Method table backed by libtab — the dispatch source of truth.
 *
 * One store per process: every generated class server registers its methods
 * (including flattened inherited ones) at startup.  The persisted columns
 * are stable identity (class, method, selector, signature); the thunk
 * address is an in-process cache hint guarded by gen == getpid(), so rows
 * left by an earlier run are never trusted as pointers. */

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
	char dir[256], path[256];
	int i;

	if(o9_methods != nil)
		return 0;
	if(root == nil || root[0] == '\0')
		return -1;
	if(app == nil || app[0] == '\0')
		app = "app";
	o9_ns_ensure_app(root);
	snprint(dir, sizeof dir, "%s/state", root);
	o9_ns_ensure_dir(dir);
	snprint(path, sizeof path, "%s/%s.methods.tab", dir, app);

	s = mallocz(sizeof *s, 1);
	if(s == nil)
		return -1;
	s->path = strdup(path);
	if(s->path == nil){
		free(s);
		return -1;
	}
	s->tab = tab_open(s->path);
	if(s->tab != nil && !o9_tab_has_col(s->tab, "key")){
		tab_close(s->tab);
		s->tab = nil;
		remove(s->path);
	}
	if(s->tab == nil){
		memset(spec, 0, sizeof spec);
		for(i = 0; i < nelem(o9_method_cols); i++)
			spec[i].name = o9_method_cols[i];
		s->tab = tab_create(s->path, "o9methods", spec, nelem(spec));
	}
	if(s->tab == nil){
		free(s->path);
		free(s);
		return -1;
	}
	tab_commit(s->tab);
	o9_methods = s;
	return 0;
}

void
o9_method_store_close(void)
{
	if(o9_methods == nil)
		return;
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
	return tab_commit(o9_methods->tab);
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
	if(root != nil && root[0] != '\0'){
		o9_ns_ensure_app(root);
		snprint(dir, sizeof dir, "%s/state", root);
		o9_ns_ensure_dir(dir);
		snprint(path, sizeof path, "%s/%s.%s.tab", dir, classname, instname);
	}else{
		snprint(path, sizeof path, "/tmp/o9state.%ld.%s.%s.tab",
			(long)getpid(), classname, instname);
	}
	s->path = strdup(path);
	if(s->path == nil){
		free(spec);
		free(s);
		return nil;
	}
	if(root != nil && root[0] != '\0'){
		s->tab = tab_open(s->path);
		if(s->tab != nil && !o9_state_schema_matches(s->tab, cols, ncols)){
			tab_close(s->tab);
			s->tab = nil;
			remove(s->path);
		}
	}
	if(s->tab == nil)
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

void
o9_state_set(O9State *s, char *col, char *value)
{
	if(s == nil || s->tab == nil || s->row == nil || col == nil)
		return;
	if(value == nil)
		value = "";
	if(tab_set(s->tab, s->row, col, value) == 0)
		tab_commit(s->tab);
}

void
o9_state_set_int(O9State *s, char *col, vlong value)
{
	char buf[64];

	snprint(buf, sizeof buf, "%lld", value);
	o9_state_set(s, col, buf);
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
o9_9p_rpc(int fd, uchar *tx, int ntx, uchar *rx, int nrx, int want)
{
	int n;

	if(fd < 0 || tx == nil || rx == nil)
		return -1;
	if(write(fd, tx, ntx) != ntx)
		return -1;
	n = read(fd, rx, nrx);
	if(n < 5)
		return -1;
	if(rx[4] == 107)	/* Rerror */
		return -1;
	if(want != 0 && rx[4] != want)
		return -1;
	return n;
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
	enum { Rootfid = 1, Ctlfid = 2, Datafid = 3 };

	if(obj == nil || obj->fd < 0 || cmd == nil)
		return -1;
	if(o9_9p_walk1(obj->fd, Rootfid, Ctlfid, "ctl") < 0)
		return -1;
	if(o9_9p_open(obj->fd, Ctlfid, OWRITE) < 0)
		goto failctl;
	if(o9_9p_write_all(obj->fd, Ctlfid, cmd) < 0)
		goto failctl;
	o9_9p_clunk(obj->fd, Ctlfid);
	if(o9_9p_walk1(obj->fd, Rootfid, Datafid, "data") < 0)
		return -1;
	if(o9_9p_open(obj->fd, Datafid, OREAD) < 0)
		goto faildata;
	if(o9_9p_read_all(obj->fd, Datafid, data, ndata) < 0)
		goto faildata;
	o9_9p_clunk(obj->fd, Datafid);
	return 0;

faildata:
	o9_9p_clunk(obj->fd, Datafid);
	return -1;
failctl:
	o9_9p_clunk(obj->fd, Ctlfid);
	return -1;
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
    O9Msg *m;
    O9Reply *r;
    void *ret;
    char cmd[1024], data[8192];

    if(obj->dispatch_chan != nil){
        m = mallocz(sizeof(O9Msg), 1);
        m->sel = selector;
        m->args = args;
        m->nargs = nargs;
        m->replyc = chancreate(sizeof(void*), 0);
        sendp(obj->dispatch_chan, m);
        r = recvp(m->replyc);
        if(r->err != nil){
            werrstr("%s", r->err);
            ret = nil;
        } else
            ret = (void*)r->ret;
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
                return nil;
            }
            return (void*)(uintptr)strtoll(data, nil, 0);
        }
    }

    return nil;
}

void*
obj9_msgSend(void *receiver, char *method, ulong selector, void *args)
{
	return obj9_msgSendN(receiver, method, selector, args, args != nil ? 1 : 0);
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
 * o9_connect — dial and 9P handshake
 * addr can be "il!host!service", "tcp!host!port", or "/srv/name" (Unix)
 */
int
o9_connect(void *client, char *addr, char *srvname)
{
	o9_Object *obj = client;
	char buf[256];
	uchar rbuf[256];
	int fd, n, msize;

	if(addr == nil) return -1;

	fd = dial(addr, nil, nil, nil);
	if(fd < 0) return -1;

	strncpy(buf, addr, sizeof(buf)-1);
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
	write(fd, buf, 13+n);

	/* Rversion */
	n = read(fd, rbuf, sizeof(rbuf));
	if(n < 7) goto fail;

	/* Tattach root fid 1. */
	PUT4(buf, 0); /* len */
	buf[4] = 104; /* Tattach */
	buf[5] = 0; buf[6] = 0; /* tag */
	PUT4(buf+7, 1); /* fid */
	PUT4(buf+11, NOFID); /* afid */
	PUT2(buf+15, 1); /* uname len */
	buf[17] = 'S'; /* uname placeholder */
	PUT2(buf+18, 1); /* aname len */
	buf[20] = '/';
	PUT4(buf, 21);
	write(fd, buf, 21);

	/* Rattach */
	n = read(fd, rbuf, sizeof(rbuf));
	if(n < 7) goto fail;

	obj->shm_base = nil;
	obj->table = nil;
	obj->dispatch_chan = nil;
	obj->distance = 0; /* remote */
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
			free(e->key);
			/* Note: generic val is NOT freed, caller must manage if it's a pointer */
			free(e);
		}
	}
}

static ulong
o9_dict_hash(char *s)
{
	ulong h = 5381;
	int c;
	while((c = *s++))
		h = ((h << 5) + h) + c;
	return h & 63;
}

/*
 * o9_dict_get — get value for key. Returns nil if not found.
 */
void*
o9_dict_get(O9Dict *d, char *key)
{
	O9DictEntry *e;
	if(d == nil || key == nil) return nil;
	for(e = d->buckets[o9_dict_hash(key)]; e; e = e->next)
		if(strcmp(e->key, key) == 0)
			return e->val;
	return nil;
}

/*
 * o9_dict_set — set key=val, replacing existing if present.
 */
void
o9_dict_set(O9Dict *d, char *key, void *val)
{
	ulong h;
	O9DictEntry *e;
	if(d == nil || key == nil) return;
	h = o9_dict_hash(key);
	for(e = d->buckets[h]; e; e = e->next){
		if(strcmp(e->key, key) == 0){
			e->val = val;
			return;
		}
	}
	e = mallocz(sizeof(O9DictEntry), 1);
	e->key = strdup(key);
	e->val = val;
	e->next = d->buckets[h];
	d->buckets[h] = e;
}

/*
 * o9_dict_has — check if key exists.
 */
int
o9_dict_has(O9Dict *d, char *key)
{
	O9DictEntry *e;
	if(d == nil || key == nil) return 0;
	for(e = d->buckets[o9_dict_hash(key)]; e; e = e->next)
		if(strcmp(e->key, key) == 0) return 1;
	return 0;
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
			len += strlen(e->key) + 1 + strlen(e->val) + 1;
	buf = mallocz(len, 1);
	p = buf;
	for(i = 0; i < 64; i++){
		for(e = d->buckets[i]; e; e = e->next){
			memmove(p, e->key, strlen(e->key));
			p += strlen(e->key);
			*p++ = ':';
			memmove(p, e->val, strlen(e->val));
			p += strlen(e->val);
			*p++ = '\n';
		}
	}
	*p = '\0';
	return buf;
}
