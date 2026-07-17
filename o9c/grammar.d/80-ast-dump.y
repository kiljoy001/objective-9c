/* ========================================================================
 * AST DUMP
 * ======================================================================== */

static char*
node_kind(int type)
{
    static char *names[NNodeKinds] = {
        "NClass",
        "NProp",
        "NState",
        "NStream",
        "NSecret",
        "NCap",
        "NInherit",
        "NMethod",
        "NDestructor",
        "NIdent",
        "NType",
        "NChanSend",
        "NChanRecv",
        "NChanTry",
        "NAssign",
        "NReturn",
        "NIntLit",
        "NDoubleLit",
        "NStringLit",
        "NCharLit",
        "NBoolLit",
        "NAdd",
        "NSub",
        "NMul",
        "NDiv",
        "NMod",
        "NEq",
        "NNe",
        "NLt",
        "NLe",
        "NGt",
        "NGe",
        "NAnd",
        "NOr",
        "NBitAnd",
        "NBitOr",
        "NBitXor",
        "NLshift",
        "NRshift",
        "NNot",
        "NBitNot",
        "NNeg",
        "NIf",
        "NIfElse",
        "NElse",
        "NElseIf",
        "NWhile",
        "NLocalVar",
        "NMsgSend",
        "NPropRead",
        "NFuncCall",
        "NFor",
        "NArrayGet",
        "NArraySet",
        "NInterface",
        "NStruct",
        "NEnum",
        "NEnumVal",
        "NImport",
        "NObject",
        "NLink",
        "NModule",
        "NTypeParam",
        "NSelfCall",
        "NDelete",
        "NTry",
        "NDefer",
        "NSpawn",
        "NCast",
        "NRawC",
        "NUse",
        "NAlt",
        "NAltCase",
        "NAltDefault",
        "NTupleLit",
    };

    if(type >= 0 && type < NNodeKinds && names[type] != nil)
        return names[type];
    return "NUnknown";
}

static void
dump_indent(int depth)
{
    int i;

    for(i = 0; i < depth; i++)
        print("  ");
}

static void
dump_params(Node *params)
{
    Node *p;
    int first;

    if(params == nil)
        return;
    print(" params=");
    first = 1;
    for(p = params; p; p = p->next){
        if(!first)
            print(",");
        if(p->name != nil)
            print("%s", p->name);
        first = 0;
    }
}

static void
dump_node_line(Node *n, int depth, char *label)
{
    char *rendered, *dumped;

    dump_indent(depth);
    if(label != nil)
        print("%s ", label);
    print("%s", node_kind(n->type));
    if(n->name != nil)
        print(" name=%s", n->name);
    if(n->typename != nil)
        print(" typename=%s", n->typename);
    if(n->flags & NFAbstract)
        print(" abstract");
    if(n->flags & NFChanSendOnly)
        print(" sendonly");
    if(n->flags & NFChanRecvOnly)
        print(" recvonly");
    if(n->qname != nil)
        print(" qname=%s", n->qname);
    if(n->cname != nil)
        print(" cname=%s", n->cname);
    dump_params(n->params);
    if(n->typeinfo != nil){
        rendered = type_render(n->typeinfo);
        dumped = type_dump(n->typeinfo);
        print(" type=%s typedump=%s", rendered, dumped);
    }
    if(n->line > 0)
        print(" line=%d", n->line);
    print("\n");
}

static void
dump_ast_nodes(Node *n, int depth, char *label)
{
    for(; n; n = n->next){
        dump_node_line(n, depth, label);
        if(n->left != nil)
            dump_ast_nodes(n->left, depth + 1, "left");
        if(n->right != nil)
            dump_ast_nodes(n->right, depth + 1, "right");
    }
}

static void
dump_ast(Node *root)
{
    dump_ast_nodes(root, 0, nil);
}
