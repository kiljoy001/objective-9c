/* ========================================================================
 * IMPORT RESOLUTION
 * ======================================================================== */
/* ---- import resolution (see docs/IMPORTS.md) ----
 *
 * Runs before prescan/parse. Scans the source for import lines, resolves
 * each to a real file within the project subtree, and splices the named
 * declarations' SOURCE into the input so the one parse produces full
 * class nodes (members + bodies), which then transpile normally.
 *
 *   import "path";              -> all top-level decls from path
 *   from "path" import A, B;    -> only decls named A, B (+ deps come
 *                                  along because the whole file's decls
 *                                  are spliced; unnamed ones are inert
 *                                  if unused — kept simple: splice all,
 *                                  selective names are advisory/dep hint)
 *
 * Path rule: resolved relative to import_base_dir, and MUST stay within
 * that dir's subtree (no .., no absolute). A project is self-contained.
 */

static char *imp_loaded[64];
static int imp_nloaded;

/* Canonicalize a/b/../c style path in place (fold . and ..). Returns -1
 * if a .. would climb above the start (escapes the subtree). */
static int
path_within_subtree(char *rel)
{
    char *parts[128];
    int np = 0, i, depth = 0;
    char *p, *save, out[1024];

    if(rel[0] == '/')
        return -1;	/* absolute: rejected */
    /* split on '/', track depth; a '..' at depth 0 escapes */
    for(p = rel; *p != '\0'; ){
        save = p;
        while(*p != '\0' && *p != '/') p++;
        if(*p == '/') *p++ = '\0';
        if(strcmp(save, "") == 0 || strcmp(save, ".") == 0)
            continue;
        if(strcmp(save, "..") == 0){
            if(depth == 0) return -1;	/* climbs above base */
            depth--; np--;
            continue;
        }
        if(np < nelem(parts)){ parts[np++] = save; depth++; }
    }
    out[0] = '\0';
    for(i = 0; i < np; i++){
        if(i > 0) strcat(out, "/");
        strcat(out, parts[i]);
    }
    strcpy(rel, out);
    return 0;
}

/* Read a whole file into a malloc'd NUL-terminated buffer; *len set. */
static char*
read_whole_file(char *path, long *len)
{
    int fd;
    long n, total = 0, cap = 8192;
    char *buf;

    fd = open(path, OREAD);
    if(fd < 0) return nil;
    buf = malloc(cap);
    while((n = read(fd, buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){ cap *= 2; buf = realloc(buf, cap); }
    }
    close(fd);
    buf[total] = '\0';
    *len = total;
    return buf;
}
