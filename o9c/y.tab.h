
typedef union  {
    Node *node;
    char *name;
}	YYSTYPE;
extern	YYSTYPE	yylval;
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
