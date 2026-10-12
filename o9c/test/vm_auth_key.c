#include <u.h>
#include <libc.h>
#include <libsec.h>
#include <authsrv.h>

/* Install a test account in the VM-local keyfs. */

void
main(int argc, char **argv)
{
	Authkey key;
	char path[128];
	int fd;

	if(argc != 3)
		sysfatal("usage: vm_auth_key user password");
	memset(&key, 0, sizeof key);
	passtokey(&key, argv[2]);
	snprint(path, sizeof path, "/mnt/keys/%s", argv[1]);
	fd = create(path, OREAD, DMDIR|0777);
	if(fd < 0)
		sysfatal("create %s: %r", path);
	close(fd);
	snprint(path, sizeof path, "/mnt/keys/%s/key", argv[1]);
	fd = open(path, OWRITE);
	if(fd < 0 || write(fd, key.des, DESKEYLEN) != DESKEYLEN)
		sysfatal("write %s: %r", path);
	close(fd);
	snprint(path, sizeof path, "/mnt/keys/%s/aeskey", argv[1]);
	fd = open(path, OWRITE);
	if(fd >= 0){
		if(write(fd, key.aes, AESKEYLEN) != AESKEYLEN)
			sysfatal("write %s: %r", path);
		close(fd);
	}
	print("key installed: %s\n", argv[1]);
	exits(nil);
}
