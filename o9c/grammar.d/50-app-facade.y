/* ========================================================================
 * APP FACADE GENERATION AND PROGRAM EMISSION
 * ======================================================================== */

void
codegen(Node *root)
{
    Node *n;
    ClassDef *cd;

    mono_scan_node(root);

    cprint("/* Generated o9 Source */\n");
    cprint("#include <u.h>\n#include <libc.h>\n#include <thread.h>\n#include <fcall.h>\n#include <9p.h>\n#include <auth.h>\n#include <o9.h>\n\n");
    cprint("#ifndef O9_HAVE_SRVRELEASE\n");
    cprint("/* 9legacy lib9p lacks 9front's srvrelease/srvacquire. o9build defines */\n");
    cprint("/* O9_HAVE_SRVRELEASE (via a <9p.h> probe) on 9front so the real API is */\n");
    cprint("/* used and requests can interleave; 9legacy falls back to these no-ops. */\n");
    cprint("static void\no9_compat_srvrelease(Srv *s)\n{\n\tUSED(s);\n}\n");
    cprint("static void\no9_compat_srvacquire(Srv *s)\n{\n\tUSED(s);\n}\n");
    cprint("#define srvrelease o9_compat_srvrelease\n");
    cprint("#define srvacquire o9_compat_srvacquire\n");
    cprint("#endif\n\n");
    emit_cdeps();
    cprint("#ifndef _O9_COMMON_\n#define _O9_COMMON_\n");
    cprint("#define o9_offsetof(s, m) (long)(&(((s*)0)->m))\n");
    cprint("typedef struct ArcEntry ArcEntry;\nstruct ArcEntry {\n\tulong id;\n\tlong count;\n};\n\n");
    cprint("typedef struct ArcLedger ArcLedger;\nstruct ArcLedger {\n\tArcEntry entries[64];\n};\n");
    /* Per-app facade: ONE Srv with a fixed root shape, built once at
     * startup.  Root control files are stable; clone creates session dirs
     * and exports/ accepts published tabulae. The served facade does not
     * compose the app from per-object fileservers. ctl names its target
     * instance in the line (method Class.inst method arg...);
     * status/methods list the object graph and public surface by reading.
     *
     * Class handlers register themselves in a small table so the flat
     * ctl/read handler can route to any class's fsread/fswrite body. */
    cprint("typedef struct O9ClassH O9ClassH;\n");
    cprint("struct O9ClassH {\n");
    cprint("\tchar *name;\n");
    cprint("\tvoid (*read)(Req*, void*);\n");
    cprint("\tvoid (*write)(Req*, void*);\n");
    cprint("\tvoid *(*find)(char*);\t/* <C>_find_instance */\n");
    cprint("\tint (*dumpstate)(char*, int);\t/* <C>_dumpstate: debug */\n");
    cprint("\tint (*listinst)(char*, int);\t/* <C>_listinstances: append \" name\" per live instance */\n");
    cprint("\tint (*listactors)(char*, int);\t/* <C>_listactors: list actors for /actors */\n");
    cprint("};\n");
    cprint("extern O9ClassH o9app_classes[64];\n");
    cprint("extern int o9app_nclasses;\n");
    cprint("extern Srv o9app_srv;\n");
    cprint("extern Tree *o9app_tree;\n");
    cprint("extern char o9app_root[128];\n");
    cprint("extern char o9app_srvname[128];\n");
    cprint("extern char o9app_mount[256];\n");
    cprint("extern char o9app_name[64];\n");
    cprint("extern File *o9app_exports_dir;\t/* served-tree exports/ dir */\n");
    cprint("extern File *o9app_imports_dir;\t/* served-tree imports/ dir */\n");
    cprint("static void\no9app_register_handler(char *name, void (*rd)(Req*,void*), void (*wr)(Req*,void*), void *(*find)(char*), int (*dump)(char*,int), int (*listinst)(char*,int), int (*listactors)(char*,int))\n{\n");
    cprint("\tif(o9app_nclasses >= nelem(o9app_classes)) return;\n");
    cprint("\to9app_classes[o9app_nclasses].name = name;\n");
    cprint("\to9app_classes[o9app_nclasses].read = rd;\n");
    cprint("\to9app_classes[o9app_nclasses].write = wr;\n");
    cprint("\to9app_classes[o9app_nclasses].find = find;\n");
    cprint("\to9app_classes[o9app_nclasses].dumpstate = dump;\n");
    cprint("\to9app_classes[o9app_nclasses].listinst = listinst;\n");
    cprint("\to9app_classes[o9app_nclasses].listactors = listactors;\n");
    cprint("\to9app_nclasses++;\n}\n");
    /* Debug gate: O9DEBUG env var exposes live object state via the
     * `state` file.  Off by default — encapsulation preserved. */
    cprint("extern int o9app_debug;\n");
    /* Split a "Class.inst" token; returns the class handler and writes
     * the bare instance name into instout.  nil if not found. */
    cprint("static O9ClassH*\no9app_resolve(char *tok, char *instout, int n)\n{\n");
    cprint("\tchar *dot; int i;\n");
    cprint("\tif(tok == nil) return nil;\n");
    cprint("\tdot = strchr(tok, '.');\n");
    cprint("\tif(dot != nil){\n");
    cprint("\t\tint clen;\n\t\tclen = dot - tok;\n");
    cprint("\t\tsnprint(instout, n, \"%%s\", dot+1);\n");
    cprint("\t\tfor(i = 0; i < o9app_nclasses; i++)\n");
    cprint("\t\t\tif(strncmp(o9app_classes[i].name, tok, clen) == 0 && o9app_classes[i].name[clen] == '\\0')\n");
    cprint("\t\t\t\treturn &o9app_classes[i];\n");
    cprint("\t\treturn nil;\n");
    cprint("\t}\n");
    /* No class prefix: search every class for an instance of that name */
    cprint("\tsnprint(instout, n, \"%%s\", tok);\n");
    cprint("\tfor(i = 0; i < o9app_nclasses; i++)\n");
    cprint("\t\tif(o9app_classes[i].find != nil && o9app_classes[i].find(tok) != nil)\n");
    cprint("\t\t\treturn &o9app_classes[i];\n");
    cprint("\treturn nil;\n}\n");
    cprint("#endif\n\n");
    /* Shared app-server globals (once per program). */
    cprint("O9ClassH o9app_classes[64];\n");
    cprint("int o9app_nclasses;\n");
    cprint("Srv o9app_srv;\n");
    cprint("Tree *o9app_tree;\n");
    cprint("char o9app_root[128];\n");
    cprint("char o9app_srvname[128];\n");
    cprint("char o9app_mount[256];\n");
    cprint("char o9app_name[64];\n");
    cprint("File *o9app_exports_dir;\t/* served-tree exports/ dir (mutable) */\n");
    cprint("File *o9app_imports_dir;\t/* served-tree imports/ dir (mutable) */\n");
    cprint("int o9app_debug;\t/* set from O9DEBUG at startup */\n\n");
    cprint("int o9app_auth_required;\t/* set from O9AUTH=required at startup */\n\n");
    /* One published tabula: its serialized bytes live in the File's aux,
     * served ramfs-style on read.  This is the mutable part of the fs. */
    cprint("typedef struct O9Export O9Export;\n");
    cprint("typedef struct O9ImportStage O9ImportStage;\n");
    /* aux tag: both O9Export and O9Session live in File->aux; the first
     * field discriminates them (destroyfid only has the Fid). */
    cprint("enum { O9AUX_EXPORT = 1, O9AUX_SESSION = 2, O9AUX_IMPORT = 3, O9AUX_IMPORT_STAGE = 4 };\n");
    cprint("struct O9Export {\n\tint tag;\n\tQLock lock;\n\tchar *data;\n\tint ndata;\n};\n\n");
    cprint("struct O9ImportStage {\n\tint tag;\n\tO9Export *file;\n\tQLock lock;\n\tchar *data;\n\tint ndata;\n\tint wrote;\n\tint commit;\n\tint failed;\n};\n\n");
    cprint("static int\no9app_export_name_ok(char *s)\n{\n");
    cprint("\tuchar *p;\n");
    cprint("\tif(s == nil || s[0] == '\\0' || strcmp(s, \".\") == 0 || strcmp(s, \"..\") == 0) return 0;\n");
    cprint("\tfor(p = (uchar*)s; *p != '\\0'; p++)\n");
    cprint("\t\tif(*p < ' ' || *p == 0177 || *p == '/') return 0;\n");
    cprint("\treturn 1;\n");
    cprint("}\n\n");
    cprint("static int\no9app_import_name_ok(char *s)\n{\n");
    cprint("\tint n;\n");
    cprint("\tif(!o9app_export_name_ok(s)) return 0;\n");
    cprint("\tn = strlen(s);\n");
    cprint("\treturn n > 4 && strcmp(s+n-4, \".tab\") == 0;\n");
    cprint("}\n\n");

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
    cprint("typedef struct O9Session O9Session;\n");
    /* QLock per session guards data/status against concurrent request
     * handlers (once srvrelease lets requests interleave). */
    cprint("struct O9Session {\n\tint tag;\n\tint id;\n\tFile *dir;\n\tQLock lock;\n\tlong ref;\n\tint inuse;\n\tint blessed;\n\tchar authuser[64];\n\tchar data[4096];\n\tchar status[256];\n};\n");
    cprint("static O9Session **o9app_sessions;\t/* the pool (grows) */\n");
    cprint("static int o9app_nsessions;\t/* slots created */\n");
    cprint("static int o9app_sessions_cap;\n");
    cprint("static QLock o9app_pool_lock;\t/* guards pool alloc/reuse */\n");
    cprint("static char o9app_lastdata[4096];\t/* root-ctl fire-and-forget reply */\n");
    /* NO global cur_session. The session is DYNAMIC REQUEST STATE — it
     * follows the Req*, derived from r->fid->file->aux. A global would be
     * clobbered by a concurrent request while the first is inside
     * ch->write (blocked on the actor's reply). */
    cprint("static O9Session*\no9app_req_session(Req *r)\n{\n");
    cprint("\tvoid *aux;\n");
    cprint("\tif(r == nil || r->fid == nil || r->fid->file == nil) return nil;\n");
    cprint("\taux = r->fid->file->aux;\n");
    cprint("\tif(aux != nil && *(int*)aux == O9AUX_SESSION) return aux;\n");
    cprint("\treturn nil;\n");
    cprint("}\n");
    cprint("static void\no9app_put_result(Req *r, char *s)\n{\n");
    cprint("\tO9Session *sess;\n\tsess = o9app_req_session(r);\n");
    cprint("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->data, sizeof sess->data, \"%%s\", s); qunlock(&sess->lock); }\n");
    cprint("\telse snprint(o9app_lastdata, sizeof o9app_lastdata, \"%%s\", s);\t/* root-ctl fire-and-forget */\n");
    cprint("}\n");
    cprint("static void\no9app_put_status(Req *r, char *s)\n{\n");
    cprint("\tO9Session *sess;\n\tsess = o9app_req_session(r);\n");
    cprint("\tif(sess != nil){ qlock(&sess->lock); snprint(sess->status, sizeof sess->status, \"%%s\", s); qunlock(&sess->lock); }\n");
    cprint("}\n");
    cprint("static void\no9app_req_user(Req *r, char *buf, int nbuf)\n{\n");
    cprint("\tO9Session *sess; char *u;\n");
    cprint("\tif(buf == nil || nbuf <= 0) return;\n");
    cprint("\tbuf[0] = '\\0';\n");
    cprint("\tsess = o9app_req_session(r);\n");
    cprint("\tif(sess != nil){\n");
    cprint("\t\tqlock(&sess->lock);\n");
    cprint("\t\tif(sess->blessed && sess->authuser[0] != '\\0') snprint(buf, nbuf, \"%%s\", sess->authuser);\n");
    cprint("\t\tqunlock(&sess->lock);\n");
    cprint("\t\tif(buf[0] != '\\0') return;\n");
    cprint("\t}\n");
    cprint("\tif(r != nil && r->fid != nil && r->fid->uid != nil){ snprint(buf, nbuf, \"%%s\", r->fid->uid); return; }\n");
    cprint("\tu = getuser();\n");
    cprint("\tsnprint(buf, nbuf, \"%%s\", u != nil ? u : \"\");\n");
    cprint("}\n");
    cprint("static int\no9app_req_blessed(Req *r)\n{\n");
    cprint("\tO9Session *sess; int ok;\n");
    cprint("\tsess = o9app_req_session(r);\n");
    cprint("\tif(sess != nil){ qlock(&sess->lock); ok = sess->blessed; qunlock(&sess->lock); if(ok) return 1; }\n");
    cprint("\tif(o9app_auth_required && r != nil && r->fid != nil && r->fid->uid != nil) return strcmp(r->fid->uid, \"none\") != 0;\n");
    cprint("\treturn 0;\n");
    cprint("}\n");
    cprint("static void\no9app_wipe(void *p, int n)\n{\n");
    cprint("\tvolatile uchar *q;\n");
    cprint("\tif(p == nil) return;\n");
    cprint("\tq = p;\n");
    cprint("\twhile(n-- > 0) *q++ = 0;\n");
    cprint("}\n");
    cprint("static int\no9app_login_name_ok(char *s)\n{\n");
    cprint("\tuchar *p; int n;\n");
    cprint("\tif(s == nil || s[0] == '\\0') return 0;\n");
    cprint("\tn = 0;\n");
    cprint("\tfor(p = (uchar*)s; *p != '\\0'; p++){\n");
    cprint("\t\tif(*p <= ' ' || *p == 0177 || *p == '/') return 0;\n");
    cprint("\t\tif(++n >= 64) return 0;\n");
    cprint("\t}\n");
    cprint("\treturn 1;\n");
    cprint("}\n");
    cprint("static int\no9app_auth_login(char *user, char *pass, char *err, int nerr)\n{\n");
    cprint("\tAuthInfo *ai; int ok;\n");
    cprint("\tif(err != nil && nerr > 0) err[0] = '\\0';\n");
    cprint("\tif(!o9app_login_name_ok(user)){ if(err != nil) snprint(err, nerr, \"bad user\"); return 0; }\n");
    cprint("\tif(pass == nil || pass[0] == '\\0'){ if(err != nil) snprint(err, nerr, \"empty password\"); return 0; }\n");
    cprint("\tai = auth_userpasswd(user, pass);\n");
    cprint("\tif(ai == nil){ if(err != nil) snprint(err, nerr, \"%%r\"); return 0; }\n");
    cprint("\tok = ai->cuid != nil && strcmp(ai->cuid, user) == 0;\n");
    cprint("\tif(!ok && err != nil) snprint(err, nerr, \"authenticated as %%s\", ai->cuid != nil ? ai->cuid : \"none\");\n");
    cprint("\tauth_freeAI(ai);\n");
    cprint("\treturn ok;\n");
    cprint("}\n");
    /* Create one new pool slot: <i>/{ctl,data,status} into the stable root
     * (single createfile-into-stable-parent — the safe pattern; done at
     * GROWTH only, never destroyed). */
    cprint("static O9Session*\no9app_grow_session(void)\n{\n");
    cprint("\tO9Session *s; char nm[32]; File *dir;\n");
    cprint("\tif(o9app_nsessions >= o9app_sessions_cap){\n");
    cprint("\t\tint ncap;\n\t\tncap = o9app_sessions_cap ? o9app_sessions_cap*2 : 8;\n");
    cprint("\t\tO9Session **np;\n\t\tnp = realloc(o9app_sessions, ncap*sizeof(O9Session*));\n");
    cprint("\t\tif(np == nil) return nil;\n");
    cprint("\t\to9app_sessions = np; o9app_sessions_cap = ncap;\n");
    cprint("\t}\n");
    cprint("\ts = mallocz(sizeof *s, 1);\n");
    cprint("\tif(s == nil) return nil;\n");
    cprint("\ts->tag = O9AUX_SESSION;\n");
    cprint("\ts->id = o9app_nsessions;\n");
    cprint("\tsnprint(nm, sizeof nm, \"%%d\", s->id);\n");
    cprint("\tdir = createfile(o9app_tree->root, nm, \"o9\", DMDIR|0555, s);\n");
    cprint("\tif(dir == nil){ free(s); return nil; }\n");
    cprint("\ts->dir = dir;\n");
    cprint("\tcreatefile(dir, \"ctl\", \"o9\", 0222, s);\n");
    cprint("\tcreatefile(dir, \"data\", \"o9\", 0444, s);\n");
    cprint("\tcreatefile(dir, \"status\", \"o9\", 0444, s);\n");
    cprint("\to9app_sessions[o9app_nsessions++] = s;\n");
    cprint("\treturn s;\n}\n");
    /* clone: a session is an EXPLICIT CONVERSATION owned by the client
     * until they `echo close > <id>/ctl` — NOT an open-fid lifetime. That
     * is the whole point of path-visible clone (shell use: echo>ctl then
     * cat data are separate opens; the session must persist between them).
     * Reuse a CLOSED slot (inuse==0), else grow. Clear its buffers on
     * (re)alloc. Pool-locked. */
    cprint("static O9Session*\no9app_alloc_session(void)\n{\n");
    cprint("\tint i; O9Session *s;\n\ts = nil;\n");
    cprint("\tqlock(&o9app_pool_lock);\n");
    cprint("\tfor(i = 0; i < o9app_nsessions; i++)\n");
    cprint("\t\tif(o9app_sessions[i]->inuse == 0){ s = o9app_sessions[i]; break; }\n");
    cprint("\tif(s == nil) s = o9app_grow_session();\n");
    cprint("\tif(s == nil){ qunlock(&o9app_pool_lock); return nil; }\n");
    cprint("\ts->inuse = 1; s->ref = 0;\n");
    cprint("\tqlock(&s->lock);\n");
    cprint("\ts->blessed = 0;\n");
    cprint("\ts->authuser[0] = '\\0';\n");
    cprint("\ts->data[0] = '\\0';\n");
    cprint("\tsnprint(s->status, sizeof s->status, \"ready\\n\");\n");
    cprint("\tqunlock(&s->lock);\n");
    cprint("\tqunlock(&o9app_pool_lock);\n");
    cprint("\treturn s;\n}\n");
    /* close: the ONLY thing that ends a conversation — marks the slot
     * reusable. `echo close > <id>/ctl`. */
    cprint("static void\no9app_close_session(O9Session *s)\n{\n");
    cprint("\tif(s == nil) return;\n");
    cprint("\tqlock(&o9app_pool_lock);\n");
    cprint("\ts->inuse = 0;\n");
    cprint("\tqlock(&s->lock); s->blessed = 0; s->authuser[0] = '\\0'; snprint(s->status, sizeof s->status, \"closed\\n\"); s->data[0] = '\\0'; qunlock(&s->lock);\n");
    cprint("\tqunlock(&o9app_pool_lock);\n");
    cprint("}\n");
    cprint("static O9ImportStage*\no9app_import_stage_new(O9Export *imp, int copy)\n{\n");
    cprint("\tO9ImportStage *st;\n");
    cprint("\tst = mallocz(sizeof *st, 1);\n");
    cprint("\tif(st == nil) return nil;\n");
    cprint("\tst->tag = O9AUX_IMPORT_STAGE;\n");
    cprint("\tst->file = imp;\n");
    cprint("\tif(copy && imp != nil){\n");
    cprint("\t\tqlock(&imp->lock);\n");
    cprint("\t\tif(imp->ndata > 0){\n");
    cprint("\t\t\tst->data = malloc(imp->ndata + 1);\n");
    cprint("\t\t\tif(st->data == nil){ qunlock(&imp->lock); free(st); return nil; }\n");
    cprint("\t\t\tmemmove(st->data, imp->data, imp->ndata);\n");
    cprint("\t\t\tst->data[imp->ndata] = '\\0';\n");
    cprint("\t\t\tst->ndata = imp->ndata;\n");
    cprint("\t\t}\n");
    cprint("\t\tqunlock(&imp->lock);\n");
    cprint("\t}\n");
    cprint("\treturn st;\n");
    cprint("}\n");
    cprint("static void\no9app_import_commit(Fid *f)\n{\n");
    cprint("\tO9ImportStage *st; O9Export *imp; char *old;\n");
    cprint("\tif(f == nil || f->aux == nil || *(int*)f->aux != O9AUX_IMPORT_STAGE) return;\n");
    cprint("\tst = f->aux; f->aux = nil;\n");
    cprint("\tqlock(&st->lock);\n");
    cprint("\tif(st->commit && !st->failed && st->file != nil){\n");
    cprint("\t\timp = st->file;\n");
    cprint("\t\tqlock(&imp->lock);\n");
    cprint("\t\told = imp->data;\n");
    cprint("\t\timp->data = st->data;\n");
    cprint("\t\timp->ndata = st->ndata;\n");
    cprint("\t\tst->data = nil;\n");
    cprint("\t\tif(f->file != nil) f->file->length = imp->ndata;\n");
    cprint("\t\tqunlock(&imp->lock);\n");
    cprint("\t\tfree(old);\n");
    cprint("\t}\n");
    cprint("\tqunlock(&st->lock);\n");
    cprint("\tfree(st->data);\n");
    cprint("\tfree(st);\n");
    cprint("}\n");
    cprint("static void\no9app_import_write(Req *r)\n{\n");
    cprint("\tO9ImportStage *st; O9Export *imp; vlong off; long count; int need; char *np;\n");
    cprint("\tif(r == nil || r->fid == nil || r->fid->file == nil || r->fid->file->aux == nil){ respond(r, \"not import\"); return; }\n");
    cprint("\tif(*(int*)r->fid->file->aux != O9AUX_IMPORT){ respond(r, \"not import\"); return; }\n");
    cprint("\tif(r->fid->aux == nil || *(int*)r->fid->aux != O9AUX_IMPORT_STAGE){\n");
    cprint("\t\timp = r->fid->file->aux;\n");
    cprint("\t\tr->fid->aux = o9app_import_stage_new(imp, 1);\n");
    cprint("\t\tif(r->fid->aux == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\t}\n");
    cprint("\tst = r->fid->aux;\n");
    cprint("\toff = r->ifcall.offset; count = r->ifcall.count;\n");
    cprint("\tqlock(&st->lock);\n");
    cprint("\tif(off < 0 || count < 0 || off + count > 4*1024*1024){ st->failed = 1; qunlock(&st->lock); respond(r, \"import too large\"); return; }\n");
    cprint("\tneed = (int)(off + count);\n");
    cprint("\tif(need + 1 > st->ndata + 1){\n");
    cprint("\t\tnp = realloc(st->data, need + 1);\n");
    cprint("\t\tif(np == nil){ st->failed = 1; qunlock(&st->lock); respond(r, \"no memory\"); return; }\n");
    cprint("\t\tif(off > st->ndata) memset(np + st->ndata, 0, (int)(off - st->ndata));\n");
    cprint("\t\tst->data = np;\n");
    cprint("\t}\n");
    cprint("\tif(count > 0) memmove(st->data + (int)off, r->ifcall.data, count);\n");
    cprint("\tif(need > st->ndata) st->ndata = need;\n");
    cprint("\tif(st->data != nil) st->data[st->ndata] = '\\0';\n");
    cprint("\tst->wrote = 1; st->commit = 1;\n");
    cprint("\tqunlock(&st->lock);\n");
    cprint("\tr->ofcall.count = count;\n");
    cprint("\trespond(r, nil);\n");
    cprint("}\n");
    /* destroyfid: DIAGNOSTICS ONLY (ref count). Clunking a fid does NOT
     * end the conversation — the client owns it until an explicit close.
     * This is what makes echo>ctl; cat data safe (ctl clunks first). */
    cprint("static void\no9app_destroyfid(Fid *f)\n{\n");
    cprint("\tauthdestroy(f);\n");
    cprint("\to9app_import_commit(f);\n");
    cprint("\tif(f != nil && f->file != nil && f->file->aux != nil &&\n");
    cprint("\t   *(int*)f->file->aux == O9AUX_SESSION && f->omode != -1){\n");
    cprint("\t\tO9Session *s;\n\t\ts = f->file->aux;\n");
    cprint("\t\tadec(&s->ref);\n");
    cprint("\t}\n");
    cprint("}\n");
    /* open: ref++ (diagnostics; balanced by destroyfid). */
    cprint("static void\no9app_open(Req *r)\n{\n");
    cprint("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    cprint("\t   *(int*)r->fid->file->aux == O9AUX_IMPORT){\n");
    cprint("\t\tint __m;\n\t\t__m = r->ifcall.mode & 3;\n");
    cprint("\t\tif(__m == OWRITE || __m == ORDWR || (r->ifcall.mode & OTRUNC)){\n");
    cprint("\t\t\tO9ImportStage *__st;\n\t\t\t__st = o9app_import_stage_new(r->fid->file->aux, (r->ifcall.mode & OTRUNC) ? 0 : 1);\n");
    cprint("\t\t\tif(__st == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\t\t\tif(r->ifcall.mode & OTRUNC) __st->commit = 1;\n");
    cprint("\t\t\tr->fid->aux = __st;\n");
    cprint("\t\t}\n");
    cprint("\t}\n");
    cprint("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil &&\n");
    cprint("\t   *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    cprint("\t\tO9Session *s;\n\t\ts = r->fid->file->aux;\n");
    cprint("\t\tainc(&s->ref);\n");
    cprint("\t}\n");
    cprint("\trespond(r, nil);\n");
    cprint("}\n");
    cprint("static void\no9app_auth(Req *r)\n{\n");
    cprint("\tif(!o9app_auth_required){ respond(r, \"authentication not required\"); return; }\n");
    cprint("\tauth9p(r);\n");
    cprint("}\n");
    cprint("static void\no9app_attach(Req *r)\n{\n");
    cprint("\tif(o9app_auth_required && authattach(r) < 0) return;\n");
    cprint("\tif(r->fid == nil || o9app_tree == nil || o9app_tree->root == nil){ respond(r, \"no root\"); return; }\n");
    cprint("\tr->fid->file = o9app_tree->root;\n");
    cprint("\tr->fid->qid = o9app_tree->root->qid;\n");
    cprint("\tr->ofcall.qid = r->fid->qid;\n");
    cprint("\trespond(r, nil);\n");
    cprint("}\n");
    cprint("static void\no9app_create(Req *r)\n{\n");
    cprint("\tFile *f; O9Export *imp; O9ImportStage *st;\n");
    cprint("\tif(r == nil || r->fid == nil || r->fid->file == nil){ respond(r, \"bad fid\"); return; }\n");
    cprint("\tif(r->fid->file != o9app_imports_dir){ respond(r, \"create prohibited\"); return; }\n");
    cprint("\tif((r->ifcall.perm & DMDIR) != 0){ respond(r, \"imports accept files only\"); return; }\n");
    cprint("\tif(!o9app_import_name_ok(r->ifcall.name)){ respond(r, \"bad import name\"); return; }\n");
    cprint("\timp = mallocz(sizeof *imp, 1);\n");
    cprint("\tif(imp == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\timp->tag = O9AUX_IMPORT;\n");
    cprint("\tf = createfile(o9app_imports_dir, r->ifcall.name, \"o9\", 0666, imp);\n");
    cprint("\tif(f == nil){ free(imp); respond(r, \"file exists\"); return; }\n");
    cprint("\tst = o9app_import_stage_new(imp, 0);\n");
    cprint("\tif(st == nil){ removefile(f); respond(r, \"no memory\"); return; }\n");
    cprint("\tst->commit = 1;\n");
    cprint("\tr->fid->file = f;\n");
    cprint("\tr->fid->qid = f->qid;\n");
    cprint("\tr->fid->aux = st;\n");
    cprint("\tr->ofcall.qid = f->qid;\n");
    cprint("\trespond(r, nil);\n");
    cprint("}\n");
    cprint("static void\no9app_root_read(Req *r)\n{\n");
    cprint("\tif(r != nil && r->fid != nil && (r->fid->qid.type & QTAUTH)){ authread(r); return; }\n");
    cprint("\tchar *name;\n\tname = r->fid->file->name;\n");
    cprint("\tchar buf[8192]; char *p;\n\tp = buf; int i;\n");
    /* clone: reading allocates a session and returns its id. */
    cprint("\tif(strcmp(name, \"clone\") == 0){\n");
    cprint("\t\tO9Session *__s;\n\t\t__s = o9app_alloc_session();\n");
    cprint("\t\tchar __idb[16];\n");
    cprint("\t\tif(__s == nil){ respond(r, \"no session\"); return; }\n");
    cprint("\t\tsnprint(__idb, sizeof __idb, \"%%d\\n\", __s->id);\n");
    cprint("\t\treadstr(r, __idb); respond(r, nil); return;\n\t}\n");
    /* Session-local data/status: the file's aux is the O9Session; serve
     * that session's private result/status (the per-caller fix). Named
     * data/status distinguishes them from exports (arbitrary names). */
    cprint("\tif(r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_SESSION){\n");
    cprint("\t\tO9Session *__s;\n\t\t__s = r->fid->file->aux;\n");
    cprint("\t\tchar __sb[4096];\n");
    cprint("\t\tqlock(&__s->lock); snprint(__sb, sizeof __sb, \"%%s\", strcmp(name, \"data\") == 0 ? __s->data : __s->status); qunlock(&__s->lock);\n");
    cprint("\t\treadstr(r, __sb); respond(r, nil); return;\n\t}\n");
    /* Export/import file: its aux holds committed serialized bytes.
     * Serve them ramfs-style (offset/count). */
    cprint("\tif(r->fid->file->aux != nil && (*(int*)r->fid->file->aux == O9AUX_EXPORT || *(int*)r->fid->file->aux == O9AUX_IMPORT)){\n");
    cprint("\t\tO9Export *__ex;\n\t\t__ex = r->fid->file->aux;\n");
    cprint("\t\tvlong __off;\n\t\t__off = r->ifcall.offset; long __cnt;\n\t__cnt = r->ifcall.count;\n");
    cprint("\t\tqlock(&__ex->lock);\n");
    cprint("\t\tif(__off >= __ex->ndata){ qunlock(&__ex->lock); r->ofcall.count = 0; respond(r, nil); return; }\n");
    cprint("\t\tif(__off + __cnt > __ex->ndata) __cnt = __ex->ndata - __off;\n");
    cprint("\t\tmemmove(r->ofcall.data, __ex->data + (int)__off, __cnt);\n");
    cprint("\t\tqunlock(&__ex->lock);\n");
    cprint("\t\tr->ofcall.count = __cnt; respond(r, nil); return;\n\t}\n");
    /* Root data: only the root-ctl (fire-and-forget/debug) reply. */
    cprint("\tif(strcmp(name, \"data\") == 0){ readstr(r, o9app_lastdata); respond(r, nil); return; }\n");
    cprint("\tif(strcmp(name, \"ctl\") == 0){ readstr(r, \"\"); respond(r, nil); return; }\n");
    cprint("\tif(strcmp(name, \"status\") == 0){\n");
    cprint("\t\tp += snprint(p, sizeof buf-(p-buf), \"app %%s\\nstate running\\nclasses\", o9app_name);\n");
    cprint("\t\tfor(i = 0; i < o9app_nclasses; i++) p += snprint(p, sizeof buf-(p-buf), \" %%s\", o9app_classes[i].name);\n");
    /* #8: list instances per class (docs say classes AND instances). */
    cprint("\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    cprint("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    cprint("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"instances %%s\", o9app_classes[i].name);\n");
    cprint("\t\t\tif(o9app_classes[i].listinst != nil) p += o9app_classes[i].listinst(p, (int)(sizeof buf-(p-buf)));\n");
    cprint("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"\\n\");\n");
    cprint("\t\t}\n");
    cprint("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    cprint("\tif(strcmp(name, \"methods\") == 0){\n");
    cprint("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    cprint("\t\t\tchar mb[4096]; o9_method_serialize(o9app_classes[i].name, mb, sizeof mb);\n");
    cprint("\t\t\tp += snprint(p, sizeof buf-(p-buf), \"%%s\", mb);\n");
    cprint("\t\t}\n");
    cprint("\t\treadstr(r, buf); respond(r, nil); return;\n\t}\n");
    cprint("\tif(strcmp(name, \"graph\") == 0){\n");
    cprint("\t\tchar *__gbuf; int __n;\n");
    cprint("\t\t__gbuf = mallocz(16384, 1);\n");
    cprint("\t\tif(__gbuf == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\t\t__n = o9_dag_dump(__gbuf, 16384);\n");
    cprint("\t\treadbuf(r, __gbuf, __n); free(__gbuf); respond(r, nil); return;\n\t}\n");
    cprint("\tif(strcmp(name, \"actors\") == 0){\n");
    cprint("\t\tchar *__abuf, *__ap, *__aep; int __ai, __an;\n");
    cprint("\t\t__abuf = mallocz(32768, 1);\n");
    cprint("\t\tif(__abuf == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\t\t__ap = __abuf; __aep = __abuf + 32768;\n");
    cprint("\t\t__ap = seprint(__ap, __aep, \"# id\\tclass\\tstate\\twaiting_on\\tmethod\\n\");\n");
    cprint("\t\tfor(__ai = 0; __ai < o9app_nclasses && __ap < __aep; __ai++){\n");
    cprint("\t\t\tif(o9app_classes[__ai].listactors != nil)\n");
    cprint("\t\t\t\t__ap += o9app_classes[__ai].listactors(__ap, (int)(__aep - __ap));\n");
    cprint("\t\t}\n");
    cprint("\t\t__an = (int)(__ap - __abuf);\n");
    cprint("\t\treadbuf(r, __abuf, __an); free(__abuf); respond(r, nil); return;\n\t}\n");
    /* state: DEBUG-only inspector.  Off by default (encapsulation);
     * O9DEBUG dumps read-only metadata snapshots plus live state tabs. */
    cprint("\tif(strcmp(name, \"state\") == 0){\n");
    cprint("\t\tif(!o9app_debug){ readstr(r, \"debug disabled (set O9DEBUG)\\n\"); respond(r, nil); return; }\n");
    cprint("\t\t{ char *__dbuf;\n\t__dbuf = mallocz(32768, 1); char *__dp;\n");
    cprint("\t\tif(__dbuf == nil){ respond(r, \"no memory\"); return; }\n");
    cprint("\t\t__dp = __dbuf;\n");
    cprint("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# methods\\n\");\n");
    cprint("\t\t__dp += o9_method_store_serialize(__dp, (int)(32768-(__dp-__dbuf)));\n");
    cprint("\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"\\n\");\n");
    cprint("\t\tfor(i = 0; i < o9app_nclasses; i++){\n");
    cprint("\t\t\tif(o9app_classes[i].dumpstate == nil) continue;\n");
    cprint("\t\t\t__dp += snprint(__dp, 32768-(__dp-__dbuf), \"# %%s\\n\", o9app_classes[i].name);\n");
    cprint("\t\t\t__dp += o9app_classes[i].dumpstate(__dp, (int)(32768-(__dp-__dbuf)));\n");
    cprint("\t\t}\n");
    cprint("\t\treadstr(r, __dbuf); free(__dbuf); respond(r, nil); return; }\n\t}\n");
    cprint("\trespond(r, \"not found\");\n}\n");
    cprint("static void\no9app_root_write(Req *r)\n{\n");
    cprint("\tif(r != nil && r->fid != nil && (r->fid->qid.type & QTAUTH)){ authwrite(r); return; }\n");
    cprint("\tchar *name;\n\tname = r->fid->file->name;\n");
    cprint("\tchar cmd[1024], *f[16]; int nf; char inst[64]; O9ClassH *ch;\n");
    cprint("\tif(r->fid != nil && r->fid->file != nil && r->fid->file->aux != nil && *(int*)r->fid->file->aux == O9AUX_IMPORT){ o9app_import_write(r); return; }\n");
    cprint("\tif(strcmp(name, \"ctl\") != 0){ respond(r, \"read only\"); return; }\n");
    /* No global cur_session: the session is derived from r inside the
     * put_result/put_status helpers (o9app_req_session(r)), so concurrent
     * requests each route to their OWN session. */
    cprint("\tsnprint(cmd, sizeof cmd, \"%%.*s\", (int)r->ifcall.count, (char*)r->ifcall.data);\n");
    cprint("\tnf = tokenize(cmd, f, nelem(f));\n");
    /* `close`: end THIS conversation (a session ctl only) — mark the slot
     * reusable. The explicit release that ends a session's lifetime. */
    cprint("\tif(nf >= 1 && strcmp(f[0], \"close\") == 0){\n");
    cprint("\t\tO9Session *__cs;\n\t\t__cs = o9app_req_session(r);\n");
    cprint("\t\tif(__cs != nil) o9app_close_session(__cs);\n");
    cprint("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    cprint("\tif(nf >= 1 && strcmp(f[0], \"login\") == 0){\n");
    cprint("\t\tO9Session *__ls;\n\t\t__ls = o9app_req_session(r); char __err[128]; int __ok;\n");
    cprint("\t\tif(__ls == nil){ o9app_wipe(cmd, sizeof cmd); respond(r, \"login requires session ctl\"); return; }\n");
    cprint("\t\tif(nf != 3){ o9app_put_status(r, \"error: want login user password\\n\"); o9app_put_result(r, \"\"); o9app_wipe(cmd, sizeof cmd); r->ofcall.count = r->ifcall.count; respond(r, nil); return; }\n");
    cprint("\t\tif(r->srv != nil) srvrelease(r->srv);\n");
    cprint("\t\t__ok = o9app_auth_login(f[1], f[2], __err, sizeof __err);\n");
    cprint("\t\tif(r->srv != nil) srvacquire(r->srv);\n");
    cprint("\t\tqlock(&__ls->lock);\n");
    cprint("\t\tif(__ok){ __ls->blessed = 1; snprint(__ls->authuser, sizeof __ls->authuser, \"%%s\", f[1]); snprint(__ls->status, sizeof __ls->status, \"ok login %%s\\n\", f[1]); snprint(__ls->data, sizeof __ls->data, \"%%s\\n\", f[1]); }\n");
    cprint("\t\telse{ __ls->blessed = 0; __ls->authuser[0] = '\\0'; snprint(__ls->status, sizeof __ls->status, \"error: login failed: %%s\\n\", __err[0] != '\\0' ? __err : \"auth failed\"); __ls->data[0] = '\\0'; }\n");
    cprint("\t\tqunlock(&__ls->lock);\n");
    cprint("\t\to9app_wipe(cmd, sizeof cmd);\n");
    cprint("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    cprint("\tif(nf >= 1 && strcmp(f[0], \"logout\") == 0){\n");
    cprint("\t\tO9Session *__ls;\n\t\t__ls = o9app_req_session(r);\n");
    cprint("\t\tif(__ls == nil){ respond(r, \"logout requires session ctl\"); return; }\n");
    cprint("\t\tqlock(&__ls->lock); __ls->blessed = 0; __ls->authuser[0] = '\\0'; snprint(__ls->status, sizeof __ls->status, \"ok logout\\n\"); __ls->data[0] = '\\0'; qunlock(&__ls->lock);\n");
    cprint("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    cprint("\tif(nf >= 1 && strcmp(f[0], \"whoami\") == 0){\n");
    cprint("\t\tchar __ub[64], __wb[96]; o9app_req_user(r, __ub, sizeof __ub); snprint(__wb, sizeof __wb, \"%%s %%d\\n\", __ub, o9app_req_blessed(r));\n");
    cprint("\t\to9app_put_status(r, \"ok\\n\"); o9app_put_result(r, __wb);\n");
    cprint("\t\tr->ofcall.count = r->ifcall.count; respond(r, nil); return;\n\t}\n");
    cprint("\tif(nf < 3 || (strcmp(f[0], \"method\") != 0 && strcmp(f[0], \"new\") != 0)){ respond(r, \"want: method Class.inst name | new Class inst | login user password | logout | whoami | close\"); return; }\n");
    /* Resolve to a class handler. new Class inst -> resolve by CLASS name
     * (f[1] is the class). method Class.inst -> resolve by Class.inst.
     * The class fswrite re-tokenizes r->ifcall.data itself and handles
     * both new and method, so we only need to pick the right handler. */
    cprint("\tif(strcmp(f[0], \"new\") == 0){\n");
    cprint("\t\tint __ci; ch = nil;\n");
    cprint("\t\tfor(__ci = 0; __ci < o9app_nclasses; __ci++)\n");
    cprint("\t\t\tif(strcmp(o9app_classes[__ci].name, f[1]) == 0){ ch = &o9app_classes[__ci]; break; }\n");
    cprint("\t\tif(ch == nil){ respond(r, \"unknown class\"); return; }\n");
    cprint("\t}else{\n");
    cprint("\t\tch = o9app_resolve(f[1], inst, sizeof inst);\n");
    cprint("\t\tif(ch == nil){ respond(r, \"unknown object\"); return; }\n");
    cprint("\t}\n");
    cprint("\tch->write(r, nil);\t/* class fswrite re-parses r->ifcall.data */\n");
    cprint("}\n\n");

    /* o9_export_tab: publish a tabula into the served-tree exports/ dir at
     * runtime.  A single createfile into the stable exports parent (the
     * safe pattern); the serialized bytes go in the child File's aux.  If
     * a file of that name exists, its bytes are replaced (re-export). */
    cprint("void\no9_export_tab(O9String *name, O9Tabula *t)\n{\n");
    cprint("\tFile *f; O9Export *ex; O9String *bytes; char *cname, *cbytes, *old;\n");
    cprint("\tif(o9app_exports_dir == nil || name == nil || t == nil) return;\n");
    cprint("\tcname = o9_string_cstr(name);\n");
    cprint("\tif(cname == nil) return;\n");
    cprint("\tif(!o9app_export_name_ok(cname)){ free(cname); return; }\n");
    cprint("\tbytes = o9_tab_serialize(t);\n");
    cprint("\tcbytes = o9_string_cstr(bytes);\n");
    cprint("\tif(cbytes == nil){ free(cname); o9_string_release(bytes); return; }\n");
    cprint("\tf = createfile(o9app_exports_dir, cname, \"o9\", 0444, nil);\n");
    cprint("\tif(f == nil){\t/* exists: replace its bytes */\n");
    cprint("\t\tf = walkfile(o9app_exports_dir, cname);\n");
    cprint("\t\tif(f == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    cprint("\t}\n");
    cprint("\tex = f->aux;\n");
    cprint("\tif(ex != nil && ex->tag != O9AUX_EXPORT){ free(cname); free(cbytes); o9_string_release(bytes); return; }\n");
    cprint("\tif(ex == nil){ ex = mallocz(sizeof *ex, 1); if(ex == nil){ free(cname); free(cbytes); o9_string_release(bytes); return; } ex->tag = O9AUX_EXPORT; f->aux = ex; }\n");
    cprint("\tqlock(&ex->lock);\n");
    cprint("\told = ex->data;\n");
    cprint("\tex->data = cbytes; ex->ndata = bytes != nil ? o9_string_len(bytes) : 0;\n");
    cprint("\tf->length = ex->ndata;\n");
    cprint("\tqunlock(&ex->lock);\n");
    cprint("\tfree(old);\n");
    cprint("\tfree(cname); o9_string_release(bytes);\n");
    cprint("}\n\n");

    cprint("static void\no9_app_listen(O9String *addr)\n{\n");
    cprint("\tchar *caddr;\n");
    cprint("\tif(addr == nil) return;\n");
    cprint("\tcaddr = o9_string_cstr(addr);\n");
    cprint("\tif(caddr == nil || caddr[0] == '\\0'){ free(caddr); return; }\n");
    cprint("\tthreadlistensrv(&o9app_srv, caddr);\t/* caddr intentionally lives for process lifetime */\n");
    cprint("}\n\n");

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
    emit_tabula_helpers_node(root);
    for(n = mono_list; n; n = n->next)
        emit_tabula_helpers_node(n);
    for(n = mono_list; n; n = n->next)
        if(n->type == NClass && (n->flags & NFAbstract) == 0)
            gen_class_server(n);
    gen_classes(function_expr_classes);
    last = gen_classes(root);

    /* Per-app facade: one Srv/tree for the whole program.  o9_app_start
     * sets the app names, allocates the shared tree, and posts the single
     * /srv/o9.<app>; each class then registers INTO it. */
    cprint("static void\no9_app_start(int argc, char **argv)\n{\n");
    cprint("\tchar *__o9app;\n\t__o9app = \"%s\";\n", last != nil ? last->name : "app");
    cprint("\tif(argc > 1 && argv[1] != nil && argv[1][0] != '\\0') __o9app = argv[1];\n");
    cprint("\tsnprint(o9app_name, sizeof o9app_name, \"%%s\", __o9app);\n");
    cprint("\t{ char *__d;\n\t__d = getenv(\"O9DEBUG\"); o9app_debug = (__d != nil && __d[0] != '\\0'); free(__d); }\n");
    cprint("\t{ char *__a;\n\t__a = getenv(\"O9AUTH\"); o9app_auth_required = (__a != nil && strcmp(__a, \"required\") == 0); free(__a); }\n");
    cprint("\to9_ns_app_root(o9app_root, sizeof o9app_root, __o9app);\n");
    cprint("\to9_ns_service_name(o9app_srvname, sizeof o9app_srvname, __o9app, __o9app, \"app\");\n");
    cprint("\to9_ns_class_path(o9app_mount, sizeof o9app_mount, o9app_root, __o9app);\n");
    cprint("\to9_ns_ensure_app(o9app_root);\n");
    cprint("\to9app_tree = alloctree(nil, nil, DMDIR|0555, nil);\n");
    cprint("\to9app_srv.tree = o9app_tree;\n");
    cprint("\to9app_srv.read = o9app_root_read;\n\to9app_srv.write = o9app_root_write;\n");
    cprint("\tif(o9app_auth_required){\n");
    cprint("\t\to9app_srv.auth = o9app_auth;\n");
    cprint("\t\to9app_srv.attach = o9app_attach;\n");
    cprint("\t\to9app_srv.keyspec = \"proto=p9any role=server\";\n");
    cprint("\t}\n");
    cprint("\to9app_srv.create = o9app_create;\n");
    cprint("\to9app_srv.open = o9app_open;\n\to9app_srv.destroyfid = o9app_destroyfid;\t/* session fid diagnostics */\n");
    /* The four control files + state are a FIXED shape, built once, never
     * mutated (their content is live, their structure is frozen). */
    cprint("\tcreatefile(o9app_tree->root, \"ctl\", \"o9\", 0666, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"data\", \"o9\", 0444, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"status\", \"o9\", 0444, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"methods\", \"o9\", 0444, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"actors\", \"o9\", 0444, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"graph\", \"o9\", 0444, nil);\n");
    cprint("\tcreatefile(o9app_tree->root, \"state\", \"o9\", 0444, nil);\t/* debug inspector */\n");
    /* clone: reading it allocates a session <id>/ with session-local
     * ctl/data/status (docs/SESSIONS.md) — the /net/tcp/clone pattern that
     * gives concurrent callers a private, path-addressable conversation. */
    cprint("\tcreatefile(o9app_tree->root, \"clone\", \"o9\", 0444, nil);\n");
    /* exports/ is a served-tree DIRECTORY inside the application file tree
     * (NOT on disk).  It is the one MUTABLE part: objects publish tabulae
     * into it at runtime via a single createfile into this stable parent
     * dir (the authsrv/ramfs-proven safe pattern — no nested subtree, no
     * walkfile).  Reachable through the mount; ls reflects live objects. */
    cprint("\to9app_exports_dir = createfile(o9app_tree->root, \"exports\", \"o9\", DMDIR|0555, nil);\n");
    cprint("\to9app_imports_dir = createfile(o9app_tree->root, \"imports\", \"o9\", DMDIR|0777, nil);\n");
    cprint("}\n");
    cprint("static void\no9_app_post(void)\n{\n");
    cprint("\t{ char __sp[160]; snprint(__sp, sizeof __sp, \"/srv/%%s\", o9app_srvname); remove(__sp); }\n");
    cprint("\t{ char __ln[300]; snprint(__ln, sizeof __ln, \"mount /srv/%%s %%s\", o9app_srvname, o9app_mount); o9_ns_recipe(o9app_root, o9app_name, __ln); }\n");
    cprint("\tif(o9_ns_ensure_dir(o9app_mount) == 0)\n");
    /* MREPL|MCREATE: the exports/ dir is mutable — objects createfile
     * into it at runtime — so the facade mount must permit creation
     * (this is exactly what ramfs uses: MREPL|MCREATE). */
    cprint("\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, o9app_mount, MREPL|MCREATE);\n");
    cprint("\telse\n\t\tthreadpostmountsrv(&o9app_srv, o9app_srvname, nil, MREPL|MCREATE);\n");
    cprint("}\n\n");

    cprint("int mainstacksize = 65536;\n\n");
    cprint("void\nthreadmain(int argc, char **argv)\n{\n");
    cprint("\tvlong __o9fr[%d][12];\n", O9_MSG_FRAMES);
    cprint("\tUSED(argc); USED(argv); USED(__o9fr);\n");
    cprint("\to9_process_set_args(argc, argv);\n");
    /* Per-app namespace isolation MUST happen here — the very first thing
     * in threadmain, BEFORE o9_registry_start or any proccreate. Forking
     * the namespace group after procs exist disturbs the thread library's
     * proc/rendezvous group. RFNAMEG copies the namespace (isolation);
     * then re-bind the global #s (srv) device onto /srv so the app's post
     * stays reachable to other processes (facade) — the iostats.c /
     * lib/namespace pattern. Isolation for the app's own tree + shared
     * /srv for the post. Verified: mk export-test = export: OK. */
    cprint("\trfork(RFNAMEG);\n");
    cprint("\tbind(\"#s\", \"/srv\", MREPL|MCREATE);\n");
    cprint("\to9_registry_start();\n");
    gen_object_metadata(root);
    /* One app server; every class that got a class-server (generic
     * and non-generic alike) registers into it, then post once. */
    {
        int __ri;
        cprint("\to9_app_start(argc, argv);\n");
        for(__ri = 0; __ri < o9_nregistered; __ri++)
            cprint("\to9_register_class_%s();\n", o9_registered[__ri]);
        cprint("\to9_app_post();\n");
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
    cprint("\tthreadexitsall(nil);\n}\n");
    source_comments();
}
