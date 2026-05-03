#ifndef _O9_NODE_H_
#define _O9_NODE_H_

typedef struct Node Node;

enum {
    NClass,
    NProp,
    NInherit,
    NMethod,
    NIdent,
    NType,
    NChanSend,
    NChanRecv,
    NAssign,
    NReturn
};

struct Node {
    int type;
    char *name;
    char *typename;
    Node *left;
    Node *right;
    Node *next;
};

#endif
