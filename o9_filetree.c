#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"

enum { FT_BUCKETS = 64 };

typedef struct O9FTMount O9FTMount;
typedef struct O9FTSource O9FTSource;
struct O9FTMount { O9FileTree *source; int mode; O9FTMount *next; };
struct O9FTSource { char *id; O9FileTree *tree; O9FTSource *next; };
static QLock ft_mount_lock;
static O9FTSource *ft_sources;

struct O9FTEntry {
	char *name;
	uvlong id;
	int kind;
	int writable;
	int removed;
	O9String *data;
	O9FileTree *tree;
	O9FTMount *mounts;
	O9FTEntry *parent;
	O9FTEntry *hashnext;
	O9FTEntry *allnext;
	O9FTEntry *buckets[FT_BUCKETS];
};

struct O9FileTree {
	QLock lock;
	void *owner;
	int alive;
	O9FTEntry *root;
	O9FTEntry *all;
};

static Lock ft_id_lock;
static uvlong ft_next_id = 1;

static uvlong
ft_id(void)
{
	uvlong id;
	lock(&ft_id_lock);
	id = ft_next_id++;
	unlock(&ft_id_lock);
	return id;
}

static uint
ft_bucket(char *name)
{
	uint h;
	uchar *p;
	h = 2166136261U;
	for(p = (uchar*)name; *p; p++)
		h = (h ^ *p) * 16777619U;
	return h % FT_BUCKETS;
}

static int
ft_name_ok(char *name)
{
	uchar *p;
	if(name == nil || *name == 0 || strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
		return 0;
	for(p = (uchar*)name; *p; p++)
		if(*p == '/' || *p < ' ' || *p == 0177)
			return 0;
	return 1;
}

static O9FTEntry*
ft_find(O9FTEntry *dir, char *name)
{
	O9FTEntry *e;
	if(dir == nil || dir->kind != O9FT_DIR)
		return nil;
	for(e = dir->buckets[ft_bucket(name)]; e != nil; e = e->hashnext)
		if(!e->removed && strcmp(e->name, name) == 0)
			return e;
	return nil;
}

static O9FTEntry*
ft_entry(O9FileTree *t, O9FTEntry *parent, char *name, int kind, O9String *data, int writable)
{
	O9FTEntry *e;
	uint b;
	e = mallocz(sizeof *e, 1);
	if(e == nil)
		return nil;
	e->name = strdup(name);
	if(e->name == nil){ free(e); return nil; }
	e->id = ft_id();
	e->kind = kind;
	e->writable = writable;
	e->data = o9_string_retain(data);
	e->tree = t;
	e->parent = parent;
	e->allnext = t->all;
	t->all = e;
	if(parent != nil){
		b = ft_bucket(name);
		e->hashnext = parent->buckets[b];
		parent->buckets[b] = e;
	}
	return e;
}

static int
ft_owned(O9FileTree *t)
{
	return t != nil && t->alive && t->owner == o9_actor_channel();
}

O9FileTree*
o9_filetree_new(void)
{
	O9FileTree *t;
	t = mallocz(sizeof *t, 1);
	if(t == nil)
		return nil;
	t->owner = o9_actor_channel();
	t->alive = 1;
	t->root = ft_entry(t, nil, ".", O9FT_DIR, nil, 0);
	if(t->root == nil){ free(t); return nil; }
	return t;
}

/* Resolve the parent and final name while holding the tree lock. */
static O9FTEntry*
ft_parent(O9FileTree *t, char *path, char **leaf)
{
	O9FTEntry *dir;
	char *p, *slash;
	if(path == nil || *path == 0 || *path == '/' || leaf == nil)
		return nil;
	dir = t->root;
	p = path;
	for(;;){
		slash = strchr(p, '/');
		if(slash == nil){
			if(!ft_name_ok(p)) return nil;
			*leaf = p;
			return dir;
		}
		*slash = 0;
		if(!ft_name_ok(p)) return nil;
		dir = ft_find(dir, p);
		if(dir == nil || dir->kind != O9FT_DIR) return nil;
		p = slash + 1;
	}
}

static int
ft_put(O9FileTree *t, O9String *path, int kind, O9String *data, int writable)
{
	O9FTEntry *parent, *e;
	char *p, *leaf;
	int rv;
	if(!ft_owned(t) || path == nil || (kind == O9FT_TEXT && data == nil)) return -1;
	p = o9_string_cstr(path);
	if(p == nil) return -1;
	rv = -1;
	qlock(&ft_mount_lock);
	qlock(&t->lock);
	parent = t->alive ? ft_parent(t, p, &leaf) : nil;
	if(parent != nil){
		e = ft_find(parent, leaf);
		if(e == nil){
			e = ft_entry(t, parent, leaf, kind, data, writable);
			if(e != nil) rv = 0;
		}else if(e->kind == kind && kind != O9FT_DIR){
			o9_string_release(e->data);
			e->data = o9_string_retain(data);
			e->writable = writable;
			rv = 0;
		}else if(e->kind == kind && kind == O9FT_DIR)
			rv = 0;
	}
	qunlock(&t->lock);
	qunlock(&ft_mount_lock);
	free(p);
	return rv;
}

int o9_filetree_dir(O9FileTree *t, O9String *path) { return ft_put(t, path, O9FT_DIR, nil, 0); }
int o9_filetree_text(O9FileTree *t, O9String *path, O9String *data, vlong writable) { return ft_put(t, path, O9FT_TEXT, data, writable != 0); }
int o9_filetree_live(O9FileTree *t, O9String *path, vlong writable) { return ft_put(t, path, O9FT_LIVE, nil, writable != 0); }

int
o9_filetree_remove(O9FileTree *t, O9String *path)
{
	O9FTEntry *parent, *e, **pp;
	char *p, *leaf;
	int i, rv;
	if(!ft_owned(t) || path == nil) return -1;
	p = o9_string_cstr(path);
	if(p == nil) return -1;
	rv = -1;
	qlock(&ft_mount_lock);
	qlock(&t->lock);
	parent = t->alive ? ft_parent(t, p, &leaf) : nil;
	if(parent != nil && (e = ft_find(parent, leaf)) != nil){
		for(i = 0; i < FT_BUCKETS; i++)
			if(e->buckets[i] != nil) break;
		if(i == FT_BUCKETS){
			for(pp = &parent->buckets[ft_bucket(leaf)]; *pp != nil; pp = &(*pp)->hashnext)
				if(*pp == e){ *pp = e->hashnext; break; }
			e->removed = 1;
			rv = 0;
		}
	}
	qunlock(&t->lock);
	qunlock(&ft_mount_lock);
	free(p);
	return rv;
}

void
o9_filetree_revoke(O9FileTree *t)
{
	O9FTSource **pp, *s;
	if(t == nil) return;
	qlock(&ft_mount_lock);
	qlock(&t->lock);
	t->alive = 0;
	qunlock(&t->lock);
	for(pp = &ft_sources; *pp != nil; ){
		if((*pp)->tree == t){
			s = *pp;
			*pp = s->next;
			free(s->id);
			free(s);
		}else pp = &(*pp)->next;
	}
	qunlock(&ft_mount_lock);
}
void o9_filetree_close(O9FileTree *t) { if(ft_owned(t)) o9_filetree_revoke(t); }
int o9_filetree_alive(O9FileTree *t) { int ok; if(t == nil) return 0; qlock(&t->lock); ok = t->alive; qunlock(&t->lock); return ok; }
void* o9_filetree_owner(O9FileTree *t) { return t != nil ? t->owner : nil; }
O9FTEntry* o9_filetree_root(O9FileTree *t) { return t != nil ? t->root : nil; }
int o9_filetree_kind(O9FTEntry *e) { return e != nil ? e->kind : 0; }
int o9_filetree_writable(O9FTEntry *e) { return e != nil ? e->writable : 0; }
uvlong o9_filetree_id(O9FTEntry *e) { return e != nil ? e->id : 0; }
char* o9_filetree_name(O9FTEntry *e) { return e != nil ? e->name : nil; }
O9FTEntry* o9_filetree_parent(O9FTEntry *e) { return e != nil ? e->parent : nil; }
O9FileTree* o9_filetree_entry_tree(O9FTEntry *e) { return e != nil ? e->tree : nil; }

int
o9_filetree_register(O9FileTree *t, O9String *id)
{
	O9FTSource *s, *p;
	char *name;
	int registered;
	if(!ft_owned(t) || id == nil) return -1;
	name = o9_string_cstr(id);
	if(name == nil) return -1;
	if(!ft_name_ok(name) || strchr(name, '!') != nil || strchr(name, ':') != nil){ free(name); return -1; }
	s = mallocz(sizeof *s, 1);
	if(s == nil){ free(name); return -1; }
	s->id = name;
	s->tree = t;
	qlock(&ft_mount_lock);
	registered = 0;
	for(p = ft_sources; t->alive && p != nil; p = p->next)
		if(strcmp(p->id, name) == 0) break;
	if(t->alive && p == nil){ s->next = ft_sources; ft_sources = s; registered = 1; }
	qunlock(&ft_mount_lock);
	if(!registered){ free(name); free(s); return -1; }
	return 0;
}

static O9FileTree*
ft_resolve(char *id)
{
	O9FTSource *s;
	for(s = ft_sources; s != nil; s = s->next)
		if(strcmp(s->id, id) == 0 && s->tree->alive)
			return s->tree;
	return nil;
}

static O9FTEntry*
ft_lookup_mount(O9FTEntry *dir, char *name, int depth)
{
	O9FTMount *m;
	O9FTEntry *e;
	int replace;
	if(dir == nil || dir->kind != O9FT_DIR || dir->removed || !dir->tree->alive || depth > 64)
		return nil;
	replace = 0;
	for(m = dir->mounts; m != nil; m = m->next){
		if(m->mode == 0) replace = 1;
		if(m->mode == 0 || m->mode == 1){
			e = ft_lookup_mount(m->source->root, name, depth+1);
			if(e != nil) return e;
		}
	}
	if(!replace){
		qlock(&dir->tree->lock);
		e = ft_find(dir, name);
		qunlock(&dir->tree->lock);
		if(e != nil) return e;
	}
	for(m = dir->mounts; m != nil; m = m->next)
		if(m->mode == 2){
			e = ft_lookup_mount(m->source->root, name, depth+1);
			if(e != nil) return e;
		}
	return nil;
}

typedef struct O9FTPlan O9FTPlan;
struct O9FTPlan { O9FTEntry *target; O9FTMount *mounts; O9FTPlan *next; };

static void
ft_free_mounts(O9FTMount *m)
{
	O9FTMount *next;
	while(m != nil){ next = m->next; free(m); m = next; }
}

static O9FTMount*
ft_copy_mounts(O9FTMount *m)
{
	O9FTMount *head, **tail, *copy;
	head = nil;
	tail = &head;
	for(; m != nil; m = m->next){
		copy = mallocz(sizeof *copy, 1);
		if(copy == nil){ ft_free_mounts(head); return nil; }
		copy->source = m->source;
		copy->mode = m->mode;
		*tail = copy;
		tail = &copy->next;
	}
	return head;
}

static O9FTPlan*
ft_plan_for(O9FTPlan *plans, O9FTEntry *entry)
{
	for(; plans != nil; plans = plans->next)
		if(plans->target == entry) return plans;
	return nil;
}

static O9FTEntry*
ft_target(O9FileTree *t, char *path)
{
	char *copy, *p, *slash;
	O9FTEntry *e;
	if(path == nil || *path == 0 || *path == '/') return nil;
	if(strcmp(path, ".") == 0) return t->root;
	copy = strdup(path);
	if(copy == nil) return nil;
	e = t->root;
	p = copy;
	for(;;){
		slash = strchr(p, '/');
		if(slash != nil) *slash = 0;
		if(!ft_name_ok(p)){ e = nil; break; }
		e = ft_find(e, p);
		if(e == nil || e->kind != O9FT_DIR){ e = nil; break; }
		if(slash == nil) break;
		p = slash + 1;
	}
	free(copy);
	return e;
}

static int
ft_reaches(O9FileTree *tree, O9FileTree *goal, O9FTPlan *plans,
	O9FileTree **seen, int nseen)
{
	O9FTEntry *e;
	O9FTMount *m;
	O9FTPlan *p;
	int i;
	if(tree == goal) return 1;
	if(nseen >= 256) return 1;
	for(i = 0; i < nseen; i++) if(seen[i] == tree) return 0;
	seen[nseen++] = tree;
	for(e = tree->all; e != nil; e = e->allnext){
		if(e->removed) continue;
		p = ft_plan_for(plans, e);
		for(m = p != nil ? p->mounts : e->mounts; m != nil; m = m->next)
			if(ft_reaches(m->source, goal, plans, seen, nseen)) return 1;
	}
	return 0;
}

int
o9_filetree_apply_specs(O9FileTree *t, O9FTMountSpec *spec, int n)
{
	O9FTPlan *plans, *p, *next;
	O9FTMount *m, **tail, *old;
	O9FTEntry *target;
	O9FileTree *source, *seen[256];
	int i, rv;
	if(!ft_owned(t) || spec == nil || n < 0) return -1;
	plans = nil;
	rv = -1;
	qlock(&ft_mount_lock);
	if(!t->alive) goto done;
	for(i = 0; i < n; i++){
		target = ft_target(t, spec[i].target);
		if(target == nil) goto done;
		p = ft_plan_for(plans, target);
		if(p == nil){
			p = mallocz(sizeof *p, 1);
			if(p == nil) goto done;
			p->target = target;
			p->mounts = ft_copy_mounts(target->mounts);
			if(target->mounts != nil && p->mounts == nil){ free(p); goto done; }
			p->next = plans;
			plans = p;
		}
		if(spec[i].unmount){
			ft_free_mounts(p->mounts);
			p->mounts = nil;
			continue;
		}
		if(spec[i].mode < 0 || spec[i].mode > 2 || spec[i].source == nil) goto done;
		source = ft_resolve(spec[i].source);
		if(source == nil) goto done;
		m = mallocz(sizeof *m, 1);
		if(m == nil) goto done;
		m->source = source;
		m->mode = spec[i].mode;
		if(m->mode == 0){ ft_free_mounts(p->mounts); p->mounts = nil; }
		if(m->mode == 1){
			m->next = p->mounts;
			p->mounts = m;
		}else{
			for(tail = &p->mounts; *tail != nil; tail = &(*tail)->next) ;
			*tail = m;
		}
	}
	for(p = plans; p != nil; p = p->next)
		for(m = p->mounts; m != nil; m = m->next)
			if(ft_reaches(m->source, t, plans, seen, 0)) goto done;
	for(p = plans; p != nil; p = p->next){
		old = p->target->mounts;
		p->target->mounts = p->mounts;
		p->mounts = nil;
		ft_free_mounts(old);
	}
	rv = 0;
done:
	qunlock(&ft_mount_lock);
	for(p = plans; p != nil; p = next){ next = p->next; ft_free_mounts(p->mounts); free(p); }
	return rv;
}

O9FTEntry*
o9_filetree_lookup(O9FileTree *t, O9FTEntry *parent, char *name)
{
	O9FTEntry *e;
	if(t == nil || parent == nil || name == nil) return nil;
	qlock(&ft_mount_lock);
	e = t->alive ? ft_lookup_mount(parent, name, 0) : nil;
	qunlock(&ft_mount_lock);
	return e;
}

O9String*
o9_filetree_data(O9FileTree *t, O9FTEntry *e)
{
	O9String *s;
	if(t == nil || e == nil) return nil;
	qlock(&e->tree->lock);
	s = t->alive && e->tree->alive && !e->removed ? o9_string_retain(e->data) : nil;
	qunlock(&e->tree->lock);
	return s;
}

typedef struct O9FTList O9FTList;
struct O9FTList { O9FTEntry **v; int n; int cap; };

static int
ft_list_add(O9FTList *list, O9FTEntry *e)
{
	O9FTEntry **v;
	int i, cap;
	for(i = 0; i < list->n; i++)
		if(strcmp(list->v[i]->name, e->name) == 0) return 0;
	if(list->n == list->cap){
		cap = list->cap ? list->cap * 2 : 8;
		v = realloc(list->v, cap * sizeof *v);
		if(v == nil) return -1;
		list->v = v;
		list->cap = cap;
	}
	list->v[list->n++] = e;
	return 0;
}

static int
ft_collect(O9FTEntry *dir, O9FTList *list, int depth)
{
	O9FTMount *m;
	O9FTEntry *e;
	int i, replace;
	if(dir == nil || dir->kind != O9FT_DIR || dir->removed || !dir->tree->alive || depth > 64)
		return -1;
	replace = 0;
	for(m = dir->mounts; m != nil; m = m->next){
		if(m->mode == 0) replace = 1;
		if((m->mode == 0 || m->mode == 1) && ft_collect(m->source->root, list, depth+1) < 0)
			return -1;
	}
	if(!replace){
		qlock(&dir->tree->lock);
		for(i = 0; i < FT_BUCKETS; i++)
			for(e = dir->buckets[i]; e != nil; e = e->hashnext)
				if(ft_list_add(list, e) < 0){ qunlock(&dir->tree->lock); return -1; }
		qunlock(&dir->tree->lock);
	}
	for(m = dir->mounts; m != nil; m = m->next)
		if(m->mode == 2 && ft_collect(m->source->root, list, depth+1) < 0)
			return -1;
	return 0;
}

int
o9_filetree_entries(O9FileTree *t, O9FTEntry *dir, O9FTEntry ***out)
{
	O9FTList list;
	if(out == nil || t == nil || dir == nil || dir->kind != O9FT_DIR) return -1;
	*out = nil;
	memset(&list, 0, sizeof list);
	qlock(&ft_mount_lock);
	if(!t->alive || ft_collect(dir, &list, 0) < 0){
		qunlock(&ft_mount_lock);
		free(list.v);
		return -1;
	}
	qunlock(&ft_mount_lock);
	*out = list.v;
	return list.n;
}
