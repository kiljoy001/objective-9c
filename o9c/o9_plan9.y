%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

/*
 * o9.y -- small yacc-based Obj9/O9 transpiler.
 * The generated output intentionally targets native Plan 9 C:
 *   - no C99 designated initializers
 *   - no // comments
 *   - no mixed declarations after statements
 *   - no stddef.h
 *   - Plan 9 typedef/struct style
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
	fprint(2, "o9c: error: %s\n", s);
}

static Biobuf *bin;

int
yylex(void)
{
	int c;
	int d;
	int i;
	char buf[128];

	while((c = Bgetc(bin)) != Beof){
		if(isspace(c))
			continue;
		if(c == '<'){
			d = Bgetc(bin);
			if(d == '-')
				return TCHANRECV;
			Bungetc(bin);
			return '<';
		}
		if(c == '-'){
			d = Bgetc(bin);
			if(d == '>')
				return TCHANSEND;
			Bungetc(bin);
			return '-';
		}
		if(c == '=')
			return TEQ;
		if(isalpha(c) || c == '_'){
			i = 0;
			buf[i++] = c;
			while((c = Bgetc(bin)) != Beof && (isalnum(c) || c == '_')){
				if(i < sizeof(buf)-1)
					buf[i++] = c;
			}
			if(c != Beof)
				Bungetc(bin);
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

void
gen_stmt(Node *s)
{
	if(s == nil)
		return;
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

	print("/* Generated client header for class %s */\n", c->name);
	print("#ifndef _O9_GEN_%s_H_\n#define _O9_GEN_%s_H_\n\n", c->name, c->name);
	print("typedef struct %s_AsmTable %s_AsmTable;\n", c->name, c->name);
	print("typedef struct %s_Client %s_Client;\n\n", c->name, c->name);
	print("struct %s_AsmTable {\n\tvoid *data_cache[64];\n\tvoid (*ctrl_cache[64])(void*);\n};\n\n", c->name);
	print("struct %s_Client {\n\tint fd;\n\t%s_AsmTable *table;\n\tlong ref;\t/* ARC counter */\n", c->name, c->name);
	for(m = c->left; m != nil; m = m->next){
		if(m->type == NInherit)
			print("\t%s_Client %s;\n", m->name, m->name);
	}
	print("};\n\n#endif\n\n");
}

void
gen_class_server(Node *c)
{
	Node *m;
	Node *s;

	print("/* Generated 9P fileserver for class %s with ARC ledger */\n", c->name);
	print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n\n");

	print("typedef struct ArcEntry ArcEntry;\n");
	print("typedef struct ArcLedger ArcLedger;\n");
	print("typedef struct %s_State %s_State;\n\n", c->name, c->name);

	print("struct ArcEntry {\n\tulong id;\n\tlong count;\n};\n\n");
	print("struct ArcLedger {\n\tArcEntry entries[64];\n};\n\n");

	print("struct %s_State {\n\tArcLedger ledger;\n", c->name);
	for(m = c->left; m != nil; m = m->next){
		if(m->type == NInherit)
			print("\t%s_State %s;\n", m->name, m->name);
		if(m->type == NProp)
			print("\t%s %s;\n", map_type(m->typename), m->name);
	}
	print("};\n\n");

	for(m = c->left; m != nil; m = m->next){
		if(m->type == NMethod){
			print("static %s\no9_impl_%s_%s(%s_State *self)\n{\n", map_type(m->typename), c->name, m->name, c->name);
			for(s = m->left; s != nil; s = s->next)
				gen_stmt(s);
			print("}\n\n");
		}
	}

	print("static void\nfsread(Req *r)\n{\n\tchar buf[1024];\n\t%s_State *s;\n\tchar *p;\n\tint i;\n\n", c->name);
	print("\ts = r->srv->aux;\n");
	print("\tif(strcmp(r->fid->file->dir.name, \"ledger\") == 0){\n");
	print("\t\tp = buf;\n");
	print("\t\tp += snprint(p, sizeof buf - (p-buf), \"ID\\t\\tREFS\\n\");\n");
	print("\t\tfor(i = 0; i < 64; i++){\n");
	print("\t\t\tif(s->ledger.entries[i].id != 0)\n");
	print("\t\t\t\tp += snprint(p, sizeof buf - (p-buf), \"%%lud\\t%%ld\\n\", s->ledger.entries[i].id, s->ledger.entries[i].count);\n");
	print("\t\t}\n\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");

	print("\tif(strcmp(r->fid->file->dir.name, \"cache\") == 0){\n");
	print("\t\tp = buf;\n");
	print("\t\tp += snprint(p, sizeof buf - (p-buf), \"seg:shared\\n\");\n");
	print("\t\tp += snprint(p, sizeof buf - (p-buf), \"ledger:%%ld\\n\", (long)(&((%s_State*)0)->ledger));\n", c->name);
	for(m = c->left; m != nil; m = m->next){
		if(m->type == NProp)
			print("\t\tp += snprint(p, sizeof buf - (p-buf), \"d:%%ld:%%ld\\n\", 0L, (long)(&((%s_State*)0)->%s));\n", c->name, m->name);
		if(m->type == NMethod)
			print("\t\tp += snprint(p, sizeof buf - (p-buf), \"c:%%ld:%%p\\n\", 0L, o9_impl_%s_%s);\n", c->name, m->name);
	}
	print("\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n\trespond(r, \"not found\");\n}\n\n");

	print("Srv o9srv_%s;\n\n", c->name);

	print("void\nthreadmain(int argc, char **argv)\n{\n\t%s_State *s;\n\n", c->name);
	print("\tUSED(argc);\n\tUSED(argv);\n");
	print("\ts = segattach(0, \"shared\", nil, sizeof(%s_State));\n", c->name);
	print("\tif(s == (void*)-1)\n\t\tsysfatal(\"segattach failed: %%r\");\n");
	print("\tmemset(s, 0, sizeof(%s_State));\n", c->name);
	print("\to9srv_%s.read = fsread;\n", c->name);
	print("\to9srv_%s.aux = s;\n", c->name);
	print("\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n", c->name, c->name);
	print("\tthreadexitsall(nil);\n}\n");
}

void
codegen(Node *root)
{
	Node *n;

	for(n = root; n != nil; n = n->next){
		if(n->type == NClass){
			gen_class_header(n);
			gen_class_server(n);
		}
	}
}

int
main(int argc, char **argv)
{
	USED(argc);
	USED(argv);
	bin = Bfdopen(0, OREAD);
	if(bin == nil)
		sysfatal("Bfdopen: %r");
	if(yyparse() == 0)
		codegen(ast_root);
	exits(nil);
	return 0;
}
