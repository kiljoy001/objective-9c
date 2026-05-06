#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"
#include "inheritance.h"

void
threadmain(int argc, char **argv)
{
    Child_Client client;
    o9_AsmTable table;
    long *val_ptr, *extra_ptr;
    
    memset(&table, 0, sizeof(table));
    client.table = (void*)&table;
    
    /* Initialize client by connecting to /srv/Child */
    if(o9_init_client(&client, "Child", 4096) < 0)
        sysfatal("o9_init_client failed: %r");
    
    print("Client initialized.\n");
    
    /* Test Property Access via Asm Dispatch (Simulated) */
    /* hash for "val" (Parent prop) and "extra" (Child prop) */
    val_ptr = o9_dispatch_data(&client, o9_hash("val"));
    extra_ptr = o9_dispatch_data(&client, o9_hash("extra"));
    
    if(val_ptr) {
        *val_ptr = 42;
        print("Inherited 'val' set to 42 via asm.\n");
    } else {
        print("Failed to dispatch 'val'.\n");
    }
    
    if(extra_ptr) {
        *extra_ptr = 100;
        print("Child 'extra' set to 100 via asm.\n");
    }
    
    /* Test Destructor via 9P */
    int fd = open("/srv/Child/destroy", OWRITE);
    if(fd >= 0) {
        write(fd, "1", 1);
        close(fd);
        print("Destructor triggered via /srv/Child/destroy.\n");
    }
    
    threadexitsall(nil);
}
