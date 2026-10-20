#include <math.h>
#include <stdint.h>

/*
 * Small native Plan 9 math shims for QuickJS.
 *
 * The normal build also compiles math/*.c from musl 1.2.5, which provides
 * acosh/asinh/atanh/expm1/log1p/log2/cbrt/round/trunc/scalbn and the
 * double-precision routines.  This file supplies only the pieces the musl
 * set does not: signbit, the GCC bit builtins 6c lacks, lrint, fmin/fmax,
 * and an optional approximate bootstrap set (-DP9MATH_FALLBACK).
 */

int
p9_signbit(double x)
{
	union {
		double d;
		uint64_t u;
	} v;

	v.d = x;
	return (int)(v.u >> 63);
}

static double
p9_negzero(void)
{
	union {
		uint64_t u;
		double d;
	} v;

	/* Do not write -0.0 as a literal: 6c may fold it to +0. */
	v.u = UINT64_C(0x8000000000000000);
	return v.d;
}

int
__builtin_clz(unsigned int x)
{
	int n;

	if(x == 0)
		return 32;
	for(n = 0; (x & 0x80000000U) == 0; n++)
		x <<= 1;
	return n;
}

int
__builtin_ctz(unsigned int x)
{
	int n;

	if(x == 0)
		return 32;
	for(n = 0; (x & 1) == 0; n++)
		x >>= 1;
	return n;
}

int
__builtin_clzll(uint64_t x)
{
	return (x >> 32) != 0 ? __builtin_clz((unsigned int)(x >> 32))
	                      : 32 + __builtin_clz((unsigned int)x);
}

int
__builtin_ctzll(uint64_t x)
{
	return (uint32_t)x != 0 ? __builtin_ctz((unsigned int)x)
	                        : 32 + __builtin_ctz((unsigned int)(x >> 32));
}

double
fmax(double x, double y)
{
	if(isnan(x))
		return y;
	if(isnan(y))
		return x;
	if(x == y)
		return p9_signbit(x) ? y : x;
	return x > y ? x : y;
}

double
fmin(double x, double y)
{
	if(isnan(x))
		return y;
	if(isnan(y))
		return x;
	if(x == y)
		return p9_signbit(x) ? x : y;
	return x < y ? x : y;
}

/* QuickJS only uses lrint for nonnegative values representable in a long. */
long
lrint(double x)
{
	double i, f;

	i = floor(x);
	f = x - i;
	if(f > 0.5 || (f == 0.5 && fmod(i, 2.0) != 0))
		i++;
	return (long)i;
}

#ifdef P9MATH_FALLBACK

double
trunc(double x)
{
	double i;

	if(isnan(x) || isinf(x))
		return x;
	modf(x, &i);
	return i;
}

double
round(double x)
{
	double i, f;

	if(isnan(x) || isinf(x) || x == 0)
		return x;
	modf(x, &i);
	f = x - i;
	if(f >= 0.5)
		i += 1;
	else if(f <= -0.5)
		i -= 1;
	if(i == 0 && p9_signbit(x))
		return p9_negzero();
	return i;
}

double
acosh(double x)
{
	if(isnan(x) || x < 1)
		return NAN;
	if(x == 1)
		return 0;
	return log(x + sqrt(x - 1) * sqrt(x + 1));
}

double
asinh(double x)
{
	if(isnan(x) || isinf(x) || x == 0)
		return x;
	if(x < 0)
		return -asinh(-x);
	return log(x + sqrt(x * x + 1));
}

double
atanh(double x)
{
	if(isnan(x) || x < -1 || x > 1)
		return NAN;
	if(x == 1)
		return INFINITY;
	if(x == -1)
		return -INFINITY;
	return 0.5 * log((1 + x) / (1 - x));
}

double
expm1(double x)
{
	if(isnan(x) || isinf(x) || x == 0)
		return x;
	if(fabs(x) < 1e-5)
		return x + x * x / 2 + x * x * x / 6;
	return exp(x) - 1;
}

double
log1p(double x)
{
	if(isnan(x) || x < -1)
		return NAN;
	if(x == -1)
		return -INFINITY;
	if(isinf(x) || x == 0)
		return x;
	if(fabs(x) < 1e-4)
		return x - x * x / 2 + x * x * x / 3;
	return log(1 + x);
}

double
log2(double x)
{
	if(isnan(x) || x < 0)
		return NAN;
	if(x == 0)
		return -INFINITY;
	return log(x) * 1.4426950408889634074;
}

double
cbrt(double x)
{
	double y;

	if(isnan(x) || isinf(x) || x == 0)
		return x;
	y = pow(fabs(x), 1.0 / 3.0);
	y = y - (y * y * y - fabs(x)) / (3 * y * y);
	if(x < 0)
		return -y;
	return y;
}

double
scalbn(double x, int n)
{
	return ldexp(x, n);
}

#endif /* P9MATH_FALLBACK */
