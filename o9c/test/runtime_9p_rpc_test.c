#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

void
threadmain(int, char**)
{
	if(o9_selftest_9p_rpc_split() < 0)
		sysfatal("split 9P response was not read as one framed message");
	print("runtime_9p_rpc_test: OK\n");
	threadexitsall(nil);
}
