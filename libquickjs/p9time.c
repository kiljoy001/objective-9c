#include <u.h>
#include <libc.h>

#include <time.h>
#include <sys/time.h>

/*
 * Native Plan 9 time adapter for the QuickJS engine.
 *
 * Plan 9 has nsec()/tmtime()/Tm, not gettimeofday()/struct tm.  QuickJS uses
 * gettimeofday for Date.now() and for Math.random seeding, and localtime_r
 * plus tm_gmtoff for getTimezoneOffset().  The engine's generated9 PLAN9
 * branch was changed by vendor.rc to use localtime_r, so there is no need
 * for a struct-tm gmtime()/mktime() that would collide with libc's Tm API.
 */

static Tzone *localtz;

static Tzone *
getlocaltz(void)
{
	if(localtz == nil)
		localtz = tzload("local");
	return localtz; /* nil means GMT */
}

static struct tm *
filltm(struct tm *out, vlong sec, Tzone *tz)
{
	Tm tm;

	if(out == nil)
		return nil;
	if(tmtimens(&tm, sec, 0, tz) == nil)
		return nil;
	out->tm_sec = tm.sec;
	out->tm_min = tm.min;
	out->tm_hour = tm.hour;
	out->tm_mday = tm.mday;
	out->tm_mon = tm.mon;
	out->tm_year = tm.year - 1900;
	out->tm_wday = tm.wday;
	out->tm_yday = tm.yday;
	out->tm_isdst = 0;
	out->tm_gmtoff = tm.tzoff;
	strncpy(out->tm_zone, tm.zone, sizeof out->tm_zone - 1);
	out->tm_zone[sizeof out->tm_zone - 1] = 0;
	return out;
}

struct tm *
localtime_r(const time_t *t, struct tm *out)
{
	if(t == nil)
		return nil;
	return filltm(out, (vlong)*t, getlocaltz());
}

struct tm *
gmtime_r(const time_t *t, struct tm *out)
{
	if(t == nil)
		return nil;
	return filltm(out, (vlong)*t, nil);
}

int
gettimeofday(struct timeval *tv, void *tz)
{
	vlong ns;
	long sec;

	(void)tz;
	if(tv == nil)
		return -1;
	ns = nsec();
	if(ns < 0){
		/* QuickJS does not check the return value when seeding
		 * Math.random, so always leave tv initialized. */
		sec = time(nil);
		if(sec < 0)
			sec = 0;
		tv->tv_sec = sec;
		tv->tv_usec = 0;
		return 0;
	}
	tv->tv_sec = ns / 1000000000LL;
	tv->tv_usec = (ns % 1000000000LL) / 1000;
	return 0;
}
