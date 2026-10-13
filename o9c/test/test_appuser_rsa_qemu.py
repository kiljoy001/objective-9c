#!/usr/bin/env python3
"""Check AppUser RSA signing against stock 9front factotum in a disposable VM."""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_appuser_rsa_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with tempfile.TemporaryDirectory(prefix="o9appuser-qemu-") as tmp:
        work = Path(tmp)
        source = work / "appuser.c"
        with source.open("w") as output:
            subprocess.run([str(ROOT / "o9c/o9c"), "stdlib/e2e_appuser.o9"],
                           cwd=ROOT, stdout=output, check=True)
        generated = source.read_text()
        for method in ("enroll", "challenge", "answer"):
            if f'o9_method_register("AppUserRSAProvider", "{method}"' in generated:
                raise AssertionError(f"provider {method} leaked into the 9P method table")
        if 'o9_method_register("AppUser", "prove"' in generated:
            raise AssertionError("factotum signing method leaked into the 9P method table")
        if 'o9_method_register("AppUserRSASignRaw", "run"' in generated:
            raise AssertionError("factotum signing helper leaked into the 9P method table")
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        ini = work / "plan9.ini"
        ini.write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat, str(ini), "::plan9.ini"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9usr"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9lib"], check=True)
        runtime = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
                   "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
                   "monocypher.c", "monocypher.h", "o9_dispatch_386.s")
        for name, path in (("appuser.c", source),
                           *((name, ROOT / name) for name in runtime)):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9usr/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.c"):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9lib/{path.name}"], check=True)
        for path in (ROOT / "libtab").glob("*.h"):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9lib/{path.name}"], check=True)

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
                    raise RuntimeError(f"guest command timed out: {command}")

            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")
                for command in (
                    "9fs 9fat",
                    "ramfs",
                    "mkdir /tmp/o9usr",
                    "mkdir /tmp/o9usr/libtab",
                    "cp /n/9fat/o9usr/* /tmp/o9usr",
                    "cp /n/9fat/o9lib/* /tmp/o9usr/libtab",
                    "bind -b /usr/glenda/bin/386 /bin",
                    "cd /tmp/o9usr; mk libo9.a",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9usr -o /tmp/appuser.8 /tmp/o9usr/appuser.c",
                    "8l -o /tmp/appuser /tmp/appuser.8 /tmp/o9usr/libo9.a "
                    "/386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "auth/rsagen -b 2048 -t 'service=appuser app=o9irc hash=sha256' >/tmp/appuser-key",
                    "auth/rsagen -b 2048 -t 'service=appuser app=notes hash=sha256' >/tmp/appuser-other-key",
                    "cat /tmp/appuser-key >/mnt/factotum/ctl",
                    "cat /tmp/appuser-other-key >/mnt/factotum/ctl",
                    "n=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/appuser-key}",
                    "e=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/appuser-key}",
                    "n2=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/appuser-other-key}",
                    "e2=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/appuser-other-key}",
                    "/tmp/appuser appuser $n $e $n2 $e2",
                ):
                    guest(command, 300 if "mk libo9" in command else 180)
                transcript = logpath.read_text(errors="replace")
                for label, wanted in (("PROFILE", "1"), ("SIGNED", "1"),
                                      ("VERIFY", "1"), ("WRONG_SERVICE", "0"),
                                      ("WRONG_NONCE", "0"), ("WRONG_APP", "0"),
                                      ("SECOND_APP_SIGNED", "1"), ("SECOND_APP_VERIFY", "1"),
                                      ("WRONG_KEY", "0"), ("BAD_SCOPE", "1"),
                                      ("PROVIDER_ENROLL", "1"), ("PROVIDER_DUP_KEY", "1"),
                                      ("PROVIDER_BAD_KEY", "1"),
                                      ("PROVIDER_BAD_SCOPE", "1"),
                                      ("PROVIDER_NONCE", "1"), ("PROVIDER_ANSWER", "1"),
                                      ("PROVIDER_REPLAY", "1"), ("PROVIDER_REPLACED", "1"),
                                      ("PROVIDER_REPLACED_CONSUMED", "1"),
                                      ("PROVIDER_BINDING", "1"),
                                      ("PROVIDER_BINDING_OK", "1"), ("PROVIDER_BAD_SIG", "1"),
                                      ("PROVIDER_BAD_RETRY", "1"), ("PROVIDER_EXPIRED", "1")):
                    if not re.search(rf"^{label} {wanted}\r?$", transcript, re.MULTILINE):
                        raise AssertionError(f"missing {label} {wanted}")
                print("APPUSER RSA PROVIDER VM PASS: enrolled keys, bound nonces, expiry, one-time answers")
            except Exception:
                log.flush()
                print(logpath.read_text(errors="replace")[-14000:])
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
