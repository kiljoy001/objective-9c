#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

/* Generated headers would go here */
typedef struct Parent_Client {
    int fd;
    o9_AsmTable *table;
    long ref;
} Parent_Client;

typedef struct Child_Client {
    int fd;
    o9_AsmTable *table;
    long ref;
    Parent_Client;
} Child_Client;

void
main(int argc, char **argv)
{
    Child_Client client;
    o9_AsmTable table;
    long *val_ptr, *extra_ptr;
    
    USED(argc); USED(argv);

    memset(&table, 0, sizeof(table));
    client.table = &table;
    
    print("Testing client initialization...\n");
    
    /* Test Property Access via Asm Dispatch */
    val_ptr = o9_dispatch_data(&client, o9_hash("val"));
    extra_ptr = o9_dispatch_data(&client, o9_hash("extra"));
    
    if(val_ptr) {
        *val_ptr = 42;
        print("Inherited 'val' set to 42 via asm.\n");
    }
    
    if(extra_ptr) {
        *extra_ptr = 100;
        print("Child 'extra' set to 100 via asm.\n");
    }
    
    /* Test Destructor via 9P write to /srv/Child/destroy */
    int fd = open("/srv/Child/destroy", OWRITE);
    if(fd >= 0) {
        write(fd, "1", 1);
        close(fd);
        print("Destructor triggered via /srv/Child/destroy.\n");
    }
    
    threadexitsall(nil);
}
