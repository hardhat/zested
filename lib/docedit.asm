; zested - document editing beyond insertion: newline counting and range deletion.

; HL = memory, BC = length -> DE = number of newlines. Clobbers A, BC, HL.
count_nl_mem:
	LD DE,0
count_nl_mem_loop:
	LD A,B
	OR C
	RET Z
	LD A,10
	CPIR
	RET NZ
	INC DE
	JR count_nl_mem_loop

; HL = memory, BC = length -> DE = newlines, HL = bytes after the last newline (== length if none).
; Clobbers A, BC.
text_nl_tail:
	LD (tnt_tail),BC
	LD DE,0
text_nl_tail_loop:
	LD A,B
	OR C
	JR Z,text_nl_tail_done
	LD A,10
	CPIR
	JR NZ,text_nl_tail_done
	INC DE
	LD (tnt_tail),BC
	JR text_nl_tail_loop
text_nl_tail_done:
	LD HL,(tnt_tail)
	RET

; Counts the newlines of the whole document into doc_newlines (saturating).
doc_count_all:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	LD IX,fio_iter
	CALL iter_init
	LD HL,0
	LD (doc_newlines),HL
doc_count_all_loop:
	CALL iter_chunk
	JR C,doc_count_all_done
	LD (dc_chunk),BC
	CALL count_nl_mem
	LD HL,(doc_newlines)
	ADD HL,DE
	JR NC,doc_count_all_store
	LD HL,0xFFFF
doc_count_all_store:
	LD (doc_newlines),HL
	LD BC,(dc_chunk)
	CALL iter_skip
	JR doc_count_all_loop
doc_count_all_done:
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; IX = iterator, BC = length -> DE = newlines in the next BC bytes (stops at EOF).
; The iterator is not moved. Preserves BC, HL.
doc_count_range:
	PUSH BC
	PUSH HL
	PUSH IX
	LD (dc_len),BC
	PUSH IX
	POP HL
	LD DE,dc_iter
	LD BC,IT_SIZE
	LDIR
	LD IX,dc_iter
	LD HL,0
	LD (dc_count),HL
doc_count_range_loop:
	LD BC,(dc_len)
	LD A,B
	OR C
	JR Z,doc_count_range_done
	CALL iter_chunk
	JR C,doc_count_range_done
	LD DE,(dc_len)
	PUSH HL
	LD H,B
	LD L,C
	OR A
	SBC HL,DE
	POP HL
	JR C,doc_count_range_use	; chunk shorter than the range: take all of it
	LD B,D
	LD C,E
doc_count_range_use:
	LD (dc_chunk),BC
	CALL count_nl_mem
	LD HL,(dc_count)
	ADD HL,DE
	LD (dc_count),HL
	LD BC,(dc_chunk)
	CALL iter_skip
	LD HL,(dc_len)
	OR A
	SBC HL,BC
	LD (dc_len),HL
	JR doc_count_range_loop
doc_count_range_done:
	LD DE,(dc_count)
	POP IX
	POP HL
	POP BC
	RET

; IX = iterator at the first byte to delete, BC = number of bytes (clamped at EOF).
; Only the piece table changes. The iterator is left at the deletion point. Updates doc_newlines.
; Returns A = error (0 = ok), Z set on success.
doc_delete:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD A,B
	OR C
	JP Z,doc_delete_ret
	LD A,(IX+IT_REM)
	OR (IX+IT_REM+1)
	JP Z,doc_delete_ret		; at EOF: nothing to delete
	LD (dd_len),BC
	CALL undo_begin_edit
	CALL doc_count_range
	LD (dd_nl),DE
	LD L,(IX+IT_PIDX)
	LD H,(IX+IT_PIDX+1)
	LD (dd_idx),HL
	CALL iter_offset		; HL = offset inside the first piece
	LD A,H
	OR L
	JR Z,doc_delete_capture
	LD (dd_off),HL
	LD DE,(dd_len)
	ADD HL,DE
	JR C,doc_delete_split
	LD E,(IX+IT_LEN)
	LD D,(IX+IT_LEN+1)
	OR A
	SBC HL,DE
	JP Z,doc_delete_tail		; the range is exactly the end of this piece
doc_delete_split:
	LD HL,(dd_off)
	EX DE,HL
	LD HL,(dd_idx)
	CALL piece_split		; the range now starts at a piece boundary
	OR A
	JP NZ,doc_delete_ret
	LD HL,(dd_idx)
	INC HL
	LD (dd_idx),HL
doc_delete_capture:
	CALL undo_del_begin
doc_delete_loop:
	LD BC,(dd_len)
	LD A,B
	OR C
	JR Z,doc_delete_after
	LD HL,(dd_idx)
	LD DE,(doc_piece_count)
	OR A
	SBC HL,DE
	JR NC,doc_delete_after		; ran off the end of the document
	LD HL,(dd_idx)
	CALL piece_addr
	CALL undo_del_piece
	PUSH HL
	POP IY
	LD E,(IY+P_LEN)
	LD D,(IY+P_LEN+1)
	LD HL,(dd_len)
	OR A
	SBC HL,DE			; remaining - piece length
	JR C,doc_delete_partial
	LD (dd_len),HL
	LD HL,(dd_idx)
	CALL piece_remove
	OR A
	JP NZ,doc_delete_ret
	JR doc_delete_loop
doc_delete_partial:
	LD HL,(dd_len)			; drop the first `remaining` bytes of this piece
	CALL undo_del_fix_len
	LD A,(IY+P_BANK)
	LD D,(IY+P_PAGE)
	LD E,(IY+P_OFF)
	CALL addr_add
	LD (IY+P_BANK),A
	LD (IY+P_PAGE),D
	LD (IY+P_OFF),E
	LD E,(IY+P_LEN)
	LD D,(IY+P_LEN+1)
	LD HL,(dd_len)
	EX DE,HL
	OR A
	SBC HL,DE
	LD (IY+P_LEN),L
	LD (IY+P_LEN+1),H
	LD HL,0
	LD (dd_len),HL
doc_delete_after:
	LD HL,(dd_idx)
	LD A,H
	OR L
	JR Z,doc_delete_here
	DEC HL
	CALL piece_addr
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD (dd_prev),DE
	LD HL,(dd_idx)
	DEC HL
	CALL piece_merge
	JR NC,doc_delete_here
	LD HL,(dd_idx)
	DEC HL
	LD DE,(dd_prev)			; cursor sits at the old join inside the merged piece
	JR doc_delete_seek
doc_delete_here:
	LD HL,(dd_idx)
	LD DE,0
	JR doc_delete_seek
; The range is the tail of one piece (backspace over typed text): shorten the piece, no shifting.
doc_delete_tail:
	LD L,(IX+IT_PPTR)
	LD H,(IX+IT_PPTR+1)
	PUSH HL
	POP IY
	LD A,(IY+P_SRC)
	LD (ds_desc+P_SRC),A
	LD A,(IY+P_BANK)
	LD D,(IY+P_PAGE)
	LD E,(IY+P_OFF)
	LD HL,(dd_off)
	CALL addr_add
	LD (ds_desc+P_BANK),A
	LD A,D
	LD (ds_desc+P_PAGE),A
	LD A,E
	LD (ds_desc+P_OFF),A
	LD HL,(dd_len)
	LD (ds_desc+P_LEN),HL
	CALL undo_del_begin_one
	LD HL,ds_desc
	CALL undo_del_piece
	LD HL,(dd_off)
	LD (IY+P_LEN),L
	LD (IY+P_LEN+1),H
	LD HL,(dd_idx)
	LD DE,(dd_off)
doc_delete_seek:
	CALL iter_seek
	LD HL,(doc_newlines)
	LD DE,(dd_nl)
	OR A
	SBC HL,DE
	JR NC,doc_delete_nl
	LD HL,0
doc_delete_nl:
	LD (doc_newlines),HL
	LD A,1
	LD (doc_dirty),A
	LD HL,(doc_gen)
	INC HL
	LD (doc_gen),HL
	CALL undo_del_end
	XOR A
doc_delete_ret:
	OR A
	POP IY
	POP HL
	POP DE
	POP BC
	RET

; HL = 24-bit variable, DE = 16-bit value: (HL) += DE. Preserves all registers.
add24:
	PUSH AF
	PUSH HL
	LD A,(HL)
	ADD A,E
	LD (HL),A
	INC HL
	LD A,(HL)
	ADC A,D
	LD (HL),A
	INC HL
	LD A,(HL)
	ADC A,0
	LD (HL),A
	POP HL
	POP AF
	RET
