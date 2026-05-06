/* Generated o9 Source */
#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>

#ifndef _O9_COMMON_
#define _O9_COMMON_
#define o9_offsetof(s, m) (long)(&(((s*)0)->m))
typedef struct ArcEntry {
	ulong id;
	long count;
} ArcEntry;

typedef struct ArcLedger {
	ArcEntry entries[64];
} ArcLedger;
typedef struct O9Msg O9Msg;
typedef struct O9Reply O9Reply;
struct O9Msg {
	ulong sel;
	void *args;
	int nargs;
	Channel *replyc;
};
struct O9Reply {
	int ok;
	void *ret;
	char *err;
};
#endif

/* Generated Client Header for class LocalTest */
#ifndef _O9_GEN_LocalTest_H_
#define _O9_GEN_LocalTest_H_

typedef struct LocalTest_AsmTable {
	void *data_cache[64];
	void (*ctrl_cache[64])(void*);
} LocalTest_AsmTable;

typedef struct LocalTest_Client {
	int fd;
	LocalTest_AsmTable *table;
	long ref;	/* ARC Counter */
} LocalTest_Client;

#endif

/* Implementation for class LocalTest (Tiered CSP/9P Model) */
typedef struct LocalTest_Internal LocalTest_Internal;
struct LocalTest_Internal {
	ArcLedger ledger;
	vlong val;
	Channel *dispatch_chan;
};

static void o9_impl_LocalTest_run(LocalTest_Internal *self, O9Msg *msg) {
	O9Reply *r = mallocz(sizeof(O9Reply), 1);
	vlong temp = 10;
	vlong temp2;
	temp2 = 5;
	self->val = (temp + temp2);
	r->ok = 1;
	sendp(msg->replyc, r);
}

static void o9_cleanup_LocalTest(LocalTest_Internal *self) {
	chanfree(self->dispatch_chan);
	free(self);
}

static void LocalTest_loop(void *v) {
	LocalTest_Internal *self = v;
	O9Msg *m;
	for(;;){
		m = recvp(self->dispatch_chan);
		if(m == nil) continue;
		switch(m->sel){
		case 0xb88a75a: o9_impl_LocalTest_run(self, m); break;
		case 0xd0b2097af1ef: o9_cleanup_LocalTest(self); threadexits(nil); break;
		default: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = "bad selector"; sendp(m->replyc, r); } break;
		}
	}
}

static void fsread_LocalTest(Req *r) {
	char buf[1024];
	LocalTest_Internal *s = r->srv->aux;
	char *name = r->fid->file->dir.name;

	if(strcmp(name, "status") == 0) { readstr(r, "running"); respond(r, nil); return; }
	if(strcmp(name, "val") == 0){
		snprint(buf, sizeof buf, "%lld\n", (vlong)s->val);
		readstr(r, buf); respond(r, nil); return;
	}
	respond(r, "not found");
}

static void fswrite_LocalTest(Req *r) {
	LocalTest_Internal *s = r->srv->aux;
	char *name = r->fid->file->dir.name;
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

Srv o9srv_LocalTest;

void o9_main_LocalTest(int argc, char **argv) {
	LocalTest_Internal *s = emalloc9p(sizeof(LocalTest_Internal));
	memset(s, 0, sizeof(LocalTest_Internal));
	s->dispatch_chan = chancreate(sizeof(void*), 10);
	o9srv_LocalTest.read = fsread_LocalTest;
	o9srv_LocalTest.write = fswrite_LocalTest;
	o9srv_LocalTest.aux = s;
	Tree *t = alloctree(nil, nil, 0555, nil);
	o9srv_LocalTest.tree = t;
	createfile(t->root, "ctl", nil, 0222, nil);
	createfile(t->root, "msg", nil, 0222, nil);
	createfile(t->root, "status", nil, 0444, nil);
	createfile(t->root, "cache", nil, 0444, nil);
	createfile(t->root, "val", nil, 0666, nil);
	proccreate(LocalTest_loop, s, 8192);
	threadpostmountsrv(&o9srv_LocalTest, "LocalTest", nil, MREPL);
}
void
threadmain(int argc, char **argv)
{
	o9_main_LocalTest(argc, argv);
}
