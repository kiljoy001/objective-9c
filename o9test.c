#include <u.h>
#include <libc.h>

enum {
	Maxpath = 1024,
	Maxtests = 2048,
	Maxlog = 16384,
	Defaulttimeout = 30,
	Defaultbuildtimeout = 180,
};

typedef struct Testfile Testfile;
struct Testfile {
	char path[Maxpath];
};

static Testfile tests[Maxtests];
static int ntests;
static char *pattern;
static char *builder;
static char *seedarg;
static char *trialsarg;
static int timeout = Defaulttimeout;
static int buildtimeout = Defaultbuildtimeout;
static int verbose;
static int quiet;
static int showoutput;
static int failfast;
static int listonly;
static int keep;
static int sanitize;
static char scratch[Maxpath];

static void
usage(void)
{
	fprint(2, "usage: o9test [-vqsx] [-k text] [-t seconds] [--seed n] [--trials n] [--sanitize] [--build-timeout seconds] [--builder path] [--list] [--keep] [path ...]\n");
	exits("usage");
}

static int
seconds(char *s)
{
	char *end;
	long n;

	if(s == nil || *s == 0)
		usage();
	n = strtol(s, &end, 10);
	if(*end != 0 || n < 1 || n > 3600)
		usage();
	return n;
}

static int
positive(char *s, int max)
{
	char *end;
	long n;

	if(s == nil || *s == 0)
		usage();
	n = strtol(s, &end, 10);
	if(*end != 0 || n < 1 || n > max)
		usage();
	return n;
}

static void
validseed(char *s)
{
	int i;

	if(s == nil || *s == 0 || strlen(s) > 18)
		usage();
	for(i = 0; s[i] != 0; i++)
		if(s[i] < '0' || s[i] > '9')
			usage();
}

static int
suffix(char *s, char *end)
{
	int ns, ne;

	ns = strlen(s);
	ne = strlen(end);
	return ns >= ne && strcmp(s + ns - ne, end) == 0;
}

static int
testname(char *name)
{
	return suffix(name, ".o9") &&
		(strncmp(name, "test_", 5) == 0 || suffix(name, "_test.o9"));
}

static int
skipdir(char *name)
{
	return name[0] == '.' || strcmp(name, "local") == 0 ||
		strcmp(name, "node_modules") == 0 || strcmp(name, "vendor") == 0 ||
		strcmp(name, "build") == 0 || strcmp(name, "dist") == 0;
}

static void
addtest(char *path)
{
	int i;

	if(pattern != nil && strstr(path, pattern) == nil)
		return;
	for(i = 0; i < ntests; i++)
		if(strcmp(tests[i].path, path) == 0)
			return;
	if(ntests >= Maxtests)
		sysfatal("too many test files (limit %d)", Maxtests);
	if(strlen(path) >= sizeof tests[0].path)
		sysfatal("test path too long: %s", path);
	snprint(tests[ntests++].path, Maxpath, "%s", path);
}

static void
discover(char *path, int explicit, int depth)
{
	Dir *st, *entries;
	char child[Maxpath];
	int fd, n, i;

	if(depth > 64)
		sysfatal("directory nesting limit: %s", path);
	st = dirstat(path);
	if(st == nil)
		sysfatal("cannot inspect %s: %r", path);
	if(!(st->qid.type & QTDIR)){
		if(!suffix(path, ".o9"))
			sysfatal("test source must end in .o9: %s", path);
		if(explicit || testname(st->name))
			addtest(path);
		free(st);
		return;
	}
	free(st);
	fd = open(path, OREAD);
	if(fd < 0)
		sysfatal("cannot read directory %s: %r", path);
	n = dirreadall(fd, &entries);
	close(fd);
	if(n < 0)
		sysfatal("cannot list directory %s: %r", path);
	for(i = 0; i < n; i++){
		if(entries[i].qid.type & QTDIR){
			if(skipdir(entries[i].name))
				continue;
		}else if(!testname(entries[i].name))
			continue;
		if(snprint(child, sizeof child, "%s/%s", path, entries[i].name) >= sizeof child)
			sysfatal("test path too long under %s", path);
		discover(child, 0, depth + 1);
	}
	free(entries);
}

static int
comparetest(void *a, void *b)
{
	return strcmp(((Testfile*)a)->path, ((Testfile*)b)->path);
}

static char*
defaultbuilder(void)
{
	char *home;
	static char path[Maxpath];

	home = getenv("home");
	if(home != nil){
		snprint(path, sizeof path, "%s/bin/rc/o9build", home);
		free(home);
		if(access(path, AEXEC) == 0)
			return path;
	}
	if(access("/rc/bin/o9build", AEXEC) == 0)
		return "/rc/bin/o9build";
	if(access("/bin/o9build", AEXEC) == 0)
		return "/bin/o9build";
	return nil;
}

static void
mkscratch(void)
{
	char *base;
	int fd, attempt;

	base = getenv("TMP");
	if(base == nil || *base == 0){
		free(base);
		base = strdup("/tmp");
	}
	for(attempt = 0; attempt < 100; attempt++){
		if(snprint(scratch, sizeof scratch, "%s/o9test-%d-%ld-%d",
			base, getpid(), time(0), attempt) >= sizeof scratch)
			sysfatal("temporary path too long");
		fd = create(scratch, OREAD|OEXCL, DMDIR|0700);
		if(fd >= 0){
			close(fd);
			free(base);
			return;
		}
	}
	free(base);
	sysfatal("cannot create private temporary directory: %r");
}

static int
runphase(char *program, char *arg1, char *arg2, char *logpath,
	int limit, int *timedout, char *status, int nstatus)
{
	Waitmsg *w;
	int fd, pid, watchdog, gotchild, gotwatch;

	*timedout = 0;
	status[0] = 0;
	fd = create(logpath, OWRITE|OTRUNC, 0600);
	if(fd < 0){
		snprint(status, nstatus, "cannot create log: %r");
		return -1;
	}
	pid = rfork(RFPROC|RFFDG|RFNOTEG|RFENVG);
	if(pid < 0){
		close(fd);
		snprint(status, nstatus, "cannot start process: %r");
		return -1;
	}
	if(pid == 0){
		dup(fd, 1);
		dup(fd, 2);
		if(fd > 2)
			close(fd);
		if(arg2 == nil){
			if(sanitize)
				putenv("O9_SANITIZE", "1");
			if(seedarg != nil)
				putenv("O9TEST_SEED", seedarg);
			if(trialsarg != nil)
				putenv("O9TEST_TRIALS", trialsarg);
		}
		if(arg2 != nil){
			execl(program, program, arg1, arg2, nil);
			execl("/bin/rc", "rc", program, arg1, arg2, nil);
		}else
			execl(program, program, nil);
		exits("exec");
	}
	close(fd);
	watchdog = rfork(RFPROC|RFFDG|RFNOTEG);
	if(watchdog == 0){
		sleep(limit * 1000);
		postnote(PNGROUP, pid, "kill");
		exits("timeout");
	}
	if(watchdog < 0){
		snprint(status, nstatus, "cannot start timeout watchdog: %r");
		postnote(PNGROUP, pid, "kill");
		while((w = wait()) != nil){
			if(w->pid == pid){
				free(w);
				break;
			}
			free(w);
		}
		return -1;
	}
	gotchild = 0;
	gotwatch = 0;
	while(!gotchild || !gotwatch){
		w = wait();
		if(w == nil)
			break;
		if(w->pid == pid){
			gotchild = 1;
			snprint(status, nstatus, "%s", w->msg != nil ? w->msg : "");
			if(!gotwatch)
				postnote(PNPROC, watchdog, "kill");
		}else if(w->pid == watchdog){
			gotwatch = 1;
			if(!gotchild)
				*timedout = 1;
		}
		free(w);
	}
	if(!gotchild){
		snprint(status, nstatus, "child did not report exit");
		return -1;
	}
	return *timedout ? -1 : status[0] == 0 ? 0 : -1;
}

static void
showlog(char *path)
{
	Dir *st;
	char buf[Maxlog + 1];
	vlong start;
	int fd, n;

	fd = open(path, OREAD);
	if(fd < 0)
		return;
	st = dirfstat(fd);
	start = st != nil && st->length > Maxlog ? st->length - Maxlog : 0;
	free(st);
	seek(fd, start, 0);
	n = read(fd, buf, Maxlog);
	close(fd);
	if(n > 0){
		buf[n] = 0;
		fprint(2, "%s%s\n", start > 0 ? "... output truncated ...\n" : "", buf);
	}
}

static void
cleanfiles(char *binary, char *logpath)
{
	char path[Maxpath];
	char *objtype;

	remove(binary);
	snprint(path, sizeof path, "%s.c", binary);
	remove(path);
	objtype = getenv("objtype");
	if(objtype == nil || strcmp(objtype, "amd64") == 0)
		snprint(path, sizeof path, "%s.6", binary);
	else if(strcmp(objtype, "386") == 0)
		snprint(path, sizeof path, "%s.8", binary);
	else if(strcmp(objtype, "arm") == 0)
		snprint(path, sizeof path, "%s.5", binary);
	else if(strcmp(objtype, "arm64") == 0)
		snprint(path, sizeof path, "%s.7", binary);
	else if(strcmp(objtype, "mips") == 0)
		snprint(path, sizeof path, "%s.v", binary);
	else if(strcmp(objtype, "power") == 0 || strcmp(objtype, "power64") == 0)
		snprint(path, sizeof path, "%s.q", binary);
	else if(strcmp(objtype, "sparc") == 0 || strcmp(objtype, "sparc64") == 0)
		snprint(path, sizeof path, "%s.k", binary);
	else
		path[0] = 0;
	if(path[0] != 0)
		remove(path);
	free(objtype);
	remove(logpath);
}

void
main(int argc, char **argv)
{
	char binary[Maxpath], logpath[Maxpath], status[256];
	char **paths;
	int i, npath, pass, fail, errors, timed, cut, rc, endopts;

	paths = mallocz(argc * sizeof *paths, 1);
	if(paths == nil)
		sysfatal("no memory for command line");
	npath = 0;
	endopts = 0;
	for(i = 1; i < argc; i++){
		if(strcmp(argv[i], "--") == 0){
			endopts = 1;
			continue;
		}
		if(!endopts && (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)){
			print("o9test discovers test_*.o9 and *_test.o9 below each path (default: tests if present, else .).\n");
			print("-k text filters paths; -v names every test; -q shows only the summary; -s shows captured output.\n");
			print("-x stops after the first failure; -t sets each test's run timeout (default 30s).\n");
			print("--build-timeout sets the build timeout (default 180s); --list prints discovered files.\n");
			print("--builder selects a build script; --keep retains scratch files.\n");
			print("--seed replays property input generation; --trials sets cases per property (default 100).\n");
			print("--sanitize enables native bounds and ARC diagnostics with live allocation reports.\n");
			exits(nil);
		}
		if(!endopts && strcmp(argv[i], "-v") == 0) verbose = 1;
		else if(!endopts && strcmp(argv[i], "-q") == 0) quiet = 1;
		else if(!endopts && strcmp(argv[i], "-s") == 0) showoutput = 1;
		else if(!endopts && strcmp(argv[i], "-x") == 0) failfast = 1;
		else if(!endopts && strcmp(argv[i], "--list") == 0) listonly = 1;
		else if(!endopts && strcmp(argv[i], "--keep") == 0) keep = 1;
		else if(!endopts && strcmp(argv[i], "--sanitize") == 0) sanitize = 1;
		else if(!endopts && strcmp(argv[i], "-k") == 0 && ++i < argc) pattern = argv[i];
		else if(!endopts && strcmp(argv[i], "-t") == 0 && ++i < argc) timeout = seconds(argv[i]);
		else if(!endopts && strcmp(argv[i], "--build-timeout") == 0 && ++i < argc) buildtimeout = seconds(argv[i]);
		else if(!endopts && strcmp(argv[i], "--builder") == 0 && ++i < argc) builder = argv[i];
		else if(!endopts && strcmp(argv[i], "--seed") == 0 && ++i < argc){
			validseed(argv[i]);
			seedarg = argv[i];
		}
		else if(!endopts && strcmp(argv[i], "--trials") == 0 && ++i < argc){
			positive(argv[i], 100000);
			trialsarg = argv[i];
		}
		else if(!endopts && argv[i][0] == '-') usage();
		else paths[npath++] = argv[i];
	}
	if(builder == nil && !listonly)
		builder = defaultbuilder();
	if(builder == nil && !listonly)
		sysfatal("o9build not found; install Objective-9C or use --builder path");
	for(i = 0; i < npath; i++)
		discover(paths[i], 1, 0);
	free(paths);
	if(npath == 0){
		Dir *testdir;
		testdir = dirstat("tests");
		if(testdir != nil && (testdir->qid.type & QTDIR))
			discover("tests", 1, 0);
		else
			discover(".", 1, 0);
		free(testdir);
	}
	qsort(tests, ntests, sizeof tests[0], comparetest);
	if(ntests == 0){
		fprint(2, "o9test: no tests found\n");
		exits("no tests");
	}
	if(listonly){
		for(i = 0; i < ntests; i++)
			print("%s\n", tests[i].path);
		exits(nil);
	}
	mkscratch();
	pass = fail = errors = timed = 0;
	for(i = 0; i < ntests; i++){
		if(snprint(binary, sizeof binary, "%s/test%04d", scratch, i) >= sizeof binary)
			sysfatal("scratch path too long");
		snprint(logpath, sizeof logpath, "%s/test%04d.log", scratch, i);
		rc = runphase(builder, tests[i].path, binary, logpath,
			buildtimeout, &cut, status, sizeof status);
		if(rc == 0 && access(binary, AEXEC) < 0){
			rc = -1;
			snprint(status, sizeof status, "builder produced no executable");
		}
		if(rc < 0){
			errors++;
			fprint(2, "BUILD ERROR %s%s%s%s\n", tests[i].path,
				cut ? " (timeout)" : "", status[0] ? ": " : "",
				status[0] ? status : "");
			showlog(logpath);
		}else{
			rc = runphase(binary, nil, nil, logpath,
				timeout, &cut, status, sizeof status);
			if(rc < 0){
				if(cut) timed++;
				else fail++;
				fprint(2, "%s %s%s%s\n", cut ? "TIMEOUT" : "FAIL",
					tests[i].path, cut ? "" : ": ",
					cut ? "" : status);
				showlog(logpath);
			}else{
				pass++;
				if(verbose) print("PASS %s\n", tests[i].path);
				else if(!quiet) print(".");
				if(showoutput || sanitize) showlog(logpath);
			}
		}
		if(!keep)
			cleanfiles(binary, logpath);
		if(failfast && (fail + errors + timed) > 0)
			break;
	}
	if(!quiet && !verbose)
		print("\n");
	print("%d passed, %d failed, %d build errors, %d timed out", pass, fail, errors, timed);
	if(failfast && i + 1 < ntests)
		print(" (%d not run)", ntests - i - 1);
	print("\n");
	if(keep)
		print("scratch: %s\n", scratch);
	else
		remove(scratch);
	if(fail + errors + timed)
		exits("tests failed");
	exits(nil);
}
