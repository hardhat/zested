; zested - document: add store, text insertion, load and save.

doc_init:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,vars_start
	LD DE,vars_start + 1
	LD BC,vars_end - vars_start - 1
	LD (HL),0
	LDIR
	CALL undo_reset
	POP HL
	POP DE
	POP BC
	RET

; Releases every text bank and resets the document. Preserves AF, BC, DE, HL.
doc_close:
	PUSH AF
	CALL compact_abort
	LD A,BANK_ORIGINAL
	CALL bank_free_type
	LD A,BANK_ADD
	CALL bank_free_type
	CALL doc_init
	POP AF
	RET

; Makes sure the add store has room at (add_bank, add_page, add_off).
; Returns A = error (0 = ok), Z set on success. Preserves BC, DE, HL.
add_reserve:
	LD A,(add_bank)
	OR A
	JR Z,add_reserve_new
	LD A,(add_page)
	CP PAGES_PER_BANK
	JR NC,add_reserve_new
	XOR A
	RET
add_reserve_new:
	PUSH BC
	LD A,BANK_ADD
	CALL bank_alloc
	OR A
	JR NZ,add_reserve_ret
	LD A,(add_bank)
	OR A
	CALL NZ,bank_link
	LD A,B
	LD (add_bank),A
	XOR A
	LD (add_page),A
	LD (add_off),A
add_reserve_ret:
	OR A
	POP BC
	RET

; HL = source, BC = length (> 0). The source must not lie in BANK_WINDOW.
; Appends the bytes to the add store, growing it by whole banks as needed.
; Returns A = error (0 = ok), B/D/E = bank/page/offset where the text starts.
add_append:
	LD A,B
	OR C
	LD A,ERR_INVALID_PARAMETER
	RET Z
	LD (aa_src),HL
	LD (aa_len),BC
	CALL add_reserve
	OR A
	RET NZ
	LD A,(add_bank)
	LD (aa_sbank),A
	LD A,(add_page)
	LD (aa_spage),A
	LD A,(add_off)
	LD (aa_soff),A
add_append_loop:
	LD A,(add_off)			; chunk = min(remaining, bytes left in the page)
	LD E,A
	LD D,0
	LD HL,0x100
	OR A
	SBC HL,DE
	LD BC,(aa_len)
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR NC,add_append_copy		; space >= remaining: BC already the chunk
	LD B,H
	LD C,L
add_append_copy:
	LD (aa_chunk),BC
	LD A,(add_bank)
	CALL bank_select
	LD A,(add_page)
	ADD A,BANK_WINDOW >> 8
	LD D,A
	LD A,(add_off)
	LD E,A
	LD HL,(aa_src)
	LDIR
	LD (aa_src),HL
	LD HL,(aa_len)
	LD BC,(aa_chunk)
	OR A
	SBC HL,BC
	LD (aa_len),HL
	LD A,(add_off)
	LD L,A
	LD H,0
	ADD HL,BC
	LD A,H
	OR A
	JR Z,add_append_off
	LD A,(add_page)
	INC A
	LD (add_page),A
	XOR A
	LD H,A
	LD L,A
add_append_off:
	LD A,L
	LD (add_off),A
	LD HL,(aa_len)
	LD A,H
	OR L
	JR Z,add_append_done
	CALL add_reserve
	OR A
	RET NZ
	JR add_append_loop
add_append_done:
	LD A,(aa_sbank)
	LD B,A
	LD A,(aa_spage)
	LD D,A
	LD A,(aa_soff)
	LD E,A
	XOR A
	RET

; IX = iterator giving the insertion point, HL = text, BC = length (> 0).
; Copies the text to the add store and links it into the piece table at the iterator position,
; splitting a piece if needed and merging with neighbours. The iterator is left just after the
; inserted text. Updates doc_newlines.
; Returns A = error (0 = ok), Z set on success.
doc_insert:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL doc_insert_prepare
	OR A
	JR NZ,doc_insert_ret
	CALL doc_insert_desc
doc_insert_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; HL = text, BC = length (> 0). Stores the text in the add store and describes it in di_desc,
; di_len and di_nl, ready for doc_insert_desc. Doing this once and inserting many times lets
; every insertion share one copy of the text. Returns A = error (0 = ok). Clobbers BC, DE, HL.
doc_insert_prepare:
	LD (di_len),BC
	PUSH HL
	PUSH BC
	CALL count_nl_mem
	LD (di_nl),DE
	POP BC
	POP HL
	CALL add_append
	OR A
	RET NZ
	LD A,SRC_ADD
	LD (di_desc+P_SRC),A
	LD A,B
	LD (di_desc+P_BANK),A
	LD A,D
	LD (di_desc+P_PAGE),A
	LD A,E
	LD (di_desc+P_OFF),A
	LD HL,(di_len)
	LD (di_desc+P_LEN),HL
	XOR A
	RET

; IX = iterator giving the insertion point. Links the text described by doc_insert_prepare into
; the piece table there and leaves the iterator just after it. Preserves BC, DE, HL.
doc_insert_desc:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL undo_begin_edit
	LD L,(IX+IT_PIDX)
	LD H,(IX+IT_PIDX+1)
	LD (di_idx),HL
	LD A,(IX+IT_REM)
	OR (IX+IT_REM+1)
	JR Z,doc_insert_link		; EOF: append
	LD L,(IX+IT_PPTR)
	LD H,(IX+IT_PPTR+1)
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)			; DE = piece length
	LD L,(IX+IT_REM)
	LD H,(IX+IT_REM+1)
	EX DE,HL
	OR A
	SBC HL,DE			; HL = offset inside the piece
	LD A,H
	OR L
	JR Z,doc_insert_link		; piece boundary: insert before
	EX DE,HL			; DE = offset
	LD HL,(di_idx)
	CALL piece_split
	OR A
	JP NZ,doc_insert_desc_ret
	LD HL,(di_idx)
	INC HL
	LD (di_idx),HL
doc_insert_link:
	LD HL,(di_idx)
	LD DE,di_desc
	CALL piece_insert
	OR A
	JP NZ,doc_insert_desc_ret
	LD HL,(di_idx)
	LD (di_pos_idx),HL
	LD HL,(di_len)
	LD (di_pos_off),HL		; cursor = (new piece, its length), i.e. just after the text
	LD HL,(di_idx)
	CALL piece_merge		; new piece + following: offset unchanged
	LD HL,(di_idx)
	LD A,H
	OR L
	JR Z,doc_insert_dirty
	DEC HL
	CALL piece_addr
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)			; DE = length of the previous piece
	PUSH DE
	LD HL,(di_idx)
	DEC HL
	CALL piece_merge		; previous + new piece
	POP DE
	JR NC,doc_insert_dirty
	LD HL,(di_idx)
	DEC HL
	LD (di_pos_idx),HL
	LD HL,(di_pos_off)
	ADD HL,DE
	LD (di_pos_off),HL
doc_insert_dirty:
	LD A,1
	LD (doc_dirty),A
	LD HL,(doc_gen)
	INC HL
	LD (doc_gen),HL
	LD HL,(doc_newlines)
	LD DE,(di_nl)
	ADD HL,DE
	JR NC,doc_insert_nl
	LD HL,0xFFFF
doc_insert_nl:
	LD (doc_newlines),HL
	LD HL,(di_pos_idx)
	LD DE,(di_pos_off)
	CALL iter_seek
	CALL undo_rec_insert
	XOR A
doc_insert_desc_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; BC = path (NUL-terminated, in virtual page 1 or 2). Replaces the document with the file
; contents, stored as whole 16KB original banks. Call on a freshly initialised/closed document.
; Returns A = error (0 = ok, otherwise the document is closed).
doc_load:
	PUSH BC
	PUSH DE
	PUSH HL
	XOR A
	LD (fio_prev),A
	LD H,O_RDONLY
	OPEN
	OR A
	JP M,doc_load_open_err
	LD (fio_fd),A
doc_load_bank:
	LD A,BANK_ORIGINAL
	CALL bank_alloc
	OR A
	JR NZ,doc_load_fail
	LD A,B
	LD (fio_cur),A
	CALL bank_select
	LD HL,0
	LD (fio_filled),HL
doc_load_read:
	LD HL,BANK_WINDOW
	LD DE,(fio_filled)
	ADD HL,DE
	EX DE,HL			; DE = where the next read lands
	LD HL,BANK_SIZE
	LD BC,(fio_filled)
	OR A
	SBC HL,BC
	LD B,H
	LD C,L				; BC = room left in the bank
	LD A,(fio_fd)
	LD H,A
	READ
	OR A
	JR NZ,doc_load_fail
	LD A,B
	OR C
	JR Z,doc_load_eof
	LD HL,(fio_filled)
	ADD HL,BC
	LD (fio_filled),HL
	LD A,H
	CP BANK_SIZE >> 8
	JR NZ,doc_load_read
	CALL doc_load_commit		; bank is full, continue with the next one
	OR A
	JR NZ,doc_load_fail
	JR doc_load_bank
doc_load_eof:
	LD HL,(fio_filled)
	LD A,H
	OR L
	JR Z,doc_load_unused
	CALL doc_load_commit
	OR A
	JR NZ,doc_load_fail
	JR doc_load_done
doc_load_unused:
	LD A,(fio_cur)
	LD B,A
	CALL bank_release
doc_load_done:
	CALL doc_load_close
	CALL doc_count_all
	XOR A
	LD (doc_dirty),A
	JR doc_load_ret
doc_load_fail:
	PUSH AF
	CALL doc_load_close
	CALL doc_close
	POP AF
	JR doc_load_ret
doc_load_open_err:
	NEG
doc_load_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

doc_load_close:
	PUSH AF
	LD A,(fio_fd)
	LD H,A
	CLOSE
	POP AF
	RET

; Links the bank in fio_cur after fio_prev and adds a piece for fio_filled bytes.
doc_load_commit:
	LD A,(fio_cur)
	LD B,A
	LD A,(fio_prev)
	OR A
	CALL NZ,bank_link
	LD A,B
	LD (fio_prev),A
	LD DE,(fio_filled)
	LD HL,orig_bytes
	CALL add24
	LD HL,(fio_filled)
	LD DE,0
	LD A,SRC_ORIGINAL
	JP piece_append

; BC = path (NUL-terminated, in virtual page 1 or 2). Streams the logical document to the file,
; writing straight out of the mapped banks. Returns A = error (0 = ok).
doc_save:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	PUSH BC			; remove any old file first: over hostfs, truncating leaves a stale size that
	LD D,B			; makes the OS report spurious write errors
	LD E,C
	RM
	POP BC
	LD H,O_WRONLY | O_CREAT | O_TRUNC
	OPEN
	OR A
	JP M,doc_save_open_err
	LD (fio_fd),A
	LD IX,fio_iter
	CALL iter_init
doc_save_loop:
	CALL iter_chunk
	JR C,doc_save_done
	EX DE,HL			; DE = buffer inside the bank window
	LD A,(fio_fd)
	LD H,A
	WRITE
	OR A
	JR NZ,doc_save_fail
	LD A,B
	OR C
	LD A,ERR_FAILURE
	JR Z,doc_save_fail		; nothing written: give up
	CALL iter_skip
	JR doc_save_loop
doc_save_done:
	CALL doc_load_close
	XOR A
	LD (doc_dirty),A
	JR doc_save_ret
doc_save_fail:
	PUSH AF
	CALL doc_load_close
	POP AF
	JR doc_save_ret
doc_save_open_err:
	NEG
doc_save_ret:
	OR A
	POP IX
	POP HL
	POP DE
	POP BC
	RET
