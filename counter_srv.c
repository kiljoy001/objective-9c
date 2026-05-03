#ifndef _O9_GEN_Counter_H_
#define _O9_GEN_Counter_H_

typedef struct Counter_Client {
        int fd;
        void *shm_base;
        vlong *val;
} Counter_Client;

#define Counter_SEND(c, prop, val) (*(c)->prop = val)
#define Counter_GET(c, prop) (*(c)->prop)

#endif

#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>
#include <stddef.h>
#include <sys/mman.h>
#include <fcntl.h>

typedef struct Counter_State {
        vlong val;
} Counter_State;

static void
fsread(Req *r)
{
        char buf[512];
        Counter_State *s = r->srv->aux;
        if(strcmp(r->fid->file->dir.name, "val") == 0){
                snprint(buf, sizeof buf, "%lld\n", (vlong)s->val);
                readstr(r, buf);
                respond(r, nil);
                return;
        }
        if(strcmp(r->fid->file->dir.name, "cache") == 0){
                char *p = buf;
                p += snprint(p, sizeof buf - (p-buf), "shm:/tmp/o9.Counter.shm\n");
                p += snprint(p, sizeof buf - (p-buf), "val:%ld\n", (long)offsetof(Counter_State, val));
                readstr(r, buf);
                respond(r, nil);
                return;
        }
        respond(r, "not found");
}

static void
fswrite(Req *r)
{
        Counter_State *s = r->srv->aux;
        if(strcmp(r->fid->file->dir.name, "val") == 0){
                s->val = strtoll(r->ifcall.data, nil, 0);
                r->ofcall.count = r->ifcall.count;
                respond(r, nil);
                return;
        }
        respond(r, "not found");
}

Srv o9srv_Counter = {
        .read = fsread,
        .write = fswrite,
};

void
threadmain(int argc, char **argv)
{
        Counter_State *s;
        Tree *t;
        int fd;

        fd = p9open("/tmp/o9.Counter.shm", ORDWR|OTRUNC);
        if(fd < 0) fd = create("/tmp/o9.Counter.shm", ORDWR, 0666);
        seek(fd, sizeof(Counter_State)-1, 0);
        write(fd, "", 1);
        s = mmap(NULL, sizeof(Counter_State), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
        memset(s, 0, sizeof(Counter_State));
        o9srv_Counter.aux = s;

        t = alloctree(nil, nil, 0555, nil);
        o9srv_Counter.tree = t;
        createfile(t->root, "val", nil, 0666, nil);
        createfile(t->root, "cache", nil, 0444, nil);

        threadpostmountsrv(&o9srv_Counter, "Counter", nil, MREPL);
        print("o9 Server [Counter] Online\n");
        threadexitsall(nil);
}
