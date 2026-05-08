
#line	2	"/n/linux/objective-9c/o9c/o9_plan9.y"
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

typedef struct Node Node;

enum {
    NClass,
    NProp,
    NState,
    NAtomic,
    NStream,
    NSecret,
    NCap,
    NInherit,
    NMethod,
    NDestructor,
    NIdent,
    NType,
    NChanSend,
    NChanRecv,
    NChanTry,
    NAssign,
    NReturn,
    NIntLit,
    NStringLit,
    NCharLit,
    NBoolLit,
    NAdd,
    NSub,
    NMul,
    NDiv,
    NMod,
    NEq,
    NNe,
    NLt,
    NLe,
    NGt,
    NGe,
    NAnd,
    NOr,
    NBitAnd,
    NBitOr,
    NBitXor,
    NLshift,
    NRshift,
    NNot,
    NBitNot,
    NNeg,
    NIf,
    NIfElse,
    NElse,
    NWhile,
    NLocalVar,
    NMsgSend,
    NFuncCall
};

struct Node {
    int type;
    char *name;
    char *typename;
    Node *left;
    Node *right;
    Node *next;
};

typedef struct ClassDef ClassDef;
struct ClassDef {
    char *name;
    Node *node;
    ClassDef *next;
};
ClassDef *classes;

void
add_class(char *name, Node *n)
{
    ClassDef *c = malloc(sizeof(ClassDef));
    c->name = strdup(name);
    c->node = n;
    c->next = classes;
    classes = c;
}

Node*
find_class(char *name)
{
    ClassDef *c;
    for(c = classes; c; c = c->next)
        if(strcmp(c->name, name) == 0) return c->node;
    return nil;
}

Node* mk(int type, char *name, char *typename, Node *l, Node *r);
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);
ulong o9_hash(char *str);
void  add_var_class(char *varname, char *classname);

Node *ast_root;

char*
map_type(char *t)
{
    if(t == nil) return "void";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "uint64") == 0) return "uvlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "uint32") == 0) return "ulong";
    if(strcmp(t, "int16") == 0) return "short";
    if(strcmp(t, "uint16") == 0) return "ushort";
    if(strcmp(t, "int8") == 0) return "char";
    if(strcmp(t, "uint8") == 0) return "uchar";
    if(strcmp(t, "bool") == 0) return "int";
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";
    return t; /* Fallback to raw Plan 9 type */
}

char*
type_fmt(char *t)
{
    if(strcmp(t, "vlong") == 0) return "%lld";
    if(strcmp(t, "uvlong") == 0) return "%llud";
    if(strcmp(t, "long") == 0) return "%ld";
    if(strcmp(t, "ulong") == 0) return "%lud";
    if(strcmp(t, "int") == 0) return "%d";
    if(strcmp(t, "uint") == 0) return "%ud";
    if(strcmp(t, "short") == 0) return "%d";
    if(strcmp(t, "ushort") == 0) return "%ud";
    if(strcmp(t, "char") == 0) return "%d";
    if(strcmp(t, "uchar") == 0) return "%ud";
    if(strcmp(t, "char*") == 0) return "%s";
    return "%lld"; /* fallback */
}

char*
type_cast(char *t)
{
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    return "vlong"; /* fallback */
}

char*
get_sym_type(Node *c, char *name)
{
    Node *m;
    if(c == nil || name == nil) return "vlong";
    for(m = c->left; m; m = m->next){
        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0){
            return map_type(m->typename);
        }
    }
    return "vlong";
}

#line	167	"/n/linux/objective-9c/o9c/o9_plan9.y"
typedef union  {
    Node *node;
    char *name;
} YYSTYPE;
extern	int	yyerrflag;
#ifndef	YYMAXDEPTH
#define	YYMAXDEPTH	150
#endif
YYSTYPE	yylval;
YYSTYPE	yyval;
#define	TIDENT	57346
#define	TTYPE	57347
#define	TINTLIT	57348
#define	TSTRINGLIT	57349
#define	TCHARLIT	57350
#define	TCLASS	57351
#define	TFUNC	57352
#define	TMETHOD	57353
#define	TRETURN	57354
#define	TCHAN	57355
#define	TIF	57356
#define	TELSE	57357
#define	TWHILE	57358
#define	TNEW	57359
#define	TPRINT	57360
#define	TSTATE	57361
#define	TPROP	57362
#define	TATOMIC	57363
#define	TSTREAM	57364
#define	TSECRET	57365
#define	TCAP	57366
#define	TTRUE	57367
#define	TFALSE	57368
#define	TARROW	57369
#define	TEQ	57370
#define	TADD	57371
#define	TSUB	57372
#define	TCHANSEND	57373
#define	TCHANRECV	57374
#define	TCHANTRY	57375
#define	TEQEQ	57376
#define	TNEQ	57377
#define	TLE	57378
#define	TGE	57379
#define	TAND	57380
#define	TOR	57381
#define	TLSHIFT	57382
#define	TRSHIFT	57383
#define	UMINUS	57384
#define YYEOFCODE 1
#define YYERRCODE 2

#line	494	"/n/linux/objective-9c/o9c/o9_plan9.y"


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
        if(c == '~')
            return '~';
        if(c == '='){
            if((c = Bgetc(bin)) == '=') return TEQEQ;
            if(c == '>') return TARROW;
            Bungetc(bin);
            return TEQ;
        }
        if(c == '&'){
            if((c = Bgetc(bin)) == '&') return TAND;
            Bungetc(bin);
            return '&';
        }
        if(c == '|'){
            if((c = Bgetc(bin)) == '|') return TOR;
            Bungetc(bin);
            return '|';
        }
        if(c == '!'){
            if((c = Bgetc(bin)) == '=') return TNEQ;
            Bungetc(bin);
            return '!';
        }
        if(c == '<'){
            if((c = Bgetc(bin)) == '-') return TCHANRECV;
            if(c == '=') return TLE;
            if(c == '<') return TLSHIFT;
            Bungetc(bin);
            return '<';
        }
        if(c == '>'){
            if((c = Bgetc(bin)) == '=') return TGE;
            if(c == '>') return TRSHIFT;
            Bungetc(bin);
            return '>';
        }
        if(c == '"'){
            char buf[1024];
            int i = 0;
            while((c = Bgetc(bin)) != Beof && c != '"' && i < 1023) {
                if(c == '\\'){
                    if((c = Bgetc(bin)) == Beof) break;
                    if(c == 'n') buf[i++] = '\n';
                    else if(c == 't') buf[i++] = '\t';
                    else buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TSTRINGLIT;
        }
        if(c == '\''){
            char buf[16];
            int i = 0;
            while((c = Bgetc(bin)) != Beof && c != '\'' && i < 15) {
                if(c == '\\'){
                    if((c = Bgetc(bin)) == Beof) break;
                    buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TCHARLIT;
        }
        if(c == '-'){
            if((c = Bgetc(bin)) == '>'){
                if((c = Bgetc(bin)) == '?') return TCHANTRY;
                Bungetc(bin);
                return TCHANSEND;
            }
            Bungetc(bin);
            return TSUB;
        }
        if(c == '/'){
            if((c = Bgetc(bin)) == '/'){
                while((c = Bgetc(bin)) != Beof && c != '\n');
                continue;
            }
            if(c == '*'){
                while((c = Bgetc(bin)) != Beof){
                    if(c == '*'){
                        if((c = Bgetc(bin)) == '/') break;
                        Bungetc(bin);
                    }
                }
                continue;
            }
            Bungetc(bin);
            return '/';
        }
        if(c == '+') return TADD;

        if(isdigit(c)){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            if(c == '0'){
                c = Bgetc(bin);
                if(c == 'x' || c == 'X'){
                    buf[i++] = c;
                    while(isxdigit(c = Bgetc(bin))) {
                        if(i < 63) buf[i++] = c;
                    }
                    Bungetc(bin);
                    buf[i] = '\0';
                    yylval.name = strdup(buf);
                    return TINTLIT;
                }
                Bungetc(bin);
            }
            while(isdigit(c = Bgetc(bin))) {
                if(i < 63) buf[i++] = c;
            }
            Bungetc(bin);
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TINTLIT;
        }

        if(isalpha(c) || c == '_'){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = Bgetc(bin)) || c == '_') {
                if(i < 63) buf[i++] = c;
            }
            Bungetc(bin);
            buf[i] = '\0';
            
            yylval.node = mk(NIdent, buf, nil, nil, nil);
            
            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "method") == 0) return TMETHOD;
            if(strcmp(buf, "state") == 0) return TSTATE;
            if(strcmp(buf, "prop") == 0) return TPROP;
            if(strcmp(buf, "atomic") == 0) return TATOMIC;
            if(strcmp(buf, "stream") == 0) return TSTREAM;
            if(strcmp(buf, "secret") == 0) return TSECRET;
            if(strcmp(buf, "cap") == 0) return TCAP;
            if(strcmp(buf, "chan") == 0) return TCHAN;
            if(strcmp(buf, "return") == 0) return TRETURN;
            if(strcmp(buf, "if") == 0) return TIF;
            if(strcmp(buf, "else") == 0) return TELSE;
            if(strcmp(buf, "while") == 0) return TWHILE;
            if(strcmp(buf, "true") == 0) return TTRUE;
            if(strcmp(buf, "false") == 0) return TFALSE;
            if(strcmp(buf, "print") == 0) return TPRINT;
            if(strcmp(buf, "bool") == 0) return TTYPE;
            if(strcmp(buf, "uint64") == 0) return TTYPE;
            if(strcmp(buf, "int32") == 0) return TTYPE;
            if(strcmp(buf, "uint32") == 0) return TTYPE;
            if(strcmp(buf, "int16") == 0) return TTYPE;
            if(strcmp(buf, "uint16") == 0) return TTYPE;
            if(strcmp(buf, "int8") == 0) return TTYPE;
            if(strcmp(buf, "uint8") == 0) return TTYPE;
            if(strcmp(buf, "void") == 0) return TTYPE;
            if(strcmp(buf, "string") == 0) return TTYPE;
            if(strcmp(buf, "int") == 0) return TTYPE;
            if(strcmp(buf, "char") == 0) return TTYPE;
            if(strcmp(buf, "vlong") == 0) return TTYPE;
            if(strcmp(buf, "uvlong") == 0) return TTYPE;
            if(strcmp(buf, "ulong") == 0) return TTYPE;
            if(strcmp(buf, "ushort") == 0) return TTYPE;
            if(strcmp(buf, "uchar") == 0) return TTYPE;
            return TIDENT;
        }
        return c;
    }
    return 0;
}

/* --- Code Generator --- */

char *local_vars[128];
int num_locals = 0;
int in_class_context = 1;		/* 0 when generating top-level main() */
int in_method_body = 0;		/* 1 when generating inside a method impl */
int has_return = 0;			/* 1 when a return statement was emitted */

/* Variable-to-class symbol table */
typedef struct VarClass VarClass;
struct VarClass {
    char *varname;
    char *classname;
};
VarClass var_classes[128];
int num_var_classes = 0;

void
add_var_class(char *varname, char *classname)
{
    if(num_var_classes >= 128) return;
    var_classes[num_var_classes].varname = varname;
    var_classes[num_var_classes].classname = classname;
    num_var_classes++;
}

char*
get_var_class(char *varname)
{
    int i;
    for(i=0; i<num_var_classes; i++){
        if(strcmp(var_classes[i].varname, varname) == 0)
            return var_classes[i].classname;
    }
    return nil;
}

void
mark_locals(Node *n)
{
    if(n == nil) return;
    if(n->type == NLocalVar && n->name) {
        if(num_locals < 128) local_vars[num_locals++] = n->name;
    }
    mark_locals(n->left);
    mark_locals(n->right);
    mark_locals(n->next);
}

int
is_local(char *name)
{
    int i;
    for(i=0; i<num_locals; i++){
        if(strcmp(local_vars[i], name) == 0) return 1;
    }
    return 0;
}

void gen_expr(Node *e);

void
gen_expr(Node *e)
{
    if(e == nil) return;
    switch(e->type){
    case NIdent:
        if(is_local(e->name))
            print("%s", e->name);
        else if(in_class_context)
            print("self->%s", e->name);
        else
            print("%s", e->name);
        break;
    case NIntLit:
        print("%s", e->name);
        break;
    case NStringLit:
        print("\"%s\"", e->name);
        break;
    case NCharLit:
        print("'%s'", e->name);
        break;
    case NBoolLit:
        print("%s", e->name);
        break;
    case NMsgSend:
        /* c.method(args...) -> obj9_msgSend(&c, hash, o9_call_args) */
        /* Plan 9 C-compatible: comma expressions for multi-arg, simple call for 0-arg */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            if(nargs > 0){
                /* Assign args to global buffer using comma ops */
                int i = 0;
                int first = 1;
                for(a = e->right; a; a = a->next){
                    if(first) print("(o9_call_args[%d]=", i);
                    else      print(", o9_call_args[%d]=", i);
                    gen_expr(a);
                    first = 0;
                    i++;
                }
                print(", (vlong)obj9_msgSend(&");
            } else {
                print("((vlong)obj9_msgSend(&");
            }
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args))", o9_hash(e->name));
        }
        break;
    case NAdd:
        print("("); gen_expr(e->left); print(" + "); gen_expr(e->right); print(")");
        break;
    case NSub:
        print("("); gen_expr(e->left); print(" - "); gen_expr(e->right); print(")");
        break;
    case NMul:
        print("("); gen_expr(e->left); print(" * "); gen_expr(e->right); print(")");
        break;
    case NDiv:
        print("("); gen_expr(e->left); print(" / "); gen_expr(e->right); print(")");
        break;
    case NMod:
        print("("); gen_expr(e->left); print(" %% "); gen_expr(e->right); print(")");
        break;
    case NEq:
        print("("); gen_expr(e->left); print(" == "); gen_expr(e->right); print(")");
        break;
    case NNe:
        print("("); gen_expr(e->left); print(" != "); gen_expr(e->right); print(")");
        break;
    case NLt:
        print("("); gen_expr(e->left); print(" < "); gen_expr(e->right); print(")");
        break;
    case NLe:
        print("("); gen_expr(e->left); print(" <= "); gen_expr(e->right); print(")");
        break;
    case NGt:
        print("("); gen_expr(e->left); print(" > "); gen_expr(e->right); print(")");
        break;
    case NGe:
        print("("); gen_expr(e->left); print(" >= "); gen_expr(e->right); print(")");
        break;
    case NAnd:
        print("("); gen_expr(e->left); print(" && "); gen_expr(e->right); print(")");
        break;
    case NOr:
        print("("); gen_expr(e->left); print(" || "); gen_expr(e->right); print(")");
        break;
    case NBitAnd:
        print("("); gen_expr(e->left); print(" & "); gen_expr(e->right); print(")");
        break;
    case NBitOr:
        print("("); gen_expr(e->left); print(" | "); gen_expr(e->right); print(")");
        break;
    case NBitXor:
        print("("); gen_expr(e->left); print(" ^ "); gen_expr(e->right); print(")");
        break;
    case NLshift:
        print("("); gen_expr(e->left); print(" << "); gen_expr(e->right); print(")");
        break;
    case NRshift:
        print("("); gen_expr(e->left); print(" >> "); gen_expr(e->right); print(")");
        break;
    case NNot:
        print("!"); gen_expr(e->left);
        break;
    case NBitNot:
        print("~"); gen_expr(e->left);
        break;
    case NNeg:
        print("-"); gen_expr(e->left);
        break;
    case NFuncCall:
        /* Built-in functions like print(...) */
        if(strcmp(e->name, "print") == 0){
            /* Emit print("fmt", args...) directly */
            print("print(");
            int first = 1;
            Node *a;
            for(a = e->left; a; a = a->next){
                if(!first) print(", ");
                gen_expr(a);
                first = 0;
            }
            print(")");
        } else {
            /* Unknown function call — just emit as-is */
            print("%s(", e->name);
            int first = 1;
            Node *a;
            for(a = e->left; a; a = a->next){
                if(!first) print(", ");
                gen_expr(a);
                first = 0;
            }
            print(")");
        }
        break;
    }
}

void gen_stmt(Node *c, Node *s);

void
gen_stmt(Node *c, Node *s)
{
    Node *n;
    if(s == nil) return;
    switch(s->type){
    case NLocalVar:
        {
            char *cname = find_class(s->typename) ? s->typename : nil;
            int is_new = (s->left && s->left->type == NClass && s->left->name);
            if(in_class_context || cname == nil){
                /* Plain local variable */
                print("\t%s %s", map_type(s->typename), s->name);
                if(s->left && !is_new){
                    print(" = "); gen_expr(s->left);
                }
                print(";\n");
            } else if(is_new && cname){
                /* Counter c = new Counter(...) -> spawn in-process server + client */
                char *cn = cname;
                /* Count constructor args from TNEW node's call_args (s->left->right) */
                int nctor = 0;
                {
                    Node *ca;
                    for(ca = s->left->right; ca; ca = ca->next) nctor++;
                }
                print("\t%s_Internal *__%s = emalloc9p(sizeof(%s_Internal));\n", cn, s->name, cn);
                print("\tmemset(__%s, 0, sizeof(%s_Internal));\n", s->name, cn);
                print("\t__%s->dispatch_chan = chancreate(sizeof(void*), 10);\n", s->name);
                print("\t%s_Client %s;\n", cn, s->name);
                print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
                print("\t%s.dispatch_chan = __%s->dispatch_chan;\n", s->name, s->name);
                if(find_class(cn)){
                    Node *cnode = find_class(cn);
                    Node *m;
                    for(m = cnode->left; m; m = m->next){
                        if(m->type == NProp || m->type == NState || m->type == NAtomic){
                            print("\t__%s->%s = 0;\n", s->name, m->name);
                        }
                    }
                }
                print("\tproccreate(%s_loop, __%s, 8192);\n", cn, s->name);
                /* Send constructor args if any */
                if(nctor > 0){
                    /* Use global o9_call_args buffer (Plan 9 C compatible) */
                    int first = 1;
                    Node *ca;
                    int ai = 0;
                    for(ca = s->left->right; ca; ca = ca->next){
                        if(first) print("\to9_call_args[%d]=", ai);
                        else      print("\t\no9_call_args[%d]=", ai);
                        gen_expr(ca);
                        print(";\n");
                        first = 0;
                        ai++;
                    }
                    print("\tobj9_msgSend(&%s, 0x%lux, o9_call_args);\n", s->name, o9_hash(cname));
                }
            } else {
                /* Class-typed variable with client init (no new) */
                print("\t%s_Client %s;\n", cname, s->name);
                print("\to9_AsmTable %s_tbl;\n", s->name);
                print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cname);
                print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
                print("\t%s.table = &%s_tbl;\n", s->name, s->name);
                print("\to9_init_client(&%s, \"%s\", 4096);\n", s->name, cname);
            }
        }
        break;
        break;
    case NChanSend: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; sendp("); gen_expr(s->left); print(", __box); }\n");
        break;
    }
    case NChanTry: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; Alt __a[] = {{"); gen_expr(s->left); print(", __box, CHANSND}, {nil, nil, CHANNOBLK}, {nil, nil, CHANEND}}; if(alt(__a) == 1) free(__box); }\n");
        break;
    }
    case NChanRecv: {
        char *t = "vlong";
        if(s->left->type == NIdent) t = get_sym_type(c, s->left->name);
        print("\t{ %s *__box = recvp(", t); gen_expr(s->right); print("); if(__box){ "); gen_expr(s->left); print(" = *__box; free(__box); } }\n");
        break;
    }
    case NAssign:
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;
    case NReturn:
        if(in_method_body){
            has_return = 1;
            print("\tr->ret = (void*)("); gen_expr(s->left); print(");\n\tgoto done;\n");
        } else {
            print("\treturn "); gen_expr(s->left); print(";\n");
        }
        break;
    case NIf:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NIfElse:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right->left; n; n = n->next) gen_stmt(c, n);
        print("\t} else {\n");
        for(n = s->right->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NWhile:
        print("\twhile("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    default:
        print("\t"); gen_expr(s); print(";\n");
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
    print("typedef struct %s_Client {\n\tint fd;\n\tvoid *shm_base;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_Client;\n", m->name);
    }
    print("} %s_Client;\n\n#endif\n\n", c->name);
}

void
gen_cache_entries(Node *c, char *classname)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_cache_entries(p, classname);
        }
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"d:%ld:%ld\\n\", %ldL, (long)o9_offsetof(%s_State, %s));\n", o9_hash(m->name), classname, m->name);
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"c:%ld:%p\\n\", %ldL, (long)o9_impl_%s_%s);\n", o9_hash(m->name), c->name, m->name);
    }
}

void
gen_prop_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_handlers(p);
        }
        if(m->type == NProp){
            print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
            print("\t\tsnprint(buf, sizeof buf, \"%%lld\\n\", (vlong)s->%s);\n", m->name);
            print("\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_write_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_write_handlers(p);
        }
        if(m->type == NProp){
            print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
            print("\t\ts->%s = strtoll(r->ifcall.data, nil, 0);\n", m->name);
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_prop_create(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_create(p);
        }
        if(m->type == NProp) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    }
}

void
gen_class_server(Node *c)
{
    Node *m, *s;
    print("/* Implementation for class %s (Tiered CSP/9P Model) */\n", c->name);

    /* 1. State Structure (internal authoritative state) */
    print("typedef struct %s_Internal %s_Internal;\n", c->name, c->name);
    print("struct %s_Internal {\n\tArcLedger ledger;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_Internal;\n", m->name);
        if(m->type == NProp || m->type == NState || m->type == NAtomic) 
            print("\t%s %s;\n", map_type(m->typename), m->name);
        if(m->type == NStream)
            print("\tChannel *%s;\n", m->name);
    }
    print("\tChannel *dispatch_chan;\n");
    print("};\n\n");

    int has_destruct = 0;
    /* 2. Method Implementations (as internal functions) */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod){
            num_locals = 0;
            mark_locals(m->left);
            /* Register param names as locals so gen_expr emits bare names */
            {
                Node *p;
                for(p = m->right; p; p = p->next){
                    if(num_locals < 128) local_vars[num_locals++] = p->name;
                }
            }
            print("static void o9_impl_%s_%s(%s_Internal *self, O9Msg *msg) {\n", c->name, m->name, c->name);
            print("\tO9Reply *r = mallocz(sizeof(O9Reply), 1);\n");
            /* Unpack params from msg->args (packed as vlong array for now) */
            {
                Node *p;
                int pi = 0;
                for(p = m->right; p; p = p->next){
                    print("\t%s %s = ((vlong*)msg->args)[%d];\n", map_type(p->typename), p->name, pi);
                    pi++;
                }
            }
            in_method_body = 1;
            has_return = 0;
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            in_method_body = 0;
            if(has_return) print("done:\n");
            print("\tr->ok = 1;\n\tsendp(msg->replyc, r);\n}\n\n");
        }
        if(m->type == NDestructor){
            has_destruct = 1;
            num_locals = 0;
            mark_locals(m->left);
            print("static void o9_destruct_%s(%s_Internal *self) {\n", c->name, c->name);
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            print("}\n\n");
        }
    }

    print("static void o9_cleanup_%s(%s_Internal *self) {\n", c->name, c->name);
    if (has_destruct) {
        print("\to9_destruct_%s(self);\n", c->name);
    }
    print("\tchanfree(self->dispatch_chan);\n");
    print("\tfree(self);\n");
    print("}\n\n");

    /* 3. CSP Dispatch Loop */
    print("static void %s_loop(void *v) {\n", c->name);
    print("\t%s_Internal *self = v;\n\tO9Msg *m;\n", c->name);
    print("\tfor(;;){\n\t\tm = recvp(self->dispatch_chan);\n\t\tif(m == nil) continue;\n");
    print("\t\tswitch(m->sel){\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod)
            print("\t\tcase 0x%lux: o9_impl_%s_%s(self, m); break;\n", o9_hash(m->name), c->name, m->name);
    }
    print("\t\tcase 0x%lux: o9_cleanup_%s(self); threadexits(nil); break;\n", o9_hash("destroy"), c->name);
    print("\t\tdefault: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = \"bad selector\"; sendp(m->replyc, r); } break;\n");
    print("\t\t}\n\t}\n}\n\n");

    /* 4. 9P Fileserver Facade (fsread/fswrite) */
    print("static void fsread_%s(Req *r) {\n", c->name);
    print("\tchar buf[1024];\n\t%s_Internal *s = r->srv->aux;\n", c->name);
    print("\tchar *name = r->fid->file->name;\n\n");
    print("\tif(strcmp(name, \"status\") == 0) { readstr(r, \"running\"); respond(r, nil); return; }\n");
    
    /* props/ sub-directory logic would go here, simplified for MVP */
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            char *fmt = type_fmt(t);
            char *cast = type_cast(t);
            if(strcmp(fmt, "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", s->%s ? s->%s : \"\");\n", m->name, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)s->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");

    print("static void fswrite_%s(Req *r) {\n", c->name);
    print("\t%s_Internal *s = r->srv->aux;\n\tchar *name = r->fid->file->name;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) { /* TODO: parse text ctl */ respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"msg\") == 0) { /* TODO: parse binary msg */ respond(r, nil); return; }\n");
    
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            if(strcmp(type_fmt(t), "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tfree(s->%s);\n", m->name);
                print("\t\ts->%s = strdup(r->ifcall.data);\n", m->name);
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\ts->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"read only or not found\");\n}\n\n");

    print("Srv o9srv_%s;\n\n", c->name);

    print("void o9_main_%s(int argc, char **argv) {\n", c->name);
    print("\t%s_Internal *s = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
    print("\tmemset(s, 0, sizeof(%s_Internal));\n", c->name);
    print("\ts->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\to9srv_%s.read = fsread_%s;\n\to9srv_%s.write = fswrite_%s;\n", c->name, c->name, c->name, c->name);
    print("\to9srv_%s.aux = s;\n", c->name);
    print("\tTree *t = alloctree(nil, nil, 0555, nil);\n\to9srv_%s.tree = t;\n", c->name);
    print("\tcreatefile(t->root, \"ctl\", nil, 0222, nil);\n");
    print("\tcreatefile(t->root, \"msg\", nil, 0222, nil);\n");
    print("\tcreatefile(t->root, \"status\", nil, 0444, nil);\n");
    print("\tcreatefile(t->root, \"cache\", nil, 0444, nil);\n");
    for(m = c->left; m; m = m->next) if(m->type == NProp || m->type == NAtomic) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    print("\tproccreate(%s_loop, s, 8192);\n", c->name);
    print("\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n}\n", c->name, c->name);
}

ulong
o9_hash(char *str)
{
    ulong hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    return hash & 0xFFFFFFFFul;
}

void
codegen(Node *root)
{
    Node *n;
    
    print("/* Generated o9 Source */\n");
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include \"o9.h\"\n\n");
    print("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    print("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    print("vlong o9_call_args[64];\n");
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n");
    print("#endif\n\n");

    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_class_header(n);
        }
    }
    Node *main_func = nil;
    Node *last = nil;
    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_class_server(n);
            last = n;
        }
        if(n->type == NMethod && strcmp(n->name, "main") == 0){
            main_func = n;
        }
    }
    print("void\nthreadmain(int argc, char **argv)\n{\n");
    if(last){
        print("\to9_main_%s(argc, argv);\n", last->name);
    }
    if(main_func){
        num_locals = 0;
        mark_locals(main_func->left);
        in_class_context = 0;
        for(n = main_func->left; n; n = n->next)
            gen_stmt(nil, n);
    }
    /* Also need a global flag for class init tracking */
    if(main_func && last){
        /* The class server was started by o9_main_Counter above.
         * Variables declared in main() still need o9_Object init if
         * they are class-typed. The var_class table tracks which
         * variables map to which classes. This is a TODO for now. */
    }
    print("\tthreadexitsall(nil);\n}\n");
}

int
main(int argc, char **argv)
{
    bin = Bfdopen(0, OREAD);
    if(yyparse() == 0)
        codegen(ast_root);
    exits(nil);
    return 0;
}
short	yyexca[] =
{-1, 1,
	1, -1,
	-2, 0,
-1, 82,
	4, 1,
	-2, 80,
};
#define	YYNPROD	92
#define	YYPRIVATE 57344
#define	YYLAST	879
short	yyact[] =
{
  74,  73, 169, 168,  93,  57, 215, 207,  94, 201,
 139, 185, 184, 185,  28, 176, 185, 138, 175, 139,
 216, 139, 197, 100,  99,  98,  97,  96,  90,  67,
  60,  58,  46,  48,  50,  51, 166,  53,  54,  55,
 219, 218, 105, 106, 107, 103,  61, 104, 111, 112,
 114, 116, 117, 118, 122, 123, 120, 121, 119, 113,
 115, 108, 109, 110,  95, 191, 165, 124, 106, 107,
 178, 200, 212, 111, 112, 114, 116, 126, 199, 122,
 123, 131, 132, 133, 113, 115, 108, 109, 110, 134,
 141, 135, 124,  95, 190, 202,  41, 137,  11, 177,
 101,  14, 182, 173, 130, 142, 143, 145, 146, 147,
 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
 158, 159, 160, 161, 162, 163, 129, 108, 109, 110,
 170, 171, 172, 124, 189, 128,  92,  70,  63,  45,
  95,  12, 124,  91,  38,  40, 181, 180, 179,  42,
  30,  31, 127,  29,  83,  84,  85,  49,  40,  32,
  33,  34,  35,  36,  37,  88,   6,   7, 183,   5,
  47,  40, 164,  86,  87, 170, 140, 188,  81, 136,
 193, 125,  69, 192, 170,  68, 195, 170, 198,  66,
  65,  39,  43, 204, 106, 107, 203,  15,  79,  80,
  64,  62,  89,  95,  59, 208, 209, 210,  56,  52,
  44,  10, 108, 109, 110,   9, 217,   3, 124,  25,
   8,  24,  23,  22, 220, 221, 105, 106, 107, 103,
  21, 104, 111, 112, 114, 116, 117, 118, 122, 123,
 120, 121, 119, 113, 115, 108, 109, 110,  20,  19,
  72, 124, 105, 106, 107, 103, 206, 104, 111, 112,
 114, 116, 117, 118, 122, 123, 120, 121, 119, 113,
 115, 108, 109, 110,  27,  26,  18, 124, 105, 106,
 107, 103, 196, 104, 111, 112, 114, 116, 117, 118,
 122, 123, 120, 121, 119, 113, 115, 108, 109, 110,
  17,  16,  13, 124, 105, 106, 107, 103, 167, 104,
 111, 112, 114, 116, 117, 118, 122, 123, 120, 121,
 119, 113, 115, 108, 109, 110,   4,   2,   1, 124,
 105, 106, 107, 103, 102, 104, 111, 112, 114, 116,
 117, 118, 122, 123, 120, 121, 119, 113, 115, 108,
 109, 110,   0,   0,   0, 124,   0, 187, 105, 106,
 107, 103,   0, 104, 111, 112, 114, 116, 117, 118,
 122, 123, 120, 121, 119, 113, 115, 108, 109, 110,
   0,   0,   0, 124,   0, 186, 105, 106, 107, 103,
   0, 104, 111, 112, 114, 116, 117, 118, 122, 123,
 120, 121, 119, 113, 115, 108, 109, 110,   0,   0,
   0, 124,   0, 174, 105, 106, 107, 103,   0, 104,
 111, 112, 114, 116, 117, 118, 122, 123, 120, 121,
 119, 113, 115, 108, 109, 110,   0,   0,   0, 124,
  82,  40,  83,  84,  85,   0,   0,   0,  75,   0,
  77,   0,  78,  88,  76,  82,  40,  83,  84,  85,
   0,  86,  87,  75,   0,  77,  81,  78,  88,  76,
  82,  40,  83,  84,  85,   0,  86,  87,  75,   0,
  77,  81,  78,  88,  76,   0,  79,  80,   0,   0,
  89,  86,  87, 223,   0,   0,  81,   0,   0,   0,
   0,  79,  80,   0,   0,  89,   0,   0, 222,   0,
   0,   0,   0,   0,   0,   0,  79,  80,   0,   0,
  89,   0,   0, 214,  82,  40,  83,  84,  85,   0,
   0,   0,  75,   0,  77,   0,  78,  88,  76,  82,
  40,  83,  84,  85,   0,  86,  87,  75,   0,  77,
  81,  78,  88,  76,  82,  40,  83,  84,  85,   0,
  86,  87,  75,   0,  77,  81,  78,  88,  76,   0,
  79,  80,   0,   0,  89,  86,  87, 213,   0,   0,
  81,   0,   0,   0,   0,  79,  80,   0,   0,  89,
   0,   0, 211,   0,   0,   0,   0,   0,   0,   0,
  79,  80,   0,   0,  89,   0,   0, 205,  82,  40,
  83,  84,  85,   0,   0,   0,  75,   0,  77,   0,
  78,  88,  76,   0,   0,   0,   0,   0,   0,  86,
  87,   0, 106, 107,  81,   0,   0, 111, 112, 114,
 116, 117, 118, 122, 123, 120, 121, 119, 113, 115,
 108, 109, 110,   0,  79,  80, 124,   0,  89,   0,
   0, 194, 106, 107, 103,   0, 104, 111, 112, 114,
 116, 117, 118, 122, 123, 120, 121, 119, 113, 115,
 108, 109, 110,   0,   0,   0, 124,  82,  40,  83,
  84,  85,   0,   0,   0,  75,   0,  77,   0,  78,
  88,  76,   0,   0,   0,   0,   0,   0,  86,  87,
   0, 106, 107,  81,   0,   0, 111, 112, 114, 116,
 117,   0, 122, 123, 120, 121, 119, 113, 115, 108,
 109, 110,   0,  79,  80, 124,   0,  89, 106, 107,
  71,   0,   0, 111, 112, 114, 116,   0,   0, 122,
 123, 120, 121, 119, 113, 115, 108, 109, 110, 106,
 107,   0, 124,   0, 111, 112, 114, 116,   0,   0,
 122, 123,   0, 121, 119, 113, 115, 108, 109, 110,
 106, 107,   0, 124,   0, 111, 112, 114, 116,   0,
   0, 122, 123,   0,   0, 119, 113, 115, 108, 109,
 110,   0,   0, 127, 124,  83,  84,  85,   0,   0,
   0,   0,   0,   0,   0,   0,  88,   0,   0,   0,
   0,   0,   0,   0,  86,  87,   0, 106, 107,  81,
   0, 144,   0,   0, 114, 116,   0,   0, 122, 123,
   0,   0,   0, 113, 115, 108, 109, 110,   0,  79,
  80, 124,   0,  89, 106, 107,   0,   0,   0,   0,
   0,   0,   0,   0,   0, 122, 123,   0,   0,   0,
   0,   0, 108, 109, 110,   0,   0,   0, 124
};
short	yypact[] =
{
 157,-1000, 157,-1000,-1000,-1000, 211, 207,-1000,  42,
  87,-1000,  46, 140,  40,-1000,-1000,-1000,-1000,-1000,
-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000, 145, 206,
  85, 166, 153, 153, 153, 205, 153, 153, -19, 204,
-1000,-1000, -27, 200, -28, 153, 197,  84, 196,-1000,
 186, 185, -29, 181, 178,-1000,  83, 683,-1000, -30,
-1000,  96,  82, 153, -31, -32, -33,-1000, -34, -35,
  45,-1000,-1000, 276, 177, 148,  81,  72,  50, 148,
 148, 148,-1000,-1000,-1000,-1000,-1000,-1000, 153, 148,
-1000, 175, 153, -38,-1000, 172,-1000,-1000,-1000,-1000,
-1000,  34,-1000, 148, 148, 799, 148, 148, 148, 148,
 148, 148, 148, 148, 148, 148, 148, 148, 148, 148,
 148, 148, 148, 148, 168,   8, 250,-1000, 148, 148,
 148,  89,  89,  89,  49, 358, -37, -40,  43, 153,
-1000,-1000, 603, 603, 148, 633,  80,  80,  89,  89,
  89, 798, 798, 825, 825, 825, 825, 709, 682,  39,
 730, 751, 165, 165,  48,-1000, 148,-1000, -43,-1000,
 386, 330, 302, 148,-1000, 130,  38,-1000, 148,-1000,
 604, 603, 148, 224, -36, 148,  22,  15, -46,  41,
-1000, 148, 550, 198,-1000, -48,-1000,-1000,-1000,-1000,
-1000,-1000, 153, 535,  14,-1000,-1000,-1000, 520, 466,
 -49,-1000,-1000,   5,-1000, 153, -15, -16,-1000,-1000,
 451, 436,-1000,-1000
};
short	yypgo[] =
{
   0, 328, 327, 217, 326, 302, 301, 300, 276, 275,
 274,   5, 250,   1, 249, 248, 230, 223, 222, 221,
 219,   0,   4,   8,   3,   2, 169
};
short	yyr1[] =
{
   0,  21,  21,   1,   1,   2,   2,   3,   3,  26,
   4,   5,   5,   6,   6,   6,   6,   6,   6,   6,
   6,   6,   6,   6,  15,  16,  17,  18,  19,  20,
  14,  14,  14,  14,   9,   7,   7,   7,   8,  22,
  22,  22,  23,  10,  11,  11,  12,  12,  12,  12,
  12,  12,  12,  12,  13,  13,  13,  13,  13,  13,
  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,
  13,  13,  13,  13,  13,  13,  13,  13,  13,  13,
  13,  13,  13,  13,  13,  13,  13,  13,  24,  24,
  24,  25
};
short	yyr2[] =
{
   0,   1,   1,   0,   1,   1,   2,   1,   1,   7,
   5,   0,   2,   1,   1,   1,   1,   1,   1,   1,
   1,   1,   1,   1,   4,   4,   4,   3,   4,   4,
   9,   9,   8,   8,   2,   3,   4,   3,  14,   0,
   1,   3,   2,   7,   0,   2,   2,   3,   5,   3,
   5,   7,  11,   7,   3,   3,   4,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   2,   2,   2,   6,
   1,   1,   1,   1,   1,   1,   5,   3,   0,   1,
   3,   1
};
short	yychk[] =
{
-1000,  -1,  -2,  -3,  -4, -26,   9,  10,  -3,   4,
   4,  56,  54,  -5,  55,  57,  -6,  -7,  -8, -14,
 -15, -16, -17, -18, -19, -20,  -9, -10, -21,  13,
  10,  11,  19,  20,  21,  22,  23,  24,   4,  51,
   5,  56,   4,  47,   4,  54, -21,   4, -21,   4,
 -21, -21,   4, -21, -21,  58,   4, -11,  58,   4,
  58, -21,   4,  54,   4,   4,   4,  58,   4,   4,
  54,  57, -12, -13, -21,  12,  18,  14,  16,  50,
  51,  30,   4,   6,   7,   8,  25,  26,  17,  54,
  58,  47,  54, -22, -23, -21,  58,  58,  58,  58,
  58,  55,  58,  31,  33,  28,  29,  30,  47,  48,
  49,  34,  35,  45,  36,  46,  37,  38,  39,  44,
  42,  43,  40,  41,  53,   4, -13,   4,  54,  54,
  54, -13, -13, -13, -21, -13,   4, -22,  55,  59,
   4,  56, -13, -13,  32, -13, -13, -13, -13, -13,
 -13, -13, -13, -13, -13, -13, -13, -13, -13, -13,
 -13, -13, -13, -13,   4,  58,  28,  58, -24, -25,
 -13, -13, -13,  54,  55,  55,  55,  56,  27, -23,
 -11, -13,  54, -13,  55,  59,  55,  55, -24,   4,
  56,  27, -11, -13,  57, -24,  58,  58, -25,  56,
  56,  55,  54, -11, -13,  57,  58,  55, -11, -11,
 -22,  57,  58,  57,  57,  55,  15, -21,  56,  56,
 -11, -11,  57,  57
};
short	yydef[] =
{
   3,  -2,   4,   5,   7,   8,   0,   0,   6,   0,
   0,  11,   0,   0,   0,  10,  12,  13,  14,  15,
  16,  17,  18,  19,  20,  21,  22,  23,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   1,   0,
   2,  44,   0,   0,   0,   0,   0,   1,   0,   1,
   0,   0,   0,   0,   0,  34,   0,   0,  35,   0,
  37,   0,   0,  39,   0,   0,   0,  27,   0,   0,
   0,   9,  45,   0,   0,   0,   0,   0,   0,   0,
   0,   0,  -2,  81,  82,  83,  84,  85,   0,   0,
  36,   0,  39,   0,  40,   0,  24,  25,  26,  28,
  29,   0,  46,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,  80,  88,   0,
   0,  76,  77,  78,   0,   0,   0,   0,   0,   0,
  42,  44,  54,  55,   0,  57,  58,  59,  60,  61,
  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,
  72,  73,  74,  75,   0,  47,   0,  49,   0,  89,
  91,   0,   0,  88,  87,   0,   0,  44,   0,  41,
   0,  56,  88,   0,   0,   0,   0,   0,   0,   0,
  44,   0,   0,   0,  43,   0,  48,  50,  90,  44,
  44,  86,  39,   0,   0,  32,  33,  79,   0,   0,
   0,  30,  31,  51,  53,   0,   0,   0,  44,  44,
   0,   0,  52,  38
};
short	yytok1[] =
{
   1,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,  50,   0,   0,   0,  49,  44,   0,
  54,  55,  47,   0,  59,   0,  53,  48,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  58,
  45,   0,  46,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,  43,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,  56,  42,  57,  51
};
short	yytok2[] =
{
   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,
  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,
  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,
  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,
  52
};
long	yytok3[] =
{
   0
};

#line	1	"/sys/lib/yaccpar"
#define YYFLAG 		-1000
#define	yyclearin	yychar = -1
#define	yyerrok		yyerrflag = 0

#ifdef	yydebug
#include	"y.debug"

char*
yytokname(int yyc)
{
	static char x[16];

	if(yyc > 0 && yyc <= sizeof(yytoknames)/sizeof(yytoknames[0]))
	if(yytoknames[yyc-1])
		return yytoknames[yyc-1];
	sprint(x, "<%d>", yyc);
	return x;
}

char*
yystatname(int yys)
{
	static char x[16];

	if(yys >= 0 && yys < sizeof(yystates)/sizeof(yystates[0]))
	if(yystates[yys])
		return yystates[yys];
	sprint(x, "<%d>\n", yys);
	return x;
}
#else
#define	yydebug		0
#define yytokname(x)	""
#define yystatname(x)	""
#endif

/*	parser for yacc output	*/

int	yynerrs = 0;		/* number of errors */
int	yyerrflag = 0;		/* error recovery flag */


long
yylex1(void)
{
	long yychar;
	long *t3p;
	int c;

	yychar = yylex();
	if(yychar <= 0) {
		c = yytok1[0];
		goto out;
	}
	if(yychar < sizeof(yytok1)/sizeof(yytok1[0])) {
		c = yytok1[yychar];
		goto out;
	}
	if(yychar >= YYPRIVATE)
		if(yychar < YYPRIVATE+sizeof(yytok2)/sizeof(yytok2[0])) {
			c = yytok2[yychar-YYPRIVATE];
			goto out;
		}
	for(t3p=yytok3;; t3p+=2) {
		c = t3p[0];
		if(c == yychar) {
			c = t3p[1];
			goto out;
		}
		if(c == 0)
			break;
	}
	c = 0;

out:
	if(c == 0)
		c = yytok2[1];	/* unknown char */
	if(yydebug >= 3)
		fprint(2, "lex %.4lux %s\n", yychar, yytokname(c));
	return c;
}

int
yyparse(void)
{
	struct
	{
		YYSTYPE	yyv;
		int	yys;
	} yys[YYMAXDEPTH], *yyp, *yypt;
	short *yyxi;
	int yyj, yym, yystate, yyn, yyg;
	long yychar;
	YYSTYPE save1, save2;
	int save3, save4;

	save1 = yylval;
	save2 = yyval;
	save3 = yynerrs;
	save4 = yyerrflag;

	yystate = 0;
	yychar = -1;
	yynerrs = 0;
	yyerrflag = 0;
	yyp = &yys[-1];
	goto yystack;

ret0:
	yyn = 0;
	goto ret;

ret1:
	yyn = 1;
	goto ret;

ret:
	yylval = save1;
	yyval = save2;
	yynerrs = save3;
	yyerrflag = save4;
	return yyn;

yystack:
	/* put a state and value onto the stack */
	if(yydebug >= 4)
		fprint(2, "char %s in %s", yytokname(yychar), yystatname(yystate));

	yyp++;
	if(yyp >= &yys[YYMAXDEPTH]) {
		yyerror("yacc stack overflow");
		goto ret1;
	}
	yyp->yys = yystate;
	yyp->yyv = yyval;

yynewstate:
	yyn = yypact[yystate];
	if(yyn <= YYFLAG)
		goto yydefault; /* simple state */
	if(yychar < 0)
		yychar = yylex1();
	yyn += yychar;
	if(yyn < 0 || yyn >= YYLAST)
		goto yydefault;
	yyn = yyact[yyn];
	if(yychk[yyn] == yychar) { /* valid shift */
		yychar = -1;
		yyval = yylval;
		yystate = yyn;
		if(yyerrflag > 0)
			yyerrflag--;
		goto yystack;
	}

yydefault:
	/* default state action */
	yyn = yydef[yystate];
	if(yyn == -2) {
		if(yychar < 0)
			yychar = yylex1();

		/* look through exception table */
		for(yyxi=yyexca;; yyxi+=2)
			if(yyxi[0] == -1 && yyxi[1] == yystate)
				break;
		for(yyxi += 2;; yyxi += 2) {
			yyn = yyxi[0];
			if(yyn < 0 || yyn == yychar)
				break;
		}
		yyn = yyxi[1];
		if(yyn < 0)
			goto ret0;
	}
	if(yyn == 0) {
		/* error ... attempt to resume parsing */
		switch(yyerrflag) {
		case 0:   /* brand new error */
			yyerror("syntax error");
			yynerrs++;
			if(yydebug >= 1) {
				fprint(2, "%s", yystatname(yystate));
				fprint(2, "saw %s\n", yytokname(yychar));
			}

		case 1:
		case 2: /* incompletely recovered error ... try again */
			yyerrflag = 3;

			/* find a state where "error" is a legal shift action */
			while(yyp >= yys) {
				yyn = yypact[yyp->yys] + YYERRCODE;
				if(yyn >= 0 && yyn < YYLAST) {
					yystate = yyact[yyn];  /* simulate a shift of "error" */
					if(yychk[yystate] == YYERRCODE)
						goto yystack;
				}

				/* the current yyp has no shift onn "error", pop stack */
				if(yydebug >= 2)
					fprint(2, "error recovery pops state %d, uncovers %d\n",
						yyp->yys, (yyp-1)->yys );
				yyp--;
			}
			/* there is no state on the stack with an error shift ... abort */
			goto ret1;

		case 3:  /* no shift yet; clobber input char */
			if(yydebug >= 2)
				fprint(2, "error recovery discards %s\n", yytokname(yychar));
			if(yychar == YYEOFCODE)
				goto ret1;
			yychar = -1;
			goto yynewstate;   /* try again in the same state */
		}
	}

	/* reduction by production yyn */
	if(yydebug >= 2)
		fprint(2, "reduce %d in:\n\t%s", yyn, yystatname(yystate));

	yypt = yyp;
	yyp -= yyr2[yyn];
	yyval = (yyp+1)->yyv;
	yym = yyn;

	/* consult goto table to find next state */
	yyn = yyr1[yyn];
	yyg = yypgo[yyn];
	yyj = yyg + yyp->yys + 1;

	if(yyj >= YYLAST || yychk[yystate=yyact[yyj]] != -yyn)
		yystate = yyact[yyg];
	switch(yym) {
		
case 1:
#line	202	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 2:
#line	203	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 3:
#line	207	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ ast_root = nil; } break;
case 4:
#line	208	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ ast_root = yypt[-0].yyv.node; } break;
case 5:
#line	212	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 6:
#line	213	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ 
        Node *n = yypt[-1].yyv.node;
        while(n->next) n = n->next;
        n->next = yypt[-0].yyv.node;
        yyval.node = yypt[-1].yyv.node;
    } break;
case 9:
#line	228	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-5].yyv.node->name, "void", yypt[-1].yyv.node, nil);
    } break;
case 10:
#line	235	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NClass, yypt[-3].yyv.node->name, nil, yypt[-1].yyv.node, nil);
        add_class(yypt[-3].yyv.node->name, yyval.node);
    } break;
case 11:
#line	242	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 12:
#line	243	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ 
        if(yypt[-1].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-1].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-1].yyv.node;
        }
    } break;
case 24:
#line	270	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NState, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 25:
#line	277	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 26:
#line	284	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NAtomic, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 27:
#line	291	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NStream, yypt[-1].yyv.node->name, nil, nil, nil);
    } break;
case 28:
#line	298	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NSecret, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 29:
#line	305	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NCap, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 30:
#line	324	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, yypt[-7].yyv.node->name, yypt[-1].yyv.node, yypt[-4].yyv.node);
    } break;
case 31:
#line	328	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *body = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil);
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, yypt[-7].yyv.node->name, body, yypt[-4].yyv.node);
    } break;
case 32:
#line	333	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, "void", yypt[-1].yyv.node, yypt[-4].yyv.node);
    } break;
case 33:
#line	337	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *body = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil);
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, "void", body, yypt[-4].yyv.node);
    } break;
case 34:
#line	345	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NInherit, yypt[-1].yyv.node->name, nil, nil, nil);
    } break;
case 35:
#line	352	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 36:
#line	356	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        char buf[128];
        snprint(buf, sizeof buf, "%s*", yypt[-3].yyv.node->name);
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, buf, nil, nil);
    } break;
case 37:
#line	362	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NStream, yypt[-1].yyv.node->name, "chan", nil, nil);
    } break;
case 38:
#line	369	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *params = yypt[-5].yyv.node;
        Node *stmts = yypt[-1].yyv.node;
        yyval.node = mk(NMethod, yypt[-7].yyv.node->name, yypt[-3].yyv.node->name, stmts, params);
    } break;
case 39:
#line	377	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 40:
#line	378	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 41:
#line	379	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        if(yypt[-2].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-2].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-2].yyv.node;
        }
    } break;
case 42:
#line	392	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-0].yyv.node->name, yypt[-1].yyv.node->name, nil, nil);
    } break;
case 43:
#line	399	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NDestructor, yypt[-5].yyv.node->name, nil, yypt[-1].yyv.node, nil);
    } break;
case 44:
#line	405	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 45:
#line	406	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        if(yypt[-1].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-1].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-1].yyv.node;
        }
    } break;
case 46:
#line	418	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-1].yyv.node; } break;
case 47:
#line	419	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLocalVar, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil); if(find_class(yypt[-2].yyv.node->name)) add_var_class(yypt[-1].yyv.node->name, yypt[-2].yyv.node->name); } break;
case 48:
#line	420	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLocalVar, yypt[-3].yyv.node->name, yypt[-4].yyv.node->name, yypt[-1].yyv.node, nil); if(find_class(yypt[-4].yyv.node->name)) add_var_class(yypt[-3].yyv.node->name, yypt[-4].yyv.node->name); } break;
case 49:
#line	421	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil); } break;
case 50:
#line	422	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NFuncCall, "print", nil, yypt[-2].yyv.node, nil);
    } break;
case 51:
#line	425	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NIf, nil, nil, yypt[-4].yyv.node, yypt[-1].yyv.node); } break;
case 52:
#line	426	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NIfElse, nil, nil, yypt[-8].yyv.node, mk(NElse, nil, nil, yypt[-5].yyv.node, yypt[-1].yyv.node));
    } break;
case 53:
#line	429	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NWhile, nil, nil, yypt[-4].yyv.node, yypt[-1].yyv.node); } break;
case 54:
#line	433	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanSend, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 55:
#line	434	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanTry, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 56:
#line	435	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanRecv, nil, nil, yypt[-3].yyv.node, yypt[-0].yyv.node); } break;
case 57:
#line	436	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAssign, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 58:
#line	437	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAdd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 59:
#line	438	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NSub, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 60:
#line	439	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NMul, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 61:
#line	440	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NDiv, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 62:
#line	441	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NMod, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 63:
#line	442	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NEq, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 64:
#line	443	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 65:
#line	444	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLt, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 66:
#line	445	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 67:
#line	446	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NGt, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 68:
#line	447	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NGe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 69:
#line	448	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAnd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 70:
#line	449	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NOr, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 71:
#line	450	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitAnd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 72:
#line	451	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitOr, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 73:
#line	452	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitXor, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 74:
#line	453	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLshift, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 75:
#line	454	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NRshift, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 76:
#line	455	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNot, nil, nil, yypt[-0].yyv.node, nil); } break;
case 77:
#line	456	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitNot, nil, nil, yypt[-0].yyv.node, nil); } break;
case 78:
#line	457	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNeg, nil, nil, yypt[-0].yyv.node, nil); } break;
case 79:
#line	458	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMsgSend, yypt[-3].yyv.node->name, nil, yypt[-5].yyv.node, yypt[-1].yyv.node);
    } break;
case 80:
#line	461	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 81:
#line	462	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NIntLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 82:
#line	463	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NStringLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 83:
#line	464	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NCharLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 84:
#line	465	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBoolLit, "1", nil, nil, nil); } break;
case 85:
#line	466	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBoolLit, "0", nil, nil, nil); } break;
case 86:
#line	467	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *n = mk(NClass, yypt[-3].yyv.node->name, nil, nil, nil);
        n->left = yypt[-3].yyv.node;
        n->right = yypt[-1].yyv.node;
        yyval.node = n;
    } break;
case 87:
#line	473	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-1].yyv.node; } break;
case 88:
#line	477	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 89:
#line	478	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 90:
#line	479	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        if(yypt[-2].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-2].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-2].yyv.node;
        }
    } break;
case 91:
#line	491	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
	}
	goto yystack;  /* stack new state and value */
}
