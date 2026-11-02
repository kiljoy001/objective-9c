#ifndef P9_QUICKJS_PLAN9_H
#define P9_QUICKJS_PLAN9_H

/*
 * Native Plan 9 compatibility header for the QuickJS engine.
 *
 * This file is included by quickjs.h and cutils.h when PLAN9 is defined,
 * and by the vendored musl math libm.h as "../plan9.h".  It must not pull
 * in <u.h> or <libc.h>: engine translation units use the small C99 headers
 * in compat/ instead, and p9time.c is the only file that talks to native
 * Plan 9 time APIs directly.
 *
 * Target: native amd64 Plan 9 (6c/6l).  See README.md for the 32-bit caveat.
 */

#include <stdint.h>
#include <stdlib.h>
#include <math.h>

/* 6l/6c do not automatically add libc; these pragmas are recorded in each
 * object that includes this header. */
#pragma lib "libc.a"
#pragma lib "libstdio.a"

#ifndef CONFIG_VERSION
#define CONFIG_VERSION "2026-06-04"
#endif

/* 6c has neither GCC attributes nor GCC builtins. */
#ifndef __attribute
#define __attribute(x)
#endif
#ifndef __attribute__
#define __attribute__(x)
#endif
#ifndef __builtin_expect
#define __builtin_expect(x, y) (x)
#endif

/* Plan 9 allocation accounting used by the generated9 engine patch. */
void *p9_malloc(size_t);
void *p9_realloc(void *, size_t);
void p9_free(void *);
size_t p9_msize(const void *);

/* Called once from JS_NewRuntime under PLAN9. */
void p9_init(void);

/* IEEE-754 helpers and the small bits of C99 libm that Plan 9 lacks.
 * The full set (acosh/asinh/atanh/expm1/log1p/log2/cbrt/round/trunc/
 * scalbn) comes from math/ in the normal build. */
int p9_signbit(double);
int __builtin_clz(unsigned int);
int __builtin_ctz(unsigned int);
int __builtin_clzll(uint64_t);
int __builtin_ctzll(uint64_t);
long lrint(double);
double fmin(double, double);
double fmax(double, double);

/* Optional bootstrap fallbacks, used only with -DP9MATH_FALLBACK and
 * without the musl math objects. */
#ifdef P9MATH_FALLBACK
double acosh(double);
double asinh(double);
double atanh(double);
double expm1(double);
double log1p(double);
double log2(double);
double cbrt(double);
double round(double);
double trunc(double);
double scalbn(double, int);
#endif

#endif /* P9_QUICKJS_PLAN9_H */
