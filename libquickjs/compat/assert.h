#ifndef P9_COMPAT_ASSERT_H
#define P9_COMPAT_ASSERT_H

void _assert(char *);

#ifndef assert
#define p9_assert_string(x) #x
#define assert(x) if(x){}else _assert(p9_assert_string(x))
#endif

#endif
