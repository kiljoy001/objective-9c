#include <u.h>
#include <libc.h>
#include <bio.h>
#include <thread.h>
#include "o9.h"

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
obj9_msgSend(void *receiver, ulong selector, void *args)
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
