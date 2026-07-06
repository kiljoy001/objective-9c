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
	if(o9_randbytes(seed, sizeof seed) < 0)
		return -1;
	tohex(seed, 32, sec);	/* the persistent secret is the 32-byte seed */
	/* key_pair expands seed->sk(64) and derives pk; it wipes seed after */
	crypto_eddsa_key_pair(sk, pk, seed);
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
	if(fromhex(sechex, seed, 32) != 32)	/* stored secret is the seed */
		return -1;
	crypto_eddsa_key_pair(sk, pk, seed);	/* expand seed -> 64-byte sk */
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
char*
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
	return sec;
}

/* pubkey(sec) -> 64-hex Ed25519 public key derived from the seed. */
char*
o9_pubkey(char *sec)
{
	uchar seed[32], sk[64], pk[32];
	char *pub;

	if(sec == nil || fromhex(sec, seed, 32) != 32)
		return nil;
	pub = malloc(65);
	if(pub == nil)
		return nil;
	crypto_eddsa_key_pair(sk, pk, seed);	/* wipes seed itself */
	tohex(pk, 32, pub);
	crypto_wipe(sk, sizeof sk);
	return pub;
}

/* sign(sec, msg) -> 128-hex Ed25519 signature over the string msg. */
char*
o9_sign(char *sec, char *msg)
{
	char *sig;

	if(sec == nil || msg == nil)
		return nil;
	sig = malloc(129);
	if(sig == nil)
		return nil;
	if(o9_crypto_sign(sec, (uchar*)msg, strlen(msg), sig) < 0){
		free(sig);
		return nil;
	}
	return sig;
}

/* verify(pub, msg, sig) -> 1 valid, 0 invalid, -1 malformed input. */
vlong
o9_verify(char *pub, char *msg, char *sig)
{
	if(pub == nil || msg == nil || sig == nil)
		return -1;
	return o9_crypto_verify(pub, (uchar*)msg, strlen(msg), sig);
}

/* hash(msg) -> 64-hex BLAKE2b-256 of the string msg.  (Named o9_digest:
 * o9_hash is the runtime's selector hash in o9_runtime.c.) */
char*
o9_digest(char *msg)
{
	char *out;

	if(msg == nil)
		return nil;
	out = malloc(65);
	if(out == nil)
		return nil;
	if(o9_crypto_hash((uchar*)msg, strlen(msg), out) < 0){
		free(out);
		return nil;
	}
	return out;
}

/* mac(key, msg) -> 64-hex keyed BLAKE2b-256; symmetric attestation.
 * key is 64 hex chars (32 bytes) — any keygen() output works. */
char*
o9_mac(char *keyhex, char *msg)
{
	uchar key[32], h[32];
	char *out;

	if(keyhex == nil || msg == nil)
		return nil;
	if(fromhex(keyhex, key, 32) != 32)
		return nil;
	out = malloc(65);
	if(out == nil){
		crypto_wipe(key, sizeof key);
		return nil;
	}
	crypto_blake2b_keyed(h, sizeof h, key, sizeof key, (uchar*)msg, strlen(msg));
	crypto_wipe(key, sizeof key);
	tohex(h, 32, out);
	return out;
}

/* encrypt(key, msg) -> hex(nonce[24] || mac[16] || ciphertext), one
 * self-contained blob.  XChaCha20-Poly1305; the nonce is drawn fresh
 * from the system RNG on every call and carried in the blob, so key
 * reuse is safe and there is no nonce argument to get wrong. */
char*
o9_encrypt(char *keyhex, char *msg)
{
	uchar key[32], nonce[24], mac[16], *ct;
	char *out;
	long n;

	if(keyhex == nil || msg == nil)
		return nil;
	if(fromhex(keyhex, key, 32) != 32)
		return nil;
	n = strlen(msg);
	ct = malloc(n == 0 ? 1 : n);
	out = malloc(2*(24 + 16 + n) + 1);
	if(ct == nil || out == nil || o9_randbytes(nonce, sizeof nonce) < 0){
		free(ct);
		free(out);
		crypto_wipe(key, sizeof key);
		return nil;
	}
	crypto_aead_lock(ct, mac, key, nonce, nil, 0, (uchar*)msg, (size_t)n);
	crypto_wipe(key, sizeof key);
	tohex(nonce, 24, out);
	tohex(mac, 16, out + 48);
	tohex(ct, n, out + 80);
	free(ct);
	return out;
}

/* decrypt(key, blob) -> plaintext string, or nil if the key is wrong
 * or the blob was tampered with (Poly1305 authentication fails). */
char*
o9_decrypt(char *keyhex, char *blob)
{
	uchar key[32], nonce[24], mac[16], *buf;
	char *pt;
	long nb, n;

	if(keyhex == nil || blob == nil)
		return nil;
	nb = strlen(blob);
	if(nb % 2 != 0 || nb/2 < 24 + 16)
		return nil;
	n = nb/2;
	if(fromhex(keyhex, key, 32) != 32)
		return nil;
	buf = malloc(n);
	pt = malloc(n - 40 + 1);
	if(buf == nil || pt == nil || fromhex(blob, buf, n) != n){
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
	return pt;
}

/* passkey(password, salt) -> 64-hex key via Argon2id, ready to feed
 * encrypt/mac.  Deterministic: the same password+salt always derives
 * the same key, so a secret sealed in an object can be reopened from
 * the passphrase alone — nothing key-shaped needs storing.  Cost is
 * libtab's default (64 MiB, 3 passes, 1 lane; tab_hashed.c), so
 * password hardness is uniform across the stack.  Salt is per-secret
 * context, 8 bytes minimum (argon2 requirement). */
char*
o9_passkey(char *pass, char *salt)
{
	crypto_argon2_config cfg;
	crypto_argon2_inputs in;
	uchar h[32];
	char *out;
	void *work;

	if(pass == nil || salt == nil || strlen(salt) < 8)
		return nil;
	cfg.algorithm = CRYPTO_ARGON2_ID;
	cfg.nb_blocks = 65536;	/* 64 MiB: libtab's Argon2dDefMlog2 */
	cfg.nb_passes = 3;
	cfg.nb_lanes = 1;
	in.pass = (uchar*)pass;
	in.pass_size = strlen(pass);
	in.salt = (uchar*)salt;
	in.salt_size = strlen(salt);
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
	return out;
}

/* xpubkey(sec) -> 64-hex X25519 public key; sec is any keygen() seed.
 * X25519 keys are separate from Ed25519 ones — don't reuse a signing
 * seed for exchange. */
char*
o9_xpubkey(char *sec)
{
	uchar sk[32], pk[32];
	char *pub;

	if(sec == nil || fromhex(sec, sk, 32) != 32)
		return nil;
	pub = malloc(65);
	if(pub == nil){
		crypto_wipe(sk, sizeof sk);
		return nil;
	}
	crypto_x25519_public_key(pk, sk);
	crypto_wipe(sk, sizeof sk);
	tohex(pk, 32, pub);
	return pub;
}

/* exchange(mysec, theirpub) -> 64-hex shared key: BLAKE2b-256 of the
 * raw X25519 secret, ready to feed encrypt/mac directly.  Both sides
 * agree: exchange(a, xpubkey(b)) == exchange(b, xpubkey(a)).  Returns
 * nil if the peer key is low-order (raw shared secret all zero). */
char*
o9_exchange(char *sec, char *pub)
{
	uchar sk[32], pk[32], raw[32], h[32];
	char *out;
	int i, z;

	if(sec == nil || pub == nil)
		return nil;
	if(fromhex(sec, sk, 32) != 32 || fromhex(pub, pk, 32) != 32)
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
	return out;
}
