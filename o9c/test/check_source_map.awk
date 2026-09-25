# Check lowering locations independently of the C optimizer's PC attribution.
/\/\* o9: o9c\/test\/source_map\/root.o9:6 \| print\( \*\// { rootcomment++ }
/\/\* o9: o9c\/test\/source_map\/middle.o9:15 \| return \*\// { returncomment++ }
/\/\* o9: o9c\/test\/source_map\/leaf.o9:11 \| defer mark\(\); \*\// { defercomment++ }
/^\/\* o9 source: / { originals++ }
/^ \* 7 \| .*"root marker/ { continuation++ }
/^ \* 5 \| .*"must not run/ { stripped++ }
/^#line / {
	line = $2
	file = $3
	gsub(/"/, "", file)
	next
}
function expect(path, number) {
	if(file != path || line != number){
		print "source-map: emitted " file ":" line ", want " path ":" number
		failed = 1
	}
	seen++
}
/__o9r->ret = \(uintptr\)\(23\);/ { expect("o9c/test/source_map/middle.o9", 15) }
/__o9r->ret = \(uintptr\)\(41\);/ { expect("o9c/test/source_map/leaf.o9", 4) }
{ line++ }
END {
	if(rootcomment != 1 || returncomment != 1 || defercomment != 2 ||
	   originals != 3 || continuation != 1 || stripped != 1){
		print "source-map: original-source comment counts", rootcomment, returncomment, defercomment, originals, continuation, stripped
		failed = 1
	}
	if(seen != 2){
		print "source-map: missing emitted return probes"
		failed = 1
	}
	exit failed
}
