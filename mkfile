# root mkfile — build and install o9 toolchain
# Targets:
#   mk            — build o9c compiler + libo9.a
#   mk install    — install o9c, o9.h, libo9.a system-wide
#   mk clean      — clean build artifacts

</$objtype/mkfile

# === o9c compiler ===
CFILES=\
	o9c/y.tab.$O\

y.tab.h y.tab.c: o9c/o9_plan9.y
	cd o9c; yacc -d o9_plan9.y

o9c/y.tab.$O:	o9c/y.tab.c
	cd o9c; $CC y.tab.c

o9c:V:	$CFILES
	cd o9c; $LD -o o9c y.tab.$O

# === runtime library ===
RUNTIME_OBJ=\
	o9_dispatch.$O\
	o9_runtime.$O\

o9_dispatch.$O:	o9_dispatch.s
	$a o9_dispatch.s

o9_runtime.$O:	o9_runtime.c o9.h
	$CC o9_runtime.c

libo9.a:V:	$RUNTIME_OBJ
	ar r libo9.a o9_dispatch.$O o9_runtime.$O

# === default target ===
default:V:
	o9c libo9.a

# === install ===
install:V: o9c libo9.a
	cp o9c/o9c /$objtype/bin/o9c
	cp o9_dispatch.s /sys/src/cmd/o9_dispatch.s
	cp o9_runtime.c /sys/src/cmd/o9_runtime.c
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
	rm -f o9c/y.tab.* o9c/o9c *.[$O] libo9.a
