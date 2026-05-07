
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
#define	TSTATE	57360
#define	TPROP	57361
#define	TATOMIC	57362
#define	TSTREAM	57363
#define	TSECRET	57364
#define	TCAP	57365
#define	TTRUE	57366
#define	TFALSE	57367
#define	TARROW	57368
#define	TGET	57369
#define	TSET	57370
#define	TEQ	57371
#define	TADD	57372
#define	TSUB	57373
#define	TCHANSEND	57374
#define	TCHANRECV	57375
#define	TCHANTRY	57376
#define	TEQEQ	57377
#define	TNEQ	57378
#define	TLE	57379
#define	TGE	57380
#define	TAND	57381
#define	TOR	57382
#define	TLSHIFT	57383
#define	TRSHIFT	57384
#define	UMINUS	57385
#define YYEOFCODE 1
#define YYERRCODE 2

#line	495	"/n/linux/objective-9c/o9c/o9_plan9.y"


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
    print("typedef struct %s_Client {\n\tint fd;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n", c->name);
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
-1, 81,
	4, 1,
	-2, 80,
};
#define	YYNPROD	92
#define	YYPRIVATE 57344
#define	YYLAST	971
short	yyact[] =
{
  74,  73, 170,  92, 169,  57, 213, 205,  93, 199,
 138, 186, 185, 186,  28, 175, 186, 137, 174, 138,
 214, 138,  99,  98,  97,  96,  95,  89,  67,  60,
  58,  55,  46,  48,  50,  51, 165,  53,  54, 217,
 190, 216, 104, 105, 106, 102,  61, 103, 110, 111,
 113, 115, 116, 117, 121, 122, 119, 120, 118, 112,
 114, 107, 108, 109,  94, 197, 164, 123, 177, 196,
 200, 189, 210, 140,  41,  11, 100, 125, 105, 106,
 129, 130, 131, 107, 108, 109,  14, 181, 133, 123,
 134, 172,  94, 132, 128, 136, 107, 108, 109, 176,
 127,  91, 123, 123, 141, 142, 144, 145, 146, 147,
 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
 158, 159, 160, 161, 162,  70,  63,  45,  12, 167,
 168,  42,  90, 188, 171,   6,   7,  49,  40,  94,
  47,  40,  38,  40, 163, 180, 179, 178,  30,  31,
 139,  29, 105, 106, 135, 124,  32,  33,  34,  35,
  36,  37,  69, 121, 122,  68,  66, 182,  65,  64,
 107, 108, 109,  62, 171,  43, 123, 187,  59, 192,
  56,  52, 191, 171,  44,  10, 194,   9, 171, 198,
  39,   3, 202,   5,   8, 201,  15,  25,  24,  23,
  22,  94, 206, 207, 208,  21,  20,  19,  72,  27,
  26,  18,  17,  16, 215,  13,   4,   2,   1,   0,
   0,   0, 218, 219, 104, 105, 106, 102,   0, 103,
 110, 111, 113, 115, 116, 117, 121, 122, 119, 120,
 118, 112, 114, 107, 108, 109,   0,   0,   0, 123,
 104, 105, 106, 102, 204, 103, 110, 111, 113, 115,
 116, 117, 121, 122, 119, 120, 118, 112, 114, 107,
 108, 109,   0,   0,   0, 123, 104, 105, 106, 102,
 195, 103, 110, 111, 113, 115, 116, 117, 121, 122,
 119, 120, 118, 112, 114, 107, 108, 109,   0,   0,
   0, 123, 104, 105, 106, 102, 166, 103, 110, 111,
 113, 115, 116, 117, 121, 122, 119, 120, 118, 112,
 114, 107, 108, 109,   0,   0,   0, 123, 104, 105,
 106, 102, 101, 103, 110, 111, 113, 115, 116, 117,
 121, 122, 119, 120, 118, 112, 114, 107, 108, 109,
   0,   0,   0, 123,   0, 184, 104, 105, 106, 102,
   0, 103, 110, 111, 113, 115, 116, 117, 121, 122,
 119, 120, 118, 112, 114, 107, 108, 109,   0,   0,
   0, 123,   0, 183, 104, 105, 106, 102,   0, 103,
 110, 111, 113, 115, 116, 117, 121, 122, 119, 120,
 118, 112, 114, 107, 108, 109,   0,   0,   0, 123,
   0, 173, 104, 105, 106, 102,   0, 103, 110, 111,
 113, 115, 116, 117, 121, 122, 119, 120, 118, 112,
 114, 107, 108, 109, 105, 106, 102, 123, 103, 110,
 111, 113, 115, 116, 117, 121, 122, 119, 120, 118,
 112, 114, 107, 108, 109,   0,   0,   0, 123,  81,
  40,  82,  83,  84,   0,   0,   0,  75,   0,  76,
   0,  77,  87,   0,   0,   0,   0,   0,   0,  85,
  86,  81,  40,  82,  83,  84,  80,   0,   0,  75,
   0,  76,   0,  77,  87,   0,   0,   0,   0,   0,
   0,  85,  86,   0,   0,   0,  78,  79,  80,   0,
  88,   0,   0, 221,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,  78,  79,
   0,   0,  88,   0,   0, 220,  81,  40,  82,  83,
  84,   0,   0,   0,  75,   0,  76,   0,  77,  87,
   0,   0,   0,   0,   0,   0,  85,  86,  81,  40,
  82,  83,  84,  80,   0,   0,  75,   0,  76,   0,
  77,  87,   0,   0,   0,   0,   0,   0,  85,  86,
   0,   0,   0,  78,  79,  80,   0,  88,   0,   0,
 212,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,  78,  79,   0,   0,  88,
   0,   0, 211,  81,  40,  82,  83,  84,   0,   0,
   0,  75,   0,  76,   0,  77,  87,   0,   0,   0,
   0,   0,   0,  85,  86,  81,  40,  82,  83,  84,
  80,   0,   0,  75,   0,  76,   0,  77,  87,   0,
   0,   0,   0,   0,   0,  85,  86,   0,   0,   0,
  78,  79,  80,   0,  88,   0,   0, 209,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,  78,  79,   0,   0,  88,   0,   0, 203,
  81,  40,  82,  83,  84,   0,   0,   0,  75,   0,
  76,   0,  77,  87,   0,   0,   0,   0,   0,   0,
  85,  86,  81,  40,  82,  83,  84,  80,   0,   0,
  75,   0,  76,   0,  77,  87,   0,   0,   0,   0,
   0,   0,  85,  86,   0,   0,   0,  78,  79,  80,
   0,  88,   0,   0, 193,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  78,
  79,   0,   0,  88, 105, 106,  71,   0,   0, 110,
 111, 113, 115, 116, 117, 121, 122, 119, 120, 118,
 112, 114, 107, 108, 109, 105, 106,   0, 123,   0,
 110, 111, 113, 115, 116,   0, 121, 122, 119, 120,
 118, 112, 114, 107, 108, 109, 105, 106,   0, 123,
   0, 110, 111, 113, 115,   0,   0, 121, 122, 119,
 120, 118, 112, 114, 107, 108, 109, 105, 106,   0,
 123,   0, 110, 111, 113, 115,   0,   0, 121, 122,
   0, 120, 118, 112, 114, 107, 108, 109, 105, 106,
   0, 123,   0, 110, 111, 113, 115,   0,   0, 121,
 122,   0,   0, 118, 112, 114, 107, 108, 109, 105,
 106,   0, 123,   0, 110, 111, 113, 115,   0,   0,
 121, 122,   0,   0,   0, 112, 114, 107, 108, 109,
   0,   0, 126, 123,  82,  83,  84, 126,   0,  82,
  83,  84,   0,   0,   0,  87,   0,   0,   0,   0,
  87,   0,  85,  86,   0,   0,   0,  85,  86,  80,
   0, 143,   0,   0,  80,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  78,
  79,   0,   0,  88,  78,  79, 105, 106,  88,   0,
   0,   0,   0, 113, 115,   0,   0, 121, 122,   0,
   0,   0, 112, 114, 107, 108, 109,   0,   0,   0,
 123
};
short	yypact[] =
{
 126,-1000, 126,-1000,-1000,-1000, 183, 181,-1000,  18,
  73,-1000,  30, 138,  17,-1000,-1000,-1000,-1000,-1000,
-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000, 127, 180,
  72, 136, 133, 133, 133, 177, 133, 133, -28, 176,
-1000,-1000, -29, 174, -30, 133, 169,  71, 165,-1000,
 164, 162, -31, 161, 158,-1000,  70, 708,-1000, -32,
-1000,  84,  46, 133, -33, -34, -35,-1000, -36, -37,
  20,-1000,-1000, 273, 151, 893,  45,  39, 893, 893,
 893,  38,-1000,-1000,-1000,-1000,-1000, 133, 893,-1000,
 150, 133, -39,-1000, 146,-1000,-1000,-1000,-1000,-1000,
  16,-1000, 893, 893, 888, 893, 893, 893, 893, 893,
 893, 893, 893, 893, 893, 893, 893, 893, 893, 893,
 893, 893, 893, 140,   7, 247,  38, 893, 893,  49,
  49,  49, 893,  36, 355, -38, -41,  42, 133,-1000,
-1000, 734, 734, 893, 404,  35,  35,  49,  49,  49,
 916, 916, 122, 122, 122, 122, 776, 755, 839, 797,
 818,  48,  48,  32,-1000, 893,-1000, 327, 299, -44,
-1000, 383, 893,-1000, 129,  14,-1000, 893,-1000, 686,
 734, 893, 221,  12,   8,-1000, 893, -47,  15,-1000,
 893, 631, 195,-1000, -49,-1000,-1000,-1000,-1000,-1000,
 133, 609,  13,-1000,-1000,-1000, 554, 532, -50,-1000,
-1000,   5,-1000, 133, -16, -18,-1000,-1000, 477, 455,
-1000,-1000
};
short	yypgo[] =
{
   0, 218, 217, 191, 216, 215, 213, 212, 211, 210,
 209,   5, 208,   1, 207, 206, 205, 200, 199, 198,
 197,   0,   3,   8,   4,   2, 193
};
short	yyr1[] =
{
   0,  21,  21,   1,   1,   2,   2,   3,   3,  26,
   4,   5,   5,   6,   6,   6,   6,   6,   6,   6,
   6,   6,   6,   6,  15,  16,  17,  18,  19,  20,
  14,  14,  14,  14,   9,   7,   7,   7,   8,  22,
  22,  22,  23,  10,  11,  11,  12,  12,  12,  12,
  12,  12,  12,  13,  13,  13,  13,  13,  13,  13,
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
   7,  11,   7,   3,   3,   4,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   2,   2,   2,   6,   4,
   1,   1,   1,   1,   1,   1,   5,   3,   0,   1,
   3,   1
};
short	yychk[] =
{
-1000,  -1,  -2,  -3,  -4, -26,   9,  10,  -3,   4,
   4,  57,  55,  -5,  56,  58,  -6,  -7,  -8, -14,
 -15, -16, -17, -18, -19, -20,  -9, -10, -21,  13,
  10,  11,  18,  19,  20,  21,  22,  23,   4,  52,
   5,  57,   4,  48,   4,  55, -21,   4, -21,   4,
 -21, -21,   4, -21, -21,  59,   4, -11,  59,   4,
  59, -21,   4,  55,   4,   4,   4,  59,   4,   4,
  55,  58, -12, -13, -21,  12,  14,  16,  51,  52,
  31,   4,   6,   7,   8,  24,  25,  17,  55,  59,
  48,  55, -22, -23, -21,  59,  59,  59,  59,  59,
  56,  59,  32,  34,  29,  30,  31,  48,  49,  50,
  35,  36,  46,  37,  47,  38,  39,  40,  45,  43,
  44,  41,  42,  54,   4, -13,   4,  55,  55, -13,
 -13, -13,  55, -21, -13,   4, -22,  56,  60,   4,
  57, -13, -13,  33, -13, -13, -13, -13, -13, -13,
 -13, -13, -13, -13, -13, -13, -13, -13, -13, -13,
 -13, -13, -13,   4,  59,  29,  59, -13, -13, -24,
 -25, -13,  55,  56,  56,  56,  57,  26, -23, -11,
 -13,  55, -13,  56,  56,  56,  60, -24,   4,  57,
  26, -11, -13,  58, -24,  59,  57,  57, -25,  56,
  55, -11, -13,  58,  59,  56, -11, -11, -22,  58,
  59,  58,  58,  56,  15, -21,  57,  57, -11, -11,
  58,  58
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
   0,  -2,  81,  82,  83,  84,  85,   0,   0,  36,
   0,  39,   0,  40,   0,  24,  25,  26,  28,  29,
   0,  46,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,  80,   0,   0,  75,
  76,  77,  88,   0,   0,   0,   0,   0,   0,  42,
  44,  53,  54,   0,  56,  57,  58,  59,  60,  61,
  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,
  72,  73,  74,   0,  47,   0,  49,   0,   0,   0,
  89,  91,  88,  87,   0,   0,  44,   0,  41,   0,
  55,  88,   0,   0,   0,  79,   0,   0,   0,  44,
   0,   0,   0,  43,   0,  48,  44,  44,  90,  86,
  39,   0,   0,  32,  33,  78,   0,   0,   0,  30,
  31,  50,  52,   0,   0,   0,  44,  44,   0,   0,
  51,  38
};
short	yytok1[] =
{
   1,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,  51,   0,   0,   0,  50,  45,   0,
  55,  56,  48,   0,  60,   0,  54,  49,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  59,
  46,   0,  47,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,  44,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,  57,  43,  58,  52
};
short	yytok2[] =
{
   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,
  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,
  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,
  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,
  42,  53
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
#line	203	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 2:
#line	204	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 3:
#line	208	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ ast_root = nil; } break;
case 4:
#line	209	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ ast_root = yypt[-0].yyv.node; } break;
case 5:
#line	213	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 6:
#line	214	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ 
        Node *n = yypt[-1].yyv.node;
        while(n->next) n = n->next;
        n->next = yypt[-0].yyv.node;
        yyval.node = yypt[-1].yyv.node;
    } break;
case 9:
#line	229	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-5].yyv.node->name, "void", yypt[-1].yyv.node, nil);
    } break;
case 10:
#line	236	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NClass, yypt[-3].yyv.node->name, nil, yypt[-1].yyv.node, nil);
        add_class(yypt[-3].yyv.node->name, yyval.node);
    } break;
case 11:
#line	243	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 12:
#line	244	"/n/linux/objective-9c/o9c/o9_plan9.y"
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
#line	271	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NState, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 25:
#line	278	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 26:
#line	285	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NAtomic, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 27:
#line	292	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NStream, yypt[-1].yyv.node->name, nil, nil, nil);
    } break;
case 28:
#line	299	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NSecret, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 29:
#line	306	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NCap, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 30:
#line	325	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, yypt[-7].yyv.node->name, yypt[-1].yyv.node, yypt[-4].yyv.node);
    } break;
case 31:
#line	329	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *body = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil);
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, yypt[-7].yyv.node->name, body, yypt[-4].yyv.node);
    } break;
case 32:
#line	334	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, "void", yypt[-1].yyv.node, yypt[-4].yyv.node);
    } break;
case 33:
#line	338	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *body = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil);
        yyval.node = mk(NMethod, yypt[-6].yyv.node->name, "void", body, yypt[-4].yyv.node);
    } break;
case 34:
#line	346	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NInherit, yypt[-1].yyv.node->name, nil, nil, nil);
    } break;
case 35:
#line	353	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil);
    } break;
case 36:
#line	357	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        char buf[128];
        snprint(buf, sizeof buf, "%s*", yypt[-3].yyv.node->name);
        yyval.node = mk(NProp, yypt[-1].yyv.node->name, buf, nil, nil);
    } break;
case 37:
#line	363	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NStream, yypt[-1].yyv.node->name, "chan", nil, nil);
    } break;
case 38:
#line	370	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *params = yypt[-5].yyv.node;
        Node *stmts = yypt[-1].yyv.node;
        yyval.node = mk(NMethod, yypt[-7].yyv.node->name, yypt[-3].yyv.node->name, stmts, params);
    } break;
case 39:
#line	378	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 40:
#line	379	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 41:
#line	380	"/n/linux/objective-9c/o9c/o9_plan9.y"
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
#line	393	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NProp, yypt[-0].yyv.node->name, yypt[-1].yyv.node->name, nil, nil);
    } break;
case 43:
#line	400	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NDestructor, yypt[-5].yyv.node->name, nil, yypt[-1].yyv.node, nil);
    } break;
case 44:
#line	406	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 45:
#line	407	"/n/linux/objective-9c/o9c/o9_plan9.y"
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
#line	419	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-1].yyv.node; } break;
case 47:
#line	420	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLocalVar, yypt[-1].yyv.node->name, yypt[-2].yyv.node->name, nil, nil); if(find_class(yypt[-2].yyv.node->name)) add_var_class(yypt[-1].yyv.node->name, yypt[-2].yyv.node->name); } break;
case 48:
#line	421	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLocalVar, yypt[-3].yyv.node->name, yypt[-4].yyv.node->name, yypt[-1].yyv.node, nil); if(find_class(yypt[-4].yyv.node->name)) add_var_class(yypt[-3].yyv.node->name, yypt[-4].yyv.node->name); } break;
case 49:
#line	422	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil); } break;
case 50:
#line	423	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NIf, nil, nil, yypt[-4].yyv.node, yypt[-1].yyv.node); } break;
case 51:
#line	424	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NIfElse, nil, nil, yypt[-8].yyv.node, mk(NElse, nil, nil, yypt[-5].yyv.node, yypt[-1].yyv.node));
    } break;
case 52:
#line	427	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NWhile, nil, nil, yypt[-4].yyv.node, yypt[-1].yyv.node); } break;
case 53:
#line	431	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanSend, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 54:
#line	432	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanTry, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 55:
#line	433	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NChanRecv, nil, nil, yypt[-3].yyv.node, yypt[-0].yyv.node); } break;
case 56:
#line	434	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAssign, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 57:
#line	435	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAdd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 58:
#line	436	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NSub, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 59:
#line	437	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NMul, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 60:
#line	438	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NDiv, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 61:
#line	439	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NMod, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 62:
#line	440	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NEq, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 63:
#line	441	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 64:
#line	442	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLt, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 65:
#line	443	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 66:
#line	444	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NGt, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 67:
#line	445	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NGe, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 68:
#line	446	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NAnd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 69:
#line	447	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NOr, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 70:
#line	448	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitAnd, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 71:
#line	449	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitOr, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 72:
#line	450	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitXor, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 73:
#line	451	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NLshift, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 74:
#line	452	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NRshift, nil, nil, yypt[-2].yyv.node, yypt[-0].yyv.node); } break;
case 75:
#line	453	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNot, nil, nil, yypt[-0].yyv.node, nil); } break;
case 76:
#line	454	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBitNot, nil, nil, yypt[-0].yyv.node, nil); } break;
case 77:
#line	455	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NNeg, nil, nil, yypt[-0].yyv.node, nil); } break;
case 78:
#line	456	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NMsgSend, yypt[-3].yyv.node->name, nil, yypt[-5].yyv.node, yypt[-1].yyv.node);
    } break;
case 79:
#line	459	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        yyval.node = mk(NFuncCall, yypt[-3].yyv.node->name, nil, yypt[-1].yyv.node, nil);
    } break;
case 80:
#line	462	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 81:
#line	463	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NIntLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 82:
#line	464	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NStringLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 83:
#line	465	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NCharLit, yypt[-0].yyv.name, nil, nil, nil); } break;
case 84:
#line	466	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBoolLit, "1", nil, nil, nil); } break;
case 85:
#line	467	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = mk(NBoolLit, "0", nil, nil, nil); } break;
case 86:
#line	468	"/n/linux/objective-9c/o9c/o9_plan9.y"
{
        Node *n = mk(NClass, yypt[-3].yyv.node->name, nil, nil, nil);
        n->left = yypt[-3].yyv.node;
        n->right = yypt[-1].yyv.node;
        yyval.node = n;
    } break;
case 87:
#line	474	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-1].yyv.node; } break;
case 88:
#line	478	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = nil; } break;
case 89:
#line	479	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 90:
#line	480	"/n/linux/objective-9c/o9c/o9_plan9.y"
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
#line	492	"/n/linux/objective-9c/o9c/o9_plan9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
	}
	goto yystack;  /* stack new state and value */
}
