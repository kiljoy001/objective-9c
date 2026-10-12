#include <u.h>
#include <libc.h>
#include <libsec.h>

/* Disposable VM test helper: switch users without rebuilding the namespace. */

void
main(int argc, char **argv)
{
	uchar rand[20], hash[SHA1dlen];
	char *cap, *key, *from, *to;
	int fd, n;

	if(argc < 3)
		sysfatal("usage: vm_as user command ...");
	from = getuser();
	to = argv[1];
	cap = malloc(strlen(from)+strlen(to)+sizeof rand*3+4);
	if(cap == nil)
		sysfatal("malloc: %r");
	sprint(cap, "%s@%s", from, to);
	genrandom(rand, sizeof rand);
	key = cap + strlen(cap) + 1;
	enc64(key, sizeof rand*3, rand, sizeof rand);
	hmac_sha1((uchar*)cap, strlen(cap), (uchar*)key, strlen(key), hash, nil);
	fd = open("/dev/caphash", OWRITE);
	if(fd < 0 || write(fd, hash, sizeof hash) != sizeof hash)
		sysfatal("install capability: %r");
	close(fd);
	key[-1] = '@';
	fd = open("/dev/capuse", OWRITE);
	n = strlen(cap);
	if(fd < 0 || write(fd, cap, n) != n)
		sysfatal("use capability: %r");
	close(fd);
	argv += 2;
	exec(argv[0], argv);
	sysfatal("exec %s: %r", argv[0]);
}
