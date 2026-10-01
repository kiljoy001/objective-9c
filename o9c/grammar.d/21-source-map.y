/* Source locations survive import splicing. Entries are indexed by the
 * physical line in input_buf; AST nodes retain the original file and line. */
typedef struct SourceLoc SourceLoc;
struct SourceLoc {
	char *file;
	int line;
};

static SourceLoc *sources, *sourcebuild;
static int nsources, nsourcebuild, sourcecap;
static SourceLoc csource;
static int ccontinuous, cbol = 1, cmapped, cneedline;

typedef struct SourceFile SourceFile;
struct SourceFile {
	char *path;
	char *text;
	long len;
};

static SourceFile *sourcefiles;
static int nsourcefiles;

/* Snapshot bytes before import splicing or imported-main removal. */
static void
source_capture(char *path, char *text, long len)
{
	SourceFile *f;
	int i;

	for(i = 0; i < nsourcefiles; i++)
		if(strcmp(sourcefiles[i].path, path) == 0)
			return;
	sourcefiles = realloc(sourcefiles, (nsourcefiles+1)*sizeof *sourcefiles);
	if(sourcefiles == nil)
		sysfatal("malloc: source files");
	f = &sourcefiles[nsourcefiles++];
	f->path = strdup(path);
	f->text = malloc(len+1);
	if(f->path == nil || f->text == nil)
		sysfatal("malloc: source snapshot");
	memmove(f->text, text, len);
	f->text[len] = 0;
	f->len = len;
}

static SourceLoc
source_at(int line)
{
	SourceLoc loc;

	loc.file = nil;
	loc.line = 0;
	if(line > 0 && line < nsources)
		loc = sources[line];
	return loc;
}

static void
node_source(Node *n, int line)
{
	SourceLoc loc;

	loc = source_at(line);
	n->sourcefile = loc.file;
	n->sourceline = loc.line;
}

static void
copy_source(Node *to, Node *from)
{
	to->sourcefile = from->sourcefile;
	to->sourceline = from->sourceline;
}

static void
source_add(SourceLoc loc)
{
	if(nsourcebuild == sourcecap){
		sourcecap = sourcecap == 0 ? 128 : sourcecap*2;
		sourcebuild = realloc(sourcebuild, sourcecap*sizeof *sourcebuild);
		if(sourcebuild == nil)
			sysfatal("malloc: source map");
	}
	sourcebuild[nsourcebuild++] = loc;
}

static void
source_begin(void)
{
	SourceLoc loc;

	nsourcebuild = 0;
	loc.file = nil;
	loc.line = 0;
	source_add(loc);
	source_add(loc);	/* empty line before the first splice */
}

static void
source_append(SourceLoc loc, char *text, long len)
{
	long i;

	source_add(loc);	/* splice_append inserts a newline first */
	for(i = 0; i < len; i++){
		if(text[i] == '\n'){
			loc.line++;
			source_add(loc);
		}
	}
}

static void
source_commit(void)
{
	free(sources);
	sources = sourcebuild;
	nsources = nsourcebuild;
	sourcebuild = nil;
	nsourcebuild = 0;
	sourcecap = 0;
}

static void
source_discard(void)
{
	free(sourcebuild);
	sourcebuild = nil;
	nsourcebuild = 0;
	sourcecap = 0;
}

static void
source_init(char *file, char *text)
{
	SourceLoc loc;

	loc.file = strdup(file);
	loc.line = 0;
	source_add(loc);
	loc.line = 1;
	source_add(loc);
	for(; *text; text++){
		if(*text == '\n'){
			loc.line++;
			source_add(loc);
		}
	}
	source_commit();
}

static void
csetsource(SourceLoc loc, int continuous)
{
	/* Locations change only at statement/raw-block boundaries. Finish the
	 * preceding generated line before issuing a preprocessor directive. */
	if(!cbol)
		cprint("\n");
	csource = loc;
	ccontinuous = continuous;
	cneedline = 1;
}

static void source_comment(Node*);

static void
cnode(Node *n)
{
	SourceLoc loc;

	source_comment(n);
	loc.file = n->sourcefile;
	loc.line = n->sourceline;
	csetsource(loc, 0);
}

static void
cfileline(SourceLoc loc)
{
	/* Plan 9 cc reads this filename literally, without C string escapes. */
	if(strchr(loc.file, '"') != nil || strchr(loc.file, '\n') != nil ||
	   strchr(loc.file, '\r') != nil)
		sysfatal("source path cannot be represented in a Plan 9 #line directive");
	/* libmach applies a history record after its recorded line boundary.
	 * A spacer puts code beyond that boundary; subtract it from #line so
	 * both cc diagnostics and debugger PCs retain the original line. */
	if(loc.line > 1){
		print("#line %d \"%s\"\n\n", loc.line-1, loc.file);
	}else{
		print("#line %d \"%s\"\n", loc.line, loc.file);
	}
}

/* Pin every generated line for a statement to its original source line.
 * One directive per statement is insufficient: lowering can emit dozens of
 * C lines. Raw C advances normally; generated scaffolding has its own name. */
static void
cprint(char *fmt, ...)
{
	va_list args;
	char *text, *p, *end;
	SourceLoc generated;
	long n;

	va_start(args, fmt);
	text = vsmprint(fmt, args);
	va_end(args);
	if(text == nil)
		sysfatal("malloc: generated C");
	for(p = text; *p; p = end){
		if(cbol){
			if(csource.file != nil && csource.line > 0){
				if(!ccontinuous || cneedline)
					cfileline(csource);
				cmapped = 1;
			}else if(cmapped){
				generated.file = "<o9-generated>";
				generated.line = 1;
				cfileline(generated);
				cmapped = 0;
			}
			cneedline = 0;
		}
		end = strchr(p, '\n');
		if(end != nil)
			end++;
		else
			end = p + strlen(p);
		n = end - p;
		if(write(1, p, n) != n)
			sysfatal("write generated C: %r");
		cbol = end[-1] == '\n';
		if(cbol && ccontinuous)
			csource.line++;
	}
	free(text);
}

/* Comments are emitted outside source mapping, then #line is restored for
 * the actual C. Never insert annotations within a verbatim raw-C body. */
static void
comment_text(char *text, long len)
{
	char *copy;
	long i, start;
	int ch;

	/* Plan 9 %.*s precision counts runes, not bytes. Bound each slice
	 * with NUL so UTF-8 cannot copy beyond the checked comment text. */
	copy = malloc(len+1);
	if(copy == nil)
		sysfatal("malloc: source comment");
	memmove(copy, text, len);
	copy[len] = 0;
	start = 0;
	for(i = 0; i < len; i++){
		ch = (uchar)text[i];
		if((ch == '*' && i+1 < len && text[i+1] == '/') ||
		   ch == '\r' || (ch < ' ' && ch != '\t') || ch == 127){
			copy[i] = 0;
			cprint("%s", copy+start);
			copy[i] = ch;
			if(ch == '*'){
				cprint("* /");
				i++;
			}else if(ch == '\r')
				cprint("\\r");
			else
				cprint("\\x%2.2ux", ch);
			start = i+1;
		}
	}
	cprint("%s", copy+start);
	free(copy);
}

static void
source_comment(Node *n)
{
	SourceFile *f;
	SourceLoc generated;
	long start, stop;
	int i, line;

	if(n->sourcefile == nil || n->sourceline < 1)
		return;
	for(i = 0; i < nsourcefiles; i++)
		if(strcmp(sourcefiles[i].path, n->sourcefile) == 0)
			break;
	if(i == nsourcefiles)
		return;
	f = &sourcefiles[i];
	start = 0;
	for(line = 1; start < f->len && line < n->sourceline; start++)
		if(f->text[start] == '\n')
			line++;
	for(stop = start; stop < f->len && f->text[stop] != '\n'; stop++)
		;
	while(start < stop && (f->text[start] == ' ' || f->text[start] == '\t'))
			start++;
	generated.file = nil;
	generated.line = 0;
	csetsource(generated, 0);
	cprint("\t/* o9: ");
	comment_text(f->path, strlen(f->path));
	cprint(":%d | ", n->sourceline);
	comment_text(f->text+start, stop-start);
	cprint(" */\n");
}

/* Keep the complete, numbered original text available in the C file for
 * multiline logic, imports, and source statements lowered to many C lines.
 * It remains a comment, with no data emitted into the executable. */
static void
source_comments(void)
{
	SourceFile *f;
	SourceLoc generated;
	long start, stop;
	int i, line;

	generated.file = nil;
	generated.line = 0;
	csetsource(generated, 0);
	for(i = 0; i < nsourcefiles; i++){
		f = &sourcefiles[i];
		cprint("\n/* o9 source: ");
		comment_text(f->path, strlen(f->path));
		cprint("\n");
		for(start = 0, line = 1; start < f->len; start = stop+1, line++){
			for(stop = start; stop < f->len && f->text[stop] != '\n'; stop++)
				;
			cprint(" * %d | ", line);
			comment_text(f->text+start, stop-start);
			cprint("\n");
		}
		cprint(" */\n");
	}
}
