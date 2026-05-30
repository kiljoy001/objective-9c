header = r"""%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

typedef struct Node Node;

enum {
    NClass, NProp, NState, NAtomic, NStream, NSecret, NCap, NInherit, NMethod, NDestructor,
    NIdent, NType, NChanSend, NChanRecv, NChanTry, NAssign, NReturn, NIntLit, NStringLit,
    NCharLit, NBoolLit, NAdd, NSub, NMul, NDiv, NMod, NEq, NNe, NLt, NLe, NGt, NGe,
    NAnd, NOr, NBitAnd, NBitOr, NBitXor, NLshift, NRshift, NNot, NBitNot, NNeg,
    NIf, NIfElse, NElse, NElseIf, NWhile, NLocalVar, NMsgSend, NPropRead, NFuncCall,
    NFor, NArrayGet, NArraySet, NInterface, NStruct, NImport
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

void add_class(char *name, Node *n) {
    ClassDef *c = malloc(sizeof(ClassDef));
    c->name = strdup(name);
    c->node = n;
    c->next = classes;
    classes = c;
}

Node* find_class(char *name) {
    ClassDef *c;
    for(c = classes; c; c = c->next) if(strcmp(c->name, name) == 0) return c->node;
    return nil;
}

Node* mk(int type, char *name, char *typename, Node *l, Node *r);
char* map_type(char *t);
char* get_sym_type(Node *c, char *name);
char* get_method_type(Node *c, char *name);
char* get_expr_type(Node *e);
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);
ulong o9_hash(char *str);

typedef struct TypeSym TypeSym;
struct TypeSym {
    char *name;
    char *typename;
    TypeSym *next;
};
TypeSym *type_syms;

void add_type_sym(char *name, char *typename) {
    TypeSym *s = malloc(sizeof(TypeSym));
    s->name = strdup(name);
    s->typename = strdup(typename);
    s->next = type_syms;
    type_syms = s;
}

char* get_type_sym(char *name) {
    TypeSym *s;
    for(s = type_syms; s; s = s->next) if(strcmp(s->name, name) == 0) return s->typename;
    return nil;
}

void clear_type_syms(void) {
    TypeSym *s, *next;
    for(s = type_syms; s; s = next){ next = s->next; free(s->name); free(s->typename); free(s); }
    type_syms = nil;
}

int is_subclass(char *sub, char *parent) {
    Node *c, *m;
    if(sub == nil || parent == nil) return 0;
    if(strcmp(sub, parent) == 0) return 1;
    c = find_class(sub); if(c == nil) return 0;
    for(m = c->left; m; m = m->next) if(m->type == NInherit) { if(strcmp(m->name, parent) == 0) return 1; if(is_subclass(m->name, parent)) return 1; }
    return 0;
}

int is_type_compatible(char *target, char *actual) {
    if(target == nil || actual == nil) return 0;
    if(strcmp(target, actual) == 0) return 1;
    if(strcmp(target, "vlong") == 0 && strcmp(actual, "int64") == 0) return 1;
    if(strcmp(target, "int64") == 0 && strcmp(actual, "vlong") == 0) return 1;
    if(is_subclass(actual, target)) return 1;
    return 0;
}

char* get_method_type(Node *c, char *name) {
    Node *m;
    if(c == nil || name == nil) return nil;
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod && m->name && strcmp(m->name, name) == 0) return m->typename;
        if(m->type == NInherit){ Node *p = find_class(m->name); if(p){ char *t = get_method_type(p, name); if(t) return t; } }
    }
    return nil;
}

char* get_sym_type(Node *c, char *name) {
    Node *m;
    if(c == nil || name == nil) return nil;
    for(m = c->left; m; m = m->next){
        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0) return map_type(m->typename);
        if(m->type == NInherit){ Node *p = find_class(m->name); if(p){ char *t = get_sym_type(p, name); if(t) return t; } }
    }
    return nil;
}

char* get_expr_type(Node *e) {
    if(e == nil) return "void";
    switch(e->type){
    case NIntLit: return "int64";
    case NStringLit: return "string";
    case NBoolLit: return "bool";
    case NIdent: { char *t = get_type_sym(e->name); if(t) return t; return "vlong"; }
    case NPropRead: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_sym_type(c, e->name); } return "vlong";
    case NMsgSend: if(e->left){ char *lt = get_expr_type(e->left); Node *c = find_class(lt); if(c) return get_method_type(c, e->name); } return "vlong";
    case NClass: return e->name;
    case NAdd: case NSub: case NMul: case NDiv: case NMod: return "int64";
    default: return "vlong";
    }
}

void  add_var_class(char *varname, char *classname);
int   is_primitive(char *t);

Node *ast_root;

char* map_type(char *t) {
    int len;
    Node *n;
    if(t == nil) return "void";
    if(strncmp(t, "Dict:", 5) == 0) return "O9Dict";
    if(strncmp(t, "List:", 5) == 0) return "O9Slice";
    len = strlen(t);
    if(len > 2 && strcmp(t + len - 2, "[]") == 0) return "char*";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "uint64") == 0) return "uvlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "uint32") == 0) return "ulong";
    if(strcmp(t, "bool") == 0) return "int";
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";
    n = find_class(t); if(n != nil && n->type == NStruct) return t;
    return t;
}

char* type_fmt(char *t) {
    if(strcmp(t, "vlong") == 0) return "%lld";
    if(strcmp(t, "char*") == 0) return "%s";
    return "%lld";
}

char* type_cast(char *t) {
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 || strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 || strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 || strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 || strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    if(find_class(t) && find_class(t)->type == NStruct) return "";
    return "vlong";
}

int is_primitive(char *t) {
    if(t == nil) return 1;
    if(strncmp(t, "Dict:", 5) == 0 || strncmp(t, "List:", 5) == 0) return 1;
    if(strcmp(t, "int64") == 0 || strcmp(t, "uint64") == 0 || strcmp(t, "bool") == 0 || strcmp(t, "string") == 0 || strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 || strcmp(t, "void") == 0 || strcmp(t, "chan") == 0) return 1;
    if(find_class(t) && find_class(t)->type == NStruct) return 1;
    return 0;
}
%}

%union { Node *node; char *name; }

%token <node> TIDENT TTYPE
%token <name> TINTLIT TSTRINGLIT TCHARLIT
%token TCLASS TINTERFACE TSTRUCT TIMPORT TFUNC TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TDICT TLIST TNIL
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

%type <node> program top_levels top_level class_decl interface_decl struct_decl import_decl member_list member var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename param_list param call_args call_arg func_top_level for_init for_cond for_step else_clause

%start program

%%

typename: TIDENT { $$ = $1; } | TTYPE { $$ = $1; } ;
program: /* empty */ { ast_root = nil; } | top_levels { ast_root = $1; } ;
top_levels: top_level { $$ = $1; } | top_levels top_level { Node *n = $1; while(n->next) n = n->next; n->next = $2; $$ = $1; } ;
top_level: class_decl | interface_decl | struct_decl | import_decl | func_top_level ;
import_decl: TIMPORT TSTRINGLIT ';' { $$ = mk(NImport, $2, nil, nil, nil); } ;
func_top_level: TFUNC TIDENT '(' ')' '{' stmt_list '}' { $$ = mk(NMethod, $2->name, "void", $6, nil); } ;
class_decl: TCLASS TIDENT '{' member_list '}' { $$ = mk(NClass, $2->name, nil, $4, nil); add_class($2->name, $$); } ;
interface_decl: TINTERFACE TIDENT '{' member_list '}' { $$ = mk(NInterface, $2->name, nil, $4, nil); add_class($2->name, $$); } ;
struct_decl: TSTRUCT TIDENT '{' member_list '}' { $$ = mk(NStruct, $2->name, nil, $4, nil); add_class($2->name, $$); } ;
member_list: /* empty */ { $$ = nil; } | member_list member { if($1 == nil) $$ = $2; else { Node *n = $1; while(n->next) n = n->next; n->next = $2; $$ = $1; } } ;
member: var_decl | func_decl | method_decl | state_decl | prop_decl | atomic_decl | stream_decl | secret_decl | cap_decl | inherit_decl | destructor_decl ;
state_decl: TSTATE typename TIDENT ';' { $$ = mk(NState, $3->name, $2->name, nil, nil); } ;
prop_decl: TPROP typename TIDENT ';' { $$ = mk(NProp, $3->name, $2->name, nil, nil); } ;
atomic_decl: TATOMIC typename TIDENT ';' { $$ = mk(NAtomic, $3->name, $2->name, nil, nil); } ;
stream_decl: TSTREAM TIDENT ';' { $$ = mk(NStream, $2->name, nil, nil, nil); } ;
secret_decl: TSECRET typename TIDENT ';' { $$ = mk(NSecret, $3->name, $2->name, nil, nil); } ;
cap_decl: TCAP typename TIDENT ';' { $$ = mk(NCap, $3->name, $2->name, nil, nil); } ;
method_decl: TMETHOD typename TIDENT '(' param_list ')' '{' stmt_list '}' { $$ = mk(NMethod, $3->name, $2->name, $8, $5); }
    | TMETHOD typename TIDENT '(' param_list ')' TARROW expr ';' { Node *body = mk(NReturn, nil, nil, $8, nil); $$ = mk(NMethod, $3->name, $2->name, body, $5); }
    | TMETHOD TIDENT '(' param_list ')' '{' stmt_list '}' { $$ = mk(NMethod, $2->name, "void", $7, $4); }
    | TMETHOD TIDENT '(' param_list ')' TARROW expr ';' { Node *body = mk(NReturn, nil, nil, $7, nil); $$ = mk(NMethod, $2->name, "void", body, $4); } ;
inherit_decl: TIDENT ';' { $$ = mk(NInherit, $1->name, nil, nil, nil); } ;
var_decl: typename TIDENT ';' { $$ = mk(NProp, $2->name, $1->name, nil, nil); }
    | TDICT '<' typename ',' typename '>' TIDENT ';' { char buf[128]; snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name); $$ = mk(NProp, $7->name, buf, nil, nil); }
    | TLIST '<' typename '>' TIDENT ';' { char buf[128]; snprint(buf, sizeof buf, "List:%s", $3->name); $$ = mk(NProp, $5->name, buf, nil, nil); }
    | typename '[' ']' TIDENT ';' { char buf[64]; snprint(buf, sizeof buf, "%s[]", $1->name); $$ = mk(NProp, $4->name, buf, nil, nil); } ;
func_decl: TFUNC '(' typename '*' TIDENT ')' TIDENT '(' param_list ')' typename '{' stmt_list '}' { $$ = mk(NMethod, $7->name, $11->name, $13, $9); } ;
param_list: /* empty */ { $$ = nil; } | param { $$ = $1; } | param_list ',' param { if($1 == nil) $$ = $3; else { Node *n = $1; while(n->next) n = n->next; n->next = $3; $$ = $1; } } ;
param: typename TIDENT { $$ = mk(NProp, $2->name, $1->name, nil, nil); } ;
destructor_decl: '~' TIDENT '(' ')' '{' stmt_list '}' { $$ = mk(NDestructor, $2->name, nil, $6, nil); } ;
stmt_list: /* empty */ { $$ = nil; } | stmt_list stmt { if($1 == nil) $$ = $2; else { Node *n = $1; while(n->next) n = n->next; n->next = $2; $$ = $1; } } ;
stmt: typename TIDENT ';' { $$ = mk(NLocalVar, $2->name, $1->name, nil, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | typename TIDENT TEQ expr ';' { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); if(find_class($1->name)) add_var_class($2->name, $1->name); }
    | TLIST '<' typename '>' TIDENT ';' { char buf[128]; snprint(buf, sizeof buf, "List:%s", $3->name); $$ = mk(NLocalVar, $5->name, buf, nil, nil); }
    | TDICT '<' typename ',' typename '>' TIDENT ';' { char buf[128]; snprint(buf, sizeof buf, "Dict:%s:%s", $3->name, $5->name); $$ = mk(NLocalVar, $7->name, buf, nil, nil); }
    | expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    | TPRINT '(' call_args ')' ';' { $$ = mk(NFuncCall, "print", nil, $3, nil); }
    | TIF '(' expr ')' '{' stmt_list '}' else_clause { $$ = mk(NIfElse, nil, nil, $3, $6); $$->next = $8; }
    | TWHILE '(' expr ')' '{' stmt_list '}' { $$ = mk(NWhile, nil, nil, $3, $6); }
    | TFOR '(' for_init TFORSEMI for_cond TFORSEMI for_step ')' '{' stmt_list '}' { Node *f = mk(NFor, nil, nil, $3, mk(0, nil, nil, $5, $7)); f->right->next = $10; $$ = f; } ;
for_init: /* empty */ { $$ = nil; } | expr | typename TIDENT TEQ expr { $$ = mk(NLocalVar, $2->name, $1->name, $4, nil); } ;
for_cond: /* empty */ { $$ = nil; } | expr ;
for_step: /* empty */ { $$ = nil; } | expr ;
else_clause: /* empty */ { $$ = nil; } | TELSE '{' stmt_list '}' { $$ = mk(NElse, nil, nil, $3, nil); }
    | TELIF '(' expr ')' '{' stmt_list '}' else_clause { $$ = mk(NElseIf, nil, nil, $3, $6); $$->next = $8; } ;
expr: TINTLIT { $$ = mk(NIntLit, $1, nil, nil, nil); } | TSTRINGLIT { $$ = mk(NStringLit, $1, nil, nil, nil); } | TTRUE { $$ = mk(NBoolLit, "1", nil, nil, nil); } | TFALSE { $$ = mk(NBoolLit, "0", nil, nil, nil); } | TNIL { $$ = mk(NBoolLit, "0", "vlong", nil, nil); } | TIDENT { $$ = $1; }
    | expr '.' TIDENT { $$ = mk(NPropRead, $3->name, nil, $1, nil); }
    | TIDENT '(' call_args ')' { $$ = mk(NFuncCall, $1->name, nil, $3, nil); }
    | expr '.' TIDENT '(' call_args ')' { $$ = mk(NMsgSend, $3->name, nil, $1, $5); }
    | expr '[' expr ']' { $$ = mk(NArrayGet, nil, nil, $1, $3); }
    | expr TADD expr { $$ = mk(NAdd, nil, nil, $1, $3); }
    | expr TSUB expr { $$ = mk(NSub, nil, nil, $1, $3); }
    | expr '*' expr { $$ = mk(NMul, nil, nil, $1, $3); }
    | expr '/' expr { $$ = mk(NDiv, nil, nil, $1, $3); }
    | expr '%' expr { $$ = mk(NMod, nil, nil, $1, $3); }
    | expr TEQEQ expr { $$ = mk(NEq, nil, nil, $1, $3); }
    | expr TNEQ expr { $$ = mk(NNe, nil, nil, $1, $3); }
    | expr '<' expr { $$ = mk(NLt, nil, nil, $1, $3); }
    | expr '>' expr { $$ = mk(NGt, nil, nil, $1, $3); }
    | expr TLE expr { $$ = mk(NLe, nil, nil, $1, $3); }
    | expr TGE expr { $$ = mk(NGe, nil, nil, $1, $3); }
    | expr TAND expr { $$ = mk(NAnd, nil, nil, $1, $3); }
    | expr TOR expr { $$ = mk(NOr, nil, nil, $1, $3); }
    | '!' expr { $$ = mk(NNot, nil, nil, $2, nil); }
    | TIDENT TEQ expr { $$ = mk(NAssign, nil, nil, $1, $3); }
    | expr '.' TIDENT TEQ expr { $$ = mk(NAssign, $3->name, nil, $1, $5); }
    | expr TCHANSEND expr { $$ = mk(NChanSend, nil, nil, $1, $3); }
    | expr TCHANRECV { $$ = mk(NChanRecv, nil, nil, $1, nil); }
    | TNEW typename '(' call_args ')' { Node *n = mk(NClass, $2->name, "same", nil, nil); n->left = $2; n->right = $4; $$ = n; }
    | '(' expr ')' { $$ = $2; } ;
call_args: /* empty */ { $$ = nil; } | call_arg | call_args ',' call_arg { if($1 == nil) $$ = $3; else { Node *n = $1; while(n->next) n = n->next; n->next = $3; $$ = $1; } } ;
call_arg: expr ;

%%

ulong o9_hash(char *str) { ulong h = 5381; int c; while ((c = *str++)) h = ((h << 5) + h) + c; return h & 0xFFFFFFFFul; }
Node* mk(int type, char *name, char *typename, Node *l, Node *r) { Node *n = malloc(sizeof(Node)); memset(n, 0, sizeof(Node)); n->type = type; if(name) n->name = strdup(name); if(typename) n->typename = strdup(typename); n->left = l; n->right = r; return n; }
void yyerror(char *s) { fprint(2, "o9c: error: %s\n", s); }
static char *input_buf; static int input_pos, input_len; static int for_paren_depth = -1; static int pushback[8], npush = 0;
static int lex_getc(void) { if(npush > 0) return pushback[--npush]; if(input_pos >= input_len) return Beof; return (unsigned char)input_buf[input_pos++]; }
static void lex_ungetc(int c) { if(npush < 8) pushback[npush++] = c; }
int yylex(void) {
    int c; while((c = lex_getc()) != Beof){
        if(isspace(c)) continue;
        if(for_paren_depth >= 0){ if(c == '(') { for_paren_depth++; return '('; } if(c == ')' && for_paren_depth > 0) { for_paren_depth--; return ')'; } if(c == ')' && for_paren_depth == 0) { for_paren_depth = -1; return ')'; } if(c == ';') return TFORSEMI; }
        if(c == '~') return '~';
        if(c == '='){ if((c = lex_getc()) == '=') return TEQEQ; if(c == '>') return TARROW; lex_ungetc(c); return TEQ; }
        if(c == '&'){ if((c = lex_getc()) == '&') return TAND; lex_ungetc(c); return '&'; }
        if(c == '|'){ if((c = lex_getc()) == '|') return TOR; lex_ungetc(c); return '|'; }
        if(c == '!'){ if((c = lex_getc()) == '=') return TNEQ; lex_ungetc(c); return '!'; }
        if(c == '<'){ if((c = lex_getc()) == '-') return TCHANRECV; if(c == '=') return TLE; if(c == '<') return TLSHIFT; lex_ungetc(c); return '<'; }
        if(c == '>'){ if((c = lex_getc()) == '=') return TGE; if(c == '>') return TRSHIFT; lex_ungetc(c); return '>'; }
        if(c == '"'){ char buf[1024]; int i = 0; while((c = lex_getc()) != Beof && c != '"' && i < 1023) { if(c == '\\\\'){ if((c = lex_getc()) == Beof) break; if(c == 'n') buf[i++] = '\n'; else if(c == 't') buf[i++] = '\t'; else buf[i++] = c; } else buf[i++] = c; } buf[i] = '\0'; yylval.name = strdup(buf); return TSTRINGLIT; }
        if(c == '-'){ if((c = lex_getc()) == '>') { if((c = lex_getc()) == '?') return TCHANTRY; lex_ungetc(c); return TCHANSEND; } lex_ungetc(c); return TSUB; }
        if(c == '/'){ if((c = lex_getc()) == '/'){ while((c = lex_getc()) != Beof && c != '\n'); continue; } if(c == '*'){ while((c = lex_getc()) != Beof){ if(c == '*'){ if((c = lex_getc()) == '/') break; lex_ungetc(c); } } continue; } lex_ungetc(c); return '/'; }
        if(c == '+') return TADD;
        if(isdigit(c)){ char buf[64]; int i = 0; buf[i++] = c; while(isdigit(c = lex_getc())) if(i < 63) buf[i++] = c; lex_ungetc(c); buf[i] = '\0'; yylval.name = strdup(buf); return TINTLIT; }
        if(isalpha(c) || c == '_'){
            char buf[64]; int i = 0; buf[i++] = c; while(isalnum(c = lex_getc()) || c == '_') if(i < 63) buf[i++] = c; lex_ungetc(c); buf[i] = '\0'; yylval.node = mk(NIdent, buf, nil, nil, nil);
            if(strcmp(buf, "class") == 0) return TCLASS; if(strcmp(buf, "struct") == 0) return TSTRUCT; if(strcmp(buf, "interface") == 0) return TINTERFACE; if(strcmp(buf, "import") == 0) return TIMPORT; if(strcmp(buf, "func") == 0) return TFUNC; if(strcmp(buf, "new") == 0) return TNEW; if(strcmp(buf, "near") == 0) return TNEAR; if(strcmp(buf, "far") == 0) return TFAR; if(strcmp(buf, "dict") == 0) return TDICT; if(strcmp(buf, "List") == 0) return TLIST; if(strcmp(buf, "method") == 0) return TMETHOD; if(strcmp(buf, "state") == 0) return TSTATE; if(strcmp(buf, "prop") == 0) return TPROP; if(strcmp(buf, "atomic") == 0) return TATOMIC; if(strcmp(buf, "chan") == 0) return TCHAN; if(strcmp(buf, "return") == 0) return TRETURN; if(strcmp(buf, "if") == 0) return TIF; if(strcmp(buf, "else") == 0){ int nc = lex_getc(); while(nc == ' ' || nc == '\t') nc = lex_getc(); if(nc == 'i'){ int nc2 = lex_getc(); if(nc2 == 'f') return TELIF; lex_ungetc(nc2); } lex_ungetc(nc); return TELSE; } if(strcmp(buf, "while") == 0) return TWHILE; if(strcmp(buf, "for") == 0){ for_paren_depth = 0; return TFOR; } if(strcmp(buf, "true") == 0) return TTRUE; if(strcmp(buf, "false") == 0) return TFALSE; if(strcmp(buf, "nil") == 0) return TNIL; if(strcmp(buf, "print") == 0) return TPRINT; if(strcmp(buf, "int64") == 0 || strcmp(buf, "string") == 0 || strcmp(buf, "bool") == 0 || strcmp(buf, "void") == 0) return TTYPE; if(find_class(buf)) return TTYPE; return TIDENT;
        }
        if(strchr("{}();.,:<>[]!@#$%^&*|/-+=~", c)) return c;
    } return Beof;
}
void mark_locals(Node *n); char *local_vars[128]; int num_locals = 0, in_class_context = 0;
void mark_locals(Node *n) { Node *c; if(n == nil) return; for(c = n; c; c = c->next){ if(c->type == NLocalVar) if(num_locals < 128) local_vars[num_locals++] = c->name; mark_locals(c->left); mark_locals(c->right); } }
int is_local(char *name) { int i; for(i = 0; i < num_locals; i++) if(strcmp(local_vars[i], name) == 0) return 1; return 0; }
typedef struct VarClass VarClass; struct VarClass { char *varname, *classname; VarClass *next; }; VarClass *var_classes;
void add_var_class(char *varname, char *classname) { VarClass *v = malloc(sizeof(VarClass)); v->varname = strdup(varname); v->classname = strdup(classname); v->next = var_classes; var_classes = v; }
char* get_var_class(char *varname) { VarClass *v; for(v = var_classes; v; v = v->next) if(strcmp(v->varname, varname) == 0) return v->classname; return nil; }
void gen_expr(Node *e);
void gen_expr(Node *e) {
    if(e == nil) return;
    switch(e->type){
    case NIntLit: case NStringLit: case NBoolLit: print("%s", e->name); break;
    case NIdent: if(is_local(e->name) || !in_class_context) print("%s", e->name); else print("self->%s", e->name); break;
    case NMsgSend: {
        char *lt = get_expr_type(e->left);
        if(strncmp(lt, "List:", 5) == 0){
            if(strcmp(e->name, "Add") == 0){ char *et = lt + 5; print("({ %s __v = ", map_type(et)); gen_expr(e->right); print("; o9_slice_append(&"); gen_expr(e->left); print(", &__v); (vlong)0; })"); return; }
            if(strcmp(e->name, "Length") == 0){ print("(vlong)("); gen_expr(e->left); print(".len)"); return; }
        }
        if(strncmp(lt, "Dict:", 5) == 0){ if(strcmp(e->name, "Has") == 0){ print("o9_dict_has(&"); gen_expr(e->left); print(", "); gen_expr(e->right); print(")"); return; } }
        print("(vlong)obj9_msgSend(&"); gen_expr(e->left); print(", \"%s\", 0x%lux, nil)", e->name, o9_hash(e->name)); break;
    }
    case NPropRead: {
        if(e->left && e->left->type == NIdent && e->left->name){
            char *cn = get_var_class(e->left->name); Node *cnode = find_class(cn);
            if(cnode != nil){
                if(cnode->type == NClass || cnode->type == NInterface){ print("((%s_Internal*)((%s_Client*)&", cn, cn); gen_expr(e->left); print(")->shm_base)->%s", e->name); break; }
                else if(cnode->type == NStruct){ gen_expr(e->left); print(".%s", e->name); break; }
            }
        }
        gen_expr(e->left); print(".%s", e->name); break;
    }
    case NArrayGet: {
        char *lt = get_expr_type(e->left);
        if(strncmp(lt, "Dict:", 5) == 0){ char *last = strrchr(lt, ':'); char *vt = last ? last + 1 : "vlong"; print("((%s)o9_dict_get(&", map_type(vt)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))"); }
        else if(strncmp(lt, "List:", 5) == 0){ char *et = lt + 5; print("(*(%s*)o9_slice_get(&", map_type(et)); gen_expr(e->left); print(", "); gen_expr(e->right); print("))"); }
        else { print("o9_array_get("); gen_expr(e->left); print(", "); gen_expr(e->right); print(")"); } break;
    }
    case NFuncCall: if(strcmp(e->name, "print") == 0){ print("fprint(1, "); Node *a = e->left; if(a && a->type == NStringLit){ print("\"%s\"", a->name); for(a = a->next; a; a = a->next){ print(", "); gen_expr(a); } } print(")"); } break;
    case NAdd: print("("); gen_expr(e->left); print(" + "); gen_expr(e->right); print(")"); break;
    case NSub: print("("); gen_expr(e->left); print(" - "); gen_expr(e->right); print(")"); break;
    case NEq: print("("); gen_expr(e->left); print(" == "); gen_expr(e->right); print(")"); break;
    case NAssign: {
        if(e->left && e->left->type == NArrayGet){
            char *lt = get_expr_type(e->left->left);
            if(strncmp(lt, "Dict:", 5) == 0){ print("o9_dict_set(&"); gen_expr(e->left->left); print(", "); gen_expr(e->left->right); print(", (void*)("); gen_expr(e->right); print("))"); return; }
            else if(strncmp(lt, "List:", 5) == 0){ char *et = lt + 5; print("({ %s __v = ", map_type(et)); gen_expr(e->right); print("; o9_slice_set(&"); gen_expr(e->left->left); print(", "); gen_expr(e->left->right); print(", &__v); })"); return; }
        }
        gen_expr(e->left); print(" = "); gen_expr(e->right); break;
    }
    }
}
void gen_stmt(Node *c, Node *s);
void gen_stmt(Node *c, Node *s) {
    if(s == nil) return; Node *n;
    switch(s->type){
    case NLocalVar: if(is_primitive(s->typename)){ print("\t%s %s;\n", map_type(s->typename), s->name);
        if(strncmp(s->typename, "List:", 5) == 0) print("\to9_slice_init(&%s, sizeof(%s));\n", s->name, map_type(s->typename+5));
        else if(strncmp(s->typename, "Dict:", 5) == 0) print("\to9_dict_init(&%s);\n", s->name);
        else if(s->left){ print("\t%s = ", s->name); gen_expr(s->left); print(";\n"); }
        } else {
            char *cname = find_class(s->typename) ? s->typename : nil;
            if(cname){ print("\t%s_Client %s; memset(&%s, 0, sizeof(%s_Client));\n", cname, s->name, s->name, cname); }
            else print("\t%s %s;\n", map_type(s->typename), s->name);
        } break;
    case NReturn: print("\treturn "); gen_expr(s->left); print(";\n"); break;
    default: print("\t"); gen_expr(s); print(";\n"); break;
    }
}
void gen_struct_def(Node *c) { Node *m; print("typedef struct %s %s;\nstruct %s {\n", c->name, c->name, c->name); for(m = c->left; m; m = m->next) if(m->type == NProp) print("\t%s %s;\n", map_type(m->typename), m->name); print("};\n\n"); }
void gen_class_header(Node *c) { print("typedef struct %s_Client { int fd; void *shm_base; void *table; long ref; void *dispatch_chan; int distance; } %s_Client;\n", c->name, c->name); }
void codegen(Node *root) {
    Node *n; print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <o9.h>\n\n");
    for(n = root; n; n = n->next) if(n->type == NStruct) gen_struct_def(n);
    for(n = root; n; n = n->next) if(n->type == NClass) gen_class_header(n);
    for(n = root; n; n = n->next) if(n->type == NMethod && strcmp(n->name, "main") == 0) {
        print("void threadmain(int argc, char **argv) {\n\tUSED(argc); USED(argv);\n");
        num_locals = 0; mark_locals(n->left); for(n = n->left; n; n = n->next) gen_stmt(nil, n); print("\tthreadexitsall(nil);\n}\n");
    }
}
static void scan_buffer(char *buf, long len) {
    long pos = 0; int c, i; char name[64];
    while(pos < len){
        c = (unsigned char)buf[pos++]; if(isspace(c)) continue;
        if(isalpha(c) || c == '_'){
            i = 0; name[i++] = c; while(i < 63 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_')) name[i++] = buf[pos++]; name[i] = '\0';
            if(strcmp(name, "class") == 0 || strcmp(name, "struct") == 0){
                while(pos < len && isspace((unsigned char)buf[pos])) pos++; i = 0; while(i < 63 && pos < len && (isalnum((unsigned char)buf[pos]) || buf[pos] == '_')) name[i++] = buf[pos++]; name[i] = '\0';
                if(i > 0) add_class(name, mk(NClass, name, nil, nil, nil));
            }
        }
    }
}
static void prescan(void) { scan_buffer(input_buf, input_len); }
Node *cur_meth; char *tc_class;
static void typecheck_expr(Node *e, int *errs) {
    if(e == nil) return;
    switch(e->type){
    case NLocalVar: if(e->name) add_type_sym(e->name, e->typename); break;
    case NAssign: { char *lt = get_expr_type(e->left); char *rt = get_expr_type(e->right); if(!is_type_compatible(lt, rt)){ fprint(2, "o9c: error: incompatible types in assignment: expected %s, got %s\n", lt, rt); (*errs)++; } } break;
    }
}
static void check_node(Node *n, int *errs) { Node *c; if(n == nil) return; for(c = n; c; c = c->next){ typecheck_expr(c, errs); check_node(c->left, errs); check_node(c->right, errs); } }
static int typecheck(Node *root) { int errors = 0; clear_type_syms(); check_node(root, &errors); return errors; }
int main(int argc, char **argv) {
    input_buf = malloc(8192); input_len = read(0, input_buf, 8192);
    prescan(); if(yyparse() == 0) if(typecheck(ast_root) == 0) codegen(ast_root); return 0;
}
"""

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(header)
