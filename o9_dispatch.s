/*
 * Plan 9 6a asm dispatch with nil-table protection.
 * Calling convention (Pike manual):
 *   BP = first arg (client)
 *   8(SP) = reserved (copy of BP)
 *   16(SP) = second arg (hash)
 *   24(SP) = third arg (args — calls only)
 *
 * ulong is 32-bit even on amd64. Use MOVL then MOVLQZX.
 */
 
/* int o9_dispatch_data(void *client, ulong hash) */
TEXT	o9_dispatch_data(SB), $0
	MOVQ	BP, BX
	MOVQ	16(BX), SI		/* SI = client->table */
	TESTQ	SI, SI
	JZ	fail_data		/* nil table -> fail (CSP fallback handles it) */
	MOVL	16(SP), AX		/* AX = hash */
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
	TESTQ	SI, SI
	JZ	fail_data
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

/* int o9_dispatch_call(void *client, ulong hash, void *args) */
TEXT	o9_dispatch_call(SB), $0
	MOVQ	BP, BX			/* BX = client */
	MOVQ	16(BX), SI		/* SI = client->table */
	TESTQ	SI, SI
	JZ	fail_call		/* nil table -> fail */
	MOVQ	24(SP), DI		/* DI = args */
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
	TESTQ	SI, SI
	JZ	fail_call
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
