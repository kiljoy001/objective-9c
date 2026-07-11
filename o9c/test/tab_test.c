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
	O9Tabula *t, *t2, *q;
	O9String *os, *oa, *ob, *oc;
	char *s, *item, *qty, *path;
	int fd, n, count;

	/* build a two-column tab with two rows */
	oa = o9_string_from_c("orders");
	ob = o9_string_from_c("item,qty");
	t = o9_tab_new(oa, ob);
	o9_string_release(oa);
	o9_string_release(ob);
	if(t == nil)
		sysfatal("new");
	oa = o9_string_from_c("a");
	ob = o9_string_from_c("item");
	oc = o9_string_from_c("widget");
	if(o9_tab_write(t, oa, ob, oc) != 0) sysfatal("write item");
	o9_string_release(ob);
	o9_string_release(oc);
	ob = o9_string_from_c("qty");
	oc = o9_string_from_c("5");
	if(o9_tab_write(t, oa, ob, oc) != 0) sysfatal("write qty");
	o9_string_release(oa);
	o9_string_release(ob);
	o9_string_release(oc);
	oa = o9_string_from_c("b");
	ob = o9_string_from_c("item");
	oc = o9_string_from_c("gadget");
	if(o9_tab_write(t, oa, ob, oc) != 0) sysfatal("write item2");
	o9_string_release(ob);
	o9_string_release(oc);
	ob = o9_string_from_c("qty");
	oc = o9_string_from_c("3");
	if(o9_tab_write(t, oa, ob, oc) != 0) sysfatal("write qty2");
	o9_string_release(oa);
	o9_string_release(ob);
	o9_string_release(oc);

	/* iterate and count/read back */
	count = 0;
	if(o9_tab_first(t)){
		do {
			oa = o9_string_from_c("item");
			os = o9_tab_get(t, oa);
			item = o9_string_cstr(os);
			o9_string_release(oa);
			o9_string_release(os);
			if(item == nil || item[0] == '\0')
				sysfatal("empty item at row %d", count);
			free(item);
			count++;
		} while(o9_tab_next(t));
	}
	if(count != 2)
		sysfatal("expected 2 rows, iterated %d", count);

	/* query by column/value */
	oa = o9_string_from_c("item");
	ob = o9_string_from_c("widget");
	q = o9_tab_query(t, oa, ob);
	o9_string_release(oa);
	o9_string_release(ob);
	if(q == nil || !o9_tab_first(q))
		sysfatal("query");
	oa = o9_string_from_c("qty");
	os = o9_tab_get(q, oa);
	qty = o9_string_cstr(os);
	o9_string_release(oa);
	o9_string_release(os);
	if(qty == nil || strcmp(qty, "5") != 0)
		sysfatal("query qty");
	free(qty);
	o9_tab_close(q);

	/* serialize, write to disk, reopen, verify a value survives */
	os = o9_tab_read(t);
	s = o9_string_cstr(os);
	if(s == nil || s[0] == '\0')
		sysfatal("serialize empty");
	path = "/tmp/o9_tab_test.tab";
	fd = create(path, OWRITE, 0644);
	if(fd < 0) sysfatal("create %s", path);
	n = strlen(s);
	if(write(fd, s, n) != n) sysfatal("write");
	close(fd);
	free(s);
	o9_string_release(os);

	oa = o9_string_from_c(path);
	t2 = o9_tab_open(oa);
	o9_string_release(oa);
	if(t2 == nil)
		sysfatal("reopen");
	oa = o9_string_from_c("b");
	ob = o9_string_from_c("qty");
	oc = o9_string_from_c("4");
	if(o9_tab_write(t2, oa, ob, oc) != 0)
		sysfatal("disk write");
	o9_string_release(oa);
	o9_string_release(ob);
	o9_string_release(oc);
	if(o9_tab_flush(t2) != 0)
		sysfatal("flush");
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
