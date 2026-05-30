with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix fid->file->name to fid->file->dir.name
content = content.replace("char *name = r->fid->file->name;", "char *name = r->fid->file->dir.name;")

# Fix ainc/adec to __sync_fetch_and_add for Linux cross-compatibility
content = content.replace("\\tainc(&self->ref);\\n", "\\t__sync_fetch_and_add(&self->ref, 1);\\n")
content = content.replace("adec(&self->ref)", "__sync_sub_and_fetch(&self->ref, 1)")

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
