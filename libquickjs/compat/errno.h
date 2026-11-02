#ifndef P9_COMPAT_ERRNO_H
#define P9_COMPAT_ERRNO_H

/* Native Plan 9 has no errno; QuickJS only includes this under
 * CONFIG_ATOMICS, which is disabled under PLAN9.  Keep a definition for
 * source compatibility, but do not use it for real error reporting. */
extern int errno;

#define EDOM 33
#define ERANGE 34
#define EINVAL 22
#define ENOMEM 12

#endif
