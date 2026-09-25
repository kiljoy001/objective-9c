#ifndef _O9TEST_H_
#define _O9TEST_H_

/*
 * o9test — minimal native unit-test library for 9front C tests.
 *
 * The house style before this was sysfatal() on the first bad value: the
 * run stops at failure #1, so a change that breaks twenty things reports
 * one, and you learn the next failure only after fixing this one. This
 * library keeps going. A failing check records the case, the file, the
 * line, and the got/want pair, then execution continues to the next
 * check, so one run tells you everything that is broken.
 *
 * Shape:
 *
 *	#include <u.h>
 *	#include <libc.h>
 *	#include "o9test.h"
 *
 *	static void
 *	test_basename(void)
 *	{
 *		O9T_CASE("basename");
 *		o9t_eqstr("plain", o9_basename_c("a/b/c"), "c");
 *		o9t_eqint("empty", o9_basename_c("")[0], 0);
 *	}
 *
 *	void
 *	main(int, char**)
 *	{
 *		o9t_begin("mytest");
 *		test_basename();
 *		exits(o9t_report());
 *	}
 *
 * o9t_report() prints the summary, returns nil when everything passed and
 * a non-nil status string otherwise, so `exits(o9t_report())` gives mk the
 * non-zero exit it needs to fail the build.
 *
 * Threaded tests (anything linking libo9, which pulls in the thread
 * library) use threadmain and threadexitsall(o9t_report()) instead.
 *
 * The library is deliberately free of malloc and of any dependency beyond
 * <u.h>/<libc.h>: a test binary that crashes in its own harness tells you
 * nothing about the code under test.
 */

enum {
	O9Tmaxfail = 64,	/* failures recorded in full before summarizing */
	O9Tmsgmax = 256,	/* per-failure message buffer */
	O9Tcasemax = 128,	/* current-case label buffer */
};

/* Declare the current case. Every check reports under the most recent
 * label, so failures read as "suite/case: check". Call it once at the top
 * of each test function; it is a statement, not a declaration. */
#define O9T_CASE(name) o9t_case(name)

/* Checks. Each returns 1 on pass and 0 on fail so a caller can skip
 * follow-on work that would crash on the bad value:
 *
 *	if(o9t_notnil("parsed", p))
 *		o9t_eqstr("field", p->name, "x");
 *
 * `what` names the property being checked, not the value. */
int o9t_ok(char *what, int cond);			/* cond is true */
int o9t_eqint(char *what, vlong got, vlong want);	/* integers equal */
int o9t_eqstr(char *what, const char *got, const char *want);	/* strings equal; nil-safe */
int o9t_eqmem(char *what, void *got, void *want, long n);	/* n bytes equal */
int o9t_nil(char *what, void *p);			/* pointer is nil */
int o9t_notnil(char *what, void *p);			/* pointer is not nil */

/* Record a failure directly, for conditions the checks above do not
 * express. Always returns 0, so `return o9t_fail(...)` reads naturally. */
int o9t_fail(char *what, char *fmt, ...);

/* Note a check that was deliberately not run (missing fixture, a case
 * that only applies on some file servers). Skips do not fail the run but
 * are counted and listed, so a silently-disabled test stays visible. */
void o9t_skip(char *what, char *why);

void o9t_begin(char *suite);	/* start a run; names it in output */
void o9t_case(char *name);	/* set current case label (via O9T_CASE) */

/* Print the summary and return an exits() status: nil when every check
 * passed, otherwise a short non-nil string. Skips alone do not fail. */
char *o9t_report(void);

/* Counters, for a test that needs to assert on its own progress. */
int o9t_passed(void);
int o9t_failed(void);
int o9t_skipped(void);

/* Temp directory for tests that touch the disk, honouring $TMP so a
 * host whose /tmp is read-only (a shared drawterm server) still runs the
 * disk cases; falls back to /tmp. Never returns nil. */
char *o9t_tmpdir(void);

/* Build a unique scratch path under o9t_tmpdir(): "<tmp>/<stem><pid>".
 * Returns buf. Tests are responsible for removing what they create. */
char *o9t_tmppath(char *buf, int nbuf, char *stem);

#endif
