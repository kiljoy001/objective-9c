/*
 * tab_open — open a libtab file, parse the mandatory schema= tuple,
 * read every row into memory for later iteration.
 *
 * Files are ndb-shaped on disk; we lean on libndb for the parser.
 * The first entry must be `schema=<name>` and declares the table's
 * columns.  Every subsequent entry is a row.  Row cells outside the
 * declared schema are rejected; libtab is a small table store, not an
 * ad-hoc key/value file reader.
 *
 * We read the whole file at open, validate each row against the schema,
 * and keep rows in memory for iteration, mutation, and commit.
 */

#include "tab_internal.h"

/* Defined in tab_rowmap.c. */
int tab_rowmap_insert(Tab *t, Ndbtuple *chain);

static int
schema_col_index(Tab *t, const char *name)
{
	int i;

	for(i = 0; i < t->schema.ncols; i++)
		if(strcmp(t->schema.cols[i].name, name) == 0)
			return i;
	return -1;
}

static int
schema_type_ok(const char *type)
{
	if(type == nil)
		return 1;
	return strcmp(type, "HASHED") == 0 || strcmp(type, "SIGNED") == 0;
}

/* Walk an entry's tuple chain looking for the next `col=` tuple.
 * Returns 1 if found and advances *ptp past it (so the next call
 * resumes from the following tuple).  Returns 0 at end of chain.
 *
 * `*col_tuple_out` is set to the `col=` tuple itself so the caller
 * can walk its ->line ring to collect sibling attributes.  In ndb,
 * tuples on the same source line form a ring via ->line linking back
 * to the head tuple.  We use the ring (not the entry chain) to find
 * attributes that belong to *this* column rather than to a later one. */
static int
next_col(Ndbtuple **ptp, Ndbtuple **col_tuple_out)
{
	Ndbtuple *t;

	for(t = *ptp; t != nil; t = t->entry){
		if(strcmp(t->attr, "col") == 0){
			*col_tuple_out = t;
			*ptp = t->entry;
			return 1;
		}
	}
	*ptp = nil;
	return 0;
}

/* For a given `col=` tuple, walk the same-line ring and call back
 * for every sibling attribute (i.e. everything on that line except
 * the `col=` tuple itself).  `type=` is recognised by the schema
 * extractor; everything else lands in TabCol.attrs[]. */
static int
collect_col_metadata(Ndbtuple *coltup, TabCol *out)
{
	Ndbtuple *line;
	int nattrs, i;

	out->name = strdup(coltup->val);
	out->type = nil;
	out->nattrs = 0;
	out->attrs = nil;
	if(out->name == nil){
		tab_seterror("tab_open: out of memory for column name");
		return -1;
	}

	/* First pass: count non-col, non-type siblings on the line ring. */
	nattrs = 0;
	for(line = coltup->line; line != nil && line != coltup; line = line->line){
		if(strcmp(line->attr, "col") == 0)
			continue;
		if(strcmp(line->attr, "type") == 0)
			continue;
		nattrs++;
	}

	if(nattrs > 0){
		out->attrs = mallocz(nattrs * sizeof *out->attrs, 1);
		if(out->attrs == nil){
			tab_seterror("tab_open: out of memory for column attrs");
			return -1;
		}
	}

	/* Second pass: capture type and the attrs. */
	i = 0;
	for(line = coltup->line; line != nil && line != coltup; line = line->line){
		if(strcmp(line->attr, "col") == 0)
			continue;
		if(strcmp(line->attr, "type") == 0){
			out->type = strdup(line->val);
			if(out->type == nil){
				tab_seterror("tab_open: out of memory for type");
				return -1;
			}
			continue;
		}
		out->attrs[i].key = strdup(line->attr);
		out->attrs[i].val = strdup(line->val);
		if(out->attrs[i].key == nil || out->attrs[i].val == nil){
			tab_seterror("tab_open: out of memory for attr %d", i);
			return -1;
		}
		i++;
	}
	out->nattrs = i;
	return 0;
}

/* Parse a `schema=<name>` entry into t->schema.  Caller owns the entry
 * chain (still in libndb's allocator), but we only need name+type+attr
 * strings; we copy them so the entry can be ndbfree'd by the caller. */
static int
extract_schema(Tab *t, Ndbtuple *entry)
{
	Ndbtuple *cur, *coltup;
	int n;

	t->schema.name = strdup(entry->val);
	if(t->schema.name == nil){
		tab_seterror("tab_open: out of memory for schema name");
		return -1;
	}
	if(t->schema.name[0] == '\0'){
		tab_seterror("tab_open: empty schema name");
		return -1;
	}

	/* Count columns first. */
	cur = entry->entry;
	n = 0;
	while(next_col(&cur, &coltup))
		n++;

	if(n == 0){
		tab_seterror("tab_open: schema %q declares no columns",
			t->schema.name);
		return -1;
	}

	t->schema.cols = mallocz(n * sizeof *t->schema.cols, 1);
	if(t->schema.cols == nil){
		tab_seterror("tab_open: out of memory for columns");
		return -1;
	}

	cur = entry->entry;
	t->schema.ncols = 0;
	while(next_col(&cur, &coltup)){
		if(collect_col_metadata(coltup,
			&t->schema.cols[t->schema.ncols]) < 0)
			return -1;
		if(t->schema.cols[t->schema.ncols].name[0] == '\0'){
			tab_seterror("tab_open: schema %q has empty column name",
				t->schema.name);
			return -1;
		}
		if(!schema_type_ok(t->schema.cols[t->schema.ncols].type)){
			tab_seterror("tab_open: column %q has unsupported type %q",
				t->schema.cols[t->schema.ncols].name,
				t->schema.cols[t->schema.ncols].type);
			return -1;
		}
		for(n = 0; n < t->schema.ncols; n++){
			if(strcmp(t->schema.cols[n].name,
			    t->schema.cols[t->schema.ncols].name) == 0){
				tab_seterror("tab_open: duplicate column %q",
					t->schema.cols[t->schema.ncols].name);
				return -1;
			}
		}
		t->schema.ncols++;
	}
	return 0;
}

static int
validate_row(Tab *t, Ndbtuple *entry)
{
	Ndbtuple *tp;
	int idx;

	for(tp = entry; tp != nil; tp = tp->entry){
		idx = schema_col_index(t, tp->attr);
		if(idx < 0){
			tab_seterror("tab_open: row %d has undeclared column %q",
				t->nrows, tp->attr);
			return -1;
		}
		if(t->schema.cols[idx].type != nil && tp->val != nil &&
		   tp->val[0] != '\0' &&
		   !tab_cell_has_tag(tp->val, t->schema.cols[idx].type)){
			tab_seterror("tab_open: row %d column %q missing %q "
				"tag (got %q)", t->nrows,
				t->schema.cols[idx].name,
				t->schema.cols[idx].type, tp->val);
			return -1;
		}
	}
	return 0;
}

Tab *
tab_open(const char *path)
{
	return tab_open_dial(path, nil, nil);
}

Tab *
tab_open_dial(const char *path, const char *dial, const char *remote_path)
{
	Tab *t;
	Ndbtuple *entry;
	int got_schema = 0;

	tab_clearerror();

	if(path == nil || *path == '\0'){
		tab_seterror("tab_open: empty path");
		return nil;
	}

	t = mallocz(sizeof *t, 1);
	if(t == nil){
		tab_seterror("tab_open: out of memory for Tab");
		return nil;
	}
	t->path = strdup((char *)path);
	if(t->path == nil){
		tab_seterror("tab_open: out of memory for path");
		free(t);
		return nil;
	}
	if(dial != nil){
		t->dial = strdup((char *)dial);
		if(t->dial == nil){
			tab_seterror("tab_open: out of memory for dial");
			free(t->path);
			free(t);
			return nil;
		}
	}
	if(remote_path != nil){
		t->remote_path = strdup((char *)remote_path);
		if(t->remote_path == nil){
			tab_seterror("tab_open: out of memory for remote_path");
			free(t->dial);
			free(t->path);
			free(t);
			return nil;
		}
	}

	t->db = ndbopen((char *)path);
	if(t->db == nil){
		tab_seterror("tab_open: ndbopen %s: %r", path);
		free(t->remote_path);
		free(t->dial);
		free(t->path);
		free(t);
		return nil;
	}

	/* Walk every entry.  The first tuple must be the schema
	 * declaration; the rest are rows validated against it. */
	for(;;){
		entry = ndbparse(t->db);
		if(entry == nil)
			break;
		if(!got_schema){
			if(strcmp(entry->attr, "schema") != 0){
				tab_seterror("tab_open: first tuple must be schema=, got %q",
					entry->attr);
				ndbfree(entry);
				goto fail;
			}
			if(extract_schema(t, entry) < 0){
				ndbfree(entry);
				goto fail;
			}
			ndbfree(entry);
			got_schema = 1;
			continue;
		}
		if(validate_row(t, entry) < 0){
			ndbfree(entry);
			goto fail;
		}

		int ins = tab_rowmap_insert(t, entry);
		if(ins < 0){
			ndbfree(entry);
			goto fail;
		}
		if(ins == 0){
			/* duplicate row: dedup'd by content hash. */
			ndbfree(entry);
		}
	}
	if(!got_schema){
		tab_seterror("tab_open: missing schema tuple");
		goto fail;
	}
	return t;

fail:
	tab_close(t);
	return nil;
}

/* In tab_persist.c. */
int tab_commit(Tab *t);

void
tab_close(Tab *t)
{
	int i;

	if(t == nil)
		return;
	/* Close-time auto-commit if dirty.  Errors here are reported via
	 * tab_lasterror() but cannot fail the close — the caller has
	 * already moved on.  A consumer that needs to know the flush
	 * succeeded calls tab_commit() explicitly first. */
	if(t->dirty)
		tab_commit(t);
	tab_index_freeall(t);
	if(t->schema.cols != nil){
		for(i = 0; i < t->schema.ncols; i++){
			int j;
			free(t->schema.cols[i].name);
			free(t->schema.cols[i].type);
			for(j = 0; j < t->schema.cols[i].nattrs; j++){
				free(t->schema.cols[i].attrs[j].key);
				free(t->schema.cols[i].attrs[j].val);
			}
			free(t->schema.cols[i].attrs);
		}
		free(t->schema.cols);
	}
	free(t->schema.name);
	if(t->db != nil)
		ndbclose(t->db);
	free(t->path);
	free(t->dial);
	free(t->remote_path);
	free(t);
}

const char *
tab_schema_name(Tab *t)
{
	return t->schema.name;
}

int
tab_ncolumns(Tab *t)
{
	return t->schema.ncols;
}

const char *
tab_colname(Tab *t, int idx)
{
	if(idx < 0 || idx >= t->schema.ncols)
		return nil;
	return t->schema.cols[idx].name;
}

const char *
tab_coltype(Tab *t, int idx)
{
	if(idx < 0 || idx >= t->schema.ncols)
		return nil;
	return t->schema.cols[idx].type;
}

const char *
tab_col_attr_internal(Tab *t, int idx, const char *key)
{
	int j;
	TabCol *c;
	if(idx < 0 || idx >= t->schema.ncols || key == nil)
		return nil;
	c = &t->schema.cols[idx];
	for(j = 0; j < c->nattrs; j++){
		if(strcmp(c->attrs[j].key, key) == 0)
			return c->attrs[j].val;
	}
	return nil;
}

const char *
tab_col_attr(Tab *t, const char *col, const char *key)
{
	int i;
	if(t == nil || col == nil)
		return nil;
	for(i = 0; i < t->schema.ncols; i++){
		if(strcmp(t->schema.cols[i].name, col) == 0)
			return tab_col_attr_internal(t, i, key);
	}
	return nil;
}
