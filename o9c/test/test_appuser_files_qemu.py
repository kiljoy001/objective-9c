#!/usr/bin/env python3
"""Exercise per-attach AppUser .tab files in a disposable 9front VM."""

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
        raise SystemExit("usage: test_appuser_files_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with tempfile.TemporaryDirectory(prefix="o9appfiles-qemu-") as tmp:
        work = Path(tmp)
        for kind in ("server", "client", "status"):
            with (work / f"{kind}.c").open("w") as output:
                subprocess.run([str(ROOT / "o9c/o9c"),
                                f"stdlib/e2e_appuser_files_{kind}.o9"],
                               cwd=ROOT, stdout=output, check=True)
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        (work / "plan9.ini").write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat, str(work / "plan9.ini"), "::plan9.ini"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9files"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9flib"], check=True)
        subprocess.run(["mcopy", "-i", fat,
                        str(ROOT / "o9c/test/vm_appuser_split.c"),
                        "::vm_appuser_split.c"], check=True)
        runtime = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
                   "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
                   "monocypher.c", "monocypher.h", "o9_dispatch_386.s")
        for name, path in (("server.c", work / "server.c"),
                           ("client.c", work / "client.c"),
                           ("status.c", work / "status.c"),
                           *((name, ROOT / name) for name in runtime)):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9files/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.c"):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9flib/{path.name}"], check=True)
        for path in (ROOT / "libtab").glob("*.h"):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9flib/{path.name}"], check=True)

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
                    "9fs 9fat", "ramfs", "mkdir /tmp/o9files", "mkdir /tmp/o9files/libtab",
                    "cp /n/9fat/o9files/* /tmp/o9files",
                    "cp /n/9fat/o9flib/* /tmp/o9files/libtab",
                    "bind -b /usr/glenda/bin/386 /bin",
                    "cd /tmp/o9files; mk libo9.a",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9files -o /tmp/o9files/server.8 /tmp/o9files/server.c",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9files -o /tmp/o9files/client.8 /tmp/o9files/client.c",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9files -o /tmp/o9files/status.8 /tmp/o9files/status.c",
                    "8l -o /tmp/o9appfiles-server /tmp/o9files/server.8 /tmp/o9files/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "8l -o /tmp/o9appfiles-client /tmp/o9files/client.8 /tmp/o9files/libo9.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a /386/lib/libndb.a",
                    "8l -o /tmp/o9appfiles-status /tmp/o9files/status.8 /tmp/o9files/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "cp /n/9fat/vm_appuser_split.c /tmp/vm_appuser_split.c",
                    "8c -o /tmp/vm_appuser_split.8 /tmp/vm_appuser_split.c",
                    "8l -o /tmp/vm_appuser_split /tmp/vm_appuser_split.8",
                    "auth/rsagen -b 2048 -t 'service=appuser app=o9irc hash=sha256' >/tmp/appuser-key",
                    "cat /tmp/appuser-key >/mnt/factotum/ctl",
                    "n=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/appuser-key}",
                    "e=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/appuser-key}",
                    "/tmp/o9appfiles-server appuserfiles $n $e </dev/null >/tmp/o9appfiles.log >[2=1] &",
                    "sleep 2",
                    "chmod 666 /srv/appuserfiles",
                    "mkdir /tmp/appmnt1", "mkdir /tmp/appmnt2",
                    "mount /srv/appuserfiles /tmp/appmnt1",
                    "mount /srv/appuserfiles /tmp/appmnt2",
                    "cat /tmp/appmnt1/clone",
                    "cat /tmp/appmnt2/0/challenge.tab >[2=1]",
                    "/tmp/vm_appuser_split -deny /tmp/appmnt1/0/ctl",
                    "echo auth alice >/tmp/appmnt1/0/ctl",
                    "cat /tmp/appmnt1/0/challenge.tab",
                    "/tmp/o9appfiles-client client $n $e /tmp/appmnt1/0/challenge.tab",
                    "/tmp/vm_appuser_split /tmp/appuser-files-answer.tab /tmp/appmnt1/0/response.tab",
                    "cat /tmp/appmnt1/0/status.tab",
                    "/tmp/o9appfiles-status status /tmp/appmnt1/0/status.tab",
                    "cat /tmp/appmnt1/0/view/caller",
                    "cat /tmp/appmnt1/0/view/identity",
                    "cat /tmp/appmnt2/0/view/caller >[2=1]",
                ):
                    guest(command, 300 if "mk libo9" in command else 180)
                transcript = logpath.read_text(errors="replace")
                if ("RESPONSE READY" not in transcript or
                    "SPLIT RESPONSE PASS" not in transcript or
                    "REPLAY DENIED" not in transcript):
                    raise AssertionError("client did not produce a signed response")
                if "state=verified" not in transcript or "principal=alice" not in transcript:
                    raise AssertionError("server did not verify response.tab")
                if "AUTH STATUS appuser_status_v1 verified alice" not in transcript:
                    raise AssertionError("status.tab is not readable as a tabula")
                if "PREAUTH CTL DENIED" not in transcript:
                    raise AssertionError("unauthenticated ctl command was accepted")
                if "cat: can't open /tmp/appmnt2/0/challenge.tab: permission denied" not in transcript:
                    raise AssertionError("second attach could read the challenge")
                if not re.search(r"term% cat /tmp/appmnt1/0/view/caller.*?\nalice", transcript, re.S):
                    raise AssertionError("private view did not receive Alice principal")
                if not re.search(r"term% cat /tmp/appmnt1/0/view/identity.*?\nalice", transcript, re.S):
                    raise AssertionError("view controller did not inherit verified caller")
                if not re.search(r"term% cat /tmp/appmnt2/0/view/caller.*?permission denied", transcript, re.S | re.I):
                    raise AssertionError("second attach could access Alice's view")
                print("APPUSER SESSION FILES VM PASS: signed .tab exchange and private view")
            except Exception:
                log.flush()
                print(logpath.read_text(errors="replace")[-18000:])
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
