/* ========================================================================
 * YACC TOKENS AND GRAMMAR
 * ======================================================================== */

%union {
    Node *node;
    char *name;
    Type *type;
    TypeList *types;
}

%token <node> TIDENT TTYPE TQIDENT TTYPEIDENT TENUMIDENT
%token <name> TINTLIT TSTRINGLIT TCHARLIT TRAWC
%token <name> TDOUBLELIT
%token TCLASS TINTERFACE TSTRUCT TENUM TMODULE TIMPORT TFUNC TFUNCTION TMAIN TMETHOD TRETURN TCHAN TIF TELSE TELIF TWHILE TFOR TNEW TPRINT TNEAR TFAR TLISTENER TDICT TLIST TTASK TNIL TABSTRACT TDELETE TSPAWN TCAST TUSE
%token TALT TCASE TDEFAULT
%token TSTATE TPROP TATOMIC TSTREAM TSECRET TCAP TOBJECT TTRUE TFALSE TARROW
%token TPUBLIC TPRIVATE
%token TTRY TDEFER
%token TEQ TADD TSUB TCHANSEND TCHANRECV TCHANTRY TEQEQ TNEQ TLE TGE
%token TAND TOR TLSHIFT TRSHIFT TFORSEMI

%left TEQ
%left TCHANSEND TCHANTRY
%right TCHANRECV
%left TOR
%left TAND
%left '|'
%left '^'
%left '&'
%left TEQEQ TNEQ
%left '<' '>' TLE TGE
%left TLSHIFT TRSHIFT
%left TADD TSUB
%left '*' '/' '%'
%right '!' '~' UMINUS
%right TTRY
%left '.' '['

%type <node> program top_levels top_level class_decl class_head interface_decl interface_head struct_decl struct_head enum_decl enum_vals enum_val module_decl module_head import_decl object_decl member_list member member_body var_decl func_decl inherit_decl destructor_decl stmt_list stmt expr method_decl state_decl prop_decl atomic_decl stream_decl secret_decl cap_decl typename name_ref type_name_ref decl_name generic_name enum_name member_name spawn_name dep_name dep_list param_list param call_args call_arg main_decl func_top_level function_decl for_init for_cond for_step else_clause generic_opt generic_names abstract_opt alt_stmt alt_cases alt_case locality
%type <type> type_expr type_primary
%type <types> type_args type_args_opt

%start program
