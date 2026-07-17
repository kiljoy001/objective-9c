%%

typename:
    type_expr { $$ = type_node($1); }
    ;

name_ref:
    TIDENT { $$ = $1; }
    | TQIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TENUMIDENT { $$ = $1; }
    ;

type_name_ref:
    TTYPEIDENT { $$ = $1; }
    ;

decl_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

generic_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

enum_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TENUMIDENT { $$ = $1; }
    ;

member_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TENUMIDENT { $$ = $1; }
    ;

spawn_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    ;

dep_name:
    TIDENT { $$ = $1; }
    | TTYPEIDENT { $$ = $1; }
    | TSTRINGLIT { $$ = mk(NIdent, $1, nil, nil, nil); }
    ;

dep_list:
    /* empty */ { $$ = nil; }
    | dep_list dep_name { $$ = append_node($1, mk(NIdent, $2->name, nil, nil, nil)); }
    | dep_list ',' { $$ = $1; }
    | dep_list ';' { $$ = $1; }
    ;

type_expr:
    type_primary { $$ = $1; }
    | type_expr '*' { $$ = type_ptr($1); }
    | type_expr '[' ']' { $$ = type_array($1); }
    ;

type_primary:
    type_name_ref type_args_opt
    {
        Type *base;

        base = type_from_name($1->name);
        if($2 != nil)
            $$ = type_apply(base->name, $2);
        else
            $$ = base;
    }
    | TTYPE { $$ = type_name($1->name); }
    | TLIST '<' type_args '>' { $$ = type_apply("List", $3); }
    | TDICT '<' type_args '>' { $$ = type_apply("Dict", $3); }
    | TTASK '<' type_args '>' { $$ = type_apply("Task", $3); }
    | '(' type_args ')' {
        if(type_list_len($2) == 1)
            $$ = $2->type;
        else
            $$ = type_apply("Tuple", $2);
    }
    ;

type_args_opt:
    /* empty */ { $$ = nil; }
    | '<' type_args '>' { $$ = $2; }
    ;

type_args:
    type_expr { $$ = type_list($1); }
    | type_args ',' type_expr { $$ = type_list_append($1, $3); }
    ;

program:
    /* empty */ { ast_root = nil; }
    | top_levels { ast_root = $1; }
    ;

top_levels:
    top_level { $$ = $1; }
    | top_levels top_level {
        $$ = append_node($1, $2);
    }
    ;

top_level:
    class_decl
    | interface_decl
    | struct_decl
    | enum_decl
    | module_decl
    | import_decl
    | object_decl
    | main_decl
    | func_top_level
    | function_decl
    ;

module_head:
    TMODULE name_ref '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        push_module($2->name);
        $$ = mk(NModule, name, nil, nil, nil);
        set_node_names($$, source, name);
    }
    ;

module_decl:
    module_head top_levels '}'
    {
        pop_module();
        $$ = $1;
        $$->left = $2;
    }
    | module_head '}'
    {
        pop_module();
        $$ = $1;
    }
    ;

import_decl:
    TIMPORT TSTRINGLIT ';'
    {
        $$ = mk(NImport, $2, nil, nil, nil);
    }
    ;

object_decl:
    TOBJECT typename member_name ';'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $3->name);
        name = mangle_source_name(source);
        $$ = mk_typed(NObject, name, $2, nil, nil);
        set_node_names($$, source, name);
        add_object_sym($$);
    }
    ;

main_decl:
    TMAIN '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, "main", typed_node_from_name("void"), $3, nil);
        $$->flags |= NFMain;
    }
    ;

func_top_level:
    TFUNC TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $6, nil);
    }
    ;

/* `function name(params) type { body }` — desugars to a templated class
 * (fixed spawn skeleton + the one user method `run`). See docs/CONCURRENCY.md. */
function_decl:
    TFUNCTION TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        char *fname = current_parse_class_source != nil ?
            join_module_name(current_parse_class_source, $2->name) : $2->name;
        $$ = synth_function_class(fname, $6, $4, $8);
    }
    | TFUNCTION TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        char *fname = current_parse_class_source != nil ?
            join_module_name(current_parse_class_source, $2->name) : $2->name;
        $$ = synth_function_class(fname, nil, $4, $7);
    }
    ;

abstract_opt:
    /* empty */ { $$ = nil; }
    | TABSTRACT { $$ = mk(NIdent, "abstract", nil, nil, nil); }
    ;

class_head:
    abstract_opt TCLASS decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $3->name);
        name = mangle_source_name(source);
        $$ = mk(NClass, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $4;
        if($1 != nil)
            $$->flags |= NFAbstract;
        push_type_params($4);
        push_parse_class(source);
    }
    ;

class_decl:
    class_head member_list '}'
    {
        pop_parse_class();
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

interface_head:
    TINTERFACE decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        $$ = mk(NInterface, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $3;
        push_type_params($3);
    }
    ;

interface_decl:
    interface_head member_list '}'
    {
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

struct_head:
    TSTRUCT decl_name generic_opt '{'
    {
        char *source, *name;

        source = qualify_source_name(current_module, $2->name);
        name = mangle_source_name(source);
        $$ = mk(NStruct, name, nil, nil, nil);
        set_node_names($$, source, name);
        $$->params = $3;
        push_type_params($3);
    }
    ;

struct_decl:
    struct_head member_list '}'
    {
        pop_type_params();
        $$ = $1;
        $$->left = $2;
        add_class($$->name, $$);
    }
    ;

generic_opt:
    /* empty */ { $$ = nil; }
    | '<' generic_names '>' { $$ = $2; }
    ;

generic_names:
    generic_name { $$ = mk(NTypeParam, $1->name, nil, nil, nil); }
    | generic_names ',' generic_name { $$ = append_node($1, mk(NTypeParam, $3->name, nil, nil, nil)); }
    ;

enum_decl:
    TENUM decl_name '{' enum_vals '}'
    {
        char *source = qualify_source_name(current_module, $2->name);
        char *name = qualify_type_name($2->name);
        $$ = mk(NEnum, name, nil, $4, nil);
        set_node_names($$, source, name);
        add_class(name, $$);
        register_enum_values(source, name, $4);
    }
    | TENUM decl_name '{' enum_vals ',' '}'
    {
        char *source = qualify_source_name(current_module, $2->name);
        char *name = qualify_type_name($2->name);
        $$ = mk(NEnum, name, nil, $4, nil);
        set_node_names($$, source, name);
        add_class(name, $$);
        register_enum_values(source, name, $4);
    }
    ;

enum_vals:
    enum_val { $$ = $1; }
    | enum_vals ',' enum_val { $$ = append_node($1, $3); }
    ;

enum_val:
    enum_name { $$ = mk(NEnumVal, $1->name, nil, nil, nil); }
    ;

member_list:
    /* empty */ { $$ = nil; }
    | member_list member {
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

member:
    member_body            { $$ = $1; }
    | TPUBLIC member_body  { $$ = $2; }  /* public is the default; explicit form */
    | TPRIVATE member_body {
        /* class-scoped: not reachable through the app facade, callable
         * only from the declaring class's own methods.  A secret field
         * desugars to a small list (blob + seal/open); mark every node
         * in it private so the accessors are private too. */
        Node *n;
        for(n = $2; n != nil; n = n->next)
            n->flags |= NFPrivate;
        $$ = $2;
    }
    ;

member_body:
    var_decl
    | function_decl
    | func_decl
    | method_decl
    | state_decl
    | prop_decl
    | atomic_decl
    | stream_decl
    | secret_decl
    | cap_decl
    | inherit_decl
    | destructor_decl
    ;

state_decl:
    TSTATE typename member_name ';'
    {
        $$ = mk_typed(NState, $3->name, $2, nil, nil);
    }
    ;

prop_decl:
    TPROP typename member_name ';'
    {
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
    }
    ;

atomic_decl:
    TATOMIC typename member_name ';'
    {
        /* `atomic` is not a user-facing field type. The runtime uses
         * 9front atomics internally for ARC/tasks/counters, but language
         * concurrency is actors, spawn/Task, streams, and 9P sessions. */
        fprint(2, "o9c: error: 'atomic' is not a language keyword. "
            "Use object dispatch/streams/spawn for concurrency; low-level "
            "atomics are internal runtime machinery or raw C in a function.\n");
        semantic_errors++;
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
    }
    ;

stream_decl:
    TSTREAM TIDENT ';'
    {
        $$ = mk(NStream, $2->name, nil, nil, nil);
    }
    | TSTREAM '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $5->name, $3, nil, nil);
    }
    | TCHAN '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $5->name, $3, nil, nil);
    }
    | TIDENT TSTREAM TIDENT ';'
    {
        $$ = mk(NStream, $3->name, nil, nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TSTREAM '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $6->name, $4, nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TCHAN member_name ';'
    {
        $$ = mk_typed(NStream, $3->name, typed_node_from_name("chan"), nil, nil);
        set_channel_dir($$, $1);
    }
    | TIDENT TCHAN '<' typename '>' member_name ';'
    {
        $$ = mk_typed(NStream, $6->name, $4, nil, nil);
        set_channel_dir($$, $1);
    }
    ;

secret_decl:
    TSECRET typename member_name ';'
    {
        $$ = mk_secret_field($2, $3->name);
    }
    ;

cap_decl:
    TCAP typename member_name ';'
    {
        /* `cap` is removed — and not reserved for later. Capabilities
         * are already provided one layer down: a 9P fid / namespace mount
         * IS an unforgeable handle to a resource, granted, delegated, and
         * attenuated by namespace composition, over pubkey identity. A
         * language-level `cap` field would duplicate (or fight) that OS
         * mechanism — un-o9. Authority to reach an object = whether it's
         * in your namespace; a bearer token = a `secret` field + a check.
         * There is no gap for a `cap` keyword to fill. */
        fprint(2, "o9c: error: 'cap' is not a language keyword. "
            "Capabilities in o9 are 9P fids / namespace mounts (an "
            "unforgeable handle granted by whoever mounts it), over "
            "pubkey identity — not a field type. Use a namespace mount "
            "for authority, or a `secret` field for a bearer token.\n");
        semantic_errors++;
        $$ = mk_typed(NProp, $3->name, $2, nil, nil);
    }
    ;

/*
 * C#-style method declaration.
 * Return type first:  method int64 getValue() { return val; }
 * No return type (void implied):  method inc(int64 n) { val += n; }
 * Expression body:  method int64 double() => val * 2;
 * Backward compat:  method inc() { }
 */
method_decl:
    TABSTRACT TMETHOD typename member_name '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $4->name, $3, nil, $6);
        $$->flags |= NFAbstract|NFMethodDecl;
    }
    | TABSTRACT TMETHOD TIDENT '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $3->name, typed_node_from_name("void"), nil, $5);
        $$->flags |= NFAbstract|NFMethodDecl;
    }
    |
    TMETHOD typename member_name '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $3->name, $2, $8, $5);
    }
    | TMETHOD typename member_name '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $8, nil);
        $$ = mk_typed(NMethod, $3->name, $2, body, $5);
    }
    | TMETHOD typename member_name '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $3->name, $2, nil, $5);
        $$->flags |= NFMethodDecl;
    }
    | TMETHOD TIDENT '(' param_list ')' '{' stmt_list '}'
    {
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $7, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' TARROW expr ';'
    {
        Node *body = mk(NReturn, nil, nil, $7, nil);
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), body, $4);
    }
    | TMETHOD TIDENT '(' param_list ')' ';'
    {
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), nil, $4);
        $$->flags |= NFMethodDecl;
    }
    | TMETHOD TTYPEIDENT '(' param_list ')' '{' stmt_list '}'
    {
        /* Constructor: class names lex as TTYPEIDENT (prescan registers them),
         * so method Counter(...) never matches the TIDENT rules above. */
        $$ = mk_typed(NMethod, $2->name, typed_node_from_name("void"), $7, $4);
    }
    ;

inherit_decl:
    typename ';'
    {
        $$ = mk_typed(NInherit, $1->name, $1, nil, nil);
    }
    ;

var_decl:
    typename member_name ';'
    {
        $$ = mk_typed(NProp, $2->name, $1, nil, nil);
    }
    | TCHAN TIDENT ';'
    {
        $$ = mk_typed(NStream, $2->name, typed_node_from_name("chan"), nil, nil);
    }
    ;

func_decl:
    TFUNC '(' typename TIDENT ')' TIDENT '(' param_list ')' typename '{' stmt_list '}'
    {
        Node *params = $8;
        Node *stmts = $12;
        $$ = mk_typed(NMethod, $6->name, $10, stmts, params);
    }
    ;

param_list:
    /* empty */ { $$ = nil; }
    | param { $$ = $1; }
    | param_list ',' param {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

param:
    typename member_name
    {
        $$ = mk_typed(NProp, $2->name, $1, nil, nil);
    }
    ;

destructor_decl:
    '~' TIDENT '(' ')' '{' stmt_list '}'
    {
        $$ = mk(NDestructor, $2->name, nil, $6, nil);
    }
    | '~' TTYPEIDENT '(' ')' '{' stmt_list '}'
    {
        /* Class names lex as TTYPEIDENT (prescan registers them) */
        $$ = mk(NDestructor, $2->name, nil, $6, nil);
    }
    ;

stmt_list:
    /* empty */ { $$ = nil; }
    | stmt_list stmt {
        if($1 == nil) $$ = $2;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $2;
            $$ = $1;
        }
    }
    ;

stmt:
    typename member_name ';' { $$ = mk_typed(NLocalVar, $2->name, $1, nil, nil); note_var_class_type($2->name, $1->typeinfo); }
    | typename member_name TEQ expr ';' { $$ = mk_typed(NLocalVar, $2->name, $1, $4, nil); note_var_class_type($2->name, $1->typeinfo); }
    | locality typename member_name TEQ expr '@' expr ';' {
        $$ = mk_typed(NLocalVar, $3->name, $2, $5, nil);
        $$->cname = strdup($1->name);	/* locality tag for this declaration */
        $$->params = $7;		/* address expression after @ */
        note_var_class_type($3->name, $2->typeinfo);
    }
    | expr ';' { $$ = $1; }
    | TRETURN expr ';' { $$ = mk(NReturn, nil, nil, $2, nil); }
    | TDEFER expr ';' { $$ = mk(NDefer, nil, nil, $2, nil); }
    | TDELETE TIDENT ';' { $$ = mk(NDelete, $2->name, nil, $2, nil); }
    | TPRINT '(' call_args ')' ';' {
        $$ = mk(NFuncCall, "print", nil, $3, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' { $$ = mk(NIf, nil, nil, $3, $6); }
    | TIF '(' expr ')' '{' stmt_list '}' TELSE '{' stmt_list '}' {
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElse, nil, nil, $10, nil);
    }
    | TIF '(' expr ')' '{' stmt_list '}' TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NIfElse, nil, nil, $3, $6);
        $$->next = mk(NElseIf, nil, nil, $10, $13);
        if($15) $$->next->next = $15;
    }
    | TWHILE '(' expr ')' '{' stmt_list '}' { $$ = mk(NWhile, nil, nil, $3, $6); }
    | TFOR '(' for_init TFORSEMI for_cond TFORSEMI for_step ')' '{' stmt_list '}' { $$ = mk(NFor, nil, nil, $3, mk(NFor, nil, nil, $5, $7)); $$->right->next = $10; }
    | alt_stmt { $$ = $1; }
    | TUSE '{' dep_list '}' { $$ = mk(NUse, nil, nil, $3, nil); }
    | TRAWC { $$ = mk(NRawC, $1, nil, nil, nil); }
    ;

alt_stmt:
    TALT '{' alt_cases '}'
    {
        $$ = mk(NAlt, nil, nil, $3, nil);
    }
    ;

alt_cases:
    alt_case { $$ = $1; }
    | alt_cases alt_case { $$ = append_node($1, $2); }
    ;

alt_case:
    TCASE expr TEQ TCHANRECV expr ':' stmt_list
    {
        $$ = mk(NAltCase, nil, nil, mk(NChanRecv, nil, nil, $2, $5), $7);
    }
    | TDEFAULT ':' stmt_list
    {
        $$ = mk(NAltDefault, nil, nil, $3, nil);
    }
    ;

for_init:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_cond:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

for_step:
    expr { $$ = $1; }
    | /* empty */ { $$ = nil; }
    ;

else_clause:
    /* empty */ { $$ = nil; }
    | TELSE '{' stmt_list '}' { $$ = mk(NElse, nil, nil, $3, nil); }
    | TELIF '(' expr ')' '{' stmt_list '}' else_clause {
        $$ = mk(NElseIf, nil, nil, $3, $6);
        $$->next = $8;
    }
    ;

locality:
    TNEAR { $$ = mk(NIdent, "near", nil, nil, nil); }
    | TFAR { $$ = mk(NIdent, "far", nil, nil, nil); }
    | TLISTENER { $$ = mk(NIdent, "listener", nil, nil, nil); }
    ;

expr:
    expr TCHANSEND expr { $$ = mk(NChanSend, nil, nil, $1, $3); }
    | expr TCHANTRY expr { $$ = mk(NChanTry, nil, nil, $1, $3); }
    | expr TEQ TCHANRECV expr { $$ = mk(NChanRecv, nil, nil, $1, $4); }
    | expr TEQ expr { $$ = mk(NAssign, nil, nil, $1, $3); }
    | expr TADD expr { $$ = mk(NAdd, nil, nil, $1, $3); }
    | expr TSUB expr { $$ = mk(NSub, nil, nil, $1, $3); }
    | expr '*' expr { $$ = mk(NMul, nil, nil, $1, $3); }
    | expr '/' expr { $$ = mk(NDiv, nil, nil, $1, $3); }
    | expr '%' expr { $$ = mk(NMod, nil, nil, $1, $3); }
    | expr TEQEQ expr { $$ = mk(NEq, nil, nil, $1, $3); }
    | expr TNEQ expr { $$ = mk(NNe, nil, nil, $1, $3); }
    | expr '<' expr { $$ = mk(NLt, nil, nil, $1, $3); }
    | expr TLE expr { $$ = mk(NLe, nil, nil, $1, $3); }
    | expr '>' expr { $$ = mk(NGt, nil, nil, $1, $3); }
    | expr TGE expr { $$ = mk(NGe, nil, nil, $1, $3); }
    | expr TAND expr { $$ = mk(NAnd, nil, nil, $1, $3); }
    | expr TOR expr { $$ = mk(NOr, nil, nil, $1, $3); }
    | expr '&' expr { $$ = mk(NBitAnd, nil, nil, $1, $3); }
    | expr '|' expr { $$ = mk(NBitOr, nil, nil, $1, $3); }
    | expr '^' expr { $$ = mk(NBitXor, nil, nil, $1, $3); }
    | expr TLSHIFT expr { $$ = mk(NLshift, nil, nil, $1, $3); }
    | expr TRSHIFT expr { $$ = mk(NRshift, nil, nil, $1, $3); }
    | '!' expr { $$ = mk(NNot, nil, nil, $2, nil); }
    | '~' expr { $$ = mk(NBitNot, nil, nil, $2, nil); }
    | TSUB expr %prec UMINUS { $$ = mk(NNeg, nil, nil, $2, nil); }
    | expr '.' member_name {
        $$ = mk(NPropRead, $3->name, nil, $1, nil);
    }
    | expr '.' member_name '(' call_args ')' {
        $$ = mk(NMsgSend, $3->name, nil, $1, $5);
    }
    | expr '[' expr ']' {
        $$ = mk(NArrayGet, nil, nil, $1, $3);
    }
    | TIDENT '(' call_args ')' {
        /* Bare call: sibling method on the enclosing class (implicit self) */
        $$ = mk(NSelfCall, $1->name, nil, nil, $3);
    }
    | TIDENT { $$ = enum_expr_or_ident($1); }
    | TQIDENT { $$ = enum_expr_or_ident($1); }
    | TENUMIDENT { $$ = enum_expr_or_ident($1); }
    | TINTLIT { $$ = mk(NIntLit, $1, nil, nil, nil); }
    | TDOUBLELIT { $$ = mk(NDoubleLit, $1, nil, nil, nil); }
    | TSTRINGLIT { $$ = mk(NStringLit, $1, nil, nil, nil); }
    | TCHARLIT { $$ = mk(NCharLit, $1, nil, nil, nil); }
    | TTRUE { $$ = mk(NBoolLit, "1", nil, nil, nil); }
    | TFALSE { $$ = mk(NBoolLit, "0", nil, nil, nil); }
    | TNIL { $$ = mk(NBoolLit, "nil", nil, nil, nil); }
    | TTRY expr {
        /* try expr: propagate the callee's error out of this method */
        Node *n = mk(NTry, nil, nil, $2, nil);
        n->typeinfo = $2->typeinfo;	/* try yields the success value's type */
        $$ = n;
    }
    | TNEW typename '(' call_args ')' {
        Node *n = mk(NClass, $2->name, "same", nil, nil);
        n->typeinfo = $2->typeinfo;
        n->left = $2;
        n->right = $4;
        $$ = n;
    }
    /* spawn f(args): run function-class f concurrently; evaluates to a
     * Task<T> (join handle). name = function, right = args. */
    | TSPAWN spawn_name '(' call_args ')' {
        Node *n = mk(NSpawn, $2->name, nil, nil, $4);
        $$ = n;
    }
    | TCAST '<' type_expr '>' '(' expr ')' {
        Node *tn = type_node($3);
        $$ = mk_typed(NCast, "cast", tn, $6, nil);
    }
    | TNEW TNEAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "near", nil, nil);
        n->typeinfo = $3->typeinfo;
        n->left = $3;
        n->right = $5;
        $$ = n;
    }
    | TNEW TFAR typename '(' call_args ')' {
        Node *n = mk(NClass, $3->name, "far", nil, nil);
        n->typeinfo = $3->typeinfo;
        n->left = $3;
        n->right = $5;
        $$ = n;
    }
    | '(' call_args ')' {
        if(node_list_len($2) == 1)
            $$ = $2;
        else
            $$ = mk(NTupleLit, nil, nil, $2, nil);
    }
    ;

call_args:
    /* empty */ { $$ = nil; }
    | call_arg { $$ = $1; }
    | call_args ',' call_arg {
        if($1 == nil) $$ = $3;
        else {
            Node *n = $1;
            while(n->next) n = n->next;
            n->next = $3;
            $$ = $1;
        }
    }
    ;

call_arg:
    expr { $$ = $1; }
    ;
