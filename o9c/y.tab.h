
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
#define	TSTATE	57360
#define	TPROP	57361
#define	TATOMIC	57362
#define	TSTREAM	57363
#define	TSECRET	57364
#define	TCAP	57365
#define	TTRUE	57366
#define	TFALSE	57367
#define	TEQ	57368
#define	TADD	57369
#define	TSUB	57370
#define	TCHANSEND	57371
#define	TCHANRECV	57372
#define	TCHANTRY	57373
#define	TEQEQ	57374
#define	TNEQ	57375
#define	TLE	57376
#define	TGE	57377
#define	TAND	57378
#define	TOR	57379
#define	TLSHIFT	57380
#define	TRSHIFT	57381
#define	UMINUS	57382
