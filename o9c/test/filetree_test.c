#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

static O9String*
s(char *text)
{
	return o9_string_from_c(text);
}

static void
want(int ok, char *what)
{
	if(!ok) sysfatal("filetree: %s", what);
}

static char*
contents(O9FileTree *t, O9FTEntry *dir, char *name)
{
	O9FTEntry *e;
	O9String *value;
	char *copy;
	e = o9_filetree_lookup(t, dir, name);
	if(e == nil) return nil;
	value = o9_filetree_data(t, e);
	if(value == nil) return nil;
	copy = o9_string_cstr(value);
	o9_string_release(value);
	return copy;
}

static void
wanttext(O9FileTree *t, O9FTEntry *dir, char *name, char *expected)
{
	char *got;
	got = contents(t, dir, name);
	want(got != nil && strcmp(got, expected) == 0, name);
	free(got);
}

static O9MountTable*
recipe(char *target, char *source, int mode)
{
	O9MountTable *m;
	m = o9_mount_table_new(nil);
	want(m != nil, "new mount table");
	want(o9_mount_table_view(m, s(target), s(source), mode) == 0, "add view row");
	return m;
}

void
threadmain(int argc, char **argv)
{
	O9FileTree *a, *b, *c, *d;
	O9FTEntry *root, *first, **listing;
	O9MountTable *m, *loaded;
	O9String *bytes;
	char *copy;
	uvlong id;
	int fd, n;
	USED(argc);
	USED(argv);
	a = o9_filetree_new();
	b = o9_filetree_new();
	c = o9_filetree_new();
	d = o9_filetree_new();
	want(a != nil && b != nil && c != nil && d != nil, "new trees");
	root = o9_filetree_root(a);
	want(o9_filetree_entries(a, root, &listing) == 0, "empty root");
	free(listing);
	want(o9_filetree_dir(a, s("nested")) == 0, "directory");
	want(o9_filetree_text(a, s("nested/leaf"), s("first"), 0) == 0, "stored text");
	first = o9_filetree_lookup(a, o9_filetree_lookup(a, root, "nested"), "leaf");
	want(first != nil, "hash lookup");
	id = o9_filetree_id(first);
	want(o9_filetree_text(a, s("nested/leaf"), s("second"), 1) == 0, "replace text");
	want(o9_filetree_id(first) == id, "stable entry id");
	wanttext(a, o9_filetree_lookup(a, root, "nested"), "leaf", "second");
	want(o9_filetree_remove(a, s("nested/leaf")) == 0, "remove entry");
	want(o9_filetree_lookup(a, o9_filetree_lookup(a, root, "nested"), "leaf") == nil, "removed entry hidden");
	want(o9_filetree_text(a, s("nested/leaf"), s("third"), 0) == 0, "recreate entry");
	want(o9_filetree_id(o9_filetree_lookup(a, o9_filetree_lookup(a, root, "nested"), "leaf")) != id, "new id on recreate");
	want(o9_filetree_text(a, s("shared"), s("A"), 0) == 0, "local shared");
	want(o9_filetree_text(b, s("shared"), s("B"), 0) == 0, "mounted shared");
	want(o9_filetree_text(c, s("shared"), s("C"), 0) == 0, "second mounted shared");
	want(o9_filetree_register(a, s("a")) == 0 && o9_filetree_register(b, s("b")) == 0 &&
	     o9_filetree_register(c, s("c")) == 0, "local registration");
	want(o9_filetree_register(b, s("b")) < 0, "duplicate source id");
	m = recipe(".", "b", 1);
	want(o9_mount_table_allow_root(m, s("/tmp/o9-filetree-mount-root")) == 0,
	     "set process namespace root");
	want(o9_mount_table_validate(m) < 0, "process namespace rejects view row");
	want(o9_filetree_apply(a, m) == 0, "before mount");
	wanttext(a, root, "shared", "B");
	loaded = recipe(".", "c", 1);
	want(o9_filetree_apply(a, loaded) == 0, "new before mount");
	wanttext(a, root, "shared", "C");
	o9_mount_table_close(loaded);
	n = o9_filetree_entries(a, root, &listing);
	want(n == 2, "union listing deduplicates names");
	free(listing);
	bytes = o9_mount_table_serialize(m);
	want(bytes != nil, "serialize mount table");
	fd = create("/tmp/o9_filetree_mount_test.tab", OWRITE, 0600);
	want(fd >= 0, "create serialized table");
	want(write(fd, o9_string_data(bytes), o9_string_len(bytes)) == o9_string_len(bytes), "write serialized table");
	close(fd);
	loaded = o9_mount_table_new(s("/tmp/o9_filetree_mount_test.tab"));
	want(loaded != nil, "load serialized table");
	want(o9_filetree_apply(d, loaded) == 0, "resolve source locally after load");
	wanttext(d, o9_filetree_root(d), "shared", "B");
	o9_mount_table_close(loaded);
	o9_string_release(bytes);
	o9_mount_table_close(m);
	m = o9_mount_table_new(nil);
	want(o9_mount_table_unmount(m, s(".")) == 0, "unmount row");
	want(o9_filetree_apply(a, m) == 0, "unmount apply");
	wanttext(a, root, "shared", "A");
	o9_mount_table_close(m);
	m = recipe(".", "b", 2);
	want(o9_filetree_apply(a, m) == 0, "after mount");
	wanttext(a, root, "shared", "A");
	o9_mount_table_close(m);
	m = recipe(".", "b", 0);
	want(o9_filetree_apply(a, m) == 0, "replace mount");
	wanttext(a, root, "shared", "B");
	o9_mount_table_close(m);
	m = recipe(".", "missing", 0);
	want(o9_filetree_apply(a, m) < 0, "missing source rejected");
	wanttext(a, root, "shared", "B");
	o9_mount_table_close(m);
	m = recipe(".", "a", 0);
	want(o9_filetree_apply(b, m) < 0, "indirect cycle rejected");
	want(o9_filetree_apply(a, m) < 0, "direct cycle rejected");
	o9_mount_table_close(m);
	m = recipe(".", "c", 0);
	want(o9_filetree_apply(b, m) == 0, "second graph edge");
	o9_mount_table_close(m);
	m = recipe(".", "a", 0);
	want(o9_filetree_apply(c, m) < 0, "long cycle rejected");
	o9_mount_table_close(m);
	m = o9_mount_table_new(nil);
	want(o9_mount_table_unmount(m, s(".")) == 0, "remove second graph edge");
	want(o9_filetree_apply(b, m) == 0, "restore local B");
	o9_mount_table_close(m);
	m = o9_mount_table_new(nil);
	want(o9_mount_table_view(m, s("."), s("tcp!host!port"), 0) < 0, "address rejected");
	want(o9_mount_table_view(m, s("."), s("/srv/other"), 0) < 0, "srv path rejected");
	o9_mount_table_close(m);
	o9_filetree_revoke(a);
	want(o9_filetree_lookup(a, root, "nested") == nil, "revoked tree hidden");
	copy = contents(b, o9_filetree_root(b), "shared");
	want(copy != nil && strcmp(copy, "B") == 0, "other tree survives revoke");
	free(copy);
	print("filetree: OK\n");
	threadexitsall(nil);
}
