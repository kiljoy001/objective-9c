// Monocypher version 4.0.2
//
// This file is dual-licensed.  Choose whichever licence you want from
// the two licences listed below.
//
// The first licence is a regular 2-clause BSD licence.  The second licence
// is the CC-0 from Creative Commons. It is intended to release Monocypher
// to the public domain.  The BSD licence serves as a fallback option.
//
// SPDX-License-Identifier: BSD-2-Clause OR CC0-1.0
//
// ------------------------------------------------------------------------
//
// Copyright (c) 2017-2019, Loup Vaillant
// All rights reserved.
//
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the
//    distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ------------------------------------------------------------------------
//
// Written in 2017-2019 by Loup Vaillant
//
// To the extent possible under law, the author(s) have dedicated all copyright
// and related neighboring rights to this software to the public domain
// worldwide.  This software is distributed without any warranty.
//
// You should have received a copy of the CC0 Public Domain Dedication along
// with this software.  If not, see
// <https://creativecommons.org/publicdomain/zero/1.0/>

// Explicit type definitions replaced by stdint.h usage
#ifndef MONOCYPHER_H
#define MONOCYPHER_H

#ifdef MONO_PLAN9
/* o9/9front userland: <u.h>/<libc.h> already included by the translation
 * unit.  Flat #ifdef-only block — 6c's cpp rejects "#if defined(...)". */
#ifndef _STDINT_PLAN9_H
#define _STDINT_PLAN9_H
typedef u8int uint8_t;
typedef u16int uint16_t;
typedef u32int uint32_t;
typedef u64int uint64_t;
typedef s8int int8_t;
typedef s16int int16_t;
typedef s32int int32_t;
typedef s64int int64_t;
typedef ulong size_t;
#endif
#else
#ifdef KERNEL
#include "u.h"
#ifndef _STDINT_KERNEL_H
#define _STDINT_KERNEL_H
#ifdef __UINT8_TYPE__
typedef __UINT8_TYPE__ uint8_t;
typedef __UINT16_TYPE__ uint16_t;
typedef __UINT32_TYPE__ uint32_t;
typedef __UINT64_TYPE__ uint64_t;
typedef __INT8_TYPE__ int8_t;
typedef __INT16_TYPE__ int16_t;
typedef __INT32_TYPE__ int32_t;
typedef __INT64_TYPE__ int64_t;
#else
typedef u8int uint8_t;
typedef u16int uint16_t;
typedef u32int uint32_t;
typedef u64int uint64_t;
typedef s8int int8_t;
typedef s16int int16_t;
typedef s32int int32_t;
typedef s64int int64_t;
#endif
#endif
#ifndef _SIZE_T_DEFINED_
#define _SIZE_T_DEFINED_
#ifdef __SIZE_TYPE__
typedef __SIZE_TYPE__ size_t;
#else
typedef ulong size_t;
#endif
#endif
#else
#include <stddef.h>
#include <stdint.h>
#endif
#endif

#ifdef MONOCYPHER_CPP_NAMESPACE
namespace MONOCYPHER_CPP_NAMESPACE {
#elif defined(__cplusplus)
extern "C" {
#endif

// Constant time comparisons
// -------------------------

// Return 0 if a and b are equal, -1 otherwise
int crypto_verify16(const uint8_t a[16], const uint8_t b[16]);
int crypto_verify32(const uint8_t a[32], const uint8_t b[32]);
int crypto_verify64(const uint8_t a[64], const uint8_t b[64]);

// Erase sensitive data
// --------------------
/*@ requires size == 0 || secret != \null;
    requires size == 0 || \valid(((uint8_t*)secret) + (0 .. (size - 1)));
    terminates \true;
    assigns ((uint8_t*)secret)[0 .. (size - 1)];
*/
void crypto_wipe(void *secret, size_t size);

// Authenticated encryption
// ------------------------
void crypto_aead_lock(uint8_t *cipher_text, uint8_t mac[16],
                      const uint8_t key[32], const uint8_t nonce[24],
                      const uint8_t *ad, size_t ad_size,
                      const uint8_t *plain_text, size_t text_size);
int crypto_aead_unlock(uint8_t *plain_text, const uint8_t mac[16],
                       const uint8_t key[32], const uint8_t nonce[24],
                       const uint8_t *ad, size_t ad_size,
                       const uint8_t *cipher_text, size_t text_size);

// Authenticated stream
// --------------------
typedef struct {
  uint64_t counter;
  uint8_t key[32];
  uint8_t nonce[8];
} crypto_aead_ctx;

void crypto_aead_init_x(crypto_aead_ctx *ctx, const uint8_t key[32],
                        const uint8_t nonce[24]);
void crypto_aead_init_djb(crypto_aead_ctx *ctx, const uint8_t key[32],
                          const uint8_t nonce[8]);
void crypto_aead_init_ietf(crypto_aead_ctx *ctx, const uint8_t key[32],
                           const uint8_t nonce[12]);

void crypto_aead_write(crypto_aead_ctx *ctx, uint8_t *cipher_text,
                       uint8_t mac[16], const uint8_t *ad, size_t ad_size,
                       const uint8_t *plain_text, size_t text_size);
int crypto_aead_read(crypto_aead_ctx *ctx, uint8_t *plain_text,
                     const uint8_t mac[16], const uint8_t *ad, size_t ad_size,
                     const uint8_t *cipher_text, size_t text_size);

// General purpose hash (BLAKE2b)
// ------------------------------

// Direct interface
void crypto_blake2b(uint8_t *hash, size_t hash_size, const uint8_t *message,
                    size_t message_size);

void crypto_blake2b_keyed(uint8_t *hash, size_t hash_size, const uint8_t *key,
                          size_t key_size, const uint8_t *message,
                          size_t message_size);

// Incremental interface
typedef struct {
  // Do not rely on the size or contents of this type,
  // for they may change without notice.
  uint64_t hash[8];
  uint64_t input_offset[2];
  uint64_t input[16];
  size_t input_idx;
  size_t hash_size;
} crypto_blake2b_ctx;

/*@
  @ requires \valid(ctx);
  @ requires hash_size > 0 && hash_size <= 64;
  @ assigns *ctx;
  @*/
void crypto_blake2b_init(crypto_blake2b_ctx *ctx, size_t hash_size);
void crypto_blake2b_keyed_init(crypto_blake2b_ctx *ctx, size_t hash_size,
                               const uint8_t *key, size_t key_size);
/*@
  @ requires \valid(ctx);
  @ requires \valid_read(message + (0 .. message_size - 1));
  @ assigns *ctx;
  @*/
void crypto_blake2b_update(crypto_blake2b_ctx *ctx, const uint8_t *message,
                           size_t message_size);
/*@
  @ requires \valid(ctx);
  @ requires \valid(hash + (0 .. 63));
  @ assigns *ctx, hash[0 .. 63];
  @*/
void crypto_blake2b_final(crypto_blake2b_ctx *ctx, uint8_t *hash);

// Password key derivation (Argon2)
// --------------------------------
#define CRYPTO_ARGON2_D 0
#define CRYPTO_ARGON2_I 1
#define CRYPTO_ARGON2_ID 2

typedef struct {
  uint32_t algorithm; // Argon2d, Argon2i, Argon2id
  uint32_t nb_blocks; // memory hardness, >= 8 * nb_lanes
  uint32_t nb_passes; // CPU hardness, >= 1 (>= 3 recommended for Argon2i)
  uint32_t nb_lanes;  // parallelism level (single threaded anyway)
} crypto_argon2_config;

typedef struct {
  const uint8_t *pass;
  const uint8_t *salt;
  uint32_t pass_size;
  uint32_t salt_size; // 16 bytes recommended
} crypto_argon2_inputs;

typedef struct {
  const uint8_t *key; // may be NULL if no key
  const uint8_t *ad;  // may be NULL if no additional data
  uint32_t key_size;  // 0 if no key (32 bytes recommended otherwise)
  uint32_t ad_size;   // 0 if no additional data
} crypto_argon2_extras;

extern const crypto_argon2_extras crypto_argon2_no_extras;

/*@ requires hash_size > 0;
    requires \valid(hash + (0 .. (hash_size - 1)));
    requires config.nb_blocks > 0;
    requires \valid(((uint8_t*)work_area) + (0 .. ((size_t)config.nb_blocks *
   1024 - 1))); terminates \true; assigns hash[0 .. (hash_size - 1)]; assigns
   ((uint8_t*)work_area)[0 .. ((size_t)config.nb_blocks * 1024 - 1)];
*/
void crypto_argon2(uint8_t *hash, uint32_t hash_size, void *work_area,
                   crypto_argon2_config config, crypto_argon2_inputs inputs,
                   crypto_argon2_extras extras);

// Key exchange (X-25519)
// ----------------------

// Shared secrets are not quite random.
// Hash them to derive an actual shared key.
void crypto_x25519_public_key(uint8_t public_key[32],
                              const uint8_t secret_key[32]);
void crypto_x25519(uint8_t raw_shared_secret[32],
                   const uint8_t your_secret_key[32],
                   const uint8_t their_public_key[32]);

// Conversion to EdDSA
void crypto_x25519_to_eddsa(uint8_t eddsa[32], const uint8_t x25519[32]);

// scalar "division"
// Used for OPRF.  Be aware that exponential blinding is less secure
// than Diffie-Hellman key exchange.
void crypto_x25519_inverse(uint8_t blind_salt[32],
                           const uint8_t private_key[32],
                           const uint8_t curve_point[32]);

// "Dirty" versions of x25519_public_key().
// Use with crypto_elligator_rev().
// Leaks 3 bits of the private key.
void crypto_x25519_dirty_small(uint8_t pk[32], const uint8_t sk[32]);
void crypto_x25519_dirty_fast(uint8_t pk[32], const uint8_t sk[32]);

// Signatures
// ----------

// EdDSA with curve25519 + BLAKE2b
void crypto_eddsa_key_pair(uint8_t secret_key[64], uint8_t public_key[32],
                           uint8_t seed[32]);
void crypto_eddsa_sign(uint8_t signature[64], const uint8_t secret_key[64],
                       const uint8_t *message, size_t message_size);
int crypto_eddsa_check(const uint8_t signature[64],
                       const uint8_t public_key[32], const uint8_t *message,
                       size_t message_size);

// Conversion to X25519
void crypto_eddsa_to_x25519(uint8_t x25519[32], const uint8_t eddsa[32]);

// EdDSA building blocks
void crypto_eddsa_trim_scalar(uint8_t out[32], const uint8_t in[32]);
void crypto_eddsa_reduce(uint8_t reduced[32], const uint8_t expanded[64]);
void crypto_eddsa_mul_add(uint8_t r[32], const uint8_t a[32],
                          const uint8_t b[32], const uint8_t c[32]);
void crypto_eddsa_scalarbase(uint8_t point[32], const uint8_t scalar[32]);
int crypto_eddsa_check_equation(const uint8_t signature[64],
                                const uint8_t public_key[32],
                                const uint8_t h_ram[32]);

// Chacha20
// --------

// Specialised hash.
// Used to hash X25519 shared secrets.
void crypto_chacha20_h(uint8_t out[32], const uint8_t key[32],
                       const uint8_t in[16]);

// Unauthenticated stream cipher.
// Don't forget to add authentication.
uint64_t crypto_chacha20_djb(uint8_t *cipher_text, const uint8_t *plain_text,
                             size_t text_size, const uint8_t key[32],
                             const uint8_t nonce[8], uint64_t ctr);
uint32_t crypto_chacha20_ietf(uint8_t *cipher_text, const uint8_t *plain_text,
                              size_t text_size, const uint8_t key[32],
                              const uint8_t nonce[12], uint32_t ctr);
/*@ requires cipher_text == \null || text_size == 0 ||
             \valid(cipher_text + (0..text_size - 1));
  @ requires plain_text == \null || text_size == 0 ||
             \valid_read(plain_text + (0..text_size - 1));
  @ requires key == \null || \valid_read(key + (0..31));
  @ requires nonce == \null || \valid_read(nonce + (0..23));
  @ terminates \true;
  @ assigns cipher_text[0..text_size - 1];
  */
uint64_t crypto_chacha20_x(uint8_t *cipher_text, const uint8_t *plain_text,
                           size_t text_size, const uint8_t key[32],
                           const uint8_t nonce[24], uint64_t ctr);

// Poly 1305
// ---------

// This is a *one time* authenticator.
// Disclosing the mac reveals the key.
// See crypto_lock() on how to use it properly.

// Direct interface
void crypto_poly1305(uint8_t mac[16], const uint8_t *message,
                     size_t message_size, const uint8_t key[32]);

// Incremental interface
typedef struct {
  // Do not rely on the size or contents of this type,
  // for they may change without notice.
  uint8_t c[16];   // chunk of the message
  size_t c_idx;    // How many bytes are there in the chunk.
  uint32_t r[4];   // constant multiplier (from the secret key)
  uint32_t pad[4]; // random number added at the end (from the secret key)
  uint32_t h[5];   // accumulated hash
} crypto_poly1305_ctx;

void crypto_poly1305_init(crypto_poly1305_ctx *ctx, const uint8_t key[32]);
void crypto_poly1305_update(crypto_poly1305_ctx *ctx, const uint8_t *message,
                            size_t message_size);
void crypto_poly1305_final(crypto_poly1305_ctx *ctx, uint8_t mac[16]);

// Elligator 2
// -----------

// Elligator mappings proper
void crypto_elligator_map(uint8_t curve[32], const uint8_t hidden[32]);
int crypto_elligator_rev(uint8_t hidden[32], const uint8_t curve[32],
                         uint8_t tweak);

// Easy to use key pair generation
void crypto_elligator_key_pair(uint8_t hidden[32], uint8_t secret_key[32],
                               uint8_t seed[32]);

#ifdef __cplusplus
}
#endif

#endif // MONOCYPHER_H
