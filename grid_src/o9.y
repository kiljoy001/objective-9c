%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

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

Node* mk(int type, char *name, char *typename, Node *l, Node *r);
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);

Node *ast_root;

char*
map_type(char *t)
{
    if(t == nil) return "void";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "chan") == 0) return "Channel*";
    return t;
}
%}

%union {
    Node *node;
    char *name;
}

%token <node> TIDENT TTYPE
%token TCLASS TFUNC TNEW TRETURN TCHAN
%token TEQ TADD TSUB TCHANSEND TCHANRECV

%type <node> program top_levels top_level class_decl member_list member var_decl func_decl inherit_decl stmt_list stmt expr

%%

program:
    /* empty */ { ast_root = nil; }
    | top_levels { ast_root = $1; }
    ;

top_levels:
    top_level { $$ = $1; }
    | top_levels top_level { 
        Node *n = $1;
        while(n->next) n = n->next;
        n->next = $2;
        $$ = $1;
    }
    ;

top_level:
    class_decl
    ;

class_decl:
    TCLASS TIDENT '{' member_list '}'
    {
        $$ = mk(NClass, $2->name, nil, $4, nil);
    }
    ;

member_list:
    /* empty */ { $$ = nil; }
    | member_list member { 
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

member:
    var_decl
    | func_decl
    | inherit_decl
    ;

inherit_decl:
    TIDENT ';'
    {
        $$ = mk(NInherit, $1->name, nil, nil, nil);
    }
    ;

var_decl:
    TIDENT TIDENT ';'
    { 
        $$ = mk(NProp, $1->name, $2->name, nil, nil);
    }
    ;

func_decl:
    TFUNC '(' TIDENT '*' TIDENT ')' TIDENT '(' ')' TIDENT '{' stmt_list '}'
    {
        $$ = mk(NMethod, $5->name, $10->name, $12, nil);
    }
    ;

stmt_list:
    /* empty */ { $$ = nil; }
    | stmt_list stmt {
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

stmt:
    expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    ;

expr:
    TIDENT TCHANSEND TIDENT { $$ = mk(NChanSend, $1->name, nil, $3, nil); }
    | TIDENT TEQ TCHANRECV TIDENT { $$ = mk(NChanRecv, $1->name, nil, $4, nil); }
    | TIDENT TEQ TIDENT { $$ = mk(NAssign, $1->name, nil, $3, nil); }
    | TIDENT { $$ = $1; }
    ;

%%

Node*
mk(int type, char *name, char *typename, Node *l, Node *r)
{
    Node *n = malloc(sizeof(Node));
    memset(n, 0, sizeof(Node));
    n->type = type;
    if(name) n->name = strdup(name);
    if(typename) n->typename = strdup(typename);
    n->left = l;
    n->right = r;
    return n;
}

void
yyerror(char *s)
{
    fprint(2, "o9c: error: %s\n", s);
}

static Biobuf *bin;

int
yylex(void)
{
    int c;

    while((c = Bgetc(bin)) != Beof){
        if(isspace(c))
            continue;
        if(c == '<'){
            if((c = Bgetc(bin)) == '-') return TCHANRECV;
            Bungetc(bin);
            return '<';
        }
        if(c == '-'){
            if((c = Bgetc(bin)) == '>') return TCHANSEND; 
            Bungetc(bin);
            return '-';
        }
        if(isalpha(c)){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = Bgetc(bin))) {
                if(i < 63) buf[i++] = c;
            }
            Bungetc(bin);
            buf[i] = '\0';
            
            yylval.node = mk(NIdent, buf, nil, nil, nil);
            
            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "chan") == 0) return TCHAN;
            if(strcmp(buf, "return") == 0) return TRETURN;
            return TIDENT;
        }
        return c;
    }
    return 0;
}

/* --- Code Generator --- */

void
gen_stmt(Node *s)
{
    if(s == nil) return;
    switch(s->type){
    case NChanSend:
        print("\tsendp(%s, (void*)%s);\n", s->name, s->left->name);
        break;
    case NChanRecv:
        print("\t%s = recvp(%s);\n", s->name, s->left->name);
        break;
    case NAssign:
        print("\t%s = %s;\n", s->name, s->left->name);
        break;
    case NReturn:
        print("\treturn %s;\n", s->left->name);
        break;
    }
}

void
gen_class_header(Node *c)
{
    Node *m;
    print("/* Generated Client Header for class %s */\n", c->name);
    print("#ifndef _O9_GEN_%s_H_\n#define _O9_GEN_%s_H_\n\n", c->name, c->name);
    print("typedef struct %s_AsmTable {\n\tvoid *data_cache[64];\n\tvoid (*ctrl_cache[64])(void*);\n} %s_AsmTable;\n\n", c->name, c->name);
    print("typedef struct %s_Client {\n\tint fd;\n\t%s_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n", c->name, c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_Client;\n", m->name);
    }
    print("} %s_Client;\n\n#endif\n\n", c->name);
}

void
gen_class_server(Node *c)
{
    Node *m, *s;
    print("/* Generated 9P/Asm Fileserver for class %s with ARC Ledger */\n", c->name);
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <9p.h>\n#include <stddef.h>\n\n");
    
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n\n");

    print("typedef struct %s_State {\n\tArcLedger ledger;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_State;\n", m->name);
        if(m->type == NProp) print("\t%s %s;\n", map_type(m->typename), m->name);
    }
    print("} %s_State;\n\n", c->name);

    for(m = c->left; m; m = m->next){
        if(m->type == NMethod){
            print("static %s o9_impl_%s_%s(%s_State *self) {\n", map_type(m->typename), c->name, m->name, c->name);
            for(s = m->left; s; s = s->next) gen_stmt(s);
            print("}\n\n");
        }
    }

    print("static void\nfsread(Req *r)\n{\n\tchar buf[1024];\n\t%s_State *s = r->srv->aux;\n\tint i;\n\n", c->name);
    print("\tif(strcmp(r->fid->file->dir.name, \"ledger\") == 0){\n\t\tchar *p = buf;\n");
    print("\t\tp += snprint(p, sizeof buf - (p-buf), \"ID\\t\\tREFS\\n\");\n");
    print("\t\tfor(i=0; i<64; i++){\n\t\t\tif(s->ledger.entries[i].id != 0)\n");
    print("\t\t\t\tp += snprint(p, sizeof buf - (p-buf), \"%%ld\\t%%ld\\n\", s->ledger.entries[i].id, s->ledger.entries[i].count);\n");
    print("\t\t}\n\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");

    print("\tif(strcmp(r->fid->file->dir.name, \"cache\") == 0){\n\t\tchar *p = buf;\n");
    print("\t\tp += snprint(p, sizeof buf - (p-buf), \"seg:shared\\n\");\n");
    print("\t\tp += snprint(p, sizeof buf - (p-buf), \"ledger:%%ld\\n\", (long)offsetof(%s_State, ledger));\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"d:%%ld:%%ld\\n\", 0L, (long)offsetof(%s_State, %s));\n", m->name);
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"c:%%ld:%%p\\n\", 0L, (long)o9_impl_%s_%s);\n", c->name, m->name);
    }
    print("\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n\trespond(r, \"not found\");\n}\n\n");

    print("Srv o9srv_%s = { .read = fsread };\n\n", c->name);
    
    print("void\nthreadmain(int argc, char **argv)\n{\n\t%s_State *s;\n", c->name);
    print("\ts = segattach(0, \"shared\", nil, sizeof(%s_State));\n", c->name);
    print("\tif(s == (void*)-1) sysfatal(\"segattach failed: %%r\");\n");
    print("\tmemset(s, 0, sizeof(%s_State));\n\to9srv_%s.aux = s;\n", c->name, c->name);
    print("\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n\tthreadexitsall(nil);\n}\n", c->name, c->name);
}

void
codegen(Node *root)
{
    Node *n;
    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_class_header(n);
            gen_class_server(n);
        }
    }
}

int
main(int argc, char **argv)
{
    bin = Bfdopen(0, OREAD);
    if(yyparse() == 0)
        codegen(ast_root);
    return 0;
}
