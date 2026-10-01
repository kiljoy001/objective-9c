#include <u.h>
#include <libc.h>
#include <bio.h>
#include <mach.h>

/* Inspect PCs in the expected function, then have Acid independently report
 * those PCs. file2pc is an approximate inverse and is unsuitable for testing
 * repeated #line locations created by lowering one statement to many lines. */
typedef struct Check Check;
struct Check {
	char *name;
	char *symbol;
	char *file;
	int line;
};

static Check checks[] = {
	{"root", "threadmain", "o9c/test/source_map/root.o9", 6},
	{"raw", "o9_impl_origin_run", "o9c/test/source_map/middle.o9", 12},
	{"return", "o9_impl_origin_run", "o9c/test/source_map/middle.o9", 15},
	{"nested", "o9_impl_MappedLeaf_value", "o9c/test/source_map/leaf.o9", 3},
	{"defer", "o9_impl_MappedLeaf_branch", "o9c/test/source_map/leaf.o9", 11},
	{"elif", "o9_impl_MappedLeaf_branch", "o9c/test/source_map/leaf.o9", 14},
};

static void
check(Check *c)
{
	Symbol sym;
	uvlong bounds[2], pc;
	char got[2048], want[1024];
	int n;

	if(!lookup(nil, c->symbol, &sym) || !fnbound(sym.value, bounds))
		sysfatal("source-map: missing function %s", c->symbol);
	snprint(want, sizeof want, "%s:%d", c->file, c->line);
	n = strlen(want);
	for(pc = bounds[0]; pc < bounds[1]; pc++){
		if(fileline(got, sizeof got, pc) && strncmp(got, want, n) == 0 &&
		   (got[n] == '\0' || got[n] == '[')){
			print("print(\"source-map %s \", pcfile(0x%llux), \":\", pcline(0x%llux), \"\\n\");\n",
				c->name, pc, pc);
			return;
		}
	}
	sysfatal("source-map: %s has no PC mapped to %s", c->symbol, want);
}

void
main(int argc, char **argv)
{
	Fhdr hdr;
	int fd, i;

	if(argc != 2)
		sysfatal("usage: source_map_check executable");
	fd = open(argv[1], OREAD);
	if(fd < 0 || !crackhdr(fd, &hdr) || syminit(fd, &hdr) < 0)
		sysfatal("source-map: read symbols: %r");
	for(i = 0; i < nelem(checks); i++)
		check(&checks[i]);
	close(fd);
	exits(nil);
}
