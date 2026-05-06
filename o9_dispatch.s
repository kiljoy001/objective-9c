/*
 * o9_dispatch.s -- Plan 9 amd64 assembly dispatch.
 *
 * Plan 9 6a convention: first arg in BP, rest on stack.
 * ulong is 32-bit. Use MOVL, then MOVLQZX.
 *
 * Only registers AX, CX, DX, BX, BP, SI, DI.
 * BX is callee-saved — use it to stash client across CALL.
 *
 * Cache entry layout (16 bytes each):
 *   +0: u64int hash
 *   +8: void *ptr
 * data_cache at offset 0, ctrl_cache at offset 1024.
 */

TEXT	o9_dispatch_data(SB), $0
	/* BX = client (callee-saved stash) */
	MOVQ	BP, BX

	/* DI = table = client->table */
	MOVQ	16(BX), DI

	/* AX = hash (32-bit ulong from stack) */
	MOVL	8(SP), AX

	/* SI = hash & 63, then * 16 */
	MOVL	AX, SI
	ANDL	$63, SI
	SHLQ	$4, SI

	/* CX = &data_cache[hash & 63] */
	LEAQ	(DI)(SI*1), CX

	/* DX = hash zero-extended to 64-bit for cmp */
	MOVLQZX	AX, DX

	/* Compare entry->hash (64-bit) with hash */
	CMPQ	0(CX), DX
	JNE	miss_data

	/* Hit: return entry->ptr */
	MOVQ	8(CX), AX
	RET

miss_data:
	/* Restore BP = client and call o9_cache_fill */
	MOVQ	BX, BP
	MOVL	$0, 16(SP)
	CALL	o9_cache_fill(SB)

	/* Retry */
	MOVQ	16(BX), DI
	MOVL	8(SP), AX
	MOVL	AX, SI
	ANDL	$63, SI
	SHLQ	$4, SI
	LEAQ	(DI)(SI*1), CX
	MOVLQZX	AX, DX
	CMPQ	0(CX), DX
	JNE	fail_data
	MOVQ	8(CX), AX
	RET

fail_data:
	XORL	AX, AX
	RET

TEXT	o9_dispatch_call(SB), $0
	MOVQ	BP, BX
	MOVQ	16(BX), DI
	MOVQ	16(SP), SI		/* SI = args */

	MOVL	8(SP), AX
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	DI, CX

	MOVLQZX	AX, DX
	CMPQ	0(CX), DX
	JNE	miss_ctrl

	/* Hit */
	MOVQ	8(CX), AX
	TESTQ	AX, AX
	JZ	fail_ctrl
	MOVQ	SI, BP
	CALL	AX
	MOVL	$1, AX
	RET

miss_ctrl:
	MOVQ	BX, BP
	MOVL	$1, 16(SP)
	CALL	o9_cache_fill(SB)

	/* Retry */
	MOVQ	16(BX), DI
	MOVL	8(SP), AX
	MOVL	AX, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	DI, CX
	MOVLQZX	AX, DX
	CMPQ	0(CX), DX
	JNE	fail_ctrl
	MOVQ	8(CX), AX
	TESTQ	AX, AX
	JZ	fail_ctrl
	MOVQ	16(SP), BP
	CALL	AX
	MOVL	$1, AX
	RET

fail_ctrl:
	XORL	AX, AX
	RET
