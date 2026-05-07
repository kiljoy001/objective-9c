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
done:
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
done:
	r->ok = 1;
	sendp(msg->replyc, r);
}

static void o9_impl_Counter_double(Counter_Internal *self, O9Msg *msg) {
	O9Reply *r = mallocz(sizeof(O9Reply), 1);
	r->ret = (void*)((self->val * 2));
	goto done;
done:
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
		case 0xd0a834ada145: o9_impl_Counter_Counter(self, m); break;
		case 0x1ae710fdcb98a2: o9_impl_Counter_getValue(self, m); break;
		case 0xb88801f: o9_impl_Counter_inc(self, m); break;
		case 0x652f93d5b20: o9_impl_Counter_double(self, m); break;
		case 0xd0b2097af1ef: o9_cleanup_Counter(self); threadexits(nil); break;
		default: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = "bad selector"; sendp(m->replyc, r); } break;
		}
	}
}

static void fsread_Counter(Req *r) {
	char buf[1024];
	Counter_Internal *s = r->srv->aux;
	char *name = r->fid->file->name;

	if(strcmp(name, "status") == 0) { readstr(r, "running"); respond(r, nil); return; }
	if(strcmp(name, "val") == 0){
		snprint(buf, sizeof buf, "%lld\n", (vlong)s->val);
		readstr(r, buf); respond(r, nil); return;
	}
	respond(r, "not found");
}

static void fswrite_Counter(Req *r) {
	Counter_Internal *s = r->srv->aux;
	char *name = r->fid->file->name;
	if(strcmp(name, "ctl") == 0) { /* TODO: parse text ctl */ respond(r, nil); return; }
	if(strcmp(name, "msg") == 0) { /* TODO: parse binary msg */ respond(r, nil); return; }
	if(strcmp(name, "val") == 0){
		s->val = (vlong)strtoll(r->ifcall.data, nil, 0);
		r->ofcall.count = r->ifcall.count;
		respond(r, nil);
		return;
	}
	respond(r, "read only or not found");
}

Srv o9srv_Counter;

void o9_main_Counter(int argc, char **argv) {
	Counter_Internal *s = emalloc9p(sizeof(Counter_Internal));
	memset(s, 0, sizeof(Counter_Internal));
	s->dispatch_chan = chancreate(sizeof(void*), 10);
	o9srv_Counter.read = fsread_Counter;
	o9srv_Counter.write = fswrite_Counter;
	o9srv_Counter.aux = s;
	Tree *t = alloctree(nil, nil, 0555, nil);
	o9srv_Counter.tree = t;
	createfile(t->root, "ctl", nil, 0222, nil);
	createfile(t->root, "msg", nil, 0222, nil);
	createfile(t->root, "status", nil, 0444, nil);
	createfile(t->root, "cache", nil, 0444, nil);
	createfile(t->root, "val", nil, 0666, nil);
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
	c.dispatch_chan = __c->dispatch_chan;
	__c->val = 0;
	proccreate(Counter_loop, __c, 8192);
	o9_call_args[0]=10;
	obj9_msgSend(&c, 0xd0a834ada145, o9_call_args);
	(o9_call_args[0]=5, (vlong)obj9_msgSend(&c, 0xb88801f, o9_call_args));
	(o9_call_args[0]=1, (vlong)obj9_msgSend(&c, 0xb88801f, o9_call_args));
	vlong v = ((vlong)obj9_msgSend(&c, 0x1ae710fdcb98a2, o9_call_args));
	vlong d = ((vlong)obj9_msgSend(&c, 0x652f93d5b20, o9_call_args));
	threadexitsall(nil);
}
