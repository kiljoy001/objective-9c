#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

int mainstacksize = 65536;

enum {
	STRING_ITERS = 200000,
	SLICE_COLLECTIONS = 10000,
	SLICE_ELEMS = 100,
	TURN_ITERS = 50000
};

static void
run_heap_bench(void)
{
	int i, j;
	vlong t0, t1, dt_str, dt_slice, dt_turn;
	O9String *s;
	O9Slice sl;
	vlong val;

	print("=== Running HEAP Baseline Benchmarks ===\n");

	/* 1. Strings */
	t0 = nsec();
	for(i = 0; i < STRING_ITERS; i++){
		s = o9_string_new("transaction-header-token-alpha", 30);
		if(o9_string_len(s) != 30) sysfatal("corrupt");
		o9_string_release(s);
	}
	t1 = nsec();
	dt_str = t1 - t0;
	print("  Heap ARC String    : %d ops in %.2f ms (%.1f ns/op, %.0f ops/sec)\n",
		STRING_ITERS, (double)dt_str / 1e6, (double)dt_str / STRING_ITERS,
		(STRING_ITERS * 1e9) / dt_str);

	/* 2. Slices */
	t0 = nsec();
	for(i = 0; i < SLICE_COLLECTIONS; i++){
		o9_slice_init(&sl, sizeof(vlong));
		for(j = 0; j < SLICE_ELEMS; j++){
			val = i + j;
			o9_slice_append(&sl, &val);
		}
		o9_slice_free(&sl);
	}
	t1 = nsec();
	dt_slice = t1 - t0;
	print("  Heap Realloc Slice : %d collections in %.2f ms (%.1f ns/collection)\n",
		SLICE_COLLECTIONS, (double)dt_slice / 1e6, (double)dt_slice / SLICE_COLLECTIONS);

	/* 3. Turns */
	t0 = nsec();
	for(i = 0; i < TURN_ITERS; i++){
		O9String *p1 = o9_string_new("sys", 3);
		O9String *p2 = o9_string_new("src", 3);
		O9String *p3 = o9_string_new("cmd", 3);
		O9String *p4 = o9_string_new("auth", 4);
		O9Slice results;
		vlong dummy = 99;

		o9_slice_init(&results, sizeof(vlong));
		o9_slice_append(&results, &dummy);
		o9_slice_append(&results, &dummy);
		o9_slice_append(&results, &dummy);
		o9_slice_append(&results, &dummy);

		o9_slice_free(&results);
		o9_string_release(p1);
		o9_string_release(p2);
		o9_string_release(p3);
		o9_string_release(p4);
	}
	t1 = nsec();
	dt_turn = t1 - t0;
	print("  Heap Turn          : %d turns in %.2f ms (%.1f ns/turn, %.0f turns/sec)\n\n",
		TURN_ITERS, (double)dt_turn / 1e6, (double)dt_turn / TURN_ITERS,
		(TURN_ITERS * 1e9) / dt_turn);
}

static void
run_stack_bench(O9DataStack *ds)
{
	int i, j;
	vlong t0, t1, dt_str, dt_slice, dt_turn;
	O9String *s;
	O9Slice sl;
	vlong val;
	void *mark;

	print("=== Running GOOSE DATASTACK Benchmarks ===\n");

	/* 1. Strings */
	t0 = nsec();
	for(i = 0; i < STRING_ITERS; i++){
		mark = o9_datastack_mark(ds);
		s = o9_datastack_string(ds, "transaction-header-token-alpha", 30);
		if(o9_string_len(s) != 30) sysfatal("corrupt");
		o9_datastack_reset(ds, mark);
	}
	t1 = nsec();
	dt_str = t1 - t0;
	print("  Goose DataStack    : %d ops in %.2f ms (%.1f ns/op, %.0f ops/sec)\n",
		STRING_ITERS, (double)dt_str / 1e6, (double)dt_str / STRING_ITERS,
		(STRING_ITERS * 1e9) / dt_str);

	/* 2. Slices */
	t0 = nsec();
	for(i = 0; i < SLICE_COLLECTIONS; i++){
		mark = o9_datastack_mark(ds);
		o9_datastack_slice_begin(ds, &sl, sizeof(vlong));
		for(j = 0; j < SLICE_ELEMS; j++){
			val = i + j;
			o9_datastack_slice_push(ds, &sl, &val);
		}
		o9_datastack_slice_end(ds, &sl);
		o9_datastack_reset(ds, mark);
	}
	t1 = nsec();
	dt_slice = t1 - t0;
	print("  Goose DataStack    : %d collections in %.2f ms (%.1f ns/collection)\n",
		SLICE_COLLECTIONS, (double)dt_slice / 1e6, (double)dt_slice / SLICE_COLLECTIONS);

	/* 3. Turns */
	t0 = nsec();
	for(i = 0; i < TURN_ITERS; i++){
		mark = o9_datastack_mark(ds);
		o9_datastack_string(ds, "sys", 3);
		o9_datastack_string(ds, "src", 3);
		o9_datastack_string(ds, "cmd", 3);
		o9_datastack_string(ds, "auth", 4);
		O9Slice results;
		vlong dummy = 99;

		o9_datastack_slice_begin(ds, &results, sizeof(vlong));
		o9_datastack_slice_push(ds, &results, &dummy);
		o9_datastack_slice_push(ds, &results, &dummy);
		o9_datastack_slice_push(ds, &results, &dummy);
		o9_datastack_slice_push(ds, &results, &dummy);
		o9_datastack_slice_end(ds, &results);

		o9_datastack_reset(ds, mark);
	}
	t1 = nsec();
	dt_turn = t1 - t0;
	print("  Goose DataStack    : %d turns in %.2f ms (%.1f ns/turn, %.0f turns/sec)\n\n",
		TURN_ITERS, (double)dt_turn / 1e6, (double)dt_turn / TURN_ITERS,
		(TURN_ITERS * 1e9) / dt_turn);
}

void
threadmain(int argc, char **argv)
{
	O9DataStack *ds;
	int do_heap = 1;
	int do_stack = 1;

	if(argc > 1){
		if(strcmp(argv[1], "heap") == 0){
			do_stack = 0;
		} else if(strcmp(argv[1], "stack") == 0){
			do_heap = 0;
		}
	}

	ds = o9_datastack_create(1024 * 1024);
	if(ds == nil) sysfatal("cannot create datastack");

	if(do_heap)
		run_heap_bench();
	if(do_stack)
		run_stack_bench(ds);

	o9_datastack_destroy(ds);
	threadexitsall(0);
}
