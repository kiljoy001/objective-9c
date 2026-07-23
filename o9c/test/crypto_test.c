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

	print("crypto_test: OK\n");
	threadexitsall(nil);
}
