/*
 * libtab — internal layout shared across compilation units.
 * Not installed; libtab consumers see only libtab.h.
 *
 * Storage model: every loaded row is keyed in memory by a hash of its
 * canonical TSV form (cells in schema-column order, separated by '\t',
 * empty cells represented as a single null byte).  Two rows with the
 * same hash are the same row by definition — the second load is a
 * no-op.  There are no per-column secondary indexes; search is a scan
 * over the row-hash map filtered by (col, value).
 */

#ifndef _LIBTAB_INTERNAL_H_
#define _LIBTAB_INTERNAL_H_

#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ndb.h>
#include "libtab.h"

#ifndef __GNUC__
typedef u32int uint32_t;
typedef uchar uint8_t;
#endif

/* A schema attribute: every `key=value` pair that appeared on the
 * same source line as a `col=` tuple, except `col` and `type` which
 * get their own slots on TabCol.  E.g. for
 *	col=pwhash type=HASHED algo=argon2id signer=hostowner
 * a TabCol gets `name=pwhash`, `type=HASHED`, and an `attrs` list of
 * [(algo, argon2id), (signer, hostowner)]. */
typedef struct TabAttr TabAttr;
struct TabAttr {
	char *key;
	char *val;
};

/* Per-column metadata extracted from the `schema=<name>` tuple. */
typedef struct TabCol TabCol;
struct TabCol {
	char *name;	/* `col=` value; never nil */
	char *type;	/* `type=` value; nil if untyped (plain text) */
	int nattrs;
	TabAttr *attrs;	/* heap; length = nattrs; nil if zero */
};

struct TabSchema {
	char *name;	/* mandatory `schema=<name>` */
	int ncols;
	TabCol *cols;	/* heap; length = ncols */
};

/* One row in the in-memory map.  `hash` is the row's content hash;
 * `chain` is the libndb tuple chain we kept alive from ndbparse.
 *
 * This struct *is* the public TabRow — consumers hold pointers to
 * these objects directly.  Lifetime is the Tab's lifetime, not the
 * iterator's.  An iterator is purely a cursor over t->rows[]. */
struct TabRow {
	uint32_t hash;
	Ndbtuple *chain;
	struct TabRow *next;	/* hash-bucket chain (collision resolution only) */
};

struct Tab {
	char *path;	/* local file the read parser uses */
	char *dial;	/* 9P dial-string, or nil for POSIX persistence */
	char *remote_path;	/* 9P-side path for tab_commit; nil → use t->path */
	Ndb *db;	/* the underlying ndb handle */
	TabSchema schema;
	int dirty;	/* set by any successful mutation; cleared by tab_commit */

	/* The one and only index: row-hash bucket array.  Power-of-two
	 * size so we can mask instead of mod.  Collisions chain by
	 * 32-bit hash equality and full-byte canonical compare. */
	uint32_t mask;	/* nbuckets - 1 */
	TabRow **buckets;
	int nentries;
	int nbuckets_target;	/* desired entries for next resize threshold */

	/* Linear list of every loaded row, in source order.  This is
	 * what iterators walk.  The bucket array points into the same
	 * row objects. */
	int nrows;
	int nrows_cap;
	TabRow **rows;
};

struct TabIter {
	Tab *t;
	int idx;		/* next position in t->rows[] to consider */
	/* For filtered iteration (tab_search): the predicate is (col, value).
	 * Nil col == unfiltered scan. */
	char *col;
	char *value;
};

/* Internal helper: fetch a cell value from an Ndbtuple chain by column.
 * Used by tab_get (public) and the canonical-form builder. */
const char *tab_row_cell(Ndbtuple *head, const char *col);

/* FNV-1a 32-bit hash over a byte range. */
uint32_t tab_hash_bytes(const uint8_t *p, int n);

/* Drop every TabEntry attached to t; called from tab_close. */
void tab_index_freeall(Tab *t);

/* Set / fetch the thread-local error buffer. */
void tab_seterror(const char *fmt, ...);
void tab_clearerror(void);

/* Internal helper: look up a schema attribute on column `col_idx`.
 * Returns nil if not present. */
const char *tab_col_attr_internal(Tab *t, int col_idx, const char *key);

/* Serialise the in-memory Tab to ndb-shaped text.  Returns a malloc'd
 * NUL-terminated buffer; *outlen receives the length excluding the
 * terminator.  Caller frees.  Returns nil on OOM. */
char *tab_serialize(Tab *t, int *outlen);

#endif /* _LIBTAB_INTERNAL_H_ */
