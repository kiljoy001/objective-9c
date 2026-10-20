/*
 * Host-only entry point for the libdraw UI end-to-end cases.
 *
 * o9c --no-facade emits the object model and an o9_host_main() function
 * instead of the 9front 9P facade.  The UI tests exercise the same
 * widget/layout/event code as the native cases without posting a service.
 */
#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

extern int o9_host_main(int, char**);
extern char o9app_root[128];

void
threadmain(int argc, char **argv)
{
	char root[128];
	int rc;

	/* --no-facade does not run o9_app_start, so give object state a
	 * private host root instead of dropping *.tab files in the cwd. */
	snprint(root, sizeof root, "/tmp/o9-ui-%d", getpid());
	if(o9_ns_ensure_dir(root) >= 0)
		snprint(o9app_root, sizeof o9app_root, "%s", root);

	rc = o9_host_main(argc, argv);
	threadexitsall(rc == 0 ? nil : "ui-test");
}
