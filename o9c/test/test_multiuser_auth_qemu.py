#!/usr/bin/env python3
"""Exercise two factotum identities against an o9c service in a 9front VM."""

import importlib.util
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] not in ("p9sk1", "dp9ik")):
        raise SystemExit("usage: test_multiuser_auth_qemu.py /path/to/9front.img [p9sk1|dp9ik]")
    proto = sys.argv[2] if len(sys.argv) == 3 else "p9sk1"
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    passwords = {name: secrets.token_hex(12) for name in ("keyfs", "o9srv", "alice", "bob")}

    with tempfile.TemporaryDirectory(prefix="o9auth-qemu-") as tmp:
        work = Path(tmp)
        source = work / "multiuser.c"
        with source.open("w") as output:
            subprocess.run([str(ROOT / "o9c/o9c"),
                            "o9c/test/multiuser_view_app.o9"],
                           cwd=ROOT, stdout=output, check=True)
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        ini = work / "plan9.ini"
        ini.write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat, str(ini), "::plan9.ini"], check=True)
        for name in ("vm_auth_key.c", "vm_as.c", "vm_auth_client.rc"):
            subprocess.run(["mcopy", "-o", "-i", fat,
                            str(ROOT / "o9c/test" / name), f"::{name}"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9multi"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9mlib"], check=True)
        runtime = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c", "o9_view.c",
                   "o9_tab_discard.c", "o9_crypto.c", "monocypher.c", "monocypher.h",
                   "o9_dispatch_386.s")
        for name, path in (("multiuser.c", source),
                           *((name, ROOT / name) for name in runtime)):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9multi/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.c"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9mlib/{path.name}"], check=True)
        for path in (ROOT / "libtab").glob("*.h"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9mlib/{path.name}"], check=True)

        qemu = ["qemu-system-i386", "-m", "1024", "-display", "none",
                "-monitor", "none", "-serial", "stdio", "-no-reboot",
                "-netdev", "user,id=n0", "-device", "ne2k_pci,netdev=n0",
                "-drive", f"file={disk},format=raw,if=ide,index=0"]
        if os.access("/dev/kvm", os.R_OK | os.W_OK):
            qemu.insert(1, "-enable-kvm")
        logpath = work / "serial.log"
        with logpath.open("w") as log:
            proc = subprocess.Popen(qemu, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            console = builder.Console(proc, log)
            serial = 0

            def guest(command, timeout=60):
                nonlocal serial
                marker = f"O9END{serial:04d}"
                serial += 1
                proc.stdin.write((command + "; echo " + marker + "\n").encode())
                proc.stdin.flush()
                if console.expect([marker + "\r\nterm% ", marker + "\nterm% "], timeout) is None:
                    raise RuntimeError(f"guest command {serial} timed out")

            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")
                # An existing key file selects DES mode; an absent file lets
                # keyfs initialize AES mode for dp9ik.
                if proto == "p9sk1":
                    guest("echo x >/tmp/o9keys")
                proc.stdin.write(b"auth/keyfs -p /tmp/o9keys\n")
                proc.stdin.flush()
                if console.expect(["Password"], 30) is None:
                    raise RuntimeError("keyfs did not prompt")
                proc.stdin.write((passwords["keyfs"] + "\n").encode())
                proc.stdin.flush()
                if console.expect(["term% "], 30) is None:
                    raise RuntimeError("keyfs did not start")

                for command in (
                    "9fs 9fat",
                    "cp /n/9fat/vm_auth_key.c /tmp/vm_auth_key.c",
                    "8c -o /tmp/vm_auth_key.8 /tmp/vm_auth_key.c",
                    "8l -o /tmp/vm_auth_key /tmp/vm_auth_key.8",
                    "cp /n/9fat/vm_as.c /tmp/vm_as.c",
                    "8c -o /tmp/vm_as.8 /tmp/vm_as.c",
                    "8l -o /tmp/vm_as /tmp/vm_as.8 /386/lib/libsec.a",
                    "cp /n/9fat/vm_auth_client.rc /tmp/vm_auth_client.rc",
                    *(f"/tmp/vm_auth_key {name} {passwords[name]}"
                      for name in ("o9srv", "alice", "bob")),
                    "echo 'authdom=o9vm auth=127.0.0.1' >>/lib/ndb/local",
                    "ip/ipconfig loopback /dev/null 127.0.0.1 /8",
                    "aux/listen1 -t tcp!*!567 auth/authsrv >/tmp/o9authsrv.log >[2=1] &",
                    *(f"echo 'key proto={proto} dom=o9vm user={name} !password={passwords[name]}' >/mnt/factotum/ctl"
                      for name in ("o9srv", "alice", "bob")),
                    "mkdir /tmp/o9multi",
                    "mkdir /tmp/o9multi/libtab",
                    "cp /n/9fat/o9multi/* /tmp/o9multi",
                    "cp /n/9fat/o9mlib/* /tmp/o9multi/libtab",
                ):
                    guest(command)
                guest("cd /tmp/o9multi; mk libo9.a", 300)
                for command in (
                    "8c -I/tmp/o9multi -o /tmp/o9multi.8 /tmp/o9multi/multiuser.c",
                    "8l -o /tmp/o9multi-app /tmp/o9multi.8 /tmp/o9multi/libo9.a /386/lib/libndb.a",
                    "/tmp/o9multi-app o9multi </dev/null >/tmp/o9multi.log >[2=1] &",
                    "sleep 2",
                    "chmod 666 /srv/o9multi",
                    "mkdir /tmp/o9mt-alice",
                    "mkdir /tmp/o9mt-bob",
                    "chmod 777 /tmp/o9mt-alice /tmp/o9mt-bob /tmp",
                    "/tmp/vm_as alice /bin/rc /tmp/vm_auth_client.rc alice",
                    "/tmp/vm_as bob /bin/rc /tmp/vm_auth_client.rc bob alice",
                    "/tmp/vm_as alice /bin/rc /tmp/vm_auth_client.rc alice bob",
                ):
                    guest(command)
                log.flush()
                transcript = logpath.read_text(errors="replace")
                passes = re.findall(r"^O9 AUTH CLIENT PASS: (alice|bob) session (\d+)$",
                                    transcript, re.MULTILINE)
                if passes != [("alice", "0"), ("bob", "1"), ("alice", "2")]:
                    raise AssertionError(f"authenticated client results: {passes}")
                if re.search(r"^O9 AUTH .*FAIL|^O9 AUTH CROSS ACCESS|^O9 AUTH WRONG DENIAL",
                             transcript, re.MULTILINE):
                    raise AssertionError("authenticated client reported a failure")
                print(f"O9 MULTIUSER AUTH VM PASS ({proto}): Alice/Bob factotum attaches, private views, cross-user denial")
            except Exception:
                log.flush()
                transcript = logpath.read_text(errors="replace")
                for password in passwords.values():
                    transcript = transcript.replace(password, "<test-password>")
                print(transcript[-12000:])
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
