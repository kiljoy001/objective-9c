#ifndef P9_COMPAT_SYS_TIME_H
#define P9_COMPAT_SYS_TIME_H

struct timeval {
	long tv_sec;
	long tv_usec;
};

int gettimeofday(struct timeval *, void *);

#endif
