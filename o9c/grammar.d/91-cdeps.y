/* ========================================================================
 * C DEPENDENCY LOADING
 * ======================================================================== */

typedef struct CDepSpec CDepSpec;
struct CDepSpec {
    char *name;
    char *header;
    char *archive;
    char *requires;
};

static CDepSpec builtin_cdep_specs[] = {
    { "9p",       "<9p.h>",       "/$objtype/lib/lib9p.a", nil },
    { "String",   "<String.h>",   "/$objtype/lib/libString.a", nil },
    { "aml",      "<aml.h>",      "/$objtype/lib/libaml.a", nil },
    { "auth",     "<auth.h>",     "/$objtype/lib/libauth.a", nil },
    { "authsrv",  "<authsrv.h>",  "/$objtype/lib/libauthsrv.a", "auth sec" },
    { "avl",      "<avl.h>",      "/$objtype/lib/libavl.a", nil },
    { "bin",      "<bin.h>",      "/$objtype/lib/libbin.a", nil },
    { "bio",      "<bio.h>",      "/$objtype/lib/libbio.a", nil },
    { "complete", "<complete.h>", "/$objtype/lib/libcomplete.a", nil },
    { "control",  "<control.h>",  "/$objtype/lib/libcontrol.a", nil },
    { "disk",     "<disk.h>",     "/$objtype/lib/libdisk.a", nil },
    { "draw",     "<draw.h>",     "/$objtype/lib/libdraw.a", nil },
    { "event",    "<event.h>",    nil, "draw" },
    { "dtracy",   "<dtracy.h>",   "/$objtype/lib/libdtracy.a", nil },
    { "fis",      "<fis.h>",      "/$objtype/lib/libfis.a", nil },
    { "flate",    "<flate.h>",    "/$objtype/lib/libflate.a", nil },
    { "frame",    "<frame.h>",    "/$objtype/lib/libframe.a", "draw" },
    { "geometry", "<geometry.h>", "/$objtype/lib/libgeometry.a", nil },
    { "html",     "<html.h>",     "/$objtype/lib/libhtml.a", nil },
    { "httpd",    "<httpd.h>",    "/$objtype/lib/libhttpd.a", nil },
    { "ip",       "<ip.h>",       "/$objtype/lib/libip.a", nil },
    { "json",     "<json.h>",     "/$objtype/lib/libjson.a", nil },
    { "mach",     "<mach.h>",     "/$objtype/lib/libmach.a", nil },
    { "memdraw",  "<memdraw.h>",  "/$objtype/lib/libmemdraw.a", "draw" },
    { "memlayer", "<memlayer.h>", "/$objtype/lib/libmemlayer.a", "memdraw draw" },
    { "mp",       "<mp.h>",       "/$objtype/lib/libmp.a", nil },
    { "ndb",      "<ndb.h>",      "/$objtype/lib/libndb.a", nil },
    { "pcm",      "<pcm.h>",      "/$objtype/lib/libpcm.a", nil },
    { "plumb",    "<plumb.h>",    "/$objtype/lib/libplumb.a", nil },
    { "regexp",   "<regexp.h>",   "/$objtype/lib/libregexp.a", nil },
    { "sat",      "<sat.h>",      "/$objtype/lib/libsat.a", nil },
    { "scribble", "<scribble.h>", "/$objtype/lib/libscribble.a", nil },
    { "sec",      "<libsec.h>",   "/$objtype/lib/libsec.a", "mp" },
    { "stdio",    "<stdio.h>",    "/$objtype/lib/libstdio.a", nil },
    { "sunrpc",   "<sunrpc.h>",   "/$objtype/lib/libsunrpc.a", nil },
    { "thread",   "<thread.h>",   "/$objtype/lib/libthread.a", nil },
    { "ttf",      "<ttf.h>",      "/$objtype/lib/libttf.a", nil },
    { "venti",    "<venti.h>",    "/$objtype/lib/libventi.a", nil },
    { nil, nil, nil, nil }
};

static char*
trim_ws(char *s)
{
    char *e;

    while(*s != '\0' && isspace((uchar)*s))
        s++;
    e = s + strlen(s);
    while(e > s && isspace((uchar)e[-1]))
        *--e = '\0';
    return s;
}

static char*
unquote_value(char *s)
{
    int n;

    s = trim_ws(s);
    n = strlen(s);
    if(n >= 2 && ((s[0] == '"' && s[n-1] == '"') || (s[0] == '\'' && s[n-1] == '\''))){
        s[n-1] = '\0';
        return s + 1;
    }
    return s;
}

static int
safe_dep_name(char *s)
{
    char *p;

    if(s == nil || s[0] == '\0' || !(isalpha((uchar)s[0]) || s[0] == '_'))
        return 0;
    for(p = s; *p != '\0'; p++)
        if(!(isalnum((uchar)*p) || *p == '_'))
            return 0;
    return 1;
}

static int
safe_project_chars(char *s, int allowobj)
{
    char *p;

    for(p = s; *p != '\0'; p++){
        if(isalnum((uchar)*p) || *p == '_' || *p == '.' || *p == '/' || *p == '-')
            continue;
        if(*p == '$' && allowobj && strncmp(p, "$objtype", 8) == 0){
            p += 7;
            continue;
        }
        return 0;
    }
    return 1;
}

static char*
clean_project_dep_path(char *val, int allowobj, int line, char *field)
{
    char clean[1024];

    if(val == nil)
        return nil;
    val = unquote_value(val);
    if(val[0] == '<' || val[0] == '"' || val[0] == '/' ||
       !safe_project_chars(val, allowobj)){
        fprint(2, "o9c: error: line %d: deps.tab %s path '%s' is not project-relative\n",
            line, field, val);
        semantic_errors++;
        return nil;
    }
    strncpy(clean, val, sizeof clean - 1);
    clean[sizeof clean - 1] = '\0';
    if(path_within_subtree(clean) < 0){
        fprint(2, "o9c: error: line %d: deps.tab %s path '%s' escapes the project root\n",
            line, field, val);
        semantic_errors++;
        return nil;
    }
    return strdup(clean);
}

static CDep*
find_cdep(char *name)
{
    CDep *d;

    for(d = cdeps; d != nil; d = d->next)
        if(strcmp(d->name, name) == 0)
            return d;
    return nil;
}

static CDep*
new_cdep(char *name, int system)
{
    CDep *d;

    d = mallocz(sizeof *d, 1);
    if(d == nil)
        sysfatal("malloc: cdep");
    d->name = strdup(name);
    d->system = system;
    return d;
}

static void
add_builtin_cdep(char *name, char *header, char *archive, char *requires)
{
    CDep *d;

    d = new_cdep(name, 1);
    d->header = header != nil ? strdup(header) : nil;
    d->archive = archive != nil ? strdup(archive) : nil;
    d->requires = requires != nil ? strdup(requires) : nil;
    d->next = cdeps;
    cdeps = d;
}

static void
load_builtin_cdeps(void)
{
    int i;

    if(cdeps != nil)
        return;
    for(i = 0; builtin_cdep_specs[i].name != nil; i++)
        add_builtin_cdep(builtin_cdep_specs[i].name,
            builtin_cdep_specs[i].header,
            builtin_cdep_specs[i].archive,
            builtin_cdep_specs[i].requires);
}

static void
cdep_replace(CDep *old, CDep *n)
{
    old->header = n->header;
    old->include = n->include;
    old->archive = n->archive;
    old->source = n->source;
    old->requires = n->requires;
    old->system = 0;
}

static void
finish_project_cdep(CDep *d, int line)
{
    CDep *old;

    if(d == nil)
        return;
    if(!safe_dep_name(d->name)){
        fprint(2, "o9c: error: line %d: deps.tab dependency name '%s' is not a simple identifier\n",
            line, d->name != nil ? d->name : "");
        semantic_errors++;
        return;
    }
    if(d->header != nil)
        d->header = clean_project_dep_path(d->header, 0, line, "header");
    if(d->include != nil)
        d->include = clean_project_dep_path(d->include, 0, line, "include");
    if(d->source != nil)
        d->source = clean_project_dep_path(d->source, 0, line, "source");
    if(d->archive != nil)
        d->archive = clean_project_dep_path(d->archive, 1, line, "archive");
    if(semantic_errors > 0)
        return;

    old = find_cdep(d->name);
    if(old != nil){
        if(!d->override){
            fprint(2, "o9c: error: line %d: deps.tab dependency '%s' already exists; set override=true to replace it\n",
                line, d->name);
            semantic_errors++;
            return;
        }
        cdep_replace(old, d);
        return;
    }
    d->system = 0;
    d->next = cdeps;
    cdeps = d;
}

static int
project_deps_skip_line(char *s)
{
    if(s[0] == '\0' || s[0] == '#')
        return 1;
    return s[0] == '/' && s[1] == '/';
}

static int
project_deps_keyval(char *linebuf, char **key, char **val, int line)
{
    char *s, *eq;

    s = trim_ws(linebuf);
    if(project_deps_skip_line(s))
        return 0;
    eq = strchr(s, '=');
    if(eq == nil){
        fprint(2, "o9c: error: line %d: deps.tab line needs key=value\n", line);
        semantic_errors++;
        return 0;
    }
    *eq = '\0';
    *key = trim_ws(s);
    *val = unquote_value(eq + 1);
    return 1;
}

static char**
project_cdep_slot(CDep *cur, char *key)
{
    if(strcmp(key, "header") == 0)
        return &cur->header;
    if(strcmp(key, "include") == 0)
        return &cur->include;
    if(strcmp(key, "archive") == 0)
        return &cur->archive;
    if(strcmp(key, "source") == 0)
        return &cur->source;
    if(strcmp(key, "requires") == 0)
        return &cur->requires;
    return nil;
}

static int
project_cdep_bool(char *val)
{
    return strcmp(val, "true") == 0 || strcmp(val, "1") == 0 ||
        strcmp(val, "yes") == 0;
}

static int
project_cdep_set_field(CDep *cur, char *key, char *val, int line)
{
    char **slot;

    slot = project_cdep_slot(cur, key);
    if(slot != nil){
        *slot = strdup(val);
        return 1;
    }
    if(strcmp(key, "override") == 0){
        cur->override = project_cdep_bool(val);
        return 1;
    }
    if(strcmp(key, "kind") == 0){
        if(strcmp(val, "project") != 0){
            fprint(2, "o9c: error: line %d: deps.tab kind must be project\n", line);
            semantic_errors++;
        }
        return 1;
    }
    return 0;
}

static void
project_cdep_apply_line(CDep **cur, int *rowline, char *key, char *val, int line)
{
    if(strcmp(key, "name") == 0){
        finish_project_cdep(*cur, *rowline);
        *cur = new_cdep(val, 0);
        *rowline = line;
        return;
    }
    if(*cur == nil){
        fprint(2, "o9c: error: line %d: deps.tab field '%s' appears before name\n",
            line, key);
        semantic_errors++;
        return;
    }
    if(project_cdep_set_field(*cur, key, val, line))
        return;
    fprint(2, "o9c: error: line %d: deps.tab unknown field '%s'\n", line, key);
    semantic_errors++;
}

static void
load_project_cdeps(void)
{
    char path[1024], linebuf[1024], *buf, *p, *nl, *key, *val;
    long len;
    int line, rowline;
    CDep *cur;

    snprint(path, sizeof path, "%s/deps.tab", project_root);
    buf = read_whole_file(path, &len);
    if(buf == nil)
        return;

    cur = nil;
    rowline = 0;
    line = 0;
    for(p = buf; p != nil && *p != '\0'; p = (nl != nil ? nl + 1 : nil)){
        nl = strchr(p, '\n');
        if(nl != nil)
            *nl = '\0';
        line++;
        strncpy(linebuf, p, sizeof linebuf - 1);
        linebuf[sizeof linebuf - 1] = '\0';
        if(project_deps_keyval(linebuf, &key, &val, line))
            project_cdep_apply_line(&cur, &rowline, key, val, line);
    }
    finish_project_cdep(cur, rowline);
    free(buf);
}

static void
mark_cdep_used(CDep *d)
{
    if(d->used)
        return;
    d->used = 1;
    if(used_cdeps_tail != nil)
        used_cdeps_tail->usednext = d;
    else
        used_cdeps = d;
    used_cdeps_tail = d;
}

static void
use_cdep_inner(char *name, int line, int *errs, int depth)
{
    CDep *d;
    char *reqs, *tok, *p;

    if(name == nil)
        return;
    if(depth > 32){
        fprint(2, "o9c: error: line %d: C dependency '%s' has a recursive requires chain\n",
            line, name);
        (*errs)++;
        return;
    }
    d = find_cdep(name);
    if(d == nil){
        fprint(2, "o9c: error: line %d: unknown C dependency '%s'\n", line, name);
        (*errs)++;
        return;
    }
    if(d->requires != nil && d->requires[0] != '\0'){
        reqs = strdup(d->requires);
        for(p = reqs; *p != '\0'; p++)
            if(*p == ',')
                *p = ' ';
        for(tok = strtok(reqs, " \t\r\n"); tok != nil; tok = strtok(nil, " \t\r\n"))
            use_cdep_inner(tok, line, errs, depth + 1);
        free(reqs);
    }
    mark_cdep_used(d);
}

static void
use_cdep(char *name, int line, int *errs)
{
    use_cdep_inner(name, line, errs, 0);
}

static char*
expand_objtype(char *s)
{
    char *obj, *p, out[1024];
    int n;

    if(s == nil)
        return nil;
    obj = getenv("objtype");
    if(obj == nil || obj[0] == '\0')
        obj = getenv("OBJTYPE");
    if(obj == nil || obj[0] == '\0')
        obj = "unknown";
    out[0] = '\0';
    n = 0;
    for(p = s; *p != '\0' && n < sizeof out - 1; p++){
        if(strncmp(p, "$objtype", 8) == 0){
            n += snprint(out + n, sizeof out - n, "%s", obj);
            p += 7;
        } else
            out[n++] = *p;
    }
    out[n] = '\0';
    return strdup(out);
}

static void
emit_cdeps(void)
{
    CDep *d;
    char *x;
    int hasevent;

    hasevent = 0;
    for(d = used_cdeps; d != nil; d = d->usednext){
        if(strcmp(d->name, "event") == 0)
            hasevent = 1;
        print("/* o9: dep %s %s */\n", d->system ? "system" : "project", d->name);
        if(d->include != nil)
            print("/* o9: include %s */\n", d->include);
        if(d->source != nil)
            print("/* o9: source %s */\n", d->source);
        if(d->archive != nil){
            x = expand_objtype(d->archive);
            print("/* o9: archive %s */\n", x);
            free(x);
        }
    }
    for(d = used_cdeps; d != nil; d = d->usednext){
        if(d->header == nil)
            continue;
        if(d->header[0] == '<' || d->header[0] == '"')
            print("#include %s\n", d->header);
        else
            print("#include \"%s\"\n", d->header);
    }
    if(used_cdeps != nil)
        print("\n");
    if(hasevent)
        print("static int o9_draw_resized;\nstatic int o9_draw_width;\nstatic int o9_draw_height;\n\nvoid\neresized(int new)\n{\n\tif(new && getwindow(display, Refnone) < 0)\n\t\tsysfatal(\"cannot reattach draw window\");\n\tif(screen != nil){\n\t\to9_draw_resized = 1;\n\t\to9_draw_width = Dx(screen->r);\n\t\to9_draw_height = Dy(screen->r);\n\t}\n}\n\n");
}
