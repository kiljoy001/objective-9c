#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>

/* 
 * o9pkg.c - The o9 "Mountable Installer" Fileserver
 */

static char *inst_script = 
    "#!/bin/rc\n"
    "echo 'Installing o9 Toolchain...'\n"
    "cp /n/o9/bin/o9c /bin/o9c\n"
    "cp /n/o9/include/o9.h /sys/include/o9.h\n"
    "cp /n/o9/lib/libo9.a /sys/lib/libo9.a\n"
    "chmod +x /bin/o9c\n"
    "echo 'o9 Installation Complete.'\n";

static void
serve_host_file(Req *r, char *path)
{
    int fd;
    long n;
    char *buf;

    fd = p9open(path, OREAD);
    if(fd < 0){
        respond(r, "could not open host file");
        return;
    }
    
    buf = emalloc9p(r->ifcall.count);
    n = pread(fd, buf, r->ifcall.count, r->ifcall.offset);
    close(fd);

    if(n < 0){
        free(buf);
        respond(r, "read error");
        return;
    }

    r->ofcall.data = buf;
    r->ofcall.count = n;
    respond(r, nil);
    free(buf);
}

static void
fsread(Req *r)
{
    char *name = r->fid->file->dir.name;

    if(strcmp(name, "install") == 0){
        readstr(r, inst_script);
        respond(r, nil);
        return;
    }
    
    if(strcmp(name, "o9c") == 0) { serve_host_file(r, "o9c/o9c"); return; }
    if(strcmp(name, "o9.h") == 0) { serve_host_file(r, "o9.h"); return; }
    if(strcmp(name, "libo9.a") == 0) { serve_host_file(r, "libo9.a"); return; }

    respond(r, "not found");
}

Srv o9pkg_srv = {
    .read = fsread,
};

void
usage(void)
{
    fprint(2, "usage: o9pkg [-a address]\n");
    threadexitsall("usage");
}

void
threadmain(int argc, char **argv)
{
    Tree *t;

    ARGBEGIN{
    case 'a':
        EARGF(usage());
        break;
    }ARGEND

    t = alloctree(nil, nil, 0555, nil);
    o9pkg_srv.tree = t;

    createfile(t->root, "install", nil, 0444, nil);
    File *bin = createfile(t->root, "bin", nil, DMDIR|0555, nil);
    createfile(bin, "o9c", nil, 0555, nil);
    File *inc = createfile(t->root, "include", nil, DMDIR|0555, nil);
    createfile(inc, "o9.h", nil, 0444, nil);
    File *lib = createfile(t->root, "lib", nil, DMDIR|0555, nil);
    createfile(lib, "libo9.a", nil, 0444, nil);

    /* Post the service locally */
    threadpostmountsrv(&o9pkg_srv, "o9pkg", nil, MREPL);
    
    print("o9 Installer Fileserver Online.\n");
    print("\nTo serve on network (Bash-safe):\n");
    print("aux/listen -t 'tcp!*!9009' /bin/9pserve -u \"$NAMESPACE/o9pkg\"\n\n");
    
    /* Allow the process to continue in the background */
    threadmaybackground();
    
    /* Keep the main thread alive but dormant */
    for(;;)
        sleep(10000);
}
