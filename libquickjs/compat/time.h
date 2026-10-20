#ifndef P9_COMPAT_TIME_H
#define P9_COMPAT_TIME_H

/* Plan 9 native time is vlong nanoseconds; the engine only needs a
 * time_t wide enough for the millisecond date range. */
typedef long long time_t;

struct tm {
	int tm_sec;
	int tm_min;
	int tm_hour;
	int tm_mday;
	int tm_mon;    /* 0..11 */
	int tm_year;   /* years since 1900 */
	int tm_wday;
	int tm_yday;
	int tm_isdst;
	long tm_gmtoff;      /* seconds east of UTC */
	char tm_zone[16];    /* copied, not a pointer; Plan 9 Tm owns its name */
};

struct tm *localtime_r(const time_t *, struct tm *);
struct tm *gmtime_r(const time_t *, struct tm *);

#endif
