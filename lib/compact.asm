; zested - piece-table compaction.
; Copies the logical document into fresh banks (one contiguous original store), replaces the
; piece table with a handful of large pieces and releases the old stores, including every
; add-store byte that is no longer referenced. It can run in small steps: any edit made
; while one is pending makes it give up (doc_gen changes) and nothing is lost.
; Compaction ends the undo history, since old records point into the released stores.
; The cursor (cur_it) is re-seated at the same offset.

; Starts a compaction. Returns A = error (0 = ok), Z on success.
compact_begin:
	LD A,(cmp_active)
	OR A
	LD A,ERR_INVALID_PARAMETER
	RET NZ
	XOR A
	LD (cn_first),A
	LD (cn_bank),A
	LD (cn_page),A
	LD (cn_off),A
	PUSH IX
	LD IX,cmp_it
	CALL iter_init
	POP IX
	PUSH HL
	LD HL,(doc_gen)
	LD (cmp_gen),HL
	POP HL
	LD A,1
	LD (cmp_active),A
	XOR A
	RET

; Gives up a pending compaction and frees the banks it had built. Preserves all registers.
compact_abort:
	PUSH AF
	LD A,(cmp_active)
	OR A
	JR Z,compact_abort_ret
	LD A,BANK_TEMP
	CALL bank_free_type
	XOR A
	LD (cmp_active),A
compact_abort_ret:
	POP AF
	RET

; BC = most bytes to copy in this call. Returns carry clear with A = 0 (more to do) or A = 1
; (finished); carry set with A = error (ERR_FAILURE if an edit got in the way,
; ERR_NO_MORE_MEMORY if the new store does not fit). After an error nothing has changed.
compact_step:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,(cmp_active)
	OR A
	JP Z,compact_step_inactive
	LD (cmp_budget),BC
	LD HL,(doc_gen)
	LD DE,(cmp_gen)
	OR A
	SBC HL,DE
	JP NZ,compact_step_stale
	LD IX,cmp_it
compact_step_loop:
	LD HL,(cmp_budget)
	LD A,H
	OR L
	JP Z,compact_step_more
	CALL iter_chunk
	JP C,compact_step_end
	LD (cmp_src),HL
	LD A,B
	OR A
	JR Z,compact_step_small
	LD BC,256
compact_step_small:
	LD HL,(cmp_budget)
	OR A
	SBC HL,BC
	JR NC,compact_step_fits
	LD BC,(cmp_budget)
compact_step_fits:
	LD A,(cn_off)
	LD E,A
	LD D,0
	LD HL,256
	OR A
	SBC HL,DE			; room left in the destination page
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR NC,compact_step_page
	LD B,H
	LD C,L
compact_step_page:
	LD (cmp_n),BC
	LD HL,(cmp_src)
	LD DE,cmp_buf
	LDIR				; the source bank is still mapped
	LD A,(cn_bank)
	OR A
	JR Z,compact_step_new
	LD A,(cn_page)
	CP PAGES_PER_BANK
	JR C,compact_step_have
compact_step_new:
	LD A,BANK_TEMP
	CALL bank_alloc
	OR A
	JP NZ,compact_step_nomem
	LD A,(cn_bank)
	OR A
	CALL NZ,bank_link
	LD A,(cn_first)
	OR A
	JR NZ,compact_step_linked
	LD A,B
	LD (cn_first),A
compact_step_linked:
	LD A,B
	LD (cn_bank),A
	XOR A
	LD (cn_page),A
	LD (cn_off),A
compact_step_have:
	LD A,(cn_bank)
	CALL bank_select
	LD A,(cn_page)
	ADD A,BANK_WINDOW >> 8
	LD D,A
	LD A,(cn_off)
	LD E,A
	LD HL,cmp_buf
	LD BC,(cmp_n)
	LDIR
	LD A,(cn_off)
	LD L,A
	LD H,0
	LD BC,(cmp_n)
	ADD HL,BC
	LD A,H
	OR A
	JR Z,compact_step_off
	LD A,(cn_page)
	INC A
	LD (cn_page),A
	LD HL,0
compact_step_off:
	LD A,L
	LD (cn_off),A
	LD BC,(cmp_n)
	CALL iter_skip			; the source iterator is IX = cmp_it
	LD HL,(cmp_budget)
	LD BC,(cmp_n)
	OR A
	SBC HL,BC
	LD (cmp_budget),HL
	JP compact_step_loop
compact_step_more:
	XOR A
	JR compact_step_ok
compact_step_end:
	CALL compact_finish
	LD A,1
compact_step_ok:
	OR A
	JR compact_step_ret
compact_step_nomem:
	LD A,ERR_NO_MORE_MEMORY
	JR compact_step_fail
compact_step_stale:
	LD A,ERR_FAILURE
	JR compact_step_fail
compact_step_inactive:
	LD A,ERR_INVALID_PARAMETER
	JR compact_step_err
compact_step_fail:
	PUSH AF
	CALL compact_abort
	POP AF
compact_step_err:
	SCF
compact_step_ret:
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; The whole document has been copied: swap the new store in.
compact_finish:
	LD IX,cur_it
	CALL doc_position
	LD (cf_pos),HL
	LD (cf_pos+2),A
	LD HL,0
	LD (doc_piece_count),HL
	LD HL,orig_bytes
	XOR A
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD (HL),A
	LD A,(cn_first)
	LD (cf_bank),A
compact_finish_loop:
	LD A,(cf_bank)
	OR A
	JR Z,compact_finish_built
	CALL bank_get_next
	LD (cf_next),A
	OR A
	JR NZ,compact_finish_full
	LD A,(cn_page)			; the last bank is only partly used
	LD H,A
	LD A,(cn_off)
	LD L,A
	JR compact_finish_len
compact_finish_full:
	LD HL,BANK_SIZE
compact_finish_len:
	LD (cf_len),HL
	LD A,(cf_bank)
	LD B,A
	LD A,SRC_ORIGINAL
	LD DE,0
	CALL piece_append
	LD DE,(cf_len)
	LD HL,orig_bytes
	CALL add24
	LD A,(cf_next)
	LD (cf_bank),A
	JR compact_finish_loop
compact_finish_built:
	LD A,BANK_ORIGINAL
	CALL bank_free_type
	LD A,BANK_ADD
	CALL bank_free_type
	LD A,BANK_TEMP
	LD B,BANK_ORIGINAL
	CALL bank_retype
	XOR A
	LD (add_bank),A
	LD (add_page),A
	LD (add_off),A
	LD (cmp_active),A
	LD HL,0
	LD (li_count),HL
	LD HL,(doc_gen)
	INC HL
	LD (doc_gen),HL
	CALL undo_overflowed
	LD IX,cur_it
	LD A,(cf_pos+2)
	LD HL,(cf_pos)
	JP doc_locate

; Compacts the whole document now. Returns carry clear if done, carry set with A = error.
doc_compact:
	CALL compact_begin
	OR A
	JR NZ,doc_compact_err
doc_compact_loop:
	LD BC,0xFFFF
	CALL compact_step
	RET C
	OR A
	JR Z,doc_compact_loop
	XOR A
	RET
doc_compact_err:
	SCF
	RET

; Compacts the document if auto_compact is on (dropping any compaction already pending).
; Returns Z if a compaction was done, NZ if not. Clobbers A, BC, DE, HL.
doc_try_compact:
	LD A,(auto_compact)
	OR A
	JR Z,doc_try_compact_no
	CALL compact_abort
	CALL doc_compact
	JR C,doc_try_compact_no
	XOR A
	RET
doc_try_compact_no:
	LD A,1
	OR A
	RET
