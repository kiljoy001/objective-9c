/* ========================================================================
 * LEXER
 * ======================================================================== */

void
yyerror(char *s)
{
    if(last_caps_ident[0] != '\0' && last_caps_line >= cur_line - 1)
        fprint(2, "o9c: error: line %d: %s near '%s' ('%s' is not a declared type)\n",
            cur_line, s, last_caps_ident, last_caps_ident);
    else
        fprint(2, "o9c: error: line %d: %s\n", cur_line, s);
}

static char *input_buf;
static int input_pos;
static int input_len;
char *import_base_dir;	/* dir of the source file, for relative imports */

static int for_paren_depth = -1;	/* >=0 when inside for(...) — ';' returns TFORSEMI */
static int pushback[8];		/* multi-char pushback buffer */
static int npush = 0;

enum {
    RawNormal,
    RawString,
    RawChar,
    RawLineComment,
    RawBlockComment,
};

typedef struct LexMark LexMark;
struct LexMark {
    int pos;
    int npush;
    int push[8];
    int line;
};

static void
lex_save(LexMark *m)
{
    m->pos = input_pos;
    m->npush = npush;
    memmove(m->push, pushback, sizeof pushback);
    m->line = cur_line;
}

static void
lex_restore(LexMark *m)
{
    input_pos = m->pos;
    npush = m->npush;
    memmove(pushback, m->push, sizeof pushback);
    cur_line = m->line;
}

static int
lex_getc(void)
{
	int c;

	if(npush > 0)
		c = pushback[--npush];
	else if(input_pos >= input_len)
		return Beof;
	else
		c = (unsigned char)input_buf[input_pos++];
	if(c == '\n')
		cur_line++;
	return c;
}

static void
lex_ungetc(int c)
{
    if(npush < 8)
        pushback[npush++] = c;
    if(c == '\n')
        cur_line--;
}

static void
raw_append(char **buf, int *len, int *cap, int c)
{
    char *nb;

    if(*len + 2 >= *cap){
        *cap *= 2;
        nb = realloc(*buf, *cap);
        if(nb == nil)
            sysfatal("realloc: raw c block");
        *buf = nb;
    }
    (*buf)[(*len)++] = c;
    (*buf)[*len] = '\0';
}

static void
raw_init(char **buf, int *len, int *cap)
{
    *cap = 256;
    *len = 0;
    *buf = malloc(*cap);
    if(*buf == nil)
        sysfatal("malloc: raw c block");
    (*buf)[0] = '\0';
}

static int
raw_start_block(void)
{
    int c;

    do
        c = lex_getc();
    while(c != Beof && isspace(c));
    return c == '{';
}

static void
raw_scan_quote(int c, char **buf, int *len, int *cap, int *mode, int *esc)
{
    raw_append(buf, len, cap, c);
    if(*esc){
        *esc = 0;
        return;
    }
    if(c == '\\'){
        *esc = 1;
        return;
    }
    if((*mode == RawString && c == '"') || (*mode == RawChar && c == '\''))
        *mode = RawNormal;
}

static void
raw_scan_line_comment(int c, char **buf, int *len, int *cap, int *mode)
{
    raw_append(buf, len, cap, c);
    if(c == '\n')
        *mode = RawNormal;
}

static void
raw_scan_block_comment(int c, char **buf, int *len, int *cap, int *mode)
{
    int nc;

    raw_append(buf, len, cap, c);
    if(c != '*')
        return;
    nc = lex_getc();
    if(nc == '/'){
        raw_append(buf, len, cap, nc);
        *mode = RawNormal;
    } else if(nc != Beof)
        lex_ungetc(nc);
}

static void
raw_scan_slash(int c, char **buf, int *len, int *cap, int *mode)
{
    int nc;

    nc = lex_getc();
    if(nc == '/' || nc == '*'){
        *mode = nc == '/' ? RawLineComment : RawBlockComment;
        raw_append(buf, len, cap, c);
        raw_append(buf, len, cap, nc);
        return;
    }
    if(nc != Beof)
        lex_ungetc(nc);
    raw_append(buf, len, cap, c);
}

static int
raw_scan_normal(int c, char **buf, int *len, int *cap, int *mode, int *depth)
{
    if(c == '"'){
        *mode = RawString;
        raw_append(buf, len, cap, c);
        return 0;
    }
    if(c == '\''){
        *mode = RawChar;
        raw_append(buf, len, cap, c);
        return 0;
    }
    if(c == '/'){
        raw_scan_slash(c, buf, len, cap, mode);
        return 0;
    }
    if(c == '{'){
        (*depth)++;
        raw_append(buf, len, cap, c);
        return 0;
    }
    if(c == '}'){
        (*depth)--;
        if(*depth == 0)
            return 1;
        raw_append(buf, len, cap, c);
        return 0;
    }
    raw_append(buf, len, cap, c);
    return 0;
}

static int
try_raw_c_block(char **out)
{
    int c, depth, mode, esc, len, cap;
    char *buf;
    LexMark mark;

    lex_save(&mark);
    if(!raw_start_block()){
        lex_restore(&mark);
        return 0;
    }

    raw_init(&buf, &len, &cap);
    depth = 1;
    mode = RawNormal;
    esc = 0;
    while((c = lex_getc()) != Beof){
        switch(mode){
        case RawString:
        case RawChar:
            raw_scan_quote(c, &buf, &len, &cap, &mode, &esc);
            break;
        case RawLineComment:
            raw_scan_line_comment(c, &buf, &len, &cap, &mode);
            break;
        case RawBlockComment:
            raw_scan_block_comment(c, &buf, &len, &cap, &mode);
            break;
        default:
            if(raw_scan_normal(c, &buf, &len, &cap, &mode, &depth)){
                *out = buf;
                return 1;
            }
            break;
        }
    }
    *out = buf;
    return 1;
}

int
yylex(void)
{
    int c;

    while((c = lex_getc()) != Beof){
        if(isspace(c))
            continue;
        /* Inside for(...): convert the header's ';' separators to
         * TFORSEMI so for_init/cond/step can be exprs.  for_paren_depth:
         * 0 after `for` (awaiting the header '('), 1 inside the header,
         * >1 in nested parens.  The ')' that closes the header (depth 1)
         * ends for-mode (-1); nested ')' just decrements. */
        if(for_paren_depth >= 0){
            if(c == '('){ for_paren_depth++; return '('; }
            if(c == ')'){
                for_paren_depth--;
                if(for_paren_depth <= 0)
                    for_paren_depth = -1;	/* header closed: leave for-mode */
                return ')';
            }
            if(c == ';' && for_paren_depth == 1)	/* only header ';' */
                return TFORSEMI;
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
            if(c == '.'){
                if(i < 63) buf[i++] = c;
                while(isdigit(c = lex_getc())) {
                    if(i < 63) buf[i++] = c;
                }
                if(c == 'e' || c == 'E'){
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                    if(c == '+' || c == '-'){
                        if(i < 63) buf[i++] = c;
                        c = lex_getc();
                    }
                    while(isdigit(c)) {
                        if(i < 63) buf[i++] = c;
                        c = lex_getc();
                    }
                }
                lex_ungetc(c);
                buf[i] = '\0';
                yylval.name = strdup(buf);
                return TDOUBLELIT;
            }
            if(c == 'e' || c == 'E'){
                if(i < 63) buf[i++] = c;
                c = lex_getc();
                if(c == '+' || c == '-'){
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                }
                while(isdigit(c)) {
                    if(i < 63) buf[i++] = c;
                    c = lex_getc();
                }
                lex_ungetc(c);
                buf[i] = '\0';
                yylval.name = strdup(buf);
                return TDOUBLELIT;
            }
            lex_ungetc(c);
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TINTLIT;
        }

        if(isalpha(c) || c == '_'){
            char buf[128];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = lex_getc()) || c == '_') {
                if(i < sizeof(buf)-1) buf[i++] = c;
            }
            buf[i] = '\0';
            /* Only fold a dotted chain into one token when the head is a
             * registered type (enum access Color.Red) or module qualifier
             * (App.Counter); otherwise the dot is a property access and
             * belongs to the grammar. */
            if(isupper((uchar)buf[0]) && (is_known_type_name(buf) || is_module_prefix(buf))){
                while(c == '.'){
                    int nc;

                    nc = lex_getc();
                    if(!(isalpha(nc) || nc == '_')){
                        lex_ungetc(nc);
                        lex_ungetc('.');
                        break;
                    }
                    if(i < sizeof(buf)-1)
                        buf[i++] = '.';
                    if(i < sizeof(buf)-1)
                        buf[i++] = nc;
                    while(isalnum(c = lex_getc()) || c == '_'){
                        if(i < sizeof(buf)-1)
                            buf[i++] = c;
                    }
                }
            }
            lex_ungetc(c);
            buf[i] = '\0';

            if(strcmp(buf, "c") == 0){
                char *raw;
                if(try_raw_c_block(&raw)){
                    yylval.name = raw;
                    return TRAWC;
                }
            }

            yylval.node = mk(NIdent, buf, nil, nil, nil);
            if(strchr(buf, '.') != nil){
                if(resolve_enum_sym(buf) != nil)
                    return TENUMIDENT;
                if(is_known_type_name(buf) || isupper((uchar)buf[0]))
                    return TTYPEIDENT;
                return TQIDENT;
            }

            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "abstract") == 0) return TABSTRACT;
            if(strcmp(buf, "struct") == 0) return TSTRUCT;
            if(strcmp(buf, "interface") == 0) return TINTERFACE;
            if(strcmp(buf, "enum") == 0) return TENUM;
            if(strcmp(buf, "module") == 0) return TMODULE;
            if(strcmp(buf, "import") == 0) return TIMPORT;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "function") == 0) return TFUNCTION;
            if(strcmp(buf, "main") == 0) return TMAIN;
            if(strcmp(buf, "spawn") == 0) return TSPAWN;
            if(strcmp(buf, "alt") == 0) return TALT;
            if(strcmp(buf, "case") == 0) return TCASE;
            if(strcmp(buf, "default") == 0) return TDEFAULT;
            if(strcmp(buf, "cast") == 0) return TCAST;
            if(strcmp(buf, "use") == 0) return TUSE;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "near") == 0) return TNEAR;
            if(strcmp(buf, "listener") == 0) return TLISTENER;
            if(strcmp(buf, "delete") == 0) return TDELETE;
            if(strcmp(buf, "far") == 0) return TFAR;
            if(strcmp(buf, "Dict") == 0) return TDICT;
            if(strcmp(buf, "Task") == 0) return TTASK;	/* dedicated token, like List/Dict */
            if(strcmp(buf, "method") == 0) return TMETHOD;
            if(strcmp(buf, "state") == 0) return TSTATE;
            if(strcmp(buf, "prop") == 0) return TPROP;
            if(strcmp(buf, "atomic") == 0) return TATOMIC;
            if(strcmp(buf, "stream") == 0) return TSTREAM;
            if(strcmp(buf, "secret") == 0) return TSECRET;
            if(strcmp(buf, "public") == 0) return TPUBLIC;
            if(strcmp(buf, "private") == 0) return TPRIVATE;
            if(strcmp(buf, "try") == 0) return TTRY;
            if(strcmp(buf, "defer") == 0) return TDEFER;
            if(strcmp(buf, "cap") == 0) return TCAP;
            if(strcmp(buf, "object") == 0) return TOBJECT;
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
            if(strcmp(buf, "dict") == 0) return TDICT;
            if(strcmp(buf, "List") == 0) return TLIST;
            if(strcmp(buf, "nil") == 0) return TNIL;

            if(strcmp(buf, "print") == 0) return TPRINT;
            if(strcmp(buf, "bool") == 0) return TTYPE;
            if(strcmp(buf, "int64") == 0) return TTYPE;
            if(strcmp(buf, "uint64") == 0) return TTYPE;
            if(strcmp(buf, "int32") == 0) return TTYPE;
            if(strcmp(buf, "uint32") == 0) return TTYPE;
            if(strcmp(buf, "int16") == 0) return TTYPE;
            if(strcmp(buf, "uint16") == 0) return TTYPE;
            if(strcmp(buf, "int8") == 0) return TTYPE;
            if(strcmp(buf, "uint8") == 0) return TTYPE;
            if(strcmp(buf, "byte") == 0) return TTYPE;
            if(strcmp(buf, "double") == 0) return TTYPE;
            if(strcmp(buf, "void") == 0) return TTYPE;
            if(strcmp(buf, "string") == 0) return TTYPE;
            if(strcmp(buf, "int") == 0) return TTYPE;
            if(strcmp(buf, "uint") == 0) return TTYPE;
            if(strcmp(buf, "short") == 0) return TTYPE;
            if(strcmp(buf, "long") == 0) return TTYPE;
            if(strcmp(buf, "char") == 0) return TTYPE;
            if(strcmp(buf, "intptr") == 0) return TTYPE;
            if(strcmp(buf, "uintptr") == 0) return TTYPE;
            if(strcmp(buf, "vlong") == 0) return TTYPE;
            if(strcmp(buf, "uvlong") == 0) return TTYPE;
            if(strcmp(buf, "ulong") == 0) return TTYPE;
            if(strcmp(buf, "ushort") == 0) return TTYPE;
            if(strcmp(buf, "uchar") == 0) return TTYPE;
            if(resolve_enum_sym(buf) != nil)
                return TENUMIDENT;
            if(is_known_type_name(buf))
                return TTYPEIDENT;
            if(isupper((uchar)buf[0])){
                /* Not a declared type: lex as a plain identifier so
                 * PascalCase members/locals work. Remember it for
                 * yyerror's undeclared-type hint. */
                strncpy(last_caps_ident, buf, sizeof last_caps_ident - 1);
                last_caps_ident[sizeof last_caps_ident - 1] = '\0';
                last_caps_line = cur_line;
            }
            return TIDENT;
        }
        return c;
    }
    return 0;
}
