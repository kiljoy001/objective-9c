#!/usr/bin/env python3
"""Exercise the native o9test command in a disposable 9front VM."""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT.parent / "halatha/extras/9front/kernel/build-kernel.py"
FIXTURES = {
    "pass": 'print("fixture pass\\n"); exits(nil);',
    "fail": 'fprint(2, "fixture failed\\n"); exits("fixture failure");',
    "timeout": 'sleep(5000); exits(nil);',
    "env": 'char *seed, *trials; seed = getenv("O9TEST_SEED"); '
           'trials = getenv("O9TEST_TRIALS"); '
           'if(seed == nil && trials == nil) exits(nil); '
           'if(seed == nil || trials == nil || strcmp(seed, "123") != 0 '
           '|| strcmp(trials, "7") != 0) exits("property config"); '
           'free(seed); free(trials); exits(nil);',
}


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_o9test_runner_qemu.py /path/to/9front.img")
    spec = importlib.util.spec_from_file_location("builder", BUILDER)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with tempfile.TemporaryDirectory(prefix="o9runner-qemu-") as tmp:
        work = Path(tmp)
        disk = work / "test.img"
        subprocess.run(["cp", "--sparse=always", sys.argv[1], disk], check=True)
        fat = f"{disk}@@{builder.ninefat_offset(disk)}"
        (work / "plan9.ini").write_text(builder.BUILD_PLAN9INI)
        subprocess.run(["mcopy", "-o", "-i", fat,
                        str(work / "plan9.ini"), "::plan9.ini"], check=True)
        for directory in ("::o9runner", "::o9runner/tests", "::o9runner/tests/sub"):
            subprocess.run(["mmd", "-i", fat, directory], check=True)
        for name, path in (("o9test.c", ROOT / "o9test.c"),
                           ("o9proj", ROOT / "o9proj"),
                           ("mockbuild.rc", ROOT / "o9c/test/o9test_mock_build.rc")):
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9runner/{name}"], check=True)
        for name in ("test_pass.o9", "test_fail.o9", "test_build.o9", "test_env.o9",
                     "test_timeout.o9", "ordinary.o9"):
            path = work / name
            path.write_text("// runner discovery fixture\n")
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9runner/tests/{name}"], check=True)
        nested = work / "check_test.o9"
        nested.write_text("// nested runner discovery fixture\n")
        subprocess.run(["mcopy", "-i", fat, str(nested),
                        "::o9runner/tests/sub/check_test.o9"], check=True)
        for name, body in FIXTURES.items():
            path = work / f"fixture_{name}.c"
            path.write_text("#include <u.h>\n#include <libc.h>\n"
                            f"void main(void){{ {body} }}\n")
            subprocess.run(["mcopy", "-i", fat, str(path),
                            f"::o9runner/{path.name}"], check=True)

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

            def guest(command, success=True, timeout=120):
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
                full = logpath.read_text(errors="replace").replace("\r", "")
                matches = re.findall(rf"(?m)^{result}([^\n]*)$", full)
                command_start = full.rfind("term% " + command)
                output = full[command_start:] if command_start >= 0 else full[start:]
                if not matches or (matches[-1].strip() == "") != success:
                    raise AssertionError(f"wrong guest exit status: {command}\n{output[-2500:]}")
                return output

            try:
                if console.expect(["term% "], 180) is None:
                    raise RuntimeError("9front prompt unavailable")
                for command in (
                    "9fs 9fat", "ramfs", "mkdir /tmp/o9runner",
                    "mkdir /tmp/o9runner/tests", "mkdir /tmp/o9runner/tests/sub",
                    "cp /n/9fat/o9runner/*.c /tmp/o9runner",
                    "cp /n/9fat/o9runner/*.rc /tmp/o9runner",
                    "cp /n/9fat/o9runner/o9proj /tmp/o9runner",
                    "cp /n/9fat/o9runner/tests/*.o9 /tmp/o9runner/tests",
                    "cp /n/9fat/o9runner/tests/sub/* /tmp/o9runner/tests/sub",
                    "bind -b /usr/glenda/bin/386 /bin",
                    "8c -o /tmp/o9test.8 /tmp/o9runner/o9test.c",
                    "8l -o /tmp/o9test /tmp/o9test.8",
                    "cp /tmp/o9runner/mockbuild.rc /tmp/mockbuild.rc",
                    "8c -o /tmp/fixture_pass.8 /tmp/o9runner/fixture_pass.c",
                    "8l -o /tmp/o9fixture_pass /tmp/fixture_pass.8",
                    "8c -o /tmp/fixture_fail.8 /tmp/o9runner/fixture_fail.c",
                    "8l -o /tmp/o9fixture_fail /tmp/fixture_fail.8",
                    "8c -o /tmp/fixture_timeout.8 /tmp/o9runner/fixture_timeout.c",
                    "8l -o /tmp/o9fixture_timeout /tmp/fixture_timeout.8",
                    "8c -o /tmp/fixture_env.8 /tmp/o9runner/fixture_env.c",
                    "8l -o /tmp/o9fixture_env /tmp/fixture_env.8",
                    "rc /tmp/o9runner/o9proj /tmp/runnerapp",
                ):
                    guest(command)
                scaffold = guest("/tmp/o9test --list /tmp/runnerapp/tests")
                if "/tmp/runnerapp/tests/test_app.o9\n" not in scaffold:
                    raise AssertionError(f"project scaffold has no discoverable test:\n{scaffold}")
                default_listing = guest("cd /tmp/runnerapp; /tmp/o9test --list")
                if "tests/test_app.o9\n" not in default_listing:
                    raise AssertionError(f"default discovery missed scaffold test:\n{default_listing}")
                scaffold_run = guest("/tmp/o9test --builder /tmp/mockbuild.rc /tmp/runnerapp/tests")
                if "1 passed" not in scaffold_run:
                    raise AssertionError(f"project scaffold test did not run:\n{scaffold_run}")
                listing = guest("/tmp/o9test --list /tmp/o9runner/tests")
                if (listing.count(".o9\n") != 6 or
                    "ordinary.o9\n" in listing):
                    raise AssertionError(f"discovery mismatch:\n{listing}")
                explicit = guest("/tmp/o9test --list /tmp/o9runner/tests/ordinary.o9")
                if "/tmp/o9runner/tests/ordinary.o9\n" not in explicit:
                    raise AssertionError(f"explicit file was not selected:\n{explicit}")
                filtered = guest("/tmp/o9test /tmp/o9runner/tests -k pass --builder /tmp/mockbuild.rc -v")
                if "PASS /tmp/o9runner/tests/test_pass.o9" not in filtered or "1 passed" not in filtered:
                    raise AssertionError(f"filter/run mismatch:\n{filtered}")
                configured = guest("/tmp/o9test --seed 123 --trials 7 --builder /tmp/mockbuild.rc /tmp/o9runner/tests/test_env.o9")
                if "1 passed" not in configured:
                    raise AssertionError(f"property configuration was not forwarded:\n{configured}")
                stopped = guest("/tmp/o9test -x --builder /tmp/mockbuild.rc /tmp/o9runner/tests",
                                success=False)
                if "1 passed" not in stopped or "4 not run" not in stopped:
                    raise AssertionError(f"fail fast did not stop:\n{stopped}")
                all_tests = guest("/tmp/o9test -t 1 --builder /tmp/mockbuild.rc /tmp/o9runner/tests",
                                  success=False, timeout=90)
                for expected in ("1 failed", "1 build errors", "1 timed out",
                                 "3 passed", "fixture failed", "deliberate build failure"):
                    if expected not in all_tests:
                        raise AssertionError(f"missing {expected}:\n{all_tests}")
                print("O9 TEST RUNNER VM PASS: discovery, filtering, build, failure, timeout")
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
