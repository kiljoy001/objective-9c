#define threadmain o9app_generated_threadmain
#include "multiuser.c"
#undef threadmain

void
threadmain(int argc, char **argv)
{
	O9Session *first, *second;
	Fid alice, bob, authfid;
	Req areq, breq, authreq;
	Qid qid;
	char *walk;
	uvlong oldgen, newgen;
	o9_app_start(argc, argv);
	memset(&alice, 0, sizeof alice);
	memset(&bob, 0, sizeof bob);
	memset(&authfid, 0, sizeof authfid);
	memset(&areq, 0, sizeof areq);
	memset(&breq, 0, sizeof breq);
	memset(&authreq, 0, sizeof authreq);
	authfid.qid.type = QTAUTH;
	authreq.fid = &authfid;
	if(!o9_view_authorize(&authreq))
		sysfatal("authentication fid blocked");
	alice.uid = "alice";
	bob.uid = "bob";
	first = o9app_alloc_session("alice");
	if(first == nil) sysfatal("cannot allocate first session");
	if(!o9app_session_guard(&alice, first->dir, 0, &oldgen) ||
	   oldgen != first->generation)
		sysfatal("owner denied");
	if(o9app_session_guard(&bob, first->dir, 0, &newgen))
		sysfatal("foreign user accepted");
	alice.file = o9app_tree->root;
	bob.file = o9app_tree->root;
	areq.fid = &alice;
	breq.fid = &bob;
	if(o9_view_attach(&areq) < 0 || o9_view_attach(&breq) < 0)
		sysfatal("cannot attach test fids");
	walk = o9_view_walk1(&bob, "0", &qid);
	if(walk == nil || strcmp(walk, "permission denied") != 0)
		sysfatal("foreign walk accepted");
	walk = o9_view_walk1(&alice, "0", &qid);
	if(walk != nil) sysfatal("owner walk denied: %s", walk);
	o9app_close_session(first);
	if(o9_view_authorize(&areq))
		sysfatal("closed session fid accepted");
	if(o9app_session_guard(&alice, first->dir, oldgen, &newgen))
		sysfatal("closed session accepted");
	second = o9app_alloc_session("bob");
	if(second != first || second->generation == oldgen)
		sysfatal("slot reuse did not change generation");
	if(o9app_session_guard(&alice, second->dir, oldgen, &newgen))
		sysfatal("old fid accepted after reuse");
	if(o9_view_authorize(&areq))
		sysfatal("old walked fid accepted after reuse");
	walk = o9_view_walk1(&bob, "0", &qid);
	if(walk != nil) sysfatal("new owner walk denied: %s", walk);
	if(!o9app_session_guard(&bob, second->dir, 0, &newgen) ||
	   newgen != second->generation)
		sysfatal("new owner denied");
	print("O9 MULTIUSER GUARD PASS\n");
	threadexitsall(nil);
}
