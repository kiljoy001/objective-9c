#include <u.h>
#include <libc.h>
#include <bio.h>
#include <thread.h>
#include "o9.h"

/*
 * o9_runtime.c -- 9front native runtime for o9 objects.
 * Handles the handshake to "pin" shared memory and populate Asm tables.
 * Implements lazy cache-fill for the assembly dispatch stubs.
 */

/* Forward declaration of the assembly-visible cache fill callback */
void o9_cache_fill(o9_AsmTable *table, ulong hash, int is_ctrl);

static void
o9_fill_from_buf(o9_AsmTable *table, Biobuf *bp, o9_Object *obj)
{
	char *p, *key, *val, *l;

	while((l = Brdstr(bp, '\n', 1)) != nil){
		p = strchr(l, ':');
		if(p == nil) { free(l); continue; }
		*p++ = 0;
		key = l;
		val = p;

		if(strcmp(key, "seg") == 0){
			if(obj == nil) { free(l); continue; }
			obj->shm_base = segattach(0, val, nil, 8192);
			if(obj->shm_base == (void*)-1)
				obj->shm_base = nil;
			free(l);
			continue;
		}

		/* Populate Asm Tables based on hash prefix */
		if(key[0] == 'd'){
			ulong h = strtoul(key+1, nil, 10);
			long off = strtol(val, nil, 10);
			table->data_cache[h & 63].hash = h;
			if(obj && obj->shm_base)
				table->data_cache[h & 63].ptr = (char*)obj->shm_base + off;
		}
		if(key[0] == 'c'){
			ulong h = strtoul(key+1, nil, 10);
			void *ptr = (void*)strtoul(val, nil, 16);
			table->ctrl_cache[h & 63].hash = h;
			table->ctrl_cache[h & 63].ptr = ptr;
		}

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
	int fd;

	USED(size);

	/* Stash srvname and set owner back-pointer */
	strncpy(obj->srvname, srvname, sizeof(obj->srvname)-1);
	table = obj->table;
	if(table)
		table->owner = obj;

	/* Open /srv/<name>/cache to read all cache entries */
	snprint(path, sizeof path, "/srv/%s/cache", srvname);
	fd = open(path, OREAD);
	if(fd < 0) return -1;
	obj->fd = fd;

	/* If no table, just stash the fd and return */
	if(table == nil) return 0;

	bp = Bfdopen(fd, OREAD);
	if(bp == nil) return -1;

	o9_fill_from_buf(table, bp, obj);

	Bterm(bp);
	close(fd);
	obj->fd = -1;
	return 0;
}

void
o9_cache_fill(o9_AsmTable *table, ulong hash, int is_ctrl)
{
	o9_Object *obj;
	char path[256];
	Biobuf *bp;
	int fd;

	if(table == nil) return;
	obj = table->owner;
	if(obj == nil || obj->srvname[0] == '\0') return;

	/* Open /srv/<name>/cache and re-parse to find this hash */
	snprint(path, sizeof path, "/srv/%s/cache", obj->srvname);
	fd = open(path, OREAD);
	if(fd < 0) return;

	bp = Bfdopen(fd, OREAD);
	if(bp == nil){ close(fd); return; }

	o9_fill_from_buf(table, bp, obj);

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

    /* Tier 2: Local CSP Channel */
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

    /* Tier 3: 9P Fallback (not implemented here yet) */
    if(obj->fd >= 0){
        /* TODO: 9P Twalk/Twrite for remote dispatch */
    }
    return nil;
}
