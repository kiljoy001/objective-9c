/*
 * o9_dispatch.s -- Plan 9 amd64 assembly dispatch for o9 objects.
 *
 * Plan 9 6c/6a calling convention:
 *   BP = first argument
 *   8(SP) = second argument (plan9 ulong = 32 bits, stored as MOVL)
 *   16(SP) = third argument
 *
 * o9_dispatch_data(client, hash)
 *   BP = client, 8(SP) = hash (32-bit ulong)
 *   returns void* in AX
 *
 * o9_dispatch_call(client, hash, args)
 *   BP = client, 8(SP) = hash, 16(SP) = args
 *   returns void* in AX (1=success, 0=fail)
 *
 * o9_cache_fill(client, hash, is_ctrl)
 *   BP = client, 8(SP) = hash, 16(SP) = is_ctrl
 *
 * Plan 9 ulong is 32 bits even on amd64! Must use MOVL for hash,
 * then MOVLQZX (zero-extend) to 64 bits for u64int table comparisons.
 */

TEXT	o9_dispatch_data(SB), $0
	MOVQ	BP, BX			/* BX = client (callee-saved) */
	MOVQ	16(BX), R8		/* R8 = client->table */

	/* hash is 32-bit ulong on stack */
	MOVL	8(SP), CX		/* CX = hash (32-bit) */
	MOVLQZX	CX, R9			/* R9 = hash (64-bit zero-extended) */

	/* index = (hash & 63) * 16 */
	ANDL	$63, CX
	SHLQ	$4, CX			/* CX = index * 16 */
	ADDQ	R8, CX			/* CX = &data_cache[index] */

	CMPQ	(CX), R9		/* entry->hash == hash? */
	JNE	miss_data

	MOVQ	8(CX), AX
	RET

miss_data:
	/* o9_cache_fill(client, hash, 0)
	 * BP=client, 8(SP)=hash, 16(SP)=0 */
	MOVQ	BX, BP			/* keep client in BP */
	/* 8(SP) already has hash from caller */
	MOVL	$0, 16(SP)		/* is_ctrl = 0 */
	CALL	o9_cache_fill(SB)

	/* Retry */
	MOVQ	16(BX), R8
	MOVL	8(SP), CX
	MOVLQZX	CX, R9
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	R8, CX
	CMPQ	(CX), R9
	JNE	fail_data
	MOVQ	8(CX), AX
	RET

fail_data:
	XORL	AX, AX
	RET


TEXT	o9_dispatch_call(SB), $0
	MOVQ	BP, BX			/* BX = client */
	MOVL	8(SP), CX		/* CX = hash (32-bit) */
	MOVLQZX	CX, R9			/* R9 = hash (64-bit) */
	MOVQ	16(SP), R12		/* R12 = args */

	MOVQ	16(BX), R13		/* R13 = client->table */

	MOVL	R9, CX
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	R13, CX

	CMPQ	(CX), R9
	JNE	miss_ctrl

	/* Hit */
	MOVQ	8(CX), DX
	TESTQ	DX, DX
	JZ	fail_ctrl
	MOVQ	R12, BP			/* BP = args (1st arg to method) */
	CALL	DX
	MOVL	$1, AX
	RET

miss_ctrl:
	MOVQ	BX, BP
	MOVL	$1, 16(SP)		/* is_ctrl = 1 */
	CALL	o9_cache_fill(SB)

	/* Retry */
	MOVQ	16(BX), R13
	MOVL	8(SP), CX
	MOVLQZX	CX, R9
	ANDL	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	R13, CX
	CMPQ	(CX), R9
	JNE	fail_ctrl

	MOVQ	8(CX), DX
	TESTQ	DX, DX
	JZ	fail_ctrl
	MOVQ	16(SP), BP		/* BP = args */
	CALL	DX
	MOVL	$1, AX
	RET

fail_ctrl:
	XORL	AX, AX
	RET
