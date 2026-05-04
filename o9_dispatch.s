/*
 * o9_dispatch.s -- Plan 9 amd64 assembly dispatch for o9 objects.
 *
 * Two-entry point design:
 *   o9_dispatch_data(fid, hash) -> returns direct pointer to property
 *   o9_dispatch_call(fid, hash, args) -> calls method via ctrl_cache
 *
 * Cache layout (o9_AsmTable):
 *   0-511:   data_cache[64]  (8 bytes each = direct pointers)
 *   512-1023: ctrl_cache[64]  (8 bytes each = function pointers)
 *
 * The object struct layout:
 *   +0: int fd
 *   +8: void *shm_base
 *   +16: o9_AsmTable *table    <-- points to the 1024-byte table
 *   +24: Ref ref (ARC counter)
 *
 * On cache miss, fall through to o9_cache_fill() which does a
 * 9P walk+read on /cache, then retries.
 */

TEXT	o9_dispatch_data(SB), $0
	MOVQ	table+8(SP), AX		/* AX = o9_AsmTable* */
	MOVQ	hash+16(SP), CX		/* CX = hash (0-63) */
	SHLQ	$3, CX			/* CX = hash * 8 (byte offset) */
	ADDQ	AX, CX			/* CX = &data_cache[hash] */
	MOVQ	(CX), DX		/* DX = data_cache[hash] (pointer or nil) */
	TESTQ	DX, DX
	JZ	miss_data
	MOVQ	DX, AX			/* return the direct pointer */
	RET

miss_data:
	/* Cache miss — call o9_cache_fill(table, hash, 0) for data */
	MOVQ	AX, DI			/* DI = table */
	MOVQ	hash+16(SP), SI		/* SI = hash */
	XORL	DX, DX			/* DX = 0 (data, not ctrl) */
	CALL	o9_cache_fill(SB)
	/* retry dispatch */
	MOVQ	table+8(SP), AX
	MOVQ	hash+16(SP), CX
	SHLQ	$3, CX
	ADDQ	AX, CX
	MOVQ	(CX), DX
	TESTQ	DX, DX
	JZ	fail
	MOVQ	DX, AX
	RET

fail:
	XORL	AX, AX
	RET

/*
 * o9_dispatch_call(fid, hash, args) -> calls ctrl_cache[hash](args)
 * fid in DI, hash in SI, args in DX. Not used yet — stub.
 */
TEXT	o9_dispatch_call(SB), $0
	MOVQ	table+8(SP), AX
	MOVQ	hash+16(SP), CX
	SHLQ	$3, CX
	ADDQ	$512, CX		/* offset to ctrl_cache */
	ADDQ	AX, CX
	MOVQ	(CX), DX
	TESTQ	DX, DX
	JZ	miss_ctrl
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
	MOVQ	table+8(SP), AX
	MOVQ	hash+16(SP), CX
	SHLQ	$3, CX
	ADDQ	$512, CX
	ADDQ	AX, CX
	MOVQ	(CX), DX
	TESTQ	DX, DX
	JZ	fail
	PUSHQ	AX
	MOVQ	args+24(SP), DI
	CALL	DX
	POPQ	AX
	RET
