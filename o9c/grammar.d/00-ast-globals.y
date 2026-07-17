%{
#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>
#include "o9_type.h"

/* ========================================================================
 * AST TYPES AND GLOBAL STATE
 * ======================================================================== */

typedef struct Node Node;
typedef struct TypeBind TypeBind;
typedef struct TypedMember TypedMember;

enum {
    NClass,
    NProp,
    NState,
    NStream,
    NSecret,
    NCap,
    NInherit,
    NMethod,
    NDestructor,
    NIdent,
    NType,
    NChanSend,
    NChanRecv,
    NChanTry,
    NAssign,
    NReturn,
    NIntLit,
    NDoubleLit,
    NStringLit,
    NCharLit,
    NBoolLit,
    NAdd,
    NSub,
    NMul,
    NDiv,
    NMod,
    NEq,
    NNe,
    NLt,
    NLe,
    NGt,
    NGe,
    NAnd,
    NOr,
    NBitAnd,
    NBitOr,
    NBitXor,
    NLshift,
    NRshift,
    NNot,
    NBitNot,
    NNeg,
    NIf,
    NIfElse,
    NElse,
    NElseIf,
    NWhile,
    NLocalVar,
    NMsgSend,
    NPropRead,
    NFuncCall,
    NFor,
    NArrayGet,
    NArraySet,
    NInterface,
    NStruct,
    NEnum,
    NEnumVal,
    NImport,
    NObject,
    NLink,
    NModule,
    NTypeParam,
    NSelfCall,
    NDelete,
    NTry,
    NDefer,
    NSpawn,
    NCast,
    NRawC,
    NUse,
    NAlt,
    NAltCase,
    NAltDefault,
    NTupleLit,
    NNodeKinds
};

enum {
    NFAbstract = 1<<0,
    NFMethodDecl = 1<<1,
    NFSelfCalled = 1<<2,
    NFPrivate = 1<<3,	/* class-scoped; not reachable through the app facade */
    NFFunction = 1<<4,	/* a synthesized function-class (fixed spawn template) */
    NFMain = 1<<5,	/* reserved top-level program bootstrap block */
    NFChanSendOnly = 1<<6,	/* public endpoint may send, not receive */
    NFChanRecvOnly = 1<<7	/* public endpoint may receive, not send */
};

struct Node {
    int type;
    int flags;
    int line;
    char *name;
    char *typename;
    char *qname;
    char *cname;
    Type *typeinfo;
    Node *params;
    Node *left;
    Node *right;
    Node *next;
};

struct TypeBind {
    char *name;
    Type *type;
    TypeBind *next;
};

struct TypedMember {
    Node *node;
    Node *owner;
    int kind;
    Type *type;
    TypeBind *bindings;
};

typedef struct ClassDef ClassDef;
typedef struct EnumSym EnumSym;
typedef struct ObjectSym ObjectSym;
typedef struct CDep CDep;
struct ClassDef {
    char *name;
    Node *node;
    ClassDef *next;
};
ClassDef *classes;
static int semantic_errors;
static int in_prescan;              /* 1 during prescan phase, 0 during parse */
static int cur_line = 1;            /* current source line for diagnostics */
static int sem_line;                /* line of the node being semantically checked */
static Node *gen_class;             /* class whose method body is being generated */
static Type *gen_return_type;        /* method return type while emitting body */
static char *parse_class_stack[32];
static int parse_class_depth;
static char *current_parse_class_source;
static char last_caps_ident[128];   /* capitalized ident not in type registry */
static int last_caps_line;

struct EnumSym {
    char *qname;
    char *membername;
    char *enumtype;
    char *cname;
    int value;
    EnumSym *next;
};
EnumSym *enum_syms;

struct ObjectSym {
    char *qname;
    char *cname;
    char *typename;
    Node *node;
    ObjectSym *next;
};
ObjectSym *object_syms;

struct CDep {
    char *name;
    char *header;
    char *include;
    char *archive;
    char *source;
    char *requires;
    int system;
    int override;
    int used;
    CDep *next;
    CDep *usednext;
};
CDep *cdeps;
CDep *used_cdeps;
CDep *used_cdeps_tail;
char *project_root = ".";

void
add_class(char *name, Node *n)
{
    ClassDef *c;
    for(c = classes; c; c = c->next){
        if(strcmp(c->name, name) == 0){
            c->node = n;
            return;
        }
    }
    c = malloc(sizeof(ClassDef));
    c->name = strdup(name);
    c->node = n;
    c->next = classes;
    classes = c;
}

Node*
find_class(char *name)
{
    ClassDef *c;
    for(c = classes; c; c = c->next)
        if(strcmp(c->name, name) == 0) return c->node;
    return nil;
}

Node* mk(int type, char *name, char *typename, Node *l, Node *r);
static Node* mk_secret_field(Node *tn, char *name);
static Node* synth_function_class(char *fname, Node *rettn, Node *params, Node *body);
static void o9_note_registered(char *name);
static int member_exists(Node *cnode, char *name);
Node* append_node(Node *list, Node *node);
static Node* type_decl_node(Type *t);
static int validate_type(Type *t, int *errs);
char* type_storage_for_codegen(Type *t);
static Type* decl_typeinfo(Node *n);
static Node* typed_node_from_name(char *name);
static Node* member_node(Node *cnode, char *name, int method);
static int typed_member_lookup(Type *receiver, char *name, int method, TypedMember *out);
static int method_has_body(Node *m);
static Type* get_typeinfo_sym(char *name);
static void add_type_sym_typed(char *name, Type *typeinfo);
static char* type_slice(char *s, int n);
static char* qualify_type_name(char *name);
static char* qualify_source_name(char *module, char *name);
static char* mangle_source_name(char *name);
static int is_known_type_name(char *name);
static Type* type_from_name(char *name);
static Node* type_node(Type *type);
static Node* mk_typed(int type, char *name, Node *tn, Node *l, Node *r);
static void set_channel_dir(Node *n, Node *dir);
static void set_node_names(Node *n, char *qname, char *cname);
static Type* type_list_at(TypeList *list, int idx);
static void push_module(char *name);
static void pop_module(void);
static void push_type_params(Node *params);
static void pop_type_params(void);
static void add_enum_sym(char *enumsrc, char *enumtype, char *name, int value);
static EnumSym* resolve_enum_sym(char *name);
static Node* enum_expr_or_ident(Node *n);
static void add_object_sym(Node *n);
static Node* object_ref(Node *n);
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);
ulong o9_hash(char *str);
void  add_var_class(char *varname, char *classname);
static void load_builtin_cdeps(void);
static void load_project_cdeps(void);
static void use_cdep(char *name, int line, int *errs);
static void emit_cdeps(void);

int is_subclass(char *sub, char *parent);
