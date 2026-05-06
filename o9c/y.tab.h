
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
#define	TSTATE	57359
#define	TPROP	57360
#define	TATOMIC	57361
#define	TSTREAM	57362
#define	TSECRET	57363
#define	TCAP	57364
#define	TTRUE	57365
#define	TFALSE	57366
#define	TEQ	57367
#define	TADD	57368
#define	TSUB	57369
#define	TCHANSEND	57370
#define	TCHANRECV	57371
#define	TCHANTRY	57372
#define	TEQEQ	57373
#define	TNEQ	57374
#define	TLE	57375
#define	TGE	57376
#define	TAND	57377
#define	TOR	57378
#define	TLSHIFT	57379
#define	TRSHIFT	57380
#define	UMINUS	57381
