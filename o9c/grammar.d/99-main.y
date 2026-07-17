/* ========================================================================
 * COMPILER MAIN
 * ======================================================================== */

int
main(int argc, char **argv)
{
    long n, total = 0, cap = 8192;
    int dumpast, i, fd = 0;
    char *srcpath = nil;

    dumpast = 0;
    for(i = 1; i < argc; i++){
        if(strcmp(argv[i], "-ast") == 0)
            dumpast = 1;
        else if(argv[i][0] != '-')
            srcpath = argv[i];	/* optional source file (else stdin) */
    }

    /* Import resolution needs the importing file's directory. With a
     * source path, imports resolve relative to its dir; from stdin they
     * fall back to cwd (".") — existing `o9c < src` invocations keep
     * working, and the test tree's cwd is the project root. */
    if(srcpath != nil){
        char *slash;
        fd = open(srcpath, OREAD);
        if(fd < 0) sysfatal("open %s: %r", srcpath);
        import_base_dir = strdup(srcpath);
        slash = strrchr(import_base_dir, '/');
        if(slash != nil) *slash = '\0'; else strcpy(import_base_dir, ".");
    } else {
        import_base_dir = strdup(".");
    }

    input_buf = malloc(cap);
    if(input_buf == nil) sysfatal("malloc: input buffer");
    while((n = read(fd, input_buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            input_buf = realloc(input_buf, cap);
            if(input_buf == nil) sysfatal("realloc: input buffer");
        }
    }
    input_len = total;
    if(fd != 0) close(fd);

    load_builtin_cdeps();
    load_project_cdeps();
    if(semantic_errors > 0)
        exits("deps");

    for(i = 0; i < 32 && resolve_imports(); i++)
        ;
    if(i >= 32){
        fprint(2, "o9c: error: import nesting too deep or cyclic\n");
        semantic_errors++;
    }
    if(semantic_errors > 0)	/* import errors: stop before parse cascades */
        exits("import");

    prescan();

    if(yyparse() == 0){
        if(typecheck(ast_root) == 0){
            if(dumpast)
                dump_ast(ast_root);
            else
                codegen(ast_root);
        } else
            exits("typecheck");
    } else {
        fprint(2, "o9c: parse failed\n");
        exits("parse");
    }
    exits(nil);
    return 0;
}
