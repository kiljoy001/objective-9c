#ifndef P9_COMPAT_STDDEF_H
#define P9_COMPAT_STDDEF_H

/* Native Plan 9 6c has no stddef.h.  On amd64, long remains 32-bit;
 * the machine word is long long / usize (see /amd64/include/u.h). */
typedef unsigned long long size_t;
typedef long long ptrdiff_t;

#ifndef NULL
#define NULL ((void *)0)
#endif
#ifndef offsetof
#define offsetof(s, m) ((size_t)&(((s *)0)->m))
#endif

#endif
