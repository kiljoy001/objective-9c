#include <u.h>
#include <libc.h>
#include "o9test.h"

/*
 * Self-test for the o9test harness.
 *
 * A test library that miscounts, or that reports a pass for a failing
 * check, silently invalidates every suite built on it. So this exercises
 * both arms of each check: the passing arm through the normal counters,
 * and the FAILING arm — which must be verified without failing this
 * binary. The trick is o9t_begin(), which resets the counters: we
 * deliberately fail checks inside a scratch run, read the counts, then
 * begin a fresh run so those intentional failures do not leak into the
 * real result.
 *
 * Failure output from the scratch runs goes to stderr and is expected;
 * the mkfile target redirects it, and the final summary is what counts.
 */

/* Run one deliberately-failing check in a scratch run and confirm the
 * harness counted exactly one failure and no pass. Returns 1 on success.
 * Because this itself calls o9t_begin, it must not run inside a real
 * run whose counters matter. */
static int
scratch_expect_fail(void)
{
	return o9t_failed() == 1 && o9t_passed() == 0;
}

static int
scratch_expect_pass(void)
{
	return o9t_passed() == 1 && o9t_failed() == 0;
}

/* Results of the scratch phase, collected before the real run starts. */
typedef struct Probe Probe;
struct Probe {
	char *what;
	int passarm;	/* the check returned 1 and counted a pass */
	int failarm;	/* the check returned 0 and counted a failure */
};

static Probe probes[32];
static int nprobe;

static void
probe(char *what, int passarm, int failarm)
{
	if(nprobe < nelem(probes)){
		probes[nprobe].what = what;
		probes[nprobe].passarm = passarm;
		probes[nprobe].failarm = failarm;
		nprobe++;
	}
}

/* Exercise both arms of every check, recording what the harness did.
 * Each arm gets its own scratch run so the counters are unambiguous. */
static void
run_probes(void)
{
	int r;
	char a[4], b[4];

	/* o9t_ok */
	o9t_begin("scratch");
	r = o9t_ok("true", 1);
	probe("o9t_ok", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_ok("false", 0);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* o9t_eqint */
	o9t_begin("scratch");
	r = o9t_eqint("same", 42, 42);
	probe("o9t_eqint", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_eqint("differ", 42, 43);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* o9t_eqint must handle the full vlong range, not just int */
	o9t_begin("scratch");
	r = o9t_eqint("big", 0x7FFFFFFFFFLL, 0x7FFFFFFFFFLL);
	probe("o9t_eqint vlong", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_eqint("big differ", 0x7FFFFFFFFFLL, 0x7FFFFFFFFELL);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* o9t_eqstr */
	o9t_begin("scratch");
	r = o9t_eqstr("same", "abc", "abc");
	probe("o9t_eqstr", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_eqstr("differ", "abc", "abd");
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* nil handling: nil==nil passes, nil vs "" must NOT pass — these
	 * are different values and conflating them hides real bugs. */
	o9t_begin("scratch");
	r = o9t_eqstr("nil both", nil, nil);
	probe("o9t_eqstr nil==nil", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_eqstr("nil vs empty", nil, "");
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* the reverse order must fail too: neither argument may be
	 * silently coerced toward the other */
	o9t_begin("scratch");
	r = o9t_eqstr("empty vs nil", "", nil);
	probe("o9t_eqstr empty!=nil", 1, r == 0 && scratch_expect_fail());

	/* o9t_eqmem */
	memcpy(a, "abc", 4);
	memcpy(b, "abc", 4);
	o9t_begin("scratch");
	r = o9t_eqmem("same", a, b, 4);
	probe("o9t_eqmem", r == 1 && scratch_expect_pass(), 0);
	b[2] = 'z';
	o9t_begin("scratch");
	r = o9t_eqmem("differ", a, b, 4);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* o9t_nil / o9t_notnil */
	o9t_begin("scratch");
	r = o9t_nil("is nil", nil);
	probe("o9t_nil", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_nil("not nil", a);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	o9t_begin("scratch");
	r = o9t_notnil("not nil", a);
	probe("o9t_notnil", r == 1 && scratch_expect_pass(), 0);
	o9t_begin("scratch");
	r = o9t_notnil("is nil", nil);
	probes[nprobe - 1].failarm = (r == 0 && scratch_expect_fail());

	/* o9t_fail always records and always returns 0 */
	o9t_begin("scratch");
	r = o9t_fail("explicit", "reason %d", 7);
	probe("o9t_fail", 1, r == 0 && scratch_expect_fail());

	/* skips are counted separately and do not fail the run */
	o9t_begin("scratch");
	o9t_skip("absent", "no fixture");
	probe("o9t_skip", o9t_skipped() == 1 && o9t_failed() == 0, 1);

	/* a run with only passes and skips must report success (nil) */
	o9t_begin("scratch");
	o9t_ok("fine", 1);
	o9t_skip("later", "not yet");
	probe("report nil when no failures", o9t_report() == nil, 1);

	/* a run with any failure must report non-nil, so exits() is non-zero */
	o9t_begin("scratch");
	o9t_ok("bad", 0);
	probe("report non-nil on failure", o9t_report() != nil, 1);

	/* counters must accumulate across many checks, not just the last */
	o9t_begin("scratch");
	o9t_ok("a", 1);
	o9t_ok("b", 1);
	o9t_ok("c", 0);
	o9t_ok("d", 1);
	probe("counters accumulate",
		o9t_passed() == 3 && o9t_failed() == 1, 1);

	/* o9t_begin must clear counters from the previous run */
	o9t_begin("scratch");
	probe("begin resets counters",
		o9t_passed() == 0 && o9t_failed() == 0 && o9t_skipped() == 0, 1);

	/* recording more failures than the detail buffer holds must keep
	 * counting rather than overflowing the fixed array */
	o9t_begin("scratch");
	{
		int i;
		for(i = 0; i < O9Tmaxfail + 10; i++)
			o9t_ok("flood", 0);
	}
	probe("failure count survives overflow",
		o9t_failed() == O9Tmaxfail + 10, 1);
}

static void
check_probes(void)
{
	int i;

	O9T_CASE("checks report both arms");
	for(i = 0; i < nprobe; i++){
		o9t_ok(probes[i].what, probes[i].passarm);
		o9t_ok(probes[i].what, probes[i].failarm);
	}
	o9t_eqint("all probes ran", nprobe, 16);
}

static void
check_tmp_helpers(void)
{
	char buf[256], other[256];
	char *td;

	O9T_CASE("tmp helpers");
	td = o9t_tmpdir();
	if(o9t_notnil("tmpdir not nil", td))
		o9t_ok("tmpdir not empty", td[0] != '\0');

	o9t_eqstr("tmppath returns buf", o9t_tmppath(buf, sizeof buf, "self"), buf);
	o9t_ok("tmppath under tmpdir", strncmp(buf, td, strlen(td)) == 0);
	o9t_ok("tmppath contains stem", strstr(buf, "self") != nil);

	/* the pid suffix is what keeps concurrent runs from colliding */
	o9t_tmppath(other, sizeof other, "self");
	o9t_eqstr("tmppath is stable within a process", buf, other);

	o9t_tmppath(other, sizeof other, "different");
	o9t_ok("distinct stems give distinct paths", strcmp(buf, other) != 0);
}

static void
check_case_labels(void)
{
	/* Labels are cosmetic but they are how a failure is located, so at
	 * least prove setting one does not disturb the counters. */
	int before;

	O9T_CASE("case labels");
	before = o9t_passed();
	O9T_CASE("relabelled");
	o9t_eqint("relabelling does not count as a check", o9t_passed(), before);
	O9T_CASE("case labels");
	o9t_ok("checks still register after relabelling", 1);
}

void
main(int, char**)
{
	/* Phase 1: probe both arms of every check in throwaway runs. */
	run_probes();

	/* Phase 2: the real run, asserting on what phase 1 observed. */
	o9t_begin("o9test_selftest");
	check_probes();
	check_tmp_helpers();
	check_case_labels();
	exits(o9t_report());
}
