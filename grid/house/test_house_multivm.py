#!/usr/bin/env python3
"""Exercise an AppUser mutation house and worker in separate disposable 9front VMs."""

import importlib.util
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"
RUNTIME = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
           "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
           "monocypher.c", "monocypher.h", "o9_dispatch_386.s")


class VM:
    def __init__(self, builder, disk, logpath, netdev):
        self.logpath = logpath
        self.log = logpath.open("w")
        self.serial = 0
        qemu = ["qemu-system-i386", "-m", "1024", "-display", "none",
                "-monitor", "none", "-serial", "stdio", "-no-reboot",
                "-netdev", f"socket,id=n0,{netdev}" if netdev else "user,id=n0",
                "-device", "ne2k_pci,netdev=n0",
                "-drive", f"file={disk},format=raw,if=ide,index=0"]
        if os.access("/dev/kvm", os.R_OK | os.W_OK):
            qemu.insert(1, "-enable-kvm")
        self.proc = subprocess.Popen(qemu, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.console = builder.Console(self.proc, self.log)

    def boot(self):
        if self.console.expect(["term% "], 180) is None:
            raise RuntimeError(f"9front prompt unavailable: {self.logpath}")

    def run(self, command, timeout=90, want=None):
        marker = f"O9MULTI{self.serial:04d}"
        self.serial += 1
        self.log.flush()
        start = self.logpath.stat().st_size
        self.console.send(command + "; echo " + marker)
        if self.console.expect([marker + "\r\nterm% ", marker + "\nterm% "], timeout) is None:
            raise RuntimeError(f"guest command timed out: {command}")
        self.log.flush()
        output = self.logpath.read_bytes()[start:].decode(errors="replace")
        if want is not None and want not in output:
            raise AssertionError(f"missing {want!r} after {command}: {output[-2000:]}")
        return output

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.log.close()


def sparse_copy(source, dest):
    subprocess.run(["cp", "--sparse=always", str(source), str(dest)], check=True)


def stage(builder, work, disk):
    for kind in ("server", "worker"):
        subprocess.run([str(ROOT / "grid/house/build.sh"), kind,
                        str(work / f"{kind}.c")], cwd=ROOT, check=True)
    fat = f"{disk}@@{builder.ninefat_offset(disk)}"
    (work / "plan9.ini").write_text(builder.BUILD_PLAN9INI)
    (work / "jobs.tsv").write_text("m1\tsuite/test.o9\t/tmp/mutant.o9\n")
    (work / "gate.rc").write_text(
        "#!/bin/rc\n"
        "echo remote-gate: $O9MUT_SOURCE $O9MUT_MUTANT\n"
        "sleep 3\n"
        "exit failed\n")
    subprocess.run(["mcopy", "-o", "-i", fat, str(work / "plan9.ini"),
                    "::plan9.ini"], check=True)
    subprocess.run(["mmd", "-i", fat, "::o9house"], check=True)
    subprocess.run(["mmd", "-i", fat, "::o9lib"], check=True)
    for name, path in ((f"{kind}.c", work / f"{kind}.c") for kind in ("server", "worker")):
        subprocess.run(["mcopy", "-i", fat, str(path), f"::o9house/{name}"], check=True)
    for name in RUNTIME:
        subprocess.run(["mcopy", "-i", fat, str(ROOT / name),
                        f"::o9house/{name}"], check=True)
    for path in (ROOT / "libtab").glob("*.[ch]"):
        subprocess.run(["mcopy", "-i", fat, str(path),
                        f"::o9lib/{path.name}"], check=True)
    for name in ("jobs.tsv", "gate.rc"):
        subprocess.run(["mcopy", "-i", fat, str(work / name), f"::{name}"], check=True)


def prepare(builder, work, disk):
    vm = VM(builder, disk, work / "prep.log", None)
    try:
        vm.boot()
        for command in (
            "9fs 9fat", "ramfs", "mkdir /tmp/o9house", "mkdir /tmp/o9house/libtab",
            "cp /n/9fat/o9house/* /tmp/o9house",
            "cp /n/9fat/o9lib/* /tmp/o9house/libtab",
            "bind -b /usr/glenda/bin/386 /bin",
        ):
            vm.run(command)
        vm.run("cd /tmp/o9house; mk libo9.a", 300, "ar r libo9.a")
        for kind in ("server", "worker"):
            vm.run(f"8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9house "
                   f"-o /tmp/o9house/{kind}.8 /tmp/o9house/{kind}.c", 120)
            vm.run(f"8l -o /tmp/house-{kind} /tmp/o9house/{kind}.8 "
                   "/tmp/o9house/libo9.a /386/lib/libndb.a /386/lib/libauth.a "
                   "/386/lib/libmp.a /386/lib/libsec.a", 120)
            vm.run(f"ls /tmp/house-{kind}", want=f"/tmp/house-{kind}")
            vm.run(f"cp /tmp/house-{kind} /n/9fat/o9house/house-{kind}")
        vm.run("auth/rsagen -b 2048 -t 'service=appuser app=o9mut hash=sha256' "
               ">/n/9fat/o9house/key", 120)
        vm.run("ls /n/9fat/o9house/key", want="/n/9fat/o9house/key")
    finally:
        vm.stop()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_house_multivm.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix="o9house-multivm-") as tmp:
        work = Path(tmp)
        prepared = work / "prepared.img"
        sparse_copy(Path(sys.argv[1]), prepared)
        stage(builder, work, prepared)
        prepare(builder, work, prepared)
        server_disk = work / "server.img"
        worker_disk = work / "worker.img"
        sparse_copy(prepared, server_disk)
        sparse_copy(prepared, worker_disk)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        server = VM(builder, server_disk, work / "server.log", f"listen=127.0.0.1:{port}")
        worker = None
        try:
            server.boot()
            worker = VM(builder, worker_disk, work / "worker.log",
                        f"connect=127.0.0.1:{port}")
            worker.boot()
            for vm, addr in ((server, "10.44.1.1"), (worker, "10.44.1.2")):
                vm.run("9fs 9fat")
                vm.run("ramfs")
                vm.run("bind -b /usr/glenda/bin/386 /bin")
                vm.run(f"ip/ipconfig ether /net/ether0 {addr} 255.255.255.0")
            worker.run("ip/ping -n 2 10.44.1.1", 30, "ttl")
            print("HOUSE MULTIVM: isolated 9front link ready", flush=True)

            for command in (
                "cp /n/9fat/o9house/house-server /tmp/house-server",
                "chmod +x /tmp/house-server",
                "cp /n/9fat/o9house/key /tmp/house-key",
                "n=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/house-key}",
                "e=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/house-key}",
                "echo machine-a^'\t'^$n^'\t'^$e >/tmp/machines.tsv",
                "cp /n/9fat/jobs.tsv /tmp/jobs.tsv",
                "/tmp/house-server house /tmp/house-journal /tmp/machines.tsv /tmp/jobs.tsv "
                "</dev/null >/tmp/house.log >[2=1] &",
                "sleep 2",
            ):
                server.run(command)
            server.run("cat /tmp/house.log", want="house: serving authenticated machine views")
            server.run("chmod 666 /srv/house")
            server.run("mkdir /tmp/housemnt")
            server.run("mount /srv/house /tmp/housemnt")
            server.run("aux/listen1 -t tcp!*!17008 /bin/exportfs -r /tmp/housemnt "
                       "</dev/null >/tmp/listen.log >[2=1] &")

            for command in (
                "cp /n/9fat/o9house/house-worker /tmp/house-worker",
                "chmod +x /tmp/house-worker",
                "cp /n/9fat/o9house/key /tmp/house-key",
                "cat /tmp/house-key >/mnt/factotum/ctl",
                "n=`{awk '{for(i=1;i<=NF;i++)if($i~/^n=/){sub(/^n=/,\"\",$i);print $i}}' /tmp/house-key}",
                "e=`{awk '{for(i=1;i<=NF;i++)if($i~/^ek=/){sub(/^ek=/,\"\",$i);print $i}}' /tmp/house-key}",
                "cp /n/9fat/gate.rc /tmp/house-gate.rc",
                "mkdir /tmp/housemnt",
            ):
                worker.run(command)
            worker.run("srv -m tcp!10.44.1.1!17008 house /tmp/housemnt", 90)
            worker.run("cat /tmp/housemnt/clone", 30, "0")
            worker.run("/tmp/house-worker houseworker /tmp/housemnt machine-a $n $e "
                       "'rc /tmp/house-gate.rc' /tmp/house-local 10000 1 100 1000",
                       90, "HOUSE WORKER RESULT m1 killed attempt 1")
            worker.run("cat /tmp/house-local/m1.1.*.*/logs/m1.machine-a.log", 30,
                       "remote-gate: suite/test.o9 /tmp/mutant.o9")
            journal = server.run("cat /tmp/house-journal")
            for event in ("L\tm1\tmachine-a\t1\t", "H\tm1\tmachine-a\t1\t",
                          "R\tm1\tmachine-a\t1\tkilled"):
                if event not in journal:
                    raise AssertionError(f"server journal missing {event!r}: {journal}")
            print("HOUSE MULTIVM PASS: remote 9P claim, renewal, gate, and result", flush=True)
        except Exception:
            for path in (work / "prep.log", work / "server.log", work / "worker.log"):
                if path.exists():
                    print(f"{path.name}:\n{path.read_text(errors='replace')[-5000:]}")
            raise
        finally:
            if worker is not None:
                worker.stop()
            server.stop()


if __name__ == "__main__":
    main()
