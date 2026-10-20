#include <u.h>
#include <libc.h>
#include <thread.h>
#include "o9.h"
#include "o9test.h"

#ifdef O9_PROFILE
/* threadexitsall -> _exits -> _exit bypasses atexit handlers, so the
 * clang profile runtime would never flush.  Flush explicitly in the
 * coverage build. */
extern void __llvm_profile_write_file(void);
#endif

/*
 * Host-side edge tests for the o9 runtime.
 *
 * These are the primitives that the grid, the app facade, and the stdlib
 * all sit on.  They run on plan9port (Linux) as well as native 9front,
 * so a regression is caught without booting a VM.
 *
 * The tests deliberately cover boundaries the existing e2e suites do not:
 * nil/empty inputs, negative indices, out-of-range slices, path traversal,
 * duplicate mount ids, channel ownership transfer, and the vault's
 * plaintext-free temporary-file contract.
 */

static O9String*
s(char *text)
{
	return o9_string_from_c(text);
}

static void
test_strings(void)
{
	O9String *a, *b, *p;

	O9T_CASE("strings");
	a = s("alpha");
	o9t_eqint("length", o9_string_len(a), 5);
	o9t_eqstr("data", o9_string_data(a), "alpha");
	p = s("al");
	o9t_eqint("startswith", o9_string_startswith(a, p), 1);
	o9_string_release(p);
	p = s("ha");
	o9t_eqint("endswith", o9_string_endswith(a, p), 1);
	o9_string_release(p);
	p = s("ph");
	o9t_eqint("indexof", o9_string_indexof(a, p), 2);
	o9_string_release(p);
	p = s("zz");
	o9t_eqint("missing indexof", o9_string_indexof(a, p), -1);
	o9_string_release(p);
	b = o9_string_slice(a, 1, 3);
	o9t_eqstr("slice", o9_string_data(b), "lph");
	o9_string_release(b);
	b = o9_string_lower(s("ALPHA"));
	o9t_eqstr("lower", o9_string_data(b), "alpha");
	o9_string_release(b);
	b = o9_string_upper(s("alpha"));
	o9t_eqstr("upper", o9_string_data(b), "ALPHA");
	o9_string_release(b);
	o9t_eqstr("nil data", o9_string_data(nil), "");
	o9t_eqint("nil len", o9_string_len(nil), 0);
	o9_string_release(a);
}

static void
test_arrays(void)
{
	char *a;

	O9T_CASE("arrays");
	a = nil;
	o9_array_set(&a, 0, 7);
	o9t_eqint("append length", o9_array_len(a), 1);
	o9t_eqint("append value", o9_array_get(a, 0), 7);
	o9_array_set(&a, 2, 9);
	o9t_eqint("extend length", o9_array_len(a), 3);
	o9t_eqint("gap is zero", o9_array_get(a, 1), 0);
	o9t_eqint("extended value", o9_array_get(a, 2), 9);
	o9_array_set(&a, 1, 8);
	o9t_eqint("replace", o9_array_get(a, 1), 8);
	o9t_eqint("negative get", o9_array_get(a, -1), 0);
	o9t_eqint("past-end get", o9_array_get(a, 99), 0);
	free(a);
}

static void
test_slices(void)
{
	O9Slice sl;
	vlong v;

	O9T_CASE("slices");
	o9_slice_init(&sl, sizeof(vlong));
	v = 1;
	o9_slice_append(&sl, &v);
	o9t_eqint("append length", sl.len, 1);
	o9t_notnil("element", o9_slice_get(&sl, 0));
	o9t_eqint("element value", *(vlong*)o9_slice_get(&sl, 0), 1);
	v = 2;
	o9_slice_set(&sl, 0, &v);
	o9t_eqint("set value", *(vlong*)o9_slice_get(&sl, 0), 2);
	o9_slice_set(&sl, 5, &v);
	o9t_eqint("out-of-range set leaves length", sl.len, 1);
	v = 4;
	o9_slice_setgrow(&sl, 3, &v);
	o9t_eqint("grow length", sl.len, 4);
	o9t_eqint("grow value", *(vlong*)o9_slice_get(&sl, 3), 4);
	o9t_eqint("grown gap zero", *(vlong*)o9_slice_get(&sl, 1), 0);
	o9t_nil("negative get", o9_slice_get(&sl, -1));
	o9_slice_free(&sl);
}

/* Deterministic LCG: model tests should not depend on the host's rand(). */
static uvlong model_rng = 0x9e3779b97f4a7c15ULL;
static uvlong
model_rand(void)
{
	model_rng = model_rng * 6364136223846793005ULL + 1442695040888963407ULL;
	return model_rng >> 17;
}

static void
test_array_model(void)
{
	char *a;
	vlong model[24];
	int i, j, idx, len;

	O9T_CASE("array model");
	memset(model, 0, sizeof model);
	a = nil;
	len = 0;
	for(i = 0; i < 200; i++){
		idx = model_rand() % nelem(model);
		model[idx] = (vlong)(model_rand() % 1000);
		o9_array_set(&a, idx, model[idx]);
		if(idx >= len)
			len = idx + 1;
		if(!o9t_eqint("model length", o9_array_len(a), len))
			break;
		for(j = 0; j < len; j++)
			if(!o9t_eqint("model value", o9_array_get(a, j), model[j]))
				break;
	}
	free(a);
}

static void
test_slice_model(void)
{
	O9Slice sl;
	vlong model[24], v;
	int i, j, idx, len;

	O9T_CASE("slice model");
	memset(model, 0, sizeof model);
	o9_slice_init(&sl, sizeof(vlong));
	len = 0;
	for(i = 0; i < 200; i++){
		if((model_rand() & 1) == 0){
			if(len >= nelem(model))
				continue;
			v = (vlong)(model_rand() % 1000);
			o9_slice_append(&sl, &v);
			model[len++] = v;
		}else{
			idx = model_rand() % nelem(model);
			v = (vlong)(model_rand() % 1000);
			o9_slice_setgrow(&sl, idx, &v);
			if(idx >= len){
				for(j = len; j <= idx; j++)
					model[j] = 0;
				len = idx + 1;
			}
			model[idx] = v;
		}
		if(!o9t_eqint("model length", sl.len, len))
			break;
		for(j = 0; j < len; j++)
			if(!o9t_eqint("model value", *(vlong*)o9_slice_get(&sl, j),
			    model[j]))
				break;
	}
	o9_slice_free(&sl);
}

static void
test_dict_model(void)
{
	O9Dict d;
	vlong key, val, model[24];
	int i, present[24];

	O9T_CASE("dict model");
	memset(model, 0, sizeof model);
	memset(present, 0, sizeof present);
	o9_dict_init_typed(&d, sizeof(vlong), sizeof(vlong),
		O9DICT_INT, O9DICT_INT);
	for(i = 0; i < 200; i++){
		key = model_rand() % nelem(model);
		val = (vlong)(model_rand() % 1000);
		o9_dict_setv(&d, &key, &val);
		model[key] = val;
		present[key] = 1;
		if(!o9t_eqint("model has", o9_dict_hasi(&d, key), 1))
			break;
		if(o9t_notnil("model get", o9_dict_geti(&d, key)))
			o9t_eqint("model value", *(vlong*)o9_dict_geti(&d, key),
				model[key]);
	}
	for(key = 0; key < nelem(model); key++)
		o9t_eqint("model presence", o9_dict_hasi(&d, key), present[key]);
	o9_dict_free(&d);
}

static void
test_dicts(void)
{
	O9Dict d;
	vlong k, v;

	O9T_CASE("dicts");
	o9_dict_init_typed(&d, sizeof(vlong), sizeof(vlong),
		O9DICT_INT, O9DICT_INT);
	k = 7;
	v = 42;
	o9_dict_setv(&d, &k, &v);
	o9t_eqint("has", o9_dict_hasi(&d, 7), 1);
	o9t_eqint("missing", o9_dict_hasi(&d, 8), 0);
	if(o9t_notnil("get", o9_dict_geti(&d, 7)))
		o9t_eqint("value", *(vlong*)o9_dict_geti(&d, 7), 42);
	v = 43;
	o9_dict_setv(&d, &k, &v);
	o9t_eqint("replace", *(vlong*)o9_dict_geti(&d, 7), 43);
	o9_dict_free(&d);
}

static void
test_channels(void)
{
	O9ChanMsg *m;
	O9String *src, *out;
	int in, got;

	O9T_CASE("channels");
	in = 123;
	got = 0;
	m = o9_chan_pack(&in, sizeof in);
	if(o9t_notnil("raw pack", m)){
		o9t_eqint("raw take", o9_chan_take(m, &got, sizeof got), 0);
		o9t_eqint("raw value", got, 123);
		o9t_eqint("wrong take size", o9_chan_take(m, &got, 1), -1);
		o9_chan_free(m);
	}

	src = s("hello");
	out = nil;
	m = o9_chan_pack_string(src);
	if(o9t_notnil("string pack", m)){
		o9t_eqint("string take", o9_chan_take(m, &out, sizeof out), 0);
		if(o9t_notnil("string out", out))
			o9t_eqstr("string value", o9_string_data(out), "hello");
		o9_chan_free(m);	/* taken: must not release out */
		o9_string_release(out);
	}
	o9_string_release(src);
}

static void
test_filetree(void)
{
	O9FileTree *t;
	O9FTEntry *root, *leaf, **listing;
	O9String *data;
	char *copy;

	O9T_CASE("filetree");
	t = o9_filetree_new();
	if(!o9t_notnil("new tree", t))
		return;
	root = o9_filetree_root(t);
	o9t_notnil("root", root);
	o9t_eqint("dir", o9_filetree_dir(t, s("nested")), 0);
	o9t_eqint("text", o9_filetree_text(t, s("nested/leaf"), s("value"), 0), 0);
	leaf = o9_filetree_lookup(t, o9_filetree_lookup(t, root, "nested"), "leaf");
	if(o9t_notnil("leaf", leaf)){
		data = o9_filetree_data(t, leaf);
		if(o9t_notnil("leaf data", data)){
			copy = o9_string_cstr(data);
			o9t_eqstr("leaf value", copy, "value");
			free(copy);
			o9_string_release(data);
		}
	}
	o9t_eqint("missing lookup", o9_filetree_lookup(t, root, "missing") == nil, 1);
	o9t_eqint("traversal rejected", o9_filetree_text(t, s("../escape"), s("x"), 0), -1);
	o9t_eqint("absolute rejected", o9_filetree_text(t, s("/escape"), s("x"), 0), -1);
	o9t_eqint("empty component rejected", o9_filetree_text(t, s("a//b"), s("x"), 0), -1);
	o9t_eqint("register", o9_filetree_register(t, s("source")), 0);
	o9t_eqint("duplicate register", o9_filetree_register(t, s("source")), -1);
	o9t_eqint("listing", o9_filetree_entries(t, root, &listing), 1);
	free(listing);
	o9_filetree_revoke(t);
	o9t_eqint("revoked lookup", o9_filetree_lookup(t, root, "nested") == nil, 1);
	o9t_eqint("destroy", o9_filetree_destroy(t), 0);
}

/* Count `/tmp/o9vtab.<pid>.*` entries; used to prove open_tab removes its
 * plaintext scratch file even on the success path. */
static int
vault_temps(void)
{
	Dir *d;
	char prefix[64];
	int fd, i, n, count;

	snprint(prefix, sizeof prefix, "o9vtab.%d.", getpid());
	fd = open("/tmp", OREAD);
	if(fd < 0)
		return -1;
	n = dirreadall(fd, &d);
	close(fd);
	if(n < 0)
		return -1;
	count = 0;
	for(i = 0; i < n; i++)
		if(strncmp(d[i].name, prefix, strlen(prefix)) == 0)
			count++;
	free(d);
	return count;
}

static void
test_vault_tab(void)
{
	O9Vault *v;
	O9Tabula *t, *opened;
	O9String *key, *id, *col, *val, *path, *blob, *got;
	char pbuf[256], *copy;
	int before, after;

	O9T_CASE("vault tab");
	key = s("000102030405060708090a0b0c0d0e0f"
		"101112131415161718191a1b1c1d1e1f");
	v = o9_vault_new_key(key);
	o9_string_release(key);
	if(!o9t_notnil("vault", v))
		return;
	t = o9_tab_new(s("secrets"), s("id,value"));
	if(!o9t_notnil("tab", t)){
		o9_vault_close(v);
		return;
	}
	id = s("row1");
	col = s("value");
	val = s("s3cr3t");
	o9t_eqint("tab write", o9_tab_write(t, id, col, val), 0);
	o9_string_release(id);
	o9_string_release(col);
	o9_string_release(val);

	o9t_tmppath(pbuf, sizeof pbuf, "o9-vault-tab");
	remove(pbuf);
	path = o9_string_from_c(pbuf);
	before = vault_temps();
	o9t_ok("seal tab", o9_vault_seal_tab(v, path, t) >= 0);
	blob = o9_readfile(path);
	if(o9t_notnil("ciphertext", blob)){
		copy = o9_string_cstr(blob);
		o9t_ok("plaintext absent from sealed file",
			copy == nil || strstr(copy, "s3cr3t") == nil);
		free(copy);
		o9_string_release(blob);
	}
	opened = o9_vault_open_tab(v, path);
	if(o9t_notnil("opened tab", opened)){
		id = s("row1");
		col = s("value");
		got = o9_tab_value(opened, id, col);
		if(o9t_notnil("opened value", got)){
			copy = o9_string_cstr(got);
			o9t_eqstr("round trip", copy, "s3cr3t");
			free(copy);
			o9_string_release(got);
		}
		o9_string_release(id);
		o9_string_release(col);
		o9_tab_close(opened);
	}
	after = vault_temps();
	o9t_eqint("no plaintext temp left", after, before);
	o9_tab_close(t);
	o9_vault_close(v);
	remove(pbuf);
	o9_string_release(path);
}

static int dispatch_hits;

static void
dispatch_probe(void *arg)
{
	dispatch_hits++;
	if(arg != nil)
		*(vlong*)arg = 42;
}

static void
test_dispatch_ownership(void)
{
	o9_Object obj;
	o9_AsmTable table;
	Channel *mine, *other;
	vlong out;

	O9T_CASE("dispatch-ownership");
	memset(&obj, 0, sizeof obj);
	memset(&table, 0, sizeof table);
	mine = chancreate(sizeof(void*), 1);
	other = chancreate(sizeof(void*), 1);
	obj.table = &table;
	obj.dispatch_chan = mine;
	table.ctrl_cache[0x1234 & 63].hash = 0x1234;
	table.ctrl_cache[0x1234 & 63].ptr = dispatch_probe;

	/* Main thread is not an actor: a direct call must not touch the
	 * object's state.  Generated code falls back to obj9_msgSendN. */
	dispatch_hits = 0;
	o9t_eqint("cross-actor direct call rejected",
		o9_dispatch_call_checked(&obj, 0x1234, nil) == nil, 1);
	o9t_eqint("cross-actor thunk not run", dispatch_hits, 0);

	/* A nil dispatch channel is not an actor and gets no exemption. */
	obj.dispatch_chan = nil;
	o9t_eqint("no-channel direct call rejected",
		o9_dispatch_call_checked(&obj, 0x1234, nil) == nil, 1);
	o9t_eqint("no-channel thunk not run", dispatch_hits, 0);
	obj.dispatch_chan = mine;

	/* The owning actor may use the cached thunk. */
	o9_actor_enter(mine, "test");
	out = 0;
	o9t_eqint("same-actor direct call accepted",
		o9_dispatch_call_checked(&obj, 0x1234, &out) != nil, 1);
	o9t_eqint("same-actor thunk ran", dispatch_hits, 1);
	o9t_eqint("same-actor result", out, 42);

	/* A different actor must also go through the mailbox. */
	o9_actor_enter(other, "other");
	dispatch_hits = 0;
	o9t_eqint("other-actor direct call rejected",
		o9_dispatch_call_checked(&obj, 0x1234, nil) == nil, 1);
	o9t_eqint("other-actor thunk not run", dispatch_hits, 0);
	o9_actor_enter(nil, nil);

	chanfree(mine);
	chanfree(other);
}

void
threadmain(int, char**)
{
	o9t_begin("host-runtime");
	test_strings();
	test_arrays();
	test_array_model();
	test_slices();
	test_slice_model();
	test_dicts();
	test_dict_model();
	test_channels();
	test_dispatch_ownership();
	test_filetree();
	test_vault_tab();
#ifdef O9_PROFILE
	__llvm_profile_write_file();
#endif
	threadexitsall(o9t_report());
}
