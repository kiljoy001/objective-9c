# Structural contracts for compiler-owned output, not a general C formatter.
# Raw C interop remains the application's responsibility.
function bad(message) {
	print FILENAME ":" FNR ": " message
	failed = 1
}
/^\/\* o9 source:/ { original = 1; next }
original && /^ \*\// { original = 0; next }
original { next }
/^[ \t]*\/\* o9:/ { next }
/\/\* raw C begin \*\// { raw = 1; next }
/\/\* raw C end \*\// { raw = 0; next }
raw { next }
/^[ \t]+(\{[ \t]*)?(void|char|uchar|short|ushort|int|uint|long|ulong|vlong|uvlong|double|float|uintptr|intptr|[A-Z][A-Za-z_0-9]*)[ \t]+\**[A-Za-z_][A-Za-z_0-9]*(\[[^]]*\])?[ \t]*=/ {
	bad("initialize automatic variables separately from their declarations")
}
/^[ \t]*(if|for|while|switch)[ \t]+\(/ { bad("no space after a control keyword") }
/^[ \t]*(if|for|while|switch)\(.*\)[ \t]+\{/ { bad("no space before a control opening brace") }
/^typedef struct .*\{/ { bad("separate the typedef from the struct definition") }
/^struct .*\{.*;/ { bad("put struct members on separate lines") }
/^[A-Za-z_].*\)[ \t]*\{/ { bad("put the function opening brace on its own line") }
/__GNUC__|__sync_|__atomic_/ { bad("use Plan 9 atomics") }
/^#include <(stdio|stdint|stdlib|pthread)\.h>/ { bad("use native Plan 9 headers") }
/self->ledger.entries\[.*\.count\+\+/ {
	attach = $0
	sub(/\.count.*/, "", attach)
	attached++
}
/self->ledger.entries\[.*\.count--/ {
	detach = $0
	sub(/\.count.*/, "", detach)
	if(detach != attach)
		bad("ARC attach and detach must address the same ledger slot")
	detached++
}
END {
	if(attached == 0 || attached != detached)
		bad("missing paired ARC callbacks")
	exit failed
}
