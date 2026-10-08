#include <u.h>
#include <libc.h>

static void
want(int ok, char *message)
{
	if(!ok) sysfatal("view io: %s: %r", message);
}

static int
has(Dir *entries, int count, char *name)
{
	int i;
	for(i = 0; i < count; i++)
		if(strcmp(entries[i].name, name) == 0) return 1;
	return 0;
}

void
main(int argc, char **argv)
{
	char root[512], path[640], ctl[512], command[128], buf[64];
	Dir *entries, *before, *after;
	int dirfd, fd, count, n;
	if(argc != 2) sysfatal("usage: view_io_test mountpoint");
	snprint(root, sizeof root, "%s/view", argv[1]);
	snprint(path, sizeof path, "%s/editable", root);
	before = dirstat(path);
	want(before != nil, "stat editable");
	fd = open(path, ORDWR);
	want(fd >= 0, "open editable");
	want(seek(fd, 2, 0) == 2, "seek writable text");
	want(write(fd, "X", 1) == 1, "offset write");
	want(seek(fd, 2, 0) == 2, "seek readable text");
	want(read(fd, buf, 1) == 1 && buf[0] == 'X', "offset read");
	close(fd);
	after = dirstat(path);
	want(after != nil && before->qid.path == after->qid.path, "stable qid after text replacement");
	free(before);
	free(after);
	fd = open(path, OWRITE|OTRUNC);
	want(fd >= 0, "truncate writable text");
	want(write(fd, "hi", 2) == 2, "write after truncate");
	close(fd);
	fd = open(path, OREAD);
	want(fd >= 0, "reopen text");
	n = read(fd, buf, sizeof buf);
	want(n == 2 && memcmp(buf, "hi", 2) == 0, "truncated content");
	close(fd);

	dirfd = open(root, OREAD);
	want(dirfd >= 0, "open view directory");
	snprint(path, sizeof path, "%s/trigger", root);
	fd = open(path, OWRITE);
	want(fd >= 0, "open live trigger");
	want(write(fd, "new", 3) == 3, "write live trigger");
	close(fd);
	count = dirreadall(dirfd, &entries);
	want(count >= 0 && !has(entries, count, "created"), "open directory listing is a snapshot");
	free(entries);
	close(dirfd);
	dirfd = open(root, OREAD);
	want(dirfd >= 0, "reopen view directory");
	count = dirreadall(dirfd, &entries);
	want(count >= 0 && has(entries, count, "created"), "new directory listing sees change");
	free(entries);
	close(dirfd);
	snprint(path, sizeof path, "%s/created", root);
	fd = open(path, OREAD);
	want(fd >= 0, "walk newly created entry");
	close(fd);
	want(create(path, OWRITE, 0666) < 0, "client create denied");
	want(remove(path) < 0, "client remove denied");
	before = dirstat(path);
	want(before != nil, "stat before rename");
	before->name = "renamed";
	want(dirwstat(path, before) < 0, "client rename denied");
	free(before);

	fd = open(path, OREAD);
	want(fd >= 0, "open fid before revocation");
	snprint(ctl, sizeof ctl, "%s/ctl", argv[1]);
	snprint(command, sizeof command, "view close");
	dirfd = open(ctl, OWRITE);
	want(dirfd >= 0, "open root ctl");
	want(write(dirfd, command, strlen(command)) == strlen(command), "close view through root ctl");
	close(dirfd);
	want(read(fd, buf, 1) < 0, "revoked open fid fails");
	close(fd);
	want(open(path, OREAD) < 0, "revoked path no longer walks");
	print("view io: OK\n");
	exits(nil);
}
