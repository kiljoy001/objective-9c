#!/usr/bin/env python3
import sys, os

with open("/home/scott/Repo/objective-9c/o9c/o9_plan9.y", "r") as f:
    content = f.read()

old = """    /* 2b. ARC attach/destroyfid callbacks */
    print("static void o9_attach_%s(Req *r) {\\n", c->name);
    print("\\t%s_Internal *self = r->srv->aux;\\n", c->name);
    print("\\tainc(&self->ref);\\n");
    print("\\trespond(r, nil);\\n");
    print("}\\n\\n");
    print("static void o9_destroyfid_%s(Fid *f) {\\n", c->name);
    print("\\tUSED(f);\\n");
    print("\\t%s_Internal *self = f->pool->srv->aux;\\n", c->name);
    print("\\tif(adec(&self->ref) == 0){\\n");"""

new = """    /* 2b. ARC attach/destroyfid callbacks */
    {
        ulong _aid = o9_hash(c->name);
        print("static void o9_attach_%s(Req *r) {\\n", c->name);
        print("\\t%s_Internal *self = r->srv->aux;\\n", c->name);
        print("\\tself->ledger.entries[0x%lux & 63].count++;\\n", _aid);
        print("\\tainc(&self->ref);\\n");
        print("\\trespond(r, nil);\\n");
        print("}\\n\\n");
        print("static void o9_destroyfid_%s(Fid *f) {\\n", c->name);
        print("\\tUSED(f);\\n");
        print("\\t%s_Internal *self = f->pool->srv->aux;\\n", c->name);
        print("\\tself->ledger.entries[0x%lux & 63].count--;\\n", _aid);
        print("\\tif(adec(&self->ref) == 0){\\n");
    }"""

if old not in content:
    print("Old text not found!")
    sys.exit(1)

count = content.count(old)
print(f"Found {count} occurrence")
content = content.replace(old, new, 1)

with open("/home/scott/Repo/objective-9c/o9c/o9_plan9.y", "w") as f:
    f.write(content)
print("ARC wiring applied")
