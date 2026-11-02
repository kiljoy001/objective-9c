#ifndef P9_COMPAT_SETJMP_H
#define P9_COMPAT_SETJMP_H

/* dtoa.c includes setjmp.h but does not use it.  Match amd64 u.h's
 * jmp_buf size so a future use has the right ABI. */
typedef unsigned long long jmp_buf[2];

int setjmp(jmp_buf);
void longjmp(jmp_buf, int);

#endif
