#include <u.h>
#include <libc.h>

void
main(int argc, char **argv)
{
	char buf[4096];
	int in, out, n;

	if(argc != 3)
		sysfatal("usage: vm_appuser_split source response.tab | -deny ctl");
	if(strcmp(argv[1], "-deny") == 0){
		out = open(argv[2], OWRITE);
		if(out < 0)
			sysfatal("open ctl: %r");
		n = write(out, "whoami\n", 7);
		close(out);
		if(n >= 0)
			sysfatal("unauthenticated ctl write accepted");
		print("PREAUTH CTL DENIED\n");
		exits(nil);
	}
	in = open(argv[1], OREAD);
	if(in < 0)
		sysfatal("open source: %r");
	n = read(in, buf, sizeof buf);
	close(in);
	if(n < 200 || n > sizeof buf)
		sysfatal("bad response length %d", n);
	out = open(argv[2], OWRITE);
	if(out < 0)
		sysfatal("open response: %r");
	if(write(out, buf, 37) != 37 ||
	   write(out, buf+37, 113) != 113 ||
	   write(out, buf+150, n-150) != n-150)
		sysfatal("split write: %r");
	close(out);
	print("SPLIT RESPONSE PASS\n");
	out = open(argv[2], OWRITE);
	if(out >= 0){
		close(out);
		sysfatal("response replay was accepted");
	}
	print("REPLAY DENIED\n");
	exits(nil);
}
