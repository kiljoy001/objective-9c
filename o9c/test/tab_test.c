#include "libtab/tab_internal.h"
#include <thread.h>
#include "o9.h"

extern void o9_tab_discard(Tab*);

/* Exercises the tabula runtime over libtab: create -> add rows -> set
 * cells -> iterate/get -> serialize -> reopen the serialized bytes and
 * verify the rows survive the round-trip.  Uses threadmain because
 * libo9 pulls in the thread library (the facade server). */
void
threadmain(int, char**)
{
	O9Tabula *t, *t2, *q;
	O9String *os, *oa, *ob, *oc;
	char *s, *item, *qty, *path, *dupepath, *typedpath, *discardpath, *td;
	Tab *raw;
	TabRow *rr;
	TabIter *it;
	TabColSpec specs[2];
	char *ts;
	int fd, n, count;

	/* honour $TMP so the disk round-trip cases can run on a host whose
	 * /tmp is read-only (e.g. a shared drawterm server); fall back to /tmp. */
	td = getenv("TMP");
	if(td == nil || td[0] == '\0')
		td = "/tmp";

	/* build a two-column tab with two rows */
	oa = o9_string_from_c("orders");
	ob = o9_string_from_c("item,qty");
	t = o9_tab_new(oa, ob);
	o9_string_release(oa);
	o9_string_release(ob);
	if(t == nil)
		sysfatal("new");
	os = o9_tab_schema(t);
	s = o9_string_cstr(os);
	o9_string_release(os);
	if(s == nil || strcmp(s, "orders") != 0)
		sysfatal("schema");
	free(s);
	oa = o9_string_from_c("qty");
	if(o9_tab_has(t, oa) != 1)
		sysfatal("has qty");
	o9_string_release(oa);
	oa = o9_string_from_c("missing");
	if(o9_tab_has(t, oa) != 0)
		sysfatal("has missing");
	o9_string_release(oa);
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

	/* nil writes clear/omit the cell instead of serializing col=nil. */
	oa = o9_string_from_c("b");
	ob = o9_string_from_c("qty");
	if(o9_tab_write(t, oa, ob, nil) != 0)
		sysfatal("clear qty");
	os = o9_tab_value(t, oa, ob);
	qty = o9_string_cstr(os);
	o9_string_release(os);
	if(qty == nil || qty[0] != '\0')
		sysfatal("cleared qty still visible");
	free(qty);
	q = o9_tab_query(t, ob, nil);
	if(q == nil || !o9_tab_first(q))
		sysfatal("query nil qty");
	o9_tab_close(q);
	oc = o9_string_from_c("3");
	if(o9_tab_write(t, oa, ob, oc) != 0)
		sysfatal("restore qty");
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
	if(strstr(s, "qty=nil") != nil)
		sysfatal("serialized nil cell");
	path = smprint("%s/o9_tab_test.tab", td);
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

	/* typed schema metadata must survive serialization. */
	memset(specs, 0, sizeof specs);
	specs[0].name = "id";
	specs[1].name = "digest";
	specs[1].type = "HASHED";
	specs[1].algo = "blake2b";
	typedpath = smprint("%s/o9_tab_typed.tab", td);
	raw = tab_create(typedpath, "typed", specs, 2);
	if(raw == nil)
		sysfatal("typed create: %s", tab_lasterror());
	ts = tab_serialize(raw, &n);
	if(ts == nil)
		sysfatal("typed serialize: %s", tab_lasterror());
	if(strstr(ts, "col=digest type=HASHED algo=blake2b") == nil)
		sysfatal("typed schema metadata missing");
	free(ts);
	tab_close(raw);
	remove(typedpath);
	free(typedpath);

	/* discard clears dirty so close does not auto-flush a mutation. */
	memset(specs, 0, sizeof specs);
	specs[0].name = "id";
	specs[1].name = "value";
	discardpath = smprint("%s/o9_tab_discard.tab", td);
	raw = tab_create(discardpath, "discard", specs, 2);
	if(raw == nil)
		sysfatal("discard create: %s", tab_lasterror());
	if(tab_commit(raw) != 0)
		sysfatal("discard initial commit: %s", tab_lasterror());
	rr = tab_add_row(raw, "id", "kept-in-memory");
	if(rr == nil || tab_set(raw, rr, "value", "not-on-disk") != 0)
		sysfatal("discard mutate: %s", tab_lasterror());
	if(raw->dirty != 1)
		sysfatal("discard setup did not mark dirty");
	o9_tab_discard(raw);
	if(raw->dirty != 0)
		sysfatal("discard did not clear dirty");
	tab_close(raw);
	raw = tab_open(discardpath);
	if(raw == nil)
		sysfatal("discard reopen: %s", tab_lasterror());
	count = 0;
	it = tab_iter(raw);
	while(tab_iter_next(it) != nil)
		count++;
	tab_iter_close(it);
	if(count != 0)
		sysfatal("discard close flushed %d rows", count);
	tab_close(raw);
	remove(discardpath);
	free(discardpath);

	/* duplicate rows collapse on open; the text file remains the source. */
	dupepath = smprint("%s/o9_tab_dupe.tab", td);
	fd = create(dupepath, OWRITE|OTRUNC, 0644);
	if(fd < 0)
		sysfatal("create duplicate tab");
	s = "schema=dupe\n\tcol=id\n\tcol=value\n\n"
	    "id=same\n\tvalue=one\n\n"
	    "id=same\n\tvalue=one\n\n";
	n = strlen(s);
	if(write(fd, s, n) != n)
		sysfatal("write duplicate tab");
	close(fd);
	raw = tab_open(dupepath);
	if(raw == nil)
		sysfatal("open duplicate tab: %s", tab_lasterror());
	count = 0;
	it = tab_iter(raw);
	while(tab_iter_next(it) != nil)
		count++;
	tab_iter_close(it);
	if(count != 1)
		sysfatal("duplicate rows not collapsed: %d", count);
	tab_close(raw);
	remove(dupepath);
	free(dupepath);

	o9_tab_close(t);
	o9_tab_close(t2);
	remove(path);
	free(path);
	print("tab_test: OK\n");
	threadexitsall(nil);
}
