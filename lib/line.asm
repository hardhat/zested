; zested - sparse line index and line lookup.
; Entry k (1..LINE_INDEX_CAP) holds the position (piece index, offset in piece) of line 16*k.
; Line 0 is the document start. li_count entries are valid; edits truncate the index and
; line_find extends it lazily, scanning only as far as the requested line.

; HL = k -> HL = address of entry k. Preserves the other registers.
li_entry_ptr:
	PUSH DE
	DEC HL
	ADD HL,HL
	ADD HL,HL
	LD DE,LINE_INDEX
	ADD HL,DE
	POP DE
	RET

; IX = iterator, HL = k (1..li_count). Positions the iterator at the start of line 16*k.
li_seek_entry:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL li_entry_ptr
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD C,(HL)
	INC HL
	LD B,(HL)
	EX DE,HL			; HL = piece
	LD D,B
	LD E,C				; DE = offset
	CALL iter_seek
	POP HL
	POP DE
	POP BC
	RET

; IX = iterator, HL = k. Records the iterator position as entry k.
li_store_entry:
	PUSH BC
	PUSH DE
	PUSH HL
	CALL li_entry_ptr
	PUSH HL
	CALL iter_offset
	EX DE,HL			; DE = offset
	POP HL
	LD C,(IX+IT_PIDX)
	LD B,(IX+IT_PIDX+1)
	LD (HL),C
	INC HL
	LD (HL),B
	INC HL
	LD (HL),E
	INC HL
	LD (HL),D
	POP HL
	POP DE
	POP BC
	RET

; HL = line of an edit. Drops the entries at or after that line: an edit can shift or
; split the pieces they point into. Preserves all registers.
line_index_trim:
	PUSH AF
	PUSH DE
	PUSH HL
	LD A,H
	OR L
	JR Z,line_index_trim_all
	DEC HL
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L				; HL = highest entry number that starts before the edit line
	LD DE,(li_count)
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	JR NC,line_index_trim_ret	; already shorter
	LD (li_count),HL
	JR line_index_trim_ret
line_index_trim_all:
	LD HL,0
	LD (li_count),HL
line_index_trim_ret:
	POP HL
	POP DE
	POP AF
	RET

; IX = iterator, DE = number of newlines (> 0 or 0 for none) to pass. Leaves the iterator just
; after the last one. Carry set if EOF comes first. Clobbers DE.
it_skip_lines:
	LD A,D
	OR E
	RET Z
it_skip_lines_loop:
	CALL iter_chunk
	RET C
	LD (isl_avail),BC
	LD A,10
	CPIR
	PUSH AF				; Z = found a newline
	LD HL,(isl_avail)
	OR A
	SBC HL,BC
	LD B,H
	LD C,L				; BC = bytes consumed including the newline
	CALL iter_skip
	POP AF
	JR NZ,it_skip_lines_loop
	DEC DE
	LD A,D
	OR E
	JR NZ,it_skip_lines_loop
	; DE is 0 here
	OR A
	RET

; IX = iterator, HL = line number. Positions the iterator at the start of that line.
; Returns A = error (ERR_INVALID_PARAMETER if the line is past the last one), Z on success.
line_find:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (lf_line),HL
	LD DE,(doc_newlines)
	EX DE,HL
	OR A
	SBC HL,DE			; newlines - line
	LD A,ERR_INVALID_PARAMETER
	JP C,line_find_ret
	LD HL,(lf_line)
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L				; HL = entry that starts at or before the line
	LD DE,LINE_INDEX_CAP
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	JR C,line_find_k
	LD HL,LINE_INDEX_CAP		; beyond the index: use the last entry and scan on
line_find_k:
	LD (lf_k),HL
	LD A,H
	OR L
	JR NZ,line_find_indexed
	CALL iter_init
	JR line_find_rest
line_find_indexed:
	LD HL,(li_count)
	LD DE,(lf_k)
	OR A
	SBC HL,DE
	JR C,line_find_build		; entry k not built yet
	LD HL,(lf_k)
	CALL li_seek_entry
	JR line_find_rest
line_find_build:
	LD HL,(li_count)
	LD A,H
	OR L
	JR NZ,line_find_from_entry
	CALL iter_init
	JR line_find_scan
line_find_from_entry:
	CALL li_seek_entry
line_find_scan:
	LD DE,16
	CALL it_skip_lines
	LD A,ERR_FAILURE
	JR C,line_find_ret		; index and newline count disagree
	LD HL,(li_count)
	INC HL
	LD (li_count),HL
	CALL li_store_entry
	LD HL,(li_count)
	LD DE,(lf_k)
	OR A
	SBC HL,DE
	JR C,line_find_scan
line_find_rest:
	LD HL,(lf_k)
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	EX DE,HL
	LD HL,(lf_line)
	OR A
	SBC HL,DE
	EX DE,HL			; DE = lines still to pass
	CALL it_skip_lines
	LD A,ERR_INVALID_PARAMETER
	JR C,line_find_ret
	XOR A
line_find_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; B = most entries to add (1..255). Extends the index towards the end of the document, one
; entry per 16 lines. Carry set once nothing more can be added.
line_index_step:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	LD A,B
	LD (lis_n),A
	LD IX,li_it
	LD HL,(li_count)
	LD A,H
	OR L
	JR NZ,line_index_step_entry
	CALL iter_init
	JR line_index_step_loop
line_index_step_entry:
	CALL li_seek_entry
line_index_step_loop:
	LD A,(lis_n)
	OR A
	JR Z,line_index_step_more
	LD HL,(li_count)
	INC HL; number of the entry to add
	PUSH HL
	LD DE,LINE_INDEX_CAP + 1
	OR A
	SBC HL,DE
	POP HL
	JR NC,line_index_step_done
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL; its line number
	LD DE,(doc_newlines)
	EX DE,HL
	OR A
	SBC HL,DE
	JR C,line_index_step_done; the document has fewer lines than that
	LD DE,16
	CALL it_skip_lines
	JR C,line_index_step_done
	LD HL,(li_count)
	INC HL
	LD (li_count),HL
	CALL li_store_entry
	LD HL,lis_n
	DEC (HL)
	JR line_index_step_loop
line_index_step_more:
	OR A
	JR line_index_step_ret
line_index_step_done:
	SCF
line_index_step_ret:
	POP IX
	POP HL
	POP DE
	POP BC
	RET

; Throws the index away, recounts the newlines and builds the whole index again.
line_index_rebuild:
	PUSH BC
	PUSH HL
	LD HL,0
	LD (li_count),HL
	CALL doc_count_all
line_index_rebuild_loop:
	LD B,64
	CALL line_index_step
	JR NC,line_index_rebuild_loop
	POP HL
	POP BC
	RET
