#include <u.h>
#include <stdio.h>
#include "quickjs.h"

/* Native Plan 9 exits with a status string; main's return value is ignored. */
extern void exits(char *);

static void
dumperror(JSContext *ctx)
{
	JSValue exc;
	const char *s;

	exc = JS_GetException(ctx);
	s = JS_ToCString(ctx, exc);
	if(s != nil){
		fprintf(stderr, "exception: %s\n", s);
		JS_FreeCString(ctx, s);
	}else{
		fprintf(stderr, "exception (unprintable)\n");
	}
	JS_FreeValue(ctx, exc);
	fflush(stderr);
}

void
main(void)
{
	JSRuntime *rt;
	JSContext *ctx;
	JSValue v;
	const char *s;

	rt = JS_NewRuntime();
	if(rt == nil){
		fprintf(stderr, "JS_NewRuntime failed\n");
		fflush(stderr);
		exits("runtime");
	}
	ctx = JS_NewContext(rt);
	if(ctx == nil){
		fprintf(stderr, "JS_NewContext failed\n");
		fflush(stderr);
		JS_FreeRuntime(rt);
		exits("context");
	}

	v = JS_Eval(ctx, "1+1", 3, "<test>", JS_EVAL_TYPE_GLOBAL);
	if(JS_IsException(v)){
		dumperror(ctx);
		JS_FreeValue(ctx, v);
		JS_FreeContext(ctx);
		JS_FreeRuntime(rt);
		exits("eval");
	}

	s = JS_ToCString(ctx, v);
	if(s == nil){
		dumperror(ctx);
		JS_FreeValue(ctx, v);
		JS_FreeContext(ctx);
		JS_FreeRuntime(rt);
		exits("tostring");
	}
	printf("1+1 = %s\n", s);
	fflush(stdout);
	JS_FreeCString(ctx, s);

	JS_FreeValue(ctx, v);
	JS_FreeContext(ctx);
	JS_FreeRuntime(rt);
	exits(nil);
}
