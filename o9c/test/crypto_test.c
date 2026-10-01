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
		O9String *p, *s, *m, *sealed, *opened, *kname, *pval, *gval, *longstr;
		char *sopened, *sgval;
		char longsalt[129], longname[65];

		p = o9_string_from_c("hunter2");
		s = o9_string_from_c("e2e.vault.salt");
		v = o9_vault_new_pass(p, s);
		if(v == nil || o9_vault_valid(v) != 1)
			sysfatal("vault_new_pass failed");
		memset(longsalt, 's', 128);
		longsalt[128] = 0;
		longstr = o9_string_from_c(longsalt);
		if(o9_vault_new_pass(p, longstr) != nil)
			sysfatal("oversized salt accepted");
		o9_string_release(longstr);
		o9_string_release(p);
		o9_string_release(s);

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
		memset(longname, 'n', 64);
		longname[64] = 0;
		longstr = o9_string_from_c(longname);
		if(o9_vault_put(v, longstr, pval) != -1 || o9_vault_has(v, longstr) != 0)
			sysfatal("oversized slot name accepted");
		o9_string_release(longstr);
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

	/* Automatic RNG salt test */
	{
		O9Vault *va, *vb;
		O9String *rand_salt, *p, *s_auto, *m2, *sealed2, *opened2;
		char *crand, *cauto, *sopened2;

		rand_salt = o9_salt();
		if(rand_salt == nil)
			sysfatal("o9_salt returned nil");
		crand = o9_string_cstr(rand_salt);
		if(crand == nil || strlen(crand) != 32)
			sysfatal("o9_salt length mismatch");
		free(crand);
		o9_string_release(rand_salt);

		p = o9_string_from_c("hunter2");
		va = o9_vault_new_key(p);
		if(va == nil || o9_vault_valid(va) != 1)
			sysfatal("vault_new_key auto-salt failed");
		s_auto = o9_vault_salt(va);
		if(s_auto == nil)
			sysfatal("vault_salt returned nil");
		cauto = o9_string_cstr(s_auto);
		if(cauto == nil || strlen(cauto) != 32)
			sysfatal("vault_salt length mismatch: %s", cauto != nil ? cauto : "<nil>");

		m2 = o9_string_from_c("auto-salted payload");
		sealed2 = o9_vault_seal(va, m2);
		if(sealed2 == nil)
			sysfatal("vault_seal with auto-salt failed");

		/* Reopen vault with the auto-generated salt */
		vb = o9_vault_new_pass(p, s_auto);
		if(vb == nil || o9_vault_valid(vb) != 1)
			sysfatal("vault_new_pass with auto_salt failed");
		opened2 = o9_vault_open(vb, sealed2);
		if(opened2 == nil)
			sysfatal("vault_open with reopened auto_salt failed");
		sopened2 = o9_string_cstr(opened2);
		if(sopened2 == nil || strcmp(sopened2, "auto-salted payload") != 0)
			sysfatal("auto-salt round-trip mismatch");
		free(sopened2);
		o9_string_release(opened2);

		free(cauto);
		o9_string_release(s_auto);
		o9_string_release(sealed2);
		o9_string_release(m2);
		o9_string_release(p);
		o9_vault_close(va);
		o9_vault_close(vb);
	}

	print("crypto_test: OK\n");
	threadexitsall(nil);
}
