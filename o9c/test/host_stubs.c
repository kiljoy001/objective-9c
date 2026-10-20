/*
 * Host-only compatibility stubs for plan9port.
 *
 * 9front's libthread has chanclosing/chanclose; plan9port does not.  The
 * host test archive links this file instead of o9_view.o, which is
 * 9front-specific, so the runtime's reference to o9_view_dispatch_busy
 * also needs a stub.  Do not add this to the native build.
 */
#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9c/test/host_compat.h"

int
chanclosing(Channel *c)
{
	USED(c);
	return -1;
}

void
chanclose(Channel *c)
{
	USED(c);
}

int
bind(char *name, char *old, int flags)
{
	USED(name);
	USED(old);
	USED(flags);
	return -1;
}

int
mount(int fd, int afd, char *old, int flags, char *aname)
{
	USED(fd);
	USED(afd);
	USED(old);
	USED(flags);
	USED(aname);
	return -1;
}

/* The UI tests link the real o9_view.o; keep this weak so the real
 * implementation wins when both are present. */
__attribute__((weak)) int
o9_view_dispatch_busy(void)
{
	return 0;
}

void
srvrelease(Srv *s)
{
	USED(s);
}

void
srvacquire(Srv *s)
{
	USED(s);
}

void
threadlistensrv(Srv *s, char *addr)
{
	USED(s);
	USED(addr);
}

void
auth9p(Req *r)
{
	USED(r);
}

int
authattach(Req *r)
{
	USED(r);
	return 0;
}

void
authread(Req *r)
{
	USED(r);
}

void
authwrite(Req *r)
{
	USED(r);
}

void
authdestroy(Fid *f)
{
	USED(f);
}

long
ainc(long *r)
{
	return __sync_add_and_fetch(r, 1);
}

long
adec(long *r)
{
	return __sync_sub_and_fetch(r, 1);
}

int
threadpid(int tid)
{
	USED(tid);
	return 1;
}

void
do_not_call_exits_in_threaded_programs(char *s)
{
	threadexits(s);
}

/* plan9port has no unmount(2); net.o9 references it for /net namespace work. */
int
unmount(char *name, char *old)
{
	USED(name);
	USED(old);
	return -1;
}
