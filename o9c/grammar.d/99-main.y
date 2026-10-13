/* ========================================================================
 * COMPILER MAIN
 * ======================================================================== */

typedef struct CompilerOptions CompilerOptions;
struct CompilerOptions {
    int dumpast;
    int listmutants;
    int mutantline;
    int mutantordinal;
    char *mutantsource;
    char *srcpath;
};

static CompilerOptions
parse_compiler_options(int argc, char **argv)
{
    CompilerOptions opt;
    int i;

    opt.dumpast = 0;
    opt.listmutants = 0;
    chosenline = chosenordinal = 0;
    mutant_id(getenv("O9_MUTANT"));
    opt.mutantsource = getenv("O9_MUTATE_SOURCE");
    opt.srcpath = nil;
    for(i = 1; i < argc; i++){
        if(strcmp(argv[i], "-ast") == 0)
            opt.dumpast = 1;
        else if(strcmp(argv[i], "-mutants") == 0)
            opt.listmutants = 1;
        else if(strcmp(argv[i], "-mutant") == 0){
            if(i+1 >= argc)
                sysfatal("-mutant requires line.ordinal");
            mutant_id(argv[++i]);
        }
        else if(strcmp(argv[i], "-mutate-source") == 0){
            if(i+1 >= argc)
                sysfatal("-mutate-source requires a path");
            opt.mutantsource = argv[++i];
        }
        else if(argv[i][0] != '-')
            opt.srcpath = argv[i];	/* optional source file (else stdin) */
    }
    opt.mutantline = chosenline;
    opt.mutantordinal = chosenordinal;
    if(opt.listmutants && opt.mutantline)
        sysfatal("-mutants and -mutant cannot be combined");
    if((opt.listmutants || opt.mutantline) && opt.srcpath == nil)
        sysfatal("mutation requires a source path");
    if(opt.mutantsource == nil)
        opt.mutantsource = opt.srcpath;
    return opt;
}

static int
open_source_and_set_import_base(char *srcpath)
{
    char *slash;
    int fd;

    if(srcpath == nil){
        import_base_dir = strdup(".");
        return 0;
    }
    /* Import resolution needs the importing file's directory. With a
     * source path, imports resolve relative to its dir; from stdin they
     * fall back to cwd (".") — existing `o9c < src` invocations keep
     * working, and the test tree's cwd is the project root. */
    fd = open(srcpath, OREAD);
    if(fd < 0)
        sysfatal("open %s: %r", srcpath);
    import_base_dir = strdup(srcpath);
    slash = strrchr(import_base_dir, '/');
    if(slash != nil)
        *slash = '\0';
    else
        strcpy(import_base_dir, ".");
    return fd;
}

static void
read_source_into_input(int fd)
{
    long n, total, cap;

    total = 0;
    cap = 8192;
    input_buf = malloc(cap);
    if(input_buf == nil)
        sysfatal("malloc: input buffer");
    while((n = read(fd, input_buf + total, cap - total)) > 0){
        total += n;
        if(total + 1024 >= cap){
            cap *= 2;
            input_buf = realloc(input_buf, cap);
            if(input_buf == nil) sysfatal("realloc: input buffer");
        }
    }
    input_buf[total] = '\0';
    input_len = total;
    if(fd != 0)
        close(fd);
}

static void
load_dependencies_or_exit(void)
{
    load_builtin_cdeps();
    load_project_cdeps();
    if(semantic_errors > 0)
        exits("deps");
}

static void
resolve_imports_or_exit(void)
{
    int i;

    for(i = 0; i < 32 && resolve_imports(); i++)
        ;
    if(i >= 32){
        fprint(2, "o9c: error: import nesting too deep or cyclic\n");
        semantic_errors++;
    }
    if(semantic_errors > 0)	/* import errors: stop before parse cascades */
        exits("import");
}

static void
parse_typecheck_emit_or_exit(CompilerOptions opt)
{
    if(yyparse() != 0){
        fprint(2, "o9c: parse failed\n");
        exits("parse");
    }
    if(typecheck(ast_root) != 0)
        exits("typecheck");
    if(opt.listmutants || opt.mutantline){
        listmutants = opt.listmutants;
        chosenline = opt.mutantline;
        chosenordinal = opt.mutantordinal;
        mutantsource = opt.mutantsource;
        mutate_or_list(ast_root);
    }
    if(opt.listmutants)
        return;
    if(opt.dumpast)
        dump_ast(ast_root);
    else
        codegen(ast_root);
}

int
main(int argc, char **argv)
{
    CompilerOptions opt;
    int fd;

    opt = parse_compiler_options(argc, argv);
    fd = open_source_and_set_import_base(opt.srcpath);
    read_source_into_input(fd);
    source_capture(opt.srcpath != nil ? opt.srcpath : "<stdin>", input_buf, input_len);
    source_init(opt.srcpath != nil ? opt.srcpath : "<stdin>", input_buf);
    load_dependencies_or_exit();
    resolve_imports_or_exit();
    prescan();
    parse_typecheck_emit_or_exit(opt);
    exits(nil);
    return 0;
}
