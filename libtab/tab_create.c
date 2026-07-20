/*
 * libtab — create a fresh table + add rows.
 *
 * Step 1a of the identity-and-ownership migration: libtab needs
 * entry points for building a Tab from nothing (no on-disk file
 * yet) and adding rows to it, so consumers can seed canonical
 * stores like /usr/users/users.tab from scratch.
 *
 * Surface:
 *
 *   tab_create(path, schema_name, cols, ncols)
 *      Build an in-memory Tab with no underlying ndb handle.  The
 *      file at `path` does not have to exist; tab_commit() will
 *      create it.  The schema is materialised directly from the
 *      TabColSpec array — no on-disk parse needed.
 *
 *   tab_add_row(t, head_attr, head_val)
 *      Append a row whose first tuple is `head_attr=head_val`.
 *      Returns the new TabRow.  Subsequent cells are set via
 *      tab_set / tab_set_hashed / tab_set_signed.
 *
 *   tab_set(t, r, col, value)
 *      Set or create an untyped cell on a row.  Mirrors the typed
 *      setters (tab_set_hashed, tab_set_signed) for plain text.
 *      Existing cell → replace; missing cell → append.  Rehashes
 *      the row in the rowmap.
 *
 *   tab_clear(t, r, col)
 *      Remove a non-identity cell from a row. Missing cell → no-op.
 *
 * Persistence is identical to mutation-of-existing-file: every
 * tab_set_* marks the Tab dirty; tab_commit writes; tab_close
 * auto-commits if dirty.
 */

#include "tab_internal.h"

int tab_rowmap_insert(Tab *t, Ndbtuple *chain);
int tab_rowmap_rehash(Tab *t, Ndbtuple *chain);

static int
schema_type_ok(const char *type)
{
	if(type == nil)
		return 1;
	return strcmp(type, "HASHED") == 0 || strcmp(type, "SIGNED") == 0;
}

static Ndbtuple*
tab_nil_chain(Tab *t)
{
	Ndbtuple *head, *last, *nt;
	int i;

	if(t == nil || t->schema.ncols <= 0)
		return nil;
	head = ndbnew(t->schema.cols[0].name, "nil");
	if(head == nil)
		return nil;
	last = head;
	for(i = 1; i < t->schema.ncols; i++){
		nt = ndbnew(t->schema.cols[i].name, "nil");
		if(nt == nil){
			ndbfree(head);
			return nil;
		}
		last->entry = nt;
		last = nt;
	}
	return head;
}

int
tab_ensure_nil_row(Tab *t)
{
	Ndbtuple *chain;
	int i, ins;

	if(t == nil || t->schema.ncols <= 0){
		tab_seterror("tab_ensure_nil_row: bad table");
		return -1;
	}
	if(t->nilrow != nil)
		return 0;
	for(i = 0; i < t->nrows; i++){
		if(tab_row_is_nil(t, t->rows[i])){
			t->nilrow = t->rows[i];
			return 0;
		}
	}
	chain = tab_nil_chain(t);
	if(chain == nil){
		tab_seterror("tab_ensure_nil_row: ndbnew failed");
		return -1;
	}
	ins = tab_rowmap_insert(t, chain);
	if(ins < 0){
		ndbfree(chain);
		return -1;
	}
	if(ins == 0){
		ndbfree(chain);
		for(i = 0; i < t->nrows; i++){
			if(tab_row_is_nil(t, t->rows[i])){
				t->nilrow = t->rows[i];
				return 0;
			}
		}
		tab_seterror("tab_ensure_nil_row: duplicate nil row not found");
		return -1;
	}
	return 0;
}

static TabCol *
find_col(Tab *t, const char *name)
{
	int i;

	for(i = 0; i < t->schema.ncols; i++)
		if(strcmp(t->schema.cols[i].name, name) == 0)
			return &t->schema.cols[i];
	return nil;
}

/* Construct the schema portion of a Tab from a TabColSpec array.
 * Allocates name and per-column storage.  Returns 0 on success,
 * -1 on OOM. */
static int
materialise_schema(Tab *t, const char *schema_name,
	const TabColSpec *cols, int ncols)
{
	int i, na, k;

	t->schema.name = strdup((char *)schema_name);
	if(t->schema.name == nil){
		tab_seterror("tab_create: out of memory for schema name");
		return -1;
	}
	if(ncols <= 0){
		tab_seterror("tab_create: schema %q declares no columns",
			schema_name);
		return -1;
	}
	t->schema.cols = mallocz(ncols * sizeof *t->schema.cols, 1);
	if(t->schema.cols == nil){
		tab_seterror("tab_create: out of memory for columns");
		return -1;
	}
	for(i = 0; i < ncols; i++){
		TabCol *out = &t->schema.cols[i];
		if(cols[i].name == nil || cols[i].name[0] == '\0'){
			tab_seterror("tab_create: empty column name");
			return -1;
		}
		if(!schema_type_ok(cols[i].type)){
			tab_seterror("tab_create: column %q has unsupported type %q",
				cols[i].name, cols[i].type);
			return -1;
		}
		for(k = 0; k < i; k++){
			if(strcmp(cols[k].name, cols[i].name) == 0){
				tab_seterror("tab_create: duplicate column %q",
					cols[i].name);
				return -1;
			}
		}
		out->name = strdup((char *)cols[i].name);
		if(out->name == nil){
			tab_seterror("tab_create: out of memory for col name");
			return -1;
		}
		if(cols[i].type != nil){
			out->type = strdup((char *)cols[i].type);
			if(out->type == nil){
				tab_seterror("tab_create: out of memory for type");
				return -1;
			}
		}

		na = 0;
		if(cols[i].algo != nil) na++;
		if(cols[i].signer != nil) na++;
		if(na > 0){
			out->attrs = mallocz(na * sizeof *out->attrs, 1);
			if(out->attrs == nil){
				tab_seterror("tab_create: out of memory for attrs");
				return -1;
			}
			k = 0;
			if(cols[i].algo != nil){
				out->attrs[k].key = strdup("algo");
				out->attrs[k].val = strdup((char *)cols[i].algo);
				if(out->attrs[k].key == nil ||
				   out->attrs[k].val == nil){
					tab_seterror("tab_create: out of memory");
					return -1;
				}
				k++;
			}
			if(cols[i].signer != nil){
				out->attrs[k].key = strdup("signer");
				out->attrs[k].val = strdup((char *)cols[i].signer);
				if(out->attrs[k].key == nil ||
				   out->attrs[k].val == nil){
					tab_seterror("tab_create: out of memory");
					return -1;
				}
				k++;
			}
			out->nattrs = k;
		}
		t->schema.ncols++;
	}
	return 0;
}

Tab *
tab_create(const char *path, const char *schema_name,
	const TabColSpec *cols, int ncols)
{
	Tab *t;

	tab_clearerror();
	if(path == nil || *path == '\0' || schema_name == nil ||
	   schema_name[0] == '\0' || cols == nil){
		tab_seterror("tab_create: nil/empty argument");
		return nil;
	}
	t = mallocz(sizeof *t, 1);
	if(t == nil){
		tab_seterror("tab_create: out of memory for Tab");
		return nil;
	}
	t->path = strdup((char *)path);
	if(t->path == nil){
		tab_seterror("tab_create: out of memory for path");
		free(t);
		return nil;
	}
	if(materialise_schema(t, schema_name, cols, ncols) < 0){
		tab_close(t);
		return nil;
	}
	if(tab_ensure_nil_row(t) < 0){
		tab_close(t);
		return nil;
	}
	/* Fresh table: nothing on disk yet.  No ndb handle.  tab_commit
	 * will create the file via the existing serializer+persister. */
	t->dirty = 1;	/* an empty schema-only file is itself a commit */
	return t;
}

TabRow *
tab_add_row(Tab *t, const char *head_attr, const char *head_val)
{
	Ndbtuple *chain;
	int ins, i;
	TabRow *r;
	TabCol *schema_col;

	tab_clearerror();
	if(t == nil || head_attr == nil || head_val == nil){
		tab_seterror("tab_add_row: nil argument");
		return nil;
	}
	if(head_attr[0] == '\0' || head_val[0] == '\0' ||
	   strcmp(head_val, "nil") == 0){
		tab_seterror("tab_add_row: empty or reserved row name");
		return nil;
	}
	schema_col = find_col(t, head_attr);
	if(schema_col == nil){
		tab_seterror("tab_add_row: head column %q not in schema",
			head_attr);
		return nil;
	}
	if(schema_col->type != nil){
		tab_seterror("tab_add_row: head column %q is typed %q",
			head_attr, schema_col->type);
		return nil;
	}
	chain = ndbnew((char *)head_attr, (char *)head_val);
	if(chain == nil){
		tab_seterror("tab_add_row: ndbnew failed");
		return nil;
	}
	ins = tab_rowmap_insert(t, chain);
	if(ins < 0){
		ndbfree(chain);
		return nil;
	}
	if(ins == 0){
		/* Already-present row.  Return the existing one. */
		ndbfree(chain);
		for(i = 0; i < t->nrows; i++){
			if(tab_row_cell(t->rows[i]->chain, head_attr) != nil &&
			   strcmp(tab_row_cell(t->rows[i]->chain, head_attr),
			          head_val) == 0){
				return t->rows[i];
			}
		}
		tab_seterror("tab_add_row: dedup but cannot locate match");
		return nil;
	}
	r = t->rows[t->nrows - 1];
	t->dirty = 1;
	return r;
}

int
tab_set(Tab *t, TabRow *r, const char *col, const char *value)
{
	Ndbtuple *tup, *last, *newtup;
	char *saved_inline, *saved_heap;
	const char *store;
	TabCol *schema_col;
	int rh;

	tab_clearerror();
	if(t == nil || r == nil || col == nil){
		tab_seterror("tab_set: nil argument");
		return -1;
	}
	store = value != nil ? value : "nil";
	schema_col = find_col(t, col);
	if(schema_col == nil){
		tab_seterror("tab_set: column %q not in schema", col);
		return -1;
	}
	if(schema_col->type != nil){
		tab_seterror("tab_set: column %q is typed %q; use typed setter",
			col, schema_col->type);
		return -1;
	}
	if(t->schema.ncols > 0 && strcmp(col, t->schema.cols[0].name) == 0 &&
	   (store[0] == '\0' || strcmp(store, "nil") == 0)){
		tab_seterror("tab_set: empty or reserved row name");
		return -1;
	}

	/* Find existing cell; if absent, append a fresh tuple. */
	tup = nil;
	last = nil;
	{
		Ndbtuple *p;
		for(p = r->chain; p != nil; p = p->entry){
			if(strcmp(p->attr, col) == 0){
				tup = p;
				break;
			}
			last = p;
		}
	}

	if(tup == nil){
		/* Append. */
		newtup = ndbnew((char *)col, (char *)store);
		if(newtup == nil){
			tab_seterror("tab_set: ndbnew failed");
			return -1;
		}
		if(last == nil){
			/* Should never happen — r->chain is always non-nil. */
			ndbfree(newtup);
			tab_seterror("tab_set: row has no head tuple");
			return -1;
		}
		last->entry = newtup;
		rh = tab_rowmap_rehash(t, r->chain);
		if(rh == 0){
			t->dirty = 1;
			return 0;
		}
		/* Collision or error — unlink and free. */
		last->entry = nil;
		ndbfree(newtup);
		return -1;
	}

	/* Existing cell — replace with snapshot/restore on collision.
	 * Mirrors mutate_cell in tab_hashed.c and tab_signed.c. */
	saved_inline = nil;
	saved_heap = nil;
	if(tup->val == tup->valbuf){
		saved_inline = strdup(tup->valbuf);
		if(saved_inline == nil){
			tab_seterror("tab_set: out of memory snapshotting");
			return -1;
		}
	}else{
		saved_heap = tup->val;
		tup->val = tup->valbuf;
	}
	ndbsetval(tup, (char *)store, strlen(store));
	rh = tab_rowmap_rehash(t, r->chain);
	if(rh == 0){
		t->dirty = 1;
		free(saved_inline);
		free(saved_heap);
		return 0;
	}
	if(tup->val != tup->valbuf)
		free(tup->val);
	if(saved_heap != nil){
		tup->val = saved_heap;
	}else{
		tup->val = tup->valbuf;
		ndbsetval(tup, saved_inline, strlen(saved_inline));
		free(saved_inline);
	}
	return -1;
}

int
tab_clear(Tab *t, TabRow *r, const char *col)
{
	Ndbtuple *victim, **link;
	TabCol *schema_col;
	int rh;

	tab_clearerror();
	if(t == nil || r == nil || col == nil){
		tab_seterror("tab_clear: nil argument");
		return -1;
	}
	schema_col = find_col(t, col);
	if(schema_col == nil){
		tab_seterror("tab_clear: column %q not in schema", col);
		return -1;
	}
	if(t->schema.ncols > 0 && strcmp(col, t->schema.cols[0].name) == 0){
		tab_seterror("tab_clear: cannot clear row identity column %q", col);
		return -1;
	}

	link = &r->chain;
	while(*link != nil && strcmp((*link)->attr, col) != 0)
		link = &(*link)->entry;
	if(*link == nil)
		return 0;

	victim = *link;
	*link = victim->entry;
	victim->entry = nil;

	rh = tab_rowmap_rehash(t, r->chain);
	if(rh == 0){
		t->dirty = 1;
		ndbfree(victim);
		return 0;
	}

	victim->entry = *link;
	*link = victim;
	return -1;
}

int
tab_remove_row(Tab *t, TabRow *r)
{
	Ndbtuple *p;

	tab_clearerror();
	if(t == nil || r == nil || r == t->nilrow){
		tab_seterror("tab_remove_row: invalid row");
		return -1;
	}
	if(tab_ensure_nil_row(t) < 0)
		return -1;
	for(p = r->chain; p != nil; p = p->entry)
		ndbsetval(p, "nil", 3);
	if(!tab_row_is_nil(t, r)){
		tab_seterror("tab_remove_row: row did not collapse to nil");
		return -1;
	}
	if(tab_rowmap_delete(t, r) < 0)
		return -1;
	t->dirty = 1;
	return 0;
}
