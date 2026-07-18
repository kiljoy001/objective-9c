/*
 * libtab — serialise an in-memory Tab back to ndb-shaped text.
 *
 * Emits, in this order:
 *
 *	schema=<name>
 *	\tcol=<col0_name>  [type=<col0_type>]  [<k>=<v>]...
 *	\tcol=<col1_name>  [type=<col1_type>]  [<k>=<v>]...
 *	                                          ← blank line
 *	<head_attr>=<head_val>                   ← first row, head on left margin
 *	\t<attr>=<val>
 *	\t<attr>=<val>
 *	                                          ← blank line
 *	<head_attr>=<head_val>                   ← next row
 *	...
 *
 * Rows are emitted in source order (the t->rows[] order, which is the
 * order tab_open observed them — minus any dedup'd duplicates).  Each
 * row's head is its first tuple in chain order; remaining tuples
 * indent with one '\t'.  Values that are empty strings emit as
 * `attr=` with nothing after.
 *
 * Comments on disk are lost on round-trip — libndb's parser doesn't
 * preserve them.  Schemas with no rows still emit the schema= entry
 * plus the trailing blank line.
 */

#include "tab_internal.h"

/* Grow a buffer in-place; appends `n` bytes from `p` to `*buf` (which
 * has current length `*len` and capacity `*cap`).  Reallocates as
 * needed.  Returns 0 on success, -1 on OOM. */
static int
buf_append(char **buf, int *len, int *cap, const char *p, int n)
{
	int need = *len + n;
	if(need > *cap){
		int newcap = *cap > 0 ? *cap : 256;
		while(newcap < need)
			newcap *= 2;
		char *nb = realloc(*buf, newcap);
		if(nb == nil){
			tab_seterror("tab_serialize: out of memory (need %d)", need);
			return -1;
		}
		*buf = nb;
		*cap = newcap;
	}
	memcpy(*buf + *len, p, n);
	*len += n;
	return 0;
}

static int
buf_append_str(char **buf, int *len, int *cap, const char *s)
{
	return buf_append(buf, len, cap, s, strlen(s));
}

static int
buf_append_c(char **buf, int *len, int *cap, char c)
{
	return buf_append(buf, len, cap, &c, 1);
}

/* Emit `attr=val`, where val is the literal text.  No quoting yet —
 * libndb's parser handles unquoted whitespace-free values, which is
 * what every cell in our schema-bound tables looks like.  Cells with
 * embedded whitespace are not supported by the current write path;
 * they're not supported by the read path either (tab-separated TSV
 * canonical form), so the symmetry is correct. */
static int
emit_kv(char **buf, int *len, int *cap, const char *attr, const char *val)
{
	if(buf_append_str(buf, len, cap, attr) < 0) return -1;
	if(buf_append_c(buf, len, cap, '=') < 0) return -1;
	if(val != nil && *val != 0){
		if(buf_append_str(buf, len, cap, val) < 0) return -1;
	}
	return 0;
}

/* Emit the schema= entry plus all column declarations.  Each column
 * lands on its own continuation line. */
static int
emit_schema(Tab *t, char **buf, int *len, int *cap)
{
	int i, j;

	if(emit_kv(buf, len, cap, "schema", t->schema.name) < 0) return -1;
	if(buf_append_c(buf, len, cap, '\n') < 0) return -1;

	for(i = 0; i < t->schema.ncols; i++){
		TabCol *c = &t->schema.cols[i];
		if(buf_append_c(buf, len, cap, '\t') < 0) return -1;
		if(emit_kv(buf, len, cap, "col", c->name) < 0) return -1;
		if(c->type != nil){
			if(buf_append_c(buf, len, cap, ' ') < 0) return -1;
			if(emit_kv(buf, len, cap, "type", c->type) < 0) return -1;
		}
		for(j = 0; j < c->nattrs; j++){
			if(buf_append_c(buf, len, cap, ' ') < 0) return -1;
			if(emit_kv(buf, len, cap, c->attrs[j].key,
				c->attrs[j].val) < 0) return -1;
		}
		if(buf_append_c(buf, len, cap, '\n') < 0) return -1;
	}
	return 0;
}

/* Emit one row.  First tuple in the chain is the head (left margin);
 * the rest indent with a single '\t'. */
static int
emit_row(Ndbtuple *chain, char **buf, int *len, int *cap)
{
	Ndbtuple *tp;
	int first = 1;

	for(tp = chain; tp != nil; tp = tp->entry){
		if(!first){
			if(buf_append_c(buf, len, cap, '\t') < 0) return -1;
		}
		if(emit_kv(buf, len, cap, tp->attr, tp->val) < 0) return -1;
		if(buf_append_c(buf, len, cap, '\n') < 0) return -1;
		first = 0;
	}
	return 0;
}

/* Build the full serialised text into a freshly-allocated NUL-
 * terminated buffer.  Returns the buffer (caller frees) and writes
 * its length-without-the-terminator into *outlen.  Returns nil on
 * OOM. */
char *
tab_serialize(Tab *t, int *outlen)
{
	char *buf = nil;
	int len = 0, cap = 0;
	int i;

	tab_clearerror();
	if(t == nil){
		tab_seterror("tab_serialize: nil Tab");
		return nil;
	}

	if(emit_schema(t, &buf, &len, &cap) < 0)
		goto fail;
	if(buf_append_c(&buf, &len, &cap, '\n') < 0)
		goto fail;

	for(i = 0; i < t->nrows; i++){
		if(emit_row(t->rows[i]->chain, &buf, &len, &cap) < 0)
			goto fail;
		if(buf_append_c(&buf, &len, &cap, '\n') < 0)
			goto fail;
	}

	/* NUL-terminate for callers that want to treat it as a C string;
	 * outlen does not include the terminator. */
	if(buf_append_c(&buf, &len, &cap, 0) < 0)
		goto fail;
	*outlen = len - 1;
	return buf;

fail:
	free(buf);
	return nil;
}
