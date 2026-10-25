#!/bin/sh
# Host-side test gate for o9c.
#
# Builds the parts of the runtime that do not depend on 9front's lib9p File
# layout, then runs:
#   - host_runtime_test: strings, arrays, slices, dicts, channels, FileTree,
#     vault open_tab
#   - stdlib/e2e_draw*.o9: widget, layout, event, text, table, and snapshot
#     UI cases through o9c --no-facade and host_ui_main
#   - o9c_check.py: positive/negative compiler fixtures plus a fuzz pass
#
# This is intentionally separate from `mk verify`: the native suite still
# owns generated Plan 9 C, the 9P facade, auth, and 9vm/hardware integration.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PLAN9_LIB=${PLAN9:-/usr/local/plan9}/lib
BUILD=${O9_HOST_BUILD:-$(mktemp -d "${TMPDIR:-/tmp}/o9-host.XXXXXX")}
mkdir -p "$BUILD"
rm -f "$BUILD"/*.o "$BUILD"/*.a

cleanup() {
	st=$?
	if [ "$st" -eq 0 ] && [ -z "${O9_HOST_BUILD:-}" ]; then
		rm -rf "$BUILD"
	else
		echo "host-test: artifacts kept in $BUILD" >&2
	fi
}
trap cleanup EXIT HUP INT TERM

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "host-test: missing $1" >&2
		exit 1
	fi
}

need 9c
need 9l
need 9ar
need python3
need yacc

if [ ! -d "$ROOT/libtab" ]; then
	echo "host-test: libtab submodule missing; run git submodule update --init" >&2
	exit 1
fi

CC=9c
LD=9l
AR=9ar
HOST_COMPAT="$ROOT/o9c/test/host_compat.h"
CC="9c -include $HOST_COMPAT"
FUZZ_ITER=${O9_FUZZ_ITER:-100}

if [ "${O9_SANITIZE:-0}" = 1 ] && [ "${O9_TSAN:-0}" = 1 ]; then
	echo "host-test: O9_SANITIZE and O9_TSAN are mutually exclusive" >&2
	exit 1
fi

if [ "${O9_SANITIZE:-0}" = 1 ]; then
	if [ -z "${CC9:-}" ]; then
		for cand in clang-20 clang-18 clang-17 clang-14 clang; do
			if ! command -v "$cand" >/dev/null 2>&1; then
				continue
			fi
			rt=$("$cand" -print-file-name=libclang_rt.asan-x86_64.a 2>/dev/null || true)
			if [ -n "$rt" ] && [ -f "$rt" ]; then
				CC9=$cand
				export CC9
				break
			fi
		done
	fi
	CC9FLAGS="${CC9FLAGS:-} -fsanitize=address,undefined -fno-omit-frame-pointer -Wno-unknown-warning-option -Wno-unused-function -g"
	export CC9FLAGS
	ASAN_OPTIONS=detect_leaks=0
	UBSAN_OPTIONS=halt_on_error=1
	export ASAN_OPTIONS UBSAN_OPTIONS
fi

if [ "${O9_TSAN:-0}" = 1 ]; then
	if [ -z "${CC9:-}" ]; then
		for cand in clang-20 clang-18 clang-17 clang-14 clang; do
			if ! command -v "$cand" >/dev/null 2>&1; then
				continue
			fi
			rt=$("$cand" -print-file-name=libclang_rt.tsan-x86_64.a 2>/dev/null || true)
			if [ -n "$rt" ] && [ -f "$rt" ]; then
				CC9=$cand
				export CC9
				break
			fi
		done
	fi
	CC9FLAGS="${CC9FLAGS:-} -fsanitize=thread -Wno-unknown-warning-option -Wno-unused-function -g"
	export CC9FLAGS
	TSAN_OPTIONS=halt_on_error=1
	if [ -f "$ROOT/o9c/test/tsan.supp" ]; then
		TSAN_OPTIONS="$TSAN_OPTIONS suppressions=$ROOT/o9c/test/tsan.supp"
	fi
	export TSAN_OPTIONS
fi

if [ "${O9_COVERAGE:-0}" = 1 ]; then
	COV_CC=""
	for cand in clang-20 clang-18 clang-17 clang-14 clang; do
		if ! command -v "$cand" >/dev/null 2>&1; then
			continue
		fi
		rt=$("$cand" -print-file-name=libclang_rt.profile-x86_64.a 2>/dev/null || true)
		if [ -n "$rt" ] && [ -f "$rt" ]; then
			COV_CC=$cand
			break
		fi
	done
	if [ -z "$COV_CC" ]; then
		echo "host-test: O9_COVERAGE=1 needs a clang with libclang_rt.profile" >&2
		exit 1
	fi
	COV_SUFFIX=${COV_CC#clang}
	if [ "$COV_SUFFIX" = "$COV_CC" ]; then
		COV_SUFFIX=
	fi
	CC9=$COV_CC
	export CC9
	CC9FLAGS="${CC9FLAGS:-} -fprofile-instr-generate -fcoverage-mapping -DO9_PROFILE"
	export CC9FLAGS
	LLVM_PROFILE_FILE="$BUILD/coverage-%p.profraw"
	export LLVM_PROFILE_FILE
	rm -f "$BUILD"/coverage-*.profraw
	LLVM_PROFDATA="llvm-profdata$COV_SUFFIX"
	LLVM_COV="llvm-cov$COV_SUFFIX"
	for tool in "$LLVM_PROFDATA" "$LLVM_COV"; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "host-test: O9_COVERAGE=1 needs $tool" >&2
			exit 1
		fi
	done
fi

# o9_crypto.c hardcodes MONO_PLAN9; compile a copy next to libtab's header so
# plan9port's stdint definitions win (the 9front build uses the root header).
cp "$ROOT/o9_crypto.c" "$BUILD/o9_crypto.c"

echo "host-test: compiling runtime"
$CC -I"$ROOT" -I"$ROOT/libtab" -o "$BUILD/o9_runtime.o" "$ROOT/o9_runtime.c"
$CC -I"$ROOT" -o "$BUILD/o9_filetree.o" "$ROOT/o9_filetree.c"
$CC -I"$ROOT" -o "$BUILD/o9_dispatch.o" "$ROOT/o9_dispatch.c"
$CC -I"$ROOT" -I"$ROOT/libtab" -o "$BUILD/o9_tab_discard.o" "$ROOT/o9_tab_discard.c"
$CC -D_STDINT_PLAN9_H -I"$ROOT" -I"$ROOT/libtab" -o "$BUILD/o9_crypto.o" "$BUILD/o9_crypto.c"
$CC -D_STDINT_PLAN9_H -DMONO_PLAN9 -I"$ROOT/libtab" -o "$BUILD/monocypher.o" "$ROOT/libtab/monocypher.c"
$CC -I"$ROOT" -I"$ROOT/libtab" -o "$BUILD/host_stubs.o" "$ROOT/o9c/test/host_stubs.c"

echo "host-test: compiling libtab"
for f in tab_error tab_create tab_row tab_rowmap tab_iter tab_codec \
	tab_open tab_serialize tab_persist tab_emit tab_text; do
	$CC -DUSE_POSIX -I"$ROOT/libtab" -o "$BUILD/libtab_$f.o" "$ROOT/libtab/$f.c"
done
$CC -I"$ROOT/libtab" -D_STDINT_PLAN9_H -DMONO_PLAN9 \
	-o "$BUILD/libtab_tab_writer.o" "$ROOT/libtab/tab_writer.c"

$AR rcs "$BUILD/libo9host.a" \
	"$BUILD"/*.o

echo "host-test: running runtime edge tests"
$CC -I"$ROOT" -I"$ROOT/o9c/test" -o "$BUILD/o9test.o" "$ROOT/o9c/test/o9test.c"
$CC -I"$ROOT" -I"$ROOT/o9c/test" \
	-o "$BUILD/host_runtime_test.o" "$ROOT/o9c/test/host_runtime_test.c"
$LD -o "$BUILD/host_runtime_test" \
	"$BUILD/host_runtime_test.o" "$BUILD/o9test.o" "$BUILD/libo9host.a" \
	-L"$PLAN9_LIB" -l9 -lthread -lbio -lpthread -lm
"$BUILD/host_runtime_test"

if [ "${O9_SANITIZE:-0}" != 1 ] && [ "${O9_TSAN:-0}" != 1 ] && \
   command -v valgrind >/dev/null 2>&1; then
	echo "host-test: valgrind runtime edge tests"
	valgrind --quiet --error-exitcode=1 --leak-check=no \
		"$BUILD/host_runtime_test"
fi

echo "host-test: building o9c"
rm -rf "$BUILD/o9c-src"
mkdir -p "$BUILD/o9c-src"
cp -a "$ROOT/o9c/grammar.d" "$BUILD/o9c-src/"
cp "$ROOT/o9c/o9_type.c" "$ROOT/o9c/o9_type.h" "$ROOT/o9c/node.h" \
	"$BUILD/o9c-src/"
(
	cd "$BUILD/o9c-src"
	cat grammar.d/*.y > grammar.y
	yacc -d grammar.y
	9c -o y.tab.o y.tab.c
	9c -o o9_type.o o9_type.c
	9l -o "$BUILD/o9c" y.tab.o o9_type.o -lbio
)

echo "host-test: UI model/e2e tests"
rm -rf "$BUILD/ui"
mkdir -p "$BUILD/ui"
$CC -I"$ROOT" -I"$ROOT/o9c/test" \
	-o "$BUILD/host_ui_main.o" "$ROOT/o9c/test/host_ui_main.c"
$CC -I"$ROOT" -I"$ROOT/o9c/test" -DO9_PLAN9PORT \
	-o "$BUILD/o9_view.o" "$ROOT/o9_view.c"
ui_fail=0
ui_count=0
for ui_src in "$ROOT"/stdlib/e2e_draw*.o9 \
              "$ROOT"/stdlib/e2e_9p.o9 \
              "$ROOT"/stdlib/e2e_builtins.o9 \
              "$ROOT"/stdlib/e2e_cli.o9 \
              "$ROOT"/stdlib/e2e_config.o9 \
              "$ROOT"/stdlib/e2e_dir.o9 \
              "$ROOT"/stdlib/e2e_format.o9 \
              "$ROOT"/stdlib/e2e_import_stdlib.o9 \
              "$ROOT"/stdlib/e2e_io_lines.o9 \
              "$ROOT"/stdlib/e2e_log.o9 \
              "$ROOT"/stdlib/e2e_net_lines.o9 \
              "$ROOT"/stdlib/e2e_process_kit.o9 \
              "$ROOT"/stdlib/e2e_result.o9 \
              "$ROOT"/stdlib/e2e_rune.o9 \
              "$ROOT"/stdlib/e2e_service.o9 \
              "$ROOT"/stdlib/e2e_sync.o9; do
	ui_name=$(basename "$ui_src" .o9)
	ui_expected="$ROOT/stdlib/$ui_name.expected"
	[ -f "$ui_expected" ] || continue
	ui_count=$((ui_count + 1))
	ui_dir="$BUILD/ui/$ui_name"
	mkdir -p "$ui_dir"

	if ! "$BUILD/o9c" --no-facade "$ui_src" > "$ui_dir/test.c" 2>"$ui_dir/gen.err"; then
		echo "host-test: $ui_name: transpile failed"
		cat "$ui_dir/gen.err" >&2
		ui_fail=1
		continue
	fi
	if ! $CC -I"$ROOT" -I"$ROOT/o9c/test" -DO9_PLAN9PORT \
	     -o "$ui_dir/test.o" "$ui_dir/test.c" 2>"$ui_dir/cc.err"; then
		echo "host-test: $ui_name: compile failed"
		head -20 "$ui_dir/cc.err" >&2
		ui_fail=1
		continue
	fi
	if ! $LD -o "$ui_dir/test.bin" \
	     "$BUILD/host_ui_main.o" "$ui_dir/test.o" "$BUILD/o9_view.o" \
	     "$BUILD/libo9host.a" \
	     -L"$PLAN9_LIB" -l9 -lthread -lbio -ldraw -lmemdraw -lm \
	     2>"$ui_dir/link.err"; then
		echo "host-test: $ui_name: link failed"
		head -20 "$ui_dir/link.err" >&2
		ui_fail=1
		continue
	fi
	if ! "$ui_dir/test.bin" > "$ui_dir/out" 2>"$ui_dir/run.err"; then
		echo "host-test: $ui_name: run failed"
		head -20 "$ui_dir/run.err" >&2
		ui_fail=1
		continue
	fi
	if ! cmp -s "$ui_dir/out" "$ui_expected"; then
		echo "host-test: $ui_name: output mismatch"
		echo "--- expected ---" >&2
		cat "$ui_expected" >&2
		echo "--- actual ---" >&2
		cat "$ui_dir/out" >&2
		ui_fail=1
	fi
done
if [ "$ui_fail" -ne 0 ]; then
	echo "host-test: UI tests FAILED" >&2
	exit 1
fi
echo "host-test: UI tests OK ($ui_count cases)"

echo "host-test: struct return from actor"
struct_dir="$BUILD/struct-return"
mkdir -p "$struct_dir"
"$BUILD/o9c" --no-facade "$ROOT/o9c/test/struct_actor_return.o9" \
	> "$struct_dir/test.c"
$CC -I"$ROOT" -I"$ROOT/o9c/test" -DO9_PLAN9PORT \
	-o "$struct_dir/test.o" "$struct_dir/test.c"
$LD -o "$struct_dir/test.bin" \
	"$BUILD/host_ui_main.o" "$struct_dir/test.o" "$BUILD/o9_view.o" \
	"$BUILD/libo9host.a" \
	-L"$PLAN9_LIB" -l9 -lthread -lbio -ldraw -lmemdraw -lm
"$struct_dir/test.bin" > "$struct_dir/out"
if ! grep -qx "made ok 7" "$struct_dir/out"; then
	echo "host-test: struct return failed" >&2
	cat "$struct_dir/out" >&2
	exit 1
fi

echo "host-test: compiler smoke"
python3 "$ROOT/tools/o9c_check.py" --compiler "$BUILD/o9c" --timeout 5

echo "host-test: compiler fuzz"
python3 "$ROOT/tools/o9c_check.py" --compiler "$BUILD/o9c" --timeout 3 \
	--fuzz "$FUZZ_ITER"

if [ "${O9_COVERAGE:-0}" = 1 ]; then
	echo "host-test: coverage report"
	"$LLVM_PROFDATA" merge -sparse "$BUILD"/coverage-*.profraw \
		-o "$BUILD/coverage.profdata"
	set -- "$BUILD/host_runtime_test"
	for ui_bin in "$BUILD"/ui/*/test.bin; do
		[ -f "$ui_bin" ] || continue
		set -- "$@" -object "$ui_bin"
	done
	"$LLVM_COV" report "$@" \
		-instr-profile="$BUILD/coverage.profdata" \
		--ignore-filename-regex='.*/ui/.*/test\.c' > "$BUILD/coverage.txt"
	head -20 "$BUILD/coverage.txt"
	echo "host-test: coverage report at $BUILD/coverage.txt"
fi

echo "host-test: PASS"
