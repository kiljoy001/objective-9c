/* ========================================================================
 * IMPORT RESOLUTION CONTINUED
 * ======================================================================== */

static int
o9_ident_char(int c)
{
    return isalnum(c) || c == '_';
}

static char*
find_main_block_start(char *src)
{
    char *m, *p;

    if(src == nil)
        return nil;
    for(m = src; (m = strstr(m, "main")) != nil; m += 4){
        if((m > src && o9_ident_char((uchar)m[-1])) || o9_ident_char((uchar)m[4]))
            continue;
        p = m + 4;
        while(*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
            p++;
        if(*p == '{')
            return m;
    }
    return nil;
}

/* Strip imported program entries (only the root file owns the entry).
 * Supports the current `main { ... }` form.  Legacy `func main() { ... }`
 * is intentionally not stripped, so imported stale syntax still fails.
 * Balances braces from the entry block and edits in place. */
static void
strip_imported_main(char *src)
{
    char *m = find_main_block_start(src);
    char *p;
    int depth;
    if(m == nil) return;
    p = strchr(m, '{');
    if(p == nil) return;
    depth = 0;
    do {
        if(*p == '{') depth++;
        else if(*p == '}') depth--;
        p++;
    } while(depth > 0 && *p != '\0');
    /* blank out main..closing brace */
    while(m < p){ *m++ = ' '; }
}

/* Append imported source (main stripped, import lines are handled by the
 * outer scan) to the growing combined buffer. */
static char*
splice_append(char *dst, long *dlen, long *dcap, char *add, long addlen)
{
    if(*dlen + addlen + 2 >= *dcap){
        while(*dlen + addlen + 2 >= *dcap) *dcap *= 2;
        dst = realloc(dst, *dcap);
    }
    dst[(*dlen)++] = '\n';
    memmove(dst + *dlen, add, addlen);
    *dlen += addlen;
    dst[*dlen] = '\0';
    return dst;
}

/* Resolve one import path string to a full path within the subtree;
 * returns malloc'd full path or nil (with an error printed). */
static char*
resolve_import_path(char *rel, int line)
{
    char clean[1024], full[1200];

    strncpy(clean, rel, sizeof clean - 1);
    clean[sizeof clean - 1] = '\0';
    if(path_within_subtree(clean) < 0){
        fprint(2, "o9c: error: line %d: import path '%s' escapes the "
            "importing file's directory; imports must stay within the "
            "project subtree\n", line, rel);
        semantic_errors++;
        return nil;
    }
    snprint(full, sizeof full, "%s/%s", import_base_dir, clean);
    return strdup(full);
}

static char*
import_line_start(char *linebuf)
{
    char *ls;

    ls = linebuf;
    while(*ls == ' ' || *ls == '\t')
        ls++;
    return ls;
}

static int
handle_from_import_line(char *ls, int line)
{
    if(strncmp(ls, "from ", 5) != 0)
        return 0;
    fprint(2, "o9c: error: line %d: 'from ... import' is not "
        "supported; use `import \"path\";` (it pulls the file's "
        "declarations). Selective import is not yet implemented.\n", line);
    semantic_errors++;
    return 1;
}

static int
import_already_loaded(char *full)
{
    int k;

    for(k = 0; k < imp_nloaded; k++)
        if(strcmp(imp_loaded[k], full) == 0)
            return 1;
    return 0;
}

static void
append_import_file(char **combined, long *clen, long *ccap,
    char *path, char *full, int line)
{
    char *fsrc;
    long flen;

    if(import_already_loaded(full))
        return;
    if(imp_nloaded >= nelem(imp_loaded))
        return;
    imp_loaded[imp_nloaded++] = full;
    fsrc = read_whole_file(full, &flen);
    if(fsrc == nil){
        fprint(2, "o9c: error: line %d: cannot open import '%s'\n", line, path);
        semantic_errors++;
        return;
    }
    strip_imported_main(fsrc);
    *combined = splice_append(*combined, clen, ccap, fsrc, strlen(fsrc));
    free(fsrc);
}

static int
parse_import_path(char *ls, char *path, int npath)
{
    char *q1, *q2;

    q1 = strchr(ls, '"');
    if(q1 == nil)
        return 0;
    q2 = strchr(q1 + 1, '"');
    if(q2 == nil)
        return 0;
    *q2 = '\0';
    strncpy(path, q1 + 1, npath - 1);
    path[npath - 1] = '\0';
    return 1;
}

static int
handle_import_line(char *ls, int line, char **combined, long *clen, long *ccap, int *any)
{
    char path[1024], *full;

    if(strncmp(ls, "import ", 7) != 0)
        return 0;
    if(parse_import_path(ls, path, sizeof path)){
        full = resolve_import_path(path, line);
        if(full != nil)
            append_import_file(combined, clen, ccap, path, full, line);
        *any = 1;
    }
    return 1;
}

static void
copy_source_line(char **combined, long *clen, long *ccap, char *linebuf, int llen)
{
    *combined = splice_append(*combined, clen, ccap, linebuf, llen);
}

/* Pull imported files' declarations into input_buf. Returns non-zero when
 * at least one import line was consumed; callers rescan until the combined
 * source is import-free so stdlib modules can depend on each other. */
static int
resolve_imports(void)
{
    char *combined;
    long clen, ccap = 16384;
    char *p, *nl;
    int line = 0, any = 0;

    combined = malloc(ccap);
    clen = 0;
    combined[0] = '\0';

    /* Walk input line by line; import lines are resolved+spliced,
     * every other line is copied through. */
    for(p = input_buf; p != nil && *p != '\0'; p = (nl != nil ? nl + 1 : nil)){
        char *ls, *le, linebuf[1024];
        int llen;
        nl = strchr(p, '\n');
        le = nl != nil ? nl : p + strlen(p);
        llen = le - p;
        line++;
        if(llen >= (int)sizeof linebuf) llen = sizeof linebuf - 1;
        memmove(linebuf, p, llen);
        linebuf[llen] = '\0';

        ls = import_line_start(linebuf);
        /* `from "..." import ...` would splice the whole file identically
         * to `import`, so the name list would be a lie. One honest verb. */
        if(handle_from_import_line(ls, line))
            continue;
        if(handle_import_line(ls, line, &combined, &clen, &ccap, &any))
            continue;	/* drop the import line itself */
        /* ordinary line: copy through */
        copy_source_line(&combined, &clen, &ccap, linebuf, llen);
    }

    if(any){
        free(input_buf);
        input_buf = combined;
        input_len = clen;
        return 1;
    } else {
        free(combined);
        return 0;
    }
}
