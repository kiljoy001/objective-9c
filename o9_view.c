#include <u.h>
#include <libc.h>
#include <thread.h>
#include <fcall.h>
#include <9p.h>
#include "o9.h"

enum { VF_FIXED = 1, VF_TREE, VIEW_FID_MAGIC = 0x39564944 };

typedef struct O9View O9View;
typedef struct O9ViewFid O9ViewFid;
struct O9View {
	char id[65];
	O9FileTree *tree;
	int active;
	int refs;
};
struct O9ViewFid {
	int magic;
	int kind;
	O9View *view;
	File *fixed;
	void *stage;
	O9FTEntry *entry;
	O9FTEntry **stack;
	int depth;
	int cap;
	char *path;
	O9FTEntry **listing;
	int nlisting;
	Readdir *rootdir;
};

static Tree *view_root;
static o9_Object view_controller;
static int view_has_controller;
static QLock view_lock;
static void view_identity(Req *r);

static Qid
view_qid(int kind, O9View *v, O9FTEntry *e)
{
	Qid q;
	memset(&q, 0, sizeof q);
	if(kind == VF_FIXED) return view_root->root->qid;
	q.path = ((uvlong)1 << 62);
	if(kind == VF_TREE && e != nil) q.path |= o9_filetree_id(e) + 16;
	if(kind == VF_TREE && e != nil && o9_filetree_kind(e) == O9FT_DIR) q.type = QTDIR;
	USED(v);
	return q;
}

static O9ViewFid*
view_ctx(int kind)
{
	O9ViewFid *c;
	c = mallocz(sizeof *c, 1);
	if(c != nil){ c->magic = VIEW_FID_MAGIC; c->kind = kind; c->path = strdup(""); }
	return c;
}

static void
view_ctx_free(O9ViewFid *c)
{
	if(c == nil) return;
	if(c->rootdir != nil) closedirfile(c->rootdir);
	if(c->fixed != nil) closefile(c->fixed);
	if(c->view != nil){
		qlock(&view_lock);
		if(--c->view->refs == 0){
			free(c->view);
		}
		qunlock(&view_lock);
	}
	free(c->listing);
	free(c->stack);
	free(c->path);
	free(c);
}

void
o9_view_setup(Tree *root)
{
	view_root = root;
}

int
o9_view_register_controller(void *object)
{
	o9_Object *o;
	if(object == nil) return -1;
	o = object;
	if(o->dispatch_chan == nil || o->distance != -1) return -1;
	qlock(&view_lock);
	if(view_has_controller){ qunlock(&view_lock); return -1; }
	view_controller = *o;
	view_has_controller = 1;
	qunlock(&view_lock);
	return 0;
}

int
o9_view_attach(Req *r)
{
	O9ViewFid *c;
	O9View *v;
	O9FileTree *tree;
	O9String *id, *caller;
	vlong args[2];
	char *username;
	if(r == nil || r->fid == nil || view_root == nil) return -1;
	c = view_ctx(VF_FIXED);
	if(c == nil) return -1;
	c->fixed = r->fid->file;
	r->fid->file = nil;
	r->fid->aux = c;
	r->fid->qid = view_root->root->qid;
	r->ofcall.qid = r->fid->qid;
	if(!view_has_controller) return 0;
	id = o9_keygen();
	username = "anonymous";
	if(r->srv != nil && r->srv->authok && r->fid->uid != nil &&
	   strcmp(r->fid->uid, "none") != 0) username = r->fid->uid;
	caller = o9_string_from_c(username);
	if(id == nil || caller == nil){ o9_string_release(id); o9_string_release(caller); return -1; }
	args[0] = (vlong)(uintptr)id;
	args[1] = (vlong)(uintptr)caller;
	view_identity(r);
	if(r->srv != nil) srvrelease(r->srv);
	tree = obj9_msgSendN(&view_controller, "display", o9_hash("display"), args, 2);
	if(r->srv != nil) srvacquire(r->srv);
	o9_set_current_request(nil, 0);
	if(tree != nil && o9_filetree_alive(tree) &&
	   o9_filetree_owner(tree) == view_controller.dispatch_chan){
		v = mallocz(sizeof *v, 1);
		if(v == nil){ o9_string_release(id); o9_string_release(caller); return -1; }
		snprint(v->id, sizeof v->id, "%s", o9_string_data(id));
		v->tree = tree;
		v->active = 1;
		v->refs = 1;
		c->view = v;
	}else if(tree != nil){
		o9_string_release(id); o9_string_release(caller); return -1;
	}
	o9_string_release(id);
	o9_string_release(caller);
	return 0;
}

char*
o9_view_clone(Fid *fid, Fid *newfid)
{
	O9ViewFid *src, *dst;
	if(fid == nil || (src = fid->aux) == nil || src->magic != VIEW_FID_MAGIC) return "bad view fid";
	dst = view_ctx(src->kind);
	if(dst == nil) return "no memory";
	dst->view = src->view;
	if(dst->view != nil){ qlock(&view_lock); dst->view->refs++; qunlock(&view_lock); }
	dst->fixed = src->fixed;
	if(dst->fixed != nil) incref(dst->fixed);
	dst->entry = src->entry;
	free(dst->path);
	dst->path = strdup(src->path != nil ? src->path : "");
	if(dst->path == nil){ view_ctx_free(dst); return "no memory"; }
	if(src->depth > 0){
		dst->stack = malloc(src->depth * sizeof *dst->stack);
		if(dst->stack == nil){ view_ctx_free(dst); return "no memory"; }
		memmove(dst->stack, src->stack, src->depth * sizeof *dst->stack);
		dst->depth = dst->cap = src->depth;
	}
	newfid->aux = dst;
	return nil;
}

static int
view_push(O9ViewFid *c, O9FTEntry *e)
{
	O9FTEntry **v;
	char *p;
	int n;
	if(c->depth == c->cap){
		int cap;
		cap = c->cap ? c->cap * 2 : 8;
		v = realloc(c->stack, cap * sizeof *v);
		if(v == nil) return -1;
		c->stack = v;
		c->cap = cap;
	}
	n = strlen(c->path) + strlen(o9_filetree_name(e)) + 2;
	p = malloc(n);
	if(p == nil) return -1;
	if(c->path[0] != 0) snprint(p, n, "%s/%s", c->path, o9_filetree_name(e));
	else snprint(p, n, "%s", o9_filetree_name(e));
	free(c->path);
	c->path = p;
	c->stack[c->depth++] = e;
	c->entry = e;
	return 0;
}

static void
view_pop(O9ViewFid *c)
{
	char *slash;
	if(c->depth <= 0) return;
	c->depth--;
	c->entry = c->depth ? c->stack[c->depth-1] : o9_filetree_root(c->view->tree);
	slash = strrchr(c->path, '/');
	if(slash != nil) *slash = 0;
	else c->path[0] = 0;
}

char*
o9_view_walk1(Fid *fid, char *name, Qid *qid)
{
	O9ViewFid *c;
	O9FTEntry *e;
	File *f, *old;
	if(fid == nil || name == nil || qid == nil) return "bad fid";
	c = fid->aux;
	if(c == nil || c->magic != VIEW_FID_MAGIC) return "bad view fid";
	if(strcmp(name, ".") == 0){ *qid = fid->qid; return nil; }
	if(c->kind == VF_FIXED){
		old = c->fixed;
		if(old == view_root->root && strcmp(name, "view") == 0){
			if(c->view == nil || !c->view->active) return "view unavailable";
			closefile(c->fixed);
			c->fixed = nil;
			c->kind = VF_TREE;
			c->entry = o9_filetree_root(c->view->tree);
			*qid = view_qid(VF_TREE, c->view, c->entry);
			return nil;
		}
		if(old == nil) return "bad fid";
		incref(old);
		f = walkfile(old, name);
		if(f == nil) return "not found";
		closefile(old);
		c->fixed = f;
		*qid = f->qid;
		return nil;
	}
	if(c->kind != VF_TREE || c->view == nil || !c->view->active || !o9_filetree_alive(c->view->tree))
		return "view closed";
	if(strcmp(name, "..") == 0){
		if(c->depth == 0){
			c->kind = VF_FIXED;
			c->entry = nil;
			c->fixed = view_root->root;
			incref(c->fixed);
			*qid = c->fixed->qid;
		}
		else{ view_pop(c); *qid = view_qid(VF_TREE, c->view, c->entry); }
		return nil;
	}
	e = o9_filetree_lookup(c->view->tree, c->entry, name);
	if(e == nil) return "not found";
	if(view_push(c, e) < 0) return "no memory";
	*qid = view_qid(VF_TREE, c->view, e);
	return nil;
}

static int
view_valid(O9ViewFid *c)
{
	return c->kind != VF_TREE ||
		(c->view != nil && c->view->active && o9_filetree_alive(c->view->tree) &&
		 o9_filetree_alive(o9_filetree_entry_tree(c->entry)));
}

/* Keep lib9p's fixed facade File in our fid context so every walk stays
 * attached to the controller-selected view. Generated fixed-file handlers
 * temporarily use the ordinary File/aux fields during their call. */
void*
o9_view_enter_fixed(Fid *f)
{
	O9ViewFid *c;
	if(f == nil || (c = f->aux) == nil || c->magic != VIEW_FID_MAGIC ||
	   c->kind != VF_FIXED) return nil;
	f->file = c->fixed;
	f->aux = c->stage;
	return c;
}

void
o9_view_leave_fixed(Fid *f, void *context)
{
	O9ViewFid *c;
	if(f == nil || context == nil) return;
	c = context;
	if(c->fixed != f->file && c->fixed != nil) closefile(c->fixed);
	c->fixed = f->file;
	c->stage = f->aux;
	f->file = nil;
	f->aux = c;
}

File*
o9_view_request_file(Req *r)
{
	O9ViewFid *c;
	if(r == nil || r->fid == nil) return nil;
	if(r->fid->file != nil) return r->fid->file;
	c = r->fid->aux;
	if(c != nil && c->magic == VIEW_FID_MAGIC && c->kind == VF_FIXED)
		return c->fixed;
	return nil;
}

static void
view_identity(Req *r)
{
	if(r != nil && r->srv != nil && r->srv->authok && r->fid != nil &&
	   r->fid->uid != nil && strcmp(r->fid->uid, "none") != 0)
		o9_set_current_request(r->fid->uid, 1);
	else o9_set_current_request("anonymous", 0);
}

static O9String*
view_live_read(Req *r, O9ViewFid *c)
{
	O9String *id, *path, *result;
	vlong args[2];
	id = o9_string_from_c(c->view->id);
	path = o9_string_from_c(c->path);
	if(id == nil || path == nil){ o9_string_release(id); o9_string_release(path); return nil; }
	args[0] = (vlong)(uintptr)id;
	args[1] = (vlong)(uintptr)path;
	view_identity(r);
	if(r->srv != nil) srvrelease(r->srv);
	result = obj9_msgSendN(&view_controller, "readText", o9_hash("readText"), args, 2);
	if(r->srv != nil) srvacquire(r->srv);
	o9_set_current_request(nil, 0);
	o9_string_release(id);
	o9_string_release(path);
	return result;
}

static vlong
view_live_write(Req *r, O9ViewFid *c, vlong offset, O9String *data, int truncate)
{
	O9String *id, *path;
	vlong args[5], result;
	id = o9_string_from_c(c->view->id);
	path = o9_string_from_c(c->path);
	if(id == nil || path == nil){ o9_string_release(id); o9_string_release(path); return -1; }
	args[0] = (vlong)(uintptr)id;
	args[1] = (vlong)(uintptr)path;
	args[2] = offset;
	args[3] = (vlong)(uintptr)data;
	args[4] = truncate;
	view_identity(r);
	if(r->srv != nil) srvrelease(r->srv);
	result = (vlong)(uintptr)obj9_msgSendN(&view_controller, "writeText", o9_hash("writeText"), args, 5);
	if(r->srv != nil) srvacquire(r->srv);
	o9_set_current_request(nil, 0);
	o9_string_release(id);
	o9_string_release(path);
	if(o9_get_call_err() != nil) return -1;
	return result;
}

static void
view_fill_dir(Dir *d, int kind, O9View *view, O9FTEntry *entry, char *name)
{
	O9String *data;
	memset(d, 0, sizeof *d);
	d->qid = view_qid(kind, view, entry);
	d->name = strdup(name);
	d->uid = strdup("o9");
	d->gid = strdup("o9");
	d->muid = strdup("o9");
	d->mode = (d->qid.type & QTDIR) ? DMDIR|0555 : 0444;
	if(kind == VF_TREE && o9_filetree_writable(entry)) d->mode = 0666;
	if(kind == VF_TREE && o9_filetree_kind(entry) == O9FT_TEXT){
		data = o9_filetree_data(view->tree, entry);
		d->length = o9_string_len(data);
		o9_string_release(data);
	}
	d->atime = d->mtime = time(0);
}

static int
view_dirgen(int index, Dir *d, void *aux)
{
	O9ViewFid *c;
	O9FTEntry *e;
	c = aux;
	if(index < 0 || index >= c->nlisting) return -1;
	e = c->listing[index];
	view_fill_dir(d, VF_TREE, c->view, e, o9_filetree_name(e));
	return 0;
}

int
o9_view_open(Req *r)
{
	O9ViewFid *c;
	int mode;
	O9String *empty;
	if(r == nil || r->fid == nil || (c = r->fid->aux) == nil || c->magic != VIEW_FID_MAGIC) return 0;
	if(c->kind == VF_FIXED && !(c->fixed->qid.type & QTDIR)) return 0;
	if(!view_valid(c)){ respond(r, "view closed"); return 1; }
	mode = r->ifcall.mode & 3;
	if((c->kind == VF_FIXED ||
	    (c->kind == VF_TREE && o9_filetree_kind(c->entry) == O9FT_DIR)) && mode != OREAD){
		respond(r, "directory is read only"); return 1;
	}
	if(c->kind == VF_TREE && o9_filetree_kind(c->entry) != O9FT_DIR){
		if((mode == OWRITE || mode == ORDWR || (r->ifcall.mode & OTRUNC)) &&
		   !o9_filetree_writable(c->entry)){ respond(r, "read only"); return 1; }
		if(r->ifcall.mode & OTRUNC){
			empty = o9_string_from_c("");
			if(empty == nil || view_live_write(r, c, 0, empty, 1) < 0){
				o9_string_release(empty); respond(r, "write failed"); return 1;
			}
			o9_string_release(empty);
		}
	}
	if(c->kind == VF_FIXED){
		c->rootdir = opendirfile(c->fixed);
		if(c->rootdir == nil){ respond(r, "directory failed"); return 1; }
	}else if(c->kind == VF_TREE && o9_filetree_kind(c->entry) == O9FT_DIR){
		c->nlisting = o9_filetree_entries(c->view->tree, c->entry, &c->listing);
		if(c->nlisting < 0){ respond(r, "directory failed"); return 1; }
	}
	respond(r, nil);
	return 1;
}

int
o9_view_read(Req *r)
{
	O9ViewFid *c;
	O9String *s;
	if(r == nil || r->fid == nil || (c = r->fid->aux) == nil || c->magic != VIEW_FID_MAGIC) return 0;
	if(c->kind == VF_FIXED && c->fixed != view_root->root &&
	   !(c->fixed->qid.type & QTDIR)) return 0;
	if(!view_valid(c)){ respond(r, "view closed"); return 1; }
	if(c->kind == VF_FIXED){
		if(c->rootdir == nil){ respond(r, "directory not open"); return 1; }
		r->ofcall.count = readdirfile(c->rootdir, (uchar*)r->ofcall.data, r->ifcall.count, r->ifcall.offset);
		respond(r, nil); return 1;
	}
	if(c->kind == VF_TREE && o9_filetree_kind(c->entry) == O9FT_DIR){
		dirread9p(r, view_dirgen, c);
		respond(r, nil); return 1;
	}
	if(c->kind != VF_TREE){ respond(r, "read prohibited"); return 1; }
	if(o9_filetree_kind(c->entry) == O9FT_TEXT)
		s = o9_filetree_data(c->view->tree, c->entry);
	else s = view_live_read(r, c);
	if(s == nil){ respond(r, "read failed"); return 1; }
	readbuf(r, o9_string_data(s), o9_string_len(s));
	o9_string_release(s);
	respond(r, nil);
	return 1;
}

int
o9_view_write(Req *r)
{
	O9ViewFid *c;
	O9String *data;
	vlong n;
	if(r == nil || r->fid == nil || (c = r->fid->aux) == nil || c->magic != VIEW_FID_MAGIC) return 0;
	if(c->kind == VF_FIXED) return 0;
	if(!view_valid(c)){ respond(r, "view closed"); return 1; }
	if(c->kind != VF_TREE || o9_filetree_kind(c->entry) == O9FT_DIR ||
	   !o9_filetree_writable(c->entry)){ respond(r, "write prohibited"); return 1; }
	data = o9_string_new(r->ifcall.data, r->ifcall.count);
	if(data == nil){ respond(r, "no memory"); return 1; }
	n = view_live_write(r, c, r->ifcall.offset, data, 0);
	o9_string_release(data);
	if(n < 0 || n > r->ifcall.count){ respond(r, "write failed"); return 1; }
	r->ofcall.count = n;
	respond(r, nil);
	return 1;
}

int
o9_view_close(Req *r)
{
	O9ViewFid *c;
	O9View *v;
	if(r == nil || r->fid == nil || (c = r->aux) == nil ||
	   c->magic != VIEW_FID_MAGIC) return -1;
	qlock(&view_lock);
	v = c->view;
	if(v != nil) v->active = 0;
	qunlock(&view_lock);
	return v != nil ? 0 : -1;
}

void
o9_view_destroyfid(Fid *f)
{
	if(f != nil && f->aux != nil && ((O9ViewFid*)f->aux)->magic == VIEW_FID_MAGIC){
		view_ctx_free(f->aux);
		f->aux = nil;
	}
}

void
o9_view_remove(Req *r)
{
	respond(r, "remove prohibited");
}

void
o9_view_stat(Req *r)
{
	O9ViewFid *c;
	char *name;
	if(r->fid == nil){ respond(r, "bad fid"); return; }
	c = r->fid->aux;
	if(c == nil || c->magic != VIEW_FID_MAGIC || !view_valid(c)){ respond(r, "view closed"); return; }
	if(c->kind == VF_FIXED){
		r->d = c->fixed->Dir;
		r->d.name = strdup(r->d.name);
		r->d.uid = strdup(r->d.uid);
		r->d.gid = strdup(r->d.gid);
		r->d.muid = strdup(r->d.muid);
	}else{
		name = c->depth == 0 ? "view" : o9_filetree_name(c->entry);
		view_fill_dir(&r->d, c->kind, c->view, c->entry, name);
	}
	respond(r, nil);
}
