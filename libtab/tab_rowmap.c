/*
 * libtab — row-hash map and search.
 *
 * Every loaded row gets a content hash, computed in schema-column
 * order over a TSV canonical form:
 *
 *	cell0 \t cell1 \t … \t celln
 *
 * An empty cell — whether the on-disk row omits the column or writes
 * it with no value — contributes a single null byte (\0) where its
 * value would go.  Two rows hash the same iff they have the same
 * (schema-ordered) cells.
 *
 * The map is the only index libtab keeps.  Search is a scan over the
 * row list filtered by (col, value).  Inserts that hit an existing
 * hash are dropped — duplicates by definition.
 */

#include "tab_internal.h"

enum {
	HashMinBuckets	= 16,
	RowsInitCap	= 16,
};

/* FNV-1a 32-bit over a byte range. */
uint32_t
tab_hash_bytes(const uint8_t *p, int n)
{
	uint32_t h = 0x811c9dc5u;
	int i;

	for(i = 0; i < n; i++){
		h ^= p[i];
		h *= 0x01000193u;
	}
	return h;
}

static uint32_t
nextpow2(uint32_t n)
{
	uint32_t v = HashMinBuckets;
	while(v < n)
		v <<= 1;
	return v;
}

/* Build the canonical TSV bytes for `chain` in schema-column order.
 * Returns a malloc'd buffer of length *lenout, or nil on OOM. */
static uint8_t *
canonical_bytes(Tab *t, Ndbtuple *chain, int *lenout)
{
	int i, total, off, vlen;
	const char *val;
	uint8_t *buf;

	total = 0;
	for(i = 0; i < t->schema.ncols; i++){
		val = tab_row_cell(chain, t->schema.cols[i].name);
		total += (val != nil && *val != '\0') ? (int)strlen(val) : 1;
		if(i + 1 < t->schema.ncols)
			total++;	/* tab separator */
	}
	if(total < 1)
		total = 1;
	buf = malloc(total);
	if(buf == nil){
		tab_seterror("tab_open: out of memory for canonical form");
		return nil;
	}
	off = 0;
	for(i = 0; i < t->schema.ncols; i++){
		val = tab_row_cell(chain, t->schema.cols[i].name);
		if(val != nil && *val != '\0'){
			vlen = strlen(val);
			memcpy(buf + off, val, vlen);
			off += vlen;
		}else{
			buf[off++] = 0;	/* null cell */
		}
		if(i + 1 < t->schema.ncols)
			buf[off++] = '\t';
	}
	*lenout = off;
	return buf;
}

/* Allocate the bucket array, sized for the expected row count. */
static int
ensure_buckets(Tab *t, int target_rows)
{
	uint32_t nb;

	if(t->buckets != nil)
		return 0;
	nb = nextpow2(target_rows > 0 ? (uint32_t)target_rows * 2 : HashMinBuckets);
	t->buckets = mallocz(nb * sizeof *t->buckets, 1);
	if(t->buckets == nil){
		tab_seterror("tab_open: out of memory for row-hash buckets");
		return -1;
	}
	t->mask = nb - 1;
	return 0;
}

/* Does an entry with this hash + canonical bytes already exist? */
static int
already_present(Tab *t, uint32_t h, const uint8_t *cbuf, int clen)
{
	TabRow *e;
	int elen;
	uint8_t *ebuf;
	int eq;

	for(e = t->buckets[h & t->mask]; e != nil; e = e->next){
		if(e->hash != h)
			continue;
		ebuf = canonical_bytes(t, e->chain, &elen);
		if(ebuf == nil)
			return -1;
		eq = (elen == clen && memcmp(ebuf, cbuf, clen) == 0);
		free(ebuf);
		if(eq)
			return 1;
	}
	return 0;
}

/* Append a TabRow to t->rows[] (the source-order list). */
static int
push_row(Tab *t, TabRow *e)
{
	int newcap;
	TabRow **nr;

	if(t->nrows >= t->nrows_cap){
		newcap = t->nrows_cap == 0 ? RowsInitCap : t->nrows_cap * 2;
		nr = realloc(t->rows, newcap * sizeof *nr);
		if(nr == nil){
			tab_seterror("tab_open: out of memory growing rows");
			return -1;
		}
		t->rows = nr;
		t->nrows_cap = newcap;
	}
	t->rows[t->nrows++] = e;
	return 0;
}

/* Try to insert a parsed row.  Returns 1 if inserted, 0 if dropped as
 * a duplicate, -1 on error. */
int
tab_rowmap_insert(Tab *t, Ndbtuple *chain)
{
	uint8_t *cbuf;
	int clen, dup;
	uint32_t h;
	TabRow *e;

	if(ensure_buckets(t, 0) < 0)
		return -1;

	cbuf = canonical_bytes(t, chain, &clen);
	if(cbuf == nil)
		return -1;
	h = tab_hash_bytes(cbuf, clen);

	dup = already_present(t, h, cbuf, clen);
	free(cbuf);
	if(dup < 0)
		return -1;
	if(dup == 1)
		return 0;	/* duplicate — caller frees chain */

	e = malloc(sizeof *e);
	if(e == nil){
		tab_seterror("tab_open: out of memory for entry");
		return -1;
	}
	e->hash = h;
	e->chain = chain;
	e->next = t->buckets[h & t->mask];
	t->buckets[h & t->mask] = e;
	t->nentries++;

	if(push_row(t, e) < 0){
		t->buckets[h & t->mask] = e->next;
		free(e);
		t->nentries--;
		return -1;
	}
	return 1;
}

/* Re-hash an existing row after one of its cells changed.
 *
 * Returns 0 on success (entry moved from its old bucket to the new
 * one matching the row's new content hash).  Returns 1 on collision:
 * a different row already has the new canonical content, so the
 * mutation would create a duplicate and the caller must revert their
 * change.  Returns -1 on error (OOM, chain not in the map).
 *
 * The single point where in-memory row mutation re-establishes the
 * row-hash invariant.  Every tab_set_* call routes through here. */
int
tab_rowmap_rehash(Tab *t, Ndbtuple *chain)
{
	int i, clen, elen, eq;
	uint8_t *cbuf, *ebuf;
	uint32_t h_new;
	TabRow *self, *e, **prev;

	self = nil;
	for(i = 0; i < t->nrows; i++){
		if(t->rows[i]->chain == chain){
			self = t->rows[i];
			break;
		}
	}
	if(self == nil){
		tab_seterror("tab_rowmap_rehash: chain not in map");
		return -1;
	}

	cbuf = canonical_bytes(t, chain, &clen);
	if(cbuf == nil)
		return -1;
	h_new = tab_hash_bytes(cbuf, clen);

	if(h_new == self->hash){
		/* Possible no-op (or 32-bit hash collision against the row's
		 * own old hash).  Either way nothing to move. */
		free(cbuf);
		return 0;
	}

	for(e = t->buckets[h_new & t->mask]; e != nil; e = e->next){
		if(e == self) continue;
		if(e->hash != h_new) continue;
		ebuf = canonical_bytes(t, e->chain, &elen);
		if(ebuf == nil){
			free(cbuf);
			return -1;
		}
		eq = (elen == clen && memcmp(ebuf, cbuf, clen) == 0);
		free(ebuf);
		if(eq){
			free(cbuf);
			tab_seterror("tab_rowmap_rehash: mutation would "
				"create a duplicate of an existing row");
			return 1;
		}
	}
	free(cbuf);

	prev = &t->buckets[self->hash & t->mask];
	while(*prev != nil && *prev != self)
		prev = &(*prev)->next;
	if(*prev == self)
		*prev = self->next;

	self->hash = h_new;
	self->next = t->buckets[h_new & t->mask];
	t->buckets[h_new & t->mask] = self;
	return 0;
}

void
tab_index_freeall(Tab *t)
{
	int i;

	if(t == nil)
		return;
	for(i = 0; i < t->nrows; i++){
		ndbfree(t->rows[i]->chain);
		free(t->rows[i]);
	}
	free(t->rows);
	free(t->buckets);
	t->rows = nil;
	t->buckets = nil;
	t->nrows = 0;
	t->nrows_cap = 0;
	t->nentries = 0;
	t->mask = 0;
}

/* Public: scan-with-filter. */
TabIter *
tab_search(Tab *t, const char *col, const char *value)
{
	TabIter *it;

	tab_clearerror();
	if(t == nil || col == nil || value == nil){
		tab_seterror("tab_search: nil argument");
		return nil;
	}
	it = mallocz(sizeof *it, 1);
	if(it == nil){
		tab_seterror("tab_search: out of memory");
		return nil;
	}
	it->t = t;
	it->idx = 0;
	it->col = strdup((char *)col);
	it->value = strdup((char *)value);
	if(it->col == nil || it->value == nil){
		tab_seterror("tab_search: out of memory");
		free(it->col);
		free(it->value);
		free(it);
		return nil;
	}
	return it;
}
