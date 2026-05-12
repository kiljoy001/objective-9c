/*
 * Full o9_dispatch with both data and ctrl paths.
 * Tested step by step on 9front.
 */
TEXT	o9_dispatch_data(SB), $0
	MOVQ	BP, BX
	MOVQ	16(BX), SI
	MOVL	16(SP), AX
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	SI, CX
	MOVLQZX	AX, DI
	CMPQ	0(CX), DI
	JNE	miss_data
	MOVQ	8(CX), AX
	RET
miss_data:
	MOVL	AX, 8(SP)
	MOVL	$0, 16(SP)
	MOVQ	BX, BP
	CALL	o9_cache_fill(SB)
	MOVQ	16(BX), SI
	MOVL	8(SP), AX
	MOVLQZX	AX, DI
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	SI, CX
	CMPQ	0(CX), DI
	JNE	fail_data
	MOVQ	8(CX), AX
	RET
fail_data:
	XORL	AX, AX
	RET

TEXT	o9_dispatch_call(SB), $0
	MOVQ	BP, BX
	MOVQ	24(SP), DI		/* DI = args */
	MOVQ	16(BX), SI		/* SI = table */
	MOVL	16(SP), AX		/* AX = hash */
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	SI, CX
	MOVLQZX	AX, DX
	CMPQ	0(CX), DX
	JNE	miss_call
	MOVQ	8(CX), AX
	TESTQ	AX, AX
	JZ	fail_call
	MOVQ	DI, BP
	CALL	AX
	MOVL	$1, AX
	RET
miss_call:
	MOVL	AX, 8(SP)
	MOVL	$1, 24(SP)
	MOVQ	BX, BP
	CALL	o9_cache_fill(SB)
	MOVQ	16(BX), SI
	MOVL	8(SP), AX
	MOVLQZX	AX, DX
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	SI, CX
	CMPQ	0(CX), DX
	JNE	fail_call
	MOVQ	8(CX), AX
	TESTQ	AX, AX
	JZ	fail_call
	MOVQ	DI, BP
	CALL	AX
	MOVL	$1, AX
	RET
fail_call:
	XORL	AX, AX
	RET
