/*
 * libtab — typed-table storage substrate for 9lx.
 *
 * Schema-agnostic table runtime built on plan9port's libndb for parsing.
 * Files are ndb-shaped on disk with a `schema=<name>` tuple at the top
 * declaring column names and (optionally) crypto types.  All cells are
 * printable text; cryptographic columns carry a `<type>:<base64>`
 * prefix tag for self-description.
 *
 * See references/libtab-design.md for the full design.
 *
 * Steps:
 *   Step 1: scaffolding — ndb-shaped reader + schema parse.
 *   Step 2: row-hash map (dedup at load) + tab_search.
 *   Step 3: cell tagging + base64 codec.
 *   Step 4: HASHED column type.
 *   Step 5: SIGNED column type.
 *   Step 6: atomic writes.
 *
 * Naming: types and entry points use the `Tab` / `tab_` prefix to keep
 * the API legible alongside libndb's `Ndb` / `ndb_`.
 */

#ifndef _LIBTAB_H_
#define _LIBTAB_H_

/* Forward declarations.  Callers see opaque pointers; the internal
 * layout lives in tab_internal.h. */
typedef struct Tab Tab;
typedef struct TabRow TabRow;
typedef struct TabIter TabIter;
typedef struct TabSchema TabSchema;

/* Column spec for tab_create.  All fields except `name` are
 * optional; pass nil to omit.  `type` is the schema-declared type
 * ("HASHED", "SIGNED", or nil for untyped); `algo` and `signer` are
 * additional schema attributes that some types use. */
typedef struct TabColSpec TabColSpec;
struct TabColSpec {
    const char *name;
    const char *type;
    const char *algo;
    const char *signer;
};

/* Create a fresh, empty Tab whose canonical path is `path` and whose
 * schema is built directly from the column specs.  The file at `path`
 * does not have to exist; tab_commit() will create it.  Use
 * tab_add_row() to populate the table.  Returns nil on failure. */
Tab *tab_create(const char *path, const char *schema_name,
                const TabColSpec *cols, int ncols);

/* Append a row whose first tuple is `head_attr=head_val`.  Returns
 * the new TabRow; set additional cells via tab_set / tab_set_hashed /
 * tab_set_signed.  Returns nil on failure (OOM, dedup-mismatch). */
TabRow *tab_add_row(Tab *t, const char *head_attr, const char *head_val);

/* Set or create an untyped (plain text) cell.  Mirrors the typed
 * setters.  Returns 0 on success, -1 on collision or error. */
int tab_set(Tab *t, TabRow *r, const char *col, const char *value);

/* Open a libtab file.  Reads the file, parses the schema= tuple if
 * present, and prepares for iteration.  Returns nil on failure;
 * errstr-style error text is available via tab_lasterror().
 *
 * tab_open is a POSIX-persistence shortcut; tab_open_dial lets the
 * caller route writes through a 9P fileserver instead.  Reads always
 * happen from the local path (the file is parsed at open time
 * regardless of how it'll be written back). */
Tab *tab_open(const char *path);
Tab *tab_open_dial(const char *path, const char *dial,
                   const char *remote_path);

/* Close a Tab and free its resources.  If the Tab is dirty (any
 * mutation since the last commit), close auto-flushes via
 * tab_commit().  Errors at the close-time flush are visible via
 * tab_lasterror but cannot fail the close — call tab_commit
 * explicitly if you need to know the flush succeeded.  Safe to pass
 * nil. */
void tab_close(Tab *t);

/* Persist the in-memory Tab.  Writes via the dial-string set at open
 * time (9P) or atomically to the local path (POSIX) when no dial was
 * given.  Returns 0 on success, -1 with errstr on failure.  Clears
 * the dirty flag on success. */
int tab_commit(Tab *t);

/* Last error message from a tab_* call.  The returned pointer is
 * valid until the next tab_* call from the same thread.  Returns
 * "no error" if the last call succeeded. */
const char *tab_lasterror(void);

/* Schema introspection.  Returns the schema name from the mandatory
 * `schema=<name>` tuple. */
const char *tab_schema_name(Tab *t);

/* Number of columns declared in the schema. */
int tab_ncolumns(Tab *t);

/* Column name at index `idx` (0-based).  Returns nil if idx is out
 * of range. */
const char *tab_colname(Tab *t, int idx);

/* Column type at index `idx`.  Returns nil if the column is untyped
 * (plain text) or if idx is out of range.  Examples: "HASHED",
 * "SIGNED". */
const char *tab_coltype(Tab *t, int idx);

/* Look up a non-`col=`/non-`type=` attribute on a schema column.
 * E.g. for `col=pwhash type=HASHED algo=argon2id`, `tab_col_attr(t,
 * "pwhash", "algo")` returns "argon2id".  Returns nil if the column
 * doesn't exist or the attribute isn't set. */
const char *tab_col_attr(Tab *t, const char *col, const char *key);

/* Iteration over rows.  tab_iter walks every loaded row in source
 * order; tab_search walks only rows whose `col` cell equals `value`.
 * Both allocate a TabIter; caller frees with tab_iter_close().
 *
 * libtab does not maintain per-column secondary indexes.  The only
 * index is the row-hash map built at tab_open time, which dedupes
 * identical rows by content hash.  Search is a linear scan; this is
 * intentional — the substrate is a table store, not a relational
 * engine. */
TabIter *tab_iter(Tab *t);
TabIter *tab_search(Tab *t, const char *col, const char *value);

/* Advance the iterator.  Returns the next row, or nil if iteration
 * is complete.  The row is owned by the iterator and remains valid
 * until the next tab_iter_next() call or tab_iter_close(). */
TabRow *tab_iter_next(TabIter *it);

/* Free the iterator. */
void tab_iter_close(TabIter *it);

/* Row access.  Returns the cell text for `col` in `r`, or nil if the
 * column is absent from the row.  Plain-text cells are returned
 * verbatim; typed cells return their on-disk tagged form.  Use
 * tab_verify_hash / tab_verify_signed for typed-column semantics. */
const char *tab_get(TabRow *r, const char *col);

/* Base64 URL-safe (RFC 4648 §5) codec, exposed for consumers writing
 * their own typed cells.  Both functions return a freshly-allocated
 * buffer the caller must free.  Returns nil on failure; see
 * tab_lasterror().  Decoder accepts standard '=' padding. */
char    *tab_b64_encode(const unsigned char *in, int n);
unsigned char *tab_b64_decode(const char *s, int *outlen);

/* Cell-tag helpers.  Typed cells live on disk as `<tag>:<base64>`
 * where <tag> is the schema column's type spelled lowercase.
 *
 *   tab_cell_has_tag(cell, "HASHED") → 1 if cell starts with "hashed:",
 *                                      0 otherwise.
 *   tab_cell_decode(cell, "HASHED",  → decoded payload bytes after the
 *                   &outlen)           tag, or nil on malformed input.
 *   tab_cell_encode("HASHED", buf,   → freshly allocated "hashed:<b64>"
 *                   n)                 cell text.
 */
int      tab_cell_has_tag(const char *cell, const char *coltype);
unsigned char *tab_cell_decode(const char *cell, const char *coltype, int *outlen);
char    *tab_cell_encode(const char *coltype, const unsigned char *in, int n);

/* HASHED column type — irreversible content digests.
 *
 *   tab_set_hashed          — BLAKE2b-256 over preimage.  Fast,
 *                              parameter-less; right for content-
 *                              addressable refs, integrity checks,
 *                              short-form digests.
 *   tab_set_hashed_argon2id — argon2id with default tuning
 *                              (m=64MiB, t=3, p=1, 16-byte salt).
 *                              Right for password hashes.  Salt and
 *                              parameters travel inline with the
 *                              digest so verify is self-contained.
 *   tab_verify_hash         — auto-detects algo from the cell header;
 *                              runs the matching primitive and
 *                              constant-time compares.  Returns 1 on
 *                              match, 0 on mismatch, -1 on error.
 *
 * All three operate on the in-memory row.  Persistence comes later. */
int tab_set_hashed(Tab *t, TabRow *r, const char *col,
                   const unsigned char *preimage, int n);
int tab_set_hashed_argon2id(Tab *t, TabRow *r, const char *col,
                            const unsigned char *preimage, int n);
int tab_verify_hash(TabRow *r, const char *col,
                    const unsigned char *preimage, int n);

/* SIGNED column type — tamper-evident body + Ed25519 signature.
 *
 *   tab_set_signed     — sign `body` with `signer_sk` (monocypher's
 *                         64-byte combined seed+pubkey form) and
 *                         store the cell as
 *                         `signed:<b64-body>:<b64-sig>`.
 *   tab_verify_signed  — decode the cell, check the signature against
 *                         `signer_pk` (32-byte Ed25519 point), return
 *                         the body bytes on success (caller frees).
 *
 * Keys are raw bytes.  Libtab does not open key files, resolve
 * symbolic principals, or take any opinion on where the bytes come
 * from.  Consumers that want a symbolic lookup read `signer=<name>`
 * off the schema column via tab_col_attr() and do the resolution
 * themselves. */
int tab_set_signed(Tab *t, TabRow *r, const char *col,
                   const unsigned char *body, int n,
                   const unsigned char signer_sk[64]);
unsigned char *tab_verify_signed(TabRow *r, const char *col,
                                 const unsigned char signer_pk[32],
                                 int *outlen);

#endif /* _LIBTAB_H_ */
