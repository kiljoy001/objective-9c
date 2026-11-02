#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

int mainstacksize = 65536;

enum {
	RING_ITERS = 1000000,
	ROUTER_ITERS = 10000,
	LEGACY_ITERS = 200
};

static Channel *actor_chan;
static long completed_count;
static Channel *done_chan;

static void
bench_completed(O9RouterOp *op, O9Reply *reply)
{
	USED(op);
	if(reply != nil)
		free(reply);
	if(ainc(&completed_count) == ROUTER_ITERS)
		sendul(done_chan, 1);
}

static void
actor_proc(void *v)
{
	Channel *c = v;
	O9Msg *m;
	O9Reply *r;

	threadsetname("bench_actor");
	o9_actor_enter(c, "inst1");
	for(;;){
		m = recvp(c);
		if(m == nil)
			break;
		r = mallocz(sizeof(O9Reply), 1);
		if(r != nil){
			r->ok = 1;
			r->ret = 42;
		}
		o9_msg_reply(m, r);
	}
}

/* Legacy simulation: proc-per-request + heap struct */
typedef struct LegacyOp LegacyOp;
struct LegacyOp {
	Channel *replyc;
	long id;
};

static void
legacy_worker(void *v)
{
	LegacyOp *op = v;
	O9Msg m;
	O9Reply *r;

	memset(&m, 0, sizeof m);
	m.replyc = op->replyc;
	sendp(actor_chan, &m);
	r = recvp(op->replyc);
	if(r != nil)
		free(r);
	chanfree(op->replyc);
	free(op);
}

static void
run_legacy_test(int iters)
{
	int i;
	vlong t0, t1, dt;
	double us_per_op;

	t0 = nsec();
	for(i = 0; i < iters; i++){
		LegacyOp *op = mallocz(sizeof(LegacyOp), 1);
		op->replyc = chancreate(sizeof(void*), 1);
		proccreate(legacy_worker, op, 32768);
	}
	t1 = nsec();
	dt = t1 - t0;
	us_per_op = (double)dt / (iters * 1000.0);
	print("  3. Legacy proc-per-msg : %d ops in %.2f ms (%.2f us/op, %.0f ops/sec)\n",
		iters, (double)dt / 1e6, us_per_op, (iters * 1e9) / dt);
}

static O9TRing g_ring;

void
threadmain(int, char**)
{
	O9Slot slot, out;
	int i, req;
	vlong t0, t1, dt;
	double us_per_op;

	print("=== Objective-9c 9ring Router Speed Benchmark ===\n");

	/* 1. Raw Duplex 9ring Throughput */
	memset(&g_ring, 0, sizeof g_ring);
	memset(&slot, 0, sizeof slot);
	slot.handle = 0x10001;
	slot.sel = 0xABCD;
	slot.args[0] = 12345;

	t0 = nsec();
	for(i = 0; i < RING_ITERS; i++){
		while(o9_tring_submit(&g_ring, &slot) < 0)
			;
		while(!o9_tring_consume(&g_ring, &out))
			;
	}
	t1 = nsec();
	dt = t1 - t0;
	us_per_op = (double)dt / (RING_ITERS * 1000.0);
	print("  1. Raw 9ring SPSC   : %d ops in %.2f ms (%.3f us/op, %.0f ops/sec)\n",
		RING_ITERS, (double)dt / 1e6, us_per_op, (RING_ITERS * 1e9) / dt);

	/* 2. Full End-to-End 9ring CSP Router */
	actor_chan = chancreate(sizeof(void*), 64);
	done_chan = chancreate(sizeof(ulong), 1);
	proccreate(actor_proc, actor_chan, 32768);

	req = 100;
	completed_count = 0;
	t0 = nsec();
	for(i = 0; i < ROUTER_ITERS; i++){
		vlong args[2];
		args[0] = i;
		args[1] = i * 2;
		while(o9_router_submit(&req, "BenchClass", "inst1", nil, actor_chan,
		      0x1234, args, 2, "scott", 1, bench_completed, nil) < 0)
			sleep(0);
	}
	recvul(done_chan);
	t1 = nsec();
	dt = t1 - t0;
	us_per_op = (double)dt / (ROUTER_ITERS * 1000.0);
	print("  2. Duplex 9ring CSP : %d roundtrips in %.2f ms (%.2f us/op, %.0f ops/sec)\n",
		ROUTER_ITERS, (double)dt / 1e6, us_per_op, (ROUTER_ITERS * 1e9) / dt);

	/* 3. Legacy Proc-Per-Message comparison */
	run_legacy_test(LEGACY_ITERS);

	/* Clean up */
	o9_router_unregister_actor("BenchClass", "inst1");
	chanclose(actor_chan);
	print("=== Benchmark Complete ===\n");
	threadexitsall(nil);
}