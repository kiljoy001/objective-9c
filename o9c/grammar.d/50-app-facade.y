/* ========================================================================
 * APP FACADE GENERATION AND PROGRAM EMISSION
 * ======================================================================== */

void
codegen(Node *root)
{
    Node *n;
    ClassDef *cd;

    mono_scan_node(root);

    print("/* Generated o9 Source */\n");
    print("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include <o9.h>\n\n");
    emit_cdeps();
    print("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    print("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    print("typedef struct ArcEntry {\n\tulong id;\n\tlong count;\n} ArcEntry;\n\n");
    print("typedef struct ArcLedger {\n\tArcEntry entries[64];\n} ArcLedger;\n");
    /* Per-app facade: ONE Srv with a fixed root shape, built once at
     * startup.  Root control files are stable; clone creates session dirs
     * and exports/ accepts published tabulae. The served facade does not
     * compose the app from per-object fileservers. ctl names its target
     * instance in the line (method Class.inst method arg...);
     * status/methods list the object graph and public surface by reading.
     *
     * Class handlers register themselves in a small table so the flat
     * ctl/read handler can route to any class's fsread/fswrite body. */
    print("typedef struct O9ClassH O9ClassH;\n");
    print("struct O9ClassH {\n");
    print("\tchar *name;\n");
    print("\tvoid (*read)(Req*, void*);\n");
    print("\tvoid (*write)(Req*, void*);\n");
    print("\tvoid *(*find)(char*);\t/* <C>_find_instance */\n");
    print("\tint (*dumpstate)(char*, int);\t/* <C>_dumpstate: debug */\n");
    print("\tint (*listinst)(char*, int);\t/* <C>_listinstances: append \" name\" per live instance */\n");
    print("};\n");
    print("extern O9ClassH o9app_classes[64];\n");
    print("extern int o9app_nclasses;\n");
    print("extern Srv o9app_srv;\n");
    print("extern Tree *o9app_tree;\n");
    print("extern char o9app_root[128];\n");
    print("extern char o9app_srvname[128];\n");
    print("extern char o9app_mount[256];\n");
    print("extern char o9app_name[64];\n");
    print("extern File *o9app_exports_dir;\t/* served-tree exports/ dir */\n");
    print("extern File *o9app_imports_dir;\t/* served-tree imports/ dir */\n");
    print("static void o9app_register_handler(char *name, void (*rd)(Req*,void*), void (*wr)(Req*,void*), void *(*find)(char*), int (*dump)(char*,int), int (*listinst)(char*,int)){\n");
    print("\tif(o9app_nclasses >= nelem(o9app_classes)) return;\n");
    print("\to9app_classes[o9app_nclasses].name = name;\n");
    print("\to9app_classes[o9app_nclasses].read = rd;\n");
    print("\to9app_classes[o9app_nclasses].write = wr;\n");
    print("\to9app_classes[o9app_nclasses].find = find;\n");
    print("\to9app_classes[o9app_nclasses].dumpstate = dump;\n");
    print("\to9app_classes[o9app_nclasses].listinst = listinst;\n");
    print("\to9app_nclasses++;\n}\n");
    /* Debug gate: O9DEBUG env var exposes live object state via the
     * `state` file.  Off by default — encapsulation preserved. */
    print("extern int o9app_debug;\n");
    /* Split a "Class.inst" token; returns the class handler and writes
     * the bare instance name into instout.  nil if not found. */
    print("static O9ClassH *o9app_resolve(char *tok, char *instout, int n){\n");
    print("\tchar *dot; int i;\n");
    print("\tif(tok == nil) return nil;\n");
    print("\tdot = strchr(tok, '.');\n");
    print("\tif(dot != nil){\n");
    print("\t\tint clen = dot - tok;\n");
    print("\t\tsnprint(instout, n, \"%%s\", dot+1);\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++)\n");
    print("\t\t\tif(strncmp(o9app_classes[i].name, tok, clen) == 0 && o9app_classes[i].name[clen] == '\\0')\n");
    print("\t\t\t\treturn &o9app_classes[i];\n");
    print("\t\treturn nil;\n");
    print("\t}\n");
    /* No class prefix: search every class for an instance of that name */
    print("\tsnprint(instout, n, \"%%s\", tok);\n");
    print("\tfor(i = 0; i < o9app_nclasses; i++)\n");
    print("\t\tif(o9app_classes[i].find != nil && o9app_classes[i].find(tok) != nil)\n");
    print("\t\t\treturn &o9app_classes[i];\n");
    print("\treturn nil;\n}\n");
    print("#endif\n\n");
    /* Shared app-server globals (once per program). */
    print("O9ClassH o9app_classes[64];\n");
    print("int o9app_nclasses;\n");
    print("Srv o9app_srv;\n");
    print("Tree *o9app_tree;\n");
    print("char o9app_root[128];\n");
    print("char o9app_srvname[128];\n");
    print("char o9app_mount[256];\n");
    print("char o9app_name[64];\n");
    print("File *o9app_exports_dir;\t/* served-tree exports/ dir (mutable) */\n");
    print("File *o9app_imports_dir;\t/* served-tree imports/ dir (mutable) */\n");
    print("int o9app_debug;\t/* set from O9DEBUG at startup */\n\n");
    /* One published tabula: its serialized bytes live in the File's aux,
     * served ramfs-style on read.  This is the mutable part of the fs. */
    print("typedef struct O9Export O9Export;\n");
    print("typedef struct O9ImportStage O9ImportStage;\n");
    /* aux tag: both O9Export and O9Session live in File->aux; the first
     * field discriminates them (destroyfid only has the Fid). */
    print("enum { O9AUX_EXPORT = 1, O9AUX_SESSION = 2, O9AUX_IMPORT = 3, O9AUX_IMPORT_STAGE = 4 };\n");
    print("struct O9Export { int tag; QLock lock; char *data; int ndata; };\n\n");
    print("struct O9ImportStage { int tag; O9Export *file; QLock lock; char *data; int ndata; int wrote; int commit; int failed; };\n\n");
    print("static int o9app_export_name_ok(char *s){\n");
    print("\tuchar *p;\n");
    print("\tif(s == nil || s[0] == '\\0' || strcmp(s, \".\") == 0 || strcmp(s, \"..\") == 0) return 0;\n");
    print("\tfor(p = (uchar*)s; *p != '\\0'; p++)\n");
    print("\t\tif(*p < ' ' || *p == 0177 || *p == '/') return 0;\n");
    print("\treturn 1;\n");
    print("}\n\n");
    print("static int o9app_import_name_ok(char *s){\n");
    print("\tint n;\n");
    print("\tif(!o9app_export_name_ok(s)) return 0;\n");
    print("\tn = strlen(s);\n");
    print("\treturn n > 4 && strcmp(s+n-4, \".tab\") == 0;\n");
    print("}\n\n");

    /* exports/ is a served-tree DIRECTORY (part of the application file
     * tree, reachable through the mount) — NOT an on-disk directory.
     * Objects publish tabulae into it at runtime via createfile; the
     * serialized bytes live in the child File's aux. */
    /* Flat root handlers.  The four files share these; ctl routes by the
     * line's Class.inst to a class handler, the rest aggregate. */
    /* Per-session conversation state (docs/SESSIONS.md). Fixes the per-caller
     * race: results/status live on the SESSION, not a global mailbox. A
     * session is allocated by reading `clone`; its dir + ctl/data/status
     * are createfile'd into the served root, each carrying the O9Session*
     * in File->aux. */
    /* Sessions: a GROW-AND-REUSE POOL (the Plan 9 /net clone model, with
     * List-style growth). Slot dirs <i>/{ctl,data,status} are created once
     * and NEVER removed — clone hands out a closed slot, and explicit
     * `close` marks it reusable. Fid clunks update diagnostic refs only.
     * This dissolves both the leak (slots are bounded by peak open
     * conversations, then recycled) and the reap re-entrancy fault
     * (nothing is ever removefile'd). */
    print("typedef struct O9Session O9Session;\n");
    /* QLock per session guards data/status against concurrent request
     * handlers (once srvrelease lets requests interleave). */
    print("struct O9Session { int tag; int id; File *dir; QLock lock; long ref; int inuse; char data[4096]; char status[256]; };\n");
    print("static O9Session **o9app_sessions;\t/* the pool (grows) */\n");
    print("static int o9app_nsessions;\t/* slots created */\n");
    print("static int o9app_sessions_cap;\n");
    print("static QLock o9app_pool_lock;\t/* guards pool alloc/reuse */\n");
    print("static char o9app_lastdata[4096];\t/* root-ctl fire-and-forget reply */\n");
    /* NO global cur_session. The session is DYNAMIC REQUEST STATE — it
     * follows the Req*, derived from r->fid->file->aux. A global would be
     * clobbered by a concurrent request while the first is inside
     * ch->write (blocked on the actor's reply). */
    print("static O9Session *o9app_req_session(Req *r){\n");
    print("\tvoid *aux;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil) return nil;\n");
    print("\taux = r->fid->file->aux;\n");
    print("\tif(aux != nil && *(int*)aux == O9AUX_SESSION) return aux;\n");
    print("\treturn nil;\n");
    print("}\n");
    print("static void o9app_put_result(Req *r, char *s){\n");
    print("\tO9Session *sess = o9app_req_session(r);\n");
    print("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->data, sizeof sess->data, \"%%s\", s); qunlock(&sess->lock); }\n");
    print("\telse snprint(o9app_lastdata, sizeof o9app_lastdata, \"%%s\", s);\t/* root-ctl fire-and-forget */\n");
    print("}\n");
    print("static void o9app_put_status(Req *r, char *s){\n");
    print("\tO9Session *sess = o9app_req_session(r);\n");
    print("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->status, sizeof sess->status, \"%%s\", s); qunlock(&sess->lock); }\n");
    print("}\n");
    /* Create one new pool slot: <i>/{ctl,data,status} into the stable root
     * (single createfile-into-stable-parent — the safe pattern; done at
     * GROWTH only, never destroyed). */
    print("static O9Session *o9app_grow_session(void){\n");
    print("\tO9Session *s; char nm[32]; File *dir;\n");
    print("\tif(o9app_nsessions >= o9app_sessions_cap){\n");
    print("\t\tint ncap = o9app_sessions_cap ? o9app_sessions_cap*2 : 8;\n");
    print("\t\tO9Session **np = realloc(o9app_sessions, ncap*sizeof(O9Session*));\n");
    print("\t\tif(np == nil) return nil;\n");
    print("\t\to9app_sessions = np; o9app_sessions_cap = ncap;\n");
    print("\t}\n");
    print("\ts = mallocz(sizeof *s, 1);\n");
    print("\tif(s == nil) return nil;\n");
    print("\ts->tag = O9AUX_SESSION;\n");
    print("\ts->id = o9app_nsessions;\n");
    print("\tsnprint(nm, sizeof nm, \"%%d\", s->id);\n");
    print("\tdir = createfile(o9app_tree->root, nm, \"o9\", DMDIR|0555, s);\n");
    print("\tif(dir == nil){ free(s); return nil; }\n");
    print("\ts->dir = dir;\n");
    print("\tcreatefile(dir, \"ctl\", \"o9\", 0222, s);\n");
    print("\tcreatefile(dir, \"data\", \"o9\", 0444, s);\n");
    print("\tcreatefile(dir, \"status\", \"o9\", 0444, s);\n");
    print("\to9app_sessions[o9app_nsessions++] = s;\n");
    print("\treturn s;\n}\n");
    /* clone: a session is an EXPLICIT CONVERSATION owned by the client
     * until they `echo close > <id>/ctl` — NOT an open-fid lifetime. That
     * is the whole point of path-visible clone (shell use: echo>ctl then
     * cat data are separate opens; the session must persist between them).
     * Reuse a CLOSED slot (inuse==0), else grow. Clear its buffers on
     * (re)alloc. Pool-locked. */
    print("static O9Session *o9app_alloc_session(void){\n");
    print("\tint i; O9Session *s = nil;\n");
    print("\tqlock(&o9app_pool_lock);\n");
    print("\tfor(i = 0; i < o9app_nsessions; i++)\n");
    print("\t\tif(o9app_sessions[i]->inuse == 0){ s = o9app_sessions[i]; break; }\n");
    print("\tif(s == nil) s = o9app_grow_session();\n");
    print("\tif(s == nil){ qunlock(&o9app_pool_lock); return nil; }\n");
    print("\ts->inuse = 1; s->ref = 0;\n");
    print("\tqlock(&s->lock);\n");
    print("\ts->data[0] = '\\0';\n");
    print("\tsnprint(s->status, sizeof s->status, \"ready\\n\");\n");
    print("\tqunlock(&s->lock);\n");
    print("\tqunlock(&o9app_pool_lock);\n");
    print("\treturn s;\n}\n");
    /* close: the ONLY thing that ends a conversation — marks the slot
     * reusable. `echo close > <id>/ctl`. */
    print("static void o9app_close_session(O9Session *s){\n");
    print("\tif(s == nil) return;\n");
    print("\tqlock(&o9app_pool_lock);\n");
    print("\ts->inuse = 0;\n");
    print("\tqlock(&s->lock); snprint(s->status, sizeof s->status, \"closed\\n\"); s->data[0] = '\\0'; qunlock(&s->lock);\n");
    print("\tqunlock(&o9app_pool_lock);\n");
    print("}\n");
    print("static O9ImportStage *o9app_import_stage_new(O9Export *imp, int copy){\n");
    print("\tO9ImportStage *st;\n");
    print("\tst = mallocz(sizeof *st, 1);\n");
    print("\tif(st == nil) return nil;\n");
    print("\tst->tag = O9AUX_IMPORT_STAGE;\n");
    print("\tst->file = imp;\n");
    print("\tif(copy && imp != nil){\n");
    print("\t\tqlock(&imp->lock);\n");
    print("\t\tif(imp->ndata > 0){\n");
    print("\t\t\tst->data = malloc(imp->ndata + 1);\n");
    print("\t\t\tif(st->data == nil){ qunlock(&imp->lock); free(st); return nil; }\n");
    print("\t\t\tmemmove(st->data, imp->data, imp->ndata);\n");
    print("\t\t\tst->data[imp->ndata] = '\\0';\n");
    print("\t\t\tst->ndata = imp->ndata;\n");
    print("\t\t}\n");
    print("\t\tqunlock(&imp->lock);\n");
    print("\t}\n");
    print("\treturn st;\n");
    print("}\n");
    print("static void o9app_import_commit(Fid *f){\n");
    print("\tO9ImportStage *st; O9Export *imp; char *old;\n");
    print("\tif(f == nil || f->aux == nil || *(int*)f->aux != O9AUX_IMPORT_STAGE) return;\n");
    print("\tst = f->aux; f->aux = nil;\n");
    print("\tqlock(&st->lock);\n");
    print("\tif(st->commit && !st->failed && st->file != nil){\n");
    print("\t\timp = st->file;\n");
    print("\t\tqlock(&imp->lock);\n");
    print("\t\told = imp->data;\n");
    print("\t\timp->data = st->data;\n");
    print("\t\timp->ndata = st->ndata;\n");
    print("\t\tst->data = nil;\n");
    print("\t\tif(f->file != nil) f->file->length = imp->ndata;\n");
    print("\t\tqunlock(&imp->lock);\n");
    print("\t\tfree(old);\n");
    print("\t}\n");
    print("\tqunlock(&st->lock);\n");
    print("\tfree(st->data);\n");
    print("\tfree(st);\n");
    print("}\n");
    print("static void o9app_import_write(Req *r){\n");
    print("\tO9ImportStage *st; O9Export *imp; vlong off; long count; int need; char *np;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil || r->fid->file->aux == nil){ respond(r, \"not import\"); return; }\n");
    print("\tif(*(int*)r->fid->file->aux != O9AUX_IMPORT){ respond(r, \"not import\"); return; }\n");
    print("\tif(r->fid->aux == nil || *(int*)r->fid->aux != O9AUX_IMPORT_STAGE){\n");
    print("\t\timp = r->fid->file->aux;\n");
    print("\t\tr->fid->aux = o9app_import_stage_new(imp, 1);\n");
    print("\t\tif(r->fid->aux == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t}\n");
    print("\tst = r->fid->aux;\n");
    print("\toff = r->ifcall.offset; count = r->ifcall.count;\n");
    print("\tqlock(&st->lock);\n");
    print("\tif(off < 0 || count < 0 || off + count > 4*1024*1024){ st->failed = 1; qunlock(&st->lock); respond(r, \"import too large\"); return; }\n");
    print("\tneed = (int)(off + count);\n");
    print("\tif(need + 1 > st->ndata + 1){\n");
    print("\t\tnp = realloc(st->data, need + 1);\n");
    print("\t\tif(np == nil){ st->failed = 1; qunlock(&st->lock); respond(r, \"no memory\"); return; }\n");
    print("\t\tif(off > st->ndata) memset(np + st->ndata, 0, (int)(off - st->ndata));\n");
    print("\t\tst->data = np;\n");
    print("\t}\n");
    print("\tif(count > 0) memmove(st->data + (int)off, r->ifcall.data, count);\n");
    print("\tif(need > st->ndata) st->ndata = need;\n");
    print("\tif(st->data != nil) st->data[st->ndata] = '\\0';\n");
    print("\tst->wrote = 1; st->commit = 1;\n");
    print("\tqunlock(&st->lock);\n");
    print("\tr->ofcall.count = count;\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    /* destroyfid: DIAGNOSTICS ONLY (ref count). Clunking a fid does NOT
     * end the conversation — the client owns it until an explicit close.
     * This is what makes echo>ctl; cat data safe (ctl clunks first). */
    print("static void o9app_destroyfid(Fid *f){\n");
    print("\to9app_import_commit(f);\n");
    print("\tif(f != nil && f->file != nil && f->file->aux != nil &&\n");
    print("\t   *(int*)f->file->aux == O9AUX_SESSION && f->omode != -1){\n");
    print("\t\tO9Session *s = f->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_sub_and_fetch(&s->ref, 1);\n#else\n\t\tadec(&s->ref);\n#endif\n");
    print("\t}\n");
    print("}\n");
    /* open: ref++ (diagnostics; balanced by destroyfid). */
    print("static void o9app_open(Req *r){\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    print("\t   *(int*)r->fid->file->aux == O9AUX_IMPORT){\n");
    print("\t\tint __m = r->ifcall.mode & 3;\n");
    print("\t\tif(__m == OWRITE || __m == ORDWR || (r->ifcall.mode & OTRUNC)){\n");
    print("\t\t\tO9ImportStage *__st = o9app_import_stage_new(r->fid->file->aux, (r->ifcall.mode & OTRUNC) ? 0 : 1);\n");
    print("\t\t\tif(__st == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t\t\tif(r->ifcall.mode & OTRUNC) __st->commit = 1;\n");
    print("\t\t\tr->fid->aux = __st;\n");
    print("\t\t}\n");
    print("\t}\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    print("\t   *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    print("\t\tO9Session *s = r->fid->file->aux;\n");
    print("#ifdef __GNUC__\n\t\t__sync_fetch_and_add(&s->ref, 1);\n#else\n\t\tainc(&s->ref);\n#endif\n");
    print("\t}\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    print("static void o9app_create(Req *r){\n");
    print("\tFile *f; O9Export *imp; O9ImportStage *st;\n");
    print("\tif(r == nil || r->fid == nil || r->fid->file == nil){ respond(r, \"bad fid\"); return; }\n");
    print("\tif(r->fid->file != o9app_imports_dir){ respond(r, \"create prohibited\"); return; }\n");
    print("\tif((r->ifcall.perm & DMDIR) != 0){ respond(r, \"imports accept files only\"); return; }\n");
    print("\tif(!o9app_import_name_ok(r->ifcall.name)){ respond(r, \"bad import name\"); return; }\n");
    print("\timp = mallocz(sizeof *imp, 1);\n");
    print("\tif(imp == nil){ respond(r, \"no memory\"); return; }\n");
    print("\timp->tag = O9AUX_IMPORT;\n");
    print("\tf = createfile(o9app_imports_dir, r->ifcall.name, \"o9\", 0666, imp);\n");
    print("\tif(f == nil){ free(imp); respond(r, \"file exists\"); return; }\n");
    print("\tst = o9app_import_stage_new(imp, 0);\n");
    print("\tif(st == nil){ removefile(f); respond(r, \"no memory\"); return; }\n");
    print("\tst->commit = 1;\n");
    print("\tr->fid->file = f;\n");
    print("\tr->fid->qid = f->qid;\n");
    print("\tr->fid->aux = st;\n");
    print("\tr->ofcall.qid = f->qid;\n");
    print("\trespond(r, nil);\n");
    print("}\n");
    print("static void o9app_root_read(Req *r){\n");
    print("\tchar *name = r->fid->file->name;\n");
    print("\tchar buf[8192]; char *p = buf; int i;\n");
    /* clone: reading allocates a session and returns its id. */
    print("\tif(strcmp(name, \"clone\") == 0){\n");
    print("\t\tO9Session *__s = o9app_alloc_session();\n");
    print("\t\tchar __idb[16];\n");
    print("\t\tif(__s == nil){ respond(r, \"no session\"); return; }\n");
    print("\t\tsnprint(__idb, sizeof __idb, \"%%d\\n\", __s->id);\n");
    print("\t\treadstr(r, __idb); respond(r, nil); return;\n\t}\n");
    /* Session-local data/status: the file's aux is the O9Session; serve
     * that session's private result/status (the per-caller fix). Named
     * data/status distinguishes them from exports (arbitrary names). */
    print("\tif(r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    print("\t\tO9Session *__s = r->fid->file->aux;\n");
    print("\t\tchar __sb[4096];\n");
    print("\t\tqlock(&__s->lock); snprint(__sb, sizeof __sb, \"%%s\", strcmp(name, \"data\") == 0 ? __s->data : __s->status); qunlock(&__s->lock);\n");
    print("\t\treadstr(r, __sb); respond(r, nil); return;\n\t}\n");
    /* Export/import file: its aux holds committed serialized bytes.
     * Serve them ramfs-style (offset/count). */
    print("\tif(r->fid->file->aux != nil && (*(int*)r->fid->file->aux == O9AUX_EXPORT || *(int*)r->fid->file->aux == O9AUX_IMPORT)){\n");
    print("\t\tO9Export *__ex = r->fid->file->aux;\n");
    print("\t\tvlong __off = r->ifcall.offset; long __cnt = r->ifcall.count;\n");
    print("\t\tqlock(&__ex->lock);\n");
    print("\t\tif(__off >= __ex->ndata){ qunlock(&__ex->lock); r->ofcall.count = 0; respond(r, nil); return; }\n");
    print("\t\tif(__off + __cnt > __ex->ndata) __cnt = __ex->ndata - __off;\n");
    print("\t\tmemmove(r->ofcall.data, __ex->data + (int)__off, __cnt);\n");
    print("\t\tqunlock(&__ex->lock);\n");
    print("\t\tr->ofcall.count = __cnt; respond(r, nil); return;\n\t}\n");
    /* Root data: only the root-ctl (fire-and-forget/debug) reply. */
    print("\tif(strcmp(name, \"data\") == 0){ readstr(r, o9app_lastdata); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"ctl\") == 0){ readstr(r, \"\"); respond(r, nil); return; }\n");
    print("\tif(strcmp(name, \"status\") == 0){\n");
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"app %%s\\nstate running\\nclasses\", o9app_name);\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++) p += snprint(p, sizeof buf-(p-buf), \" %%s\", o9app_classes[i].name);\n");
    /* #8: list instances per class (docs say classes AND instances). */
    print("\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"instances %%s\", o9app_classes[i].name);\n");
    print("\t\t\tif(o9app_classes[i].listinst != nil) p += o9app_classes[i].listinst(p, (int)(sizeof buf-(p-buf)));\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    print("\tif(strcmp(name, \"methods\") == 0){\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tchar mb[4096]; o9_method_serialize(o9app_classes[i].name, mb, sizeof mb);\n");
    print("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"%%s\", mb);\n");
    print("\t\t}\n");
    print("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    /* state: DEBUG-only inspector.  Off by default (encapsulation);
     * O9DEBUG dumps read-only metadata snapshots plus live state tabs. */
    print("\tif(strcmp(name, \"state\") == 0){\n");
    print("\t\tif(!o9app_debug){ readstr(r, \"debug disabled (set O9DEBUG)\\n\"); respond(r, nil); return; }\n");
    print("\t\t{ char *__dbuf = mallocz(32768, 1); char *__dp;\n");
    print("\t\tif(__dbuf == nil){ respond(r, \"no memory\"); return; }\n");
    print("\t\t__dp = __dbuf;\n");
    print("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# methods\\n\");\n");
    print("\t\t__dp += o9_method_store_serialize(__dp, (int)(32768-(__dp-__dbuf)));\n");
    print("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"\\n\");\n");
    print("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    print("\t\t\tif(o9app_classes[i].dumpstate == nil) continue;\n");
    print("\t\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# %%s\\n\", o9app_classes[i].name);\n");
    print("\t\t\t__dp += o9app_classes[i].dumpstate(__dp, (int)(32768-(__dp-__dbuf)));\n");
    print("\t\t}\n");
    print("\t\treadstr(r, __dbuf); free(__dbuf); respond(r, nil); return; }\n\t}\n");
    print("\trespond(r, \"not found\");\n}\n");
    print("static void o9app_root_write(Req *r){\n");
    print("\tchar *name = r->fid->file->name;\n");
    print("\tchar cmd[1024], *f[16]; int nf; char inst[64]; O9ClassH *ch;\n");
    print("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_IMPORT){ o9app_import_write(r); return; }\n");
    print("\tif(strcmp(name, \"ctl\") != 0){ respond(r, \"read only\"); return; }\n");
    /* No global cur_session: the session is derived from r inside the
     * put_result/put_status helpers (o9app_req_session(r)), so concurrent
     * requests each route to their OWN session. */
    print("\tsnprint(cmd, sizeof cmd, \"%%.*s\", (int)r->ifcall.count, (char*)r->ifcall.data);\n");
    print("\tnf = tokenize(cmd, f, nelem(f));\n");
    /* `close`: end THIS conversation (a session ctl only) — mark the slot
     * reusable. The explicit release that ends a session's lifetime. */
    print("\tif(nf >= 1 && strcmp(f[0], \"close\") == 0){\n");
    print("\t\tO9Session *__cs = o9app_req_session(r);\n");
    print("\t\tif(__cs != nil) o9app_close_session(__cs);\n");
    print("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    print("\tif(nf < 3 || (strcmp(f[0], \"method\") != 0 && strcmp(f[0], \"new\") != 0)){ respond(r, \"want: method Class.inst name | new Class inst | close\"); return; }\n");
    /* Resolve to a class handler. new Class inst -> resolve by CLASS name
     * (f[1] is the class). method Class.inst -> resolve by Class.inst.
     * The class fswrite re-tokenizes r->ifcall.data itself and handles
     * both new and method, so we only need to pick the right handler. */
    print("\tif(strcmp(f[0], \"new\") == 0){\n");
    print("\t\tint __ci; ch = nil;\n");
    print("\t\tfor(__ci = 0; __ci < o9app_nclasses; __ci++)\n");
    print("\t\t\tif(strcmp(o9app_classes[__ci].name, f[1]) == 0){ ch = &o9app_classes[__ci]; break; }\n");
    print("\t\tif(ch == nil){ respond(r, \"unknown class\"); return; }\n");
    print("\t} else {\n");
    print("\t\tch = o9app_resolve(f[1], inst, sizeof inst);\n");
    print("\t\tif(ch == nil){ respond(r, \"unknown object\"); return; }\n");
    print("\t}\n");
    print("\tch->write(r, nil);\t/* class fswrite re-parses r->ifcall.data */\n");
    print("}\n\n");

    /* o9_export_tab: publish a tabula into the served-tree exports/ dir at
     * runtime.  A single createfile into the stable exports parent (the
     * safe pattern); the serialized bytes go in the child File's aux.  If
     * a file of that name exists, its bytes are replaced (re-export). */
    print("void o9_export_tab(O9String *name, O9Tabula *t){\n");
    print("\tFile *f; O9Export *ex; O9String *bytes; char *cname, *cbytes, *old;\n");
    print("\tif(o9app_exports_dir == nil || name == nil || t == nil) return;\n");
    print("\tcname = o9_string_cstr(name);\n");
    print("\tif(cname == nil) return;\n");
    print("\tif(!o9app_export_name_ok(cname)){ free(cname); return; }\n");
    print("\tbytes = o9_tab_serialize(t);\n");
    print("\tcbytes = o9_string_cstr(bytes);\n");
    print("\tif(cbytes == nil){ free(cname); o9_string_release(bytes); return; }\n");
    print("\tf = createfile(o9app_exports_dir, cname, \"o9\", 0444, nil);\n");
    print("\tif(f == nil){\t/* exists: replace its bytes */\n");
    print("\t\tf = walkfile(o9app_exports_dir, cname);\n");
    print("\t\tif(f == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    print("\t}\n");
    print("\tex = f->aux;\n");
    print("\tif(ex != nil && ex->tag != O9AUX_EXPORT){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    print("\tif(ex == nil){ ex = mallocz(sizeof *ex, 1); if(ex == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; } ex->tag = O9AUX_EXPORT; f->aux = ex; }\n");
    print("\tqlock(&ex->lock);\n");
    print("\told = ex->data;\n");
    print("\tex->data = cbytes; ex->ndata = bytes != nil ? o9_string_len(bytes) : 0;\n");
    print("\tf->length = ex->ndata;\n");
    print("\tqunlock(&ex->lock);\n");
    print("\tfree(old);\n");
    print("\tfree(cname); o9_string_release(bytes);\n");
    print("}\n\n");

    print("static void o9_app_listen(O9String *addr){\n");
    print("\tchar *caddr;\n");
    print("\tif(addr == nil) return;\n");
    print("\tcaddr = o9_string_cstr(addr);\n");
    print("\tif(caddr == nil || caddr[0] == '\\0'){ free(caddr); return; }\n");
    print("\tthreadlistensrv(&o9app_srv, caddr);\t/* caddr intentionally lives for process lifetime */\n");
    print("}\n\n");

    /* 1. Emit headers for ALL known classes/interfaces (local and imported) */
    for(cd = classes; cd; cd = cd->next){
        if(cd->node->type != NStruct && cd->node->type != NEnum)
            gen_class_header(cd->node);
    }
    Node *main_func = find_main_func(root);
    Node *last = nil;

    gen_enums(root);
    gen_structs(root);
    emit_tuple_types_node(root);
    for(n = mono_list; n; n = n->next)
        if(n->type == NStruct)
            gen_struct_def(n);
    for(n = mono_list; n; n = n->next)
        if(n->type == NClass && (n->flags & NFAbstract) == 0)
            gen_class_server(n);
    last = gen_classes(root);

    /* Per-app facade: one Srv/tree for the whole program.  o9_app_start
     * sets the app names, allocates the shared tree, and posts the single
     * /srv/o9.<app>; each class then registers INTO it. */
    print("static void o9_app_start(int argc, char **argv){\n");
    print("\tchar *__o9app = \"%s\";\n", last != nil ? last->name : "app");
    print("\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    print("\tsnprint(o9app_name, sizeof o9app_name, \"%%s\", __o9app);\n");
    print("\t{ char *__d = getenv(\"O9DEBUG\"); o9app_debug = (__d != nil && __d[0] != '\\0'); free(__d); }\n");
    print("\to9_ns_app_root(o9app_root, sizeof o9app_root, __o9app);\n");
    print("\to9_ns_service_name(o9app_srvname, sizeof o9app_srvname, __o9app, __o9app, \"app\");\n");
    print("\to9_ns_class_path(o9app_mount, sizeof o9app_mount, o9app_root, __o9app);\n");
    print("\to9_ns_ensure_app(o9app_root);\n");
    print("\to9app_tree = alloctree(nil, nil, DMDIR|0555, nil);\n");
    print("\to9app_srv.tree = o9app_tree;\n");
    print("\to9app_srv.read = o9app_root_read;\n\to9app_srv.write = o9app_root_write;\n");
    print("\to9app_srv.create = o9app_create;\n");
    print("\to9app_srv.open = o9app_open;\n\to9app_srv.destroyfid = o9app_destroyfid;\t/* session fid diagnostics */\n");
    /* The four control files + state are a FIXED shape, built once, never
     * mutated (their content is live, their structure is frozen). */
    print("\tcreatefile(o9app_tree->root, \"ctl\", \"o9\", 0666, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"data\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"status\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"methods\", \"o9\", 0444, nil);\n");
    print("\tcreatefile(o9app_tree->root, \"state\", \"o9\", 0444, nil);\t/* debug inspector */\n");
    /* clone: reading it allocates a session <id>/ with session-local
     * ctl/data/status (docs/SESSIONS.md) — the /net/tcp/clone pattern that
     * gives concurrent callers a private, path-addressable conversation. */
    print("\tcreatefile(o9app_tree->root, \"clone\", \"o9\", 0444, nil);\n");
    /* exports/ is a served-tree DIRECTORY inside the application file tree
     * (NOT on disk).  It is the one MUTABLE part: objects publish tabulae
     * into it at runtime via a single createfile into this stable parent
     * dir (the authsrv/ramfs-proven safe pattern — no nested subtree, no
     * walkfile).  Reachable through the mount; ls reflects live objects. */
    print("\to9app_exports_dir = createfile(o9app_tree->root, \"exports\", \"o9\", DMDIR|0555, nil);\n");
    print("\to9app_imports_dir = createfile(o9app_tree->root, \"imports\", \"o9\", DMDIR|0777, nil);\n");
    print("}\n");
    print("static void o9_app_post(void){\n");
    print("\t{ char __sp[160]; snprint(__sp, sizeof __sp, \"/srv/%%s\", o9app_srvname); remove(__sp); }\n");
    print("\t{ char __ln[300]; snprint(__ln, sizeof __ln, \"mount /srv/%%s %%s\", o9app_srvname, o9app_mount); o9_ns_recipe(o9app_root, o9app_name, __ln); }\n");
    print("\tif(o9_ns_ensure_dir(o9app_mount) == 0)\n");
    /* MREPL|MCREATE: the exports/ dir is mutable — objects createfile
     * into it at runtime — so the facade mount must permit creation
     * (this is exactly what ramfs uses: MREPL|MCREATE). */
    print("\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, o9app_mount, MREPL|MCREATE);\n");
    print("\telse\n\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, nil, MREPL|MCREATE);\n");
    print("}\n\n");

    print("int mainstacksize = 65536;\n\n");
    print("void\nthreadmain(int argc, char **argv)\n{\n");
    print("\tvlong __o9fr[%d][12];\n", O9_MSG_FRAMES);
    print("\tUSED(argc); USED(argv); USED(__o9fr);\n");
    print("\to9_process_set_args(argc, argv);\n");
    /* Per-app namespace isolation MUST happen here — the very first thing
     * in threadmain, BEFORE o9_registry_start or any proccreate. Forking
     * the namespace group after procs exist disturbs the thread library's
     * proc/rendezvous group. RFNAMEG copies the namespace (isolation);
     * then re-bind the global #s (srv) device onto /srv so the app's post
     * stays reachable to other processes (facade) — the iostats.c /
     * lib/namespace pattern. Isolation for the app's own tree + shared
     * /srv for the post. Verified: mk export-test = export: OK. */
    print("\trfork(RFNAMEG);\n");
    print("\tbind(\"#s\", \"/srv\", MREPL|MCREATE);\n");
    print("\to9_registry_start();\n");
    gen_object_metadata(root);
    /* One app server; every class that got a class-server (generic
     * and non-generic alike) registers into it, then post once. */
    {
        int __ri;
        print("\to9_app_start(argc, argv);\n");
        for(__ri = 0; __ri < o9_nregistered; __ri++)
            print("\to9_register_class_%s();\n", o9_registered[__ri]);
        print("\to9_app_post();\n");
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
