# root mkfile — build and install o9 toolchain
# Targets:
#   mk            — build o9c compiler + libo9.a
#   mk install    — install o9c, o9.h, libo9.a, stdlib, and o9proj
#   mk clean      — clean build artifacts

</$objtype/mkfile

default:V: o9c libo9.a

# === o9c compiler ===
CFILES=\
	o9c/y.tab.$O\
	o9c/o9_type.$O\

GRAMMAR_PARTS=\
	o9c/grammar.d/00-ast-globals.y\
	o9c/grammar.d/01-symbols.y\
	o9c/grammar.d/02-type-helpers.y\
	o9c/grammar.d/03-yacc-decls.y\
	o9c/grammar.d/10-grammar-rules.y\
	o9c/grammar.d/20-ast-construction.y\
	o9c/grammar.d/30-lexer.y\
	o9c/grammar.d/40-codegen.y\
	o9c/grammar.d/50-app-facade.y\
	o9c/grammar.d/60-prescan.y\
	o9c/grammar.d/70-typecheck.y\
	o9c/grammar.d/80-ast-dump.y\
	o9c/grammar.d/90-import-resolution.y\
	o9c/grammar.d/91-cdeps.y\
	o9c/grammar.d/92-import-resolution-continued.y\
	o9c/grammar.d/99-main.y\

o9c/grammar.y:	$GRAMMAR_PARTS
	cat $GRAMMAR_PARTS > o9c/grammar.y

o9c/y.tab.h o9c/y.tab.c: o9c/grammar.y o9c/o9_type.h
	cd o9c; yacc -d grammar.y

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

tabula-transport-test:V:	o9c libo9.a
	rc ./o9c/test/run_tabula_transport.rc

session-test:V:	o9c libo9.a
	rc ./o9c/test/run_session.rc

session-stress-test:V:	o9c libo9.a
	rc ./o9c/test/run_session_stress.rc

draw-window-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_window.rc

draw-button-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_button.rc

draw-textinput-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_textinput.rc

draw-table-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_table.rc

draw-menu-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_menu.rc

draw-scrollbar-demo:V:	o9c libo9.a
	rc ./o9c/test/run_draw_scrollbar.rc

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

crap-test:V:	libo9.a
	rc ./o9c/test/run_crap.rc

prop-test:V:	o9c libo9.a
	rc ./o9c/test/run_prop_scalar.rc o9c/test/prop/scalar prop-scalar
	rc ./o9c/test/run_prop_scalar.rc o9c/test/prop/width prop-width
	rc ./o9c/test/run_prop_scalar.rc o9c/test/prop/stdlib prop-stdlib

verify:V:	o9c libo9.a
	mk ast-test
	mk run-test
	mk prop-test
	mk export-test
	mk tabula-transport-test
	mk session-test
	mk ctlargs-test
	mk ctlquote-test
	mk issue-test
	mk crypto-test
	mk tab-test
	mk crap-test

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
	if(! cp o9c/o9c /$objtype/bin/o9c) echo 'warning: could not install /'$objtype'/bin/o9c; using /bin/o9c' >[1=2]
	if(! cp o9c/o9c /bin/o9c){
		echo 'warning: could not install /bin/o9c; using '$home'/bin/'$objtype'/o9c' >[1=2]
		if(! test -d $home/bin) mkdir $home/bin
		if(! test -d $home/bin/$objtype) mkdir $home/bin/$objtype
		cp o9c/o9c $home/bin/$objtype/o9c
		chmod +x $home/bin/$objtype/o9c
	}
	if(test -e /bin/o9c) chmod +x /bin/o9c
	if(! cp o9proj /bin/o9proj){
		echo 'warning: could not install /bin/o9proj; using '$home'/bin/rc/o9proj' >[1=2]
		if(! test -d $home/bin) mkdir $home/bin
		if(! test -d $home/bin/rc) mkdir $home/bin/rc
		cp o9proj $home/bin/rc/o9proj
		chmod +x $home/bin/rc/o9proj
	}
	if(test -e /bin/o9proj) chmod +x /bin/o9proj
	if(! cp o9_dispatch.s /sys/src/cmd/o9_dispatch.s) echo 'warning: could not install /sys/src/cmd/o9_dispatch.s' >[1=2]
	if(! cp o9_runtime.c /sys/src/cmd/o9_runtime.c) echo 'warning: could not install /sys/src/cmd/o9_runtime.c' >[1=2]
	if(! cp o9_tab_discard.c /sys/src/cmd/o9_tab_discard.c) echo 'warning: could not install /sys/src/cmd/o9_tab_discard.c' >[1=2]
	if(! cp o9.h /sys/include/o9.h){
		echo 'warning: could not install /sys/include/o9.h; using '$home'/include/o9.h' >[1=2]
		if(! test -d $home/include) mkdir $home/include
		cp o9.h $home/include/o9.h
	}
	if(! cp libo9.a /$objtype/lib/libo9.a){
		echo 'warning: could not install /'$objtype'/lib/libo9.a; using '$home'/lib/o9/libo9.a' >[1=2]
		if(! test -d $home/lib) mkdir $home/lib
		if(! test -d $home/lib/o9) mkdir $home/lib/o9
		cp libo9.a $home/lib/o9/libo9.a
	}
	if(! @{
		if(! test -d /sys/lib/o9) mkdir /sys/lib/o9
		if(! test -d /sys/lib/o9/stdlib) mkdir /sys/lib/o9/stdlib
		cp stdlib/*.o9 /sys/lib/o9/stdlib
	}){
		echo 'warning: could not install /sys/lib/o9/stdlib; using '$home'/lib/o9/stdlib' >[1=2]
		if(! test -d $home/lib) mkdir $home/lib
		if(! test -d $home/lib/o9) mkdir $home/lib/o9
		if(! test -d $home/lib/o9/stdlib) mkdir $home/lib/o9/stdlib
		cp stdlib/*.o9 $home/lib/o9/stdlib
	}
	@ echo ''
	@ echo '=== o9 toolchain installed ==='
	@ echo '  o9c      -> /bin/o9c'
	@ echo '  o9proj   -> /bin/o9proj or '$home'/bin/rc/o9proj'
	@ echo '  o9.h     -> /sys/include/o9.h or '$home'/include/o9.h'
	@ echo '  libo9.a  -> /'$objtype'/lib/libo9.a or '$home'/lib/o9/libo9.a'
	@ echo '  stdlib   -> /sys/lib/o9/stdlib or '$home'/lib/o9/stdlib'
	@ echo ''
	@ echo 'Usage:'
	@ echo '  o9c < source.o9 > out.c'
	@ echo '  6c out.c'
	@ echo '  6l out.6 -lo9'
	@ echo '  o9proj myapp'

clean:V:
	rm -f o9c/grammar.y o9c/y.tab.* o9c/type.tab.* o9c/o9c o9c/o9type o9c/*.[$O]
	rm -f *.[$O] *.9 libo9.a
	rm -f o9c/test/*.[$O] o9c/test/crypto_test o9c/test/tab_test
	rm -f o9c/test/artifacts/o9_draw_*.img o9c/test/artifacts/o9_draw_*.png
