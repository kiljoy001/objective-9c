# root mkfile — build and install o9 toolchain
# Targets:
#   mk            — build o9c compiler + libo9.a
#   mk install    — install o9c, o9.h, libo9.a system-wide
#   mk clean      — clean build artifacts

</$objtype/mkfile

default:V: o9c libo9.a

# === o9c compiler ===
CFILES=\
	o9c/y.tab.$O\
	o9c/o9_type.$O\

o9c/y.tab.h o9c/y.tab.c: o9c/o9.y o9c/o9_type.h
	cd o9c; yacc -d o9.y

o9c/y.tab.$O:	o9c/y.tab.c
	cd o9c; $CC -o y.tab.$O y.tab.c

o9c:V:	$CFILES
	cd o9c; $LD -o o9c y.tab.$O o9_type.$O

# o9_type.o — the live type-builtin table, linked into o9c (above).
o9c/o9_type.$O:	o9c/o9_type.c o9c/o9_type.h
	cd o9c; $CC -o o9_type.$O o9_type.c

ast-test:V:	o9c
	rc ./o9c/test/production_ast.rc

run-test:V:	o9c libo9.a
	rc ./o9c/test/run_e2e.rc

ext-test:V:	o9c libo9.a
	rc ./o9c/test/run_ext.rc

export-test:V:	o9c libo9.a
	rc ./o9c/test/run_export.rc

session-test:V:	o9c libo9.a
	rc ./o9c/test/run_session.rc

session-stress-test:V:	o9c libo9.a
	rc ./o9c/test/run_session_stress.rc

draw-window-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_window.rc

sessreuse-test:V:	o9c libo9.a
	rc ./o9c/test/run_sessreuse.rc

ctlargs-test:V:	o9c libo9.a
	rc ./o9c/test/run_ctlargs.rc

ctlquote-test:V:	o9c libo9.a
	rc ./o9c/test/run_ctlquote.rc

debug-test:V:	o9c libo9.a
	rc ./o9c/test/run_debug.rc

issue-test:V:	o9c libo9.a
	rc ./o9c/test/run_issue_regressions.rc

crypto-test:V:	libo9.a
	$CC -I. o9c/test/crypto_test.c
	$LD -o o9c/test/crypto_test crypto_test.$O libo9.a
	o9c/test/crypto_test

tab-test:V:	libo9.a
	$CC -I. o9c/test/tab_test.c
	$LD -o o9c/test/tab_test tab_test.$O libo9.a
	o9c/test/tab_test

# === runtime library ===
RUNTIME_OBJ=\
	o9_dispatch.$O\
	o9_runtime.$O\
	o9_tab_discard.$O\
	o9_crypto.$O\
	monocypher.$O\

LIBTABDIR=../9lx/libtab
LIBTAB_OBJ=\
	libtab_tab_error.$O\
	libtab_tab_create.$O\
	libtab_tab_row.$O\
	libtab_tab_rowmap.$O\
	libtab_tab_iter.$O\
	libtab_tab_codec.$O\
	libtab_tab_open.$O\
	libtab_tab_serialize.$O\
	libtab_tab_persist.$O\

o9_dispatch.$O:	o9_dispatch.s
	$AS o9_dispatch.s

o9_runtime.$O:	o9_runtime.c o9.h
	$CC -I$LIBTABDIR o9_runtime.c

o9_tab_discard.$O:	o9_tab_discard.c
	$CC -I$LIBTABDIR o9_tab_discard.c

o9_crypto.$O:	o9_crypto.c o9.h monocypher.h
	$CC o9_crypto.c

monocypher.$O:	monocypher.c monocypher.h
	$CC -DMONO_PLAN9 monocypher.c

libtab_tab_error.$O:	$LIBTABDIR/tab_error.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_error.c

libtab_tab_create.$O:	$LIBTABDIR/tab_create.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_create.c

libtab_tab_row.$O:	$LIBTABDIR/tab_row.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_row.c

libtab_tab_rowmap.$O:	$LIBTABDIR/tab_rowmap.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_rowmap.c

libtab_tab_iter.$O:	$LIBTABDIR/tab_iter.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_iter.c

libtab_tab_codec.$O:	$LIBTABDIR/tab_codec.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_codec.c

libtab_tab_open.$O:	$LIBTABDIR/tab_open.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_open.c

libtab_tab_serialize.$O:	$LIBTABDIR/tab_serialize.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_serialize.c

libtab_tab_persist.$O:	$LIBTABDIR/tab_persist.c $LIBTABDIR/libtab.h $LIBTABDIR/tab_internal.h
	$CC -I$LIBTABDIR -o $target $LIBTABDIR/tab_persist.c

libo9.a:	$RUNTIME_OBJ $LIBTAB_OBJ
	ar r libo9.a $RUNTIME_OBJ $LIBTAB_OBJ

# === install ===
install:V: o9c libo9.a
	cp o9c/o9c /$objtype/bin/o9c
	cp o9c/o9c /bin/o9c
	cp o9_dispatch.s /sys/src/cmd/o9_dispatch.s
	cp o9_runtime.c /sys/src/cmd/o9_runtime.c
	cp o9_tab_discard.c /sys/src/cmd/o9_tab_discard.c
	cp o9.h /sys/include/o9.h
	cp libo9.a /$objtype/lib/libo9.a
	@ echo ''
	@ echo '=== o9 toolchain installed ==='
	@ echo '  o9c      -> /'$objtype'/bin/o9c'
	@ echo '  o9.h     -> /sys/include/o9.h'
	@ echo '  libo9.a  -> /'$objtype'/lib/libo9.a'
	@ echo ''
	@ echo 'Usage:'
	@ echo '  o9c < source.o9 > out.c'
	@ echo '  6c out.c'
	@ echo '  6l out.6 -lo9'

clean:V:
	rm -f o9c/y.tab.* o9c/type.tab.* o9c/o9c o9c/o9type *.[$O] libo9.a
