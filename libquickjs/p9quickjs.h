#ifndef P9QUICKJS_H
#define P9QUICKJS_H

/*
 * Minimal embedding API for native Plan 9 lib9p servers.
 *
 * This header deliberately forward-declares JSRuntime/JSContext instead of
 * including quickjs.h.  A server that already includes <u.h> and <libc.h>
 * can include p9quickjs.h without pulling the engine's C99 compatibility
 * headers into the server translation unit.  Include quickjs.h separately
 * only in files that install native bindings.
 */

/*
 * No standard headers are included here, so a native lib9p server can
 * include <u.h>/<libc.h> and then this file without -Icompat.  On native
 * amd64 Plan 9, unsigned long is the machine word and matches size_t.
 */
struct JSRuntime;
struct JSContext;

typedef struct P9JS P9JS;

#define P9JS_DEFAULT_MEMORY_LIMIT (16UL * 1024 * 1024)
#define P9JS_DEFAULT_MAX_STACK_SIZE (256UL * 1024)

typedef struct P9JSOptions {
	/* 0 selects the default.  These are engine allocation/stack limits,
	 * not a security boundary; the host should also enforce its own. */
	unsigned long memory_limit;
	unsigned long max_stack_size;

	/* Polled by the interpreter.  Return nonzero to abort execution. */
	int (*interrupt)(void *opaque);

	/* Optional sinks for the global print() and for exception text.
	 * With no output sink, print() writes to fd 1; errors go to fd 2. */
	void (*output)(void *opaque, const char *s, unsigned long n);
	void (*error)(void *opaque, const char *s, unsigned long n);

	void *opaque;
} P9JSOptions;

/* Create a runtime and context.  Returns nil on failure. */
P9JS *p9js_new(const P9JSOptions *opts);

/* Evaluate a NUL-terminated global script.
 *
 * Returns 0 on success, -1 on a JavaScript exception or allocation failure.
 * On success, if result is non-nil it receives a malloc(2)-allocated UTF-8
 * string of the completion value; free it with free(2).  filename may be
 * nil, in which case "<eval>" is used.
 */
int p9js_eval(P9JS *js, const char *src, const char *filename, char **result);

/* Free the context, runtime, and wrapper.  Safe on nil. */
void p9js_free(P9JS *js);

/* Escape hatches for host bindings.  The returned pointers are owned by js.
 * These are the same types as QuickJS's JSContext/JSRuntime typedefs. */
struct JSContext *p9js_context(P9JS *js);
struct JSRuntime *p9js_runtime(P9JS *js);

#endif
