/*
 * libtab — HASHED column type.
 *
 * Wire format of a HASHED cell:
 *
 *	hashed: <base64-url-safe(
 *	            algo_id(1) ||
 *	            algo-specific parameters ||
 *	            digest(32)
 *	        )>
 *
 *	algo_id = 0x01  BLAKE2b-256
 *	                params: none
 *	                wire = 0x01 || digest[32]
 *
 *	algo_id = 0x02  argon2id
 *	                params: m_log2(1) || t(1) || p(1) || salt_len(1)
 *	                              || salt[salt_len]
 *	                wire = 0x02 || m_log2 || t || p || slen
 *	                            || salt[slen] || digest[32]
 *	                m  (in KiB) = 1 << m_log2  — e.g. m_log2=16 → 64 MiB.
 *	                t  = number of passes
 *	                p  = lanes (1 in single-threaded use)
 *
 * The parameters ride with the cell so verify can recompute the hash
 * without depending on the schema being stable.  This matches every
 * modern password-hash format (argon2 PHC string, bcrypt, scrypt).
 *
 * Algorithm choice is by the schema's `algo=` attribute:
 *
 *	type=HASHED                      → BLAKE2b-256 (default)
 *	type=HASHED algo=blake2b         → BLAKE2b-256 (explicit)
 *	type=HASHED algo=argon2id        → argon2id with default params
 *	                                   (m_log2=16, t=3, p=1, salt=16)
 *
 * Custom argon2id parameters arrive in a later step if a consumer
 * actually needs them; the default tuning is the OWASP 2024
 * recommendation for interactive auth.
 */

#include "tab_internal.h"
#include "../monocypher.h"

/* In tab_rowmap.c. */
int tab_rowmap_rehash(Tab *t, Ndbtuple *chain);

/* From the kernel via getrandom(2).  Spinning until the pool is
 * seeded is the right behaviour for a salt — we'd rather block at
 * boot than produce a predictable salt. */
extern long getrandom(void *, unsigned long, unsigned int);

enum {
	HashedDigest	= 32,
	HashedAlgoBlake	= 0x01,
	HashedAlgoArgon	= 0x02,

	Argon2dDefMlog2	= 16,	/* 64 MiB */
	Argon2dDefT	= 3,
	Argon2dDefP	= 1,
	Argon2dDefSalt	= 16,
	Argon2dMaxSalt	= 64,
};

/* Find a tuple by attr in a chain. */
static Ndbtuple *
find_tuple(Ndbtuple *chain, const char *col)
{
	Ndbtuple *t;
	for(t = chain; t != nil; t = t->entry){
		if(strcmp(t->attr, col) == 0)
			return t;
	}
	return nil;
}

/* Find a schema column by name. */
static TabCol *
find_col(Tab *t, const char *name)
{
	int i;
	for(i = 0; i < t->schema.ncols; i++){
		if(strcmp(t->schema.cols[i].name, name) == 0)
			return &t->schema.cols[i];
	}
	return nil;
}

/* Algorithm chosen by the schema's `algo=` attribute on the column.
 * "blake2b" (or absent) → BLAKE2b-256.  "argon2id" → argon2id with
 * defaults. */
static int
schema_algo_for(Tab *t, const char *col)
{
	const char *algo = tab_col_attr(t, col, "algo");
	if(algo == nil || strcmp(algo, "blake2b") == 0)
		return HashedAlgoBlake;
	if(strcmp(algo, "argon2id") == 0)
		return HashedAlgoArgon;
	tab_seterror("tab_set_hashed: column %q algo=%q not supported",
		col, algo);
	return -1;
}

/* Replace a tuple's value, then ask the rowmap to re-establish the
 * content-hash invariant.  On collision, restore the original value.
 *
 * Returns 0 on success, -1 on collision or error (errstr set). */
static int
mutate_cell(Tab *t, Ndbtuple *chain, const char *col, const char *newval)
{
	Ndbtuple *tup;
	char *saved_inline, *saved_heap;
	int rh;

	tup = find_tuple(chain, col);
	if(tup == nil){
		/* No existing cell — append a fresh tuple with the new
		 * value, then rehash.  Mirrors the append branch in
		 * tab_set; lets callers populate freshly-added rows. */
		Ndbtuple *last, *newtup;
		int rh2;
		last = chain;
		while(last->entry != nil) last = last->entry;
		newtup = ndbnew((char *)col, (char *)newval);
		if(newtup == nil){
			tab_seterror("tab_set_hashed: ndbnew failed");
			return -1;
		}
		last->entry = newtup;
		rh2 = tab_rowmap_rehash(t, chain);
		if(rh2 == 0){
			t->dirty = 1;
			return 0;
		}
		last->entry = nil;
		ndbfree(newtup);
		return -1;
	}

	/* Snapshot the old value so we can roll back on rowmap collision.
	 * Ndbtuple values live either inline in tup->valbuf or on the
	 * heap with tup->val pointing there. */
	saved_inline = nil;
	saved_heap = nil;
	if(tup->val == tup->valbuf){
		saved_inline = strdup(tup->valbuf);
		if(saved_inline == nil){
			tab_seterror("tab_set_hashed: out of memory snapshotting");
			return -1;
		}
	}else{
		saved_heap = tup->val;
		tup->val = tup->valbuf;	/* detach so ndbsetval allocates fresh */
	}

	ndbsetval(tup, (char *)newval, strlen(newval));

	rh = tab_rowmap_rehash(t, chain);
	if(rh == 0){
		t->dirty = 1;
		free(saved_inline);
		free(saved_heap);
		return 0;
	}

	/* Collision or error — restore the original cell text. */
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

/* ---- BLAKE2b-256 ---- */

static int
encode_blake2b_cell(const uint8_t digest[HashedDigest], char **out)
{
	uint8_t wire[1 + HashedDigest];
	char *cell;

	wire[0] = HashedAlgoBlake;
	memcpy(wire + 1, digest, HashedDigest);
	cell = tab_cell_encode("HASHED", wire, sizeof wire);
	if(cell == nil)
		return -1;
	*out = cell;
	return 0;
}

/* ---- argon2id ---- */

static int
do_argon2id(uint8_t digest[HashedDigest],
	uint32_t m_log2, uint32_t t_passes, uint32_t p_lanes,
	const uint8_t *salt, uint32_t salt_len,
	const uint8_t *pass, uint32_t pass_len)
{
	crypto_argon2_config cfg;
	crypto_argon2_inputs in;
	uint64_t nb_blocks;
	void *work;

	cfg.algorithm = CRYPTO_ARGON2_ID;
	nb_blocks = (uint64_t)1 << m_log2;	/* nb_blocks counts 1KiB blocks */
	if(nb_blocks < 8ull * p_lanes){
		tab_seterror("argon2id: m too small for p lanes");
		return -1;
	}
	if(nb_blocks > 0xfffffffful){
		tab_seterror("argon2id: m too large");
		return -1;
	}
	cfg.nb_blocks = (uint32_t)nb_blocks;
	cfg.nb_passes = t_passes;
	cfg.nb_lanes = p_lanes;

	in.pass = pass;
	in.pass_size = pass_len;
	in.salt = salt;
	in.salt_size = salt_len;

	/* Work area: 1 KiB per block.  At 64 MiB that's 64 MiB allocated
	 * once per hash.  Caller is libtab consumer code (auth path),
	 * which runs at low frequency. */
	work = malloc((size_t)cfg.nb_blocks * 1024);
	if(work == nil){
		tab_seterror("argon2id: out of memory for work area (%u KiB)",
			cfg.nb_blocks);
		return -1;
	}
	crypto_argon2(digest, HashedDigest, work, cfg, in,
		crypto_argon2_no_extras);
	memset(work, 0, (size_t)cfg.nb_blocks * 1024);
	free(work);
	return 0;
}

static int
encode_argon2id_cell(uint8_t m_log2, uint8_t t_passes, uint8_t p_lanes,
	const uint8_t *salt, uint32_t salt_len,
	const uint8_t digest[HashedDigest], char **out)
{
	uint8_t *wire;
	int wlen;
	char *cell;

	wlen = 1 + 4 + (int)salt_len + HashedDigest;
	wire = malloc(wlen);
	if(wire == nil){
		tab_seterror("argon2id: out of memory for cell encoding");
		return -1;
	}
	wire[0] = HashedAlgoArgon;
	wire[1] = m_log2;
	wire[2] = t_passes;
	wire[3] = p_lanes;
	wire[4] = (uint8_t)salt_len;
	memcpy(wire + 5, salt, salt_len);
	memcpy(wire + 5 + salt_len, digest, HashedDigest);
	cell = tab_cell_encode("HASHED", wire, wlen);
	memset(wire, 0, wlen);
	free(wire);
	if(cell == nil)
		return -1;
	*out = cell;
	return 0;
}

/* ---- Public: set + verify ---- */

/* Validate that `col` exists in the schema and is typed HASHED.
 * Returns the column on success, nil with errstr on failure. */
static TabCol *
validate_hashed_col(Tab *t, const char *col)
{
	TabCol *c = find_col(t, col);
	if(c == nil){
		tab_seterror("tab_set_hashed: column %q not in schema", col);
		return nil;
	}
	if(c->type == nil || strcmp(c->type, "HASHED") != 0){
		tab_seterror("tab_set_hashed: column %q is not HASHED "
			"(type=%q)", col, c->type != nil ? c->type : "(plain)");
		return nil;
	}
	return c;
}

/* Compute and store a BLAKE2b digest in the cell. */
static int
do_blake2b_set(Tab *t, TabRow *r, const char *col,
	const unsigned char *preimage, int n)
{
	uint8_t digest[HashedDigest];
	char *cell;
	int rc;
	crypto_blake2b(digest, HashedDigest, preimage, (size_t)n);
	if(encode_blake2b_cell(digest, &cell) < 0){
		memset(digest, 0, sizeof digest);
		return -1;
	}
	memset(digest, 0, sizeof digest);
	rc = mutate_cell(t, r->chain, col, cell);
	free(cell);
	return rc;
}

/* Compute and store an argon2id digest in the cell (default params,
 * fresh random 16-byte salt). */
static int
do_argon2id_set(Tab *t, TabRow *r, const char *col,
	const unsigned char *preimage, int n)
{
	uint8_t salt[Argon2dDefSalt];
	uint8_t digest[HashedDigest];
	char *cell;
	int rc;

	if(getrandom(salt, sizeof salt, 0) != (long)sizeof salt){
		tab_seterror("tab_set_hashed: getrandom(salt) failed");
		return -1;
	}
	if(do_argon2id(digest, Argon2dDefMlog2, Argon2dDefT, Argon2dDefP,
		salt, sizeof salt, preimage, (uint32_t)n) < 0){
		memset(salt, 0, sizeof salt);
		return -1;
	}
	if(encode_argon2id_cell(Argon2dDefMlog2, Argon2dDefT, Argon2dDefP,
		salt, sizeof salt, digest, &cell) < 0){
		memset(salt, 0, sizeof salt);
		memset(digest, 0, sizeof digest);
		return -1;
	}
	memset(salt, 0, sizeof salt);
	memset(digest, 0, sizeof digest);
	rc = mutate_cell(t, r->chain, col, cell);
	free(cell);
	return rc;
}

/* Schema-driven dispatch: consult the column's `algo=` attribute
 * (blake2b default, argon2id available).  This is the recommended
 * entry point for consumers — it puts the algorithm choice in the
 * schema where it can be inspected and migrated. */
int
tab_set_hashed(Tab *t, TabRow *r, const char *col,
	const unsigned char *preimage, int n)
{
	TabCol *c;
	int algo;

	tab_clearerror();
	if(t == nil || r == nil || col == nil || (preimage == nil && n != 0)){
		tab_seterror("tab_set_hashed: nil argument");
		return -1;
	}
	if(n < 0){
		tab_seterror("tab_set_hashed: negative preimage length");
		return -1;
	}
	c = validate_hashed_col(t, col);
	if(c == nil)
		return -1;
	algo = schema_algo_for(t, col);
	if(algo < 0)
		return -1;
	if(algo == HashedAlgoArgon)
		return do_argon2id_set(t, r, col, preimage, n);
	return do_blake2b_set(t, r, col, preimage, n);
}

/* Explicit override: use argon2id with default parameters regardless
 * of what the schema says.  Kept for consumers who haven't yet moved
 * their algorithm choice into the schema (or who want to use argon2id
 * on a schema that defaults to blake2b for some columns). */
int
tab_set_hashed_argon2id(Tab *t, TabRow *r, const char *col,
	const unsigned char *preimage, int n)
{
	tab_clearerror();
	if(t == nil || r == nil || col == nil || (preimage == nil && n != 0)){
		tab_seterror("tab_set_hashed_argon2id: nil argument");
		return -1;
	}
	if(n < 0){
		tab_seterror("tab_set_hashed_argon2id: negative preimage length");
		return -1;
	}
	if(validate_hashed_col(t, col) == nil)
		return -1;
	return do_argon2id_set(t, r, col, preimage, n);
}

/* Constant-time compare of two equal-length byte buffers.
 *
 * The buffers being compared are digest outputs (already public to
 * anyone who can read the cell), so the leak surface from a non-CT
 * compare is small in this context.  We still use a CT compare
 * because it costs nothing and removes a class of timing-channel
 * thinking from future readers. */
static int
ct_eq(const uint8_t *a, const uint8_t *b, int n)
{
	int i, acc = 0;
	for(i = 0; i < n; i++)
		acc |= a[i] ^ b[i];
	return acc == 0;
}

int
tab_verify_hash(TabRow *r, const char *col,
	const unsigned char *preimage, int n)
{
	const char *cellv;
	uint8_t *wire;
	uint8_t computed[HashedDigest];
	int wlen, ok;
	uint32_t salt_len;
	uint8_t algo, m_log2, t_passes, p_lanes;

	tab_clearerror();
	if(r == nil || col == nil || (preimage == nil && n != 0)){
		tab_seterror("tab_verify_hash: nil argument");
		return -1;
	}
	if(n < 0){
		tab_seterror("tab_verify_hash: negative preimage length");
		return -1;
	}
	cellv = tab_row_cell(r->chain, col);
	if(cellv == nil || *cellv == 0){
		tab_seterror("tab_verify_hash: cell %q is empty", col);
		return 0;
	}
	wire = tab_cell_decode(cellv, "HASHED", &wlen);
	if(wire == nil)
		return -1;
	if(wlen < 1){
		tab_seterror("tab_verify_hash: cell too short");
		free(wire);
		return -1;
	}
	algo = wire[0];
	switch(algo){
	case HashedAlgoBlake:
		if(wlen != 1 + HashedDigest){
			tab_seterror("tab_verify_hash: BLAKE2b cell length %d, "
				"want %d", wlen, 1 + HashedDigest);
			free(wire);
			return -1;
		}
		crypto_blake2b(computed, HashedDigest, preimage, (size_t)n);
		ok = ct_eq(wire + 1, computed, HashedDigest);
		memset(computed, 0, sizeof computed);
		free(wire);
		return ok ? 1 : 0;

	case HashedAlgoArgon:
		if(wlen < 1 + 4 + HashedDigest){
			tab_seterror("tab_verify_hash: argon2id cell too short");
			free(wire);
			return -1;
		}
		m_log2 = wire[1];
		t_passes = wire[2];
		p_lanes = wire[3];
		salt_len = wire[4];
		if(salt_len < 1 || salt_len > Argon2dMaxSalt){
			tab_seterror("tab_verify_hash: argon2id salt_len=%u "
				"out of range", salt_len);
			free(wire);
			return -1;
		}
		if(wlen != 1 + 4 + (int)salt_len + HashedDigest){
			tab_seterror("tab_verify_hash: argon2id cell length "
				"mismatches header (wlen=%d, salt_len=%u)",
				wlen, salt_len);
			free(wire);
			return -1;
		}
		if(m_log2 < 3 || m_log2 > 24){	/* 8 KiB .. 16 MiB^2 == 16 GiB */
			tab_seterror("tab_verify_hash: argon2id m_log2=%u "
				"out of range", m_log2);
			free(wire);
			return -1;
		}
		if(t_passes < 1 || p_lanes < 1){
			tab_seterror("tab_verify_hash: argon2id t/p must be >= 1");
			free(wire);
			return -1;
		}
		if(do_argon2id(computed, m_log2, t_passes, p_lanes,
			wire + 5, salt_len, preimage, (uint32_t)n) < 0){
			free(wire);
			return -1;
		}
		ok = ct_eq(wire + 5 + salt_len, computed, HashedDigest);
		memset(computed, 0, sizeof computed);
		free(wire);
		return ok ? 1 : 0;

	default:
		tab_seterror("tab_verify_hash: unknown algo_id 0x%02x", algo);
		free(wire);
		return -1;
	}
}
