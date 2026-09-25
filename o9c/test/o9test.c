#include <u.h>
#include <libc.h>
#include "o9test.h"

/*
 * o9test — see o9test.h for the contract.
 *
 * All state is static and fixed-size. The harness must not be able to
 * fail in ways that look like the code under test failing, so there is no
 * malloc here and no unbounded growth: past O9Tmaxfail recorded failures
 * the run keeps counting but stops storing detail.
 */

static char o9t_suite[O9Tcasemax] = "test";
static char o9t_curcase[O9Tcasemax] = "";
static char o9t_fails[O9Tmaxfail][O9Tmsgmax];
static char o9t_skips[O9Tmaxfail][O9Tmsgmax];
static int o9t_npass;
static int o9t_nfail;
static int o9t_nskip;

void
o9t_begin(char *suite)
{
	if(suite != nil && suite[0] != '\0')
		snprint(o9t_suite, sizeof o9t_suite, "%s", suite);
	o9t_curcase[0] = '\0';
	o9t_npass = 0;
	o9t_nfail = 0;
	o9t_nskip = 0;
}

void
o9t_case(char *name)
{
	snprint(o9t_curcase, sizeof o9t_curcase, "%s",
		name != nil ? name : "");
}

/* Qualified label for a check: "case: what", or just one of them when
 * the other is absent. Written into caller-supplied storage. */
static char*
o9t_label(char *buf, int nbuf, char *what)
{
	if(what == nil)
		what = "";
	if(o9t_curcase[0] != '\0' && what[0] != '\0')
		snprint(buf, nbuf, "%s: %s", o9t_curcase, what);
	else if(o9t_curcase[0] != '\0')
		snprint(buf, nbuf, "%s", o9t_curcase);
	else
		snprint(buf, nbuf, "%s", what);
	return buf;
}

/* Record one failure. Detail past O9Tmaxfail is dropped but still
 * counted, so the summary total stays honest. */
static void
o9t_record(char *msg)
{
	if(o9t_nfail < O9Tmaxfail)
		snprint(o9t_fails[o9t_nfail], O9Tmsgmax, "%s", msg);
	o9t_nfail++;
	fprint(2, "FAIL %s/%s\n", o9t_suite, msg);
}

static int
o9t_pass(void)
{
	o9t_npass++;
	return 1;
}

int
o9t_ok(char *what, int cond)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	if(cond)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: condition is false", label);
	o9t_record(msg);
	return 0;
}

int
o9t_eqint(char *what, vlong got, vlong want)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	if(got == want)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: got %lld want %lld", label, got, want);
	o9t_record(msg);
	return 0;
}

int
o9t_eqstr(char *what, const char *got, const char *want)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	/* nil is a distinct value from "", and conflating them has hidden
	 * real bugs in these helpers before, so compare it explicitly. */
	if(got == nil && want == nil)
		return o9t_pass();
	if(got != nil && want != nil && strcmp(got, want) == 0)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: got %s%s%s want %s%s%s", label,
		got != nil ? "\"" : "", got != nil ? got : "<nil>",
		got != nil ? "\"" : "",
		want != nil ? "\"" : "", want != nil ? want : "<nil>",
		want != nil ? "\"" : "");
	o9t_record(msg);
	return 0;
}

int
o9t_eqmem(char *what, void *got, void *want, long n)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];
	uchar *a, *b;
	long i;

	if(got != nil && want != nil && memcmp(got, want, n) == 0)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	if(got == nil || want == nil){
		snprint(msg, sizeof msg, "%s: got %s want %s", label,
			got != nil ? "buffer" : "<nil>",
			want != nil ? "buffer" : "<nil>");
		o9t_record(msg);
		return 0;
	}
	/* Point at the first differing byte; "buffers differ" alone sends
	 * you back to a debugger for something the harness already knows. */
	a = got;
	b = want;
	for(i = 0; i < n; i++)
		if(a[i] != b[i])
			break;
	snprint(msg, sizeof msg,
		"%s: first difference at byte %ld: got 0x%02ux want 0x%02ux",
		label, i, i < n ? a[i] : 0, i < n ? b[i] : 0);
	o9t_record(msg);
	return 0;
}

int
o9t_nil(char *what, void *p)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	if(p == nil)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: got %p want nil", label, p);
	o9t_record(msg);
	return 0;
}

int
o9t_notnil(char *what, void *p)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	if(p != nil)
		return o9t_pass();
	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: got nil", label);
	o9t_record(msg);
	return 0;
}

int
o9t_fail(char *what, char *fmt, ...)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax], detail[O9Tmsgmax];
	va_list arg;

	o9t_label(label, sizeof label, what);
	va_start(arg, fmt);
	vsnprint(detail, sizeof detail, fmt, arg);
	va_end(arg);
	snprint(msg, sizeof msg, "%s: %s", label, detail);
	o9t_record(msg);
	return 0;
}

void
o9t_skip(char *what, char *why)
{
	char label[O9Tmsgmax], msg[O9Tmsgmax];

	o9t_label(label, sizeof label, what);
	snprint(msg, sizeof msg, "%s: %s", label,
		why != nil && why[0] != '\0' ? why : "skipped");
	if(o9t_nskip < O9Tmaxfail)
		snprint(o9t_skips[o9t_nskip], O9Tmsgmax, "%s", msg);
	o9t_nskip++;
	fprint(2, "SKIP %s/%s\n", o9t_suite, msg);
}

int
o9t_passed(void)
{
	return o9t_npass;
}

int
o9t_failed(void)
{
	return o9t_nfail;
}

int
o9t_skipped(void)
{
	return o9t_nskip;
}

char*
o9t_report(void)
{
	static char status[64];
	int i, shown;

	if(o9t_nskip > 0){
		print("\n%s: %d skipped\n", o9t_suite, o9t_nskip);
		shown = o9t_nskip < O9Tmaxfail ? o9t_nskip : O9Tmaxfail;
		for(i = 0; i < shown; i++)
			print("  SKIP %s\n", o9t_skips[i]);
	}
	if(o9t_nfail == 0){
		print("%s: OK (%d checks, %d skipped)\n",
			o9t_suite, o9t_npass, o9t_nskip);
		return nil;
	}
	print("\n%s: FAILED %d of %d checks\n",
		o9t_suite, o9t_nfail, o9t_npass + o9t_nfail);
	shown = o9t_nfail < O9Tmaxfail ? o9t_nfail : O9Tmaxfail;
	for(i = 0; i < shown; i++)
		print("  %s\n", o9t_fails[i]);
	if(o9t_nfail > shown)
		print("  ... and %d more\n", o9t_nfail - shown);
	snprint(status, sizeof status, "%d failed", o9t_nfail);
	return status;
}

char*
o9t_tmpdir(void)
{
	char *td;

	td = getenv("TMP");
	if(td == nil || td[0] == '\0')
		return "/tmp";
	return td;
}

char*
o9t_tmppath(char *buf, int nbuf, char *stem)
{
	snprint(buf, nbuf, "%s/%s%d", o9t_tmpdir(),
		stem != nil ? stem : "o9t", getpid());
	return buf;
}
