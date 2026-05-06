/*
 * o9_dispatch.s -- Plan 9 amd64 assembly dispatch for o9 objects.
 *
 * Two-entry point design:
 *   o9_dispatch_data(fid, hash) -> returns direct pointer to property
 *   o9_dispatch_call(fid, hash, args) -> calls method via ctrl_cache
 *
 * Cache layout (o9_AsmTable):
 *   0-1023:    data_cache[64]  (16 bytes each: {u64 hash, void *ptr})
 *   1024-2047: ctrl_cache[64]  (16 bytes each: {u64 hash, void *ptr})
 *
 * The object struct layout:
 *   +0: int fd
 *   +8: void *shm_base
 *   +16: o9_AsmTable *table
 *   +24: Ref ref (ARC counter)
 */

TEXT	o9_dispatch_data(SB), $0
	MOVQ	client+8(SP), AX	/* AX = client* */
	MOVQ	16(AX), AX		/* AX = client->table */
	MOVQ	hash+16(SP), CX		/* CX = hash */
	MOVQ	CX, BX			/* BX = hash (for verification) */
	ANDQ	$63, CX			/* CX = hash % 64 */
	SHLQ	$4, CX			/* CX = index * 16 */
	ADDQ	AX, CX			/* CX = &data_cache[index] */
	CMPQ	(CX), BX		/* Verify entry->hash == hash */
	JNE	miss_data
	MOVQ	8(CX), AX		/* return entry->ptr */
	RET

miss_data:
	/* Cache miss — call o9_cache_fill(table, hash, 0) for data */
	MOVQ	AX, DI			/* DI = table */
	MOVQ	hash+16(SP), SI		/* SI = hash */
	XORL	DX, DX			/* DX = 0 (data, not ctrl) */
	CALL	o9_cache_fill(SB)
	/* retry dispatch */
	MOVQ	client+8(SP), AX
	MOVQ	16(AX), AX
	MOVQ	hash+16(SP), CX
	MOVQ	CX, BX
	ANDQ	$63, CX
	SHLQ	$4, CX
	ADDQ	AX, CX
	CMPQ	(CX), BX
	JNE	fail
	MOVQ	8(CX), AX
	RET

fail:
	XORL	AX, AX
	RET

TEXT	o9_dispatch_call(SB), $0
	MOVQ	client+8(SP), AX	/* AX = client* */
	MOVQ	16(AX), AX		/* AX = client->table */
	MOVQ	hash+16(SP), CX		/* CX = hash */
	MOVQ	CX, BX			/* BX = hash */
	ANDQ	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX		/* Offset to ctrl_cache */
	ADDQ	AX, CX
	CMPQ	(CX), BX		/* Verify entry->hash == hash */
	JNE	miss_ctrl
	MOVQ	8(CX), DX		/* DX = entry->ptr (function) */
	TESTQ	DX, DX
	JZ	fail
	/* Call the cached function pointer */
	PUSHQ	AX
	MOVQ	args+24(SP), DI		/* DI = args */
	CALL	DX
	POPQ	AX
	RET

miss_ctrl:
	MOVQ	AX, DI
	MOVQ	hash+16(SP), SI
	MOVL	$1, DX			/* DX = 1 (ctrl, not data) */
	CALL	o9_cache_fill(SB)
	/* retry dispatch */
	MOVQ	client+8(SP), AX
	MOVQ	16(AX), AX
	MOVQ	hash+16(SP), CX
	MOVQ	CX, BX
	ANDQ	$63, CX
	SHLQ	$4, CX
	ADDQ	$1024, CX
	ADDQ	AX, CX
	CMPQ	(CX), BX
	JNE	fail
	MOVQ	8(CX), DX
	TESTQ	DX, DX
	JZ	fail
	PUSHQ	AX
	MOVQ	args+24(SP), DI
	CALL	DX
	POPQ	AX
	RET
