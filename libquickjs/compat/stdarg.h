#ifndef P9_COMPAT_STDARG_H
#define P9_COMPAT_STDARG_H

/* If <u.h> was included first, it already supplied va_list and the
 * amd64 va_* macros; do not redefine them.  Otherwise provide the same
 * amd64 ABI definitions. */
#ifndef nil

typedef char *va_list;

#define va_start(list, start) list =\
	(sizeof(start) < 8 ?\
		(char *)((long long *)&(start) + 1) :\
		(char *)(&(start) + 1))
#define va_end(list) ((void)(list))
#define va_arg(list, mode)\
	((sizeof(mode) == 1) ?\
		((list += 8), (mode *)list)[-8] :\
	(sizeof(mode) == 2) ?\
		((list += 8), (mode *)list)[-4] :\
	(sizeof(mode) == 4) ?\
		((list += 8), (mode *)list)[-2] :\
		((list += sizeof(mode)), (mode *)list)[-1])

#endif

#endif
