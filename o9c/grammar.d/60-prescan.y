/* ========================================================================
 * PRESCAN AND TYPE REGISTRATION
 * ======================================================================== */
/* Two-pass parser: prescan registers all type names, then yyparse() resolves them */

typedef struct PrescanCtx PrescanCtx;
struct PrescanCtx {
    char *modules[32];
    char *pending_module_name;
    int brace_modules[128];
    int module_depth;
    int brace_depth;
    int pending_module;
};

static char*
scan_current_module(PrescanCtx *ctx)
{
    if(ctx->module_depth <= 0)
        return nil;
    return ctx->modules[ctx->module_depth-1];
}

static void
scan_open_brace(PrescanCtx *ctx)
{
    if(ctx->brace_depth < nelem(ctx->brace_modules))
        ctx->brace_modules[ctx->brace_depth++] = ctx->pending_module;
    if(ctx->pending_module && ctx->module_depth < nelem(ctx->modules))
        ctx->modules[ctx->module_depth++] = ctx->pending_module_name;
    ctx->pending_module = 0;
    ctx->pending_module_name = nil;
}

static void
scan_close_brace(PrescanCtx *ctx)
{
    if(ctx->brace_depth > 0 && ctx->brace_modules[--ctx->brace_depth] &&
       ctx->module_depth > 0)
        ctx->module_depth--;
}

static int
scan_brace(PrescanCtx *ctx, int c)
{
    if(c == '{'){
        scan_open_brace(ctx);
        return 1;
    }
    if(c == '}'){
        scan_close_brace(ctx);
        return 1;
    }
    return 0;
}

static int
scan_ignored_punct(int c)
{
    return isspace(c) || c == ';' || c == '(' || c == ')';
}

static void
scan_skip_string(char *buf, long len, long *pos)
{
    while(*pos < len && buf[*pos] != '"')
        (*pos)++;
    if(*pos < len)
        (*pos)++;
}

static void
scan_skip_charlit(char *buf, long len, long *pos)
{
    if(*pos < len && buf[*pos] == '\\')
        (*pos)++;
    if(*pos < len)
        (*pos)++;
    if(*pos < len)
        (*pos)++;
}

static int
scan_skip_comment(char *buf, long len, long *pos)
{
    if(*pos >= len)
        return 0;
    if(buf[*pos] == '/'){
        while(*pos < len && buf[*pos] != '\n')
            (*pos)++;
        return 1;
    }
    if(buf[*pos] == '*'){
        (*pos)++;
        while(*pos + 1 < len && !(buf[*pos] == '*' && buf[*pos+1] == '/'))
            (*pos)++;
        if(*pos + 1 < len)
            *pos += 2;
        return 1;
    }
    return 0;
}

static int
scan_literal_or_comment(char *buf, long len, long *pos, int c)
{
    if(c == '"'){
        scan_skip_string(buf, len, pos);
        return 1;
    }
    if(c == '\''){
        scan_skip_charlit(buf, len, pos);
        return 1;
    }
    if(c == '/')
        return scan_skip_comment(buf, len, pos);
    return 0;
}

static int
scan_read_ident(char *buf, long len, long *pos, int first, char *out, int outsz)
{
    int i;

    i = 0;
    out[i++] = first;
    while(i < outsz-1 && *pos < len &&
          (isalnum((unsigned char)buf[*pos]) || buf[*pos] == '_'))
        out[i++] = buf[(*pos)++];
    out[i] = '\0';
    return i;
}

static void
scan_skip_space(char *buf, long len, long *pos)
{
    while(*pos < len && isspace((unsigned char)buf[*pos]))
        (*pos)++;
}

static int
scan_read_qualified_name(char *buf, long len, long *pos, char *out, int outsz)
{
    int i;

    i = 0;
    while(i < outsz-1 && *pos < len &&
          (isalnum((unsigned char)buf[*pos]) || buf[*pos] == '_' || buf[*pos] == '.'))
        out[i++] = buf[(*pos)++];
    out[i] = '\0';
    return i;
}

static void
scan_module_decl(char *buf, long len, long *pos, PrescanCtx *ctx)
{
    char modname[128];
    char *q;

    scan_skip_space(buf, len, pos);
    scan_read_qualified_name(buf, len, pos, modname, sizeof modname);
    q = qualify_source_name(scan_current_module(ctx), modname);
    ctx->pending_module = 1;
    ctx->pending_module_name = q;
}

static void
scan_enum_values(char *buf, long len, long *pos, char *q, char *cn)
{
    char valname[64];
    int depth, value, c;

    depth = 1;
    value = 0;
    while(*pos < len && depth > 0){
        c = (unsigned char)buf[(*pos)++];
        if(c == '{'){
            depth++;
            continue;
        }
        if(c == '}'){
            depth--;
            continue;
        }
        if(depth == 1 && (isalpha(c) || c == '_')){
            scan_read_ident(buf, len, pos, c, valname, sizeof valname);
            add_enum_sym(q, cn, valname, value++);
        }
    }
}

static void
scan_enum_decl(char *buf, long len, long *pos, PrescanCtx *ctx)
{
    char enumname[64];
    char *q, *cn;
    Node *n;

    scan_skip_space(buf, len, pos);
    if(scan_read_qualified_name(buf, len, pos, enumname, sizeof enumname) <= 0)
        return;
    q = qualify_source_name(scan_current_module(ctx), enumname);
    cn = mangle_source_name(q);
    n = mk(NEnum, cn, nil, nil, nil);
    add_class(cn, n);
    scan_skip_space(buf, len, pos);
    if(*pos < len && buf[*pos] == '{'){
        (*pos)++;
        scan_enum_values(buf, len, pos, q, cn);
    }
}

static int
scan_decl_type(char *word)
{
    if(strcmp(word, "interface") == 0)
        return NInterface;
    if(strcmp(word, "struct") == 0)
        return NStruct;
    return NClass;
}

static void
scan_type_decl(char *buf, long len, long *pos, PrescanCtx *ctx, char *word)
{
    char name[64];
    char *q, *cn;
    Node *n;

    scan_skip_space(buf, len, pos);
    if(scan_read_qualified_name(buf, len, pos, name, sizeof name) <= 0)
        return;
    q = qualify_source_name(scan_current_module(ctx), name);
    cn = mangle_source_name(q);
    n = mk(scan_decl_type(word), cn, nil, nil, nil);
    add_class(cn, n);
}

static void
scan_decl_word(char *buf, long len, long *pos, PrescanCtx *ctx, char *word)
{
    if(strcmp(word, "module") == 0){
        scan_module_decl(buf, len, pos, ctx);
        return;
    }
    if(strcmp(word, "enum") == 0){
        scan_enum_decl(buf, len, pos, ctx);
        return;
    }
    if(strcmp(word, "class") == 0 || strcmp(word, "interface") == 0 ||
       strcmp(word, "struct") == 0)
        scan_type_decl(buf, len, pos, ctx, word);
}

static void
scan_buffer(char *buf, long len)
{
    PrescanCtx ctx;
    long pos;
    int c;
    char name[64];

    memset(&ctx, 0, sizeof ctx);
    pos = 0;
    while(pos < len){
        c = (unsigned char)buf[pos++];
        if(scan_brace(&ctx, c))
            continue;
        if(scan_ignored_punct(c))
            continue;
        if(scan_literal_or_comment(buf, len, &pos, c))
            continue;
        if(isalpha(c) || c == '_'){
            scan_read_ident(buf, len, &pos, c, name, sizeof name);
            scan_decl_word(buf, len, &pos, &ctx, name);
        }
    }
}

static void
prescan(void)
{
    in_prescan = 1;
    scan_buffer(input_buf, input_len);
    in_prescan = 0;
    input_pos = 0;
}
