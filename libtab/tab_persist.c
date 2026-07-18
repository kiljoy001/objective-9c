/*
 * libtab — persistence.
 *
 * Two write paths, both serialising via tab_serialize() first:
 *
 *   POSIX path (dial == nil):
 *     Write to <path>.tmp.<pid>, fsync, rename(2) over the original.
 *     Atomicity guaranteed by the kernel's rename semantics.
 *
 *   9P path  (dial != nil):
 *     Dial the named fileserver via lib9pclient, fsopen the target
 *     path for OWRITE|OTRUNC, fswrite the bytes, fsclose, fsunmount.
 *     Atomicity, durability, concurrent-writer serialisation are the
 *     fileserver's problem — libtab just emits bytes.  This is the
 *     intended path for cross-namespace and admin-inspectable tables
 *     once the system has a 9P fileserver hosting the .tab tree.
 *
 * Persistence trigger model:
 *
 *   - Any successful tab_set_* sets t->dirty = 1.
 *   - tab_commit(t) flushes and clears the flag.
 *   - tab_close(t) auto-flushes if dirty.  Errors at this stage
 *     surface via tab_lasterror() but cannot fail the close.
 *   - Consumers that need a discard semantic call tab_discard()
 *     before close (added when a consumer asks for it).
 */

#include "tab_internal.h"
#ifdef __GNUC__
#include <9pclient.h>

/* POSIX rename(2) — not declared in plan9port's libc.h, so we
 * forward-declare here.  Signature is the standard one. */
extern int rename(const char *oldpath, const char *newpath);
#endif

/* Write `bytes` of length `n` to `path` via POSIX, atomically.  The
 * temp-file is `path.tmp.<pid>` in the same directory; rename(2)
 * moves it over the original in one step. */
static int
posix_write_atomic(const char *path, const char *bytes, int n)
{
#ifdef __GNUC__
	char tmp[1024];
	int fd;
	long written;

	snprint(tmp, sizeof tmp, "%s.tmp.%d", path, (int)getpid());
	fd = create(tmp, OWRITE, 0644);
	if(fd < 0){
		tab_seterror("tab_commit: create %s: %r", tmp);
		return -1;
	}
	written = write(fd, (void *)bytes, n);
	if(written != n){
		tab_seterror("tab_commit: short write to %s: %ld of %d (%r)",
			tmp, written, n);
		close(fd);
		remove(tmp);
		return -1;
	}
	/* fsync via the underlying fd.  plan9port's libc maps this to
	 * the POSIX fsync(2) on Unix. */
	if(fsync(fd) < 0){
		tab_seterror("tab_commit: fsync %s: %r", tmp);
		close(fd);
		remove(tmp);
		return -1;
	}
	close(fd);
	if(rename(tmp, path) < 0){
		tab_seterror("tab_commit: rename %s -> %s: %r", tmp, path);
		remove(tmp);
		return -1;
	}
	return 0;
#else
	int fd;
	long written;

	fd = open((char *)path, OWRITE|OTRUNC);
	if(fd < 0)
		fd = create((char *)path, OWRITE, 0644);
	if(fd < 0){
		tab_seterror("tab_commit: open/create %s: %r", path);
		return -1;
	}
	written = write(fd, (void *)bytes, n);
	if(written != n){
		tab_seterror("tab_commit: short write to %s: %ld of %d (%r)",
			path, written, n);
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
#endif
}

/* Write `bytes` of length `n` to `path` via the named 9P fileserver.
 * The dial string is anything `nsmount` / `dial` accepts — a
 * service name (mounted under $NAMESPACE/<name>) or a network
 * address. */
static int
ninep_write(const char *dial, const char *path, const char *bytes, int n)
{
#ifdef __GNUC__
	CFsys *fs;
	CFid *fid;
	long written;

	fs = nsmount((char *)dial, nil);
	if(fs == nil){
		tab_seterror("tab_commit: nsmount %s: %r", dial);
		return -1;
	}
	fid = fsopen(fs, (char *)path, OWRITE | OTRUNC);
	if(fid == nil){
		/* Try create instead — most 9P servers return an error on
		 * open of a non-existent file. */
		fid = fscreate(fs, (char *)path, OWRITE, 0644);
	}
	if(fid == nil){
		tab_seterror("tab_commit: fsopen/fscreate %s on %s: %r",
			path, dial);
		fsunmount(fs);
		return -1;
	}
	written = fswrite(fid, (void *)bytes, n);
	if(written != n){
		tab_seterror("tab_commit: short fswrite to %s: %ld of %d (%r)",
			path, written, n);
		fsclose(fid);
		fsunmount(fs);
		return -1;
	}
	fsclose(fid);
	fsunmount(fs);
	return 0;
#else
	USED(dial);
	USED(path);
	USED(bytes);
	USED(n);
	tab_seterror("tab_commit: 9P dial persistence requires plan9port lib9pclient");
	return -1;
#endif
}

int
tab_commit(Tab *t)
{
	char *buf;
	int len, rc;

	tab_clearerror();
	if(t == nil){
		tab_seterror("tab_commit: nil Tab");
		return -1;
	}
	buf = tab_serialize(t, &len);
	if(buf == nil)
		return -1;

	if(t->dial != nil){
		const char *rp = t->remote_path != nil ? t->remote_path
		                                       : t->path;
		rc = ninep_write(t->dial, rp, buf, len);
	}else{
		rc = posix_write_atomic(t->path, buf, len);
	}
	free(buf);
	if(rc == 0)
		t->dirty = 0;
	return rc;
}
