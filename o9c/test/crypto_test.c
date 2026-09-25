#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/* Round-trips o9's crypto verbs against real monocypher under 6c:
 * keypair -> sign -> verify(ok) -> verify(tampered)=fail -> hash-stable. */
void
threadmain(int, char**)
{
	char pub[65], sec[129], sig[129], h1[65], h2[65];
	O9String *pass, *salt, *pk;
	char *spk;
	uchar msg[] = "the network is the computer";
	long n = sizeof msg - 1;

	if(o9_crypto_keypair(pub, sec) != 0)
		sysfatal("keypair");
	if(strlen(pub) != 64 || strlen(sec) != 64)
		sysfatal("key lengths: pub=%ld sec=%ld", strlen(pub), strlen(sec));

	if(o9_crypto_sign(sec, msg, n, sig) != 0)
		sysfatal("sign");
	if(strlen(sig) != 128)
		sysfatal("sig length %ld", strlen(sig));

	if(o9_crypto_verify(pub, msg, n, sig) != 1)
		sysfatal("verify should pass");

	msg[0] = 'T';	/* tamper */
	if(o9_crypto_verify(pub, msg, n, sig) != 0)
		sysfatal("verify should fail on tampered message");
	msg[0] = 't';

	if(o9_crypto_hash(msg, n, h1) != 0 || o9_crypto_hash(msg, n, h2) != 0)
		sysfatal("hash");
	if(strlen(h1) != 64 || strcmp(h1, h2) != 0)
		sysfatal("hash not stable");

	pass = o9_string_from_c("hunter2");
	salt = o9_string_from_c("e2e.vault.salt");
	pk = o9_passkey(pass, salt);
	o9_string_release(pass);
	o9_string_release(salt);
	if(pk == nil)
		sysfatal("passkey returned nil");
	spk = o9_string_cstr(pk);
	o9_string_release(pk);
	if(spk == nil ||
	   strcmp(spk, "81aee1a7dc10473b68f7593ac3ab9bee7e12e08290f886fa23faf4c6d66de95b") != 0)
		sysfatal("passkey mismatch: %s", spk != nil ? spk : "<nil>");
	free(spk);

	/* Vault tests: arena derivation, slot AEAD encryption, seal/open, wipe */
	{
		O9Vault *v;
		O9String *p, *s, *m, *sealed, *opened, *kname, *pval, *gval;
		char *sopened, *sgval;

		p = o9_string_from_c("hunter2");
		s = o9_string_from_c("e2e.vault.salt");
		v = o9_vault_new_pass(p, s);
		o9_string_release(p);
		o9_string_release(s);
		if(v == nil || o9_vault_valid(v) != 1)
			sysfatal("vault_new_pass failed");

		m = o9_string_from_c("super secret message");
		sealed = o9_vault_seal(v, m);
		if(sealed == nil)
			sysfatal("vault_seal failed");
		opened = o9_vault_open(v, sealed);
		if(opened == nil)
			sysfatal("vault_open failed");
		sopened = o9_string_cstr(opened);
		if(sopened == nil || strcmp(sopened, "super secret message") != 0)
			sysfatal("vault_open mismatch: %s", sopened != nil ? sopened : "<nil>");
		free(sopened);
		o9_string_release(opened);

		/* Slot storage (layered defense: data in arena is encrypted) */
		kname = o9_string_from_c("api_key");
		pval = o9_string_from_c("secret-api-token-99");
		if(o9_vault_put(v, kname, pval) != 0)
			sysfatal("vault_put failed");
		if(o9_vault_has(v, kname) != 1)
			sysfatal("vault_has failed");

		/* Ensure arena slot ciphertext does not match plaintext */
		if(v->arena->slots[0].nct != strlen("secret-api-token-99"))
			sysfatal("slot nct mismatch");
		if(memcmp(v->arena->slots[0].ct, "secret-api-token-99", v->arena->slots[0].nct) == 0)
			sysfatal("arena slot must be AEAD encrypted, not plaintext!");

		gval = o9_vault_get(v, kname);
		if(gval == nil)
			sysfatal("vault_get failed");
		sgval = o9_string_cstr(gval);
		if(sgval == nil || strcmp(sgval, "secret-api-token-99") != 0)
			sysfatal("vault_get mismatch: %s", sgval != nil ? sgval : "<nil>");
		free(sgval);
		o9_string_release(gval);

		if(o9_vault_drop(v, kname) != 1)
			sysfatal("vault_drop failed");
		if(o9_vault_has(v, kname) != 0)
			sysfatal("vault_has should be 0 after drop");
		if(o9_vault_get(v, kname) != nil)
			sysfatal("vault_get should be nil after drop");

		/* Wipe zeroes key and marks vault invalid */
		o9_vault_wipe(v);
		if(o9_vault_valid(v) != 0)
			sysfatal("vault_valid should be 0 after wipe");
		if(o9_vault_open(v, sealed) != nil)
			sysfatal("vault_open should fail after wipe");

		o9_string_release(m);
		o9_string_release(sealed);
		o9_string_release(kname);
		o9_string_release(pval);
		o9_vault_close(v);
	}

	print("crypto_test: OK\n");
	threadexitsall(nil);
}
