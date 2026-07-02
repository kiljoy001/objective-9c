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
	snprint(path, sizeof path, "/srv/%s/cache", srvname);
	return o9_init_client_cache(client, path, srvname, size);
}

int
o9_init_client_path(void *client, char *path, char *srvname, int size)
{
	char cachepath[256];

	if(path == nil || srvname == nil)
		return -1;
	snprint(cachepath, sizeof cachepath, "%s/cache", path);
	return o9_init_client_cache(client, cachepath, srvname, size);
}

void
o9_cache_fill(void *client, ulong hash, int is_ctrl)
{
    o9_Object *obj = client;
    char path[256];
    Biobuf *bp;
    int fd;

    USED(hash);
    USED(is_ctrl);

	if(obj == nil || obj->srvname[0] == '\0') return;

	if(obj->cachepath[0] != '\0')
		strncpy(path, obj->cachepath, sizeof(path)-1);
	else
		snprint(path, sizeof path, "/srv/%s/cache", obj->srvname);
	path[sizeof(path)-1] = '\0';
	fd = open(path, OREAD);
	if(fd < 0) return;

	bp = Bfdopen(fd, OREAD);
	if(bp == nil){ close(fd); return; }

	o9_fill_from_buf(obj->table, bp);

	Bterm(bp);
	close(fd);
}

void*
obj9_msgSend(void *receiver, char *method, ulong selector, void *args)
{
    o9_Object *obj = receiver;
    O9Msg *m;
    O9Reply *r;
    void *ret;

    if(obj->dispatch_chan != nil){
        m = mallocz(sizeof(O9Msg), 1);
        m->sel = selector;
        m->args = args;
        m->replyc = chancreate(sizeof(void*), 0);
        sendp(obj->dispatch_chan, m);
        r = recvp(m->replyc);
        ret = (void*)r->ret;
        chanfree(m->replyc);
        free(r);
        free(m);
        return ret;
    }

    /* Fall through to remote 9P dispatch if connected */
    if(obj->fd >= 0 && method != nil && obj->distance >= 0){
        uchar buf[64];
        int n;
        char mpath[128], *ep, *parts[4];
        int nparts = 0, pi;

        /* Parse method path: "inst/method" -> walk "inst" then "method" */
        strncpy(mpath, method, sizeof(mpath)-1);
        ep = mpath;
        for(pi = 0; pi < 4 && ep && *ep; pi++){
            parts[pi] = ep;
            ep = strchr(ep, '/');
            if(ep) *ep++ = '\0';
            nparts = pi + 1;
        }

        /* Twalk — walk each path element */
        for(pi = 0; pi < nparts; pi++){
            PUT4(buf, 0);
            buf[4] = 110; /* Twalk */
            buf[5] = 0; buf[6] = 0;
            PUT4(buf+7, obj->fd);
            PUT4(buf+11, obj->fd); /* newfid = same fid */
            PUT2(buf+15, 1); /* nwname = 1 */
            n = strlen(parts[pi]);
            buf[17] = n; buf[18] = 0;
            memmove(buf+19, parts[pi], n);
            PUT4(buf, 19+n);
            write(obj->fd, buf, 19+n);
            if(read(obj->fd, buf, sizeof(buf)) < 4 || buf[4] != 111)
                goto skip;
        }

        /* Topen OWRITE */
        PUT4(buf, 0);
        buf[4] = 112;
        buf[5] = 0; buf[6] = 0;
        PUT4(buf+7, obj->fd);
        buf[11] = 1;
        PUT4(buf, 12);
        write(obj->fd, buf, 12);
        n = read(obj->fd, buf, sizeof(buf));
        if(n < 4 || buf[4] != 113) goto skip;

        /* Twrite with args */
        {
            char astr[64];
            int m = snprint(astr, sizeof(astr), "%lld", args ? *(vlong*)args : 0);
            PUT4(buf, 0);
            buf[4] = 118;
            buf[5] = 0; buf[6] = 0;
            PUT4(buf+7, obj->fd);
            PUT4(buf+11, 0);
            PUT4(buf+15, m);
            memmove(buf+19, astr, m);
            PUT4(buf, 19+m);
            write(obj->fd, buf, 19+m);
            n = read(obj->fd, buf, sizeof(buf));
        }

        /* Tread — read back return value for non-void methods */
        {
            char rbuf[64];
            PUT4(buf, 0);
            buf[4] = 116; /* Tread */
            buf[5] = 0; buf[6] = 0;
            PUT4(buf+7, obj->fd);
            PUT4(buf+11, 0);
            PUT4(buf+15, sizeof(rbuf)-1);
            PUT4(buf, 19);
            write(obj->fd, buf, 19);
            n = read(obj->fd, buf, sizeof(buf));
            if(n >= 4 && buf[4] == 117){
                u32int cnt = buf[7] | (buf[8]<<8) | (buf[9]<<16) | (buf[10]<<24);
                if(cnt > 0 && n >= 11+(int)cnt){
                    static vlong retval;
                    buf[11+cnt] = '\0';
                    retval = strtoll((char*)(buf+11), nil, 0);
                    close(obj->fd);
                    return &retval;
                }
            }
        }
        goto skip;
    }

skip:
    return nil;
}

/*
 * obj9_msgSend_name — remote 9P dispatch over fd.
 * Walks to the method file, writes args, reads result.
 * Used when distance >= 0 (no dispatch_chan).
 */
void*
obj9_msgSend_name(void *receiver, char *method, ulong selector, void *args)
{
	o9_Object *obj = receiver;
	uchar buf[64];
	int n;

	if(obj == nil || obj->fd < 0) return nil;
	USED(selector);

	/* Twalk to method file — walk root (fid 0) to method name */
	buf[0] = 0; buf[1] = 0; buf[2] = 0; buf[3] = 0;
	buf[4] = 110; /* Twalk */
	buf[5] = 0; buf[6] = 0; /* tag */
	PUT4(buf+7, obj->fd); /* fid */
	PUT4(buf+11, obj->fd); /* newfid */
	PUT2(buf+15, 1); /* nwname */
	n = strlen(method);
	buf[17] = n; buf[18] = 0;
	memmove(buf+19, method, n);
	PUT4(buf, 19+n);
	write(obj->fd, buf, 19+n);
	n = read(obj->fd, buf, sizeof(buf));
	if(n < 4 || buf[4] != 111) return nil; /* Rwalk */

	/* Topen */
	PUT4(buf, 0);
	buf[4] = 112; /* Topen */
	buf[5] = 0; buf[6] = 0;
	PUT4(buf+7, obj->fd);
	buf[11] = 1; /* OWRITE */
	PUT4(buf, 12);
	write(obj->fd, buf, 12);
	n = read(obj->fd, buf, sizeof(buf));
	if(n < 4 || buf[4] != 113) return nil;

	/* Twrite — send args as vlong text */
	{
		char wbuf[64];
		int m = snprint(wbuf, sizeof(wbuf), "%lld", args ? *(vlong*)args : 0);
		PUT4(buf, 0);
		buf[4] = 118; /* Twrite */
		buf[5] = 0; buf[6] = 0;
		PUT4(buf+7, obj->fd);
		PUT4(buf+11, 0); /* offset */
		PUT4(buf+15, m);
		memmove(buf+19, wbuf, m);
		PUT4(buf, 19+m);
		write(obj->fd, buf, 19+m);
		n = read(obj->fd, buf, sizeof(buf));
	}

	return nil;
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

	/* Tattach */
	PUT4(buf, 0); /* len */
	buf[4] = 104; /* Tattach */
	buf[5] = 0; buf[6] = 0; /* tag */
	PUT4(buf+7, NOFID); /* afid */
	PUT2(buf+11, 1); /* uname len */
	buf[13] = 'S'; /* uname placeholder */
	PUT2(buf+14, 1); /* aname len */
	buf[16] = '/';
	PUT4(buf, 17);
	write(fd, buf, 17);

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

	/* Count lines */
	if(dp == nil || dp[0] == '\0')
		curlen = 0;
	else {
		curlen = 1;
		for(p = dp; *p; p++)
			if(*p == '\n') curlen++;
	}

	snprint(buf, sizeof buf, "%lld\n", val);

	if(idx < curlen){
		/* Replace — rebuild line by line */
		newsize = 0;
		p = dp;
		for(i = 0; i < curlen; i++){
			line = p;
			p = strchr(p, '\n');
			if(p) *p = '\0';
			newsize += (i == idx) ? strlen(buf) : strlen(line) + 1;
			if(p) p++;
		}
		new = mallocz(newsize + 1, 1);
		p = dp;
		for(i = 0; i < curlen; i++){
			line = p;
			p = strchr(p, '\n');
			if(p) *p++ = '\n';
			else p = line + strlen(line);
			if(i == idx)
				strcat(new, buf);
			else {
				strcat(new, line);
				strcat(new, "\n");
			}
		}
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
	n = 1;
	for(p = data; *p; p++)
		if(*p == '\n') n++;
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
