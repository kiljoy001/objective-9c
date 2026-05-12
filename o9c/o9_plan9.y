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
    NElseIf,
    NWhile,
    NLocalVar,
    NMsgSend,
    NPropRead,
    NFuncCall,
    NFor,
    NArrayGet,
    NArraySet
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
int   is_primitive(char *t);

Node *ast_root;

char*
map_type(char *t)
{
    int len;
    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0) return "char*";
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
    return t;
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

int
is_primitive(char *t)
{
    if(t == nil) return 1;
    if(strcmp(t, "int64") == 0) return 1;
    if(strcmp(t, "uint64") == 0) return 1;
    if(strcmp(t, "int32") == 0) return 1;
    if(strcmp(t, "uint32") == 0) return 1;
    if(strcmp(t, "int16") == 0) return 1;
    if(strcmp(t, "uint16") == 0) return 1;
    if(strcmp(t, "int8") == 0) return 1;
    if(strcmp(t, "uint8") == 0) return 1;
    if(strcmp(t, "bool") == 0) return 1;
    if(strcmp(t, "string") == 0) return 1;
    if(strcmp(t, "int") == 0) return 1;
    if(strcmp(t, "char") == 0) return 1;
    if(strcmp(t, "vlong") == 0) return 1;
    if(strcmp(t, "uvlong") == 0) return 1;
    if(strcmp(t, "ulong") == 0) return 1;
    if(strcmp(t, "ushort") == 0) return 1;
    if(strcmp(t, "uchar") == 0) return 1;
    if(strcmp(t, "void") == 0) return 1;
    return 0;
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
%token TCLASS TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TNIL
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TTRUE TFALSE TARROW
%token TEQ TADD TSUB TCHANSEND TCHANRECV TCHANTRY TEQEQ TNEQ TLE TGE
%token TAND TOR TLSHIFT TRSHIFT TFORSEMI

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
%left '.' '['
 
%type <node> program top_levels top_level class_decl member_list member var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename param_list param call_args call_arg func_top_level for_init for_cond for_step else_clause

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
    | TDICT '<' typename ',' typename '>' TIDENT ';'
    {
        /* Dict<K,V> name — store as "Dict:keytype:valtype" in typename for codegen */
        char buf[128];
        snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name);
        $$ = mk(NProp, $7->name, buf, nil, nil);
    }
    | typename '[' ']' TIDENT ';'
    {
        char buf[64];
        snprint(buf, sizeof buf, "%s[]", $1->name);
        $$ = mk(NProp, $4->name, buf, nil, nil);
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
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElse, nil, nil, $10, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElseIf, nil, nil, $10, $13);
        if($15) $$->next->next = $15;
    }
    | TWHILE '(' expr ')' '{' stmt_list '}' { $$ = mk(NWhile, nil, nil, $3, $6); }
    | TFOR '(' for_init TFORSEMI for_cond TFORSEMI for_step ')' '{' stmt_list '}' { $$ = mk(NFor, nil, nil, $3, mk(NFor, nil, nil, $5, $7)); $$->right->next = $10; }
    ;

for_init:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_cond:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_step:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

else_clause:
    /* empty */ { $$ = nil; }
    | TELSE '{' stmt_list '}' { $$ = mk(NElse, nil, nil, $3, nil); }
    | TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NElseIf, nil, nil, $3, $6);
        $$->next = $8;
    }
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
    | expr '.' TIDENT {
        $$ = mk(NPropRead, $3->name, nil, $1, nil);
    }
    | expr '.' TIDENT '(' call_args ')' {
        $$ = mk(NMsgSend, $3->name, nil, $1, $5);
    }
    | expr '[' expr ']' {
        $$ = mk(NArrayGet, nil, nil, $1, $3);
    }
    | TIDENT { $$ = $1; }
    | TINTLIT { $$ = mk(NIntLit, $1, nil, nil, nil); }
    | TSTRINGLIT { $$ = mk(NStringLit, $1, nil, nil, nil); }
    | TCHARLIT { $$ = mk(NCharLit, $1, nil, nil, nil); }
    | TTRUE { $$ = mk(NBoolLit, "1", nil, nil, nil); }
    | TFALSE { $$ = mk(NBoolLit, "0", nil, nil, nil); }
    | TNIL { $$ = mk(NBoolLit, "nil", nil, nil, nil); }
    | TNEW typename '(' call_args ')' {
        Node *n = mk(NClass, $2->name, "same", nil, nil);
        n->left = $2;
        n->right = $4;
        $$ = n;
    }
    | TNEW TNEAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "near", nil, nil);
        n->left = $3;
        n->right = $5;
        $$ = n;
    }
    | TNEW TFAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "far", nil, nil);
        n->left = $3;
        n->right = $5;
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

static char *input_buf;
static int input_pos;
static int input_len;
static int in_prescan;		/* 1 during prescan phase, 0 during parse */
static int for_paren_depth = -1;	/* >=0 when inside for(...) — ';' returns TFORSEMI */
static int pushback[8];		/* multi-char pushback buffer */
static int npush = 0;

static int
lex_getc(void)
{
	if(npush > 0)
		return pushback[--npush];
	if(input_pos >= input_len)
		return Beof;
	return (unsigned char)input_buf[input_pos++];
}

static void
lex_ungetc(int c)
{
	if(npush < 8)
		pushback[npush++] = c;
}

int
yylex(void)
{
    int c;

    while((c = lex_getc()) != Beof){
        if(isspace(c))
            continue;
        /* Inside for(...): track paren depth, convert ';' to TFORSEMI */
        if(for_paren_depth >= 0){
            if(c == '(') { for_paren_depth++; return '('; }
            if(c == ')' && for_paren_depth > 0) { for_paren_depth--; return ')'; }
            if(c == ')' && for_paren_depth == 0) { for_paren_depth = -1; return ')'; }
            if(c == ';') return TFORSEMI;
        }
        if(c == '~')
            return '~';
        if(c == '='){
            if((c = lex_getc()) == '=') return TEQEQ;
            if(c == '>') return TARROW;
            lex_ungetc(c);
            return TEQ;
        }
        if(c == '&'){
            if((c = lex_getc()) == '&') return TAND;
            lex_ungetc(c);
            return '&';
        }
        if(c == '|'){
            if((c = lex_getc()) == '|') return TOR;
            lex_ungetc(c);
            return '|';
        }
        if(c == '!'){
            if((c = lex_getc()) == '=') return TNEQ;
            lex_ungetc(c);
            return '!';
        }
        if(c == '<'){
            if((c = lex_getc()) == '-') return TCHANRECV;
            if(c == '=') return TLE;
            if(c == '<') return TLSHIFT;
            lex_ungetc(c);
            return '<';
        }
        if(c == '>'){
            if((c = lex_getc()) == '=') return TGE;
            if(c == '>') return TRSHIFT;
            lex_ungetc(c);
            return '>';
        }
        if(c == '"'){
            char buf[1024];
            int i = 0;
            while((c = lex_getc()) != Beof && c != '"' && i < 1023) {
                if(c == '\\'){
                    if((c = lex_getc()) == Beof) break;
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
            while((c = lex_getc()) != Beof && c != '\'' && i < 15) {
                if(c == '\\'){
                    if((c = lex_getc()) == Beof) break;
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
            if((c = lex_getc()) == '>'){
                if((c = lex_getc()) == '?') return TCHANTRY;
                lex_ungetc(c);
                return TCHANSEND;
            }
            lex_ungetc(c);
            return TSUB;
        }
        if(c == '/'){
            if((c = lex_getc()) == '/'){
                while((c = lex_getc()) != Beof && c != '\n');
                continue;
            }
            if(c == '*'){
                while((c = lex_getc()) != Beof){
                    if(c == '*'){
                        if((c = lex_getc()) == '/') break;
                        lex_ungetc(c);
                    }
                }
                continue;
            }
            lex_ungetc(c);
            return '/';
        }
        if(c == '+') return TADD;

        if(isdigit(c)){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            if(c == '0'){
                c = lex_getc();
                if(c == 'x' || c == 'X'){
                    buf[i++] = c;
                    while(isxdigit(c = lex_getc())) {
                        if(i < 63) buf[i++] = c;
                    }
                    lex_ungetc(c);
                    buf[i] = '\0';
                    yylval.name = strdup(buf);
                    return TINTLIT;
                }
                lex_ungetc(c);
            }
            while(isdigit(c = lex_getc())) {
                if(i < 63) buf[i++] = c;
            }
            lex_ungetc(c);
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TINTLIT;
        }

        if(isalpha(c) || c == '_'){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = lex_getc()) || c == '_') {
                if(i < 63) buf[i++] = c;
            }
            lex_ungetc(c);
            buf[i] = '\0';
            
            yylval.node = mk(NIdent, buf, nil, nil, nil);
            
            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "far") == 0) return TFAR;
            if(strcmp(buf, "Dict") == 0) return TDICT;
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
            if(strcmp(buf, "else") == 0){
                int nc = lex_getc();
                while(nc == ' ' || nc == '\t') nc = lex_getc();
                if(nc == 'i'){
                    int nc2 = lex_getc();
                    if(nc2 == 'f') return TELIF;
                    lex_ungetc(nc2);
                }
                lex_ungetc(nc);
                return TELSE;
            }
            if(strcmp(buf, "while") == 0) return TWHILE;
            if(strcmp(buf, "for") == 0){ for_paren_depth = 0; return TFOR; }
            if(strcmp(buf, "true") == 0) return TTRUE;
            if(strcmp(buf, "false") == 0) return TFALSE;
            if(strcmp(buf, "nil") == 0) return TNIL;
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
Node *cur_class;			/* current class being codegen'd, for type lookups */

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
        {
            /* Re-escape special chars for C output */
            char *s;
            print("\"");
            for(s = e->name; *s; s++){
                if(*s == '\n') print("\\n");
                else if(*s == '\t') print("\\t");
                else if(*s == '\\') print("\\\\");
                else if(*s == '"') print("\\\"");
                else print("%c", *s);
            }
            print("\"");
        }
        break;
    case NCharLit:
        print("'%s'", e->name);
        break;
    case NBoolLit:
        print("%s", e->name);
        break;
    case NMsgSend:
        /* c.method(args...) -> try o9_dispatch_call, fallback to obj9_msgSend */
        /* Pack: args[0]=shm_base (Internal*), then real args at [1..N] */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            /* Load args array: args[0]=shm_base, args[1..N]=real args */
            print("(o9_call_args[0]=");
            if(e->left && e->left->type == NIdent && e->left->name){
                char *__cnx = get_var_class(e->left->name);
                if(__cnx) print("(vlong)((%s_Client*)&", __cnx);
                gen_expr(e->left);
                if(__cnx) print(")->shm_base");
            } else {
                print("(vlong)&");
                gen_expr(e->left);
            }
            {
                int i = 1;
                for(a = e->right; a; a = a->next){
                    print(", o9_call_args[%d]=", i);
                    gen_expr(a);
                    i++;
                }
            }
            /* Try ctrl dispatch, fallback to CSP */
            print(", (vlong)o9_dispatch_call(&");
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args) || ", o9_hash(e->name));
            print("(vlong)obj9_msgSend(&");
            gen_expr(e->left);
            print(", \"%s\", 0x%lux, o9_call_args))", e->name, o9_hash(e->name));
        }
        break;
    case NPropRead:
        /* obj.prop — property read via SHM */
        /* emit: (vlong)((ClassName_Internal*)((ClassName_Client*)&obj)->shm_base)->prop */
        {
            /* If left is an ident, try to look up its class */
            if(e->left && e->left->type == NIdent && e->left->name){
                char *cn = get_var_class(e->left->name);
                if(cn != nil){
                    print("(vlong)((%s_Internal*)((%s_Client*)&", cn, cn);
                    gen_expr(e->left);
                    print(")->shm_base)->%s", e->name);
                } else {
                    /* Fallback: direct struct access */
                    gen_expr(e->left);
                    print(".%s", e->name);
                }
            } else {
                gen_expr(e->left);
                print(".%s", e->name);
            }
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
            /* Emit fprint(1, "fmt", args...) */
            print("fprint(1, ");
            Node *a = e->left;
            if(a == nil){
                print("\"\"");
            } else if(a->type == NStringLit && a->next == nil){
                /* Single string literal — use as format directly */
                gen_expr(a);
            } else {
                /* First arg is our format string or the value itself */
                int first = 1;
                Node *first_arg = a;
                if(first_arg->type == NStringLit){
                    /* Format string provided */
                    gen_expr(first_arg);
                    first = 0;
                    for(a = first_arg->next; a; a = a->next){
                        if(!first) print(", ");
                        gen_expr(a);
                        first = 0;
                    }
                } else if(first_arg->next == nil){
                    /* Single non-string arg — use %lld as format */
                    print("\"%%lld\"");
                    print(", ");
                    gen_expr(first_arg);
                } else {
                    /* Multiple args, first not a string — print bare */
                    for(a = first_arg; a; a = a->next){
                        if(!first) print(", ");
                        gen_expr(a);
                        first = 0;
                    }
                }
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
    case NArrayGet:
        if(e->right && e->right->type == NStringLit){
            /* Dict access: dict["key"] => o9_dict_get(&dict, "key") */
            print("o9_dict_get(&");
            gen_expr(e->left);
            print(", ");
            gen_expr(e->right);
            print(")");
        } else {
            /* Array access: arr[idx] => o9_array_get(arr, idx) */
            print("o9_array_get(");
            gen_expr(e->left);
            print(", ");
            gen_expr(e->right);
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
                char *dist = s->left->typename;
                int dval = (dist && strcmp(dist, "near") == 0) ? 0 : (dist && strcmp(dist, "far") == 0) ? 1 : -1;
                /* Count constructor args from TNEW node's call_args (s->left->right) */
                int nctor = 0;
                {
                    Node *ca;
                    for(ca = s->left->right; ca; ca = ca->next) nctor++;
                }
                if(dval >= 0){
                    /* Remote: connect via IL/TCP, no local server */
                    Node *first_arg = s->left->right;
                    int rest = nctor - 1;
                    print("\t%s_Client %s;\n", cn, s->name);
                    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
                    /* First constructor arg is the address */
                    print("\t{\n");
                    if(first_arg){
                        print("\t\tchar __addr[128];\n");
                        print("\t\tsnprint(__addr, sizeof __addr, ");
                        gen_expr(first_arg);
                        print(");\n");
                        print("\t\to9_connect(&%s, __addr, \"%s\");\n", s->name, cn);
                    }
                    print("\t\t%s.distance = %d;\n", s->name, dval);
                    /* Send constructor args (skip address, send rest) */
                    if(rest > 0){
                        Node *ca;
                        int ai;
                        print("\t\tvlong __a[%d];\n", rest);
                        for(ca = first_arg->next; ca; ca = ca->next){
                            print("\t\t__a[%d] = ", ai);
                            gen_expr(ca);
                            print(";\n");
                            ai++;
                        }
                        print("\t\tobj9_msgSend(&%s, \"%s\", 0x%lux, __a);\n", s->name, cn, o9_hash(cname));
                    }
                    print("\t}\n");
                } else {
                    /* Local: spawn in-process server */
                    Node *m, *ca;
                    int ai;
                    print("\t%s_Internal *__%s = emalloc9p(sizeof(%s_Internal));\n", cn, s->name, cn);
                    print("\tmemset(__%s, 0, sizeof(%s_Internal));\n", s->name, cn);
                    print("\t__%s->dispatch_chan = chancreate(sizeof(void*), 10);\n", s->name);
                    print("\t%s_Client %s;\n", cn, s->name);
                    print("\to9_AsmTable %s_tbl;\n", s->name);
                    print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
                    print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
                    print("\t%s.shm_base = __%s;\n", s->name, s->name);
                    print("\t%s.dispatch_chan = __%s->dispatch_chan;\n", s->name, s->name);
                    print("\t%s.table = &%s_tbl;\n", s->name, s->name);
                    print("\t__%s->distance = -1;\n", s->name);
                    print("\t%s.distance = -1;\n", s->name);
                    if(find_class(cn)){
                        Node *cnode = find_class(cn);
                        Node *m;
                        for(m = cnode->left; m; m = m->next){
                            if(m->type == NProp || m->type == NState || m->type == NAtomic){
                                if(m->typename && strncmp(m->typename, "Dict:", 5) == 0)
                                    print("\t\to9_dict_init(&__%s->%s);\n", s->name, m->name);
                                else
                                    print("\t__%s->%s = 0;\n", s->name, m->name);
                            }
                        }
                    }
                    print("\tproccreate(%s_loop, __%s, 8192);\n", cn, s->name);
                    print("\t%s_create_instance(__%s, \"%s\");\n", cn, s->name, s->name);
                    print("\t{ vlong __a[%d];\n", nctor);
                    for(ca = s->left->right; ca; ca = ca->next){
                        print("\t__a[%d] = ", ai);
                        gen_expr(ca);
                        print(";\n");
                        ai++;
                    }
                    print("\tobj9_msgSend(&%s, \"%s\", 0x%lux, __a); }\n", s->name, cn, o9_hash(cname));
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
        if(s->left != nil && s->left->type == NArrayGet){
            if(s->left->right && s->left->right->type == NStringLit){
                /* Dict set: dict["key"] = val -> o9_dict_set(&dict, "key", val) */
                print("\to9_dict_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
                print(");\n");
            } else {
                /* Array set: a[idx] = expr -> o9_array_set(&a, idx, expr) */
                print("\to9_array_set(&");
                gen_expr(s->left->left);
                print(", ");
                gen_expr(s->left->right);
                print(", ");
                gen_expr(s->right);
                print(");\n");
            }
            break;
        }
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
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        /* Walk the else/elseif chain via ->next */
        if(s->next){
            Node *tail = s->next;
            int closed = 0;
            while(tail){
                if(tail->type == NElseIf){
                    print("\t} else if("); gen_expr(tail->left); print("){\n");
                    for(n = tail->right; n; n = n->next) gen_stmt(c, n);
                } else if(tail->type == NElse){
                    print("\t} else {\n");
                    for(n = tail->left; n; n = n->next) gen_stmt(c, n);
                    print("\t}\n");
                    closed = 1;
                    break;
                }
                tail = tail->next;
            }
            if(!closed)
                print("\t}\n");
        } else {
            print("\t}\n");
        }
        break;
    case NElseIf:
        /* Should not be reached as a top-level statement — handled by NIfElse chain */
        break;
    case NWhile:
        print("\twhile("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NFor:
        /* s->left=init, s->right->left=cond, s->right->right=step, s->right->next=body */
        print("\tfor(");
        if(s->left) gen_expr(s->left);
        print("; ");
        if(s->right->left) gen_expr(s->right->left);
        print("; ");
        if(s->right->right) gen_expr(s->right->right);
        print("){\n");
        for(n = s->right->next; n; n = n->next) gen_stmt(c, n);
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
    print("typedef struct %s_Client {\n\tint fd;\n\tvoid *shm_base;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n", c->name);
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
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof cachebuf - (p-cachebuf), \"c:%%ld:%%p\\n\", %ldL, o9_ctrl_%s_%s);\n", o9_hash(m->name), c->name, m->name);
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
            char *t = map_type(m->typename);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize to buf */
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&s->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s);\n", m->name);
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(strcmp(type_fmt(t), "%s") == 0){
                    /* String property */
                    print("\t\treadstr(r, s->%s ? s->%s : \"\");\n", m->name, m->name);
                } else {
                    print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (vlong)s->%s);\n", type_fmt(t), m->name);
                    print("\t\treadstr(r, buf);\n");
                }
            }
            print("\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
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
            char *t = map_type(m->typename);
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: deserialize from write data */
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                print("\t\to9_dict_deserialize(&s->%s, r->ifcall.data);\n", m->name);
            } else {
                print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
                if(strcmp(type_fmt(t), "%s") == 0){
                    /* String property */
                    print("\t\tfree(s->%s);\n", m->name);
                    print("\t\ts->%s = strdup(r->ifcall.data);\n", m->name);
                } else {
                    print("\t\ts->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                }
            }
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
    print("struct %s_Internal {\n\tArcLedger ledger;\n\tlong ref;\t/* ARC reference count */\n\tint distance;\t/* -1=same, 0=near/IL, 1=far/TCP */\n", c->name);
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
			/* Ctrl dispatch thunk (void(*)(void*) for asm cache) */
			{
				int np = 0, pi;
				Node *pn;
				for(pn = m->right; pn; pn = pn->next) np++;
				print("static void o9_ctrl_%s_%s(void *__a){\n", c->name, m->name);
				print("\t%s_Internal *self = (%s_Internal*)((vlong*)__a)[0];\n", c->name, c->name);
				if(np > 0){
					for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
						print("\t%s __%s = ((vlong*)__a)[%d];\n", map_type(pn->typename), pn->name, pi+1);
					print("\tvlong __args[%d];\n", np);
					for(pn = m->right, pi = 0; pn; pn = pn->next, pi++)
						print("\t__args[%d] = __%s;\n", pi, pn->name);
					print("\tO9Msg __m = {0x%lux, __args, %d, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name), np);
				} else
					print("\tO9Msg __m = {0x%lux, nil, 0, chancreate(sizeof(void*), 0)};\n", o9_hash(m->name));
				print("\to9_impl_%s_%s(self, &__m);\n", c->name, m->name);
				print("\t{ O9Reply *__r = recvp(__m.replyc); free(__r); }\n");
				print("\tchanfree(__m.replyc);\n}\n\n");
			}
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
    {
        ulong _aid = o9_hash(c->name);
        print("static void o9_attach_%s(Req *r) {\n", c->name);
        print("\t%s_Internal *self = r->srv->aux;\n", c->name);
        print("\tself->ledger.entries[0x%lux & 63].count++;\n", _aid);
        print("\tainc(&self->ref);\n");
        print("\trespond(r, nil);\n");
        print("}\n\n");
        print("static void o9_destroyfid_%s(Fid *f) {\n", c->name);
        print("\tUSED(f);\n");
        print("\t%s_Internal *self = f->pool->srv->aux;\n", c->name);
        print("\tself->ledger.entries[0x%lux & 63].count--;\n", _aid);
        print("\tif(adec(&self->ref) == 0){\n");
    }
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
    print("\tif(strcmp(name, \"__distance__\") == 0 && inst) { snprint(buf, sizeof buf, \"%%d\\n\", inst->distance); readstr(r, buf); respond(r, nil); return; }\n");
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
            if(strcmp(t, "O9Dict") == 0){
                /* Dict property: serialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tchar *__s = o9_dict_serialize(&inst->%s); snprint(buf, sizeof buf, \"%%s\", __s); readstr(r, buf); free(__s); respond(r, nil); return;\n\t}\n", m->name);
            } else if(strcmp(fmt, "%s") == 0) {
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
            if(strcmp(t, "O9Dict") == 0) {
                /* Dict property: deserialize */
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\to9_dict_deserialize(&inst->%s, r->ifcall.data);\n", m->name);
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else if(strcmp(type_fmt(t), "%s") == 0) {
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
    print("\t{ File *__df = createfile(dir, \"__distance__\", nil, 0444, nil); if(__df) __df->aux = inst; }\n");
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

/* Two-pass parser: prescan registers all type names, then yyparse() resolves them */

static void
prescan(void)
{
    int c;
    int i;
    char buf[64];
    input_pos = 0;
    in_prescan = 1;
    
    while(input_pos < input_len){
        c = (unsigned char)input_buf[input_pos++];
        if(isspace(c) || c == '{' || c == '}' || c == ';' || c == '(' || c == ')')
            continue;
        /* Skip string literals */
        if(c == '"'){
            while(input_pos < input_len && input_buf[input_pos] != '"')
                input_pos++;
            if(input_pos < input_len) input_pos++;
            continue;
        }
        /* Skip char literals */
        if(c == '\''){
            if(input_pos < input_len && input_buf[input_pos] == '\\')
                input_pos++;
            if(input_pos < input_len) input_pos++;
            if(input_pos < input_len) input_pos++;
            continue;
        }
        /* Skip line comments */
        if(c == '/' && input_pos < input_len && input_buf[input_pos] == '/'){
            while(input_pos < input_len && input_buf[input_pos] != '\n')
                input_pos++;
            continue;
        }
        /* Skip block comments */
        if(c == '/' && input_pos < input_len && input_buf[input_pos] == '*'){
            input_pos++; /* skip * */
            while(input_pos + 1 < input_len && !(input_buf[input_pos] == '*' && input_buf[input_pos+1] == '/')){
                if(input_buf[input_pos] == '*' && input_pos + 1 < input_len && input_buf[input_pos+1] == '/')
                    break;
                input_pos++;
            }
            if(input_pos + 1 < input_len) input_pos += 2; /* skip */ 
            continue;
        }
        /* Skip numbers */
        if(isdigit(c)){
            if(c == '0' && input_pos < input_len && (input_buf[input_pos] == 'x' || input_buf[input_pos] == 'X'))
                input_pos++; /* skip x */
            while(input_pos < input_len && isxdigit((unsigned char)input_buf[input_pos]))
                input_pos++;
            continue;
        }
        /* Identifiers and keywords */
        if(isalpha(c) || c == '_'){
            i = 0;
            buf[i++] = c;
            while(i < 63 && input_pos < input_len && (isalnum((unsigned char)input_buf[input_pos]) || input_buf[input_pos] == '_'))
                buf[i++] = input_buf[input_pos++];
            buf[i] = '\0';
            
            if(strcmp(buf, "class") == 0){
                /* Read next token (should be class name) */
                while(input_pos < input_len && isspace((unsigned char)input_buf[input_pos]))
                    input_pos++;
                i = 0;
                while(i < 63 && input_pos < input_len && (isalnum((unsigned char)input_buf[input_pos]) || input_buf[input_pos] == '_'))
                    buf[i++] = input_buf[input_pos++];
                buf[i] = '\0';
                if(i > 0){
                    /* Register as a known class */
                    Node *n = mk(NClass, buf, nil, nil, nil);
                    add_class(buf, n);
                }
            }
            continue;
        }
    }
    /* Reset for parse phase */
    input_pos = 0;
    in_prescan = 0;
    npush = 0;
}

/* Type checker: walks the AST and validates all member references */
/* Returns number of errors (0 = clean) */

static int
member_exists(Node *cnode, char *name)
{
    Node *m, *p;
    if(cnode == nil) return -1;
    for(m = cnode->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p && member_exists(p, name) >= 0) return 2;
        }
        if(m->name && strcmp(m->name, name) == 0) return m->type;
    }
    return -1;
}

static void
typecheck_expr(Node *e, int *errs)
{
    if(e == nil) return;
    
    switch(e->type){
    case NPropRead:
        /* Check: prop read, must not be a method */
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\n", e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: '%s' is a method, not a property\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NMsgSend:
        /* Check: method call, must be a method, not a property */
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            if(cn == nil || find_class(cn) == nil){
                fprint(2, "o9c: error: unknown type for '%s'\n", e->left->name);
                (*errs)++;
            } else {
                int mt = member_exists(find_class(cn), e->name);
                if(mt >= 0 && mt != NMethod){
                    fprint(2, "o9c: error: '%s' is a property, not a method\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NAssign:
        if(e->name != nil && e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name);
            if(cn && find_class(cn)){
                int mt = member_exists(find_class(cn), e->name);
                if(mt == NMethod){
                    fprint(2, "o9c: error: cannot assign to method '%s'\n", e->name);
                    (*errs)++;
                } else if(mt < 0){
                    fprint(2, "o9c: error: '%s' has no member '%s'\n", cn, e->name);
                    (*errs)++;
                }
            }
        }
        break;
    case NLocalVar:
        /* Check typename is a known type */
        if(e->typename && !is_primitive(e->typename) && find_class(e->typename) == nil){
            fprint(2, "o9c: error: unknown type '%s'\n", e->typename);
            (*errs)++;
        }
        break;
    }
}

static void
check_node(Node *n, int *errs)
{
    Node *c;
    if(n == nil) return;
    /* Walk the next chain at this level */
    for(c = n; c; c = c->next){
        typecheck_expr(c, errs);
        check_node(c->left, errs);
        check_node(c->right, errs);
    }
}

static int
typecheck(Node *root)
{
    int errors = 0;
    
    check_node(root, &errors);
    
    return errors;
}

int
main(int argc, char **argv)
{
    long n, total = 0, cap = 8192;
    
    input_buf = malloc(cap);
    if(input_buf == nil) sysfatal("malloc: input buffer");
    while((n = read(0, input_buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            input_buf = realloc(input_buf, cap);
            if(input_buf == nil) sysfatal("realloc: input buffer");
        }
    }
    input_len = total;
    
    prescan();
    
    if(yyparse() == 0){
        if(typecheck(ast_root) == 0)
            codegen(ast_root);
    } else {
        fprint(2, "o9c: parse failed\n");
    }
    exits(nil);
    return 0;
}
