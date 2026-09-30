; zested - undo and redo.
; Every edit is one record: INSERT (the text it added, as a piece descriptor into the add
; store) or DELETE (the pieces it removed). Text is never copied: undoing an insert removes
; that range again, undoing a delete links the saved pieces back in. Records move unchanged
; between the undo log and the redo log, so replaying them is symmetric.
; Records made between undo_begin_group and undo_end_group share a group id and are undone
; and redone together.

; Called by doc_init: empty logs, recording off (the editor switches it on).
undo_reset:
	PUSH HL
	PUSH DE
	LD HL,ulog_data
	LD (ulog_desc),HL
	LD (ulog_desc+2),HL
	LD DE,ULOG_SIZE
	ADD HL,DE
	LD (ulog_desc+4),HL
	LD HL,rlog_data
	LD (rlog_desc),HL
	LD (rlog_desc+2),HL
	ADD HL,DE
	LD (rlog_desc+4),HL
	POP DE
	POP HL
	RET

; Forgets the whole history.
undo_clear_all:
	PUSH HL
	LD HL,ulog_desc
	CALL log_clear
	LD HL,rlog_desc
	CALL log_clear
	POP HL
	RET

redo_clear:
	PUSH HL
	LD HL,rlog_desc
	CALL log_clear
	POP HL
	RET

; HL = log descriptor. Empties the log.
log_clear:
	PUSH DE
	PUSH HL
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD (HL),E
	INC HL
	LD (HL),D
	POP HL
	POP DE
	RET

; The open group no longer fits: drop the history and skip recording until the group ends.
undo_overflowed:
	CALL undo_clear_all
	LD A,(undo_depth)
	OR A
	RET Z
	LD A,1
	LD (undo_overflow),A
	RET

; lr_guard = the group being written (records of it must not be dropped), 0 outside groups.
undo_set_guard:
	LD A,(undo_depth)
	OR A
	JR Z,undo_set_guard_store
	LD A,(undo_group)
undo_set_guard_store:
	LD (lr_guard),A
	RET

undo_begin_group:
	PUSH AF
	LD A,(undo_depth)
	OR A
	JR NZ,undo_begin_group_in
	LD A,(undo_gen)
	INC A
	JR NZ,undo_begin_group_id
	INC A
undo_begin_group_id:
	LD (undo_gen),A
	LD (undo_group),A
	XOR A
	LD (undo_overflow),A
undo_begin_group_in:
	LD A,(undo_depth)
	INC A
	LD (undo_depth),A
	POP AF
	RET

undo_end_group:
	PUSH AF
	LD A,(undo_depth)
	OR A
	JR Z,undo_end_group_ret
	DEC A
	LD (undo_depth),A
	JR NZ,undo_end_group_ret
	XOR A
	LD (undo_group),A
	LD (undo_overflow),A
undo_end_group_ret:
	POP AF
	RET

; ---------------------------------------------------------------- log storage

; Copies the log's base/top/end into lr_base/lr_top/lr_end.
log_load:
	LD HL,(lr_desc)
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD (lr_base),DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD (lr_top),DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD (lr_end),DE
	RET

; HL = log -> HL = its newest record. Carry set if the log is empty. Preserves BC, DE.
log_top_rec:
	PUSH BC
	PUSH DE
	LD C,(HL)
	INC HL
	LD B,(HL)
	INC HL
	LD E,(HL)
	INC HL
	LD D,(HL)			; DE = top, BC = base
	LD H,D
	LD L,E
	OR A
	SBC HL,BC
	JR Z,log_top_rec_empty
	DEC DE
	LD A,(DE)
	LD H,A
	DEC DE
	LD A,(DE)
	LD L,A				; HL = size of the newest record
	INC DE
	INC DE
	EX DE,HL			; HL = top, DE = size
	OR A
	SBC HL,DE
	OR A
	POP DE
	POP BC
	RET
log_top_rec_empty:
	SCF
	POP DE
	POP BC
	RET

; HL = log. Drops the oldest record (and the rest of its group). Carry set, nothing dropped, if
; that record belongs to lr_guard. Preserves BC, DE, HL.
log_drop_oldest:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD (ld_desc),HL
log_drop_again:
	LD HL,(ld_desc)
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD (ld_base),DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD (ld_top),DE
	LD IY,(ld_base)
	LD A,(IY+R_GROUP)
	LD (ld_g),A
	LD B,A
	LD A,(lr_guard)
	OR A
	JR Z,log_drop_go
	CP B
	JR NZ,log_drop_go
	SCF
	JR log_drop_ret
log_drop_go:
	LD L,(IY+R_SIZE)
	LD H,(IY+R_SIZE+1)
	LD (ld_size),HL
	LD DE,(ld_base)
	ADD HL,DE			; HL = start of the second record
	LD DE,(ld_top)
	EX DE,HL
	OR A
	SBC HL,DE			; HL = bytes to move down, DE = source
	LD B,H
	LD C,L
	LD HL,(ld_base)
	EX DE,HL			; HL = source, DE = base
	LD A,B
	OR C
	JR Z,log_drop_noshift
	LDIR
log_drop_noshift:
	LD HL,(ld_top)
	LD DE,(ld_size)
	OR A
	SBC HL,DE
	EX DE,HL
	LD HL,(ld_desc)
	INC HL
	INC HL
	LD (HL),E
	INC HL
	LD (HL),D			; top -= size
	LD A,(ld_g)
	OR A
	JR Z,log_drop_done
	LD HL,(ld_base)
	OR A
	SBC HL,DE			; empty now?
	JR Z,log_drop_done
	LD IY,(ld_base)
	LD A,(ld_g)
	CP (IY+R_GROUP)
	JR Z,log_drop_again
log_drop_done:
	OR A
log_drop_ret:
	POP IY
	POP HL
	POP DE
	POP BC
	RET

; HL = log, BC = bytes needed. Makes room by dropping the oldest records.
; Carry set if that is impossible (bigger than the log, or it would eat lr_guard's group).
log_room:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (lr_desc),HL
	LD (lr_need),BC
log_room_loop:
	CALL log_load
	LD HL,(lr_end)
	LD DE,(lr_top)
	OR A
	SBC HL,DE
	LD DE,(lr_need)
	OR A
	SBC HL,DE
	JR NC,log_room_ok
	LD HL,(lr_top)
	LD DE,(lr_base)
	OR A
	SBC HL,DE
	JR Z,log_room_fail		; empty and still too small
	LD HL,(lr_desc)
	CALL log_drop_oldest
	JR C,log_room_fail
	JR log_room_loop
log_room_ok:
	OR A
	JR log_room_ret
log_room_fail:
	SCF
log_room_ret:
	POP HL
	POP DE
	POP BC
	RET

; ---------------------------------------------------------------- positions

; IX = iterator -> A:HL = its 24-bit byte offset in the document. Preserves BC, DE.
doc_position:
	PUSH BC
	PUSH DE
	PUSH IY
	XOR A
	LD (dp_hi),A
	LD HL,0
	LD E,(IX+IT_PIDX)
	LD D,(IX+IT_PIDX+1)
	LD IY,PIECE_TABLE
doc_position_loop:
	LD A,D
	OR E
	JR Z,doc_position_off
	LD C,(IY+P_LEN)
	LD B,(IY+P_LEN+1)
	ADD HL,BC
	JR NC,doc_position_nc
	LD A,(dp_hi)
	INC A
	LD (dp_hi),A
doc_position_nc:
	LD BC,PIECE_SIZE
	ADD IY,BC
	DEC DE
	JR doc_position_loop
doc_position_off:
	PUSH HL
	CALL iter_offset
	LD B,H
	LD C,L
	POP HL
	ADD HL,BC
	JR NC,doc_position_ret
	LD A,(dp_hi)
	INC A
	LD (dp_hi),A
doc_position_ret:
	LD A,(dp_hi)
	POP IY
	POP DE
	POP BC
	RET

; IX = iterator, A:HL = 24-bit byte offset. Positions the iterator there (EOF if past the end).
doc_locate:
	PUSH BC
	PUSH DE
	PUSH IY
	LD (dl_hi),A
	LD DE,0
	LD IY,PIECE_TABLE
doc_locate_loop:
	PUSH HL
	LD HL,(doc_piece_count)
	OR A
	SBC HL,DE
	POP HL
	JR Z,doc_locate_eof
	LD C,(IY+P_LEN)
	LD B,(IY+P_LEN+1)
	LD A,(dl_hi)
	OR A
	JR NZ,doc_locate_sub
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR C,doc_locate_here
doc_locate_sub:
	OR A
	SBC HL,BC
	JR NC,doc_locate_next
	LD A,(dl_hi)
	DEC A
	LD (dl_hi),A
doc_locate_next:
	LD BC,PIECE_SIZE
	ADD IY,BC
	INC DE
	JR doc_locate_loop
doc_locate_here:
	EX DE,HL			; HL = piece index, DE = offset in it
	CALL iter_seek
	JR doc_locate_ret
doc_locate_eof:
	LD HL,(doc_piece_count)
	CALL iter_start_piece
doc_locate_ret:
	POP IY
	POP DE
	POP BC
	RET

; ---------------------------------------------------------------- recording

; IX = iterator at the edit position. Notes the position for the record about to be made.
undo_begin_edit:
	XOR A
	LD (ur_have),A
	LD A,(undo_enabled)
	OR A
	RET Z
	LD A,(undo_busy)
	OR A
	RET NZ
	LD A,(undo_overflow)
	OR A
	RET NZ
	CALL doc_position
	LD (ur_pos),HL
	LD (ur_pos+2),A
	LD A,1
	LD (ur_have),A
	RET

; Records the insertion described by di_desc/di_len/di_nl (made at ur_pos). Consecutive
; insertions that continue each other in the add store extend one record.
undo_rec_insert:
	LD A,(ur_have)
	OR A
	RET Z
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	CALL redo_clear
	LD HL,ulog_desc
	CALL log_top_rec
	JP C,undo_rec_new
	PUSH HL
	POP IY
	LD A,(iy+R_TYPE)
	OR A
	JP NZ,undo_rec_new
	LD A,(undo_group)
	CP (IY+R_GROUP)
	JP NZ,undo_rec_new
	LD A,(IY+R_SIZE)
	CP REC_OVERHEAD + 6
	JP NZ,undo_rec_new
	LD C,(IY+R_PIECES+P_LEN)
	LD B,(IY+R_PIECES+P_LEN+1)
	LD L,(IY+R_POS)
	LD H,(IY+R_POS+1)
	ADD HL,BC
	LD A,(IY+R_POS+2)
	ADC A,0
	LD B,A
	LD DE,(ur_pos)
	OR A
	SBC HL,DE
	JP NZ,undo_rec_new
	LD A,(ur_pos+2)
	CP B
	JP NZ,undo_rec_new
	LD A,(IY+R_PIECES+P_BANK)
	LD D,(IY+R_PIECES+P_PAGE)
	LD E,(IY+R_PIECES+P_OFF)
	LD L,(IY+R_PIECES+P_LEN)
	LD H,(IY+R_PIECES+P_LEN+1)
	CALL addr_add
	JP C,undo_rec_new
	LD HL,di_desc+P_BANK
	CP (HL)
	JP NZ,undo_rec_new
	INC HL
	LD A,D
	CP (HL)
	JP NZ,undo_rec_new
	INC HL
	LD A,E
	CP (HL)
	JP NZ,undo_rec_new
	LD L,(IY+R_PIECES+P_LEN)
	LD H,(IY+R_PIECES+P_LEN+1)
	LD DE,(di_len)
	ADD HL,DE
	JP C,undo_rec_new
	LD (IY+R_PIECES+P_LEN),L
	LD (IY+R_PIECES+P_LEN+1),H
	LD L,(IY+R_NL)
	LD H,(IY+R_NL+1)
	LD DE,(di_nl)
	ADD HL,DE
	JR NC,undo_rec_nl
	LD HL,0xFFFF
undo_rec_nl:
	LD (IY+R_NL),L
	LD (IY+R_NL+1),H
	JR undo_rec_ret
undo_rec_new:
	CALL undo_set_guard
	LD HL,ulog_desc
	LD BC,REC_OVERHEAD + 6
	CALL log_room
	JR C,undo_rec_over
	LD HL,(ulog_desc+2)
	PUSH HL
	POP IY
	LD (IY+R_SIZE),REC_OVERHEAD + 6
	LD (IY+R_SIZE+1),0
	LD (IY+R_TYPE),UT_INSERT
	LD A,(undo_group)
	LD (IY+R_GROUP),A
	LD HL,(ur_pos)
	LD (IY+R_POS),L
	LD (IY+R_POS+1),H
	LD A,(ur_pos+2)
	LD (IY+R_POS+2),A
	LD HL,(ul_line)
	LD (IY+R_LINE),L
	LD (IY+R_LINE+1),H
	LD HL,(di_nl)
	LD (IY+R_NL),L
	LD (IY+R_NL+1),H
	PUSH IY
	POP HL
	LD DE,R_PIECES
	ADD HL,DE
	EX DE,HL
	LD HL,di_desc
	LD BC,PIECE_SIZE
	LDIR
	LD (IY+R_PIECES+6),REC_OVERHEAD + 6
	LD (IY+R_PIECES+7),0
	LD HL,(ulog_desc+2)
	LD DE,REC_OVERHEAD + 6
	ADD HL,DE
	LD (ulog_desc+2),HL
	JR undo_rec_ret
undo_rec_over:
	CALL undo_overflowed
undo_rec_ret:
	POP IY
	POP HL
	POP DE
	POP BC
	RET

; doc_delete calls these three while it removes a range (dd_idx, dd_len = the pieces still to go).

; Sizes the record and reserves its space. Preserves all registers.
undo_del_begin:
	LD A,(ur_have)
	OR A
	RET Z
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD HL,(dd_idx)
	CALL piece_addr
	PUSH HL
	POP IY
	LD HL,(dd_idx)
	LD (ud_start),HL		; used as the piece counter here
	LD HL,0
	LD (ud_n),HL
	LD BC,(dd_len)
undo_del_count:
	LD A,B
	OR C
	JR Z,undo_del_counted
	LD HL,(doc_piece_count)
	LD DE,(ud_start)
	OR A
	SBC HL,DE
	JR Z,undo_del_counted
	INC DE
	LD (ud_start),DE
	LD HL,(ud_n)
	INC HL
	LD (ud_n),HL
	LD E,(IY+P_LEN)
	LD D,(IY+P_LEN+1)
	INC IY
	INC IY
	INC IY
	INC IY
	INC IY
	INC IY
	LD H,B
	LD L,C
	OR A
	SBC HL,DE
	JR C,undo_del_last
	LD B,H
	LD C,L
	JR undo_del_count
undo_del_last:
	LD BC,0
	JR undo_del_count
undo_del_counted:
	LD HL,(ud_n)
	LD D,H
	LD E,L
	ADD HL,HL
	ADD HL,DE
	ADD HL,HL			; 6 * n
	LD DE,REC_OVERHEAD
	ADD HL,DE
	LD B,H
	LD C,L
	CALL undo_set_guard
	LD HL,ulog_desc
	CALL log_room
	JR C,undo_del_over
	LD HL,(ulog_desc+2)
	LD (ud_start),HL
	LD DE,REC_HDR
	ADD HL,DE
	LD (ud_ptr),HL
	JR undo_del_begin_ret
undo_del_over:
	CALL undo_overflowed
	XOR A
	LD (ur_have),A
undo_del_begin_ret:
	POP IY
	POP HL
	POP DE
	POP BC
	RET

; HL = descriptor of a piece that is being removed. Saves a copy in the record.
undo_del_piece:
	LD A,(ur_have)
	OR A
	RET Z
	PUSH BC
	PUSH DE
	PUSH HL
	LD DE,(ud_ptr)
	LD BC,PIECE_SIZE
	LDIR
	LD (ud_ptr),DE
	POP HL
	POP DE
	POP BC
	RET

; HL = the length that was actually removed from the piece just saved (a partial piece).
undo_del_fix_len:
	LD A,(ur_have)
	OR A
	RET Z
	PUSH DE
	PUSH AF
	LD DE,(ud_ptr)
	DEC DE
	LD A,H
	LD (DE),A
	DEC DE
	LD A,L
	LD (DE),A
	POP AF
	POP DE
	RET

; Completes the record: dd_nl newlines were in the removed text.
undo_del_end:
	LD A,(ur_have)
	OR A
	RET Z
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	CALL redo_clear
	LD IY,(ud_start)
	LD HL,(ud_ptr)
	LD DE,(ud_start)
	OR A
	SBC HL,DE
	INC HL
	INC HL				; total size with the trailer
	LD (IY+R_SIZE),L
	LD (IY+R_SIZE+1),H
	LD (IY+R_TYPE),UT_DELETE
	LD A,(undo_group)
	LD (IY+R_GROUP),A
	LD HL,(ur_pos)
	LD (IY+R_POS),L
	LD (IY+R_POS+1),H
	LD A,(ur_pos+2)
	LD (IY+R_POS+2),A
	LD HL,(ul_line)
	LD (IY+R_LINE),L
	LD (IY+R_LINE+1),H
	LD HL,(dd_nl)
	LD (IY+R_NL),L
	LD (IY+R_NL+1),H
	LD E,(IY+R_SIZE)
	LD D,(IY+R_SIZE+1)
	LD HL,(ud_ptr)
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	LD (ulog_desc+2),HL
	POP IY
	POP HL
	POP DE
	POP BC
	RET
