; zested - bank allocator.
; A bank is one 16KB OS RAM page. Its id is the OS page index, and only one bank at a time
; is visible, mapped at BANK_WINDOW. Banks holding one text store are chained through
; bank_next/bank_prev so a store is a single linear (bank, page, offset) address space.
; Released banks stay owned in a pool (BANK_POOL) and are reused before asking the OS for
; more; bank_trim hands them back. The OS frees everything still owned when the program exits.

; Forgets all bank state. Call once at startup; pages still owned from the OS are not returned.
bank_init:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,bank_type
	LD DE,bank_type + 1
	LD BC,bank_state_end - bank_type - 1
	LD (HL),0
	LDIR
	POP HL
	POP DE
	POP BC
	RET

; A = bank type -> A = error (0 = ok), B = new bank id. Preserves DE, HL.
bank_alloc:
	PUSH HL
	PUSH DE
	LD (bank_tmp),A
	LD B,BANK_TABLE_SIZE
	LD HL,bank_type
	LD A,BANK_POOL
bank_alloc_scan:
	CP (HL)
	JR Z,bank_alloc_pooled
	INC HL
	DJNZ bank_alloc_scan
	PALLOC
	OR A
	JR NZ,bank_alloc_ret
	LD A,B
	CP BANK_TABLE_SIZE
	JR C,bank_alloc_ok
	PFREE
	LD A,ERR_NO_MORE_MEMORY
	JR bank_alloc_ret
bank_alloc_ok:
	LD E,B
	LD D,0
	LD HL,bank_type
	ADD HL,DE
bank_alloc_pooled:
	LD A,(bank_tmp)
	LD (HL),A
	LD DE,bank_type
	OR A
	SBC HL,DE
	LD B,L			; B = index of the table entry = bank id
	XOR A
bank_alloc_ret:
	POP DE
	POP HL
	RET

; B = bank. Unlinks it and moves it to the pool. Returns A = 0. Preserves BC, DE, HL.
bank_release:
	PUSH HL
	PUSH DE
	PUSH BC
	LD E,B
	LD D,0
	LD HL,bank_prev
	ADD HL,DE
	LD A,(HL)		; unlink from the previous bank
	OR A
	JR Z,bank_release_nprev
	LD L,A
	LD H,0
	PUSH DE
	LD DE,bank_next
	ADD HL,DE
	POP DE
	LD (HL),0
bank_release_nprev:
	LD HL,bank_next
	ADD HL,DE
	LD A,(HL)		; unlink from the next bank
	OR A
	JR Z,bank_release_nnext
	LD L,A
	LD H,0
	PUSH DE
	LD DE,bank_prev
	ADD HL,DE
	POP DE
	LD (HL),0
bank_release_nnext:
	LD HL,bank_type
	ADD HL,DE
	LD (HL),BANK_POOL
	LD HL,bank_next
	ADD HL,DE
	LD (HL),0
	LD HL,bank_prev
	ADD HL,DE
	LD (HL),0
	XOR A
	POP BC
	POP DE
	POP HL
	RET

; Returns every pooled bank to the OS. Banks the OS refuses stay in the pool.
; Preserves BC, DE, HL.
bank_trim:
	PUSH BC
	PUSH DE
	PUSH HL
	LD B,BANK_TABLE_SIZE - 1
bank_trim_loop:
	LD E,B
	LD D,0
	LD HL,bank_type
	ADD HL,DE
	LD A,(HL)
	CP BANK_POOL
	JR NZ,bank_trim_next
	PFREE
	OR A
	JR NZ,bank_trim_next
	LD E,B
	LD D,0
	LD HL,bank_type
	ADD HL,DE
	LD (HL),BANK_FREE
	LD A,(bank_current)
	CP B
	JR NZ,bank_trim_next
	XOR A
	LD (bank_current),A
bank_trim_next:
	DJNZ bank_trim_loop
	POP HL
	POP DE
	POP BC
	RET

; A = bank type. Releases every bank of that type. Preserves BC, DE, HL.
bank_free_type:
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A
	LD B,BANK_TABLE_SIZE - 1
bank_free_type_loop:
	LD E,B
	LD D,0
	LD HL,bank_type
	ADD HL,DE
	LD A,(HL)
	CP C
	JR NZ,bank_free_type_next
	CALL bank_release
bank_free_type_next:
	DJNZ bank_free_type_loop
	POP HL
	POP DE
	POP BC
	RET

; A = previous bank, B = new bank. Chains new after previous. Preserves all registers.
bank_link:
	PUSH HL
	PUSH DE
	LD E,A
	LD D,0
	LD HL,bank_next
	ADD HL,DE
	LD (HL),B
	LD E,B
	LD HL,bank_prev
	ADD HL,DE
	LD (HL),A
	POP DE
	POP HL
	RET

; A = bank -> A = next bank in its store (0 = none). Preserves all other registers.
bank_get_next:
	PUSH HL
	PUSH DE
	LD E,A
	LD D,0
	LD HL,bank_next
	ADD HL,DE
	LD A,(HL)
	POP DE
	POP HL
	RET

; A = bank -> A = previous bank in its store (0 = none). Preserves all other registers.
bank_get_prev:
	PUSH HL
	PUSH DE
	LD E,A
	LD D,0
	LD HL,bank_prev
	ADD HL,DE
	LD A,(HL)
	POP DE
	POP HL
	RET

; A = bank. Maps it at BANK_WINDOW unless it already is. Clobbers A. Preserves BC, DE, HL.
bank_select:
	PUSH HL
	LD HL,bank_current
	CP (HL)
	JR Z,bank_select_ret
	LD (HL),A
	PUSH BC
	PUSH DE
	LD B,A
	SRL A
	SRL A
	LD H,A			; H = page index >> 2
	LD A,B
	RRCA
	RRCA
	AND 0xC0
	LD B,A			; B = (page index & 3) << 6, HBC = physical address
	LD C,0
	LD DE,BANK_WINDOW
	MAP
	POP DE
	POP BC
bank_select_ret:
	POP HL
	RET

; A = bank, D = page, E = offset, HL = delta (16 bit).
; Returns A/D/E = position advanced by delta, following the bank chain.
; Carry set (A = 0) if the position lies beyond the last bank of the chain. Preserves BC, HL.
addr_add:
	PUSH BC
	PUSH HL
	LD C,A
	ADD HL,DE		; page:offset + delta, carry = bit 16
	SBC A,A
	AND 4
	LD B,A
	LD A,H
	RLCA
	RLCA
	AND 3
	ADD A,B
	LD B,A			; B = number of bank boundaries crossed
	LD A,H
	AND 0x3F
	LD D,A
	LD E,L
	LD A,B
	OR A
	LD A,C
	JR Z,addr_add_done
addr_add_loop:
	CALL bank_get_next
	OR A
	JR Z,addr_add_fail
	DJNZ addr_add_loop
addr_add_done:
	OR A
	POP HL
	POP BC
	RET
addr_add_fail:
	XOR A
	SCF
	POP HL
	POP BC
	RET

; A = old type, B = new type. Retypes every bank of the old type. Preserves all registers.
bank_retype:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,A
	LD D,B
	LD B,BANK_TABLE_SIZE - 1
bank_retype_loop:
	LD E,B
	LD H,0
	LD L,E
	PUSH DE
	LD DE,bank_type
	ADD HL,DE
	POP DE
	LD A,(HL)
	CP C
	JR NZ,bank_retype_next
	LD (HL),D
bank_retype_next:
	DJNZ bank_retype_loop
	POP HL
	POP DE
	POP BC
	POP AF
	RET
