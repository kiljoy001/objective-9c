/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison implementation for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* C LALR(1) parser skeleton written by Richard Stallman, by
   simplifying the original so-called "semantic" parser.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output, and Bison version.  */
#define YYBISON 30802

/* Bison version string.  */
#define YYBISON_VERSION "3.8.2"

/* Skeleton name.  */
#define YYSKELETON_NAME "yacc.c"

/* Pure parsers.  */
#define YYPURE 0

/* Push parsers.  */
#define YYPUSH 0

/* Pull parsers.  */
#define YYPULL 1




/* First part of user prologue.  */
#line 1 "o9_plan9.y"

#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

typedef struct Node Node;

enum {
    NClass,
    NProp,
    NState,
    NAtomic,
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
    NWhile,
    NLocalVar,
    NMsgSend,
    NFuncCall
};

struct Node {
    int type;
    char *name;
    char *typename;
    Node *left;
    Node *right;
    Node *next;
};

typedef struct ClassDef ClassDef;
struct ClassDef {
    char *name;
    Node *node;
    ClassDef *next;
};
ClassDef *classes;

void
add_class(char *name, Node *n)
{
    ClassDef *c = malloc(sizeof(ClassDef));
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
void  yyerror(char *s);
int   yylex(void);
int   yyparse(void);
ulong o9_hash(char *str);
void  add_var_class(char *varname, char *classname);

Node *ast_root;

char*
map_type(char *t)
{
    if(t == nil) return "void";
    if(strcmp(t, "int64") == 0) return "vlong";
    if(strcmp(t, "uint64") == 0) return "uvlong";
    if(strcmp(t, "int32") == 0) return "long";
    if(strcmp(t, "uint32") == 0) return "ulong";
    if(strcmp(t, "int16") == 0) return "short";
    if(strcmp(t, "uint16") == 0) return "ushort";
    if(strcmp(t, "int8") == 0) return "char";
    if(strcmp(t, "uint8") == 0) return "uchar";
    if(strcmp(t, "bool") == 0) return "int";
    if(strcmp(t, "string") == 0) return "char*";
    if(strcmp(t, "chan") == 0) return "Channel*";
    return t; /* Fallback to raw Plan 9 type */
}

char*
type_fmt(char *t)
{
    if(strcmp(t, "vlong") == 0) return "%lld";
    if(strcmp(t, "uvlong") == 0) return "%llud";
    if(strcmp(t, "long") == 0) return "%ld";
    if(strcmp(t, "ulong") == 0) return "%lud";
    if(strcmp(t, "int") == 0) return "%d";
    if(strcmp(t, "uint") == 0) return "%ud";
    if(strcmp(t, "short") == 0) return "%d";
    if(strcmp(t, "ushort") == 0) return "%ud";
    if(strcmp(t, "char") == 0) return "%d";
    if(strcmp(t, "uchar") == 0) return "%ud";
    if(strcmp(t, "char*") == 0) return "%s";
    return "%lld"; /* fallback */
}

char*
type_cast(char *t)
{
    if(strcmp(t, "char*") == 0) return "char*";
    if(strcmp(t, "vlong") == 0 || strcmp(t, "uvlong") == 0 ||
       strcmp(t, "long") == 0 || strcmp(t, "ulong") == 0 ||
       strcmp(t, "int") == 0 || strcmp(t, "uint") == 0 ||
       strcmp(t, "short") == 0 || strcmp(t, "ushort") == 0 ||
       strcmp(t, "char") == 0 || strcmp(t, "uchar") == 0) return t;
    return "vlong"; /* fallback */
}

char*
get_sym_type(Node *c, char *name)
{
    Node *m;
    if(c == nil || name == nil) return "vlong";
    for(m = c->left; m; m = m->next){
        if((m->type == NProp || m->type == NAtomic || m->type == NState) && m->name && strcmp(m->name, name) == 0){
            return map_type(m->typename);
        }
    }
    return "vlong";
}

#line 237 "o9_plan9.tab.c"

# ifndef YY_CAST
#  ifdef __cplusplus
#   define YY_CAST(Type, Val) static_cast<Type> (Val)
#   define YY_REINTERPRET_CAST(Type, Val) reinterpret_cast<Type> (Val)
#  else
#   define YY_CAST(Type, Val) ((Type) (Val))
#   define YY_REINTERPRET_CAST(Type, Val) ((Type) (Val))
#  endif
# endif
# ifndef YY_NULLPTR
#  if defined __cplusplus
#   if 201103L <= __cplusplus
#    define YY_NULLPTR nullptr
#   else
#    define YY_NULLPTR 0
#   endif
#  else
#   define YY_NULLPTR ((void*)0)
#  endif
# endif

#include "o9_plan9.tab.h"
/* Symbol kind.  */
enum yysymbol_kind_t
{
  YYSYMBOL_YYEMPTY = -2,
  YYSYMBOL_YYEOF = 0,                      /* "end of file"  */
  YYSYMBOL_YYerror = 1,                    /* error  */
  YYSYMBOL_YYUNDEF = 2,                    /* "invalid token"  */
  YYSYMBOL_TIDENT = 3,                     /* TIDENT  */
  YYSYMBOL_TTYPE = 4,                      /* TTYPE  */
  YYSYMBOL_TINTLIT = 5,                    /* TINTLIT  */
  YYSYMBOL_TSTRINGLIT = 6,                 /* TSTRINGLIT  */
  YYSYMBOL_TCHARLIT = 7,                   /* TCHARLIT  */
  YYSYMBOL_TCLASS = 8,                     /* TCLASS  */
  YYSYMBOL_TFUNC = 9,                      /* TFUNC  */
  YYSYMBOL_TMETHOD = 10,                   /* TMETHOD  */
  YYSYMBOL_TRETURN = 11,                   /* TRETURN  */
  YYSYMBOL_TCHAN = 12,                     /* TCHAN  */
  YYSYMBOL_TIF = 13,                       /* TIF  */
  YYSYMBOL_TELSE = 14,                     /* TELSE  */
  YYSYMBOL_TWHILE = 15,                    /* TWHILE  */
  YYSYMBOL_TNEW = 16,                      /* TNEW  */
  YYSYMBOL_TSTATE = 17,                    /* TSTATE  */
  YYSYMBOL_TPROP = 18,                     /* TPROP  */
  YYSYMBOL_TATOMIC = 19,                   /* TATOMIC  */
  YYSYMBOL_TSTREAM = 20,                   /* TSTREAM  */
  YYSYMBOL_TSECRET = 21,                   /* TSECRET  */
  YYSYMBOL_TCAP = 22,                      /* TCAP  */
  YYSYMBOL_TTRUE = 23,                     /* TTRUE  */
  YYSYMBOL_TFALSE = 24,                    /* TFALSE  */
  YYSYMBOL_TARROW = 25,                    /* TARROW  */
  YYSYMBOL_TGET = 26,                      /* TGET  */
  YYSYMBOL_TSET = 27,                      /* TSET  */
  YYSYMBOL_TEQ = 28,                       /* TEQ  */
  YYSYMBOL_TADD = 29,                      /* TADD  */
  YYSYMBOL_TSUB = 30,                      /* TSUB  */
  YYSYMBOL_TCHANSEND = 31,                 /* TCHANSEND  */
  YYSYMBOL_TCHANRECV = 32,                 /* TCHANRECV  */
  YYSYMBOL_TCHANTRY = 33,                  /* TCHANTRY  */
  YYSYMBOL_TEQEQ = 34,                     /* TEQEQ  */
  YYSYMBOL_TNEQ = 35,                      /* TNEQ  */
  YYSYMBOL_TLE = 36,                       /* TLE  */
  YYSYMBOL_TGE = 37,                       /* TGE  */
  YYSYMBOL_TAND = 38,                      /* TAND  */
  YYSYMBOL_TOR = 39,                       /* TOR  */
  YYSYMBOL_TLSHIFT = 40,                   /* TLSHIFT  */
  YYSYMBOL_TRSHIFT = 41,                   /* TRSHIFT  */
  YYSYMBOL_42_ = 42,                       /* '|'  */
  YYSYMBOL_43_ = 43,                       /* '^'  */
  YYSYMBOL_44_ = 44,                       /* '&'  */
  YYSYMBOL_45_ = 45,                       /* '<'  */
  YYSYMBOL_46_ = 46,                       /* '>'  */
  YYSYMBOL_47_ = 47,                       /* '*'  */
  YYSYMBOL_48_ = 48,                       /* '/'  */
  YYSYMBOL_49_ = 49,                       /* '%'  */
  YYSYMBOL_50_ = 50,                       /* '!'  */
  YYSYMBOL_51_ = 51,                       /* '~'  */
  YYSYMBOL_UMINUS = 52,                    /* UMINUS  */
  YYSYMBOL_53_ = 53,                       /* '.'  */
  YYSYMBOL_54_ = 54,                       /* '('  */
  YYSYMBOL_55_ = 55,                       /* ')'  */
  YYSYMBOL_56_ = 56,                       /* '{'  */
  YYSYMBOL_57_ = 57,                       /* '}'  */
  YYSYMBOL_58_ = 58,                       /* ';'  */
  YYSYMBOL_59_ = 59,                       /* ','  */
  YYSYMBOL_YYACCEPT = 60,                  /* $accept  */
  YYSYMBOL_typename = 61,                  /* typename  */
  YYSYMBOL_program = 62,                   /* program  */
  YYSYMBOL_top_levels = 63,                /* top_levels  */
  YYSYMBOL_top_level = 64,                 /* top_level  */
  YYSYMBOL_func_top_level = 65,            /* func_top_level  */
  YYSYMBOL_class_decl = 66,                /* class_decl  */
  YYSYMBOL_member_list = 67,               /* member_list  */
  YYSYMBOL_member = 68,                    /* member  */
  YYSYMBOL_state_decl = 69,                /* state_decl  */
  YYSYMBOL_prop_decl = 70,                 /* prop_decl  */
  YYSYMBOL_atomic_decl = 71,               /* atomic_decl  */
  YYSYMBOL_stream_decl = 72,               /* stream_decl  */
  YYSYMBOL_secret_decl = 73,               /* secret_decl  */
  YYSYMBOL_cap_decl = 74,                  /* cap_decl  */
  YYSYMBOL_method_decl = 75,               /* method_decl  */
  YYSYMBOL_inherit_decl = 76,              /* inherit_decl  */
  YYSYMBOL_var_decl = 77,                  /* var_decl  */
  YYSYMBOL_func_decl = 78,                 /* func_decl  */
  YYSYMBOL_param_list = 79,                /* param_list  */
  YYSYMBOL_param = 80,                     /* param  */
  YYSYMBOL_destructor_decl = 81,           /* destructor_decl  */
  YYSYMBOL_stmt_list = 82,                 /* stmt_list  */
  YYSYMBOL_stmt = 83,                      /* stmt  */
  YYSYMBOL_expr = 84,                      /* expr  */
  YYSYMBOL_call_args = 85,                 /* call_args  */
  YYSYMBOL_call_arg = 86                   /* call_arg  */
};
typedef enum yysymbol_kind_t yysymbol_kind_t;




#ifdef short
# undef short
#endif

/* On compilers that do not define __PTRDIFF_MAX__ etc., make sure
   <limits.h> and (if available) <stdint.h> are included
   so that the code can choose integer types of a good width.  */

#ifndef __PTRDIFF_MAX__
# include <limits.h> /* INFRINGES ON USER NAME SPACE */
# if defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stdint.h> /* INFRINGES ON USER NAME SPACE */
#  define YY_STDINT_H
# endif
#endif

/* Narrow types that promote to a signed type and that can represent a
   signed or unsigned integer of at least N bits.  In tables they can
   save space and decrease cache pressure.  Promoting to a signed type
   helps avoid bugs in integer arithmetic.  */

#ifdef __INT_LEAST8_MAX__
typedef __INT_LEAST8_TYPE__ yytype_int8;
#elif defined YY_STDINT_H
typedef int_least8_t yytype_int8;
#else
typedef signed char yytype_int8;
#endif

#ifdef __INT_LEAST16_MAX__
typedef __INT_LEAST16_TYPE__ yytype_int16;
#elif defined YY_STDINT_H
typedef int_least16_t yytype_int16;
#else
typedef short yytype_int16;
#endif

/* Work around bug in HP-UX 11.23, which defines these macros
   incorrectly for preprocessor constants.  This workaround can likely
   be removed in 2023, as HPE has promised support for HP-UX 11.23
   (aka HP-UX 11i v2) only through the end of 2022; see Table 2 of
   <https://h20195.www2.hpe.com/V2/getpdf.aspx/4AA4-7673ENW.pdf>.  */
#ifdef __hpux
# undef UINT_LEAST8_MAX
# undef UINT_LEAST16_MAX
# define UINT_LEAST8_MAX 255
# define UINT_LEAST16_MAX 65535
#endif

#if defined __UINT_LEAST8_MAX__ && __UINT_LEAST8_MAX__ <= __INT_MAX__
typedef __UINT_LEAST8_TYPE__ yytype_uint8;
#elif (!defined __UINT_LEAST8_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST8_MAX <= INT_MAX)
typedef uint_least8_t yytype_uint8;
#elif !defined __UINT_LEAST8_MAX__ && UCHAR_MAX <= INT_MAX
typedef unsigned char yytype_uint8;
#else
typedef short yytype_uint8;
#endif

#if defined __UINT_LEAST16_MAX__ && __UINT_LEAST16_MAX__ <= __INT_MAX__
typedef __UINT_LEAST16_TYPE__ yytype_uint16;
#elif (!defined __UINT_LEAST16_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST16_MAX <= INT_MAX)
typedef uint_least16_t yytype_uint16;
#elif !defined __UINT_LEAST16_MAX__ && USHRT_MAX <= INT_MAX
typedef unsigned short yytype_uint16;
#else
typedef int yytype_uint16;
#endif

#ifndef YYPTRDIFF_T
# if defined __PTRDIFF_TYPE__ && defined __PTRDIFF_MAX__
#  define YYPTRDIFF_T __PTRDIFF_TYPE__
#  define YYPTRDIFF_MAXIMUM __PTRDIFF_MAX__
# elif defined PTRDIFF_MAX
#  ifndef ptrdiff_t
#   include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  endif
#  define YYPTRDIFF_T ptrdiff_t
#  define YYPTRDIFF_MAXIMUM PTRDIFF_MAX
# else
#  define YYPTRDIFF_T long
#  define YYPTRDIFF_MAXIMUM LONG_MAX
# endif
#endif

#ifndef YYSIZE_T
# ifdef __SIZE_TYPE__
#  define YYSIZE_T __SIZE_TYPE__
# elif defined size_t
#  define YYSIZE_T size_t
# elif defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# else
#  define YYSIZE_T unsigned
# endif
#endif

#define YYSIZE_MAXIMUM                                  \
  YY_CAST (YYPTRDIFF_T,                                 \
           (YYPTRDIFF_MAXIMUM < YY_CAST (YYSIZE_T, -1)  \
            ? YYPTRDIFF_MAXIMUM                         \
            : YY_CAST (YYSIZE_T, -1)))

#define YYSIZEOF(X) YY_CAST (YYPTRDIFF_T, sizeof (X))


/* Stored state numbers (used for stacks). */
typedef yytype_uint8 yy_state_t;

/* State numbers in computations.  */
typedef int yy_state_fast_t;

#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> /* INFRINGES ON USER NAME SPACE */
#   define YY_(Msgid) dgettext ("bison-runtime", Msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(Msgid) Msgid
# endif
#endif


#ifndef YY_ATTRIBUTE_PURE
# if defined __GNUC__ && 2 < __GNUC__ + (96 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_PURE __attribute__ ((__pure__))
# else
#  define YY_ATTRIBUTE_PURE
# endif
#endif

#ifndef YY_ATTRIBUTE_UNUSED
# if defined __GNUC__ && 2 < __GNUC__ + (7 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_UNUSED __attribute__ ((__unused__))
# else
#  define YY_ATTRIBUTE_UNUSED
# endif
#endif

/* Suppress unused-variable warnings by "using" E.  */
#if ! defined lint || defined __GNUC__
# define YY_USE(E) ((void) (E))
#else
# define YY_USE(E) /* empty */
#endif

/* Suppress an incorrect diagnostic about yylval being uninitialized.  */
#if defined __GNUC__ && ! defined __ICC && 406 <= __GNUC__ * 100 + __GNUC_MINOR__
# if __GNUC__ * 100 + __GNUC_MINOR__ < 407
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")
# else
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")              \
    _Pragma ("GCC diagnostic ignored \"-Wmaybe-uninitialized\"")
# endif
# define YY_IGNORE_MAYBE_UNINITIALIZED_END      \
    _Pragma ("GCC diagnostic pop")
#else
# define YY_INITIAL_VALUE(Value) Value
#endif
#ifndef YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_END
#endif
#ifndef YY_INITIAL_VALUE
# define YY_INITIAL_VALUE(Value) /* Nothing. */
#endif

#if defined __cplusplus && defined __GNUC__ && ! defined __ICC && 6 <= __GNUC__
# define YY_IGNORE_USELESS_CAST_BEGIN                          \
    _Pragma ("GCC diagnostic push")                            \
    _Pragma ("GCC diagnostic ignored \"-Wuseless-cast\"")
# define YY_IGNORE_USELESS_CAST_END            \
    _Pragma ("GCC diagnostic pop")
#endif
#ifndef YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_END
#endif


#define YY_ASSERT(E) ((void) (0 && (E)))

#if !defined yyoverflow

/* The parser invokes alloca or malloc; define the necessary symbols.  */

# ifdef YYSTACK_USE_ALLOCA
#  if YYSTACK_USE_ALLOCA
#   ifdef __GNUC__
#    define YYSTACK_ALLOC __builtin_alloca
#   elif defined __BUILTIN_VA_ARG_INCR
#    include <alloca.h> /* INFRINGES ON USER NAME SPACE */
#   elif defined _AIX
#    define YYSTACK_ALLOC __alloca
#   elif defined _MSC_VER
#    include <malloc.h> /* INFRINGES ON USER NAME SPACE */
#    define alloca _alloca
#   else
#    define YYSTACK_ALLOC alloca
#    if ! defined _ALLOCA_H && ! defined EXIT_SUCCESS
#     include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
      /* Use EXIT_SUCCESS as a witness for stdlib.h.  */
#     ifndef EXIT_SUCCESS
#      define EXIT_SUCCESS 0
#     endif
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's 'empty if-body' warning.  */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (0)
#  ifndef YYSTACK_ALLOC_MAXIMUM
    /* The OS might guarantee only one guard page at the bottom of the stack,
       and a page size can be as small as 4096 bytes.  So we cannot safely
       invoke alloca (N) if N exceeds 4096.  Use a slightly smaller number
       to allow for a few compiler-allocated temporary stack slots.  */
#   define YYSTACK_ALLOC_MAXIMUM 4032 /* reasonable circa 2006 */
#  endif
# else
#  define YYSTACK_ALLOC YYMALLOC
#  define YYSTACK_FREE YYFREE
#  ifndef YYSTACK_ALLOC_MAXIMUM
#   define YYSTACK_ALLOC_MAXIMUM YYSIZE_MAXIMUM
#  endif
#  if (defined __cplusplus && ! defined EXIT_SUCCESS \
       && ! ((defined YYMALLOC || defined malloc) \
             && (defined YYFREE || defined free)))
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   ifndef EXIT_SUCCESS
#    define EXIT_SUCCESS 0
#   endif
#  endif
#  ifndef YYMALLOC
#   define YYMALLOC malloc
#   if ! defined malloc && ! defined EXIT_SUCCESS
void *malloc (YYSIZE_T); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
#  ifndef YYFREE
#   define YYFREE free
#   if ! defined free && ! defined EXIT_SUCCESS
void free (void *); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
# endif
#endif /* !defined yyoverflow */

#if (! defined yyoverflow \
     && (! defined __cplusplus \
         || (defined YYSTYPE_IS_TRIVIAL && YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  yy_state_t yyss_alloc;
  YYSTYPE yyvs_alloc;
};

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAXIMUM (YYSIZEOF (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (YYSIZEOF (yy_state_t) + YYSIZEOF (YYSTYPE)) \
      + YYSTACK_GAP_MAXIMUM)

# define YYCOPY_NEEDED 1

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack_alloc, Stack)                           \
    do                                                                  \
      {                                                                 \
        YYPTRDIFF_T yynewbytes;                                         \
        YYCOPY (&yyptr->Stack_alloc, Stack, yysize);                    \
        Stack = &yyptr->Stack_alloc;                                    \
        yynewbytes = yystacksize * YYSIZEOF (*Stack) + YYSTACK_GAP_MAXIMUM; \
        yyptr += yynewbytes / YYSIZEOF (*yyptr);                        \
      }                                                                 \
    while (0)

#endif

#if defined YYCOPY_NEEDED && YYCOPY_NEEDED
/* Copy COUNT objects from SRC to DST.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if defined __GNUC__ && 1 < __GNUC__
#   define YYCOPY(Dst, Src, Count) \
      __builtin_memcpy (Dst, Src, YY_CAST (YYSIZE_T, (Count)) * sizeof (*(Src)))
#  else
#   define YYCOPY(Dst, Src, Count)              \
      do                                        \
        {                                       \
          YYPTRDIFF_T yyi;                      \
          for (yyi = 0; yyi < (Count); yyi++)   \
            (Dst)[yyi] = (Src)[yyi];            \
        }                                       \
      while (0)
#  endif
# endif
#endif /* !YYCOPY_NEEDED */

/* YYFINAL -- State number of the termination state.  */
#define YYFINAL  10
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   843

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  60
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  27
/* YYNRULES -- Number of rules.  */
#define YYNRULES  92
/* YYNSTATES -- Number of states.  */
#define YYNSTATES  223

/* YYMAXUTOK -- Last valid token kind.  */
#define YYMAXUTOK   297


/* YYTRANSLATE(TOKEN-NUM) -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex, with out-of-bounds checking.  */
#define YYTRANSLATE(YYX)                                \
  (0 <= (YYX) && (YYX) <= YYMAXUTOK                     \
   ? YY_CAST (yysymbol_kind_t, yytranslate[YYX])        \
   : YYSYMBOL_YYUNDEF)

/* YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex.  */
static const yytype_int8 yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    50,     2,     2,     2,    49,    44,     2,
      54,    55,    47,     2,    59,     2,    53,    48,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,    58,
      45,     2,    46,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,    43,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    56,    42,    57,    51,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      35,    36,    37,    38,    39,    40,    41,    52
};

#if YYDEBUG
/* YYRLINE[YYN] -- Source line where rule number YYN was defined.  */
static const yytype_int16 yyrline[] =
{
       0,   203,   203,   204,   208,   209,   213,   214,   223,   224,
     228,   235,   243,   244,   256,   257,   258,   259,   260,   261,
     262,   263,   264,   265,   266,   270,   277,   284,   291,   298,
     305,   324,   328,   333,   337,   345,   352,   356,   362,   369,
     378,   379,   380,   392,   399,   406,   407,   419,   420,   421,
     422,   423,   424,   427,   431,   432,   433,   434,   435,   436,
     437,   438,   439,   440,   441,   442,   443,   444,   445,   446,
     447,   448,   449,   450,   451,   452,   453,   454,   455,   456,
     459,   462,   463,   464,   465,   466,   467,   468,   474,   478,
     479,   480,   492
};
#endif

/** Accessing symbol of state STATE.  */
#define YY_ACCESSING_SYMBOL(State) YY_CAST (yysymbol_kind_t, yystos[State])

#if YYDEBUG || 0
/* The user-facing name of the symbol whose (internal) number is
   YYSYMBOL.  No bounds checking.  */
static const char *yysymbol_name (yysymbol_kind_t yysymbol) YY_ATTRIBUTE_UNUSED;

/* YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals.  */
static const char *const yytname[] =
{
  "\"end of file\"", "error", "\"invalid token\"", "TIDENT", "TTYPE",
  "TINTLIT", "TSTRINGLIT", "TCHARLIT", "TCLASS", "TFUNC", "TMETHOD",
  "TRETURN", "TCHAN", "TIF", "TELSE", "TWHILE", "TNEW", "TSTATE", "TPROP",
  "TATOMIC", "TSTREAM", "TSECRET", "TCAP", "TTRUE", "TFALSE", "TARROW",
  "TGET", "TSET", "TEQ", "TADD", "TSUB", "TCHANSEND", "TCHANRECV",
  "TCHANTRY", "TEQEQ", "TNEQ", "TLE", "TGE", "TAND", "TOR", "TLSHIFT",
  "TRSHIFT", "'|'", "'^'", "'&'", "'<'", "'>'", "'*'", "'/'", "'%'", "'!'",
  "'~'", "UMINUS", "'.'", "'('", "')'", "'{'", "'}'", "';'", "','",
  "$accept", "typename", "program", "top_levels", "top_level",
  "func_top_level", "class_decl", "member_list", "member", "state_decl",
  "prop_decl", "atomic_decl", "stream_decl", "secret_decl", "cap_decl",
  "method_decl", "inherit_decl", "var_decl", "func_decl", "param_list",
  "param", "destructor_decl", "stmt_list", "stmt", "expr", "call_args",
  "call_arg", YY_NULLPTR
};

static const char *
yysymbol_name (yysymbol_kind_t yysymbol)
{
  return yytname[yysymbol];
}
#endif

#define YYPACT_NINF (-140)

#define yypact_value_is_default(Yyn) \
  ((Yyn) == YYPACT_NINF)

#define YYTABLE_NINF (-3)

#define yytable_value_is_error(Yyn) \
  0

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
static const yytype_int16 yypact[] =
{
      34,    19,    26,    36,    34,  -140,  -140,  -140,   -11,    -5,
    -140,  -140,  -140,     8,   390,    15,    -2,  -140,    23,    72,
      66,   103,   103,   103,    99,   103,   103,   107,  -140,     0,
    -140,  -140,  -140,  -140,  -140,  -140,  -140,  -140,  -140,  -140,
    -140,  -140,  -140,  -140,   103,    63,   119,    69,  -140,   130,
     131,   132,    78,   134,   137,    87,    84,   140,    10,    98,
     103,    94,  -140,    91,    93,    96,  -140,   105,   106,    97,
    -140,   109,     1,  -140,  -140,  -140,   187,   112,   121,   103,
    -140,  -140,   187,   187,   187,   187,  -140,   154,  -140,   415,
     158,   176,   -35,  -140,   103,  -140,  -140,  -140,  -140,  -140,
     126,  -140,   187,   129,   441,   187,   187,   142,   133,   133,
     133,   545,   -10,   123,   187,   187,   187,   187,   187,   187,
     187,   187,   187,   187,   187,   187,   187,   187,   187,   187,
     187,   187,   187,   187,   181,  -140,   136,  -140,   -19,   103,
     -28,  -140,   629,   -27,  -140,  -140,   573,   601,   187,  -140,
     187,  -140,   187,   650,    56,    56,   671,   671,   790,   790,
     238,   238,   713,   692,   308,   308,   734,   755,   776,   238,
     238,   133,   133,   133,   143,   182,   187,  -140,  -140,   -15,
     108,  -140,   187,   145,   146,   -20,   467,   671,   187,   144,
     493,   165,   187,  -140,  -140,  -140,  -140,  -140,  -140,  -140,
       7,   103,  -140,  -140,   519,   220,   242,   297,  -140,    13,
    -140,  -140,   185,  -140,   103,   148,   149,  -140,  -140,   319,
     374,  -140,  -140
};

/* YYDEFACT[STATE-NUM] -- Default reduction number in state STATE-NUM.
   Performed when YYTABLE does not specify something else to do.  Zero
   means the default is an error.  */
static const yytype_int8 yydefact[] =
{
       4,     0,     0,     0,     5,     6,     9,     8,     0,     0,
       1,     7,    12,     0,     0,     0,     2,     3,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,    11,     0,
      13,    17,    18,    19,    20,    21,    22,    16,    23,    14,
      15,    24,    45,    35,     0,     2,     0,     0,     2,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
      40,     0,    38,     0,     0,     0,    28,     0,     0,     0,
      36,     0,    81,    82,    83,    84,     0,     0,     0,     0,
      85,    86,     0,     0,     0,     0,    10,     0,    46,     0,
       0,     0,     0,    41,    40,    25,    26,    27,    29,    30,
       0,    37,    89,    81,     0,     0,     0,     0,    78,    76,
      77,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,    47,     0,    43,     0,     0,
       0,    45,    92,     0,    90,    50,     0,     0,    89,    88,
       0,    48,     0,    57,    58,    59,    54,    55,    63,    64,
      66,    68,    69,    70,    74,    75,    72,    73,    71,    65,
      67,    60,    61,    62,     0,     0,     0,    45,    42,     0,
       0,    80,     0,     0,     0,     0,     0,    56,    89,     0,
       0,     0,     0,    45,    44,    91,    45,    45,    87,    49,
       0,    40,    34,    33,     0,     0,     0,     0,    79,     0,
      32,    31,    51,    53,     0,     0,     0,    45,    45,     0,
       0,    52,    39
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int16 yypgoto[] =
{
    -140,   -14,  -140,  -140,   202,  -140,  -140,  -140,  -140,  -140,
    -140,  -140,  -140,  -140,  -140,  -140,  -140,  -140,  -140,   -93,
      68,  -140,  -139,  -140,   -32,  -129,    27
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_uint8 yydefgoto[] =
{
       0,    87,     3,     4,     5,     6,     7,    14,    30,    31,
      32,    33,    34,    35,    36,    37,    38,    39,    40,    92,
      93,    41,    58,    88,    89,   143,   144
};

/* YYTABLE[YYPACT[STATE-NUM]] -- What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule whose
   number is the opposite.  If YYTABLE_NINF, syntax error.  */
static const yytype_int16 yytable[] =
{
      29,   140,   180,    56,    -2,    46,   176,    49,    50,    51,
     192,    53,    54,    72,    17,    73,    74,    75,   150,   185,
     138,    76,     8,    77,   139,    78,    79,   179,   181,     9,
      59,   139,   182,    80,    81,   198,    10,   177,   191,   182,
      82,   193,     1,     2,   104,    12,    91,    57,   151,    13,
     108,   109,   110,   111,   205,   102,    43,   206,   207,   200,
      83,    84,   208,    15,    85,   107,   182,    86,   214,    47,
     142,    42,   139,   146,   147,    45,    17,    44,   219,   220,
      91,   153,   154,   155,   156,   157,   158,   159,   160,   161,
     162,   163,   164,   165,   166,   167,   168,   169,   170,   171,
     172,   173,    52,   131,   132,   133,    48,    17,   209,   134,
      55,    72,    17,    73,    74,    75,   142,    60,   186,    76,
     187,    77,    61,    78,    79,    91,   103,    62,    73,    74,
      75,    80,    81,    63,    64,    65,    66,    67,    82,    79,
      68,    69,    70,    71,   190,    90,    80,    81,    94,    95,
     142,    96,   100,    82,    97,   152,   142,   112,    83,    84,
     204,   136,    85,    98,    99,   194,   105,   101,    72,    17,
      73,    74,    75,    83,    84,   106,    76,    85,    77,   137,
      78,    79,   141,   102,   174,   189,   134,    91,    80,    81,
     103,   175,    73,    74,    75,    82,   148,   188,   201,   215,
     216,   196,   197,    79,   217,   218,    11,   178,     0,   195,
      80,    81,     0,     0,     0,    83,    84,    82,     0,    85,
       0,     0,   203,    72,    17,    73,    74,    75,     0,     0,
       0,    76,     0,    77,     0,    78,    79,    83,    84,     0,
       0,    85,     0,    80,    81,    72,    17,    73,    74,    75,
      82,     0,     0,    76,     0,    77,     0,    78,    79,     0,
       0,     0,     0,     0,     0,    80,    81,   114,   115,     0,
      83,    84,    82,     0,    85,     0,     0,   211,   124,   125,
       0,     0,     0,     0,     0,   131,   132,   133,     0,     0,
       0,   134,    83,    84,     0,     0,    85,     0,     0,   212,
      72,    17,    73,    74,    75,     0,     0,     0,    76,     0,
      77,     0,    78,    79,     0,     0,     0,     0,     0,     0,
      80,    81,    72,    17,    73,    74,    75,    82,     0,     0,
      76,     0,    77,     0,    78,    79,     0,   114,   115,     0,
       0,     0,    80,    81,     0,     0,     0,    83,    84,    82,
       0,    85,     0,     0,   213,   131,   132,   133,     0,     0,
       0,   134,     0,     0,     0,     0,     0,     0,     0,    83,
      84,     0,     0,    85,     0,     0,   221,    72,    17,    73,
      74,    75,     0,     0,     0,    76,     0,    77,     0,    78,
      79,     0,     0,    16,    17,     0,     0,    80,    81,    18,
      19,     0,    20,     0,    82,     0,     0,    21,    22,    23,
      24,    25,    26,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,    83,    84,     0,     0,    85,     0,
       0,   222,     0,     0,     0,     0,     0,     0,     0,     0,
       0,    27,     0,   113,   114,   115,   116,    28,   117,   118,
     119,   120,   121,   122,   123,   124,   125,   126,   127,   128,
     129,   130,   131,   132,   133,     0,     0,     0,   134,   113,
     114,   115,   116,   135,   117,   118,   119,   120,   121,   122,
     123,   124,   125,   126,   127,   128,   129,   130,   131,   132,
     133,     0,     0,     0,   134,   113,   114,   115,   116,   145,
     117,   118,   119,   120,   121,   122,   123,   124,   125,   126,
     127,   128,   129,   130,   131,   132,   133,     0,     0,     0,
     134,   113,   114,   115,   116,   199,   117,   118,   119,   120,
     121,   122,   123,   124,   125,   126,   127,   128,   129,   130,
     131,   132,   133,     0,     0,     0,   134,   113,   114,   115,
     116,   202,   117,   118,   119,   120,   121,   122,   123,   124,
     125,   126,   127,   128,   129,   130,   131,   132,   133,     0,
       0,     0,   134,   113,   114,   115,   116,   210,   117,   118,
     119,   120,   121,   122,   123,   124,   125,   126,   127,   128,
     129,   130,   131,   132,   133,     0,     0,     0,   134,     0,
     149,   113,   114,   115,   116,     0,   117,   118,   119,   120,
     121,   122,   123,   124,   125,   126,   127,   128,   129,   130,
     131,   132,   133,     0,     0,     0,   134,     0,   183,   113,
     114,   115,   116,     0,   117,   118,   119,   120,   121,   122,
     123,   124,   125,   126,   127,   128,   129,   130,   131,   132,
     133,     0,     0,     0,   134,     0,   184,   113,   114,   115,
     116,     0,   117,   118,   119,   120,   121,   122,   123,   124,
     125,   126,   127,   128,   129,   130,   131,   132,   133,   114,
     115,   116,   134,   117,   118,   119,   120,   121,   122,   123,
     124,   125,   126,   127,   128,   129,   130,   131,   132,   133,
     114,   115,     0,   134,     0,   118,   119,   120,   121,   122,
     123,   124,   125,   126,   127,   128,   129,   130,   131,   132,
     133,   114,   115,     0,   134,     0,   118,   119,   120,   121,
     122,     0,   124,   125,   126,   127,   128,   129,   130,   131,
     132,   133,   114,   115,     0,   134,     0,   118,   119,   120,
     121,     0,     0,   124,   125,   126,   127,   128,   129,   130,
     131,   132,   133,   114,   115,     0,   134,     0,   118,   119,
     120,   121,     0,     0,   124,   125,     0,   127,   128,   129,
     130,   131,   132,   133,   114,   115,     0,   134,     0,   118,
     119,   120,   121,     0,     0,   124,   125,     0,     0,   128,
     129,   130,   131,   132,   133,   114,   115,     0,   134,     0,
     118,   119,   120,   121,     0,     0,   124,   125,     0,   114,
     115,   129,   130,   131,   132,   133,   120,   121,     0,   134,
     124,   125,     0,     0,     0,   129,   130,   131,   132,   133,
       0,     0,     0,   134
};

static const yytype_int16 yycheck[] =
{
      14,    94,   141,     3,     3,    19,    25,    21,    22,    23,
      25,    25,    26,     3,     4,     5,     6,     7,    28,   148,
      55,    11,     3,    13,    59,    15,    16,    55,    55,     3,
      44,    59,    59,    23,    24,    55,     0,    56,   177,    59,
      30,    56,     8,     9,    76,    56,    60,    47,    58,    54,
      82,    83,    84,    85,   193,    54,    58,   196,   197,   188,
      50,    51,    55,    55,    54,    79,    59,    57,    55,     3,
     102,    56,    59,   105,   106,     3,     4,    54,   217,   218,
      94,   113,   114,   115,   116,   117,   118,   119,   120,   121,
     122,   123,   124,   125,   126,   127,   128,   129,   130,   131,
     132,   133,     3,    47,    48,    49,     3,     4,   201,    53,
       3,     3,     4,     5,     6,     7,   148,    54,   150,    11,
     152,    13,     3,    15,    16,   139,     3,    58,     5,     6,
       7,    23,    24,     3,     3,     3,    58,     3,    30,    16,
       3,    54,    58,     3,   176,    47,    23,    24,    54,    58,
     182,    58,    55,    30,    58,    32,   188,     3,    50,    51,
     192,     3,    54,    58,    58,    57,    54,    58,     3,     4,
       5,     6,     7,    50,    51,    54,    11,    54,    13,     3,
      15,    16,    56,    54,     3,     3,    53,   201,    23,    24,
       3,    55,     5,     6,     7,    30,    54,    54,    54,    14,
     214,    56,    56,    16,    56,    56,     4,   139,    -1,   182,
      23,    24,    -1,    -1,    -1,    50,    51,    30,    -1,    54,
      -1,    -1,    57,     3,     4,     5,     6,     7,    -1,    -1,
      -1,    11,    -1,    13,    -1,    15,    16,    50,    51,    -1,
      -1,    54,    -1,    23,    24,     3,     4,     5,     6,     7,
      30,    -1,    -1,    11,    -1,    13,    -1,    15,    16,    -1,
      -1,    -1,    -1,    -1,    -1,    23,    24,    29,    30,    -1,
      50,    51,    30,    -1,    54,    -1,    -1,    57,    40,    41,
      -1,    -1,    -1,    -1,    -1,    47,    48,    49,    -1,    -1,
      -1,    53,    50,    51,    -1,    -1,    54,    -1,    -1,    57,
       3,     4,     5,     6,     7,    -1,    -1,    -1,    11,    -1,
      13,    -1,    15,    16,    -1,    -1,    -1,    -1,    -1,    -1,
      23,    24,     3,     4,     5,     6,     7,    30,    -1,    -1,
      11,    -1,    13,    -1,    15,    16,    -1,    29,    30,    -1,
      -1,    -1,    23,    24,    -1,    -1,    -1,    50,    51,    30,
      -1,    54,    -1,    -1,    57,    47,    48,    49,    -1,    -1,
      -1,    53,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    50,
      51,    -1,    -1,    54,    -1,    -1,    57,     3,     4,     5,
       6,     7,    -1,    -1,    -1,    11,    -1,    13,    -1,    15,
      16,    -1,    -1,     3,     4,    -1,    -1,    23,    24,     9,
      10,    -1,    12,    -1,    30,    -1,    -1,    17,    18,    19,
      20,    21,    22,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    50,    51,    -1,    -1,    54,    -1,
      -1,    57,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    51,    -1,    28,    29,    30,    31,    57,    33,    34,
      35,    36,    37,    38,    39,    40,    41,    42,    43,    44,
      45,    46,    47,    48,    49,    -1,    -1,    -1,    53,    28,
      29,    30,    31,    58,    33,    34,    35,    36,    37,    38,
      39,    40,    41,    42,    43,    44,    45,    46,    47,    48,
      49,    -1,    -1,    -1,    53,    28,    29,    30,    31,    58,
      33,    34,    35,    36,    37,    38,    39,    40,    41,    42,
      43,    44,    45,    46,    47,    48,    49,    -1,    -1,    -1,
      53,    28,    29,    30,    31,    58,    33,    34,    35,    36,
      37,    38,    39,    40,    41,    42,    43,    44,    45,    46,
      47,    48,    49,    -1,    -1,    -1,    53,    28,    29,    30,
      31,    58,    33,    34,    35,    36,    37,    38,    39,    40,
      41,    42,    43,    44,    45,    46,    47,    48,    49,    -1,
      -1,    -1,    53,    28,    29,    30,    31,    58,    33,    34,
      35,    36,    37,    38,    39,    40,    41,    42,    43,    44,
      45,    46,    47,    48,    49,    -1,    -1,    -1,    53,    -1,
      55,    28,    29,    30,    31,    -1,    33,    34,    35,    36,
      37,    38,    39,    40,    41,    42,    43,    44,    45,    46,
      47,    48,    49,    -1,    -1,    -1,    53,    -1,    55,    28,
      29,    30,    31,    -1,    33,    34,    35,    36,    37,    38,
      39,    40,    41,    42,    43,    44,    45,    46,    47,    48,
      49,    -1,    -1,    -1,    53,    -1,    55,    28,    29,    30,
      31,    -1,    33,    34,    35,    36,    37,    38,    39,    40,
      41,    42,    43,    44,    45,    46,    47,    48,    49,    29,
      30,    31,    53,    33,    34,    35,    36,    37,    38,    39,
      40,    41,    42,    43,    44,    45,    46,    47,    48,    49,
      29,    30,    -1,    53,    -1,    34,    35,    36,    37,    38,
      39,    40,    41,    42,    43,    44,    45,    46,    47,    48,
      49,    29,    30,    -1,    53,    -1,    34,    35,    36,    37,
      38,    -1,    40,    41,    42,    43,    44,    45,    46,    47,
      48,    49,    29,    30,    -1,    53,    -1,    34,    35,    36,
      37,    -1,    -1,    40,    41,    42,    43,    44,    45,    46,
      47,    48,    49,    29,    30,    -1,    53,    -1,    34,    35,
      36,    37,    -1,    -1,    40,    41,    -1,    43,    44,    45,
      46,    47,    48,    49,    29,    30,    -1,    53,    -1,    34,
      35,    36,    37,    -1,    -1,    40,    41,    -1,    -1,    44,
      45,    46,    47,    48,    49,    29,    30,    -1,    53,    -1,
      34,    35,    36,    37,    -1,    -1,    40,    41,    -1,    29,
      30,    45,    46,    47,    48,    49,    36,    37,    -1,    53,
      40,    41,    -1,    -1,    -1,    45,    46,    47,    48,    49,
      -1,    -1,    -1,    53
};

/* YYSTOS[STATE-NUM] -- The symbol kind of the accessing symbol of
   state STATE-NUM.  */
static const yytype_int8 yystos[] =
{
       0,     8,     9,    62,    63,    64,    65,    66,     3,     3,
       0,    64,    56,    54,    67,    55,     3,     4,     9,    10,
      12,    17,    18,    19,    20,    21,    22,    51,    57,    61,
      68,    69,    70,    71,    72,    73,    74,    75,    76,    77,
      78,    81,    56,    58,    54,     3,    61,     3,     3,    61,
      61,    61,     3,    61,    61,     3,     3,    47,    82,    61,
      54,     3,    58,     3,     3,     3,    58,     3,     3,    54,
      58,     3,     3,     5,     6,     7,    11,    13,    15,    16,
      23,    24,    30,    50,    51,    54,    57,    61,    83,    84,
      47,    61,    79,    80,    54,    58,    58,    58,    58,    58,
      55,    58,    54,     3,    84,    54,    54,    61,    84,    84,
      84,    84,     3,    28,    29,    30,    31,    33,    34,    35,
      36,    37,    38,    39,    40,    41,    42,    43,    44,    45,
      46,    47,    48,    49,    53,    58,     3,     3,    55,    59,
      79,    56,    84,    85,    86,    58,    84,    84,    54,    55,
      28,    58,    32,    84,    84,    84,    84,    84,    84,    84,
      84,    84,    84,    84,    84,    84,    84,    84,    84,    84,
      84,    84,    84,    84,     3,    55,    25,    56,    80,    55,
      82,    55,    59,    55,    55,    85,    84,    84,    54,     3,
      84,    82,    25,    56,    57,    86,    56,    56,    55,    58,
      85,    54,    58,    57,    84,    82,    82,    82,    55,    79,
      58,    57,    57,    57,    55,    14,    61,    56,    56,    82,
      82,    57,    57
};

/* YYR1[RULE-NUM] -- Symbol kind of the left-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr1[] =
{
       0,    60,    61,    61,    62,    62,    63,    63,    64,    64,
      65,    66,    67,    67,    68,    68,    68,    68,    68,    68,
      68,    68,    68,    68,    68,    69,    70,    71,    72,    73,
      74,    75,    75,    75,    75,    76,    77,    77,    77,    78,
      79,    79,    79,    80,    81,    82,    82,    83,    83,    83,
      83,    83,    83,    83,    84,    84,    84,    84,    84,    84,
      84,    84,    84,    84,    84,    84,    84,    84,    84,    84,
      84,    84,    84,    84,    84,    84,    84,    84,    84,    84,
      84,    84,    84,    84,    84,    84,    84,    84,    84,    85,
      85,    85,    86
};

/* YYR2[RULE-NUM] -- Number of symbols on the right-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr2[] =
{
       0,     2,     1,     1,     0,     1,     1,     2,     1,     1,
       7,     5,     0,     2,     1,     1,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     4,     4,     4,     3,     4,
       4,     9,     9,     8,     8,     2,     3,     4,     3,    14,
       0,     1,     3,     2,     7,     0,     2,     2,     3,     5,
       3,     7,    11,     7,     3,     3,     4,     3,     3,     3,
       3,     3,     3,     3,     3,     3,     3,     3,     3,     3,
       3,     3,     3,     3,     3,     3,     2,     2,     2,     6,
       4,     1,     1,     1,     1,     1,     1,     5,     3,     0,
       1,     3,     1
};


enum { YYENOMEM = -2 };

#define yyerrok         (yyerrstatus = 0)
#define yyclearin       (yychar = YYEMPTY)

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYNOMEM         goto yyexhaustedlab


#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)                                    \
  do                                                              \
    if (yychar == YYEMPTY)                                        \
      {                                                           \
        yychar = (Token);                                         \
        yylval = (Value);                                         \
        YYPOPSTACK (yylen);                                       \
        yystate = *yyssp;                                         \
        goto yybackup;                                            \
      }                                                           \
    else                                                          \
      {                                                           \
        yyerror (YY_("syntax error: cannot back up")); \
        YYERROR;                                                  \
      }                                                           \
  while (0)

/* Backward compatibility with an undocumented macro.
   Use YYerror or YYUNDEF. */
#define YYERRCODE YYUNDEF


/* Enable debugging if requested.  */
#if YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)                        \
do {                                            \
  if (yydebug)                                  \
    YYFPRINTF Args;                             \
} while (0)




# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)                    \
do {                                                                      \
  if (yydebug)                                                            \
    {                                                                     \
      YYFPRINTF (stderr, "%s ", Title);                                   \
      yy_symbol_print (stderr,                                            \
                  Kind, Value); \
      YYFPRINTF (stderr, "\n");                                           \
    }                                                                     \
} while (0)


/*-----------------------------------.
| Print this symbol's value on YYO.  |
`-----------------------------------*/

static void
yy_symbol_value_print (FILE *yyo,
                       yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep)
{
  FILE *yyoutput = yyo;
  YY_USE (yyoutput);
  if (!yyvaluep)
    return;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/*---------------------------.
| Print this symbol on YYO.  |
`---------------------------*/

static void
yy_symbol_print (FILE *yyo,
                 yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep)
{
  YYFPRINTF (yyo, "%s %s (",
             yykind < YYNTOKENS ? "token" : "nterm", yysymbol_name (yykind));

  yy_symbol_value_print (yyo, yykind, yyvaluep);
  YYFPRINTF (yyo, ")");
}

/*------------------------------------------------------------------.
| yy_stack_print -- Print the state stack from its BOTTOM up to its |
| TOP (included).                                                   |
`------------------------------------------------------------------*/

static void
yy_stack_print (yy_state_t *yybottom, yy_state_t *yytop)
{
  YYFPRINTF (stderr, "Stack now");
  for (; yybottom <= yytop; yybottom++)
    {
      int yybot = *yybottom;
      YYFPRINTF (stderr, " %d", yybot);
    }
  YYFPRINTF (stderr, "\n");
}

# define YY_STACK_PRINT(Bottom, Top)                            \
do {                                                            \
  if (yydebug)                                                  \
    yy_stack_print ((Bottom), (Top));                           \
} while (0)


/*------------------------------------------------.
| Report that the YYRULE is going to be reduced.  |
`------------------------------------------------*/

static void
yy_reduce_print (yy_state_t *yyssp, YYSTYPE *yyvsp,
                 int yyrule)
{
  int yylno = yyrline[yyrule];
  int yynrhs = yyr2[yyrule];
  int yyi;
  YYFPRINTF (stderr, "Reducing stack by rule %d (line %d):\n",
             yyrule - 1, yylno);
  /* The symbols being reduced.  */
  for (yyi = 0; yyi < yynrhs; yyi++)
    {
      YYFPRINTF (stderr, "   $%d = ", yyi + 1);
      yy_symbol_print (stderr,
                       YY_ACCESSING_SYMBOL (+yyssp[yyi + 1 - yynrhs]),
                       &yyvsp[(yyi + 1) - (yynrhs)]);
      YYFPRINTF (stderr, "\n");
    }
}

# define YY_REDUCE_PRINT(Rule)          \
do {                                    \
  if (yydebug)                          \
    yy_reduce_print (yyssp, yyvsp, Rule); \
} while (0)

/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !YYDEBUG */
# define YYDPRINTF(Args) ((void) 0)
# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)
# define YY_STACK_PRINT(Bottom, Top)
# define YY_REDUCE_PRINT(Rule)
#endif /* !YYDEBUG */


/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef YYINITDEPTH
# define YYINITDEPTH 200
#endif

/* YYMAXDEPTH -- maximum size the stacks can grow to (effective only
   if the built-in stack extension method is used).

   Do not make this value too large; the results are undefined if
   YYSTACK_ALLOC_MAXIMUM < YYSTACK_BYTES (YYMAXDEPTH)
   evaluated with infinite-precision integer arithmetic.  */

#ifndef YYMAXDEPTH
# define YYMAXDEPTH 10000
#endif






/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

static void
yydestruct (const char *yymsg,
            yysymbol_kind_t yykind, YYSTYPE *yyvaluep)
{
  YY_USE (yyvaluep);
  if (!yymsg)
    yymsg = "Deleting";
  YY_SYMBOL_PRINT (yymsg, yykind, yyvaluep, yylocationp);

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/* Lookahead token kind.  */
int yychar;

/* The semantic value of the lookahead symbol.  */
YYSTYPE yylval;
/* Number of syntax errors so far.  */
int yynerrs;




/*----------.
| yyparse.  |
`----------*/

int
yyparse (void)
{
    yy_state_fast_t yystate = 0;
    /* Number of tokens to shift before error messages enabled.  */
    int yyerrstatus = 0;

    /* Refer to the stacks through separate pointers, to allow yyoverflow
       to reallocate them elsewhere.  */

    /* Their size.  */
    YYPTRDIFF_T yystacksize = YYINITDEPTH;

    /* The state stack: array, bottom, top.  */
    yy_state_t yyssa[YYINITDEPTH];
    yy_state_t *yyss = yyssa;
    yy_state_t *yyssp = yyss;

    /* The semantic value stack: array, bottom, top.  */
    YYSTYPE yyvsa[YYINITDEPTH];
    YYSTYPE *yyvs = yyvsa;
    YYSTYPE *yyvsp = yyvs;

  int yyn;
  /* The return value of yyparse.  */
  int yyresult;
  /* Lookahead symbol kind.  */
  yysymbol_kind_t yytoken = YYSYMBOL_YYEMPTY;
  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;



#define YYPOPSTACK(N)   (yyvsp -= (N), yyssp -= (N))

  /* The number of symbols on the RHS of the reduced rule.
     Keep to zero when no symbol should be popped.  */
  int yylen = 0;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yychar = YYEMPTY; /* Cause a token to be read.  */

  goto yysetstate;


/*------------------------------------------------------------.
| yynewstate -- push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed.  So pushing a state here evens the stacks.  */
  yyssp++;


/*--------------------------------------------------------------------.
| yysetstate -- set current state (the top of the stack) to yystate.  |
`--------------------------------------------------------------------*/
yysetstate:
  YYDPRINTF ((stderr, "Entering state %d\n", yystate));
  YY_ASSERT (0 <= yystate && yystate < YYNSTATES);
  YY_IGNORE_USELESS_CAST_BEGIN
  *yyssp = YY_CAST (yy_state_t, yystate);
  YY_IGNORE_USELESS_CAST_END
  YY_STACK_PRINT (yyss, yyssp);

  if (yyss + yystacksize - 1 <= yyssp)
#if !defined yyoverflow && !defined YYSTACK_RELOCATE
    YYNOMEM;
#else
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYPTRDIFF_T yysize = yyssp - yyss + 1;

# if defined yyoverflow
      {
        /* Give user a chance to reallocate the stack.  Use copies of
           these so that the &'s don't force the real ones into
           memory.  */
        yy_state_t *yyss1 = yyss;
        YYSTYPE *yyvs1 = yyvs;

        /* Each stack pointer address is followed by the size of the
           data in use in that stack, in bytes.  This used to be a
           conditional around just the two extra args, but that might
           be undefined if yyoverflow is a macro.  */
        yyoverflow (YY_("memory exhausted"),
                    &yyss1, yysize * YYSIZEOF (*yyssp),
                    &yyvs1, yysize * YYSIZEOF (*yyvsp),
                    &yystacksize);
        yyss = yyss1;
        yyvs = yyvs1;
      }
# else /* defined YYSTACK_RELOCATE */
      /* Extend the stack our own way.  */
      if (YYMAXDEPTH <= yystacksize)
        YYNOMEM;
      yystacksize *= 2;
      if (YYMAXDEPTH < yystacksize)
        yystacksize = YYMAXDEPTH;

      {
        yy_state_t *yyss1 = yyss;
        union yyalloc *yyptr =
          YY_CAST (union yyalloc *,
                   YYSTACK_ALLOC (YY_CAST (YYSIZE_T, YYSTACK_BYTES (yystacksize))));
        if (! yyptr)
          YYNOMEM;
        YYSTACK_RELOCATE (yyss_alloc, yyss);
        YYSTACK_RELOCATE (yyvs_alloc, yyvs);
#  undef YYSTACK_RELOCATE
        if (yyss1 != yyssa)
          YYSTACK_FREE (yyss1);
      }
# endif

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;

      YY_IGNORE_USELESS_CAST_BEGIN
      YYDPRINTF ((stderr, "Stack size increased to %ld\n",
                  YY_CAST (long, yystacksize)));
      YY_IGNORE_USELESS_CAST_END

      if (yyss + yystacksize - 1 <= yyssp)
        YYABORT;
    }
#endif /* !defined yyoverflow && !defined YYSTACK_RELOCATE */


  if (yystate == YYFINAL)
    YYACCEPT;

  goto yybackup;


/*-----------.
| yybackup.  |
`-----------*/
yybackup:
  /* Do appropriate processing given the current state.  Read a
     lookahead token if we need one and don't already have one.  */

  /* First try to decide what to do without reference to lookahead token.  */
  yyn = yypact[yystate];
  if (yypact_value_is_default (yyn))
    goto yydefault;

  /* Not known => get a lookahead token if don't already have one.  */

  /* YYCHAR is either empty, or end-of-input, or a valid lookahead.  */
  if (yychar == YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token\n"));
      yychar = yylex ();
    }

  if (yychar <= YYEOF)
    {
      yychar = YYEOF;
      yytoken = YYSYMBOL_YYEOF;
      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else if (yychar == YYerror)
    {
      /* The scanner already issued an error message, process directly
         to error recovery.  But do not keep the error token as
         lookahead, it is too special and may lead us to an endless
         loop in error recovery. */
      yychar = YYUNDEF;
      yytoken = YYSYMBOL_YYerror;
      goto yyerrlab1;
    }
  else
    {
      yytoken = YYTRANSLATE (yychar);
      YY_SYMBOL_PRINT ("Next token is", yytoken, &yylval, &yylloc);
    }

  /* If the proper action on seeing token YYTOKEN is to reduce or to
     detect an error, take that action.  */
  yyn += yytoken;
  if (yyn < 0 || YYLAST < yyn || yycheck[yyn] != yytoken)
    goto yydefault;
  yyn = yytable[yyn];
  if (yyn <= 0)
    {
      if (yytable_value_is_error (yyn))
        goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  /* Shift the lookahead token.  */
  YY_SYMBOL_PRINT ("Shifting", yytoken, &yylval, &yylloc);
  yystate = yyn;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END

  /* Discard the shifted token.  */
  yychar = YYEMPTY;
  goto yynewstate;


/*-----------------------------------------------------------.
| yydefault -- do the default action for the current state.  |
`-----------------------------------------------------------*/
yydefault:
  yyn = yydefact[yystate];
  if (yyn == 0)
    goto yyerrlab;
  goto yyreduce;


/*-----------------------------.
| yyreduce -- do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     '$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];


  YY_REDUCE_PRINT (yyn);
  switch (yyn)
    {
  case 2: /* typename: TIDENT  */
#line 203 "o9_plan9.y"
           { (yyval.node) = (yyvsp[0].node); }
#line 1577 "o9_plan9.tab.c"
    break;

  case 3: /* typename: TTYPE  */
#line 204 "o9_plan9.y"
            { (yyval.node) = (yyvsp[0].node); }
#line 1583 "o9_plan9.tab.c"
    break;

  case 4: /* program: %empty  */
#line 208 "o9_plan9.y"
                { ast_root = nil; }
#line 1589 "o9_plan9.tab.c"
    break;

  case 5: /* program: top_levels  */
#line 209 "o9_plan9.y"
                 { ast_root = (yyvsp[0].node); }
#line 1595 "o9_plan9.tab.c"
    break;

  case 6: /* top_levels: top_level  */
#line 213 "o9_plan9.y"
              { (yyval.node) = (yyvsp[0].node); }
#line 1601 "o9_plan9.tab.c"
    break;

  case 7: /* top_levels: top_levels top_level  */
#line 214 "o9_plan9.y"
                           { 
        Node *n = (yyvsp[-1].node);
        while(n->next) n = n->next;
        n->next = (yyvsp[0].node);
        (yyval.node) = (yyvsp[-1].node);
    }
#line 1612 "o9_plan9.tab.c"
    break;

  case 10: /* func_top_level: TFUNC TIDENT '(' ')' '{' stmt_list '}'  */
#line 229 "o9_plan9.y"
    {
        (yyval.node) = mk(NMethod, (yyvsp[-5].node)->name, "void", (yyvsp[-1].node), nil);
    }
#line 1620 "o9_plan9.tab.c"
    break;

  case 11: /* class_decl: TCLASS TIDENT '{' member_list '}'  */
#line 236 "o9_plan9.y"
    {
        (yyval.node) = mk(NClass, (yyvsp[-3].node)->name, nil, (yyvsp[-1].node), nil);
        add_class((yyvsp[-3].node)->name, (yyval.node));
    }
#line 1629 "o9_plan9.tab.c"
    break;

  case 12: /* member_list: %empty  */
#line 243 "o9_plan9.y"
                { (yyval.node) = nil; }
#line 1635 "o9_plan9.tab.c"
    break;

  case 13: /* member_list: member_list member  */
#line 244 "o9_plan9.y"
                         { 
        if((yyvsp[-1].node) == nil) (yyval.node) = (yyvsp[0].node);
        else {
            Node *n = (yyvsp[-1].node);
            while(n->next) n = n->next;
            n->next = (yyvsp[0].node);
            (yyval.node) = (yyvsp[-1].node);
        }
    }
#line 1649 "o9_plan9.tab.c"
    break;

  case 25: /* state_decl: TSTATE typename TIDENT ';'  */
#line 271 "o9_plan9.y"
    {
        (yyval.node) = mk(NState, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1657 "o9_plan9.tab.c"
    break;

  case 26: /* prop_decl: TPROP typename TIDENT ';'  */
#line 278 "o9_plan9.y"
    {
        (yyval.node) = mk(NProp, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1665 "o9_plan9.tab.c"
    break;

  case 27: /* atomic_decl: TATOMIC typename TIDENT ';'  */
#line 285 "o9_plan9.y"
    {
        (yyval.node) = mk(NAtomic, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1673 "o9_plan9.tab.c"
    break;

  case 28: /* stream_decl: TSTREAM TIDENT ';'  */
#line 292 "o9_plan9.y"
    {
        (yyval.node) = mk(NStream, (yyvsp[-1].node)->name, nil, nil, nil);
    }
#line 1681 "o9_plan9.tab.c"
    break;

  case 29: /* secret_decl: TSECRET typename TIDENT ';'  */
#line 299 "o9_plan9.y"
    {
        (yyval.node) = mk(NSecret, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1689 "o9_plan9.tab.c"
    break;

  case 30: /* cap_decl: TCAP typename TIDENT ';'  */
#line 306 "o9_plan9.y"
    {
        (yyval.node) = mk(NCap, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1697 "o9_plan9.tab.c"
    break;

  case 31: /* method_decl: TMETHOD typename TIDENT '(' param_list ')' '{' stmt_list '}'  */
#line 325 "o9_plan9.y"
    {
        (yyval.node) = mk(NMethod, (yyvsp[-6].node)->name, (yyvsp[-7].node)->name, (yyvsp[-1].node), (yyvsp[-4].node));
    }
#line 1705 "o9_plan9.tab.c"
    break;

  case 32: /* method_decl: TMETHOD typename TIDENT '(' param_list ')' TARROW expr ';'  */
#line 329 "o9_plan9.y"
    {
        Node *body = mk(NReturn, nil, nil, (yyvsp[-1].node), nil);
        (yyval.node) = mk(NMethod, (yyvsp[-6].node)->name, (yyvsp[-7].node)->name, body, (yyvsp[-4].node));
    }
#line 1714 "o9_plan9.tab.c"
    break;

  case 33: /* method_decl: TMETHOD TIDENT '(' param_list ')' '{' stmt_list '}'  */
#line 334 "o9_plan9.y"
    {
        (yyval.node) = mk(NMethod, (yyvsp[-6].node)->name, "void", (yyvsp[-1].node), (yyvsp[-4].node));
    }
#line 1722 "o9_plan9.tab.c"
    break;

  case 34: /* method_decl: TMETHOD TIDENT '(' param_list ')' TARROW expr ';'  */
#line 338 "o9_plan9.y"
    {
        Node *body = mk(NReturn, nil, nil, (yyvsp[-1].node), nil);
        (yyval.node) = mk(NMethod, (yyvsp[-6].node)->name, "void", body, (yyvsp[-4].node));
    }
#line 1731 "o9_plan9.tab.c"
    break;

  case 35: /* inherit_decl: TIDENT ';'  */
#line 346 "o9_plan9.y"
    {
        (yyval.node) = mk(NInherit, (yyvsp[-1].node)->name, nil, nil, nil);
    }
#line 1739 "o9_plan9.tab.c"
    break;

  case 36: /* var_decl: typename TIDENT ';'  */
#line 353 "o9_plan9.y"
    {
        (yyval.node) = mk(NProp, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil);
    }
#line 1747 "o9_plan9.tab.c"
    break;

  case 37: /* var_decl: typename '*' TIDENT ';'  */
#line 357 "o9_plan9.y"
    {
        char buf[128];
        snprint(buf, sizeof buf, "%s*", (yyvsp[-3].node)->name);
        (yyval.node) = mk(NProp, (yyvsp[-1].node)->name, buf, nil, nil);
    }
#line 1757 "o9_plan9.tab.c"
    break;

  case 38: /* var_decl: TCHAN TIDENT ';'  */
#line 363 "o9_plan9.y"
    {
        (yyval.node) = mk(NStream, (yyvsp[-1].node)->name, "chan", nil, nil);
    }
#line 1765 "o9_plan9.tab.c"
    break;

  case 39: /* func_decl: TFUNC '(' typename '*' TIDENT ')' TIDENT '(' param_list ')' typename '{' stmt_list '}'  */
#line 370 "o9_plan9.y"
    {
        Node *params = (yyvsp[-5].node);
        Node *stmts = (yyvsp[-1].node);
        (yyval.node) = mk(NMethod, (yyvsp[-7].node)->name, (yyvsp[-3].node)->name, stmts, params);
    }
#line 1775 "o9_plan9.tab.c"
    break;

  case 40: /* param_list: %empty  */
#line 378 "o9_plan9.y"
                { (yyval.node) = nil; }
#line 1781 "o9_plan9.tab.c"
    break;

  case 41: /* param_list: param  */
#line 379 "o9_plan9.y"
            { (yyval.node) = (yyvsp[0].node); }
#line 1787 "o9_plan9.tab.c"
    break;

  case 42: /* param_list: param_list ',' param  */
#line 380 "o9_plan9.y"
                           {
        if((yyvsp[-2].node) == nil) (yyval.node) = (yyvsp[0].node);
        else {
            Node *n = (yyvsp[-2].node);
            while(n->next) n = n->next;
            n->next = (yyvsp[0].node);
            (yyval.node) = (yyvsp[-2].node);
        }
    }
#line 1801 "o9_plan9.tab.c"
    break;

  case 43: /* param: typename TIDENT  */
#line 393 "o9_plan9.y"
    {
        (yyval.node) = mk(NProp, (yyvsp[0].node)->name, (yyvsp[-1].node)->name, nil, nil);
    }
#line 1809 "o9_plan9.tab.c"
    break;

  case 44: /* destructor_decl: '~' TIDENT '(' ')' '{' stmt_list '}'  */
#line 400 "o9_plan9.y"
    {
        (yyval.node) = mk(NDestructor, (yyvsp[-5].node)->name, nil, (yyvsp[-1].node), nil);
    }
#line 1817 "o9_plan9.tab.c"
    break;

  case 45: /* stmt_list: %empty  */
#line 406 "o9_plan9.y"
                { (yyval.node) = nil; }
#line 1823 "o9_plan9.tab.c"
    break;

  case 46: /* stmt_list: stmt_list stmt  */
#line 407 "o9_plan9.y"
                     {
        if((yyvsp[-1].node) == nil) (yyval.node) = (yyvsp[0].node);
        else {
            Node *n = (yyvsp[-1].node);
            while(n->next) n = n->next;
            n->next = (yyvsp[0].node);
            (yyval.node) = (yyvsp[-1].node);
        }
    }
#line 1837 "o9_plan9.tab.c"
    break;

  case 47: /* stmt: expr ';'  */
#line 419 "o9_plan9.y"
             { (yyval.node) = (yyvsp[-1].node); }
#line 1843 "o9_plan9.tab.c"
    break;

  case 48: /* stmt: typename TIDENT ';'  */
#line 420 "o9_plan9.y"
                          { (yyval.node) = mk(NLocalVar, (yyvsp[-1].node)->name, (yyvsp[-2].node)->name, nil, nil); if(find_class((yyvsp[-2].node)->name)) add_var_class((yyvsp[-1].node)->name, (yyvsp[-2].node)->name); }
#line 1849 "o9_plan9.tab.c"
    break;

  case 49: /* stmt: typename TIDENT TEQ expr ';'  */
#line 421 "o9_plan9.y"
                                   { (yyval.node) = mk(NLocalVar, (yyvsp[-3].node)->name, (yyvsp[-4].node)->name, (yyvsp[-1].node), nil); if(find_class((yyvsp[-4].node)->name)) add_var_class((yyvsp[-3].node)->name, (yyvsp[-4].node)->name); }
#line 1855 "o9_plan9.tab.c"
    break;

  case 50: /* stmt: TRETURN expr ';'  */
#line 422 "o9_plan9.y"
                       { (yyval.node) = mk(NReturn, nil, nil, (yyvsp[-1].node), nil); }
#line 1861 "o9_plan9.tab.c"
    break;

  case 51: /* stmt: TIF '(' expr ')' '{' stmt_list '}'  */
#line 423 "o9_plan9.y"
                                         { (yyval.node) = mk(NIf, nil, nil, (yyvsp[-4].node), (yyvsp[-1].node)); }
#line 1867 "o9_plan9.tab.c"
    break;

  case 52: /* stmt: TIF '(' expr ')' '{' stmt_list '}' TELSE '{' stmt_list '}'  */
#line 424 "o9_plan9.y"
                                                                 {
        (yyval.node) = mk(NIfElse, nil, nil, (yyvsp[-8].node), mk(NElse, nil, nil, (yyvsp[-5].node), (yyvsp[-1].node)));
    }
#line 1875 "o9_plan9.tab.c"
    break;

  case 53: /* stmt: TWHILE '(' expr ')' '{' stmt_list '}'  */
#line 427 "o9_plan9.y"
                                            { (yyval.node) = mk(NWhile, nil, nil, (yyvsp[-4].node), (yyvsp[-1].node)); }
#line 1881 "o9_plan9.tab.c"
    break;

  case 54: /* expr: expr TCHANSEND expr  */
#line 431 "o9_plan9.y"
                        { (yyval.node) = mk(NChanSend, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1887 "o9_plan9.tab.c"
    break;

  case 55: /* expr: expr TCHANTRY expr  */
#line 432 "o9_plan9.y"
                         { (yyval.node) = mk(NChanTry, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1893 "o9_plan9.tab.c"
    break;

  case 56: /* expr: expr TEQ TCHANRECV expr  */
#line 433 "o9_plan9.y"
                              { (yyval.node) = mk(NChanRecv, nil, nil, (yyvsp[-3].node), (yyvsp[0].node)); }
#line 1899 "o9_plan9.tab.c"
    break;

  case 57: /* expr: expr TEQ expr  */
#line 434 "o9_plan9.y"
                    { (yyval.node) = mk(NAssign, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1905 "o9_plan9.tab.c"
    break;

  case 58: /* expr: expr TADD expr  */
#line 435 "o9_plan9.y"
                     { (yyval.node) = mk(NAdd, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1911 "o9_plan9.tab.c"
    break;

  case 59: /* expr: expr TSUB expr  */
#line 436 "o9_plan9.y"
                     { (yyval.node) = mk(NSub, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1917 "o9_plan9.tab.c"
    break;

  case 60: /* expr: expr '*' expr  */
#line 437 "o9_plan9.y"
                    { (yyval.node) = mk(NMul, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1923 "o9_plan9.tab.c"
    break;

  case 61: /* expr: expr '/' expr  */
#line 438 "o9_plan9.y"
                    { (yyval.node) = mk(NDiv, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1929 "o9_plan9.tab.c"
    break;

  case 62: /* expr: expr '%' expr  */
#line 439 "o9_plan9.y"
                    { (yyval.node) = mk(NMod, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1935 "o9_plan9.tab.c"
    break;

  case 63: /* expr: expr TEQEQ expr  */
#line 440 "o9_plan9.y"
                      { (yyval.node) = mk(NEq, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1941 "o9_plan9.tab.c"
    break;

  case 64: /* expr: expr TNEQ expr  */
#line 441 "o9_plan9.y"
                     { (yyval.node) = mk(NNe, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1947 "o9_plan9.tab.c"
    break;

  case 65: /* expr: expr '<' expr  */
#line 442 "o9_plan9.y"
                    { (yyval.node) = mk(NLt, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1953 "o9_plan9.tab.c"
    break;

  case 66: /* expr: expr TLE expr  */
#line 443 "o9_plan9.y"
                    { (yyval.node) = mk(NLe, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1959 "o9_plan9.tab.c"
    break;

  case 67: /* expr: expr '>' expr  */
#line 444 "o9_plan9.y"
                    { (yyval.node) = mk(NGt, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1965 "o9_plan9.tab.c"
    break;

  case 68: /* expr: expr TGE expr  */
#line 445 "o9_plan9.y"
                    { (yyval.node) = mk(NGe, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1971 "o9_plan9.tab.c"
    break;

  case 69: /* expr: expr TAND expr  */
#line 446 "o9_plan9.y"
                     { (yyval.node) = mk(NAnd, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1977 "o9_plan9.tab.c"
    break;

  case 70: /* expr: expr TOR expr  */
#line 447 "o9_plan9.y"
                    { (yyval.node) = mk(NOr, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1983 "o9_plan9.tab.c"
    break;

  case 71: /* expr: expr '&' expr  */
#line 448 "o9_plan9.y"
                    { (yyval.node) = mk(NBitAnd, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1989 "o9_plan9.tab.c"
    break;

  case 72: /* expr: expr '|' expr  */
#line 449 "o9_plan9.y"
                    { (yyval.node) = mk(NBitOr, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 1995 "o9_plan9.tab.c"
    break;

  case 73: /* expr: expr '^' expr  */
#line 450 "o9_plan9.y"
                    { (yyval.node) = mk(NBitXor, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 2001 "o9_plan9.tab.c"
    break;

  case 74: /* expr: expr TLSHIFT expr  */
#line 451 "o9_plan9.y"
                        { (yyval.node) = mk(NLshift, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 2007 "o9_plan9.tab.c"
    break;

  case 75: /* expr: expr TRSHIFT expr  */
#line 452 "o9_plan9.y"
                        { (yyval.node) = mk(NRshift, nil, nil, (yyvsp[-2].node), (yyvsp[0].node)); }
#line 2013 "o9_plan9.tab.c"
    break;

  case 76: /* expr: '!' expr  */
#line 453 "o9_plan9.y"
               { (yyval.node) = mk(NNot, nil, nil, (yyvsp[0].node), nil); }
#line 2019 "o9_plan9.tab.c"
    break;

  case 77: /* expr: '~' expr  */
#line 454 "o9_plan9.y"
               { (yyval.node) = mk(NBitNot, nil, nil, (yyvsp[0].node), nil); }
#line 2025 "o9_plan9.tab.c"
    break;

  case 78: /* expr: TSUB expr  */
#line 455 "o9_plan9.y"
                             { (yyval.node) = mk(NNeg, nil, nil, (yyvsp[0].node), nil); }
#line 2031 "o9_plan9.tab.c"
    break;

  case 79: /* expr: expr '.' TIDENT '(' call_args ')'  */
#line 456 "o9_plan9.y"
                                        {
        (yyval.node) = mk(NMsgSend, (yyvsp[-3].node)->name, nil, (yyvsp[-5].node), (yyvsp[-1].node));
    }
#line 2039 "o9_plan9.tab.c"
    break;

  case 80: /* expr: TIDENT '(' call_args ')'  */
#line 459 "o9_plan9.y"
                               {
        (yyval.node) = mk(NFuncCall, (yyvsp[-3].node)->name, nil, (yyvsp[-1].node), nil);
    }
#line 2047 "o9_plan9.tab.c"
    break;

  case 81: /* expr: TIDENT  */
#line 462 "o9_plan9.y"
             { (yyval.node) = (yyvsp[0].node); }
#line 2053 "o9_plan9.tab.c"
    break;

  case 82: /* expr: TINTLIT  */
#line 463 "o9_plan9.y"
              { (yyval.node) = mk(NIntLit, (yyvsp[0].name), nil, nil, nil); }
#line 2059 "o9_plan9.tab.c"
    break;

  case 83: /* expr: TSTRINGLIT  */
#line 464 "o9_plan9.y"
                 { (yyval.node) = mk(NStringLit, (yyvsp[0].name), nil, nil, nil); }
#line 2065 "o9_plan9.tab.c"
    break;

  case 84: /* expr: TCHARLIT  */
#line 465 "o9_plan9.y"
               { (yyval.node) = mk(NCharLit, (yyvsp[0].name), nil, nil, nil); }
#line 2071 "o9_plan9.tab.c"
    break;

  case 85: /* expr: TTRUE  */
#line 466 "o9_plan9.y"
            { (yyval.node) = mk(NBoolLit, "1", nil, nil, nil); }
#line 2077 "o9_plan9.tab.c"
    break;

  case 86: /* expr: TFALSE  */
#line 467 "o9_plan9.y"
             { (yyval.node) = mk(NBoolLit, "0", nil, nil, nil); }
#line 2083 "o9_plan9.tab.c"
    break;

  case 87: /* expr: TNEW typename '(' call_args ')'  */
#line 468 "o9_plan9.y"
                                      {
        Node *n = mk(NClass, (yyvsp[-3].node)->name, nil, nil, nil);
        n->left = (yyvsp[-3].node);
        n->right = (yyvsp[-1].node);
        (yyval.node) = n;
    }
#line 2094 "o9_plan9.tab.c"
    break;

  case 88: /* expr: '(' expr ')'  */
#line 474 "o9_plan9.y"
                   { (yyval.node) = (yyvsp[-1].node); }
#line 2100 "o9_plan9.tab.c"
    break;

  case 89: /* call_args: %empty  */
#line 478 "o9_plan9.y"
                { (yyval.node) = nil; }
#line 2106 "o9_plan9.tab.c"
    break;

  case 90: /* call_args: call_arg  */
#line 479 "o9_plan9.y"
               { (yyval.node) = (yyvsp[0].node); }
#line 2112 "o9_plan9.tab.c"
    break;

  case 91: /* call_args: call_args ',' call_arg  */
#line 480 "o9_plan9.y"
                             {
        if((yyvsp[-2].node) == nil) (yyval.node) = (yyvsp[0].node);
        else {
            Node *n = (yyvsp[-2].node);
            while(n->next) n = n->next;
            n->next = (yyvsp[0].node);
            (yyval.node) = (yyvsp[-2].node);
        }
    }
#line 2126 "o9_plan9.tab.c"
    break;

  case 92: /* call_arg: expr  */
#line 492 "o9_plan9.y"
         { (yyval.node) = (yyvsp[0].node); }
#line 2132 "o9_plan9.tab.c"
    break;


#line 2136 "o9_plan9.tab.c"

      default: break;
    }
  /* User semantic actions sometimes alter yychar, and that requires
     that yytoken be updated with the new translation.  We take the
     approach of translating immediately before every use of yytoken.
     One alternative is translating here after every semantic action,
     but that translation would be missed if the semantic action invokes
     YYABORT, YYACCEPT, or YYERROR immediately after altering yychar or
     if it invokes YYBACKUP.  In the case of YYABORT or YYACCEPT, an
     incorrect destructor might then be invoked immediately.  In the
     case of YYERROR or YYBACKUP, subsequent parser actions might lead
     to an incorrect destructor call or verbose syntax error message
     before the lookahead is translated.  */
  YY_SYMBOL_PRINT ("-> $$ =", YY_CAST (yysymbol_kind_t, yyr1[yyn]), &yyval, &yyloc);

  YYPOPSTACK (yylen);
  yylen = 0;

  *++yyvsp = yyval;

  /* Now 'shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */
  {
    const int yylhs = yyr1[yyn] - YYNTOKENS;
    const int yyi = yypgoto[yylhs] + *yyssp;
    yystate = (0 <= yyi && yyi <= YYLAST && yycheck[yyi] == *yyssp
               ? yytable[yyi]
               : yydefgoto[yylhs]);
  }

  goto yynewstate;


/*--------------------------------------.
| yyerrlab -- here on detecting error.  |
`--------------------------------------*/
yyerrlab:
  /* Make sure we have latest lookahead translation.  See comments at
     user semantic actions for why this is necessary.  */
  yytoken = yychar == YYEMPTY ? YYSYMBOL_YYEMPTY : YYTRANSLATE (yychar);
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
      yyerror (YY_("syntax error"));
    }

  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse lookahead token after an
         error, discard it.  */

      if (yychar <= YYEOF)
        {
          /* Return failure if at end of input.  */
          if (yychar == YYEOF)
            YYABORT;
        }
      else
        {
          yydestruct ("Error: discarding",
                      yytoken, &yylval);
          yychar = YYEMPTY;
        }
    }

  /* Else will try to reuse lookahead token after shifting the error
     token.  */
  goto yyerrlab1;


/*---------------------------------------------------.
| yyerrorlab -- error raised explicitly by YYERROR.  |
`---------------------------------------------------*/
yyerrorlab:
  /* Pacify compilers when the user code never invokes YYERROR and the
     label yyerrorlab therefore never appears in user code.  */
  if (0)
    YYERROR;
  ++yynerrs;

  /* Do not reclaim the symbols of the rule whose action triggered
     this YYERROR.  */
  YYPOPSTACK (yylen);
  yylen = 0;
  YY_STACK_PRINT (yyss, yyssp);
  yystate = *yyssp;
  goto yyerrlab1;


/*-------------------------------------------------------------.
| yyerrlab1 -- common code for both syntax error and YYERROR.  |
`-------------------------------------------------------------*/
yyerrlab1:
  yyerrstatus = 3;      /* Each real token shifted decrements this.  */

  /* Pop stack until we find a state that shifts the error token.  */
  for (;;)
    {
      yyn = yypact[yystate];
      if (!yypact_value_is_default (yyn))
        {
          yyn += YYSYMBOL_YYerror;
          if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYSYMBOL_YYerror)
            {
              yyn = yytable[yyn];
              if (0 < yyn)
                break;
            }
        }

      /* Pop the current state because it cannot handle the error token.  */
      if (yyssp == yyss)
        YYABORT;


      yydestruct ("Error: popping",
                  YY_ACCESSING_SYMBOL (yystate), yyvsp);
      YYPOPSTACK (1);
      yystate = *yyssp;
      YY_STACK_PRINT (yyss, yyssp);
    }

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END


  /* Shift the error token.  */
  YY_SYMBOL_PRINT ("Shifting", YY_ACCESSING_SYMBOL (yyn), yyvsp, yylsp);

  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturnlab;


/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturnlab;


/*-----------------------------------------------------------.
| yyexhaustedlab -- YYNOMEM (memory exhaustion) comes here.  |
`-----------------------------------------------------------*/
yyexhaustedlab:
  yyerror (YY_("memory exhausted"));
  yyresult = 2;
  goto yyreturnlab;


/*----------------------------------------------------------.
| yyreturnlab -- parsing is finished, clean up and return.  |
`----------------------------------------------------------*/
yyreturnlab:
  if (yychar != YYEMPTY)
    {
      /* Make sure we have latest lookahead translation.  See comments at
         user semantic actions for why this is necessary.  */
      yytoken = YYTRANSLATE (yychar);
      yydestruct ("Cleanup: discarding lookahead",
                  yytoken, &yylval);
    }
  /* Do not reclaim the symbols of the rule whose action triggered
     this YYABORT or YYACCEPT.  */
  YYPOPSTACK (yylen);
  YY_STACK_PRINT (yyss, yyssp);
  while (yyssp != yyss)
    {
      yydestruct ("Cleanup: popping",
                  YY_ACCESSING_SYMBOL (+*yyssp), yyvsp);
      YYPOPSTACK (1);
    }
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif

  return yyresult;
}

#line 495 "o9_plan9.y"


Node*
mk(int type, char *name, char *typename, Node *l, Node *r)
{
    Node *n = malloc(sizeof(Node));
    memset(n, 0, sizeof(Node));
    n->type = type;
    if(name) n->name = strdup(name);
    if(typename) n->typename = strdup(typename);
    n->left = l;
    n->right = r;
    return n;
}

void
yyerror(char *s)
{
    fprint(2, "o9c: error: %s\n", s);
}

static Biobuf *bin;

int
yylex(void)
{
    int c;

    while((c = Bgetc(bin)) != Beof){
        if(isspace(c))
            continue;
        if(c == '~')
            return '~';
        if(c == '='){
            if((c = Bgetc(bin)) == '=') return TEQEQ;
            if(c == '>') return TARROW;
            Bungetc(bin);
            return TEQ;
        }
        if(c == '&'){
            if((c = Bgetc(bin)) == '&') return TAND;
            Bungetc(bin);
            return '&';
        }
        if(c == '|'){
            if((c = Bgetc(bin)) == '|') return TOR;
            Bungetc(bin);
            return '|';
        }
        if(c == '!'){
            if((c = Bgetc(bin)) == '=') return TNEQ;
            Bungetc(bin);
            return '!';
        }
        if(c == '<'){
            if((c = Bgetc(bin)) == '-') return TCHANRECV;
            if(c == '=') return TLE;
            if(c == '<') return TLSHIFT;
            Bungetc(bin);
            return '<';
        }
        if(c == '>'){
            if((c = Bgetc(bin)) == '=') return TGE;
            if(c == '>') return TRSHIFT;
            Bungetc(bin);
            return '>';
        }
        if(c == '"'){
            char buf[1024];
            int i = 0;
            while((c = Bgetc(bin)) != Beof && c != '"' && i < 1023) {
                if(c == '\\'){
                    if((c = Bgetc(bin)) == Beof) break;
                    if(c == 'n') buf[i++] = '\n';
                    else if(c == 't') buf[i++] = '\t';
                    else buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TSTRINGLIT;
        }
        if(c == '\''){
            char buf[16];
            int i = 0;
            while((c = Bgetc(bin)) != Beof && c != '\'' && i < 15) {
                if(c == '\\'){
                    if((c = Bgetc(bin)) == Beof) break;
                    buf[i++] = c;
                } else {
                    buf[i++] = c;
                }
            }
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TCHARLIT;
        }
        if(c == '-'){
            if((c = Bgetc(bin)) == '>'){
                if((c = Bgetc(bin)) == '?') return TCHANTRY;
                Bungetc(bin);
                return TCHANSEND;
            }
            Bungetc(bin);
            return TSUB;
        }
        if(c == '/'){
            if((c = Bgetc(bin)) == '/'){
                while((c = Bgetc(bin)) != Beof && c != '\n');
                continue;
            }
            if(c == '*'){
                while((c = Bgetc(bin)) != Beof){
                    if(c == '*'){
                        if((c = Bgetc(bin)) == '/') break;
                        Bungetc(bin);
                    }
                }
                continue;
            }
            Bungetc(bin);
            return '/';
        }
        if(c == '+') return TADD;

        if(isdigit(c)){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            if(c == '0'){
                c = Bgetc(bin);
                if(c == 'x' || c == 'X'){
                    buf[i++] = c;
                    while(isxdigit(c = Bgetc(bin))) {
                        if(i < 63) buf[i++] = c;
                    }
                    Bungetc(bin);
                    buf[i] = '\0';
                    yylval.name = strdup(buf);
                    return TINTLIT;
                }
                Bungetc(bin);
            }
            while(isdigit(c = Bgetc(bin))) {
                if(i < 63) buf[i++] = c;
            }
            Bungetc(bin);
            buf[i] = '\0';
            yylval.name = strdup(buf);
            return TINTLIT;
        }

        if(isalpha(c) || c == '_'){
            char buf[64];
            int i = 0;
            buf[i++] = c;
            while(isalnum(c = Bgetc(bin)) || c == '_') {
                if(i < 63) buf[i++] = c;
            }
            Bungetc(bin);
            buf[i] = '\0';
            
            yylval.node = mk(NIdent, buf, nil, nil, nil);
            
            if(strcmp(buf, "class") == 0) return TCLASS;
            if(strcmp(buf, "func") == 0) return TFUNC;
            if(strcmp(buf, "new") == 0) return TNEW;
            if(strcmp(buf, "method") == 0) return TMETHOD;
            if(strcmp(buf, "state") == 0) return TSTATE;
            if(strcmp(buf, "prop") == 0) return TPROP;
            if(strcmp(buf, "atomic") == 0) return TATOMIC;
            if(strcmp(buf, "stream") == 0) return TSTREAM;
            if(strcmp(buf, "secret") == 0) return TSECRET;
            if(strcmp(buf, "cap") == 0) return TCAP;
            if(strcmp(buf, "chan") == 0) return TCHAN;
            if(strcmp(buf, "return") == 0) return TRETURN;
            if(strcmp(buf, "if") == 0) return TIF;
            if(strcmp(buf, "else") == 0) return TELSE;
            if(strcmp(buf, "while") == 0) return TWHILE;
            if(strcmp(buf, "true") == 0) return TTRUE;
            if(strcmp(buf, "false") == 0) return TFALSE;
            if(strcmp(buf, "bool") == 0) return TTYPE;
            if(strcmp(buf, "uint64") == 0) return TTYPE;
            if(strcmp(buf, "int32") == 0) return TTYPE;
            if(strcmp(buf, "uint32") == 0) return TTYPE;
            if(strcmp(buf, "int16") == 0) return TTYPE;
            if(strcmp(buf, "uint16") == 0) return TTYPE;
            if(strcmp(buf, "int8") == 0) return TTYPE;
            if(strcmp(buf, "uint8") == 0) return TTYPE;
            if(strcmp(buf, "void") == 0) return TTYPE;
            if(strcmp(buf, "string") == 0) return TTYPE;
            if(strcmp(buf, "int") == 0) return TTYPE;
            if(strcmp(buf, "char") == 0) return TTYPE;
            if(strcmp(buf, "vlong") == 0) return TTYPE;
            if(strcmp(buf, "uvlong") == 0) return TTYPE;
            if(strcmp(buf, "ulong") == 0) return TTYPE;
            if(strcmp(buf, "ushort") == 0) return TTYPE;
            if(strcmp(buf, "uchar") == 0) return TTYPE;
            return TIDENT;
        }
        return c;
    }
    return 0;
}

/* --- Code Generator --- */

char *local_vars[128];
int num_locals = 0;
int in_class_context = 1;		/* 0 when generating top-level main() */
int in_method_body = 0;		/* 1 when generating inside a method impl */
int has_return = 0;			/* 1 when a return statement was emitted */

/* Variable-to-class symbol table */
typedef struct VarClass VarClass;
struct VarClass {
    char *varname;
    char *classname;
};
VarClass var_classes[128];
int num_var_classes = 0;

void
add_var_class(char *varname, char *classname)
{
    if(num_var_classes >= 128) return;
    var_classes[num_var_classes].varname = varname;
    var_classes[num_var_classes].classname = classname;
    num_var_classes++;
}

char*
get_var_class(char *varname)
{
    int i;
    for(i=0; i<num_var_classes; i++){
        if(strcmp(var_classes[i].varname, varname) == 0)
            return var_classes[i].classname;
    }
    return nil;
}

void
mark_locals(Node *n)
{
    if(n == nil) return;
    if(n->type == NLocalVar && n->name) {
        if(num_locals < 128) local_vars[num_locals++] = n->name;
    }
    mark_locals(n->left);
    mark_locals(n->right);
    mark_locals(n->next);
}

int
is_local(char *name)
{
    int i;
    for(i=0; i<num_locals; i++){
        if(strcmp(local_vars[i], name) == 0) return 1;
    }
    return 0;
}

void gen_expr(Node *e);

void
gen_expr(Node *e)
{
    if(e == nil) return;
    switch(e->type){
    case NIdent:
        if(is_local(e->name))
            print("%s", e->name);
        else if(in_class_context)
            print("self->%s", e->name);
        else
            print("%s", e->name);
        break;
    case NIntLit:
        print("%s", e->name);
        break;
    case NStringLit:
        print("\"%s\"", e->name);
        break;
    case NCharLit:
        print("'%s'", e->name);
        break;
    case NBoolLit:
        print("%s", e->name);
        break;
    case NMsgSend:
        /* c.method(args...) -> obj9_msgSend(&c, hash, o9_call_args) */
        /* Plan 9 C-compatible: comma expressions for multi-arg, simple call for 0-arg */
        {
            int nargs = 0;
            Node *a;
            for(a = e->right; a; a = a->next) nargs++;
            if(nargs > 0){
                /* Assign args to global buffer using comma ops */
                int i = 0;
                int first = 1;
                for(a = e->right; a; a = a->next){
                    if(first) print("(o9_call_args[%d]=", i);
                    else      print(", o9_call_args[%d]=", i);
                    gen_expr(a);
                    first = 0;
                    i++;
                }
                print(", (vlong)obj9_msgSend(&");
            } else {
                print("((vlong)obj9_msgSend(&");
            }
            gen_expr(e->left);
            print(", 0x%lux, o9_call_args))", o9_hash(e->name));
        }
        break;
    case NAdd:
        print("("); gen_expr(e->left); print(" + "); gen_expr(e->right); print(")");
        break;
    case NSub:
        print("("); gen_expr(e->left); print(" - "); gen_expr(e->right); print(")");
        break;
    case NMul:
        print("("); gen_expr(e->left); print(" * "); gen_expr(e->right); print(")");
        break;
    case NDiv:
        print("("); gen_expr(e->left); print(" / "); gen_expr(e->right); print(")");
        break;
    case NMod:
        print("("); gen_expr(e->left); print(" %% "); gen_expr(e->right); print(")");
        break;
    case NEq:
        print("("); gen_expr(e->left); print(" == "); gen_expr(e->right); print(")");
        break;
    case NNe:
        print("("); gen_expr(e->left); print(" != "); gen_expr(e->right); print(")");
        break;
    case NLt:
        print("("); gen_expr(e->left); print(" < "); gen_expr(e->right); print(")");
        break;
    case NLe:
        print("("); gen_expr(e->left); print(" <= "); gen_expr(e->right); print(")");
        break;
    case NGt:
        print("("); gen_expr(e->left); print(" > "); gen_expr(e->right); print(")");
        break;
    case NGe:
        print("("); gen_expr(e->left); print(" >= "); gen_expr(e->right); print(")");
        break;
    case NAnd:
        print("("); gen_expr(e->left); print(" && "); gen_expr(e->right); print(")");
        break;
    case NOr:
        print("("); gen_expr(e->left); print(" || "); gen_expr(e->right); print(")");
        break;
    case NBitAnd:
        print("("); gen_expr(e->left); print(" & "); gen_expr(e->right); print(")");
        break;
    case NBitOr:
        print("("); gen_expr(e->left); print(" | "); gen_expr(e->right); print(")");
        break;
    case NBitXor:
        print("("); gen_expr(e->left); print(" ^ "); gen_expr(e->right); print(")");
        break;
    case NLshift:
        print("("); gen_expr(e->left); print(" << "); gen_expr(e->right); print(")");
        break;
    case NRshift:
        print("("); gen_expr(e->left); print(" >> "); gen_expr(e->right); print(")");
        break;
    case NNot:
        print("!"); gen_expr(e->left);
        break;
    case NBitNot:
        print("~"); gen_expr(e->left);
        break;
    case NNeg:
        print("-"); gen_expr(e->left);
        break;
    case NFuncCall:
        /* Built-in functions like print(...) */
        if(strcmp(e->name, "print") == 0){
            /* Emit print("fmt", args...) directly */
            print("print(");
            int first = 1;
            Node *a;
            for(a = e->left; a; a = a->next){
                if(!first) print(", ");
                gen_expr(a);
                first = 0;
            }
            print(")");
        } else {
            /* Unknown function call — just emit as-is */
            print("%s(", e->name);
            int first = 1;
            Node *a;
            for(a = e->left; a; a = a->next){
                if(!first) print(", ");
                gen_expr(a);
                first = 0;
            }
            print(")");
        }
        break;
    }
}

void gen_stmt(Node *c, Node *s);

void
gen_stmt(Node *c, Node *s)
{
    Node *n;
    if(s == nil) return;
    switch(s->type){
    case NLocalVar:
        {
            char *cname = find_class(s->typename) ? s->typename : nil;
            int is_new = (s->left && s->left->type == NClass && s->left->name);
            if(in_class_context || cname == nil){
                /* Plain local variable */
                print("\t%s %s", map_type(s->typename), s->name);
                if(s->left && !is_new){
                    print(" = "); gen_expr(s->left);
                }
                print(";\n");
            } else if(is_new && cname){
                /* Counter c = new Counter(...) -> spawn in-process server + client */
                char *cn = cname;
                /* Count constructor args from TNEW node's call_args (s->left->right) */
                int nctor = 0;
                {
                    Node *ca;
                    for(ca = s->left->right; ca; ca = ca->next) nctor++;
                }
                print("\t%s_Internal *__%s = emalloc9p(sizeof(%s_Internal));\n", cn, s->name, cn);
                print("\tmemset(__%s, 0, sizeof(%s_Internal));\n", s->name, cn);
                print("\t__%s->dispatch_chan = chancreate(sizeof(void*), 10);\n", s->name);
                print("\t%s_Client %s;\n", cn, s->name);
                print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cn);
                print("\t%s.dispatch_chan = __%s->dispatch_chan;\n", s->name, s->name);
                if(find_class(cn)){
                    Node *cnode = find_class(cn);
                    Node *m;
                    for(m = cnode->left; m; m = m->next){
                        if(m->type == NProp || m->type == NState || m->type == NAtomic){
                            print("\t__%s->%s = 0;\n", s->name, m->name);
                        }
                    }
                }
                print("\tproccreate(%s_loop, __%s, 8192);\n", cn, s->name);
                /* Send constructor args if any */
                if(nctor > 0){
                    /* Use global o9_call_args buffer (Plan 9 C compatible) */
                    int first = 1;
                    Node *ca;
                    int ai = 0;
                    for(ca = s->left->right; ca; ca = ca->next){
                        if(first) print("\to9_call_args[%d]=", ai);
                        else      print("\t\no9_call_args[%d]=", ai);
                        gen_expr(ca);
                        print(";\n");
                        first = 0;
                        ai++;
                    }
                    print("\tobj9_msgSend(&%s, 0x%lux, o9_call_args);\n", s->name, o9_hash(cname));
                }
            } else {
                /* Class-typed variable with client init (no new) */
                print("\t%s_Client %s;\n", cname, s->name);
                print("\to9_AsmTable %s_tbl;\n", s->name);
                print("\tmemset(&%s, 0, sizeof(%s_Client));\n", s->name, cname);
                print("\tmemset(&%s_tbl, 0, sizeof(o9_AsmTable));\n", s->name);
                print("\t%s.table = &%s_tbl;\n", s->name, s->name);
                print("\to9_init_client(&%s, \"%s\", 4096);\n", s->name, cname);
            }
        }
        break;
        break;
    case NChanSend: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; sendp("); gen_expr(s->left); print(", __box); }\n");
        break;
    }
    case NChanTry: {
        char *t = "vlong";
        if(s->right->type == NIdent) t = get_sym_type(c, s->right->name);
        print("\t{ %s *__box = malloc(sizeof(%s)); *__box = (%s)", t, t, t); gen_expr(s->right); print("; Alt __a[] = {{"); gen_expr(s->left); print(", __box, CHANSND}, {nil, nil, CHANNOBLK}, {nil, nil, CHANEND}}; if(alt(__a) == 1) free(__box); }\n");
        break;
    }
    case NChanRecv: {
        char *t = "vlong";
        if(s->left->type == NIdent) t = get_sym_type(c, s->left->name);
        print("\t{ %s *__box = recvp(", t); gen_expr(s->right); print("); if(__box){ "); gen_expr(s->left); print(" = *__box; free(__box); } }\n");
        break;
    }
    case NAssign:
        print("\t"); gen_expr(s->left); print(" = "); gen_expr(s->right); print(";\n");
        break;
    case NReturn:
        if(in_method_body){
            has_return = 1;
            print("\tr->ret = (void*)("); gen_expr(s->left); print(");\n\tgoto done;\n");
        } else {
            print("\treturn "); gen_expr(s->left); print(";\n");
        }
        break;
    case NIf:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NIfElse:
        print("\tif("); gen_expr(s->left); print("){\n");
        for(n = s->right->left; n; n = n->next) gen_stmt(c, n);
        print("\t} else {\n");
        for(n = s->right->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    case NWhile:
        print("\twhile("); gen_expr(s->left); print("){\n");
        for(n = s->right; n; n = n->next) gen_stmt(c, n);
        print("\t}\n");
        break;
    default:
        print("\t"); gen_expr(s); print(";\n");
        break;
    }
}

void
gen_class_header(Node *c)
{
    Node *m;
    print("/* Generated Client Header for class %s */\n", c->name);
    print("#ifndef _O9_GEN_%s_H_\n#define _O9_GEN_%s_H_\n\n", c->name, c->name);
    print("typedef struct %s_AsmTable {\n\tvoid *data_cache[64];\n\tvoid (*ctrl_cache[64])(void*);\n} %s_AsmTable;\n\n", c->name, c->name);
    print("typedef struct %s_Client {\n\tint fd;\n\to9_AsmTable *table;\n\tlong ref;\t/* ARC Counter */\n\tvoid *dispatch_chan;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_Client;\n", m->name);
    }
    print("} %s_Client;\n\n#endif\n\n", c->name);
}

void
gen_cache_entries(Node *c, char *classname)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_cache_entries(p, classname);
        }
        if(m->type == NProp) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"d:%ld:%ld\\n\", %ldL, (long)o9_offsetof(%s_State, %s));\n", o9_hash(m->name), classname, m->name);
        if(m->type == NMethod) print("\t\tp += snprint(p, sizeof buf - (p-buf), \"c:%ld:%p\\n\", %ldL, (long)o9_impl_%s_%s);\n", o9_hash(m->name), c->name, m->name);
    }
}

void
gen_prop_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_handlers(p);
        }
        if(m->type == NProp){
            print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
            print("\t\tsnprint(buf, sizeof buf, \"%%lld\\n\", (vlong)s->%s);\n", m->name);
            print("\t\treadstr(r, buf);\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_write_handlers(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_write_handlers(p);
        }
        if(m->type == NProp){
            print("\tif(strcmp(r->fid->file->name, \"%s\") == 0){\n", m->name);
            print("\t\ts->%s = strtoll(r->ifcall.data, nil, 0);\n", m->name);
            print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
        }
    }
}

void
gen_prop_create(Node *c)
{
    Node *m, *p;
    if(c == nil) return;
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit){
            p = find_class(m->name);
            if(p) gen_prop_create(p);
        }
        if(m->type == NProp) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    }
}

void
gen_class_server(Node *c)
{
    Node *m, *s;
    print("/* Implementation for class %s (Tiered CSP/9P Model) */\n", c->name);

    /* 1. State Structure (internal authoritative state) */
    print("typedef struct %s_Internal %s_Internal;\n", c->name, c->name);
    print("struct %s_Internal {\n\tArcLedger ledger;\n", c->name);
    for(m = c->left; m; m = m->next){
        if(m->type == NInherit) print("\t%s_Internal;\n", m->name);
        if(m->type == NProp || m->type == NState || m->type == NAtomic) 
            print("\t%s %s;\n", map_type(m->typename), m->name);
        if(m->type == NStream)
            print("\tChannel *%s;\n", m->name);
    }
    print("\tChannel *dispatch_chan;\n");
    print("};\n\n");

    int has_destruct = 0;
    /* 2. Method Implementations (as internal functions) */
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod){
            num_locals = 0;
            mark_locals(m->left);
            /* Register param names as locals so gen_expr emits bare names */
            {
                Node *p;
                for(p = m->right; p; p = p->next){
                    if(num_locals < 128) local_vars[num_locals++] = p->name;
                }
            }
            print("static void o9_impl_%s_%s(%s_Internal *self, O9Msg *msg) {\n", c->name, m->name, c->name);
            print("\tO9Reply *r = mallocz(sizeof(O9Reply), 1);\n");
            /* Unpack params from msg->args (packed as vlong array for now) */
            {
                Node *p;
                int pi = 0;
                for(p = m->right; p; p = p->next){
                    print("\t%s %s = ((vlong*)msg->args)[%d];\n", map_type(p->typename), p->name, pi);
                    pi++;
                }
            }
            in_method_body = 1;
            has_return = 0;
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            in_method_body = 0;
            if(has_return) print("done:\n");
            print("\tr->ok = 1;\n\tsendp(msg->replyc, r);\n}\n\n");
        }
        if(m->type == NDestructor){
            has_destruct = 1;
            num_locals = 0;
            mark_locals(m->left);
            print("static void o9_destruct_%s(%s_Internal *self) {\n", c->name, c->name);
            for(s = m->left; s; s = s->next) gen_stmt(c, s);
            print("}\n\n");
        }
    }

    print("static void o9_cleanup_%s(%s_Internal *self) {\n", c->name, c->name);
    if (has_destruct) {
        print("\to9_destruct_%s(self);\n", c->name);
    }
    print("\tchanfree(self->dispatch_chan);\n");
    print("\tfree(self);\n");
    print("}\n\n");

    /* 3. CSP Dispatch Loop */
    print("static void %s_loop(void *v) {\n", c->name);
    print("\t%s_Internal *self = v;\n\tO9Msg *m;\n", c->name);
    print("\tfor(;;){\n\t\tm = recvp(self->dispatch_chan);\n\t\tif(m == nil) continue;\n");
    print("\t\tswitch(m->sel){\n");
    for(m = c->left; m; m = m->next){
        if(m->type == NMethod)
            print("\t\tcase 0x%lux: o9_impl_%s_%s(self, m); break;\n", o9_hash(m->name), c->name, m->name);
    }
    print("\t\tcase 0x%lux: o9_cleanup_%s(self); threadexits(nil); break;\n", o9_hash("destroy"), c->name);
    print("\t\tdefault: { O9Reply *r = mallocz(sizeof(O9Reply), 1); r->err = \"bad selector\"; sendp(m->replyc, r); } break;\n");
    print("\t\t}\n\t}\n}\n\n");

    /* 4. 9P Fileserver Facade (fsread/fswrite) */
    print("static void fsread_%s(Req *r) {\n", c->name);
    print("\tchar buf[1024];\n\t%s_Internal *s = r->srv->aux;\n", c->name);
    print("\tchar *name = r->fid->file->name;\n\n");
    print("\tif(strcmp(name, \"status\") == 0) { readstr(r, \"running\"); respond(r, nil); return; }\n");
    
    /* props/ sub-directory logic would go here, simplified for MVP */
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            char *fmt = type_fmt(t);
            char *cast = type_cast(t);
            if(strcmp(fmt, "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%%s\\n\", s->%s ? s->%s : \"\");\n", m->name, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tsnprint(buf, sizeof buf, \"%s\\n\", (%s)s->%s);\n", fmt, cast, m->name);
                print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"not found\");\n}\n\n");

    print("static void fswrite_%s(Req *r) {\n", c->name);
    print("\t%s_Internal *s = r->srv->aux;\n\tchar *name = r->fid->file->name;\n", c->name);
    print("\tif(strcmp(name, \"ctl\") == 0) { /* TODO: parse text ctl */ respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"msg\") == 0) { /* TODO: parse binary msg */ respond(r, nil); return; }\n");
    
    for(m = c->left; m; m = m->next){
        if(m->type == NProp || m->type == NAtomic){
            char *t = map_type(m->typename);
            if(strcmp(type_fmt(t), "%s") == 0) {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\tfree(s->%s);\n", m->name);
                print("\t\ts->%s = strdup(r->ifcall.data);\n", m->name);
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            } else {
                print("\tif(strcmp(name, \"%s\") == 0){\n", m->name);
                print("\t\ts->%s = (%s)strtoll(r->ifcall.data, nil, 0);\n", m->name, type_cast(t));
                print("\t\tr->ofcall.count = r->ifcall.count;\n\t\trespond(r, nil);\n\t\treturn;\n\t}\n");
            }
        }
    }
    print("\trespond(r, \"read only or not found\");\n}\n\n");

    print("Srv o9srv_%s;\n\n", c->name);

    print("void o9_main_%s(int argc, char **argv) {\n", c->name);
    print("\t%s_Internal *s = emalloc9p(sizeof(%s_Internal));\n", c->name, c->name);
    print("\tmemset(s, 0, sizeof(%s_Internal));\n", c->name);
    print("\ts->dispatch_chan = chancreate(sizeof(void*), 10);\n");
    print("\to9srv_%s.read = fsread_%s;\n\to9srv_%s.write = fswrite_%s;\n", c->name, c->name, c->name, c->name);
    print("\to9srv_%s.aux = s;\n", c->name);
    print("\tTree *t = alloctree(nil, nil, 0555, nil);\n\to9srv_%s.tree = t;\n", c->name);
    print("\tcreatefile(t->root, \"ctl\", nil, 0222, nil);\n");
    print("\tcreatefile(t->root, \"msg\", nil, 0222, nil);\n");
    print("\tcreatefile(t->root, \"status\", nil, 0444, nil);\n");
    print("\tcreatefile(t->root, \"cache\", nil, 0444, nil);\n");
    for(m = c->left; m; m = m->next) if(m->type == NProp || m->type == NAtomic) print("\tcreatefile(t->root, \"%s\", nil, 0666, nil);\n", m->name);
    print("\tproccreate(%s_loop, s, 8192);\n", c->name);
    print("\tthreadpostmountsrv(&o9srv_%s, \"%s\", nil, MREPL);\n}\n", c->name, c->name);
}

ulong
o9_hash(char *str)
{
    ulong hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    return hash & 0xFFFFFFFFul;
}

void
codegen(Node *root)
{
    Node *n;
    
    print("/* Generated o9 Source */\n");
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include \"o9.h\"\n\n");
    print("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    print("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    print("vlong o9_call_args[64];\n");
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n");
    print("#endif\n\n");

    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_class_header(n);
        }
    }
    Node *main_func = nil;
    Node *last = nil;
    for(n = root; n; n = n->next){
        if(n->type == NClass) {
            gen_class_server(n);
            last = n;
        }
        if(n->type == NMethod && strcmp(n->name, "main") == 0){
            main_func = n;
        }
    }
    print("void\nthreadmain(int argc, char **argv)\n{\n");
    if(last){
        print("\to9_main_%s(argc, argv);\n", last->name);
    }
    if(main_func){
        num_locals = 0;
        mark_locals(main_func->left);
        in_class_context = 0;
        for(n = main_func->left; n; n = n->next)
            gen_stmt(nil, n);
    }
    /* Also need a global flag for class init tracking */
    if(main_func && last){
        /* The class server was started by o9_main_Counter above.
         * Variables declared in main() still need o9_Object init if
         * they are class-typed. The var_class table tracks which
         * variables map to which classes. This is a TODO for now. */
    }
    print("\tthreadexitsall(nil);\n}\n");
}

int
main(int argc, char **argv)
{
    bin = Bfdopen(0, OREAD);
    if(yyparse() == 0)
        codegen(ast_root);
    exits(nil);
    return 0;
}
