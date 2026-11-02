#ifndef P9_COMPAT_STDLIB_H
#define P9_COMPAT_STDLIB_H

#include <stddef.h>
#include <stdarg.h> /* native stdio.h uses va_list and does not include it */

void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
void abort(void);
void exit(int);

double atof(const char *);
int atoi(const char *);
int abs(int);
long labs(long);
long atol(const char *);
long long atoll(const char *);
double strtod(const char *, char **);
long strtol(const char *, char **, int);
unsigned long strtoul(const char *, char **, int);
long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void *bsearch(const void *, const void *, size_t, size_t,
              int (*)(const void *, const void *));
char *getenv(const char *);
int system(const char *);

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

#endif
