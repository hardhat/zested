; zested - logical text iterator.
; IX points to an IT_SIZE-byte state block. The iterator hides piece, page and bank
; boundaries. It becomes invalid when the piece table is edited; re-seek afterwards.
; Every routine preserves BC, DE, HL unless the result is returned there.

; IX = iterator, HL = piece index. Positions at the first byte of that piece
; (index >= piece count means EOF). Preserves all registers.
iter_start_piece:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (IX+IT_PIDX),L
	LD (IX+IT_PIDX+1),H
	LD DE,(doc_piece_count)
	OR A
	SBC HL,DE
	LD L,(IX+IT_PIDX)
	LD H,(IX+IT_PIDX+1)
	JR C,iter_start_valid
	LD HL,(doc_piece_count)	; EOF is always index == count
	LD (IX+IT_PIDX),L
	LD (IX+IT_PIDX+1),H
	CALL piece_addr
	LD (IX+IT_PPTR),L
	LD (IX+IT_PPTR+1),H
	XOR A
	LD (IX+IT_REM),A
	LD (IX+IT_REM+1),A
	JR iter_start_ret
iter_start_valid:
	CALL piece_addr
	LD (IX+IT_PPTR),L
	LD (IX+IT_PPTR+1),H
	INC HL			; skip source
	LD A,(HL)
	LD (IX+IT_BANK),A
	INC HL
	LD A,(HL)
	LD (IX+IT_PAGE),A
	INC HL
	LD A,(HL)
	LD (IX+IT_OFF),A
	INC HL
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD (IX+IT_REM),E
	LD (IX+IT_REM+1),D
iter_start_ret:
	POP HL
	POP DE
	POP BC
	RET

; IX = iterator. Positions at the start of the document.
iter_init:
	PUSH HL
	LD HL,0
	CALL iter_start_piece
	POP HL
	RET

; IX = iterator. Positions at the end of the document.
iter_seek_end:
	PUSH HL
	LD HL,(doc_piece_count)
	CALL iter_start_piece
	POP HL
	RET

; IX = iterator, HL = piece index, DE = byte offset inside that piece (<= its length).
; Returns A = error (0 = ok), Z set on success.
iter_seek:
	PUSH BC
	PUSH HL
	LD B,D
	LD C,E
	CALL iter_start_piece
	LD A,B
	OR C
	JR Z,iter_seek_ok
	LD L,(IX+IT_REM)
	LD H,(IX+IT_REM+1)
	OR A
	SBC HL,BC
	LD A,ERR_INVALID_PARAMETER
	JR C,iter_seek_ret
	CALL iter_skip
iter_seek_ok:
	XOR A
iter_seek_ret:
	OR A
	POP HL
	POP BC
	RET

; IX = iterator, BC = bytes to advance (must not exceed the bytes left in the current piece).
iter_skip:
	PUSH AF
	PUSH DE
	PUSH HL
	LD A,B
	OR C
	JR Z,iter_skip_ret
	LD L,(IX+IT_REM)
	LD H,(IX+IT_REM+1)
	OR A
	SBC HL,BC
	JR Z,iter_skip_piece
	LD (IX+IT_REM),L
	LD (IX+IT_REM+1),H
	LD A,(IX+IT_BANK)
	LD D,(IX+IT_PAGE)
	LD E,(IX+IT_OFF)
	LD H,B
	LD L,C
	CALL addr_add
	LD (IX+IT_BANK),A
	LD (IX+IT_PAGE),D
	LD (IX+IT_OFF),E
	JR iter_skip_ret
iter_skip_piece:
	LD L,(IX+IT_PIDX)
	LD H,(IX+IT_PIDX+1)
	INC HL
	CALL iter_start_piece
iter_skip_ret:
	POP HL
	POP DE
	POP AF
	RET

; IX = iterator -> A = byte at the current position, carry clear. Carry set at EOF.
iter_peek:
	LD A,(IX+IT_REM)
	OR (IX+IT_REM+1)
	JR Z,iter_peek_eof
	PUSH HL
	LD A,(IX+IT_BANK)
	CALL bank_select
	LD A,(IX+IT_PAGE)
	ADD A,BANK_WINDOW >> 8
	LD H,A
	LD L,(IX+IT_OFF)
	LD A,(HL)
	POP HL
	OR A
	RET
iter_peek_eof:
	SCF
	RET

; IX = iterator -> A = byte at the current position, then advances. Carry set at EOF.
iter_next:
	CALL iter_peek
	RET C
	PUSH AF
	PUSH BC
	LD BC,1
	CALL iter_skip
	POP BC
	POP AF
	RET

; IX = iterator -> moves back one byte and returns it in A. Carry set (no move) at the start.
iter_prev:
	PUSH BC
	PUSH DE
	PUSH HL
	LD C,(IX+IT_REM)
	LD B,(IX+IT_REM+1)
	LD A,B
	OR C
	JR Z,iter_prev_piece	; at EOF
	LD L,(IX+IT_PPTR)
	LD H,(IX+IT_PPTR+1)
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD H,B
	LD L,C
	OR A
	SBC HL,DE
	JR Z,iter_prev_piece	; at the start of the piece
	LD A,(IX+IT_OFF)
	OR A
	JR Z,iter_prev_page
	DEC A
	LD (IX+IT_OFF),A
	JR iter_prev_rem
iter_prev_page:
	LD A,0xFF
	LD (IX+IT_OFF),A
	LD A,(IX+IT_PAGE)
	OR A
	JR Z,iter_prev_bank
	DEC A
	LD (IX+IT_PAGE),A
	JR iter_prev_rem
iter_prev_bank:
	LD A,PAGES_PER_BANK - 1
	LD (IX+IT_PAGE),A
	LD A,(IX+IT_BANK)
	CALL bank_get_prev
	LD (IX+IT_BANK),A
iter_prev_rem:
	INC BC
	LD (IX+IT_REM),C
	LD (IX+IT_REM+1),B
	JR iter_prev_read
iter_prev_piece:
	LD L,(IX+IT_PIDX)
	LD H,(IX+IT_PIDX+1)
	LD A,H
	OR L
	JR Z,iter_prev_start
	DEC HL
	LD (IX+IT_PIDX),L
	LD (IX+IT_PIDX+1),H
	CALL piece_addr
	LD (IX+IT_PPTR),L
	LD (IX+IT_PPTR+1),H
	INC HL			; skip source
	LD B,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD E,(HL)
	INC HL
	LD C,(HL)
	INC HL
	LD H,(HL)
	LD L,C			; HL = piece length
	DEC HL			; offset of the last byte
	LD A,B
	CALL addr_add
	LD (IX+IT_BANK),A
	LD (IX+IT_PAGE),D
	LD (IX+IT_OFF),E
	LD (IX+IT_REM),1
	LD (IX+IT_REM+1),0
iter_prev_read:
	CALL iter_peek
	POP HL
	POP DE
	POP BC
	RET
iter_prev_start:
	SCF
	POP HL
	POP DE
	POP BC
	RET

; IX = iterator -> HL = address (inside BANK_WINDOW) of the current byte, BC = number of
; contiguous bytes readable from there (bounded by the piece and the bank). Maps the bank.
; Carry set at EOF. Preserves DE.
iter_chunk:
	LD A,(IX+IT_REM)
	OR (IX+IT_REM+1)
	JR Z,iter_chunk_eof
	PUSH DE
	LD A,(IX+IT_BANK)
	CALL bank_select
	LD A,(IX+IT_PAGE)
	ADD A,BANK_WINDOW >> 8
	LD H,A
	LD L,(IX+IT_OFF)
	PUSH HL
	EX DE,HL
	LD HL,BANK_WINDOW + BANK_SIZE
	OR A
	SBC HL,DE		; HL = bytes to the end of the bank
	LD C,(IX+IT_REM)
	LD B,(IX+IT_REM+1)
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR NC,iter_chunk_rem	; bank end >= remaining: bounded by the piece
	LD B,H
	LD C,L
iter_chunk_rem:
	POP HL
	POP DE
	OR A
	RET
iter_chunk_eof:
	SCF
	RET
