#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/* Exercises the Tabula runtime over libtab: create -> add rows -> set
 * cells -> iterate/get -> serialize -> reopen the serialized bytes and
 * verify the rows survive the round-trip.  Uses threadmain because
 * libo9 pulls in the thread library (the facade server). */
void
threadmain(int, char**)
{
	O9Tabula *t, *t2;
	char *s, *path;
	int fd, n, count;

	/* build a two-column tab with two rows */
	t = o9_tab_new("orders", "item,qty");
	if(t == nil)
		sysfatal("new");
	if(o9_tab_add(t, "a") != 0) sysfatal("add a");
	if(o9_tab_set(t, "item", "widget") != 0) sysfatal("set item");
	if(o9_tab_set(t, "qty", "5") != 0) sysfatal("set qty");
	if(o9_tab_add(t, "b") != 0) sysfatal("add b");
	if(o9_tab_set(t, "item", "gadget") != 0) sysfatal("set item2");
	if(o9_tab_set(t, "qty", "3") != 0) sysfatal("set qty2");

	/* iterate and count/read back */
	count = 0;
	if(o9_tab_first(t)){
		do {
			char *item = o9_tab_get(t, "item");
			if(item == nil || item[0] == '\0')
				sysfatal("empty item at row %d", count);
			count++;
		} while(o9_tab_next(t));
	}
	if(count != 2)
		sysfatal("expected 2 rows, iterated %d", count);

	/* serialize, write to disk, reopen, verify a value survives */
	s = o9_tab_serialize(t);
	if(s == nil || s[0] == '\0')
		sysfatal("serialize empty");
	path = "/tmp/o9_tab_test.tab";
	fd = create(path, OWRITE, 0644);
	if(fd < 0) sysfatal("create %s", path);
	n = strlen(s);
	if(write(fd, s, n) != n) sysfatal("write");
	close(fd);
	free(s);

	t2 = o9_tab_open(path);
	if(t2 == nil)
		sysfatal("reopen");
	count = 0;
	if(o9_tab_first(t2)){
		do { count++; } while(o9_tab_next(t2));
	}
	if(count != 2)
		sysfatal("reopened: expected 2 rows, got %d", count);

	o9_tab_close(t);
	o9_tab_close(t2);
	remove(path);
	print("tab_test: OK\n");
	threadexitsall(nil);
}
