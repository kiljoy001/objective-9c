#include <u.h>
#include <libc.h>
#define MONO_PLAN9
#include "monocypher.h"
#include "o9.h"

/*
 * o9 crypto stdlib — attestation only.
 *
 * Surface is deliberately the two no-composition primitives libtab trusts:
 * sign/verify (Ed25519) and hash (BLAKE2b), plus keypair generation.  There
 * is NO encrypt/seal here and there will not be: confidentiality is the
 * transport's job (dp9ik on the wire) and the volume's job where a volume
 * exists.  o9 objects ATTEST (integrity, identity) — they do not encrypt
 * payloads, which keeps every persisted value plain text and cat-able.
 * See ARCHITECTURE.md and 9lx's libtab-design.md (the SEALED refusal).
 *
 * All boundary values are lowercase hex so results stay text: a signature
 * or digest can travel in a file, a ctl line, or a libtab cell unchanged.
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
