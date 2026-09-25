#include <u.h>
#include <libc.h>
#define MONO_PLAN9
#include "monocypher.h"
#include "o9.h"

/*
 * o9 crypto stdlib — the full practical monocypher surface.
 *
 * Attestation: sign/verify (Ed25519), hash (BLAKE2b-256), mac (keyed
 * BLAKE2b-256), plus keygen/pubkey.  Confidentiality: encrypt/decrypt
 * (XChaCha20-Poly1305 AEAD) and xpubkey/exchange (X25519 agreement).
 *
 * This supersedes the original attestation-only stance (July 2026):
 * transport confidentiality is still dp9ik's job, but application-level
 * sealing is now the program's choice.  What survives of the old rule is
 * the TEXT invariant: every boundary value is lowercase hex, so keys,
 * signatures, digests and ciphertext blobs all travel in files, ctl
 * lines and libtab cells unchanged — an encrypted value is still one
 * cat-able string, only its content is sealed.
 *
 * Key derivation: passkey (Argon2id) turns a passphrase into an
 * encrypt/mac key, deterministically — the "secret safety" path for
 * sealing text inside objects without storing anything key-shaped.
 *
 * Not exposed: raw chacha20/poly1305, elligator, and the eddsa scalar
 * ops (protocol-construction footguns with no o9 story).
 */

/* Fill buf with n random bytes from the system RNG. */
int
o9_randbytes(uchar *buf, int n)
{
	int fd, got, r;

	if(buf == nil || n < 0)
		return -1;
	fd = open("/dev/random", OREAD);
	if(fd < 0)
		return -1;
	for(got = 0; got < n; got += r){
		r = read(fd, buf + got, n - got);
		if(r <= 0){
			close(fd);
			return -1;
		}
	}
	close(fd);
	return 0;
}

static char hexdig[] = "0123456789abcdef";

static void
tohex(uchar *in, int n, char *out)
{
	int i;
	for(i = 0; i < n; i++){
		out[2*i]   = hexdig[(in[i] >> 4) & 0xf];
		out[2*i+1] = hexdig[in[i] & 0xf];
	}
	out[2*n] = '\0';
}

static int
hexval(int c)
{
	if(c >= '0' && c <= '9') return c - '0';
	if(c >= 'a' && c <= 'f') return c - 'a' + 10;
	if(c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/* Decode up to max bytes from hex; returns byte count or -1 on bad input. */
static int
fromhex(char *in, uchar *out, int max)
{
	int n, hi, lo;
	if(in == nil) return -1;
	for(n = 0; n < max; n++){
		if(in[2*n] == '\0') break;
		hi = hexval(in[2*n]);
		lo = hexval(in[2*n+1]);
		if(hi < 0 || lo < 0) return -1;
		out[n] = (uchar)((hi << 4) | lo);
	}
	return n;
}

/*
 * o9_crypto_keypair — generate an Ed25519 keypair.
 * Writes 64 hex chars of public key to pub, 128 of secret to sec.
 * The 32-byte seed is the secret; monocypher derives the public point.
 */
int
o9_crypto_keypair(char *pub, char *sec)
{
	uchar seed[32], sk[64], pk[32];

	if(pub == nil || sec == nil)
		return -1;
	/* seed from the system RNG; on 9front this is /dev/random-backed */
	if(o9_randbytes(seed, sizeof seed) < 0){
		crypto_wipe(seed, sizeof seed);
		return -1;
	}
	tohex(seed, 32, sec);	/* the persistent secret is the 32-byte seed */
	/* Monocypher wipes seed too; keep the boundary wipe explicit here. */
	crypto_eddsa_key_pair(sk, pk, seed);
	crypto_wipe(seed, sizeof seed);
	tohex(pk, 32, pub);
	crypto_wipe(sk, sizeof sk);
	return 0;
}

/*
 * o9_crypto_sign — Ed25519 sign msg (nmsg bytes) with hex secret key.
 * Writes 128 hex chars of signature to sig.  Returns 0 / -1.
 */
int
o9_crypto_sign(char *sechex, uchar *msg, long nmsg, char *sig)
{
	uchar seed[32], sk[64], pk[32], sg[64];

	if(sechex == nil || sig == nil)
		return -1;
	if(fromhex(sechex, seed, 32) != 32){	/* stored secret is the seed */
		crypto_wipe(seed, sizeof seed);
		return -1;
	}
	crypto_eddsa_key_pair(sk, pk, seed);	/* expand seed -> 64-byte sk */
	crypto_wipe(seed, sizeof seed);
	crypto_eddsa_sign(sg, sk, msg, (size_t)nmsg);
	tohex(sg, 64, sig);
	crypto_wipe(sk, sizeof sk);
	return 0;
}

/*
 * o9_crypto_verify — check a hex signature over msg against a hex pubkey.
 * Returns 1 valid, 0 invalid, -1 on malformed input.
 */
int
o9_crypto_verify(char *pubhex, uchar *msg, long nmsg, char *sighex)
{
	uchar pk[32], sg[64];

	if(pubhex == nil || sighex == nil)
		return -1;
	if(fromhex(pubhex, pk, 32) != 32)
		return -1;
	if(fromhex(sighex, sg, 64) != 64)
		return -1;
	return crypto_eddsa_check(sg, pk, msg, (size_t)nmsg) == 0 ? 1 : 0;
}

/*
 * o9_crypto_hash — BLAKE2b-256 of nmsg bytes, 64 hex chars into out.
 */
int
o9_crypto_hash(uchar *msg, long nmsg, char *out)
{
	uchar h[32];

	if(out == nil)
		return -1;
	crypto_blake2b(h, sizeof h, msg, (size_t)nmsg);
	tohex(h, 32, out);
	return 0;
}

/*
 * Language-level builtins.  o9 strings are the only message type — every
 * value the language attests is already text (hex, ctl lines, libtab
 * cells), so these take char* and return malloc'd hex strings, matching
 * the string builtin ABI (o9_readfile et al.).  Keypair generation is
 * split so each builtin returns one value: keygen() makes the seed,
 * pubkey(sec) re-derives the public point from it — same expansion
 * sign uses, so the pair can never disagree.
 */

/* keygen() -> 64-hex seed; the seed IS the persistent secret. */
O9String*
o9_keygen(void)
{
	uchar seed[32];
	char *sec;

	sec = malloc(65);
	if(sec == nil)
		return nil;
	if(o9_randbytes(seed, sizeof seed) < 0){
		free(sec);
		return nil;
	}
	tohex(seed, 32, sec);
	crypto_wipe(seed, sizeof seed);
	return o9_string_take(sec);
}

/* pubkey(sec) -> 64-hex Ed25519 public key derived from the seed. */
O9String*
o9_pubkey(O9String *sec)
{
	uchar seed[32], sk[64], pk[32];
	char *pub;
	char *csec;

	if(sec == nil)
		return nil;
	csec = o9_string_data(sec);
	if(fromhex(csec, seed, 32) != 32){
		crypto_wipe(seed, sizeof seed);
		return nil;
	}
	pub = malloc(65);
	if(pub == nil){
		crypto_wipe(seed, sizeof seed);
		return nil;
	}
	crypto_eddsa_key_pair(sk, pk, seed);
	crypto_wipe(seed, sizeof seed);
	tohex(pk, 32, pub);
	crypto_wipe(sk, sizeof sk);
	return o9_string_take(pub);
}

/* sign(sec, msg) -> 128-hex Ed25519 signature over the string msg. */
O9String*
o9_sign(O9String *sec, O9String *msg)
{
	char *sig;
	char *csec, *cmsg;

	if(sec == nil || msg == nil)
		return nil;
	csec = o9_string_data(sec);
	cmsg = o9_string_data(msg);
	sig = malloc(129);
	if(sig == nil)
		return nil;
	if(o9_crypto_sign(csec, (uchar*)cmsg, o9_string_len(msg), sig) < 0){
		free(sig);
		return nil;
	}
	return o9_string_take(sig);
}

/* verify(pub, msg, sig) -> 1 valid, 0 invalid, -1 malformed input. */
vlong
o9_verify(O9String *pub, O9String *msg, O9String *sig)
{
	char *cpub, *cmsg, *csig;

	if(pub == nil || msg == nil || sig == nil)
		return -1;
	cpub = o9_string_data(pub);
	cmsg = o9_string_data(msg);
	csig = o9_string_data(sig);
	return o9_crypto_verify(cpub, (uchar*)cmsg, o9_string_len(msg), csig);
}

/* hash(msg) -> 64-hex BLAKE2b-256 of the string msg.  (Named o9_digest:
 * o9_hash is the runtime's selector hash in o9_runtime.c.) */
O9String*
o9_digest(O9String *msg)
{
	char *out;
	char *cmsg;

	if(msg == nil)
		return nil;
	cmsg = o9_string_data(msg);
	out = malloc(65);
	if(out == nil)
		return nil;
	if(o9_crypto_hash((uchar*)cmsg, o9_string_len(msg), out) < 0){
		free(out);
		return nil;
	}
	return o9_string_take(out);
}

/* mac(key, msg) -> 64-hex keyed BLAKE2b-256; symmetric attestation.
 * key is 64 hex chars (32 bytes) — any keygen() output works. */
O9String*
o9_mac(O9String *keyhex, O9String *msg)
{
	uchar key[32], h[32];
	char *out;
	char *ckey, *cmsg;

	if(keyhex == nil || msg == nil)
		return nil;
	ckey = o9_string_data(keyhex);
	cmsg = o9_string_data(msg);
	if(fromhex(ckey, key, 32) != 32)
		return nil;
	out = malloc(65);
	if(out == nil){
		crypto_wipe(key, sizeof key);
		return nil;
	}
	crypto_blake2b_keyed(h, sizeof h, key, sizeof key, (uchar*)cmsg, o9_string_len(msg));
	crypto_wipe(key, sizeof key);
	tohex(h, 32, out);
	return o9_string_take(out);
}

/* encrypt(key, msg) -> hex(nonce[24] || mac[16] || ciphertext), one
 * self-contained blob.  XChaCha20-Poly1305; the nonce is drawn fresh
 * from the system RNG on every call and carried in the blob, so key
 * reuse is safe and there is no nonce argument to get wrong. */
O9String*
o9_encrypt(O9String *keyhex, O9String *msg)
{
	uchar key[32], nonce[24], mac[16], *ct;
	char *out;
	long n;
	char *ckey, *cmsg;

	if(keyhex == nil || msg == nil)
		return nil;
	ckey = o9_string_data(keyhex);
	cmsg = o9_string_data(msg);
	if(fromhex(ckey, key, 32) != 32)
		return nil;
	n = o9_string_len(msg);
	ct = malloc(n == 0 ? 1 : n);
	out = malloc(2*(24 + 16 + n) + 1);
	if(ct == nil || out == nil || o9_randbytes(nonce, sizeof nonce) < 0){
		free(ct);
		free(out);
		crypto_wipe(key, sizeof key);
		return nil;
	}
	crypto_aead_lock(ct, mac, key, nonce, nil, 0, (uchar*)cmsg, (size_t)n);
	crypto_wipe(key, sizeof key);
	tohex(nonce, 24, out);
	tohex(mac, 16, out + 48);
	tohex(ct, n, out + 80);
	free(ct);
	return o9_string_take(out);
}

/* decrypt(key, blob) -> plaintext string, or nil if the key is wrong
 * or the blob was tampered with (Poly1305 authentication fails). */
O9String*
o9_decrypt(O9String *keyhex, O9String *blob)
{
	uchar key[32], nonce[24], mac[16], *buf;
	char *pt;
	long nb, n;
	char *ckey, *cblob;

	if(keyhex == nil || blob == nil)
		return nil;
	ckey = o9_string_data(keyhex);
	cblob = o9_string_data(blob);
	nb = o9_string_len(blob);
	if(nb % 2 != 0 || nb/2 < 24 + 16)
		return nil;
	n = nb/2;
	if(fromhex(ckey, key, 32) != 32)
		return nil;
	buf = malloc(n);
	pt = malloc(n - 40 + 1);
	if(buf == nil || pt == nil || fromhex(cblob, buf, n) != n){
		free(buf);
		free(pt);
		crypto_wipe(key, sizeof key);
		return nil;
	}
	memmove(nonce, buf, 24);
	memmove(mac, buf + 24, 16);
	if(crypto_aead_unlock((uchar*)pt, mac, key, nonce, nil, 0, buf + 40, (size_t)(n - 40)) != 0){
		free(buf);
		free(pt);
		crypto_wipe(key, sizeof key);
		return nil;
	}
	crypto_wipe(key, sizeof key);
	free(buf);
	pt[n - 40] = '\0';
	return o9_string_take(pt);
}

/* passkey(password, salt) -> 64-hex key via Argon2id, ready to feed
 * encrypt/mac.  Deterministic: the same password+salt always derives
 * the same key, so a secret sealed in an object can be reopened from
 * the passphrase alone — nothing key-shaped needs storing.  Cost is
 * libtab's default (64 MiB, 3 passes, 1 lane; tab_hashed.c), so
 * password hardness is uniform across the stack.  Salt is per-secret
 * context, 8 bytes minimum (argon2 requirement). */
O9String*
o9_passkey(O9String *pass, O9String *salt)
{
	crypto_argon2_config cfg;
	crypto_argon2_inputs in;
	uchar h[32];
	char *out;
	void *work;
	char *cpass, *csalt;

	if(pass == nil || salt == nil || o9_string_len(salt) < 8)
		return nil;
	cpass = o9_string_data(pass);
	csalt = o9_string_data(salt);
	cfg.algorithm = CRYPTO_ARGON2_ID;
	cfg.nb_blocks = 65536;	/* 64 MiB: libtab's Argon2dDefMlog2 */
	cfg.nb_passes = 3;
	cfg.nb_lanes = 1;
	in.pass = (uchar*)cpass;
	in.pass_size = o9_string_len(pass);
	in.salt = (uchar*)csalt;
	in.salt_size = o9_string_len(salt);
	work = malloc((ulong)cfg.nb_blocks * 1024);
	if(work == nil)
		return nil;
	out = malloc(65);
	if(out == nil){
		free(work);
		return nil;
	}
	/* crypto_argon2 wipes the work area itself before returning */
	crypto_argon2(h, sizeof h, work, cfg, in, crypto_argon2_no_extras);
	free(work);
	tohex(h, 32, out);
	crypto_wipe(h, sizeof h);
	return o9_string_take(out);
}

/* xpubkey(sec) -> 64-hex X25519 public key; sec is any keygen() seed.
 * X25519 keys are separate from Ed25519 ones — don't reuse a signing
 * seed for exchange. */
O9String*
o9_xpubkey(O9String *sec)
{
	uchar sk[32], pk[32];
	char *pub;
	char *csec;

	csec = o9_string_data(sec);
	if(sec == nil || fromhex(csec, sk, 32) != 32)
		return nil;
	pub = malloc(65);
	if(pub == nil){
		crypto_wipe(sk, sizeof sk);
		return nil;
	}
	crypto_x25519_public_key(pk, sk);
	crypto_wipe(sk, sizeof sk);
	tohex(pk, 32, pub);
	return o9_string_take(pub);
}

/* exchange(mysec, theirpub) -> 64-hex shared key: BLAKE2b-256 of the
 * raw X25519 secret, ready to feed encrypt/mac directly.  Both sides
 * agree: exchange(a, xpubkey(b)) == exchange(b, xpubkey(a)).  Returns
 * nil if the peer key is low-order (raw shared secret all zero). */
O9String*
o9_exchange(O9String *sec, O9String *pub)
{
	uchar sk[32], pk[32], raw[32], h[32];
	char *out;
	int i, z;
	char *csec, *cpub;

	if(sec == nil || pub == nil)
		return nil;
	csec = o9_string_data(sec);
	cpub = o9_string_data(pub);
	if(fromhex(csec, sk, 32) != 32 || fromhex(cpub, pk, 32) != 32)
		return nil;
	crypto_x25519(raw, sk, pk);
	crypto_wipe(sk, sizeof sk);
	z = 0;
	for(i = 0; i < 32; i++)
		z |= raw[i];
	if(z == 0)
		return nil;
	out = malloc(65);
	if(out == nil){
		crypto_wipe(raw, sizeof raw);
		return nil;
	}
	crypto_blake2b(h, sizeof h, raw, sizeof raw);
	crypto_wipe(raw, sizeof raw);
	tohex(h, 32, out);
	return o9_string_take(out);
}

/*
 * Vault & O9KeyArena: isolated memory arena for encryption keys and
 * defense-in-depth storage of sensitive data.
 */

O9String*
o9_salt(void)
{
	uchar buf[16];
	char *hex;

	if(o9_randbytes(buf, sizeof buf) < 0)
		return nil;
	hex = malloc(33);
	if(hex == nil)
		return nil;
	tohex(buf, sizeof buf, hex);
	return o9_string_take(hex);
}

static int
derive_vault_key(O9Vault *v, char *pass, char *salt)
{
	crypto_argon2_config cfg;
	crypto_argon2_inputs in;
	void *work;

	cfg.algorithm = CRYPTO_ARGON2_ID;
	cfg.nb_blocks = 65536;	/* 64 MiB */
	cfg.nb_passes = 3;
	cfg.nb_lanes = 1;
	in.pass = (uchar*)pass;
	in.pass_size = strlen(pass);
	in.salt = (uchar*)salt;
	in.salt_size = strlen(salt);
	work = malloc((ulong)cfg.nb_blocks * 1024);
	if(work == nil)
		return -1;
	crypto_argon2(v->arena->key, sizeof v->arena->key, work, cfg, in, crypto_argon2_no_extras);
	free(work);
	return 0;
}

O9Vault*
o9_vault_new(void)
{
	O9Vault *v;

	v = mallocz(sizeof *v, 1);
	if(v == nil)
		return nil;
	v->arena = mallocz(sizeof *v->arena, 1);
	if(v->arena == nil){
		free(v);
		return nil;
	}
	if(o9_randbytes(v->arena->key, sizeof v->arena->key) < 0){
		free(v->arena);
		free(v);
		return nil;
	}
	v->arena->has_salt = 0;
	v->arena->salt[0] = '\0';
	v->arena->valid = 1;
	return v;
}

O9Vault*
o9_vault_new_key(O9String *keyhex)
{
	char *ckey;
	O9Vault *v;
	uchar rawsalt[16];
	int i, israwhex;

	if(keyhex == nil || o9_string_len(keyhex) == 0)
		return nil;
	ckey = o9_string_cstr(keyhex);
	if(ckey == nil)
		return nil;
	v = mallocz(sizeof *v, 1);
	if(v == nil){
		crypto_wipe(ckey, strlen(ckey));
		free(ckey);
		return nil;
	}
	v->arena = mallocz(sizeof *v->arena, 1);
	if(v->arena == nil){
		free(v);
		crypto_wipe(ckey, strlen(ckey));
		free(ckey);
		return nil;
	}

	israwhex = (strlen(ckey) == 64);
	if(israwhex){
		for(i = 0; i < 64; i++){
			if(hexval(ckey[i]) < 0){
				israwhex = 0;
				break;
			}
		}
	}

	if(israwhex){
		if(fromhex(ckey, v->arena->key, 32) != 32){
			crypto_wipe(v->arena, sizeof *v->arena);
			free(v->arena);
			free(v);
			crypto_wipe(ckey, strlen(ckey));
			free(ckey);
			return nil;
		}
		v->arena->has_salt = 0;
		v->arena->salt[0] = '\0';
	}else{
		if(o9_randbytes(rawsalt, sizeof rawsalt) < 0){
			crypto_wipe(v->arena, sizeof *v->arena);
			free(v->arena);
			free(v);
			crypto_wipe(ckey, strlen(ckey));
			free(ckey);
			return nil;
		}
		tohex(rawsalt, sizeof rawsalt, v->arena->salt);
		v->arena->has_salt = 1;
		if(derive_vault_key(v, ckey, v->arena->salt) < 0){
			crypto_wipe(v->arena, sizeof *v->arena);
			free(v->arena);
			free(v);
			crypto_wipe(ckey, strlen(ckey));
			free(ckey);
			return nil;
		}
	}

	crypto_wipe(ckey, strlen(ckey));
	free(ckey);
	v->arena->valid = 1;
	return v;
}

O9Vault*
o9_vault_new_pass(O9String *pass, O9String *salt)
{
	char *cpass, *csalt;
	O9Vault *v;

	if(pass == nil || salt == nil || o9_string_len(salt) < 8)
		return nil;
	cpass = o9_string_cstr(pass);
	csalt = o9_string_cstr(salt);
	if(cpass == nil || csalt == nil){
		free(cpass);
		free(csalt);
		return nil;
	}
	v = mallocz(sizeof *v, 1);
	if(v == nil){
		crypto_wipe(cpass, strlen(cpass));
		free(cpass);
		free(csalt);
		return nil;
	}
	v->arena = mallocz(sizeof *v->arena, 1);
	if(v->arena == nil){
		free(v);
		crypto_wipe(cpass, strlen(cpass));
		free(cpass);
		free(csalt);
		return nil;
	}
	strncpy(v->arena->salt, csalt, sizeof(v->arena->salt) - 1);
	v->arena->salt[sizeof(v->arena->salt) - 1] = '\0';
	v->arena->has_salt = 1;
	if(derive_vault_key(v, cpass, csalt) < 0){
		crypto_wipe(v->arena, sizeof *v->arena);
		free(v->arena);
		free(v);
		crypto_wipe(cpass, strlen(cpass));
		free(cpass);
		free(csalt);
		return nil;
	}
	crypto_wipe(cpass, strlen(cpass));
	free(cpass);
	free(csalt);
	v->arena->valid = 1;
	return v;
}

O9String*
o9_vault_salt(O9Vault *v)
{
	if(v == nil || v->arena == nil || !v->arena->valid || !v->arena->has_salt)
		return o9_string_from_c("");
	return o9_string_from_c(v->arena->salt);
}

vlong
o9_vault_valid(O9Vault *v)
{
	return (v != nil && v->arena != nil && v->arena->valid) ? 1 : 0;
}

O9String*
o9_vault_seal(O9Vault *v, O9String *msg)
{
	uchar nonce[24], mac[16], *ct;
	char *out, *cmsg;
	long n;

	if(v == nil || v->arena == nil || !v->arena->valid || msg == nil)
		return nil;
	cmsg = o9_string_data(msg);
	n = (long)o9_string_len(msg);
	ct = malloc(n == 0 ? 1 : n);
	out = malloc(2*(24 + 16 + n) + 1);
	if(ct == nil || out == nil || o9_randbytes(nonce, sizeof nonce) < 0){
		free(ct);
		free(out);
		return nil;
	}
	crypto_aead_lock(ct, mac, v->arena->key, nonce, nil, 0, (uchar*)cmsg, (size_t)n);
	tohex(nonce, 24, out);
	tohex(mac, 16, out + 48);
	tohex(ct, n, out + 80);
	free(ct);
	return o9_string_take(out);
}

O9String*
o9_vault_open(O9Vault *v, O9String *blob)
{
	uchar nonce[24], mac[16], *buf;
	char *pt, *cblob;
	long nb, n;

	if(v == nil || v->arena == nil || !v->arena->valid || blob == nil)
		return nil;
	cblob = o9_string_data(blob);
	nb = (long)o9_string_len(blob);
	if(nb % 2 != 0 || nb/2 < 40)
		return nil;
	n = nb/2;
	buf = malloc(n);
	pt = malloc(n - 40 + 1);
	if(buf == nil || pt == nil || fromhex(cblob, buf, n) != n){
		free(buf);
		free(pt);
		return nil;
	}
	memmove(nonce, buf, 24);
	memmove(mac, buf + 24, 16);
	if(crypto_aead_unlock((uchar*)pt, mac, v->arena->key, nonce, nil, 0, buf + 40, (size_t)(n - 40)) != 0){
		free(buf);
		free(pt);
		return nil;
	}
	free(buf);
	pt[n - 40] = '\0';
	return o9_string_take(pt);
}

vlong
o9_vault_seal_file(O9Vault *v, O9String *path, O9String *data)
{
	O9String *blob;
	vlong r;

	if(v == nil || path == nil || data == nil)
		return -1;
	blob = o9_vault_seal(v, data);
	if(blob == nil)
		return -1;
	r = o9_writefile(path, blob);
	o9_string_release(blob);
	return r;
}

O9String*
o9_vault_open_file(O9Vault *v, O9String *path)
{
	O9String *blob, *pt;

	if(v == nil || path == nil)
		return nil;
	blob = o9_readfile(path);
	if(blob == nil)
		return nil;
	pt = o9_vault_open(v, blob);
	o9_string_release(blob);
	return pt;
}

vlong
o9_vault_seal_tab(O9Vault *v, O9String *path, O9Tabula *t)
{
	O9String *serialized;
	vlong r;

	if(v == nil || path == nil || t == nil)
		return -1;
	serialized = o9_tab_serialize(t);
	if(serialized == nil)
		return -1;
	r = o9_vault_seal_file(v, path, serialized);
	o9_string_release(serialized);
	return r;
}

O9Tabula*
o9_vault_open_tab(O9Vault *v, O9String *path)
{
	static int seq;
	char temppath[128];
	int fd;
	vlong n;
	O9String *pt, *temppath_str;
	O9Tabula *t;

	if(v == nil || path == nil)
		return nil;
	pt = o9_vault_open_file(v, path);
	if(pt == nil)
		return nil;
	snprint(temppath, sizeof temppath, "/tmp/o9vtab.%d.%d", getpid(), seq++);
	fd = create(temppath, OWRITE, 0600);
	if(fd < 0){
		o9_string_release(pt);
		return nil;
	}
	n = o9_string_len(pt);
	if(write(fd, o9_string_data(pt), (long)n) != (long)n){
		close(fd);
		remove(temppath);
		o9_string_release(pt);
		return nil;
	}
	close(fd);
	o9_string_release(pt);
	temppath_str = o9_string_from_c(temppath);
	t = o9_tab_open(temppath_str);
	o9_string_release(temppath_str);
	remove(temppath);
	return t;
}

vlong
o9_vault_put(O9Vault *v, O9String *name, O9String *plaintext)
{
	char *cname, *cpt;
	long n;
	int i, idx;
	O9KeySlot *slot;

	if(v == nil || v->arena == nil || !v->arena->valid || name == nil || plaintext == nil)
		return -1;
	cname = o9_string_cstr(name);
	cpt = o9_string_cstr(plaintext);
	if(cname == nil || cpt == nil){
		free(cname);
		free(cpt);
		return -1;
	}
	idx = -1;
	for(i = 0; i < O9ArenaMaxSlots; i++){
		if(v->arena->slots[i].used && strcmp(v->arena->slots[i].name, cname) == 0){
			idx = i;
			break;
		}
	}
	if(idx < 0){
		for(i = 0; i < O9ArenaMaxSlots; i++){
			if(!v->arena->slots[i].used){
				idx = i;
				break;
			}
		}
	}
	if(idx < 0){
		crypto_wipe(cpt, strlen(cpt));
		free(cpt);
		free(cname);
		return -1;
	}
	slot = &v->arena->slots[idx];
	if(slot->used && slot->ct != nil){
		crypto_wipe(slot->ct, (size_t)slot->nct);
		free(slot->ct);
		slot->ct = nil;
	}
	if(!slot->used)
		v->arena->nslots++;
	n = (long)strlen(cpt);
	slot->ct = malloc(n == 0 ? 1 : n);
	if(slot->ct == nil || o9_randbytes(slot->nonce, sizeof slot->nonce) < 0){
		free(slot->ct);
		slot->ct = nil;
		slot->used = 0;
		v->arena->nslots--;
		crypto_wipe(cpt, (size_t)n);
		free(cpt);
		free(cname);
		return -1;
	}
	slot->nct = n;
	crypto_aead_lock(slot->ct, slot->mac, v->arena->key, slot->nonce, nil, 0, (uchar*)cpt, (size_t)n);
	crypto_wipe(cpt, (size_t)n);
	free(cpt);
	strncpy(slot->name, cname, sizeof(slot->name) - 1);
	slot->name[sizeof(slot->name) - 1] = '\0';
	slot->used = 1;
	free(cname);
	return 0;
}

O9String*
o9_vault_get(O9Vault *v, O9String *name)
{
	char *cname, *pt;
	int i;
	O9KeySlot *slot;

	if(v == nil || v->arena == nil || !v->arena->valid || name == nil)
		return nil;
	cname = o9_string_cstr(name);
	if(cname == nil)
		return nil;
	slot = nil;
	for(i = 0; i < O9ArenaMaxSlots; i++){
		if(v->arena->slots[i].used && strcmp(v->arena->slots[i].name, cname) == 0){
			slot = &v->arena->slots[i];
			break;
		}
	}
	free(cname);
	if(slot == nil || slot->ct == nil)
		return nil;
	pt = malloc(slot->nct + 1);
	if(pt == nil)
		return nil;
	if(crypto_aead_unlock((uchar*)pt, slot->mac, v->arena->key, slot->nonce, nil, 0, slot->ct, (size_t)slot->nct) != 0){
		free(pt);
		return nil;
	}
	pt[slot->nct] = '\0';
	return o9_string_take(pt);
}

vlong
o9_vault_has(O9Vault *v, O9String *name)
{
	char *cname;
	int i, found;

	if(v == nil || v->arena == nil || !v->arena->valid || name == nil)
		return 0;
	cname = o9_string_cstr(name);
	if(cname == nil)
		return 0;
	found = 0;
	for(i = 0; i < O9ArenaMaxSlots; i++){
		if(v->arena->slots[i].used && strcmp(v->arena->slots[i].name, cname) == 0){
			found = 1;
			break;
		}
	}
	free(cname);
	return found;
}

vlong
o9_vault_drop(O9Vault *v, O9String *name)
{
	char *cname;
	int i;
	O9KeySlot *slot;

	if(v == nil || v->arena == nil || !v->arena->valid || name == nil)
		return 0;
	cname = o9_string_cstr(name);
	if(cname == nil)
		return 0;
	slot = nil;
	for(i = 0; i < O9ArenaMaxSlots; i++){
		if(v->arena->slots[i].used && strcmp(v->arena->slots[i].name, cname) == 0){
			slot = &v->arena->slots[i];
			break;
		}
	}
	free(cname);
	if(slot == nil)
		return 0;
	if(slot->ct != nil){
		crypto_wipe(slot->ct, (size_t)slot->nct);
		free(slot->ct);
		slot->ct = nil;
	}
	crypto_wipe(slot, sizeof *slot);
	slot->used = 0;
	v->arena->nslots--;
	return 1;
}

void
o9_vault_wipe(O9Vault *v)
{
	int i;

	if(v == nil || v->arena == nil)
		return;
	for(i = 0; i < O9ArenaMaxSlots; i++){
		if(v->arena->slots[i].used && v->arena->slots[i].ct != nil){
			crypto_wipe(v->arena->slots[i].ct, (size_t)v->arena->slots[i].nct);
			free(v->arena->slots[i].ct);
			v->arena->slots[i].ct = nil;
		}
	}
	crypto_wipe(v->arena->key, sizeof v->arena->key);
	crypto_wipe(v->arena->salt, sizeof v->arena->salt);
	v->arena->has_salt = 0;
	crypto_wipe(v->arena->slots, sizeof v->arena->slots);
	v->arena->valid = 0;
	v->arena->nslots = 0;
}

void
o9_vault_close(O9Vault *v)
{
	if(v == nil)
		return;
	if(v->arena != nil){
		o9_vault_wipe(v);
		free(v->arena);
		v->arena = nil;
	}
	free(v);
}

