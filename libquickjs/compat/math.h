#ifndef P9_COMPAT_MATH_H
#define P9_COMPAT_MATH_H

#include <stdint.h>

/* Native Plan 9 libc spells these NaN()/Inf()/isNaN()/isInf(). */
double NaN(void);
double Inf(int);
int isNaN(double);
int isInf(double, int);

double fabs(double);
double floor(double);
double ceil(double);
double fmod(double, double);
double modf(double, double *);
double frexp(double, int *);
double ldexp(double, int);
double pow(double, double);
double sqrt(double);
double exp(double);
double log(double);
double log10(double);
double sin(double);
double cos(double);
double tan(double);
double asin(double);
double acos(double);
double atan(double);
double atan2(double, double);
double sinh(double);
double cosh(double);
double tanh(double);
double hypot(double, double);

/* Provided by p9math.c or by the vendored musl math set. */
double fmin(double, double);
double fmax(double, double);
long lrint(double);
int p9_signbit(double);

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

#ifndef NAN
#define NAN (NaN())
#endif
#ifndef INFINITY
#define INFINITY (Inf(1))
#endif
#ifndef HUGE_VAL
#define HUGE_VAL (Inf(1))
#endif

#ifndef isnan
#define isnan(x) isNaN(x)
#endif
#ifndef isinf
#define isinf(x) (isInf((x), 1) || isInf((x), -1))
#endif
#ifndef isfinite
#define isfinite(x) (!isnan(x) && !isinf(x))
#endif
#ifndef signbit
#define signbit(x) p9_signbit(x)
#endif

#endif
