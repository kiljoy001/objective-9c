/* Runtime mutation of one typed source expression. Source files stay intact. */
typedef struct Mutant Mutant;
struct Mutant {
	Node *node;
	int replacement;
	char *value;
	char *from;
	char *to;
};

typedef struct MutantLine MutantLine;
struct MutantLine {
	int line;
	int count;
};

static MutantLine *mutantlines;
static int nmutantlines;
static int nmutants;
static int chosenline;
static int chosenordinal;
static int listmutants;
static char *mutantsource;
static int mutantfound;

static void
mutant_id(char *s)
{
	char *end;
	long n;

	if(s == nil || *s == 0)
		return;
	n = strtol(s, &end, 10);
	if(*end != '.' || n < 1 || n > 1000000)
		sysfatal("invalid mutant ID: %s", s);
	chosenline = n;
	n = strtol(end+1, &end, 10);
	if(*end != 0 || n < 1 || n > 1000000)
		sysfatal("invalid mutant ID: %s", s);
	chosenordinal = n;
}

static int
mutant_ordinal(int line)
{
	int i;

	for(i = 0; i < nmutantlines; i++)
		if(mutantlines[i].line == line)
			return ++mutantlines[i].count;
	mutantlines = realloc(mutantlines, (nmutantlines+1)*sizeof *mutantlines);
	if(mutantlines == nil)
		sysfatal("malloc: mutant lines");
	mutantlines[nmutantlines].line = line;
	mutantlines[nmutantlines].count = 1;
	nmutantlines++;
	return 1;
}

static int
mutant_candidate(Node *n, Mutant *m)
{
	m->node = n;
	m->value = nil;
	switch(n->type){
	case NLt: m->replacement = NLe; m->from = "<"; m->to = "<="; break;
	case NLe: m->replacement = NLt; m->from = "<="; m->to = "<"; break;
	case NGt: m->replacement = NGe; m->from = ">"; m->to = ">="; break;
	case NGe: m->replacement = NGt; m->from = ">="; m->to = ">"; break;
	case NBoolLit:
		if(n->name == nil || (strcmp(n->name, "0") != 0 && strcmp(n->name, "1") != 0))
			return 0;
		m->replacement = NBoolLit;
		m->value = strcmp(n->name, "0") == 0 ? "1" : "0";
		m->from = strcmp(n->name, "0") == 0 ? "false" : "true";
		m->to = strcmp(n->name, "0") == 0 ? "true" : "false";
		break;
	default:
		return 0;
	}
	return 1;
}

static void
mutant_walk(Node *n)
{
	Mutant m;
	int ordinal;

	if(n == nil)
		return;
	if(n->sourcefile != nil && n->sourceline > 0 && mutantsource != nil &&
	   strcmp(n->sourcefile, mutantsource) == 0 &&
	   mutant_candidate(n, &m)){
		nmutants++;
		ordinal = mutant_ordinal(n->sourceline);
		if(listmutants)
			print("%d.%d\t%s\t%d\t%s\t%s\n", n->sourceline, ordinal,
				n->sourcefile, n->sourceline, m.from, m.to);
		if(n->sourceline == chosenline && ordinal == chosenordinal){
			n->type = m.replacement;
			if(m.value != nil)
				n->name = m.value;
			mutantfound = 1;
		}
	}
	mutant_walk(n->params);
	mutant_walk(n->left);
	mutant_walk(n->right);
	mutant_walk(n->next);
}

static void
mutate_or_list(Node *root)
{
	nmutants = 0;
	nmutantlines = 0;
	mutantfound = 0;
	mutant_walk(root);
	if(chosenline > 0 && !mutantfound){
		fprint(2, "o9c: mutant %d.%d not found in %s (%d candidates)\n",
			chosenline, chosenordinal, mutantsource, nmutants);
		exits("mutant");
	}
}
