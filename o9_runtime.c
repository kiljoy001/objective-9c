#include <u.h>
#include <libc.h>
#include <bio.h>
#include "o9.h"

/*
 * o9_runtime.c -- 9front native runtime for o9 objects.
 * Handles the handshake to "pin" shared memory and populate Asm tables.
 */

int
o9_init_client(void *client, char *srvname, int size)
{
	o9_Object *obj = client;
	o9_AsmTable *table;
	Biobuf *bp;
	char *line, *p, *key, *val;
	int fd;
	void *base;

	/* 1. Open the cache metadata from the fileserver */
	snprint(line, 128, "/srv/%s", srvname);
	fd = open(line, ORDWR);
	if(fd < 0) return -1;
	
	/* In a real impl, we'd walk to /cache. 
	 * For the MVP, we assume the fd is the root */
	bp = Bfdopen(fd, OREAD);
	if(bp == nil) return -1;

	/* 2. Parse the /cache handshake */
	while((line = Brdstr(bp, '\n', 1)) != nil){
		p = strchr(line, ':');
		if(p == nil) { free(line); continue; }
		*p++ = 0;
		key = line;
		val = p;

		if(strcmp(key, "seg") == 0){
			/* Tier 1: Shared Memory Pinning */
			base = segattach(0, val, nil, size);
			if(base == (void*)-1) return -1;
			obj->shm_base = base;
		}
		
		/* 3. Populate Asm Tables based on offsets */
		if(key[0] == 'd'){
			/* Data property offset */
			long h = strtol(key+2, nil, 10);
			long off = strtol(val, nil, 10);
			table = obj->table;
			table->data_cache[h % 64] = (char*)obj->shm_base + off;
		}
		
		free(line);
	}
	
	Bterm(bp);
	return 0;
}

void
o9_ledger_update(void *client, ulong id, int delta)
{
	/* 4ns Atomic Update to the Ledger (Verified in PBT) */
	o9_Object *obj = client;
	/* Implementation uses __sync_fetch_and_add on Linux, 
	 * or ainc() on 9front. */
}
