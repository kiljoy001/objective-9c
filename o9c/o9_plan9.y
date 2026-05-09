%{
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
%}

%union {
    Node *node;
    char *name;
}

%token <node> TIDENT TTYPE
%token <name> TINTLIT TSTRINGLIT TCHARLIT
%token TCLASS TFUNC TMETHOD TRETURN TCHAN TIF TELSE TWHILE TNEW TPRINT
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TTRUE TFALSE TARROW
%token TEQ TADD TSUB TCHANSEND TCHANRECV TCHANTRY TEQEQ TNEQ TLE TGE
%token TAND TOR TLSHIFT TRSHIFT

%left TEQ
%left TCHANSEND TCHANTRY
%right TCHANRECV
%left TOR
%left TAND
%left '|'
%left '^'
%left '&'
%left TEQEQ TNEQ
%left '<' '>' TLE TGE
%left TLSHIFT TRSHIFT
%left TADD TSUB
%left '*' '/' '%'
%right '!' '~' UMINUS
%left '.'

%type <node> program top_levels top_level class_decl member_list member var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename param_list param call_args call_arg func_top_level

%start program

%%

typename:
    TIDENT { $$ = $1; }
    | TTYPE { $$ = $1; }
    ;

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
    | func_top_level
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $6, nil);
    }
    ;

class_decl:
    TCLASS TIDENT '{' member_list '}'
    {
        $$ = mk(NClass, $2->name, nil, $4, nil);
        add_class($2->name, $$);
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
    | method_decl
    | state_decl
    | prop_decl
    | atomic_decl
    | stream_decl
    | secret_decl
    | cap_decl
    | inherit_decl
    | destructor_decl
    ;

state_decl:
    TSTATE typename TIDENT ';'
    {
        $$ = mk(NState, $3->name, $2->name, nil, nil);
    }
    ;

prop_decl:
    TPROP typename TIDENT ';'
    {
        $$ = mk(NProp, $3->name, $2->name, nil, nil);
    }
    ;

atomic_decl:
    TATOMIC typename TIDENT ';'
    {
        $$ = mk(NAtomic, $3->name, $2->name, nil, nil);
    }
    ;

stream_decl:
    TSTREAM TIDENT ';'
    {
        $$ = mk(NStream, $2->name, nil, nil, nil);
    }
    ;

secret_decl:
    TSECRET typename TIDENT ';'
    {
        $$ = mk(NSecret, $3->name, $2->name, nil, nil);
    }
    ;

cap_decl:
    TCAP typename TIDENT ';'
    {
        $$ = mk(NCap, $3->name, $2->name, nil, nil);
    }
    ;

/* 
 * C#-style method declaration.
 * Return type first:  method int64 getValue() { return val; }
 * No return type (void implied):  method inc(int64 n) { val += n; }
 * Expression body:  method int64 double() => val * 2;
 * Backward compat:  method inc() { }
 *
 * Two S/R conflicts on the TIDENT/( ambiguity are benign:
 * After "method TIDENT", lookahead TIDENT/TTYPE => shift (return-type path)
 * After "method TIDENT", lookahead '(' => shift (bare-name path)
 * Both default shift actions produce the correct parse.
 */
method_decl:
    TMETHOD typename TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $3->name, $2->name, $8, $5);
    }
    | TMETHOD typename TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $8, nil);
        $$ = mk(NMethod, $3->name, $2->name, body, $5);
    }
    | TMETHOD TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk(NMethod, $2->name, "void", $7, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $7, nil);
        $$ = mk(NMethod, $2->name, "void", body, $4);
    }
    ;

inherit_decl:
    TIDENT ';'
    {
        $$ = mk(NInherit, $1->name, nil, nil, nil);
    }
    ;

var_decl:
    typename TIDENT ';'
    {
        $$ = mk(NProp, $2->name, $1->name, nil, nil);
    }
    | typename '*' TIDENT ';'
    {
        char buf[128];
        snprint(buf, sizeof buf, "%s*", $1->name);
        $$ = mk(NProp, $3->name, buf, nil, nil);
    }
    | TCHAN TIDENT ';'
    {
        $$ = mk(NStream, $2->name, "chan", nil, nil);
    }
    ;

func_decl:
    TFUNC '(' typename '*' TIDENT ')' TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        Node *params = $9;
        Node *stmts = $13;
        $$ = mk(NMethod, $7->name, $11->name, stmts, params);
    }
    ;

param_list:
    /* empty */ { $$ = nil; }
    | param { $$ = $1; }
    | param_list ',' param {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

param:
    typename TIDENT
    {
        $$ = mk(NProp, $2->name, $1->name, nil, nil);
    }
    ;

destructor_decl:
    '~' TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NDestructor, $2->name, nil, $6, nil);
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
    typename TIDENT ';' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | typename TIDENT TEQ expr ';' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | expr '.' TIDENT TEQ expr ';' { $$ = mk(NAssign, $3->name, nil, $1, $5); }
    | expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    | TPRINT '(' call_args ')' ';' {
        $$ = mk(NFuncCall, "print", nil, $3, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' { $$ = mk(NIf, nil, nil, $3, $6); }
    | TIF '(' expr ')' '{' stmt_list '}' TELSE '{' stmt_list '}' {
        $$ = mk(NIfElse, nil, nil, $3, mk(NElse, nil, nil, $6, $10));
    }
    | TWHILE '(' expr ')' '{' stmt_list '}' { $$ = mk(NWhile, nil, nil, $3, $6); }
    ;

expr:
    expr TCHANSEND expr { $$ = mk(NChanSend, nil, nil, $1, $3); }
    | expr TCHANTRY expr { $$ = mk(NChanTry, nil, nil, $1, $3); }
    | expr TEQ TCHANRECV expr { $$ = mk(NChanRecv, nil, nil, $1, $4); }
    | expr TEQ expr { $$ = mk(NAssign, nil, nil, $1, $3); }
    | expr TADD expr { $$ = mk(NAdd, nil, nil, $1, $3); }
    | expr TSUB expr { $$ = mk(NSub, nil, nil, $1, $3); }
    | expr '*' expr { $$ = mk(NMul, nil, nil, $1, $3); }
    | expr '/' expr { $$ = mk(NDiv, nil, nil, $1, $3); }
    | expr '%' expr { $$ = mk(NMod, nil, nil, $1, $3); }
    | expr TEQEQ expr { $$ = mk(NEq, nil, nil, $1, $3); }
    | expr TNEQ expr { $$ = mk(NNe, nil, nil, $1, $3); }
    | expr '<' expr { $$ = mk(NLt, nil, nil, $1, $3); }
    | expr TLE expr { $$ = mk(NLe, nil, nil, $1, $3); }
    | expr '>' expr { $$ = mk(NGt, nil, nil, $1, $3); }
    | expr TGE expr { $$ = mk(NGe, nil, nil, $1, $3); }
    | expr TAND expr { $$ = mk(NAnd, nil, nil, $1, $3); }
    | expr TOR expr { $$ = mk(NOr, nil, nil, $1, $3); }
    | expr '&' expr { $$ = mk(NBitAnd, nil, nil, $1, $3); }
    | expr '|' expr { $$ = mk(NBitOr, nil, nil, $1, $3); }
    | expr '^' expr { $$ = mk(NBitXor, nil, nil, $1, $3); }
    | expr TLSHIFT expr { $$ = mk(NLshift, nil, nil, $1, $3); }
    | expr TRSHIFT expr { $$ = mk(NRshift, nil, nil, $1, $3); }
    | '!' expr { $$ = mk(NNot, nil, nil, $2, nil); }
    | '~' expr { $$ = mk(NBitNot, nil, nil, $2, nil); }
    | TSUB expr %prec UMINUS { $$ = mk(NNeg, nil, nil, $2, nil); }
    | expr '.' TIDENT '(' call_args ')' {
        $$ = mk(NMsgSend, $3->name, nil, $1, $5);
    }
    | TIDENT { $$ = $1; }
    | TINTLIT { $$ = mk(NIntLit, $1, nil, nil, nil); }
    | TSTRINGLIT { $$ = mk(NStringLit, $1, nil, nil, nil); }
    | TCHARLIT { $$ = mk(NCharLit, $1, nil, nil, nil); }
    | TTRUE { $$ = mk(NBoolLit, "1", nil, nil, nil); }
    | TFALSE { $$ = mk(NBoolLit, "0", nil, nil, nil); }
    | TNEW typename '(' call_args ')' {
        Node *n = mk(NClass, $2->name, nil, nil, nil);
        n->left = $2;
        n->right = $4;
        $$ = n;
    }
    | '(' expr ')' { $$ = $2; }
    ;

call_args:
    /* empty */ { $$ = nil; }
    | call_arg { $$ = $1; }
    | call_args ',' call_arg {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

call_arg:
    expr { $$ = $1; }
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
            /* Emit fprint(1, "fmt", args...) — stdout on both plan9port and 9front */
            print("fprint(1, ");
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
                print("\t%s.shm_base = __%s;\n", s->name, s->name);
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
                /* Register in /srv/<class>/<name>/ instance tree */
                print("\t%s_create_instance(__%s, \"%s\");\n", cn, s->name, s->name);
                /* Send constructor args if any — stack-allocated, no global race */
                if(nctor > 0){
                    Node *ca;
                    int ai = 0;
                    print("\t{ vlong __a[%d];\n", nctor);
                    for(ca = s->left->right; ca; ca = ca->next){
                        print("\t__a[%d] = ", ai);
                        gen_expr(ca);
                        print(";\n");
                        ai++;
                    }
                    print("\tobj9_msgSend(&%s, 0x%lux, __a); }\n", s->name, o9_hash(cname));
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
        if(s->name != nil && s->left != nil && s->left->type == NIdent && s->left->name != nil){
            /* Property write: obj.prop = expr */
            char *cname = get_var_class(s->left->name);
            if(cname != nil && find_class(cname)){
                /* Direct struct write via shm_base */
                print("\t{ %s_Client *__c = (%s_Client*)&", cname, cname);
                gen_expr(s->left);
                print(";\n\t\tif(__c->shm_base){ ((%s_Internal*)__c->shm_base)->%s = (vlong)(", cname, s->name);
                gen_expr(s->right);
                print("); } }\n");
                break;
            }
        }
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
    /* Emits snprint statements that fill a runtime cache buffer */
    Node *m, *p;
    if(c == nil) return;
    print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"seg:%s\\n\");\n", classname);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_cache_entries(p, classname);
        }
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"d:%%ld:%%ld\\n\", %ldL, (long)o9_offsetof(%s_Internal, %s));\n", o9_hash(m->name), classname, m->name);
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"c:%%ld:%%p\\n\", %ldL, o9_impl_%s_%s);\n", o9_hash(m->name), c->name, m->name);
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
    print("struct %s_Internal {\n\tArcLedger ledger;\n\tlong ref;\t/* ARC reference count */\n", c->name);
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

    /* 2b. ARC attach/destroyfid callbacks */
    print("static void o9_attach_%s(Req *r) {\n", c->name);
    print("\t%s_Internal *self = r->srv->aux;\n", c->name);
    print("\tainc(&self->ref);\n");
    print("\trespond(r, nil);\n");
    print("}\n\n");
    print("static void o9_destroyfid_%s(Fid *f) {\n", c->name);
    print("\tUSED(f);\n");
    print("\t%s_Internal *self = f->pool->srv->aux;\n", c->name);
    print("\tif(adec(&self->ref) == 0){\n");
    print("\t\tO9Msg *m = mallocz(sizeof(O9Msg), 1);\n");
    print("\t\tm->sel = 0x%lux;\n", o9_hash("destroy"));
    print("\t\tm->replyc = nil;\n");
    print("\t\tsendp(self->dispatch_chan, m);\n");
    print("\t}\n");
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

    /* 4. 9P Fileserver Facade — clone pattern */
    print("static void fsread_%s(Req *r) {\n", c->name);
    print("\tchar buf[1024];\n\tchar *name = r->fid->file->name;\n\t%s_Internal *inst = r->fid->file->aux;\n\n", c->name);
    print("\tif(strcmp(name, \"status\") == 0) { readstr(r, \"running\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"cache\") == 0) {\n");
    print("\t\tchar cachebuf[4096];\n\t\tchar *p = cachebuf;\n");
    /* Call gen_cache_entries for this class */
    gen_cache_entries(c, c->name);
    print("\t\tUSED(p);\n");
    print("\t\treadstr(r, cachebuf); respond(r, nil); return;\n\t}\n");
    print("\tif(inst == nil) { respond(r, \"clone read\"); return; }\n\n");
    /* Method file reads: check for stored O9Reply in fid aux */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0 && strcmp(m->typename, "void") != 0){
            char *t = map_type(m->typename);
            char *fmt = type_fmt(t);
            char *cast = type_cast(t);
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            print("\t\tO9Reply *__o9rep = r->fid->aux;\n");
            print("\t\tif(__o9rep == nil){ respond(r, \"no pending reply\"); return; }\n");
            if(strcmp(fmt, "%s") == 0){
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", (char*)__o9rep->ret);\n");
            } else {
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)__o9rep->ret);\n", fmt, cast);
            }
            print("\t\tr->fid->aux = nil;\n");
            print("\t\tfree(__o9rep);\n");
            print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            char *fmt = type_fmt(t);
            char *cast = type_cast(t);
            if(strcmp(fmt, "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", inst->%s ? inst->%s : \"\");\n", m->name, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)inst->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");

    print("static void fswrite_%s(Req *r) {\n", c->name);
    print("\tchar *name = r->fid->file->name;\n\t%s_Internal *inst = r->fid->file->aux;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) { /* TODO: parse ctl */ respond(r, nil); return; }\n");
    /* Method dispatch: write to method file triggers CSP call */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            int np = 0;
            Node *p;
            for(p = m->right; p; p = p->next) np++;
            print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
            if(np > 0){
                print("\t\tvlong __wargs[%d] = {0};\n", np);
                print("\t\t__wargs[0] = strtoll(r->ifcall.data, nil, 0);\n");
            }
            /* Direct channel send — inst is the Internal struct with dispatch_chan */
            {
                char *a = np > 0 ? "__wargs" : "nil";
                print("\t\t{ O9Msg __wm = {0x%lux, %s, %d, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name), a, np);
                print("\t\tsendp(inst->dispatch_chan, &__wm);\n");
                if(strcmp(m->typename, "void") != 0){
                    /* Return-value method: store O9Reply in fid aux for readback */
                    print("\t\tO9Reply *__o9rep = recvp(__wm.replyc);\n");
                    print("\t\tr->fid->aux = __o9rep;\n");
                } else {
                    /* Void method: discard reply */
                    print("\t\trecvp(__wm.replyc);\n");
                }
                print("\t\tchanfree(__wm.replyc); }\n");
            }
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            if(strcmp(type_fmt(t), "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tfree(inst->%s);\n", m->name);
                print("\t\tinst->%s = strdup(r->ifcall.data);\n", m->name);
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tinst->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"read only or not found\");\n}\n\n");
    print("Srv o9srv_%s;\n", c->name);
    print("static Tree *%s_tree;\n", c->name);
    print("int %s_create_instance(%s_Internal *inst, char *name) {\n", c->name, c->name);
    print("\tFile *dir = createfile(%s_tree->root, name, nil, 0755, nil);\n", c->name);
    print("\tif(dir == nil) return -1;\n");
    print("\tdir->aux = inst;\n");
    print("\tcreatefile(dir, \"status\", nil, 0444, nil);\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic)
            print("\t{ File *__f = createfile(dir, \"%s\", nil, 0666, nil); if(__f) __f->aux = inst; }\n", m->name);
    }
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && strcmp(m->name, "main") != 0){
            char *perm = (strcmp(m->typename, "void") == 0) ? "0222" : "0644";
            print("\t{ File *__f = createfile(dir, \"%s\", nil, %s, nil); if(__f) __f->aux = inst; }\n", m->name, perm);
        }
    }
    print("\treturn 0;\n}\n");
    print("void o9_main_%s(int argc, char **argv) {\n", c->name);
    print("\tUSED(argc); USED(argv);\n");
    print("\t%s_Internal *s = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
    print("\tmemset(s, 0, sizeof(%s_Internal));\n", c->name);
    print("\ts->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\to9srv_%s.read = fsread_%s;\n\to9srv_%s.write = fswrite_%s;\n", c->name, c->name, c->name, c->name);
    print("\to9srv_%s.aux = s;\n", c->name);
    print("\to9srv_%s.attach = o9_attach_%s;\n", c->name, c->name);
    print("\to9srv_%s.destroyfid = o9_destroyfid_%s;\n", c->name, c->name);
    print("\t%s_tree = alloctree(nil, nil, 0555, nil);\n\to9srv_%s.tree = %s_tree;\n", c->name, c->name, c->name);
    print("\tcreatefile(%s_tree->root, \"clone\", nil, 0222, nil);\n", c->name);
    print("\tcreatefile(%s_tree->root, \"status\", nil, 0444, nil);\n", c->name);
    print("\tcreatefile(%s_tree->root, \"cache\", nil, 0444, nil);\n", c->name);
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
    print("\tUSED(argc); USED(argv);\n");
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
