#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"
#include "o9test.h"

/*
 * Unit tests for the o9 runtime's file, journal, and path helpers —
 * the primitives the grid builds on:
 *
 *	o9_append_event		journal row formatting + atomic append
 *	o9_journal_split	journal row parsing
 *	o9_count_dir		queue/claim directory counting
 *	o9_has_suffix		suffix matching underneath count_dir
 *	o9_basename_c		path basename
 *	o9_strip_repo_prefix	repo-relative path rewriting
 *	o9_read_file_c		bounded whole-file read
 *	o9_kv_int		key\tvalue lookup
 *	o9_tsv_get_col(s)	tab row column extraction
 *	o9_hash			selector hashing
 *
 * These are exercised end-to-end by the grid campaigns, but only in
 * aggregate: a wrong answer shows up as a miscounted queue three layers
 * up. Testing them directly localizes the failure.
 *
 * Disk cases run under o9t_tmpdir() so a read-only /tmp (a shared
 * drawterm host) can redirect them with $TMP.
 */

/* ---- fixtures ---- */

/* Write `data` to `path`, replacing anything there. Returns 0 on success. */
static int
putfile(char *path, char *data)
{
	int fd, n, len;

	fd = create(path, OWRITE, 0644);
	if(fd < 0)
		return -1;
	len = strlen(data);
	n = write(fd, data, len);
	close(fd);
	return n == len ? 0 : -1;
}

/* Read a whole file into buf for assertions. Returns byte count, -1 on
 * error. Always NUL-terminates when it returns >= 0. */
static int
getfile(char *path, char *buf, int nbuf)
{
	int fd, n;

	fd = open(path, OREAD);
	if(fd < 0)
		return -1;
	n = read(fd, buf, nbuf - 1);
	close(fd);
	if(n < 0)
		return -1;
	buf[n] = '\0';
	return n;
}

/* ---- o9_basename_c ---- */

static void
test_basename(void)
{
	O9T_CASE("o9_basename_c");

	o9t_eqstr("plain name", o9_basename_c("file.c"), "file.c");
	o9t_eqstr("one directory", o9_basename_c("dir/file.c"), "file.c");
	o9t_eqstr("nested", o9_basename_c("a/b/c/file.c"), "file.c");
	o9t_eqstr("absolute", o9_basename_c("/sys/src/cmd/file.c"), "file.c");

	/* A nil path must not crash the caller; the contract is "". */
	o9t_eqstr("nil path", o9_basename_c(nil), "");
	o9t_eqstr("empty path", o9_basename_c(""), "");

	/* Trailing slash: there is no final component, so the basename is
	 * empty rather than the directory name. */
	o9t_eqstr("trailing slash", o9_basename_c("a/b/"), "");
	o9t_eqstr("root only", o9_basename_c("/"), "");

	/* Repeated separators collapse naturally: the last one wins. */
	o9t_eqstr("double slash", o9_basename_c("a//file.c"), "file.c");

	/* The mutant paths the grid actually passes in. */
	o9t_eqstr("mutant path",
		o9_basename_c("artifacts/o9um-grid-mutants/libtab_tab_codec.c/tab_codec.mutant.7.c"),
		"tab_codec.mutant.7.c");
}

/* ---- o9_has_suffix ---- */

static void
test_has_suffix(void)
{
	O9T_CASE("o9_has_suffix");

	o9t_eqint("matching suffix", o9_has_suffix("task.tab", ".tab"), 1);
	o9t_eqint("non-matching suffix", o9_has_suffix("task.log", ".tab"), 0);

	/* Whole-name match is still a match. */
	o9t_eqint("name equals suffix", o9_has_suffix(".tab", ".tab"), 1);

	/* A name shorter than the suffix cannot match, and must not read
	 * before the start of the string while deciding that. */
	o9t_eqint("name shorter than suffix", o9_has_suffix("ab", ".tab"), 0);
	o9t_eqint("empty name", o9_has_suffix("", ".tab"), 0);

	/* An empty suffix matches everything — count_dir relies on this
	 * only via its own explicit empty check, but the primitive should
	 * still be well-defined. */
	o9t_eqint("empty suffix", o9_has_suffix("task.tab", ""), 1);

	o9t_eqint("nil name", o9_has_suffix(nil, ".tab"), 0);
	o9t_eqint("nil suffix", o9_has_suffix("task.tab", nil), 0);
	o9t_eqint("both nil", o9_has_suffix(nil, nil), 0);

	/* The suffix must match at the end, not merely appear. */
	o9t_eqint("suffix in middle", o9_has_suffix("a.tab.bak", ".tab"), 0);
}

/* ---- o9_strip_repo_prefix ---- */

/* Run strip on a copy so the literal is not modified in place. */
static char*
stripped(char *buf, int nbuf, char *path, char *repo)
{
	snprint(buf, nbuf, "%s", path);
	o9_strip_repo_prefix(buf, repo);
	return buf;
}

static void
test_strip_repo_prefix(void)
{
	char buf[512];

	O9T_CASE("o9_strip_repo_prefix");

	/* Leading match: the repo prefix and its following slash go. */
	o9t_eqstr("leading prefix",
		stripped(buf, sizeof buf, "/usr/glenda/repo/src/a.c", "/usr/glenda/repo"),
		"src/a.c");

	/* Embedded match: the repo name appears mid-path (the drawterm
	 * mount case, where the same repo hangs off /mnt/term). */
	o9t_eqstr("embedded prefix",
		stripped(buf, sizeof buf, "/mnt/term/home/repo/src/a.c", "/home/repo"),
		"src/a.c");

	/* No match leaves the path untouched. */
	o9t_eqstr("absent prefix",
		stripped(buf, sizeof buf, "/other/src/a.c", "/home/repo"),
		"/other/src/a.c");

	/* An empty or nil repo is a no-op, not a truncation. */
	o9t_eqstr("empty repo",
		stripped(buf, sizeof buf, "/a/b.c", ""), "/a/b.c");
	o9t_eqstr("nil repo",
		stripped(buf, sizeof buf, "/a/b.c", nil), "/a/b.c");

	/* Exact match consumes the whole path. */
	o9t_eqstr("path equals repo",
		stripped(buf, sizeof buf, "/home/repo", "/home/repo"), "");

	/* Match with no following slash still strips cleanly. */
	o9t_eqstr("prefix without trailing slash",
		stripped(buf, sizeof buf, "/home/repofile", "/home/repo"), "file");

	/* A nil path must be tolerated. */
	o9_strip_repo_prefix(nil, "/home/repo");
	o9t_ok("nil path does not crash", 1);
}

/* ---- o9_hash ---- */

static void
test_hash(void)
{
	ulong a, b;

	O9T_CASE("o9_hash");

	/* djb2 over the selector name. The exact values matter because
	 * generated dispatch tables bake them in: a change to this
	 * function silently breaks every compiled binary. */
	a = o9_hash("run");
	b = o9_hash("run");
	o9t_eqint("stable across calls", a, b);

	o9t_ok("distinct selectors differ", o9_hash("run") != o9_hash("stop"));
	o9t_ok("empty string hashes", o9_hash("") == 5381);

	/* Result must stay inside 32 bits even on a 64-bit ulong, or the
	 * generated switch labels will not match at runtime. */
	o9t_eqint("masked to 32 bits",
		(vlong)(o9_hash("a_very_long_selector_name_for_masking") & ~0xFFFFFFFFul), 0);

	/* Order sensitivity: an additive-only hash would collide here. */
	o9t_ok("order sensitive", o9_hash("ab") != o9_hash("ba"));
}

/* ---- o9_journal_split ---- */

static void
test_journal_split(void)
{
	char line[512];
	char *fields[6];
	char *detail;
	int n;

	O9T_CASE("o9_journal_split");

	/* The canonical row o9_append_event writes: six fields plus an
	 * optional trailing detail that may itself contain tabs. */
	snprint(line, sizeof line, "7\t1700000000000\tctl\tchunk_requeue\tchunk\tc12\treason=stale_claim");
	n = o9_journal_split(line, fields, 6, &detail);
	o9t_eqint("field count", n, 6);
	o9t_eqstr("seq", fields[0], "7");
	o9t_eqstr("timestamp", fields[1], "1700000000000");
	o9t_eqstr("origin", fields[2], "ctl");
	o9t_eqstr("type", fields[3], "chunk_requeue");
	o9t_eqstr("entity kind", fields[4], "chunk");
	o9t_eqstr("entity id", fields[5], "c12");
	o9t_eqstr("detail", detail, "reason=stale_claim");

	/* Detail keeps its own tabs rather than being split further —
	 * that is what makes it safe to put key=value pairs in there. */
	snprint(line, sizeof line, "1\t2\to\tt\tk\ti\ta=1\tb=2");
	o9_journal_split(line, fields, 6, &detail);
	o9t_eqstr("detail retains tabs", detail, "a=1\tb=2");

	/* No detail column: detail is "" and not nil, so callers can
	 * strcmp it without a guard. */
	snprint(line, sizeof line, "1\t2\to\tt\tk\ti");
	n = o9_journal_split(line, fields, 6, &detail);
	o9t_eqint("field count without detail", n, 6);
	o9t_eqstr("detail empty when absent", detail, "");

	/* A short row must leave the unfilled fields as "" rather than
	 * stale pointers from a previous call — the loop below reuses the
	 * same array, which is exactly how the grid calls it. */
	snprint(line, sizeof line, "1\t2\to");
	n = o9_journal_split(line, fields, 6, &detail);
	o9t_eqint("short row count", n, 3);
	o9t_eqstr("short row field 0", fields[0], "1");
	o9t_eqstr("short row field 2", fields[2], "o");
	o9t_eqstr("unfilled field 3 reset", fields[3], "");
	o9t_eqstr("unfilled field 5 reset", fields[5], "");
	o9t_eqstr("short row detail", detail, "");

	/* Empty line: one empty field. */
	snprint(line, sizeof line, "%s", "");
	n = o9_journal_split(line, fields, 6, &detail);
	o9t_eqint("empty line count", n, 1);
	o9t_eqstr("empty line field 0", fields[0], "");

	/* Empty interior fields are preserved, not collapsed — an absent
	 * entity_kind must not shift entity_id into its place. */
	snprint(line, sizeof line, "1\t2\to\tt\t\tid");
	o9_journal_split(line, fields, 6, &detail);
	o9t_eqstr("empty interior field", fields[4], "");
	o9t_eqstr("field after empty stays put", fields[5], "id");

	/* Defensive arguments. */
	o9t_eqint("nil line", o9_journal_split(nil, fields, 6, &detail), 0);
	snprint(line, sizeof line, "1\t2");
	o9t_eqint("nil fields", o9_journal_split(line, nil, 6, &detail), 0);
	snprint(line, sizeof line, "1\t2");
	o9t_eqint("zero nfields", o9_journal_split(line, fields, 0, &detail), 0);

	/* A nil detail pointer is allowed: callers that only want the
	 * fixed columns pass nil. */
	snprint(line, sizeof line, "1\t2\to\tt\tk\ti\td");
	n = o9_journal_split(line, fields, 6, nil);
	o9t_eqint("nil detail out is tolerated", n, 6);
	o9t_eqstr("fields still parsed with nil detail", fields[5], "i");
}

/* ---- o9_append_event + journal round trip ---- */

static void
test_append_event(void)
{
	char path[256], buf[4096];
	char *fields[6], *detail;
	char *nl;
	int n;

	O9T_CASE("o9_append_event");

	o9t_tmppath(path, sizeof path, "o9jrn");
	remove(path);

	/* First emit creates the file even though it does not exist. */
	o9_append_event(path, "ctl", "campaign_start", "campaign", "c1", nil);
	n = getfile(path, buf, sizeof buf);
	if(!o9t_ok("file created on first emit", n > 0)){
		remove(path);
		return;
	}

	/* Row must be newline-terminated so the next append starts a row. */
	o9t_ok("row ends with newline", n > 0 && buf[n-1] == '\n');

	/* Parse it back: the writer and the reader must agree. This is the
	 * round-trip that the replay tool depends on. */
	nl = strchr(buf, '\n');
	if(o9t_notnil("row has a newline", nl)){
		*nl = '\0';
		o9_journal_split(buf, fields, 6, &detail);
		o9t_eqstr("origin round-trips", fields[2], "ctl");
		o9t_eqstr("type round-trips", fields[3], "campaign_start");
		o9t_eqstr("entity kind round-trips", fields[4], "campaign");
		o9t_eqstr("entity id round-trips", fields[5], "c1");
		/* nil detail must yield no detail column, not the string "nil" */
		o9t_eqstr("nil detail writes empty", detail, "");
		o9t_ok("seq is numeric", fields[0][0] >= '0' && fields[0][0] <= '9');
		o9t_ok("timestamp is numeric", fields[1][0] >= '0' && fields[1][0] <= '9');
	}

	/* Appending must not truncate what is already there. This is the
	 * property the OAPPEND/seek fallback exists to preserve on file
	 * servers that do not honour OAPPEND. */
	o9_append_event(path, "worker", "task_done", "task", "t1", "status=killed");
	n = getfile(path, buf, sizeof buf);
	o9t_ok("second event appended", n > 0);
	o9t_ok("first event survives append", strstr(buf, "campaign_start") != nil);
	o9t_ok("second event present", strstr(buf, "task_done") != nil);
	o9t_ok("detail written", strstr(buf, "status=killed") != nil);

	/* Sequence numbers are per-process monotonic, so the second row's
	 * seq must exceed the first's. Replay ordering depends on it. */
	{
		char first[64], second[64];
		char *p, *q;
		int s1, s2;

		p = buf;
		q = strchr(p, '\t');
		if(o9t_notnil("first row has a tab", q)){
			snprint(first, sizeof first, "%.*s", (int)(q - p), p);
			s1 = atoi(first);
			p = strchr(p, '\n');
			if(o9t_notnil("first row terminated", p)){
				p++;
				q = strchr(p, '\t');
				if(o9t_notnil("second row has a tab", q)){
					snprint(second, sizeof second, "%.*s", (int)(q - p), p);
					s2 = atoi(second);
					o9t_ok("sequence advances", s2 > s1);
				}
			}
		}
	}

	/* Exactly two rows: no duplicate writes, no partial lines. */
	{
		int i, rows;

		rows = 0;
		for(i = 0; buf[i] != '\0'; i++)
			if(buf[i] == '\n')
				rows++;
		o9t_eqint("two rows on disk", rows, 2);
	}

	remove(path);

	O9T_CASE("o9_append_event guards");

	/* Guard arguments must be rejected quietly rather than writing a
	 * malformed row or crashing a worker. */
	o9_append_event(nil, "ctl", "t", "k", "i", nil);
	o9t_ok("nil path tolerated", 1);
	o9_append_event("", "ctl", "t", "k", "i", nil);
	o9t_ok("empty path tolerated", 1);

	o9t_tmppath(path, sizeof path, "o9jgd");
	remove(path);
	o9_append_event(path, nil, "t", "k", "i", nil);
	o9t_eqint("nil origin writes nothing", getfile(path, buf, sizeof buf), -1);
	o9_append_event(path, "ctl", nil, "k", "i", nil);
	o9t_eqint("nil type writes nothing", getfile(path, buf, sizeof buf), -1);

	/* nil entity fields are legal and become empty columns. */
	o9_append_event(path, "ctl", "t", nil, nil, nil);
	n = getfile(path, buf, sizeof buf);
	if(o9t_ok("nil entity fields still write a row", n > 0)){
		nl = strchr(buf, '\n');
		if(nl != nil)
			*nl = '\0';
		o9_journal_split(buf, fields, 6, &detail);
		o9t_eqstr("nil entity kind becomes empty", fields[4], "");
		o9t_eqstr("nil entity id becomes empty", fields[5], "");
	}
	remove(path);
}

/* ---- o9_count_dir ---- */

static void
test_count_dir(void)
{
	char dir[256], path[512];
	int fd;

	O9T_CASE("o9_count_dir");

	o9t_tmppath(dir, sizeof dir, "o9cnt");
	/* Start clean in case a previous run died mid-test. */
	snprint(path, sizeof path, "%s/a.tab", dir); remove(path);
	snprint(path, sizeof path, "%s/b.tab", dir); remove(path);
	snprint(path, sizeof path, "%s/c.log", dir); remove(path);
	snprint(path, sizeof path, "%s/sub1", dir); remove(path);
	snprint(path, sizeof path, "%s/sub2", dir); remove(path);
	remove(dir);

	fd = create(dir, OREAD, DMDIR|0755);
	if(fd < 0){
		o9t_skip("count_dir", "cannot create temp directory");
		return;
	}
	close(fd);

	/* Empty directory counts zero, not an error. */
	o9t_eqint("empty dir, files", o9_count_dir(dir, 0, nil), 0);
	o9t_eqint("empty dir, dirs", o9_count_dir(dir, 1, nil), 0);

	/* Two .tab files, one .log file, two subdirectories — the exact
	 * shape of a queue directory, where pending tasks are *.tab files
	 * and claims are directories. */
	snprint(path, sizeof path, "%s/a.tab", dir); putfile(path, "x");
	snprint(path, sizeof path, "%s/b.tab", dir); putfile(path, "y");
	snprint(path, sizeof path, "%s/c.log", dir); putfile(path, "z");
	snprint(path, sizeof path, "%s/sub1", dir);
	fd = create(path, OREAD, DMDIR|0755); if(fd >= 0) close(fd);
	snprint(path, sizeof path, "%s/sub2", dir);
	fd = create(path, OREAD, DMDIR|0755); if(fd >= 0) close(fd);

	o9t_eqint("all files", o9_count_dir(dir, 0, nil), 3);
	o9t_eqint("all directories", o9_count_dir(dir, 1, nil), 2);

	/* Suffix filter applies to files. This is the pending-task count. */
	o9t_eqint("files with .tab", o9_count_dir(dir, 0, ".tab"), 2);
	o9t_eqint("files with .log", o9_count_dir(dir, 0, ".log"), 1);
	o9t_eqint("files with unmatched suffix", o9_count_dir(dir, 0, ".none"), 0);

	/* An empty suffix must behave as "no filter", not "match nothing". */
	o9t_eqint("empty suffix means no filter", o9_count_dir(dir, 0, ""), 3);

	/* Directories and files are strictly partitioned: a .tab-suffixed
	 * subdirectory must not be counted as a pending file. */
	snprint(path, sizeof path, "%s/dir.tab", dir);
	fd = create(path, OREAD, DMDIR|0755);
	if(fd >= 0){
		close(fd);
		o9t_eqint("suffixed dir not counted as file",
			o9_count_dir(dir, 0, ".tab"), 2);
		o9t_eqint("suffixed dir counted as dir",
			o9_count_dir(dir, 1, nil), 3);
		remove(path);
	}

	/* A missing directory counts zero rather than failing — the grid
	 * calls this on queues that may not exist yet. */
	snprint(path, sizeof path, "%s/nonexistent", dir);
	o9t_eqint("missing dir counts zero", o9_count_dir(path, 0, nil), 0);
	o9t_eqint("nil path counts zero", o9_count_dir(nil, 0, nil), 0);

	/* Cleanup. */
	snprint(path, sizeof path, "%s/a.tab", dir); remove(path);
	snprint(path, sizeof path, "%s/b.tab", dir); remove(path);
	snprint(path, sizeof path, "%s/c.log", dir); remove(path);
	snprint(path, sizeof path, "%s/sub1", dir); remove(path);
	snprint(path, sizeof path, "%s/sub2", dir); remove(path);
	remove(dir);
}

/* ---- o9_read_file_c ---- */

static void
test_read_file(void)
{
	char path[256];
	char *buf;
	vlong len;

	O9T_CASE("o9_read_file_c");

	o9t_tmppath(path, sizeof path, "o9rd");
	remove(path);

	if(putfile(path, "hello\nworld\n") < 0){
		o9t_skip("read_file", "cannot write temp file");
		return;
	}

	len = -1;
	buf = o9_read_file_c(path, &len, 0);
	if(o9t_notnil("read returns a buffer", buf)){
		o9t_eqstr("contents", buf, "hello\nworld\n");
		o9t_eqint("length reported", len, 12);
		free(buf);
	}

	/* A nil outlen is allowed. */
	buf = o9_read_file_c(path, nil, 0);
	if(o9t_notnil("read with nil outlen", buf)){
		o9t_eqstr("contents with nil outlen", buf, "hello\nworld\n");
		free(buf);
	}

	/* The max argument truncates rather than failing, and the result
	 * stays NUL-terminated at the truncation point. */
	len = -1;
	buf = o9_read_file_c(path, &len, 5);
	if(o9t_notnil("truncated read", buf)){
		o9t_eqstr("truncated contents", buf, "hello");
		o9t_eqint("truncated length", len, 5);
		free(buf);
	}

	/* Missing file yields nil and a zeroed length, not a stale value. */
	len = 999;
	buf = o9_read_file_c("/nonexistent/o9/path", &len, 0);
	o9t_nil("missing file returns nil", buf);
	o9t_eqint("missing file zeroes length", len, 0);

	o9t_nil("nil path returns nil", o9_read_file_c(nil, nil, 0));
	o9t_nil("empty path returns nil", o9_read_file_c("", nil, 0));

	/* An empty file is a valid read of zero bytes, distinct from a
	 * missing file — a caller must be able to tell them apart. */
	remove(path);
	putfile(path, "");
	len = -1;
	buf = o9_read_file_c(path, &len, 0);
	if(o9t_notnil("empty file returns a buffer", buf)){
		o9t_eqint("empty file length", len, 0);
		o9t_eqstr("empty file contents", buf, "");
		free(buf);
	}

	remove(path);
}

/* ---- o9_kv_int ---- */

static void
test_kv_int(void)
{
	char path[256];

	O9T_CASE("o9_kv_int");

	o9t_tmppath(path, sizeof path, "o9kv");
	remove(path);

	if(putfile(path, "workers\t9\nchunks\t42\nzero\t0\nnegative\t-3\n") < 0){
		o9t_skip("kv_int", "cannot write temp file");
		return;
	}

	o9t_eqint("first key", o9_kv_int(path, "workers", -1), 9);
	o9t_eqint("middle key", o9_kv_int(path, "chunks", -1), 42);
	o9t_eqint("zero value is not confused with default",
		o9_kv_int(path, "zero", -1), 0);
	o9t_eqint("negative value", o9_kv_int(path, "negative", 0), -3);

	/* An absent key returns the caller's default, which is how the
	 * grid distinguishes "not configured" from "configured to 0". */
	o9t_eqint("absent key returns default", o9_kv_int(path, "absent", 7), 7);
	o9t_eqint("missing file returns default",
		o9_kv_int("/nonexistent/o9/kv", "workers", 5), 5);
	o9t_eqint("nil path returns default", o9_kv_int(nil, "workers", 5), 5);
	o9t_eqint("nil key returns default", o9_kv_int(path, nil, 5), 5);

	/* A key that is a prefix of another must not match it. */
	o9t_eqint("prefix key does not match", o9_kv_int(path, "work", -1), -1);

	remove(path);

	/* A line with no tab is skipped rather than misparsed. */
	putfile(path, "garbage\nworkers\t3\n");
	o9t_eqint("tabless line skipped", o9_kv_int(path, "workers", -1), 3);

	remove(path);
}

/* ---- o9_tsv_get_col / o9_tsv_get_cols ---- */

static void
test_tsv_get_col(void)
{
	char path[256], out[128];
	const char *names[3];
	char *outs[3];
	char a[64], b[64], c[64];
	int sizes[3], n;

	O9T_CASE("o9_tsv_get_col");

	o9t_tmppath(path, sizeof path, "o9tsv");
	remove(path);

	if(putfile(path, "source\tmutant\tstatus\nlibtab.c\tm7.c\tkilled\n") < 0){
		o9t_skip("tsv_get_col", "cannot write temp file");
		return;
	}

	out[0] = '\0';
	o9t_eqint("single column found", o9_tsv_get_col(path, "source", out, sizeof out), 1);
	o9t_eqstr("single column value", out, "libtab.c");

	out[0] = '\0';
	o9t_eqint("last column found", o9_tsv_get_col(path, "status", out, sizeof out), 1);
	o9t_eqstr("last column value", out, "killed");

	/* An absent column reports not-found and clears the output, so a
	 * caller never reads a stale value from a previous lookup. */
	snprint(out, sizeof out, "stale");
	o9t_eqint("absent column not found", o9_tsv_get_col(path, "absent", out, sizeof out), 0);
	o9t_eqstr("absent column clears output", out, "");

	/* Several columns in one pass — the form the triage path uses. */
	O9T_CASE("o9_tsv_get_cols");
	names[0] = "status"; outs[0] = a; sizes[0] = sizeof a;
	names[1] = "source"; outs[1] = b; sizes[1] = sizeof b;
	names[2] = "absent"; outs[2] = c; sizes[2] = sizeof c;
	n = o9_tsv_get_cols(path, names, outs, sizes, 3);
	o9t_eqint("two of three columns found", n, 2);
	o9t_eqstr("out of order column", a, "killed");
	o9t_eqstr("second column", b, "libtab.c");
	o9t_eqstr("absent column empty", c, "");

	/* Guards. */
	o9t_eqint("nil path", o9_tsv_get_col(nil, "source", out, sizeof out), 0);
	o9t_eqint("nil name", o9_tsv_get_col(path, nil, out, sizeof out), 0);
	o9t_eqint("zero outsz", o9_tsv_get_col(path, "source", out, 0), 0);
	o9t_eqint("missing file",
		o9_tsv_get_col("/nonexistent/o9/tsv", "source", out, sizeof out), 0);

	remove(path);

	/* Header with no data row. Current behavior, pinned deliberately:
	 * the empty text after the header newline splits into one empty
	 * field, so column 0 is "found" with an empty value.
	 *
	 * That makes a header-only file indistinguishable from a real row
	 * whose cell is empty — both give found=1, value="" (asserted
	 * below). Callers that must tell them apart cannot use the return
	 * value to do it. Recorded as-is rather than changed here, because
	 * tightening it is a runtime behavior decision, not a test fix; if
	 * it is tightened, this expectation is the thing to update. */
	putfile(path, "source\tmutant\n");
	out[0] = '\0';
	o9t_eqint("header only reports found", o9_tsv_get_col(path, "source", out, sizeof out), 1);
	o9t_eqstr("header only yields empty value", out, "");

	/* The ambiguity, stated as a test so it cannot regress unnoticed. */
	remove(path);
	putfile(path, "source\tmutant\nlibtab.c\t\n");
	out[0] = '\0';
	o9t_eqint("empty cell reports found", o9_tsv_get_col(path, "mutant", out, sizeof out), 1);
	o9t_eqstr("empty cell yields empty value", out, "");

	/* A column past the end of a short row is NOT reported found —
	 * this is the bound that does still discriminate. */
	remove(path);
	putfile(path, "source\tmutant\tstatus\nlibtab.c\n");
	out[0] = '\0';
	o9t_eqint("column beyond short row not found",
		o9_tsv_get_col(path, "status", out, sizeof out), 0);

	remove(path);

	/* CRLF line endings: the row terminator must not end up inside the
	 * last column's value. Files can arrive from a host editor. */
	putfile(path, "source\tstatus\r\nlibtab.c\tkilled\r\n");
	out[0] = '\0';
	o9_tsv_get_col(path, "status", out, sizeof out);
	o9t_eqstr("CRLF does not leak into value", out, "killed");

	remove(path);
}

void
threadmain(int, char**)
{
	o9t_begin("runtime_helpers_test");

	test_basename();
	test_has_suffix();
	test_strip_repo_prefix();
	test_hash();
	test_journal_split();
	test_append_event();
	test_count_dir();
	test_read_file();
	test_kv_int();
	test_tsv_get_col();

	threadexitsall(o9t_report());
}
