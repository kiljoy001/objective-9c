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
service identity, and a server-generated attach binding. The client signs a
versioned, unambiguous encoding of that challenge. After verification, the
generated 9P server binds the enrolled application principal to that session.
The client may name the enrolled principal it wants to prove, but cannot set
the verified identity through a 9P username, `ctl` command, or IRC nickname.
Authentication does not provide transport confidentiality; remote private data
needs a protected channel as well.

`stdlib/appuser.o9` now provides the public profile, scoped challenge,
factotum signing, and RSA verification. The disposable 9front VM check is
`python3 o9c/test/test_appuser_rsa_qemu.py /path/to/9front.img`; it checks a
stock factotum signature, checks independent keys for two applications, and
rejects a different app, service, nonce, and key.

`AppUserRSAProvider` now holds the trusted enrollment map and the pending
challenge table. Its `enroll`, `challenge`, and `answer` methods are internal
to the serving application. The application must load each public key from a
trusted local source; accepting a profile sent by an unauthenticated client
as enrollment would let that client grant itself access. `challenge` takes a
server-generated connection binding and an enrolled principal and returns a
fresh 64-character nonce. The supplicant calls `AppUser.prove(service, nonce)`
and returns the signature. `answer(binding, nonce, signature)` consumes the
pending challenge before checking it, returning the enrolled principal only
when the signature, binding, nonce, and deadline all match. The provider holds
at most 64 keys and 128 pending challenges. The constructor accepts a lifetime
of 1 to 300 seconds and uses 60 seconds for an out-of-range value.
Enrollment rejects malformed RSA keys and a public key already assigned to
another principal.

For a `.tab` exchange, the application side is:

```o9
AppUserRSAProvider provider = new AppUserRSAProvider("o9irc", "ircfs", 60);
provider.enroll("alice", trustedModulus, trustedExponent);
string challengeWire = provider.challengeTab(serverBinding, "alice");
// Publish challengeWire as this session's challenge.tab.
// Stage the complete response.tab before opening it as a tabula.
tabula response = new tabula(responsePath);
string principal = provider.answerTab(serverBinding, response);
response.close();
```

The supplicant opens `challenge.tab` as a tabula and calls
`user.responseTab(challenge, expectedService)` to produce the serialized
`response.tab` record. The expected service comes from the client's trusted
configuration, not from the received record.
Its private key stays in factotum. The challenge record carries version, app,
service, nonce, and deadline. The response carries version, nonce, and RSA
signature. Neither record carries the server's session binding or the trusted
principal. The provider returns `""` for a failed exchange, and consumes a
well-formed attempted answer once.

`challengeTab`, `responseTab`, and `answerTab` are internal methods, absent
from the generated 9P method table. `serveAppUsers(provider)` now creates a
server where an unauthenticated attach can read `clone` to allocate its own
session, then:

```text
echo auth alice > /n/app/0/ctl
cat /n/app/0/challenge.tab
# Sign that challenge through AppUser.responseTab, then write its .tab bytes:
cat response.tab > /n/app/0/response.tab
cat /n/app/0/status.tab
cat /n/app/0/view/caller
```

The files are scoped to the attach's random server-generated binding. Split
9P writes to `response.tab` are staged on the open fid and processed at clunk.
The response is capped at 4096 bytes before tabula parsing. One completed
response write consumes that challenge's attempt, including a malformed
response; the client can issue a new `auth` request to try again. The verified
principal is passed to the private view controller and used for its calls.
The unauthenticated session pool is capped at 128 slots; unused, unverified
sessions with no open file handles can be reused after ten minutes.
The signing method and raw factotum helper are internal to the supplicant;
they are absent from a served application's 9P method table.

The VM integration check is `python3 o9c/test/test_appuser_files_qemu.py
/path/to/9front.img`. Enrollment remains the application's responsibility: it
must load public keys from a trusted source before calling `serveAppUsers`.
The proof authenticates an application identity; it does not encrypt the
transport.
