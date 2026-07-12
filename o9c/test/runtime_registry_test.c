#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

void
threadmain(int, char**)
{
	Channel *c1, *c2;
	O9Handle h1, h2, dead;
	int a, b;

	a = 11;
	b = 22;
	if(o9_registry_start() < 0)
		sysfatal("registry_start");

	c1 = chancreate(sizeof(void*), 0);
	c2 = chancreate(sizeof(void*), 0);
	if(c1 == nil || c2 == nil)
		sysfatal("chancreate");

	if(o9_registry_register("thing", "Thing", c1, &a) < 0)
		sysfatal("register first");
	if(o9_registry_lookup("thing", &h1) < 0)
		sysfatal("lookup first");
	if(h1.chan != c1 || h1.addr != &a || h1.gen <= 0)
		sysfatal("bad first handle chan=%p addr=%p gen=%lld", h1.chan, h1.addr, h1.gen);

	if(o9_registry_unregister("thing") < 0)
		sysfatal("unregister");
	if(o9_registry_lookup("thing", &dead) == 0)
		sysfatal("lookup returned unregistered handle");

	if(o9_registry_register("thing", "Thing", c2, &b) < 0)
		sysfatal("register second");
	if(o9_registry_lookup("thing", &h2) < 0)
		sysfatal("lookup second");
	if(h2.chan != c2 || h2.addr != &b)
		sysfatal("bad second handle chan=%p addr=%p", h2.chan, h2.addr);
	if(h2.gen <= h1.gen)
		sysfatal("generation did not advance: old=%lld new=%lld", h1.gen, h2.gen);

	chanfree(c1);
	chanfree(c2);
	print("runtime_registry_test: OK\n");
	threadexitsall(nil);
}
