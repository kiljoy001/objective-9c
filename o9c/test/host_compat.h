/*
 * Host-only compatibility declarations for plan9port.
 *
 * plan9port's libc/libthread do not declare or provide the 9front kernel
 * namespace calls and channel-close helpers used by the runtime.  The
 * host test archive supplies minimal stubs; these declarations keep
 * clang's -Werror=implicit-function-declaration quiet in coverage builds.
 *
 * This header is passed with -include by tools/host_test.sh only.  It is
 * not part of the native build.
 */
#ifndef _O9_HOST_COMPAT_H_
#define _O9_HOST_COMPAT_H_

#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>
#include <auth.h>

int bind(char *name, char *old, int flags);
int mount(int fd, int afd, char *old, int flags, char *aname);
int chanclosing(Channel *c);
void chanclose(Channel *c);

/* 9front lib9p / auth helpers not present in plan9port. */
void srvrelease(Srv *s);
void srvacquire(Srv *s);
void threadlistensrv(Srv *s, char *addr);
void auth9p(Req *r);
int authattach(Req *r);
void authread(Req *r);
void authwrite(Req *r);
void authdestroy(Fid *f);

/* 9front atomics used by generated class servers. */
long ainc(long *r);
long adec(long *r);
int threadpid(int tid);
void do_not_call_exits_in_threaded_programs(char *s);

#endif
