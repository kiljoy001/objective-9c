%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <stdio.h>
#include "node.h"
#include "y.tab.h"

extern Node* mk(int type, char *name, char *typename, Node *l, Node *r);
%}

%%

[ \t\n\r]+          ;

"class"             { return TCLASS; }
"func"              { return TFUNC; }
"return"            { return TRETURN; }
"chan"              { return TCHAN; }

[a-zA-Z_][a-zA-Z0-9_]* {
    char *s = strdup(yytext);
    yylval.node = mk(NIdent, s, s, nil, nil);
    return TIDENT;
}

"{"                 { return '{'; }
"}"                 { return '}'; }
"("                 { return '('; }
")"                 { return ')'; }
"*"                 { return '*'; }
";"                 { return ';'; }
"="                 { return TEQ; }
"<-"                { return TCHANRECV; }
"->"                { return TCHANSEND; }

.                   { return yytext[0]; }

%%

int
yywrap(void)
{
    return 1;
}
