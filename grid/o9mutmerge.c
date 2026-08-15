#include <u.h>
#include <libc.h>
#include <bio.h>

enum {
	Nhash = 524288,
	Maxrow = 8192
};

typedef struct Entry Entry;
struct Entry {
	char *id;
	char *row;
	char *file;
	int seen;
	Entry *next;
};

static Entry *tab[Nhash];
static long manifest_total, deduped_total, missing_total, duplicate_total;
static long conflict_total, unexpected_total, malformed_total;
static long killed_total, survived_total, timeout_total, infra_total, setup_total, equivalent_total;

static ulong
hstr(char *s)
{
	ulong h;
	h = 5381;
	while(*s != 0)
		h = ((h << 5) + h) ^ (uchar)*s++;
	return h % Nhash;
}

static char*
xstrdup(char *s)
{
	char *p;
	p = strdup(s);
	if(p == nil)
		sysfatal("strdup: %r");
	return p;
}

static Entry*
lookup(char *id, int create)
{
	ulong h;
	Entry *e;

	h = hstr(id);
	for(e = tab[h]; e != nil; e = e->next)
		if(strcmp(e->id, id) == 0)
			return e;
	if(!create)
		return nil;
	e = mallocz(sizeof *e, 1);
	if(e == nil)
		sysfatal("malloc: %r");
	e->id = xstrdup(id);
	e->next = tab[h];
	tab[h] = e;
	manifest_total++;
	return e;
}

static char*
field(char *row, int n, char *buf, int nbuf)
{
	char *p, *e;
	int i, len;

	p = row;
	for(i = 1; i < n && p != nil; i++){
		p = strchr(p, '\t');
		if(p != nil)
			p++;
	}
	if(p == nil){
		buf[0] = 0;
		return buf;
	}
	e = strchr(p, '\t');
	if(e == nil)
		e = p + strlen(p);
	len = e - p;
	if(len >= nbuf)
		len = nbuf - 1;
	memmove(buf, p, len);
	buf[len] = 0;
	return buf;
}

static void
count_result(char *row)
{
	char r[64];

	field(row, 5, r, sizeof r);
	if(strcmp(r, "killed") == 0)
		killed_total++;
	else if(strcmp(r, "survived") == 0)
		survived_total++;
	else if(strcmp(r, "timeout") == 0)
		timeout_total++;
	else if(strcmp(r, "infra_fail") == 0)
		infra_total++;
	else if(strcmp(r, "setup_error") == 0)
		setup_total++;
	else if(strcmp(r, "equivalent") == 0)
		equivalent_total++;
}

static void
read_manifest(char *path)
{
	Biobuf *b;
	char *line, *tabc;
	int n, first;

	b = Bopen(path, OREAD);
	if(b == nil)
		sysfatal("open manifest %s: %r", path);
	first = 1;
	while((line = Brdline(b, '\n')) != nil){
		n = Blinelen(b);
		if(n > 0 && line[n-1] == '\n')
			line[n-1] = 0;
		if(first){
			first = 0;
			continue;
		}
		tabc = strchr(line, '\t');
		if(tabc != nil)
			*tabc = 0;
		if(line[0] != 0)
			lookup(line, 1);
	}
	Bterm(b);
}

static char*
second_line(char *file, char *buf, int nbuf)
{
	int fd, n;
	char *p, *e;

	fd = open(file, OREAD);
	if(fd < 0)
		return nil;
	n = read(fd, buf, nbuf - 1);
	close(fd);
	if(n <= 0)
		return nil;
	buf[n] = 0;
	p = strchr(buf, '\n');
	if(p == nil || p[1] == 0)
		return nil;
	p++;
	e = strchr(p, '\n');
	if(e != nil)
		*e = 0;
	return p;
}

static void
merge_root(char *root, Biobuf *reportb, Biobuf *dupb, Biobuf *confb, Biobuf *unexpb, Biobuf *badb)
{
	char *dir, *file, *row;
	char buf[Maxrow], idbuf[512];
	int fd, n, i;
	Dir *ds;
	Entry *e;

	dir = smprint("%s/results", root);
	if(dir == nil)
		sysfatal("smprint: %r");
	fd = open(dir, OREAD);
	if(fd < 0){
		Bprint(badb, "%s\tmissing_results_dir\n", root);
		malformed_total++;
		free(dir);
		return;
	}
	while((n = dirread(fd, &ds)) > 0){
		for(i = 0; i < n; i++){
			if(ds[i].mode & DMDIR)
				continue;
			file = smprint("%s/%s", dir, ds[i].name);
			if(file == nil)
				sysfatal("smprint: %r");
			row = second_line(file, buf, sizeof buf);
			if(row == nil || row[0] == 0){
				Bprint(badb, "%s\tempty_or_missing_result_row\n", file);
				malformed_total++;
				free(file);
				continue;
			}
			field(row, 1, idbuf, sizeof idbuf);
			if(idbuf[0] == 0){
				Bprint(unexpb, "-\t%s\n", file);
				unexpected_total++;
				free(file);
				continue;
			}
			e = lookup(idbuf, 0);
			if(e == nil){
				Bprint(unexpb, "%s\t%s\n", idbuf, file);
				unexpected_total++;
				free(file);
				continue;
			}
			if(e->seen){
				if(strcmp(e->row, row) == 0){
					Bprint(dupb, "%s\t%s\t%s\n", idbuf, e->file, file);
					duplicate_total++;
				}else{
					Bprint(confb, "%s\t%s\t%s\t%s\t%s\n", idbuf, e->file, file, e->row, row);
					conflict_total++;
				}
				free(file);
				continue;
			}
			e->seen = 1;
			e->row = xstrdup(row);
			e->file = xstrdup(file);
			deduped_total++;
			count_result(row);
			Bprint(reportb, "%s\t%s\t%s\n", row, root, file);
			free(file);
		}
		free(ds);
	}
	close(fd);
	free(dir);
}

static void
write_missing(int fd)
{
	int i;
	Entry *e;

	for(i = 0; i < Nhash; i++){
		for(e = tab[i]; e != nil; e = e->next){
			if(!e->seen){
				fprint(fd, "%s\n", e->id);
				missing_total++;
			}
		}
	}
}

static void
mkdirp(char *path)
{
	int fd;
	fd = create(path, OREAD, DMDIR|0755);
	if(fd >= 0)
		close(fd);
}

static int
openout(char *dir, char *name)
{
	char *p;
	int fd;
	p = smprint("%s/%s", dir, name);
	if(p == nil)
		sysfatal("smprint: %r");
	fd = create(p, OWRITE, 0644);
	if(fd < 0)
		sysfatal("create %s: %r", p);
	free(p);
	return fd;
}

void
main(int argc, char **argv)
{
	char *manifest, *out;
	int i, reportfd, dupfd, conffd, missfd, unexpfd, badfd, sumfd;
	Biobuf reportb, dupb, confb, unexpb, badb;

	if(argc < 4)
		sysfatal("usage: o9mutmerge manifest outdir result-root ...");
	manifest = argv[1];
	out = argv[2];
	mkdirp(out);
	read_manifest(manifest);

	reportfd = openout(out, "report.tab");
	dupfd = openout(out, "duplicates.tab");
	conffd = openout(out, "conflicts.tab");
	missfd = openout(out, "missing.tab");
	unexpfd = openout(out, "unexpected.tab");
	badfd = openout(out, "malformed.tab");

	Binit(&reportb, reportfd, OWRITE);
	Binit(&dupb, dupfd, OWRITE);
	Binit(&confb, conffd, OWRITE);
	Binit(&unexpb, unexpfd, OWRITE);
	Binit(&badb, badfd, OWRITE);

	Bprint(&reportb, "task_id\tworker_id\tsource\tmutant_path\tresult\texit_code\tseconds\tlog_path\treason\tfinished_at\troot\tfile\n");
	Bprint(&dupb, "task_id\tfirst_file\tduplicate_file\n");
	Bprint(&confb, "task_id\tfirst_file\tconflict_file\tfirst_row\tconflict_row\n");
	fprint(missfd, "task_id\n");
	Bprint(&unexpb, "task_id\tfile\n");
	Bprint(&badb, "file\treason\n");

	for(i = 3; i < argc; i++)
		merge_root(argv[i], &reportb, &dupb, &confb, &unexpb, &badb);
	write_missing(missfd);

	Bterm(&reportb);
	Bterm(&dupb);
	Bterm(&confb);
	Bterm(&unexpb);
	Bterm(&badb);
	close(reportfd);
	close(dupfd);
	close(conffd);
	close(missfd);
	close(unexpfd);
	close(badfd);

	sumfd = openout(out, "summary.tab");
	fprint(sumfd, "key\tvalue\n");
	fprint(sumfd, "manifest_total\t%ld\n", manifest_total);
	fprint(sumfd, "deduped_total\t%ld\n", deduped_total);
	fprint(sumfd, "missing\t%ld\n", missing_total);
	fprint(sumfd, "duplicates\t%ld\n", duplicate_total);
	fprint(sumfd, "conflicts\t%ld\n", conflict_total);
	fprint(sumfd, "unexpected\t%ld\n", unexpected_total);
	fprint(sumfd, "malformed\t%ld\n", malformed_total);
	fprint(sumfd, "killed\t%ld\n", killed_total);
	fprint(sumfd, "survived\t%ld\n", survived_total);
	fprint(sumfd, "timeout\t%ld\n", timeout_total);
	fprint(sumfd, "infra_fail\t%ld\n", infra_total);
	fprint(sumfd, "setup_error\t%ld\n", setup_total);
	fprint(sumfd, "equivalent\t%ld\n", equivalent_total);
	close(sumfd);

	print("merge_complete\t%s\n", out);
	print("manifest_total\t%ld\n", manifest_total);
	print("deduped_total\t%ld\n", deduped_total);
	print("missing\t%ld\n", missing_total);
	print("duplicates\t%ld\n", duplicate_total);
	print("conflicts\t%ld\n", conflict_total);
	print("unexpected\t%ld\n", unexpected_total);
	print("malformed\t%ld\n", malformed_total);

	if(missing_total != 0 || conflict_total != 0 || unexpected_total != 0 || malformed_total != 0)
		exits("merge");
	exits(nil);
}
