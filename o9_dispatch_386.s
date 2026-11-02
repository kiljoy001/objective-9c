/*
 * Plan 9 8a asm dispatch with nil-table protection.
 *
 * 386 layout differs from amd64 because pointers are 32-bit:
 *   o9_Object.table is at +8.
 *   O9CacheEntry is 12 bytes: u64int hash at +0, void *ptr at +8.
 *   ctrl_cache starts after 64 data entries: 64 * 12 = 768.
 *
 * The selector hash is a 32-bit ulong. Runtime stores it into the u64int
 * cache tag, so a valid hit has low32 == hash and high32 == 0.
 */

/* void* o9_dispatch_data(void *client, ulong hash) */
TEXT	o9_dispatch_data(SB), $24
	MOVL	client+0(FP), BX	/* BX = client */
	TESTL	BX, BX
	JZ	fail_data
	MOVL	8(BX), SI		/* SI = client->table */
	TESTL	SI, SI
	JZ	fail_data
	MOVL	hash+4(FP), AX		/* AX = hash */

data_probe:
	MOVL	AX, CX
	ANDL	$63, CX
	LEAL	(CX)(CX*2), CX		/* hash * 3 */
	SHLL	$2, CX			/* hash * 12 */
	ADDL	SI, CX			/* CX = &data_cache[hash & 63] */
	CMPL	0(CX), AX
	JNE	miss_data
	MOVL	4(CX), DX
	TESTL	DX, DX
	JNE	miss_data
	MOVL	8(CX), AX
	TESTL	AX, AX
	JZ	fail_data
	RET

miss_data:
	MOVL	BX, 12(SP)
	MOVL	AX, 16(SP)
	MOVL	BX, 0(SP)
	MOVL	AX, 4(SP)
	MOVL	$0, 8(SP)
	CALL	o9_cache_fill(SB)
	MOVL	12(SP), BX
	MOVL	16(SP), AX
	MOVL	8(BX), SI
	TESTL	SI, SI
	JNZ	data_probe

fail_data:
	XORL	AX, AX
	RET

/* void* o9_dispatch_call(void *client, ulong hash, void *args) */
TEXT	o9_dispatch_call(SB), $24
	MOVL	client+0(FP), BX	/* BX = client */
	TESTL	BX, BX
	JZ	fail_call
	MOVL	8(BX), SI		/* SI = client->table */
	TESTL	SI, SI
	JZ	fail_call
	MOVL	hash+4(FP), AX		/* AX = hash */
	MOVL	args+8(FP), DI		/* DI = args */

call_probe:
	MOVL	AX, CX
	ANDL	$63, CX
	LEAL	(CX)(CX*2), CX		/* hash * 3 */
	SHLL	$2, CX			/* hash * 12 */
	ADDL	$768, CX
	ADDL	SI, CX			/* CX = &ctrl_cache[hash & 63] */
	CMPL	0(CX), AX
	JNE	miss_call
	MOVL	4(CX), DX
	TESTL	DX, DX
	JNE	miss_call
	MOVL	8(CX), AX
	TESTL	AX, AX
	JZ	fail_call
	MOVL	DI, 0(SP)
	CALL	AX
	MOVL	$1, AX
	RET

miss_call:
	MOVL	BX, 12(SP)
	MOVL	AX, 16(SP)
	MOVL	DI, 20(SP)
	MOVL	BX, 0(SP)
	MOVL	AX, 4(SP)
	MOVL	$1, 8(SP)
	CALL	o9_cache_fill(SB)
	MOVL	12(SP), BX
	MOVL	16(SP), AX
	MOVL	20(SP), DI
	MOVL	8(BX), SI
	TESTL	SI, SI
	JNZ	call_probe

fail_call:
	XORL	AX, AX
	RET
