#include <u.h>
#include <libc.h>
#include <bio.h>
#include <thread.h>
#include "o9.h"

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
	return ainc(p);
}

static long
o9_atomic_dec(long *p)
{
	return adec(p);
}

void o9_cache_fill(void *client, ulong hash, int is_ctrl);

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

int
o9_init_client(void *client, char *srvname, int size)
{
	o9_Object *obj = client;
	o9_AsmTable *table;
	Biobuf *bp;
	char path[256];
	char tag[64];
	int fd;

	USED(size);

	strncpy(obj->srvname, srvname, sizeof(obj->srvname)-1);
	table = obj->table;

	snprint(path, sizeof path, "/srv/%s/cache", srvname);
	fd = open(path, OREAD);
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
	obj->shm_base = segattach(0, nil, tag, 0);
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

	snprint(path, sizeof path, "/srv/%s/cache", obj->srvname);
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
        ret = r->ret;
        chanfree(m->replyc);
        free(r);
        free(m);
        return ret;
    }

    /* Fall through to remote 9P dispatch if connected */
    if(obj->fd >= 0 && method != nil && obj->distance >= 0){
        /* Inline 9P dispatch using method name */
        uchar buf[64];
        char wbuf[64];
        int n;

        /* Twalk to method */
        buf[0] = 0; buf[1] = 0; buf[2] = 0; buf[3] = 0;
        buf[4] = 110;
        buf[5] = 0; buf[6] = 0;
        PUT4(buf+7, obj->fd);
        PUT4(buf+11, obj->fd);
        n = strlen(method);
        PUT2(buf+15, 1);
        buf[17] = n; buf[18] = 0;
        memmove(buf+19, method, n);
        PUT4(buf, 19+n);
        write(obj->fd, buf, 19+n);
        n = read(obj->fd, buf, sizeof(buf));
        if(n < 4 || buf[4] != 111) goto skip;

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

        /* Twrite — triggers CSP dispatch on the server side */
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
            /* response is Rwrite — method side-effect is done */
        }

        /* Tread — read back return value for non-void methods */
        {
            char rbuf[64];
            PUT4(buf, 0);
            buf[4] = 116; /* Tread */
            buf[5] = 0; buf[6] = 0;
            PUT4(buf+7, obj->fd); /* use the same fid — method file has reply stored */
            PUT4(buf+11, 0); /* offset */
            PUT4(buf+15, sizeof(rbuf)-1); /* count */
            PUT4(buf, 19);
            write(obj->fd, buf, 19);
            n = read(obj->fd, buf, sizeof(buf));
            if(n >= 4 && buf[4] == 117){ /* Rread */
                u32int cnt = buf[7] | (buf[8]<<8) | (buf[9]<<16) | (buf[10]<<24);
                if(cnt > 0 && n >= 11+(int)cnt){
                    static vlong retval;
                    buf[11+cnt] = '\0';
                    retval = strtoll((char*)(buf+11), nil, 0);
                    return &retval;
                }
            }
        }
        goto skip;
    }

skip:
    return nil;
}

static long
o9_atomic_inc(long *p)
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

int
o9_connect(void *client, char *addr, char *srvname)
{
	o9_Object *obj = client;
	char buf[256];
	uchar rbuf[256];
	int fd, n, msize;

	/* Dial the address (il!host!service or tcp!host!port) */
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
			free(e->val);
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
char*
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
o9_dict_set(O9Dict *d, char *key, char *val)
{
	ulong h;
	O9DictEntry *e;
	if(d == nil || key == nil || val == nil) return;
	h = o9_dict_hash(key);
	for(e = d->buckets[h]; e; e = e->next){
		if(strcmp(e->key, key) == 0){
			free(e->val);
			e->val = strdup(val);
			return;
		}
	}
	e = mallocz(sizeof(O9DictEntry), 1);
	e->key = strdup(key);
	e->val = strdup(val);
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
