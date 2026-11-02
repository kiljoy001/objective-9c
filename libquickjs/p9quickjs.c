#include <u.h>
#include "p9quickjs.h"
#include "quickjs.h"

/* Declared here rather than pulling <libc.h> into the engine's compat
 * headers.  These are the native Plan 9 libc symbols. */
extern void setfcr(ulong);
extern void setfsr(ulong);
extern long write(int, void *, long);
extern void exits(char *);

/* ------------------------------------------------------------------ */
/* Plan 9 platform hooks used by the generated9 engine patch          */
/* ------------------------------------------------------------------ */

void
p9_init(void)
{
	/* JavaScript requires round-to-nearest, subnormals, and masked traps. */
	setfcr(0);
	setfsr(0);
}

typedef union Header Header;
union Header {
	size_t size;
	double align;
	void *pointer;
};

void *
p9_malloc(size_t size)
{
	Header *h;

	if(size > SIZE_MAX - sizeof *h)
		return nil;
	h = malloc(sizeof *h + size);
	if(h == nil)
		return nil;
	h->size = size;
	return h + 1;
}

void *
p9_realloc(void *p, size_t size)
{
	Header *h;

	if(p == nil)
		return p9_malloc(size);
	if(size == 0){
		p9_free(p);
		return nil;
	}
	if(size > SIZE_MAX - sizeof *h)
		return nil;
	h = realloc((Header *)p - 1, sizeof *h + size);
	if(h == nil)
		return nil;
	h->size = size;
	return h + 1;
}

void
p9_free(void *p)
{
	if(p != nil)
		free((Header *)p - 1);
}

size_t
p9_msize(const void *p)
{
	return ((const Header *)p)[-1].size;
}

/* QuickJS fatal paths call exit(); native Plan 9 uses exits(). */
void
exit(int status)
{
	exits(status ? "exit" : nil);
}

/* libstdio has no putchar symbol; QuickJS's JS_DumpChar uses it. */
int
putchar(int c)
{
	char b = c;
	write(1, &b, 1);
	return c;
}

/* ------------------------------------------------------------------ */
/* Embedding wrapper                                                   */
/* ------------------------------------------------------------------ */

struct P9JS {
	JSRuntime *rt;
	JSContext *ctx;
	P9JSOptions opts;
};

static int
p9js_interrupt(JSRuntime *rt, void *opaque)
{
	P9JS *js;

	(void)rt;
	js = opaque;
	if(js->opts.interrupt == nil)
		return 0;
	return js->opts.interrupt(js->opts.opaque);
}

static void
p9_emit(P9JS *js, int fd, const char *s, size_t n)
{
	if(js != nil){
		if(fd == 1 && js->opts.output != nil){
			js->opts.output(js->opts.opaque, s, n);
			return;
		}
		if(fd == 2 && js->opts.error != nil){
			js->opts.error(js->opts.opaque, s, n);
			return;
		}
	}
	while(n > 0){
		long w = write(fd, (void *)s, n);

		if(w <= 0)
			return;
		s += w;
		n -= w;
	}
}

static void
p9_emit_string(P9JS *js, int fd, const char *s)
{
	if(s != nil)
		p9_emit(js, fd, s, strlen(s));
}

static JSValue
p9js_print(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv)
{
	P9JS *js;
	int i;

	(void)this_val;
	js = JS_GetContextOpaque(ctx);
	for(i = 0; i < argc; i++){
		const char *s;
		size_t len;

		if(i != 0)
			p9_emit(js, 1, " ", 1);
		s = JS_ToCStringLen(ctx, &len, argv[i]);
		if(s == nil)
			return JS_EXCEPTION;
		p9_emit(js, 1, s, len);
		JS_FreeCString(ctx, s);
	}
	p9_emit(js, 1, "\n", 1);
	return JS_UNDEFINED;
}

static void
p9js_dump_error(P9JS *js)
{
	JSContext *ctx;
	JSValue exc;
	const char *s;

	ctx = js->ctx;
	exc = JS_GetException(ctx);
	s = JS_ToCString(ctx, exc);
	p9_emit_string(js, 2, "Uncaught exception: ");
	if(s != nil){
		p9_emit_string(js, 2, s);
		JS_FreeCString(ctx, s);
	}else{
		p9_emit_string(js, 2, "<exception could not be converted to a string>");
	}
	p9_emit(js, 2, "\n", 1);
	JS_FreeValue(ctx, exc);
}

static char *
p9_strdup(const char *s)
{
	size_t n;
	char *p;

	n = strlen(s) + 1;
	p = malloc(n);
	if(p != nil)
		memcpy(p, s, n);
	return p;
}

P9JS *
p9js_new(const P9JSOptions *opts)
{
	P9JS *js;
	JSValue global, fn;
	int ret;

	js = calloc(1, sizeof *js);
	if(js == nil)
		return nil;
	if(opts != nil)
		js->opts = *opts;
	if(js->opts.memory_limit == 0)
		js->opts.memory_limit = P9JS_DEFAULT_MEMORY_LIMIT;
	if(js->opts.max_stack_size == 0)
		js->opts.max_stack_size = P9JS_DEFAULT_MAX_STACK_SIZE;

	js->rt = JS_NewRuntime();
	if(js->rt == nil){
		free(js);
		return nil;
	}
	JS_SetMemoryLimit(js->rt, js->opts.memory_limit);
	JS_SetMaxStackSize(js->rt, js->opts.max_stack_size);
	JS_SetInterruptHandler(js->rt, p9js_interrupt, js);

	js->ctx = JS_NewContext(js->rt);
	if(js->ctx == nil){
		JS_FreeRuntime(js->rt);
		free(js);
		return nil;
	}
	JS_SetContextOpaque(js->ctx, js);

	global = JS_GetGlobalObject(js->ctx);
	fn = JS_NewCFunction(js->ctx, p9js_print, "print", 1);
	ret = JS_SetPropertyStr(js->ctx, global, "print", fn);
	JS_FreeValue(js->ctx, global);
	if(ret < 0){
		p9js_dump_error(js);
		p9js_free(js);
		return nil;
	}
	return js;
}

int
p9js_eval(P9JS *js, const char *src, const char *filename, char **result)
{
	JSContext *ctx;
	JSValue v;
	const char *s;
	char *out;

	if(result != nil)
		*result = nil;
	if(js == nil || js->ctx == nil || src == nil)
		return -1;
	ctx = js->ctx;
	v = JS_Eval(ctx, src, strlen(src), filename != nil ? filename : "<eval>",
	            JS_EVAL_TYPE_GLOBAL);
	if(JS_IsException(v)){
		p9js_dump_error(js);
		JS_FreeValue(ctx, v);
		return -1;
	}
	if(result != nil){
		s = JS_ToCString(ctx, v);
		if(s == nil){
			p9js_dump_error(js);
			JS_FreeValue(ctx, v);
			return -1;
		}
		out = p9_strdup(s);
		JS_FreeCString(ctx, s);
		if(out == nil){
			p9_emit_string(js, 2, "p9js_eval: out of memory\n");
			JS_FreeValue(ctx, v);
			return -1;
		}
		*result = out;
	}
	JS_FreeValue(ctx, v);
	return 0;
}

void
p9js_free(P9JS *js)
{
	if(js == nil)
		return;
	if(js->ctx != nil)
		JS_FreeContext(js->ctx);
	if(js->rt != nil)
		JS_FreeRuntime(js->rt);
	free(js);
}

JSContext *
p9js_context(P9JS *js)
{
	return js != nil ? js->ctx : nil;
}

JSRuntime *
p9js_runtime(P9JS *js)
{
	return js != nil ? js->rt : nil;
}
