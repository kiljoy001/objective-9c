#ifndef _O9_TYPE_H_
#define _O9_TYPE_H_

typedef struct Type Type;
typedef struct TypeList TypeList;

enum {
	TyName,
	TyParam,
	TyApply,
	TyPtr,
	TyArray
};

struct Type {
	int kind;
	char *name;
	Type *base;
	TypeList *args;
};

struct TypeList {
	Type *type;
	TypeList *next;
};

Type *type_name(char *name);
Type *type_param(char *name);
Type *type_apply(char *name, TypeList *args);
Type *type_ptr(Type *base);
Type *type_array(Type *base);
TypeList *type_list(Type *type);
TypeList *type_list_append(TypeList *list, Type *type);
int type_list_len(TypeList *list);
int type_builtin_count(void);
char *type_builtin_name(int idx);
int type_is_builtin_name(char *name);
char *type_builtin_plan9(char *name);
char *type_builtin_abi(char *name);
char *type_builtin_fmt(char *name);
char *type_builtin_zero(char *name);
char *type_render(Type *type);
char *type_dump(Type *type);
char *type_cname(Type *type);
char *type_storage(Type *type);
char *type_plan9(Type *type);
char *type_abi(Type *type);
char *type_fmt(Type *type);
char *type_zero(Type *type);
int type_equal(Type *a, Type *b);
int type_assignable(Type *target, Type *actual);

#endif
