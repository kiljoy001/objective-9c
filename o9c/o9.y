%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>
#include <stdio.h>
#include "node.h"

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
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";
    return t;
}
%}

%union {
    Node *node;
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
        $$ = mk(NProp, $2->name, $1->name, nil, nil);
    }
    ;

func_decl:
    TFUNC '(' TIDENT '*' TIDENT ')' TIDENT '(' ')' TIDENT '{' stmt_list '}'
    {
        $$ = mk(NMethod, $7->name, $10->name, $12, nil);
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
    if(n == nil) return nil;
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

void
gen_includes(void)
{
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n\n");
}

void
gen_state_struct(Node *c)
{
    Node *m;
    if(c == nil || c->name == nil) return;
    print("typedef struct %s_State %s_State;\n", c->name, c->name);
    print("struct %s_State {\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp && m->typename) print("\t%s %s;\n", map_type(m->typename), m->name);
    }
    print("};\n\n");
}

void
gen_read_handler(Node *c)
{
    Node *m;
    if(c == nil || c->name == nil) return;
    print("static void\nfsread(Req *r)\n{\n\tchar buf[512];\n\t%s_State *s = r->srv->aux;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp && m->name){
            print("\tif(strcmp(r->fid->file->dir.name, \"%s\") == 0){\n", m->name);
            print("\t\tsnprint(buf, sizeof buf, \"%%lld\\n\", (vlong)s->%s);\n", m->name);
            print("\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");
}

void
gen_write_handler(Node *c)
{
    Node *m;
    if(c == nil || c->name == nil) return;
    print("static void\nfswrite(Req *r)\n{\n\t%s_State *s = r->srv->aux;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp && m->name){
            print("\tif(strcmp(r->fid->file->dir.name, \"%s\") == 0){\n", m->name);
            print("\t\ts->%s = strtoll(r->ifcall.data, nil, 0);\n", m->name);
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");
}

void
gen_main_entry(Node *c)
{
    Node *m;
    if(c == nil || c->name == nil) return;
    print("Srv o9srv_%s;\n\nvoid\nthreadmain(int argc, char **argv)\n{\n\t%s_State *s;\n\tTree *t;\n\tUSED(argc); USED(argv);\n", c->name, c->name);
    print("\ts = emalloc9p(sizeof(%s_State));\n\tmemset(s, 0, sizeof(%s_State));\n", c->name, c->name);
    print("\to9srv_%s.aux = s;\n\to9srv_%s.read = fsread;\n\to9srv_%s.write = fswrite;\n", c->name, c->name, c->name);
    print("\tt = alloctree(nil, nil, 0555, nil);\n\to9srv_%s.tree = t;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NProp && m->name) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    }
    print("\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n\tthreadexitsall(nil);\n}\n", c->name, c->name);
}

void
codegen(Node *root)
{
    Node *n;
    gen_includes();
    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_state_struct(n);
            gen_read_handler(n);
            gen_write_handler(n);
            gen_main_entry(n);
        }
    }
}

int
main(int argc, char **argv)
{
    int ret;
    USED(argc); USED(argv);
    ret = yyparse();
    if(ret == 0 && ast_root != nil)
        codegen(ast_root);
    if(ret != 0)
        exits("parse error");
    exits(nil);
    return 0;
}
