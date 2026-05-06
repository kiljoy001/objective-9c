/* Generated Client Header for class Counter */
#ifndef _O9_GEN_Counter_H_
#define _O9_GEN_Counter_H_

typedef struct Counter_AsmTable {
	void *data_cache[64];
	void (*ctrl_cache[64])(void*);
} Counter_AsmTable;

typedef struct Counter_Client {
	int fd;
	Counter_AsmTable *table;
	Ref ref;
} Counter_Client;

/* Ledger-aware ref counting */
#define Counter_RETAIN(c, id) o9_ledger_update((c), id, 1)
#define Counter_RELEASE(c, id) o9_ledger_update((c), id, -1)

#endif

/* Generated 9P/Asm Fileserver for class Counter with ARC Ledger */
#include <u.h>
#include <libc.h>
#include <thread.h>
#include <9p.h>
#include <stddef.h>
#include <sys/mman.h>
#include <fcntl.h>

typedef struct ArcEntry {
	ulong id;
	long count;
} ArcEntry;

typedef struct ArcLedger {
	ArcEntry entries[64];
} ArcLedger;

typedef struct Counter_State {
	ArcLedger ledger;
	vlong val;
} Counter_State;

static void
fsread(Req *r)
{
	char buf[2048], *p;
	Counter_State *s = r->srv->aux;
	int i;

	if(strcmp(r->fid->file->dir.name, "ledger") == 0){
		p = buf;
		p += snprint(p, sizeof buf - (p-buf), "ID\t\tREFS\n");
		for(i=0; i<64; i++){
			if(s->ledger.entries[i].id != 0)
				p += snprint(p, sizeof buf - (p-buf), "%ld\t%ld\n", s->ledger.entries[i].id, s->ledger.entries[i].count);
		}
		readstr(r, buf);
		respond(r, nil);
		return;
	}
	if(strcmp(r->fid->file->dir.name, "cache") == 0){
		p = buf;
		p += snprint(p, sizeof buf - (p-buf), "shm:/tmp/o9.Counter.shm\n");
		p += snprint(p, sizeof buf - (p-buf), "ledger:%ld\n", (long)offsetof(Counter_State, ledger));
		readstr(r, buf);
		respond(r, nil);
		return;
	}
	respond(r, "not found");
}

Srv o9srv_Counter = { .read = fsread };

void
threadmain(int argc, char **argv)
{
	Counter_State *s;
	int fd;
	fd = p9open("/tmp/o9.Counter.shm", ORDWR|OTRUNC);
	if(fd < 0) fd = create("/tmp/o9.Counter.shm", ORDWR, 0666);
	seek(fd, sizeof(Counter_State)-1, 0);
	write(fd, "", 1);
	s = mmap(NULL, sizeof(Counter_State), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	memset(s, 0, sizeof(Counter_State));
	o9srv_Counter.aux = s;
	threadpostmountsrv(&o9srv_Counter, "Counter", nil, MREPL);
	threadexitsall(nil);
}
