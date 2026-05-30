with open('../objective-9c/o9_runtime.c', 'r') as f:
    content = f.read()

content = content.replace("return ainc(p);", "return __sync_add_and_fetch(p, 1);")
content = content.replace("return adec(p);", "return __sync_sub_and_fetch(p, 1);")
content = content.replace("obj->shm_base = segattach(0, nil, tag, 0);", "obj->shm_base = nil; /* segattach not available on Linux */")

with open('../objective-9c/o9_runtime.c', 'w') as f:
    f.write(content)
