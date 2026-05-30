import re

# 1. Fix o9_runtime.c for both Linux and 9front
with open('../objective-9c/o9_runtime.c', 'r') as f:
    runtime = f.read()

runtime = runtime.replace("return __sync_add_and_fetch(p, 1);", """#ifdef __GNUC__
        return __sync_add_and_fetch(p, 1);
#else
        return ainc(p);
#endif""")

runtime = runtime.replace("return __sync_sub_and_fetch(p, 1);", """#ifdef __GNUC__
        return __sync_sub_and_fetch(p, 1);
#else
        return adec(p);
#endif""")

# Fix segattach fallback description
runtime = runtime.replace("obj->shm_base = nil; /* segattach not available on Linux */", """#ifdef __GNUC__
        obj->shm_base = nil; /* TODO: Implement shm_open for Tier 1 on Linux */
#else
        obj->shm_base = segattach(0, nil, tag, 0);
#endif""")

with open('../objective-9c/o9_runtime.c', 'w') as f:
    f.write(runtime)

# 2. Fix o9.y generated code for both Linux and 9front
with open('../objective-9c/o9c/o9.y', 'r') as f:
    yacc = f.read()

# Fix atomics in yacc generated C
yacc = yacc.replace("\\t__sync_fetch_and_add(&self->ref, 1);\\n", """#ifdef __GNUC__
        print("\\t__sync_fetch_and_add(&self->ref, 1);\\n");
#else
        print("\\tainc(&self->ref);\\n");
#endif""")

yacc = yacc.replace("__sync_sub_and_fetch(&self->ref, 1)", """#ifdef __GNUC__
                __sync_sub_and_fetch(&self->ref, 1)
#else
                adec(&self->ref)
#endif""")

# Fix File name access (9front vs plan9port)
# In plan9port, File is a struct with a Dir dir member. In 9front, it might be different or accessed differently.
# Standard 9front lib9p uses File->name. plan9port uses File->dir.name.
yacc = yacc.replace("r->fid->file->dir.name", """#ifdef __GNUC__
        r->fid->file->dir.name
#else
        r->fid->file->name
#endif""")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(yacc)
