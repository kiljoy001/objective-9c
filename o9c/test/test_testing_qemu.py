#!/usr/bin/env python3
"""Run the Objective-9C testing library in a disposable 9front VM."""

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
        raise SystemExit("usage: test_testing_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with tempfile.TemporaryDirectory(prefix="o9testing-qemu-") as tmp:
        work = Path(tmp)
        for kind, source in (("ok", "e2e_testing.o9"),
                             ("fail", "e2e_testing_fail.o9"),
                             ("prop_ok", "e2e_property.o9"),
                             ("prop_fail", "e2e_property_fail.o9")):
            with (work / f"t_{kind}.c").open("w") as output:
                subprocess.run([str(ROOT / "o9c/o9c"), f"stdlib/{source}"],
                               cwd=ROOT, stdout=output, check=True)
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        (work / "plan9.ini").write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat,
                        str(work / "plan9.ini"), "::plan9.ini"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9test"], check=True)
        subprocess.run(["mmd", "-i", fat, "::o9tlib"], check=True)
        runtime = ("mkfile", "o9.h", "o9_runtime.c", "o9_filetree.c",
                   "o9_view.c", "o9_tab_discard.c", "o9_crypto.c",
                   "monocypher.c", "monocypher.h", "o9_dispatch_386.s")
        for name, path in (("t_ok.c", work / "t_ok.c"),
                           ("t_fail.c", work / "t_fail.c"),
                           ("t_prop_ok.c", work / "t_prop_ok.c"),
                           ("t_prop_fail.c", work / "t_prop_fail.c"),
                           *((name, ROOT / name) for name in runtime)):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9test/{name}"], check=True)
        for path in (ROOT / "libtab").glob("*.c"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9tlib/{path.name}"], check=True)
        for path in (ROOT / "libtab").glob("*.h"):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9tlib/{path.name}"], check=True)

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

            def guest(command, timeout=120):
                nonlocal serial
                marker = f"O9END{serial:04d}"
                result = f"O9RESULT{serial:04d}"
                serial += 1
                start = logpath.stat().st_size
                proc.stdin.write((command + "; echo " + result +
                                  " $status; echo " + marker + "\n").encode())
                proc.stdin.flush()
                if console.expect([marker + "\r\nterm% ",
                                   marker + "\nterm% "], timeout) is None:
                    raise RuntimeError(f"guest command timed out: {command}")
                output = logpath.read_text(errors="replace")[start:].replace("\r", "")
                if re.search(rf"\n{result}[ \t]*\n", output) is None:
                    raise RuntimeError(f"guest command failed: {command}\n{output[-1500:]}")

            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")
                for command in (
                    "9fs 9fat", "ramfs", "mkdir /tmp/o9test",
                    "mkdir /tmp/o9test/libtab",
                    "cp /n/9fat/o9test/* /tmp/o9test",
                    "cp /n/9fat/o9tlib/* /tmp/o9test/libtab",
                    "bind -b /usr/glenda/bin/386 /bin",
                    "cd /tmp/o9test; mk libo9.a",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9test -o /tmp/o9test/t_ok.8 /tmp/o9test/t_ok.c",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9test -o /tmp/o9test/t_fail.8 /tmp/o9test/t_fail.c",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9test -o /tmp/o9test/t_prop_ok.8 /tmp/o9test/t_prop_ok.c",
                    "8c -FV -DO9_HAVE_SRVRELEASE -I/tmp/o9test -o /tmp/o9test/t_prop_fail.8 /tmp/o9test/t_prop_fail.c",
                    "8l -o /tmp/o9-testing-ok /tmp/o9test/t_ok.8 /tmp/o9test/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "8l -o /tmp/o9-testing-fail /tmp/o9test/t_fail.8 /tmp/o9test/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "8l -o /tmp/o9-property-ok /tmp/o9test/t_prop_ok.8 /tmp/o9test/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "8l -o /tmp/o9-property-fail /tmp/o9test/t_prop_fail.8 /tmp/o9test/libo9.a /386/lib/libndb.a /386/lib/libauth.a /386/lib/libmp.a /386/lib/libsec.a",
                    "if(/tmp/o9-testing-ok) echo TEST_SUCCESS_EXIT_OK",
                    "if(! /tmp/o9-testing-fail) echo TEST_FAILURE_EXIT_OK",
                    "if(/tmp/o9-property-ok) echo PROPERTY_SUCCESS_EXIT_OK",
                    "if(! /tmp/o9-property-fail) echo PROPERTY_FAILURE_EXIT_OK",
                    "O9TEST_SEED=123; O9TEST_TRIALS=7; if(! /tmp/o9-property-fail) echo PROPERTY_REPLAY_EXIT_OK",
                ):
                    guest(command, 300 if "mk libo9" in command else 180)
                transcript = logpath.read_text(errors="replace").replace("\r", "")
                expected = (ROOT / "stdlib/e2e_testing.expected").read_text()
                if expected not in transcript:
                    raise AssertionError("testing selftest output differs from expected")
                if "UNEXPECTED_CHILD_OUTPUT" in transcript:
                    raise AssertionError("isolated child output leaked into test output")
                if "\nTEST_SUCCESS_EXIT_OK\n" not in transcript:
                    raise AssertionError("passing test process did not exit cleanly")
                if ("FAIL expected_failure/deliberate mismatch: got 1 want 2" not in transcript or
                    "expected_failure: 0 passed, 1 failed, 0 skipped" not in transcript or
                    "\nTEST_FAILURE_EXIT_OK\n" not in transcript or
                    "ERROR: finish returned" in transcript):
                    raise AssertionError("failing test process did not exit with failure")
                if ("property_pass: 1 passed, 0 failed" not in transcript or
                    "property_basics: 200 passed, 0 failed" not in transcript or
                    "\nPROPERTY_SUCCESS_EXIT_OK\n" not in transcript or
                    "seed=9009 trial=0" not in transcript or
                    "shrunk=11" not in transcript or
                    "shrunk=-11" not in transcript or
                    "property_fail: 0 passed, 2 failed" not in transcript or
                    "\nPROPERTY_FAILURE_EXIT_OK\n" not in transcript or
                    "seed=123 trial=0" not in transcript or
                    "\nPROPERTY_REPLAY_EXIT_OK\n" not in transcript):
                    raise AssertionError("native property tests did not shrink or report correctly")
                print("O9 TESTING VM PASS: assertions, TAP, fixtures, isolation, property generation, shrinking, and failure exit")
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
