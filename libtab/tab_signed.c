/*
 * libtab — SIGNED column type.
 *
 * Wire format of a SIGNED cell:
 *
 *	signed: <base64-url-safe(body)> : <base64-url-safe(sig)>
 *
 * Two base64 segments separated by an inner colon, inside the
 * `signed:` tag.  Body is the signed bytes; sig is the 64-byte
 * Ed25519 signature.  Encoding both halves separately preserves the
 * "spot-checkable with `base64 -d` at each segment" property from
 * the design doc.
 *
 * Signing key bytes flow in from the caller.  Libtab does not open
 * key files, resolve symbolic principals, or take any opinion on
 * where the bytes come from.  A schema column may carry
 * `signer=<name>` purely as a label for consumers to read via
 * tab_col_attr() — libtab never interprets it.
 *
 * Crypto: monocypher Ed25519 (crypto_eddsa_sign / crypto_eddsa_check).
 * Secret key is monocypher's 64-byte combined seed+pubkey form;
 * public key is the 32-byte point.
 *
 * Mutations are in-memory until tab_commit() or close-time auto-commit.
 */

#include "tab_internal.h"
#include "../monocypher.h"

/* In tab_rowmap.c. */
int tab_rowmap_rehash(Tab *t, Ndbtuple *chain);

enum {
	SignedSigLen	= 64,
};

/* Find a tuple by attr in a chain.  Mirrors the helper in tab_hashed.c;
 * keeping the two type modules independent is worth the duplication. */
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

/* Mutate a cell's text, then re-hash the row.  On collision (mutation
 * would duplicate an existing row) the original cell is restored.
 * Same shape as tab_hashed.c's mutate_cell — extracted into a shared
 * helper later if a third consumer ever appears. */
static int
mutate_cell(Tab *t, Ndbtuple *chain, const char *col, const char *newval)
{
	Ndbtuple *tup;
	char *saved_inline, *saved_heap;
	int rh;

	tup = find_tuple(chain, col);
	if(tup == nil){
		/* No existing cell — append a fresh tuple. */
		Ndbtuple *last, *newtup;
		int rh2;
		last = chain;
		while(last->entry != nil) last = last->entry;
		newtup = ndbnew((char *)col, (char *)newval);
		if(newtup == nil){
			tab_seterror("tab_set_signed: ndbnew failed");
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

	saved_inline = nil;
	saved_heap = nil;
	if(tup->val == tup->valbuf){
		saved_inline = strdup(tup->valbuf);
		if(saved_inline == nil){
			tab_seterror("tab_set_signed: out of memory snapshotting");
			return -1;
		}
	}else{
		saved_heap = tup->val;
		tup->val = tup->valbuf;
	}

	ndbsetval(tup, (char *)newval, strlen(newval));

	rh = tab_rowmap_rehash(t, chain);
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

/* Validate that `col` exists and is SIGNED-typed. */
static TabCol *
validate_signed_col(Tab *t, const char *col, const char *who)
{
	TabCol *c = find_col(t, col);
	if(c == nil){
		tab_seterror("%s: column %q not in schema", who, col);
		return nil;
	}
	if(c->type == nil || strcmp(c->type, "SIGNED") != 0){
		tab_seterror("%s: column %q is not SIGNED (type=%q)",
			who, col, c->type != nil ? c->type : "(plain)");
		return nil;
	}
	return c;
}

/* Build "signed:<b64-body>:<b64-sig>".  Returns malloc'd cell text or
 * nil on OOM. */
static char *
encode_signed_cell(const uint8_t *body, int body_len,
	const uint8_t sig[SignedSigLen])
{
	char *body_b64, *sig_b64, *out;
	int body_b64_len, sig_b64_len, total;
	static const char prefix[] = "signed:";
	const int prefix_len = sizeof prefix - 1;

	body_b64 = tab_b64_encode(body, body_len);
	if(body_b64 == nil)
		return nil;
	sig_b64 = tab_b64_encode(sig, SignedSigLen);
	if(sig_b64 == nil){
		free(body_b64);
		return nil;
	}
	body_b64_len = strlen(body_b64);
	sig_b64_len = strlen(sig_b64);
	total = prefix_len + body_b64_len + 1 + sig_b64_len;	/* +1 for inner ':' */
	out = malloc(total + 1);
	if(out == nil){
		tab_seterror("tab_set_signed: out of memory for cell");
		free(body_b64);
		free(sig_b64);
		return nil;
	}
	memcpy(out, prefix, prefix_len);
	memcpy(out + prefix_len, body_b64, body_b64_len);
	out[prefix_len + body_b64_len] = ':';
	memcpy(out + prefix_len + body_b64_len + 1, sig_b64, sig_b64_len);
	out[total] = 0;
	free(body_b64);
	free(sig_b64);
	return out;
}

/* Parse "signed:<b64-body>:<b64-sig>" into freshly-allocated body bytes
 * and a 64-byte signature.  Returns 0 on success with *body and
 * *body_len populated and `sig_out` filled.  Caller frees `*body` on
 * success.  Returns -1 on malformed input with errstr set. */
static int
decode_signed_cell(const char *cell,
	unsigned char **body_out, int *body_len_out,
	uint8_t sig_out[SignedSigLen])
{
	const char *p, *colon;
	char *body_b64;
	unsigned char *body, *sig_bytes;
	int body_b64_len, sig_len;
	static const char prefix[] = "signed:";
	const int prefix_len = sizeof prefix - 1;

	if(cell == nil || strncmp(cell, prefix, prefix_len) != 0){
		tab_seterror("tab_verify_signed: cell missing signed: prefix");
		return -1;
	}
	p = cell + prefix_len;
	colon = strchr(p, ':');
	if(colon == nil){
		tab_seterror("tab_verify_signed: cell missing inner ':' "
			"between body and signature");
		return -1;
	}

	body_b64_len = (int)(colon - p);
	body_b64 = malloc(body_b64_len + 1);
	if(body_b64 == nil){
		tab_seterror("tab_verify_signed: out of memory");
		return -1;
	}
	memcpy(body_b64, p, body_b64_len);
	body_b64[body_b64_len] = 0;
	body = tab_b64_decode(body_b64, body_len_out);
	free(body_b64);
	if(body == nil)
		return -1;

	sig_bytes = tab_b64_decode(colon + 1, &sig_len);
	if(sig_bytes == nil){
		free(body);
		return -1;
	}
	if(sig_len != SignedSigLen){
		tab_seterror("tab_verify_signed: signature is %d bytes, want %d",
			sig_len, SignedSigLen);
		free(body);
		free(sig_bytes);
		return -1;
	}
	memcpy(sig_out, sig_bytes, SignedSigLen);
	free(sig_bytes);
	*body_out = body;
	return 0;
}

/* ---- Public: set + verify ---- */

int
tab_set_signed(Tab *t, TabRow *r, const char *col,
	const unsigned char *body, int n,
	const unsigned char signer_sk[64])
{
	uint8_t sig[SignedSigLen];
	char *cell;
	int rc;

	tab_clearerror();
	if(t == nil || r == nil || col == nil || signer_sk == nil
	   || (body == nil && n != 0)){
		tab_seterror("tab_set_signed: nil argument");
		return -1;
	}
	if(n < 0){
		tab_seterror("tab_set_signed: negative body length");
		return -1;
	}
	if(validate_signed_col(t, col, "tab_set_signed") == nil)
		return -1;

	crypto_eddsa_sign(sig, signer_sk, body, (size_t)n);
	cell = encode_signed_cell(body, n, sig);
	memset(sig, 0, sizeof sig);
	if(cell == nil)
		return -1;
	rc = mutate_cell(t, r->chain, col, cell);
	free(cell);
	return rc;
}

unsigned char *
tab_verify_signed(TabRow *r, const char *col,
	const unsigned char signer_pk[32], int *outlen)
{
	const char *cellv;
	unsigned char *body;
	uint8_t sig[SignedSigLen];
	int body_len;

	tab_clearerror();
	if(r == nil || col == nil || signer_pk == nil || outlen == nil){
		tab_seterror("tab_verify_signed: nil argument");
		return nil;
	}
	cellv = tab_row_cell(r->chain, col);
	if(cellv == nil || *cellv == 0){
		tab_seterror("tab_verify_signed: cell %q is empty", col);
		return nil;
	}
	if(decode_signed_cell(cellv, &body, &body_len, sig) < 0)
		return nil;

	if(crypto_eddsa_check(sig, signer_pk, body, (size_t)body_len) != 0){
		tab_seterror("tab_verify_signed: signature check failed");
		memset(body, 0, body_len);
		free(body);
		return nil;
	}
	*outlen = body_len;
	return body;
}
