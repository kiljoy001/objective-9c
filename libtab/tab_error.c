/*
 * libtab error reporting.  Single thread-local buffer; tab_lasterror()
 * returns its current contents.
 */

#include "tab_internal.h"
#ifdef __GNUC__
#include <stdarg.h>
#endif

static char tab_errbuf[256] = "no error";

void
tab_clearerror(void)
{
	tab_errbuf[0] = '\0';
}

void
tab_seterror(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsnprint(tab_errbuf, sizeof tab_errbuf, (char *)fmt, ap);
	va_end(ap);
}

const char *
tab_lasterror(void)
{
	if(tab_errbuf[0] == '\0')
		return "no error";
	return tab_errbuf;
}
