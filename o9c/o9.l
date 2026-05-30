%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include "node.h"
#include "y.tab.h"

extern Node* mk(int type, char *name, char *typename, Node *l, Node *r);
%}

%%

[ \t\n\r]+          ;
"//".*              ;

"class"             { return TCLASS; }
"struct"            { return TSTRUCT; }
"interface"         { return TINTERFACE; }
"import"            { return TIMPORT; }
"func"              { return TFUNC; }
"return"            { return TRETURN; }
"chan"              { return TCHAN; }
"if"                { return TIF; }
"else"              { return TELSE; }
"elif"              { return TELIF; }
"while"             { return TWHILE; }
"for"               { return TFOR; }
"new"               { return TNEW; }
"print"             { return TPRINT; }
"dict"              { return TDICT; }
"nil"               { return TNIL; }

"state"             { return TSTATE; }
"prop"              { return TPROP; }
"atomic"            { return TATOMIC; }
"stream"            { return TSTREAM; }
"secret"            { return TSECRET; }
"cap"               { return TCAP; }
"true"              { return TTRUE; }
"false"             { return TFALSE; }

"<-"                { return TCHANRECV; }
"->"                { return TCHANSEND; }
"->?"               { return TCHANTRY; }
"=="                { return TEQEQ; }
"!="                { return TNEQ; }
"<="                { return TLE; }
">="                { return TGE; }
"&&"                { return TAND; }
"||"                { return TOR; }
"<<"                { return TLSHIFT; }
">>"                { return TRSHIFT; }

[0-9]+ {
    yylval.name = strdup(yytext);
    return TINTLIT;
}

\"([^\\\"]|\\.)*\" {
    yylval.name = strdup(yytext);
    return TSTRINGLIT;
}

\'([^\\\']|\\.)*\' {
    yylval.name = strdup(yytext);
    return TCHARLIT;
}

[a-zA-Z_][a-zA-Z0-9_]* {
    char *s = strdup(yytext);
    yylval.node = mk(NIdent, s, s, nil, nil);
    return TIDENT;
}

"{"                 { return '{'; }
"}"                 { return '}'; }
"("                 { return '('; }
")"                 { return ')'; }
"["                 { return '['; }
"]"                 { return ']'; }
"*"                 { return '*'; }
"/"                 { return '/'; }
"%"                 { return '%'; }
"+"                 { return TADD; }
"-"                 { return TSUB; }
";"                 { return ';'; }
"="                 { return TEQ; }
"."                 { return '.'; }
","                 { return ','; }
"<"                 { return '<'; }
">"                 { return '>'; }
"!"                 { return '!'; }
"~"                 { return '~'; }
"|"                 { return '|'; }
"&"                 { return '&'; }
"^"                 { return '^'; }

.                   { return yytext[0]; }

%%

int
yywrap(void)
{
    return 1;
}
