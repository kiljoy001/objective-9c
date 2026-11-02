#ifndef P9_COMPAT_STDIO_H
#define P9_COMPAT_STDIO_H

#include <stddef.h>
#include <stdarg.h>

/* Native Plan 9 stdio has no include guard.  Keep one header with a guard
 * so quickjs.c and quickjs.h can both include it.  FILE must match libstdio's
 * layout because stdout/stderr are macros over _IO_stream. */
typedef struct {
	int fd;
	char flags;
	char state;
	char *buf;
	char *rp;
	char *wp;
	char *lp;
	long bufl;
	char unbuf[1];
} FILE;
extern FILE _IO_stream[];

#define stdin  (&_IO_stream[0])
#define stdout (&_IO_stream[1])
#define stderr (&_IO_stream[2])

#define EOF (-1)
#define BUFSIZ 4096
#define FILENAME_MAX 256
#define FOPEN_MAX 64
#define L_tmpnam 32
#define TMP_MAX 10000
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

int printf(const char *, ...);
int putchar(int);
int getchar(void);
int fprintf(FILE *, const char *, ...);
int sprintf(char *, const char *, ...);
int snprintf(char *, int, const char *, ...);
int vsnprintf(char *, int, const char *, va_list);
int fflush(FILE *);
int fputs(const char *, FILE *);
int fputc(int, FILE *);
int fgetc(FILE *);
char *fgets(char *, int, FILE *);
FILE *fopen(const char *, const char *);
FILE *fdopen(int, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int);
long ftell(FILE *);
int feof(FILE *);
int ferror(FILE *);
void clearerr(FILE *);
int ungetc(int, FILE *);
int fileno(FILE *);
FILE *tmpfile(void);

#endif
