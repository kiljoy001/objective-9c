#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

typedef struct Worker Worker;
struct Worker {
	o9_Object *obj;
	Channel *done;
	int base;
	int n;
};

static void
worker(void *v)
{
	Worker *w;
	O9String *line, *reply;
	char cmd[128], *s;
	int i, want, got, fail;

	w = v;
	fail = 0;
	for(i = 0; i < w->n; i++){
		want = w->base + i;
		snprint(cmd, sizeof cmd, "method Echo.e id arg0=%d", want);
		line = o9_string_from_c(cmd);
		reply = o9_send(w->obj, line);
		o9_string_release(line);
		if(reply == nil){
			fprint(2, "remote9p: nil reply for %s\n", cmd);
			fail++;
			continue;
		}
		s = o9_string_cstr(reply);
		o9_string_release(reply);
		if(s == nil){
			fprint(2, "remote9p: nil cstr for %s\n", cmd);
			fail++;
			continue;
		}
		got = strtol(s, nil, 0);
		free(s);
		if(got != want){
			fprint(2, "remote9p: got %d want %d\n", got, want);
			fail++;
		}
	}
	sendul(w->done, fail);
	free(w);
}

void
threadmain(int argc, char **argv)
{
	o9_Object obj;
	Channel *done;
	Worker *a, *b;
	ulong fail;

	if(argc != 2)
		sysfatal("usage: runtime_remote9p_test /srv/o9.app.app.app");

	memset(&obj, 0, sizeof obj);
	obj.fd = -1;
	if(o9_connect(&obj, argv[1], "Echo", 1) < 0)
		sysfatal("o9_connect %s: %r", argv[1]);

	done = chancreate(sizeof(ulong), 2);
	if(done == nil)
		sysfatal("chancreate");
	a = mallocz(sizeof *a, 1);
	b = mallocz(sizeof *b, 1);
	if(a == nil || b == nil)
		sysfatal("malloc");
	a->obj = &obj;
	a->done = done;
	a->base = 1000;
	a->n = 32;
	b->obj = &obj;
	b->done = done;
	b->base = 2000;
	b->n = 32;
	proccreate(worker, a, 65536);
	proccreate(worker, b, 65536);
	fail = recvul(done);
	fail += recvul(done);
	chanfree(done);
	if(obj.fd >= 0)
		close(obj.fd);
	if(fail != 0)
		sysfatal("remote9p failures: %lud", fail);
	print("runtime_remote9p_test: OK\n");
	threadexitsall(nil);
}
