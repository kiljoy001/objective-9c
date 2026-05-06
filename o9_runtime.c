#include <u.h>
#include <libc.h>
#include <bio.h>
#include "o9.h"

/*
 * o9_runtime.c -- 9front native runtime for o9 objects.
 * Handles the handshake to "pin" shared memory and populate Asm tables.
 * Implements lazy cache-fill for the assembly dispatch stubs.
 */

/* Forward declaration of the assembly-visible cache fill callback */
void o9_cache_fill(o9_AsmTable *table, ulong hash, int is_ctrl);

int
o9_init_client(void *client, char *srvname, int size)
{
	o9_Object *obj = client;
	o9_AsmTable *table;
	Biobuf *bp;
	char line[256], *p, *key, *val, *l;
	int fd;
	void *base;

	/* 1. Open the cache metadata from the fileserver */
	snprint(line, sizeof line, "/srv/%s", srvname);
	fd = open(line, ORDWR);
	if(fd < 0) return -1;
	
	/* In a real impl, we'd walk to /cache. 
	 * For the MVP, we assume the fd is the root */
	bp = Bfdopen(fd, OREAD);
	if(bp == nil) return -1;

	/* 2. Parse the /cache handshake */
	while((l = Brdstr(bp, '\n', 1)) != nil){
		p = strchr(l, ':');
		if(p == nil) { free(l); continue; }
		*p++ = 0;
		key = l;
		val = p;

		if(strcmp(key, "seg") == 0){
			/* Tier 1: Shared Memory Pinning */
			base = segattach(0, val, nil, size);
			if(base == (void*)-1) return -1;
			obj->shm_base = base;
		}
		
		/* 3. Populate Asm Tables based on offsets */
		if(key[0] == 'd'){
			/* Data property offset (d:hash:offset) */
			ulong h = strtoul(key+2, nil, 10);
			long off = strtol(val, nil, 10);
			table = obj->table;
			table->data_cache[h & 63].hash = h;
			table->data_cache[h & 63].ptr = (char*)obj->shm_base + off;
		}
		if(key[0] == 'c'){
			/* Control method entry (c:hash:ptr) */
			ulong h = strtoul(key+2, nil, 10);
			void *ptr = (void*)strtoul(val, nil, 16);
			table = obj->table;
			table->ctrl_cache[h & 63].hash = h;
			table->ctrl_cache[h & 63].ptr = ptr;
		}
		
		free(l);
	}
	
	Bterm(bp);
	return 0;
}

void
o9_cache_fill(o9_AsmTable *table, ulong hash, int is_ctrl)
{
	/*
	 * Called on asm cache miss from o9_dispatch.s.
	 * In a full implementation, this would:
	 * 1. Walk to /srv/<class>/cache 
	 * 2. Find the entry matching 'hash'
	 * 3. For data: compute the SHM offset, store pointer
	 * 4. For ctrl: store the function pointer
	 *
	 * For the MVP / L1 warm-path, the table is pre-filled by
	 * o9_init_client and the cache is always hot after setup.
	 * This function is called automatically by the asm stub
	 * on cache miss and should rarely be hit in practice.
	 *
	 * For now: search the table linearly for a matching hash
	 * in the OTHER cache (some entries may have been filled by
	 * the parallel data/ctrl init) — degenerate fallback.
	 */
	int i;
	if(is_ctrl){
		for(i = 0; i < 64; i++){
			if(table->data_cache[i].hash == hash){
				table->ctrl_cache[i].hash = hash;
				table->ctrl_cache[i].ptr = table->data_cache[i].ptr;
				return;
			}
		}
	} else {
		for(i = 0; i < 64; i++){
			if(table->ctrl_cache[i].hash == hash){
				table->data_cache[i].hash = hash;
				table->data_cache[i].ptr = table->ctrl_cache[i].ptr;
				return;
			}
		}
	}
	/* Still a miss — caller's retry will fail and return nil. */
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
    return nil;
}
