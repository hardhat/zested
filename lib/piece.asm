; zested - fixed piece array.
; Piece descriptor (6 bytes): source, bank, page, offset, length (16 bit). A piece describes
; `length` bytes of one text store starting at (bank, page, offset); it may span pages and
; banks. Pieces never have zero length.

; HL = piece index -> HL = address of its descriptor. Preserves all other registers.
piece_addr:
	PUSH DE
	LD D,H
	LD E,L
	ADD HL,HL
	ADD HL,DE
	ADD HL,HL
	LD DE,PIECE_TABLE
	ADD HL,DE
	POP DE
	RET

; HL = index (0..count), DE = 6-byte descriptor to copy in (not inside the piece table).
; Shifts later pieces up. Returns A = error (0 = ok), Z set on success. Preserves BC, DE, HL.
piece_insert:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (pi_src),DE
	LD (pi_idx),HL
	EX DE,HL
	LD DE,P_LEN
	ADD HL,DE
	LD A,(HL)
	INC HL
	OR (HL)
	LD A,ERR_INVALID_PARAMETER
	JR Z,piece_insert_ret
	LD HL,(doc_piece_count)
	LD DE,(pi_idx)
	OR A
	SBC HL,DE		; HL = pieces to shift
	LD A,ERR_INVALID_PARAMETER
	JR C,piece_insert_ret
	PUSH HL
	LD HL,(doc_piece_count)
	LD DE,PIECE_CAP
	OR A
	SBC HL,DE
	POP HL
	LD A,ERR_NO_MORE_ENTRIES
	JR NC,piece_insert_ret
	LD A,H
	OR L
	JR Z,piece_insert_copy
	LD B,H
	LD C,L
	ADD HL,HL
	ADD HL,BC
	ADD HL,HL
	LD B,H
	LD C,L			; BC = shifted bytes
	LD HL,(doc_piece_count)
	CALL piece_addr
	DEC HL			; last byte in use
	PUSH HL
	LD DE,PIECE_SIZE
	ADD HL,DE
	EX DE,HL
	POP HL
	LDDR
piece_insert_copy:
	LD HL,(pi_idx)
	CALL piece_addr
	EX DE,HL
	LD HL,(pi_src)
	LD BC,PIECE_SIZE
	LDIR
	LD HL,(doc_piece_count)
	INC HL
	LD (doc_piece_count),HL
	XOR A
piece_insert_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; HL = index. Removes the piece and shifts later ones down.
; Returns A = error (0 = ok), Z set on success. Preserves BC, DE, HL.
piece_remove:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (pi_idx),HL
	LD DE,(doc_piece_count)
	OR A
	SBC HL,DE
	LD A,ERR_INVALID_PARAMETER
	JR NC,piece_remove_ret	; idx >= count
	LD HL,(doc_piece_count)
	LD DE,(pi_idx)
	OR A
	SBC HL,DE
	DEC HL			; pieces after the removed one
	LD A,H
	OR L
	JR Z,piece_remove_dec
	LD B,H
	LD C,L
	ADD HL,HL
	ADD HL,BC
	ADD HL,HL
	LD B,H
	LD C,L
	LD HL,(pi_idx)
	CALL piece_addr
	LD D,H
	LD E,L
	LD HL,PIECE_SIZE
	ADD HL,DE
	LDIR
piece_remove_dec:
	LD HL,(doc_piece_count)
	DEC HL
	LD (doc_piece_count),HL
	XOR A
piece_remove_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; HL = piece index, DE = split offset inside the piece (0 < offset < length).
; The piece keeps the first `offset` bytes; a new piece at index+1 refers to the rest.
; Returns A = error (0 = ok), Z set on success. Preserves BC, DE, HL.
piece_split:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	LD (ps_idx),HL
	LD (ps_off),DE
	CALL piece_addr
	PUSH HL
	POP IX
	LD A,D
	OR E
	LD A,ERR_INVALID_PARAMETER
	JR Z,piece_split_ret
	LD L,(IX+P_LEN)
	LD H,(IX+P_LEN+1)
	OR A
	SBC HL,DE
	JR C,piece_split_ret
	JR Z,piece_split_ret
	LD (ps_rest),HL
	LD A,(IX+P_SRC)
	LD (ps_desc+P_SRC),A
	LD HL,(ps_off)
	LD A,(IX+P_BANK)
	LD D,(IX+P_PAGE)
	LD E,(IX+P_OFF)
	CALL addr_add
	LD (ps_desc+P_BANK),A
	LD A,ERR_INVALID_PARAMETER
	JR C,piece_split_ret
	LD A,D
	LD (ps_desc+P_PAGE),A
	LD A,E
	LD (ps_desc+P_OFF),A
	LD HL,(ps_rest)
	LD (ps_desc+P_LEN),HL
	LD HL,(ps_idx)
	INC HL
	LD DE,ps_desc
	CALL piece_insert
	JR NZ,piece_split_ret
	LD HL,(ps_off)		; shorten the original (insertion only moved later pieces)
	LD (IX+P_LEN),L
	LD (IX+P_LEN+1),H
	XOR A
piece_split_ret:
	OR A
	POP IX
	POP HL
	POP DE
	POP BC
	RET

; HL = index. Merges piece HL with HL+1 when both come from the same store and the second
; starts exactly where the first ends. Carry set if merged. Preserves all registers.
piece_merge:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	PUSH IY
	LD (pm_idx),HL
	INC HL
	LD DE,(doc_piece_count)
	OR A
	SBC HL,DE
	JR NC,piece_merge_no	; no successor
	LD HL,(pm_idx)
	CALL piece_addr
	PUSH HL
	POP IX
	LD DE,PIECE_SIZE
	ADD HL,DE
	PUSH HL
	POP IY
	LD A,(IX+P_SRC)
	CP (IY+P_SRC)
	JR NZ,piece_merge_no
	LD L,(IX+P_LEN)
	LD H,(IX+P_LEN+1)
	LD E,(IY+P_LEN)
	LD D,(IY+P_LEN+1)
	ADD HL,DE
	JR C,piece_merge_no	; combined length must fit 16 bits
	LD (pm_sum),HL
	LD L,(IX+P_LEN)
	LD H,(IX+P_LEN+1)
	LD A,(IX+P_BANK)
	LD D,(IX+P_PAGE)
	LD E,(IX+P_OFF)
	CALL addr_add		; end of the first piece
	JR C,piece_merge_no
	CP (IY+P_BANK)
	JR NZ,piece_merge_no
	LD A,D
	CP (IY+P_PAGE)
	JR NZ,piece_merge_no
	LD A,E
	CP (IY+P_OFF)
	JR NZ,piece_merge_no
	LD HL,(pm_sum)
	LD (IX+P_LEN),L
	LD (IX+P_LEN+1),H
	LD HL,(pm_idx)
	INC HL
	CALL piece_remove
	POP IY
	POP IX
	POP HL
	POP DE
	POP BC
	POP AF
	SCF
	RET
piece_merge_no:
	POP IY
	POP IX
	POP HL
	POP DE
	POP BC
	POP AF
	OR A
	RET

; A = source, B = bank, D = page, E = offset, HL = length. Appends a piece at the end of the
; document, merging it into the previous piece when contiguous.
; Returns A = error (0 = ok), Z set on success. Preserves BC, DE, HL.
piece_append:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (pd_desc+P_SRC),A
	LD A,B
	LD (pd_desc+P_BANK),A
	LD A,D
	LD (pd_desc+P_PAGE),A
	LD A,E
	LD (pd_desc+P_OFF),A
	LD (pd_desc+P_LEN),HL
	LD HL,(doc_piece_count)
	LD DE,pd_desc
	CALL piece_insert
	JR NZ,piece_append_ret
	LD HL,(doc_piece_count)
	DEC HL			; index of the new piece
	LD A,H
	OR L
	JR Z,piece_append_ok
	DEC HL
	CALL piece_merge
piece_append_ok:
	XOR A
piece_append_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET
