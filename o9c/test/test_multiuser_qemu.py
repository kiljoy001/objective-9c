#!/usr/bin/env python3
"""Build the generated multiuser facade with 9front C in an isolated VM."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_multiuser_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix="o9multi-qemu-") as tmp:
        work = Path(tmp)
        source = work / "multiuser.c"
        with source.open("w") as output:
            subprocess.run([str(ROOT / "o9c/o9c"),
                            "o9c/test/multiuser_view_app.o9"],
                           cwd=ROOT, check=True, stdout=output)
        legacy = work / "legacy.c"
        with legacy.open("w") as output:
            subprocess.run([str(ROOT / "o9c/o9c"),
                            "o9c/test/view_app.o9"],
                           cwd=ROOT, check=True, stdout=output)
        if "int o9app_multiuser = 1;" not in source.read_text():
            raise AssertionError("multiuser declaration was not generated")
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        ini = work / "plan9.ini"
        ini.write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat, str(ini),
                        "::plan9.ini"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9multi"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9mlib"], check=True)
        arch = os.environ.get("O9_MULTIUSER_VM_ARCH", "386")
        if arch not in ("386", "amd64"):
            raise ValueError("O9_MULTIUSER_VM_ARCH must be 386 or amd64")
        runtime = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
                   "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
                   "monocypher.c", "monocypher.h",
                   f"o9_dispatch_{arch}.s")
        for name, path in (("multiuser.c", source),
                           ("legacy.c", legacy),
                           ("multiuser_guard_probe.c", ROOT / "o9c/test/multiuser_guard_probe.c"),
                           *((name, ROOT / name) for name in runtime)):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9multi/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.c"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9mlib/{path.name}"], check=True)
        for path in (ROOT / "libtab").glob("*.h"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9mlib/{path.name}"], check=True)
        obj = "8" if arch == "386" else "6"
        qemu = [f"qemu-system-{'i386' if arch == '386' else 'x86_64'}",
                "-m", "1024", "-display", "none", "-monitor", "none",
                "-serial", "stdio", "-no-reboot", "-netdev", "user,id=n0",
                "-device", "ne2k_pci,netdev=n0",
                "-drive", f"file={disk},format=raw,if=ide,index=0"]
        if os.access("/dev/kvm", os.R_OK | os.W_OK):
            qemu.insert(1, "-enable-kvm")
        logpath = work / "serial.log"
        with logpath.open("w") as log:
            proc = subprocess.Popen(qemu, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            console = builder.Console(proc, log)
            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")

                def guest(command, timeout=90):
                    log.flush()
                    start = logpath.stat().st_size
                    for char in command + "\n":
                        proc.stdin.write(char.encode())
                        proc.stdin.flush()
                        time.sleep(0.006)
                    if console.expect(["term% "], timeout) is None:
                        raise RuntimeError(f"guest command timed out: {command}")
                    log.flush()
                    result = logpath.read_bytes()[start:].decode(errors="replace")
                    if "error:" in result.lower() or "undefined:" in result.lower():
                        raise RuntimeError(f"guest command failed: {command}\n{result}")
                    return result

                guest("9fs 9fat", 30)
                guest("ramfs", 30)
                guest("mkdir /tmp/o9multi", 30)
                guest("mkdir /tmp/o9multi/libtab", 30)
                guest("cp /n/9fat/o9multi/* /tmp/o9multi", 45)
                guest("cp /n/9fat/o9mlib/* /tmp/o9multi/libtab", 45)
                guest(f"bind -b /usr/glenda/bin/{arch} /bin", 30)
                guest("cd /tmp/o9multi; mk libo9.a", 300)
                guest(f"{obj}c -I/tmp/o9multi -o /tmp/o9guard.{obj} "
                      "/tmp/o9multi/multiuser_guard_probe.c", 120)
                guest(f"{obj}l -o /tmp/o9guard /tmp/o9guard.{obj} "
                      f"/tmp/o9multi/libo9.a /{arch}/lib/libndb.a", 120)
                guard = guest("/tmp/o9guard", 30)
                if "O9 MULTIUSER GUARD PASS" not in guard:
                    raise AssertionError(f"owner checks failed: {guard}")
                guest(f"{obj}c -I/tmp/o9multi -o /tmp/o9legacy.{obj} "
                      "/tmp/o9multi/legacy.c", 120)
                guest(f"{obj}l -o /tmp/o9legacy-app /tmp/o9legacy.{obj} "
                      f"/tmp/o9multi/libo9.a /{arch}/lib/libndb.a", 120)
                guest("/tmp/o9legacy-app o9legacy </dev/null >/tmp/o9legacy.log >[2=1] &", 30)
                guest("sleep 1", 30)
                guest("mkdir /tmp/o9legacy-mount", 30)
                guest("mount -n -c /srv/o9legacy /tmp/o9legacy-mount", 30)
                legacy_view = guest("cat /tmp/o9legacy-mount/view/identity", 30)
                if "viewer" not in legacy_view.splitlines()[-1]:
                    raise AssertionError(f"legacy view regressed: {legacy_view}")
                guest(f"{obj}c -I/tmp/o9multi -o /tmp/o9multi.{obj} "
                      "/tmp/o9multi/multiuser.c", 120)
                guest(f"{obj}l -o /tmp/o9multi-app /tmp/o9multi.{obj} "
                      f"/tmp/o9multi/libo9.a "
                      f"/{arch}/lib/libndb.a", 120)
                guest("/tmp/o9multi-app o9multi </dev/null >/tmp/o9multi.log >[2=1] &", 30)
                guest("sleep 2", 30)
                service = guest("ls /srv/o9multi", 30)
                if "/srv/o9multi" not in service:
                    raise AssertionError("multiuser 9P service did not post")
                guest("mkdir /tmp/o9mount", 30)
                denied = guest("if(mount -n -c /srv/o9multi /tmp/o9mount >[2]/tmp/o9mount.err) "
                               "echo UNAUTH-ACCEPTED; if not echo UNAUTH-DENIED", 30)
                lines = [line.strip() for line in denied.splitlines()[1:]]
                if "UNAUTH-DENIED" not in lines or "UNAUTH-ACCEPTED" in lines:
                    raise AssertionError(f"unauthenticated attach was accepted: {denied}")
                print("O9 MULTIUSER VM PASS: built and denied unauthenticated attach")
            except Exception:
                log.flush()
                print(logpath.read_text(errors="replace")[-12000:])
                raise
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == "__main__":
    main()
