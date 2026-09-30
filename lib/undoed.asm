; zested - undo and redo of edits, applied to the document and the cursor.

; ---------------------------------------------------------------- undo / redo

; Undoes the newest edit (or edit group). Returns A = error (ERR_NO_SUCH_ENTRY if none), Z if ok.
ed_undo:
	PUSH AF
	XOR A
	JR undo_redo_common

; Redoes the edit that was last undone.
ed_redo:
	PUSH AF
	LD A,1
undo_redo_common:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD (ua_dir),A
	OR A
	JR NZ,undo_redo_from_redo
	LD HL,ulog_desc
	LD DE,rlog_desc
	JR undo_redo_sel
undo_redo_from_redo:
	LD HL,rlog_desc
	LD DE,ulog_desc
undo_redo_sel:
	LD (ua_src),HL
	LD (ua_dst),DE
	CALL log_top_rec
	LD A,ERR_NO_SUCH_ENTRY
	JR C,undo_redo_ret
	PUSH HL
	POP IY
	LD A,(IY+R_GROUP)
	LD (ua_group),A
	XOR A
	LD (ua_lost),A
	INC A
	LD (undo_busy),A
undo_redo_loop:
	LD HL,(ua_src)
	CALL log_top_rec
	JR C,undo_redo_done
	LD (ua_rec),HL
	CALL ua_apply
	OR A
	JR NZ,undo_redo_fail
	CALL ua_move
	LD A,(ua_group)
	OR A
	JR Z,undo_redo_done
	LD HL,(ua_src)
	CALL log_top_rec
	JR C,undo_redo_done
	PUSH HL
	POP IY
	LD A,(ua_group)
	CP (IY+R_GROUP)
	JR Z,undo_redo_loop
undo_redo_done:
	XOR A
undo_redo_fail:
	PUSH AF
	XOR A
	LD (undo_busy),A
	INC A
	LD (doc_dirty),A
	POP AF
undo_redo_ret:
	OR A
	POP IY
	POP HL
	POP DE
	POP BC
	POP IX
	INC SP				; drop the saved AF: the result is returned in A
	INC SP
	RET

; Replays the record at ua_rec in the direction ua_dir. Returns A = error (0 = ok).
ua_apply:
	LD HL,(ua_rec)
	PUSH HL
	POP IY
	LD A,(IY+R_TYPE)
	LD HL,ua_dir
	XOR (HL)
	LD (ua_mode),A			; 0 = remove the recorded text, 1 = put it back
	LD L,(IY+R_LINE)
	LD H,(IY+R_LINE+1)
	CALL line_index_trim
	CALL ua_count
	LD IX,cur_it
	CALL ua_locate
	LD A,(ua_mode)
	OR A
	JR NZ,ua_put
	LD BC,(ua_len)
	CALL doc_delete
	RET NZ
	JR ua_cursor
ua_put:
	LD HL,(doc_piece_count)
	LD DE,(ua_n)
	ADD HL,DE
	INC HL
	LD DE,PIECE_CAP + 1
	OR A
	SBC HL,DE
	JR C,ua_put_room
	LD A,ERR_NO_MORE_ENTRIES
	OR A
	RET
ua_put_room:
	LD HL,(ua_rec)
	LD DE,R_PIECES
	ADD HL,DE
	LD (ua_p),HL
	LD HL,(ua_n)
	LD (ua_i),HL
	LD HL,0
	LD (di_nl),HL			; newlines are added once, below
ua_put_loop:
	LD HL,(ua_p)
	LD DE,di_desc
	LD BC,PIECE_SIZE
	LDIR
	LD (ua_p),HL
	LD HL,(di_desc+P_LEN)
	LD (di_len),HL
	CALL doc_insert_desc
	OR A
	RET NZ
	LD HL,(ua_i)
	DEC HL
	LD (ua_i),HL
	LD A,H
	OR L
	JR NZ,ua_put_loop
	LD HL,(ua_rec)
	LD DE,R_NL
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD HL,(doc_newlines)
	ADD HL,DE
	JR NC,ua_put_nl
	LD HL,0xFFFF
ua_put_nl:
	LD (doc_newlines),HL
ua_cursor:
	LD HL,(ua_rec)
	PUSH HL
	POP IY
	LD A,(ua_dir)
	OR A
	JR NZ,ua_cursor_redo
	CALL ua_locate			; undo leaves the cursor at the start of the edit
	LD L,(IY+R_LINE)
	LD H,(IY+R_LINE+1)
	JR ua_cursor_set
ua_cursor_redo:
	LD L,(IY+R_LINE)
	LD H,(IY+R_LINE+1)
	LD A,(IY+R_TYPE)
	OR A
	JR NZ,ua_cursor_set		; a redone delete leaves the cursor at the hole
	LD E,(IY+R_NL)			; a redone insert leaves it after the text
	LD D,(IY+R_NL+1)
	ADD HL,DE
ua_cursor_set:
	LD (cur_line),HL
	CALL cs_line_len
	LD (cur_col),HL
	CALL cs_set_want
	XOR A
	RET

; IY = record. IX = iterator to position at the record's offset.
ua_locate:
	LD HL,(ua_rec)
	PUSH HL
	POP IY
	LD A,(IY+R_POS+2)
	LD L,(IY+R_POS)
	LD H,(IY+R_POS+1)
	JP doc_locate

; IY = record -> ua_n = number of pieces, ua_len = their total length.
ua_count:
	LD L,(IY+R_SIZE)
	LD H,(IY+R_SIZE+1)
	LD DE,REC_OVERHEAD
	OR A
	SBC HL,DE			; HL = 6 * n
	LD BC,0
	LD DE,PIECE_SIZE
ua_count_n:
	LD A,H
	OR L
	JR Z,ua_count_sum
	OR A
	SBC HL,DE
	INC BC
	JR ua_count_n
ua_count_sum:
	LD (ua_n),BC
	PUSH IY
	POP HL
	LD DE,R_PIECES
	ADD HL,DE
	LD DE,0
ua_count_loop:
	LD A,B
	OR C
	JR Z,ua_count_done
	PUSH BC
	PUSH HL
	LD BC,P_LEN
	ADD HL,BC
	LD C,(HL)
	INC HL
	LD B,(HL)
	EX DE,HL
	ADD HL,BC
	EX DE,HL
	POP HL
	LD BC,PIECE_SIZE
	ADD HL,BC
	POP BC
	DEC BC
	JR ua_count_loop
ua_count_done:
	LD (ua_len),DE
	RET

; Moves the newest record of ua_src to ua_dst. If the destination cannot hold the group being
; moved, its history is dropped instead.
ua_move:
	LD HL,(ua_src)
	CALL log_top_rec
	RET C
	PUSH HL
	POP IY
	LD C,(IY+R_SIZE)
	LD B,(IY+R_SIZE+1)
	LD (ua_len),BC
	LD A,(ua_lost)
	OR A
	JR NZ,ua_move_pop
	LD A,(ua_group)
	LD (lr_guard),A
	LD HL,(ua_dst)
	CALL log_room
	JR C,ua_move_lost
	LD HL,(ua_dst)
	INC HL
	INC HL
	LD E,(HL)
	INC HL
	LD D,(HL)			; DE = top of the destination
	PUSH IY
	POP HL
	LD BC,(ua_len)
	LDIR
	LD HL,(ua_dst)
	INC HL
	INC HL
	LD (HL),E
	INC HL
	LD (HL),D
	JR ua_move_pop
ua_move_lost:
	LD A,1
	LD (ua_lost),A
	LD HL,(ua_dst)
	CALL log_clear
ua_move_pop:
	LD HL,(ua_src)
	INC HL
	INC HL
	LD E,(HL)
	INC HL
	LD D,(HL)
	PUSH HL
	EX DE,HL
	LD BC,(ua_len)
	OR A
	SBC HL,BC
	EX DE,HL
	POP HL
	LD (HL),D
	DEC HL
	LD (HL),E
	RET
