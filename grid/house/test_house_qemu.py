#!/usr/bin/env python3
"""Run the mutation house and an authenticated 9P view on disposable 9front."""

import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"
RUNTIME = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
           "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
           "monocypher.c", "monocypher.h", "o9_dispatch_386.s")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_house_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix="o9house-qemu-") as tmp:
        work = Path(tmp)
        for kind in ("server", "client", "test_house", "inspect"):
            subprocess.run([str(ROOT / "grid/house/build.sh"), kind,
                            str(work / f"{kind}.c")], cwd=ROOT, check=True)
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        (work / "plan9.ini").write_text(builder.BUILD_PLAN9INI)
        (work / "jobs.tsv").write_text("m1\tsuite/test.o9\tmut-1\n")
        (work / "result.tab").write_text(
            "schema=mutation_result_v1\n\tcol=task_id\n\tcol=attempt\n"
            "\tcol=outcome\n\ntask_id=m1\n\tattempt=1\n\toutcome=killed\n")
        (work / "renew.tab").write_text(
            "schema=mutation_renew_v1\n\tcol=task_id\n\tcol=attempt\n\n"
            "task_id=m1\n\tattempt=1\n")
        subprocess.run(["mcopy", "-o", "-i", fat, str(work / "plan9.ini"), "::plan9.ini"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9house"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9lib"], check=True)
        sources = [(f"{kind}.c", work / f"{kind}.c")
                   for kind in ("server", "client", "test_house", "inspect")]
        sources.extend((name, ROOT / name) for name in RUNTIME)
        for name, path in sources:
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9house/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.[ch]"):
            subprocess.run(["mcopy", "-i", fat, str(path), f"::o9lib/{path.name}"], check=True)
        for name in ("jobs.tsv", "result.tab", "renew.tab"):
            subprocess.run(["mcopy", "-i", fat, str(work / name), f"::{name}"], check=True)

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

            def guest(command, timeout=90):
                nonlocal serial
                marker = f"O9END{serial:04d}"
                serial += 1
                console.send(command)
                if console.expect(["term% "], timeout) is None:
                    raise RuntimeError(f"guest command timed out: {command}")
                console.send("echo " + marker)
                if console.expect([marker + "\r\nterm% ", marker + "\nterm% "], timeout) is None:
                    raise RuntimeError(f"guest command timed out: {command}")

            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")
                commands = (
                    "9fs 9fat", "ramfs", "mkdir /tmp/o9house", "mkdir /tmp/o9house/libtab",
                    "cp /n/9fat/o9house/* /tmp/o9house",
                    "cp /n/9fat/o9lib/* /tmp/o9house/libtab",
                    "bind -b /usr/glenda/bin/386 /bin",
                    "cd /tmp/o9house; mk libo9.a",
                    *("8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9house -o /tmp/o9house/" + k + ".8 /tmp/o9house/" + k + ".c"
                      for k in ("server", "client", "test_house", "inspect")),
                    *("8l -o /tmp/house-" + k + " /tmp/o9house/" + k + ".8 /tmp/o9house/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a"
                      for k in ("server", "client", "test_house", "inspect")),
                    "/tmp/house-test_house housetest /tmp/house-ledger",
                    "auth/rsagen -b 2048 -t 'service=appuser app=o9mut hash=sha256' >/tmp/house-key",
                    "cat /tmp/house-key >/mnt/factotum/ctl",
                    "n=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/house-key}",
                    "e=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/house-key}",
                    "echo machine-a^'\t'^$n^'\t'^$e >/tmp/machines.tsv",
                    "cp /n/9fat/jobs.tsv /tmp/jobs.tsv",
                    "/tmp/house-server house /tmp/house-journal /tmp/machines.tsv /tmp/jobs.tsv </dev/null >/tmp/house.log >[2=1] &",
                    "sleep 2", "cat /tmp/house.log",
                    "cat /tmp/house-journal", "chmod 666 /srv/house", "mkdir /tmp/housemnt",
                    "mount /srv/house /tmp/housemnt", "cat /tmp/housemnt/clone",
                    "echo auth machine-a >/tmp/housemnt/0/ctl",
                    "cat /tmp/housemnt/0/challenge.tab",
                    "/tmp/house-client houseclient machine-a $n $e /tmp/housemnt/0/challenge.tab /tmp/house-response.tab",
                    "cat /tmp/house-response.tab >/tmp/housemnt/0/response.tab",
                    "cat /tmp/housemnt/0/status.tab",
                    "cat /tmp/housemnt/0/view/machine",
                    "echo 1 >/tmp/housemnt/0/view/ready",
                    "cat /tmp/housemnt/0/view/assigned.tab",
                    "/tmp/house-inspect houseinspect /tmp/housemnt/0/view/assigned.tab",
                    "sleep 2",
                    "cp /n/9fat/renew.tab /tmp/house-renew.tab",
                    "cat /tmp/house-renew.tab >/tmp/housemnt/0/view/renew.tab",
                    "cp /n/9fat/result.tab /tmp/house-result.tab",
                    "cat /tmp/house-result.tab >/tmp/housemnt/0/view/result.tab",
                    "cat /tmp/housemnt/0/view/assigned.tab",
                    "cat /tmp/house-journal",
                    "cat /tmp/housemnt/clone",
                    "cat /tmp/housemnt/1/view/machine >[2=1]",
                )
                for command in commands:
                    guest(command, 300 if "mk libo9" in command else 180)
                    if command.startswith("/tmp/house-test_house") and "HOUSE LEDGER FAIL" in logpath.read_text(errors="replace"):
                        raise AssertionError("native ledger scenario failed")
                    if command == "cat /tmp/house.log" and "invalid machine key or job manifest" in logpath.read_text(errors="replace"):
                        raise AssertionError("house server rejected manifest")
                transcript = logpath.read_text(errors="replace")
                for expected in ("HOUSE LEDGER PASS", "HOUSE CLIENT SIGNED",
                                 "state=verified", "principal=machine-a",
                                 "schema=mutation_assignment_v1", "task_id=m1",
                                 "HOUSE ASSIGNMENT TABULA PASS",
                                 "H\tm1\tmachine-a\t1\t",
                                 "R\tm1\tmachine-a\t1\tkilled",
                                 "file does not exist: '/tmp/housemnt/1/view'"):
                    if expected not in transcript:
                        raise AssertionError(f"missing {expected!r}")
                if "house: invalid machine key" in transcript:
                    raise AssertionError("server rejected machine manifest")
                print("HOUSE VM PASS: durable ledger and AppUser-gated 9P work view")
            except Exception:
                log.flush()
                print(logpath.read_text(errors="replace")[-7000:])
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
