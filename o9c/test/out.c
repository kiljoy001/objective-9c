/* Generated o9 Source */
#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>
#include "o9.h"

#ifndef _O9_COMMON_
#define _O9_COMMON_
#define o9_offsetof(s, m) (long)(&(((s*)0)->m))
vlong o9_call_args[64];
typedef struct ArcEntry {
	ulong id;
	long count;
} ArcEntry;

typedef struct ArcLedger {
	ArcEntry entries[64];
} ArcLedger;
#endif

/* Generated Client Header for class Counter */
#ifndef _O9_GEN_Counter_H_
#define _O9_GEN_Counter_H_

typedef struct Counter_AsmTable {
	void *data_cache[64];
	void (*ctrl_cache[64])(void*);
} Counter_AsmTable;

typedef struct Counter_Client {
	int fd;
	void *shm_base;
	o9_AsmTable *table;
	long ref;	/* ARC Counter */
	void *dispatch_chan;
} Counter_Client;

#endif

/* Implementation for class Counter (Tiered CSP/9P Model) */
typedef struct Counter_Internal Counter_Internal;
struct Counter_Internal {
	ArcLedger ledger;
	vlong val;
	Channel *dispatch_chan;
};

static void o9_impl_Counter_Counter(Counter_Internal *self, O9Msg *msg) {
	O9Reply *r = mallocz(sizeof(O9Reply), 1);
	vlong n = ((vlong*)msg->args)[0];
	self->val = n;
	r->ok = 1;
	sendp(msg->replyc, r);
}

static void o9_impl_Counter_getValue(Counter_Internal *self, O9Msg *msg) {
	O9Reply *r = mallocz(sizeof(O9Reply), 1);
	r->ret = (void*)(self->val);
	goto done;
done:
	r->ok = 1;
	sendp(msg->replyc, r);
}

static void o9_impl_Counter_inc(Counter_Internal *self, O9Msg *msg) {
	O9Reply *r = mallocz(sizeof(O9Reply), 1);
	vlong n = ((vlong*)msg->args)[0];
	self->val = (self->val + n);
	r->ok = 1;
	sendp(msg->replyc, r);
}

static void o9_cleanup_Counter(Counter_Internal *self) {
	chanfree(self->dispatch_chan);
	free(self);
}

static void Counter_loop(void *v) {
	Counter_Internal *self = v;
	O9Msg *m;
	for(;;){
		m = recvp(self->dispatch_chan);
		if(m == nil) continue;
		switch(m->sel){
		case 0x34ada145: o9_impl_Counter_Counter(self, m); break;
		case 0xfdcb98a2: o9_impl_Counter_getValue(self, m); break;
		case 0xb88801f: o9_impl_Counter_inc(self, m); break;
		case 0x97af1ef: o9_cleanup_Counter(self); threadexits(nil); break;
		default: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = "bad selector"; sendp(m->replyc, r); } break;
		}
	}
}

static void fsread_Counter(Req *r) {
	char buf[1024];
	char *name = r->fid->file->name;
	Counter_Internal *inst = r->fid->file->aux;

	if(strcmp(name, "status") == 0) { readstr(r, "running"); respond(r, nil); return; }
	if(strcmp(name, "cache") == 0) {
		char cachebuf[4096];
		char *p = cachebuf;
		p += snprint(p, sizeof cachebuf - (p-cachebuf), "seg:Counter\n");
		p += snprint(p, sizeof cachebuf - (p-cachebuf), "d:%ld:%ld\n", 193508808L, (long)o9_offsetof(Counter_Internal, val));
		p += snprint(p, sizeof cachebuf - (p-cachebuf), "c:%ld:%p\n", 883794245L, o9_impl_Counter_Counter);
		p += snprint(p, sizeof cachebuf - (p-cachebuf), "c:%ld:%p\n", 4257978530L, o9_impl_Counter_getValue);
		p += snprint(p, sizeof cachebuf - (p-cachebuf), "c:%ld:%p\n", 193495071L, o9_impl_Counter_inc);
		readstr(r, cachebuf); respond(r, nil); return;
	}
	if(inst == nil) { respond(r, "clone read"); return; }

	if(strcmp(name, "getValue") == 0){
		O9Reply *__o9rep = r->fid->aux;
		if(__o9rep == nil){ respond(r, "no pending reply"); return; }
		snprint(buf, sizeof buf, "%lld\n", (vlong)__o9rep->ret);
		r->fid->aux = nil;
		free(__o9rep);
		readstr(r, buf); respond(r, nil); return;
	}
	if(strcmp(name, "val") == 0){
		snprint(buf, sizeof buf, "%lld\n", (vlong)inst->val);
		readstr(r, buf); respond(r, nil); return;
	}
	respond(r, "not found");
}

static void fswrite_Counter(Req *r) {
	char *name = r->fid->file->name;
	Counter_Internal *inst = r->fid->file->aux;
	if(strcmp(name, "ctl") == 0) { /* TODO: parse ctl */ respond(r, nil); return; }
	if(strcmp(name, "Counter") == 0){
		vlong __wargs[1] = {0};
		__wargs[0] = strtoll(r->ifcall.data, nil, 0);
		{ O9Msg __wm = {0x34ada145, __wargs, 1, chancreate(sizeof(void*), 0)};
		sendp(inst->dispatch_chan, &__wm);
		recvp(__wm.replyc);
		chanfree(__wm.replyc); }
		r->ofcall.count = r->ifcall.count;
		respond(r, nil);
		return;
	}
	if(strcmp(name, "getValue") == 0){
		{ O9Msg __wm = {0xfdcb98a2, nil, 0, chancreate(sizeof(void*), 0)};
		sendp(inst->dispatch_chan, &__wm);
		O9Reply *__o9rep = recvp(__wm.replyc);
		r->fid->aux = __o9rep;
		chanfree(__wm.replyc); }
		r->ofcall.count = r->ifcall.count;
		respond(r, nil);
		return;
	}
	if(strcmp(name, "inc") == 0){
		vlong __wargs[1] = {0};
		__wargs[0] = strtoll(r->ifcall.data, nil, 0);
		{ O9Msg __wm = {0xb88801f, __wargs, 1, chancreate(sizeof(void*), 0)};
		sendp(inst->dispatch_chan, &__wm);
		recvp(__wm.replyc);
		chanfree(__wm.replyc); }
		r->ofcall.count = r->ifcall.count;
		respond(r, nil);
		return;
	}
	if(strcmp(name, "val") == 0){
		inst->val = (vlong)strtoll(r->ifcall.data, nil, 0);
		r->ofcall.count = r->ifcall.count;
		respond(r, nil);
		return;
	}
	respond(r, "read only or not found");
}

Srv o9srv_Counter;
static Tree *Counter_tree;
int Counter_create_instance(Counter_Internal *inst, char *name) {
	File *dir = createfile(Counter_tree->root, name, nil, 0755, nil);
	if(dir == nil) return -1;
	dir->aux = inst;
	createfile(dir, "status", nil, 0444, nil);
	{ File *__f = createfile(dir, "val", nil, 0666, nil); if(__f) __f->aux = inst; }
	{ File *__f = createfile(dir, "Counter", nil, 0222, nil); if(__f) __f->aux = inst; }
	{ File *__f = createfile(dir, "getValue", nil, 0644, nil); if(__f) __f->aux = inst; }
	{ File *__f = createfile(dir, "inc", nil, 0222, nil); if(__f) __f->aux = inst; }
	return 0;
}
void o9_main_Counter(int argc, char **argv) {
	Counter_Internal *s = segattach(0, nil, "o9/Counter", sizeof(Counter_Internal));
	if(s == (void*)-1){ fprint(2, "o9_main_Counter: segattach failed\n"); threadexits("segattach"); }
	memset(s, 0, sizeof(Counter_Internal));
	s->dispatch_chan = chancreate(sizeof(void*), 10);
	o9srv_Counter.read = fsread_Counter;
	o9srv_Counter.write = fswrite_Counter;
	Counter_tree = alloctree(nil, nil, 0555, nil);
	o9srv_Counter.tree = Counter_tree;
	createfile(Counter_tree->root, "clone", nil, 0222, nil);
	createfile(Counter_tree->root, "status", nil, 0444, nil);
	createfile(Counter_tree->root, "cache", nil, 0444, nil);
	proccreate(Counter_loop, s, 8192);
	threadpostmountsrv(&o9srv_Counter, "Counter", nil, MREPL);
}
void
threadmain(int argc, char **argv)
{
	o9_main_Counter(argc, argv);
	Counter_Internal *__c = emalloc9p(sizeof(Counter_Internal));
	memset(__c, 0, sizeof(Counter_Internal));
	__c->dispatch_chan = chancreate(sizeof(void*), 10);
	Counter_Client c;
	memset(&c, 0, sizeof(Counter_Client));
	c.shm_base = __c;
	c.dispatch_chan = __c->dispatch_chan;
	__c->val = 0;
	proccreate(Counter_loop, __c, 8192);
	Counter_create_instance(__c, "c");
	{ vlong __a[1];
	__a[0] = 10;
	obj9_msgSend(&c, 0x34ada145, __a); }
	(o9_call_args[0]=5, (vlong)obj9_msgSend(&c, 0xb88801f, o9_call_args));
	while((((vlong)obj9_msgSend(&c, 0xfdcb98a2, o9_call_args)) < 1000)){
	(o9_call_args[0]=1, (vlong)obj9_msgSend(&c, 0xb88801f, o9_call_args));
	}
	fprint(1, "done");
	threadexitsall(nil);
}
