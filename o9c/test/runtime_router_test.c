#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

static int completions;
static void *expected_req;
static long terminated;

static void
completed(O9RouterOp *op, O9Reply *reply)
{
	if(op == nil || op->r != expected_req || reply != nil)
		sysfatal("router failure callback received the wrong request or reply");
	completions++;
}

static void
terminated_request(O9RouterOp *op, O9Reply *reply)
{
	if(op == nil || op->r != expected_req ||
	   (reply != nil && reply->err == nil))
		sysfatal("router teardown did not fail the pending request");
	o9_reply_free(reply);
	ainc(&terminated);
}

void
threadmain(int, char**)
{
	Channel *closed, *queued, *other;
	int req, i;
	char dump[2048];

	req = 42;
	expected_req = &req;
	if(o9_router_submit(&req, "Test", "missing", nil, nil, 0, nil, 0,
	   "test", 0, completed, nil) >= 0 || completions != 1)
		sysfatal("nil actor channel did not complete its request");

	closed = chancreate(sizeof(void*), 0);
	if(closed == nil)
		sysfatal("cannot create test channel");
	chanclose(closed);
	if(o9_router_submit(&req, "Test", "closed", nil, closed, 0, nil, 0,
	   "test", 0, completed, nil) >= 0 || completions != 2)
		sysfatal("closed actor channel did not complete its request");
	chanfree(closed);
	queued = chancreate(sizeof(void*), 10);
	if(queued == nil)
		sysfatal("cannot create queue test channel");
	for(i = 0; i < 11; i++)
		if(o9_router_submit(&req, "Test", "queued", nil, queued, 0, nil, 0,
		   "test", 0, terminated_request, nil) < 0)
			sysfatal("cannot queue router test request");
	other = chancreate(sizeof(void*), 10);
	if(other == nil || o9_router_submit(&req, "Other", "queued", nil, other, 0, nil, 0,
	   "test", 0, terminated_request, nil) < 0)
		sysfatal("cannot submit another class with the same instance name");
	o9_router_dump(dump, sizeof dump);
	if(strstr(dump, "Test.queued") == nil || strstr(dump, "Other.queued") == nil)
		sysfatal("router did not keep separate class mailboxes");
	o9_router_unregister_actor("Test", "queued");
	chanclose(queued);
	for(i = 0; i < 200 && terminated != 11; i++)
		sleep(5);
	if(terminated != 11)
		sysfatal("router teardown stranded %ld of 11 requests", 11-terminated);
	chanfree(queued);
	if(terminated != 11)
		sysfatal("tearing down one class affected another class");
	o9_router_unregister_actor("Other", "queued");
	chanclose(other);
	for(i = 0; i < 200 && terminated != 12; i++)
		sleep(5);
	if(terminated != 12)
		sysfatal("other class request was stranded");
	chanfree(other);

	print("runtime_router_test: OK\n");
	threadexitsall(nil);
}
