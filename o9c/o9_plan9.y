%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

/*
 * o9_plan9.y -- small yacc-based o9 transpiler.
 * The generated output targets native Plan 9 C:
 *   - no C99 designated initializers
 *   - no // comments
 *   - no mixed declarations after statements
 *   - no stddef.h
 *   - Plan 9 typedef/struct style
 *
 * Generates a 9P fileserver with:
 *   - /<prop> for each property (read/write)
 *   - /cache for asm dispatch table handshake
 *   - /ledger for ARC reference counts
 *   - Shared memory (segattach) for direct client access
 */

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
void yyerror(char *s);
int yylex(void);
int yyparse(void);
void codegen(Node *root);

Node *ast_root;
static Biobuf bout;

char*
map_type(char *t)
{
	if(t == nil)
		return "void";
	if(strcmp(t, "int64") == 0)
		return "vlong";
	if(strcmp(t, "int32") == 0)
		return "long";
	if(strcmp(t, "string") == 0)
		return "char*";
	if(strcmp(t, "chan") == 0)
		return "Channel*";
	return t;
}

static Biobuf *bin;
static int o9_lineno = 1;
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
		Node *n;

		n = $1;
		while(n->next != nil)
			n = n->next;
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
		Node *n;

		if($1 == nil)
			$$ = $2;
		else {
			n = $1;
			while(n->next != nil)
				n = n->next;
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
		/* source form: <type> <name>; */
		$$ = mk(NProp, $2->name, $1->name, nil, nil);
	}
	;

func_decl:
	TFUNC '(' TIDENT '*' TIDENT ')' TIDENT '(' ')' TIDENT '{' stmt_list '}'
	{
		/* func(<Class> *<self>) <name>() <rettype> { ... } */
		$$ = mk(NMethod, $7->name, $10->name, $12, nil);
	}
	;

stmt_list:
	/* empty */ { $$ = nil; }
	| stmt_list stmt {
		Node *n;

		if($1 == nil)
			$$ = $2;
		else {
			n = $1;
			while(n->next != nil)
				n = n->next;
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
	Node *n;

	n = malloc(sizeof(Node));
	if(n == nil)
		sysfatal("malloc: %r");
	memset(n, 0, sizeof(Node));
	n->type = type;
	if(name != nil)
		n->name = strdup(name);
	if(typename != nil)
		n->typename = strdup(typename);
	n->left = l;
	n->right = r;
	return n;
}

void
yyerror(char *s)
{
	fprint(2, "o9c: %d: error: %s\n", o9_lineno, s);
}

/* --- Hand-written lexer (no lex needed) --- */

static int
o9_nextc(void)
{
	int c;

	c = Bgetc(bin);
	if(c == '\n')
		o9_lineno++;
	return c;
}

static void
o9_ungetc(int c)
{
	if(c == '\n')
		o9_lineno--;
	Bungetc(bin);
}

int
yylex(void)
{
	int c, d, i;
	char buf[128];

	while((c = o9_nextc()) != Beof){
		if(isspace(c))
			continue;
		if(c == '<'){
			d = o9_nextc();
			if(d == '-')
				return TCHANRECV;
			o9_ungetc(d);
			return '<';
		}
		if(c == '-'){
			d = o9_nextc();
			if(d == '>')
				return TCHANSEND;
			o9_ungetc(d);
			return '-';
		}
		if(c == '=')
			return TEQ;
		if(isalpha(c) || c == '_'){
			i = 0;
			buf[i++] = c;
			while((c = o9_nextc()) != Beof && (isalnum(c) || c == '_')){
				if(i < sizeof(buf)-1)
					buf[i++] = c;
			}
			if(c != Beof)
				o9_ungetc(c);
			buf[i] = 0;

			yylval.node = mk(NIdent, buf, buf, nil, nil);

			if(strcmp(buf, "class") == 0)
				return TCLASS;
			if(strcmp(buf, "func") == 0)
				return TFUNC;
			if(strcmp(buf, "chan") == 0)
				return TCHAN;
			if(strcmp(buf, "return") == 0)
				return TRETURN;
			return TIDENT;
		}
		return c;
	}
	return 0;
}

/* --- Code Generation --- */

void
gen_stmt(Node *s)
{
	if(s == nil)
		return;
	switch(s->type){
	case NChanSend:
		Bprint(&bout, "\tsendp(%s, (void*)%s);\n", s->name, s->left->name);
		break;
	case NChanRecv:
		Bprint(&bout, "\t%s = recvp(%s);\n", s->name, s->left->name);
		break;
	case NAssign:
		Bprint(&bout, "\t%s = %s;\n", s->name, s->left->name);
		break;
	case NReturn:
		Bprint(&bout, "\treturn %s;\n", s->left->name);
		break;
	}
}

void
gen_includes(void)
{
	Bprint(&bout, "#include <u.h>\n");
	Bprint(&bout, "#include <libc.h>\n");
	Bprint(&bout, "#include <thread.h>\n");
	Bprint(&bout, "#include <fcall.h>\n");
	Bprint(&bout, "#include <9p.h>\n\n");
}

void
gen_state_struct(Node *c)
{
	Node *m;

	if(c == nil || c->name == nil) return;
	Bprint(&bout, "typedef struct %s_State %s_State;\n", c->name, c->name);
	Bprint(&bout, "struct %s_State {\n", c->name);
	for(m = c->left; m; m = m->next){
		if(m->type == NProp && m->typename)
			Bprint(&bout, "\t%s %s;\n", map_type(m->typename), m->name);
	}
	Bprint(&bout, "};\n\n");
}

void
gen_read_handler(Node *c)
{
	Node *m;

	if(c == nil || c->name == nil) return;
	Bprint(&bout, "static void\nfsread(Req *r)\n{\n\tchar buf[512];\n\t%s_State *s = r->srv->aux;\n", c->name);
	for(m = c->left; m; m = m->next){
		if(m->type == NProp && m->name){
			Bprint(&bout, "\tif(strcmp(r->fid->file->dir.name, \"%s\") == 0){\n", m->name);
			Bprint(&bout, "\t\tsnprint(buf, sizeof buf, \"%%lld\\n\", (vlong)s->%s);\n", m->name);
			Bprint(&bout, "\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
		}
	}
	Bprint(&bout, "\tif(strcmp(r->fid->file->dir.name, \"cache\") == 0){\n");
	Bprint(&bout, "\t\tchar *p = buf;\n");
	for(m = c->left; m; m = m->next){
		if(m->type == NProp && m->name)
			Bprint(&bout, "\t\tp += snprint(p, sizeof buf - (p-buf), \"d:0:%s\\n\");\n", m->name);
	}
	Bprint(&bout, "\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
	Bprint(&bout, "\trespond(r, \"not found\");\n}\n\n");
}

void
gen_write_handler(Node *c)
{
	Node *m;

	if(c == nil || c->name == nil) return;
	Bprint(&bout, "static void\nfswrite(Req *r)\n{\n\t%s_State *s = r->srv->aux;\n", c->name);
	for(m = c->left; m; m = m->next){
		if(m->type == NProp && m->name){
			Bprint(&bout, "\tif(strcmp(r->fid->file->dir.name, \"%s\") == 0){\n", m->name);
			Bprint(&bout, "\t\ts->%s = strtoll(r->ifcall.data, nil, 0);\n", m->name);
			Bprint(&bout, "\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
		}
	}
	Bprint(&bout, "\trespond(r, \"not found\");\n}\n\n");
}

void
gen_main_entry(Node *c)
{
	Node *m;

	if(c == nil || c->name == nil) return;
	Bprint(&bout, "Srv o9srv_%s;\n\n", c->name);
	Bprint(&bout, "void\nthreadmain(int argc, char **argv)\n{\n");
	Bprint(&bout, "\tUSED(argc); USED(argv);\n");
	Bprint(&bout, "\t%s_State *s;\n\tTree *t;\n", c->name);
	Bprint(&bout, "\ts = emalloc9p(sizeof(%s_State));\n", c->name);
	Bprint(&bout, "\tmemset(s, 0, sizeof(%s_State));\n", c->name);
	Bprint(&bout, "\to9srv_%s.aux = s;\n", c->name);
	Bprint(&bout, "\to9srv_%s.read = fsread;\n", c->name);
	Bprint(&bout, "\to9srv_%s.write = fswrite;\n", c->name);
	Bprint(&bout, "\tt = alloctree(nil, nil, 0555, nil);\n");
	Bprint(&bout, "\to9srv_%s.tree = t;\n", c->name);
	for(m = c->left; m; m = m->next){
		if(m->type == NProp && m->name)
			Bprint(&bout, "\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
	}
	Bprint(&bout, "\tcreatefile(t->root, \"cache\", nil, 0444, nil);\n");
	Bprint(&bout, "\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n", c->name, c->name);
	Bprint(&bout, "\tthreadexitsall(nil);\n}\n");
}

void
codegen(Node *root)
{
	Node *n;

	gen_includes();
	for(n = root; n; n = n->next){
		if(n->type == NClass){
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
	USED(argc);
	USED(argv);
	Binit(&bout, 1, OWRITE);
	bin = Bfdopen(0, OREAD);
	if(bin == nil)
		sysfatal("Bfdopen: %r");
	if(yyparse() == 0)
		codegen(ast_root);
	Bterm(&bout);
	exits(nil);
	return 0;
}
