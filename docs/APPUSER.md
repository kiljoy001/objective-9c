# AppUser identity design

`AppUser` is an application identity, separate from the user's Plan 9 login.
An IRC nickname, display name, alias, and email are profile claims; none grants
access. The application principal is an application ID and a verified signing
key. Different applications create different keys by default.

## Stock 9front signing

The initial signing algorithm is RSA with SHA-256 and PKCS #1 v1.5 padding.
Stock 9front's `auth/rsagen` generates a key and `auth/factotum` supports
`proto=rsa role=sign hash=sha256` through `/mnt/factotum/rpc`. The caller hashes
the exact challenge bytes with SHA-256, then asks factotum to sign the 32-byte
digest. The private key stays in factotum during normal use. The server verifies
the signature using the public modulus and exponent in the `AppUser` profile.

Key records need a `service=appuser` selector and an `app=` selector so one
application cannot accidentally select another application's key. A key must
be stored in the user's protected key store for use after a restart; loading it
into factotum alone does not persist it. Key generation, enrollment, and
recovery should be separate operations from signing an ordinary login.

Objective-9C's current `keygen`/`pubkey`/`sign`/`verify` functions use
Monocypher EdDSA-BLAKE2b. That algorithm is not RFC 8032 Ed25519 and does not
match stock 9front factotum's RSA signing role. `AppUser` must use a distinct,
explicitly named RSA API; changing the existing functions would break stored
keys and signatures.

## Profile and authentication

A public `.tab` profile should carry at least `app`, `algorithm`, `modulus`,
`exponent`, `name`, `alias`, and optional `email`. Its stable key ID is a
SHA-256 digest of a canonical encoding of the algorithm and public key, scoped
to the application ID. Display fields can change without changing identity.
An email address is unverified unless the application separately verifies it.

The server issues a fresh, single-use challenge bound to its application ID,
service identity, and connection. The client signs a versioned, unambiguous
encoding of that challenge. After verification, the generated 9P server binds
the resulting `app:key-id` principal to the attach and uses it for every owned
clone check. The client must not be able to supply or replace that principal
through a 9P username, `ctl` command, or IRC nickname. Authentication does not
provide transport confidentiality; remote private data needs a protected
channel as well.

`stdlib/appuser.o9` now provides the public profile, scoped challenge,
factotum signing, and RSA verification. The disposable 9front VM check is
`python3 o9c/test/test_appuser_rsa_qemu.py /path/to/9front.img`; it checks a
stock factotum signature, checks independent keys for two applications, and
rejects a different app, service, nonce, and key.

The application server still needs enrollment, a trusted mapping from the
public key to its permissions, single-use nonce tracking, and a verified
principal bound to each 9P attach. Until that integration exists, an
`AppUser` proof alone does not grant access to an o9irc or other 9P view.
