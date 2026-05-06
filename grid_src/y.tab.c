
#line	2	"/usr/scott/o9build/o9.y"
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

#line	49	"/usr/scott/o9build/o9.y"
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
#define	TCLASS	57348
#define	TFUNC	57349
#define	TNEW	57350
#define	TRETURN	57351
#define	TCHAN	57352
#define	TEQ	57353
#define	TADD	57354
#define	TSUB	57355
#define	TCHANSEND	57356
#define	TCHANRECV	57357
#define YYEOFCODE 1
#define YYERRCODE 2

#line	153	"/usr/scott/o9build/o9.y"


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
short	yyexca[] =
{-1, 1,
	1, -1,
	-2, 0,
};
#define	YYNPROD	23
#define	YYPRIVATE 57344
#define	YYLAST	45
short	yyact[] =
{
  33,  27,  24,  22,  35,  26,  19,  18,  40,  34,
  15,  36,  20,  16,  43,  29,  39,  31,   8,  38,
   5,  17,  44,  10,  41,  42,  35,  28,  25,  23,
  21,   7,  32,   3,  30,  37,   6,  14,  13,  12,
  11,   9,   4,   2,   1
};
short	yypact[] =
{
  14,-1000,  14,-1000,-1000,  27,-1000,   2,-1000,   6,
-1000,-1000,-1000,-1000,-1000,   3, -13,-1000,  -6,  26,
-1000, -17,  25, -19,  24, -14, -20,  23,  -1,-1000,
   0,-1000,-1000,  -7,  22,   5,-1000, -10,  20,  10,
-1000,-1000,  18,-1000,-1000
};
short	yypgo[] =
{
   0,  44,  43,  33,  42,  41,  40,  39,  38,  37,
  34,  32,   0
};
short	yyr1[] =
{
   0,   1,   1,   2,   2,   3,   4,   5,   5,   6,
   6,   6,   9,   7,   8,  10,  10,  11,  11,  12,
  12,  12,  12
};
short	yyr2[] =
{
   0,   0,   1,   1,   2,   1,   5,   0,   2,   1,
   1,   1,   2,   3,  13,   0,   2,   2,   3,   3,
   4,   3,   1
};
short	yychk[] =
{
-1000,  -1,  -2,  -3,  -4,   6,  -3,   4,  16,  -5,
  17,  -6,  -7,  -8,  -9,   4,   7,  18,   4,  19,
  18,   4,  20,   4,  21,   4,  19,  21,   4,  16,
 -10,  17, -11, -12,   9,   4,  18, -12,  14,  11,
  18,   4,  15,   4,   4
};
short	yydef[] =
{
   1,  -2,   2,   3,   5,   0,   4,   0,   7,   0,
   6,   8,   9,  10,  11,   0,   0,  12,   0,   0,
  13,   0,   0,   0,   0,   0,   0,   0,   0,  15,
   0,  14,  16,   0,   0,  22,  17,   0,   0,   0,
  18,  19,   0,  21,  20
};
short	yytok1[] =
{
   1,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
  19,  21,  20,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  18,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,  16,   0,  17
};
short	yytok2[] =
{
   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,
  12,  13,  14,  15
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
#line	63	"/usr/scott/o9build/o9.y"
{ ast_root = nil; } break;
case 2:
#line	64	"/usr/scott/o9build/o9.y"
{ ast_root = yypt[-0].yyv.node; } break;
case 3:
#line	68	"/usr/scott/o9build/o9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
case 4:
#line	69	"/usr/scott/o9build/o9.y"
{ 
        Node *n = yypt[-1].yyv.node;
        while(n->next) n = n->next;
        n->next = yypt[-0].yyv.node;
        yyval.node = yypt[-1].yyv.node;
    } break;
case 6:
#line	83	"/usr/scott/o9build/o9.y"
{
        yyval.node = mk(NClass, yypt[-3].yyv.node->name, nil, yypt[-1].yyv.node, nil);
    } break;
case 7:
#line	89	"/usr/scott/o9build/o9.y"
{ yyval.node = nil; } break;
case 8:
#line	90	"/usr/scott/o9build/o9.y"
{ 
        if(yypt[-1].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-1].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-1].yyv.node;
        }
    } break;
case 12:
#line	109	"/usr/scott/o9build/o9.y"
{
        yyval.node = mk(NInherit, yypt[-1].yyv.node->name, nil, nil, nil);
    } break;
case 13:
#line	116	"/usr/scott/o9build/o9.y"
{ 
        yyval.node = mk(NProp, yypt[-2].yyv.node->name, yypt[-1].yyv.node->name, nil, nil);
    } break;
case 14:
#line	123	"/usr/scott/o9build/o9.y"
{
        yyval.node = mk(NMethod, yypt[-8].yyv.node->name, yypt[-3].yyv.node->name, yypt[-1].yyv.node, nil);
    } break;
case 15:
#line	129	"/usr/scott/o9build/o9.y"
{ yyval.node = nil; } break;
case 16:
#line	130	"/usr/scott/o9build/o9.y"
{
        if(yypt[-1].yyv.node == nil) yyval.node = yypt[-0].yyv.node;
        else {
            Node *n = yypt[-1].yyv.node;
            while(n->next) n = n->next;
            n->next = yypt[-0].yyv.node;
            yyval.node = yypt[-1].yyv.node;
        }
    } break;
case 17:
#line	142	"/usr/scott/o9build/o9.y"
{ yyval.node = yypt[-1].yyv.node; } break;
case 18:
#line	143	"/usr/scott/o9build/o9.y"
{ yyval.node = mk(NReturn, nil, nil, yypt[-1].yyv.node, nil); } break;
case 19:
#line	147	"/usr/scott/o9build/o9.y"
{ yyval.node = mk(NChanSend, yypt[-2].yyv.node->name, nil, yypt[-0].yyv.node, nil); } break;
case 20:
#line	148	"/usr/scott/o9build/o9.y"
{ yyval.node = mk(NChanRecv, yypt[-3].yyv.node->name, nil, yypt[-0].yyv.node, nil); } break;
case 21:
#line	149	"/usr/scott/o9build/o9.y"
{ yyval.node = mk(NAssign, yypt[-2].yyv.node->name, nil, yypt[-0].yyv.node, nil); } break;
case 22:
#line	150	"/usr/scott/o9build/o9.y"
{ yyval.node = yypt[-0].yyv.node; } break;
	}
	goto yystack;  /* stack new state and value */
}
