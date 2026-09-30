; zested - search and replace.
; Searches walk the logical text through the iterator, so matches may span pieces, pages and
; banks. The pattern and the replacement text live in ordinary RAM (srch_pat, repl_buf).

; HL = pattern, BC = length (1..SRCH_MAX). Returns A = error (0 = ok), Z on success.
search_set:
	LD A,B
	OR A
	JR NZ,search_set_bad
	LD A,C
	OR A
	JR Z,search_set_bad
	CP SRCH_MAX + 1
	JR NC,search_set_bad
	LD (srch_len),A
	LD DE,srch_pat
	LDIR
	XOR A
	RET
search_set_bad:
	LD A,ERR_INVALID_PARAMETER
	OR A
	RET

; HL = replacement text, BC = length (0..SRCH_MAX). Returns A = error (0 = ok), Z on success.
replace_set:
	LD A,B
	OR A
	JR NZ,replace_set_bad
	LD A,C
	CP SRCH_MAX + 1
	JR NC,replace_set_bad
	LD (repl_len),A
	OR A
	RET Z
	LD DE,repl_buf
	LDIR
	XOR A
	RET
replace_set_bad:
	LD A,ERR_INVALID_PARAMETER
	OR A
	RET

; Zeroes the line/column bookkeeping used by the searches.
sr_reset:
	PUSH HL
	LD HL,0
	LD (sr_lines),HL
	LD (sr_col),HL
	POP HL
	RET

; HL = memory, BC = length: accounts for those bytes being passed going forward.
sr_track:
	LD A,B
	OR C
	RET Z
	PUSH BC
	CALL text_nl_tail
	POP BC
	LD A,D
	OR E
	JR Z,sr_track_same
	PUSH HL
	LD HL,(sr_lines)
	ADD HL,DE
	LD (sr_lines),HL
	POP HL
	LD (sr_col),HL
	RET
sr_track_same:
	LD HL,(sr_col)
	ADD HL,BC
	LD (sr_col),HL
	RET

; A = one byte passed going forward.
sr_track_char:
	PUSH HL
	CP 10
	JR Z,sr_track_char_nl
	LD HL,(sr_col)
	INC HL
	LD (sr_col),HL
	POP HL
	RET
sr_track_char_nl:
	LD HL,(sr_lines)
	INC HL
	LD (sr_lines),HL
	LD HL,0
	LD (sr_col),HL
	POP HL
	RET

; IX = iterator. Z if the pattern starts exactly at the iterator position. The iterator does
; not move. Preserves BC, DE, HL.
search_match_here:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	PUSH IX
	POP HL
	LD DE,srch_it
	LD BC,IT_SIZE
	LDIR
	LD IX,srch_it
	LD HL,srch_pat
	LD A,(srch_len)
	LD B,A
search_match_loop:
	CALL iter_next
	JR C,search_match_no
	CP (HL)
	JR NZ,search_match_no
	INC HL
	DJNZ search_match_loop
	XOR A
	JR search_match_ret
search_match_no:
	LD A,1
	OR A
search_match_ret:
	POP IX
	POP HL
	POP DE
	POP BC
	RET

; IX = iterator. Finds the first match starting at or after the iterator position and leaves the
; iterator on its first byte. sr_lines/sr_col describe the text passed (call sr_reset first).
; Returns A = error (ERR_NO_SUCH_ENTRY if none), Z on success.
search_fwd:
	LD A,(srch_len)
	OR A
	JR Z,search_bad
	PUSH BC
	PUSH DE
	PUSH HL
search_fwd_loop:
	CALL iter_chunk
	JR C,search_fwd_none
	LD (sr_avail),BC
	LD (sr_addr),HL
	LD A,(srch_pat)
	CPIR				; look for the first byte inside the mapped chunk
	PUSH AF
	LD HL,(sr_avail)
	OR A
	SBC HL,BC
	LD B,H
	LD C,L				; BC = bytes scanned, including a hit
	POP AF
	JR Z,search_fwd_cand
	LD HL,(sr_addr)
	PUSH BC
	CALL sr_track
	POP BC
	CALL iter_skip
	JR search_fwd_loop
search_fwd_cand:
	DEC BC				; bytes before the candidate
	LD HL,(sr_addr)
	PUSH BC
	CALL sr_track
	POP BC
	CALL iter_skip
	CALL search_match_here		; the rest of the pattern is checked through the iterator
	JR Z,search_fwd_ok
	LD A,(srch_pat)
	CALL sr_track_char
	LD BC,1
	CALL iter_skip
	JR search_fwd_loop
search_fwd_ok:
	XOR A
	JR search_fwd_ret
search_fwd_none:
	LD A,ERR_NO_SUCH_ENTRY
	OR A
search_fwd_ret:
	POP HL
	POP DE
	POP BC
	RET
search_bad:
	LD A,ERR_INVALID_PARAMETER
	OR A
	RET

; IX = iterator. Finds the nearest match starting strictly before the iterator position and
; leaves the iterator on its first byte. sr_lines counts the newlines stepped over (call
; sr_reset first). Returns A = error (ERR_NO_SUCH_ENTRY if none), Z on success.
search_back:
	LD A,(srch_len)
	OR A
	JR Z,search_bad
	PUSH BC
	PUSH DE
	PUSH HL
search_back_loop:
	CALL iter_prev
	JR C,search_back_none
	CP 10
	JR NZ,search_back_test
	LD HL,(sr_lines)
	INC HL
	LD (sr_lines),HL
	LD A,10
search_back_test:
	LD HL,srch_pat
	CP (HL)
	JR NZ,search_back_loop
	CALL search_match_here
	JR NZ,search_back_loop
	XOR A
	JR search_back_ret
search_back_none:
	LD A,ERR_NO_SUCH_ENTRY
	OR A
search_back_ret:
	POP HL
	POP DE
	POP BC
	RET

; ---------------------------------------------------------------- cursor searches
; On success the cursor is on the first byte of the match. On failure it does not move.

ef_copy:
	LD HL,cur_it
	LD DE,find_it
	LD BC,IT_SIZE
	LDIR
	LD IX,find_it
	RET

ef_commit:
	LD HL,find_it
	LD DE,cur_it
	LD BC,IT_SIZE
	LDIR
	CALL cs_set_want
	XOR A
	RET

; Finds the next match at or after the cursor.
ed_find:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	CALL sr_reset
	CALL ef_copy
	JR ed_find_run

; Finds the next match after the cursor (skips a match the cursor is already on).
ed_find_next:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	CALL sr_reset
	CALL ef_copy
	CALL iter_next
	JR C,ed_find_none
	CALL sr_track_char
ed_find_run:
	CALL search_fwd
	JR NZ,ed_find_ret
	LD HL,(sr_lines)
	LD A,H
	OR L
	JR Z,ed_find_same
	LD DE,(cur_line)
	ADD HL,DE
	LD (cur_line),HL
	LD HL,(sr_col)
	LD (cur_col),HL
	JR ed_find_done
ed_find_same:
	LD HL,(cur_col)
	LD DE,(sr_col)
	ADD HL,DE
	LD (cur_col),HL
ed_find_done:
	CALL ef_commit
	JR ed_find_ret
ed_find_none:
	LD A,ERR_NO_SUCH_ENTRY
	OR A
ed_find_ret:
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; Finds the nearest match starting before the cursor.
ed_find_prev:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	CALL sr_reset
	CALL ef_copy
	CALL search_back
	JR NZ,ed_find_ret
	LD HL,(cur_line)
	LD DE,(sr_lines)
	OR A
	SBC HL,DE
	LD (cur_line),HL
	CALL cs_line_len
	LD (cur_col),HL
	CALL ef_commit
	JR ed_find_ret

; ---------------------------------------------------------------- replace

; A = a byte the replace-all scan just stepped back over: keeps ra_line, the line of the
; scan position, in step. Preserves BC, DE, HL.
ra_note_char:
	CP 10
	RET NZ
	PUSH HL
	LD HL,(ra_line)
	DEC HL
	LD (ra_line),HL
	POP HL
	RET

; A replacement can add up to three pieces (split, split, insert). Returns A = 0 if the table has
; room for that, otherwise ERR_NO_MORE_ENTRIES, so a replacement is never left half done.
pieces_room:
	PUSH HL
	PUSH DE
	LD HL,(doc_piece_count)
	LD DE,PIECE_CAP - 2
	OR A
	SBC HL,DE
	LD A,ERR_NO_MORE_ENTRIES
	JR NC,pieces_room_ret
	XOR A
pieces_room_ret:
	OR A
	POP DE
	POP HL
	RET

; Replaces the match under the cursor with the replacement text; the cursor ends after it.
; Returns A = error (ERR_NO_SUCH_ENTRY if the cursor is not on a match), Z on success.
ed_replace:
	CALL undo_begin_group
	CALL ed_replace_body
	PUSH AF
	CALL undo_end_group
	POP AF
	RET

ed_replace_body:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,(srch_len)
	OR A
	LD A,ERR_INVALID_PARAMETER
	JR Z,ed_replace_ret
	LD IX,cur_it
	CALL search_match_here
	LD A,ERR_NO_SUCH_ENTRY
	JR NZ,ed_replace_ret
	CALL pieces_room
	JR Z,ed_replace_go
	CALL doc_try_compact
	LD A,ERR_NO_MORE_ENTRIES
	JR NZ,ed_replace_ret
ed_replace_go:
	LD A,(srch_len)
	LD C,A
	LD B,0
	CALL ed_delete
	JR NZ,ed_replace_ret
	LD A,(repl_len)
	OR A
	JR Z,ed_replace_ret
	LD C,A
	LD B,0
	LD HL,repl_buf
	CALL ed_insert
ed_replace_ret:
	OR A
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; Replaces every match in the document, working from the end towards the start so that earlier
; matches keep their positions. Matches never overlap and replaced text is not searched again.
; The replacement text is stored once and every replacement points at that copy.
; Returns A = error (0 = ok), HL = number of replacements made. The cursor goes to the start.
; The whole operation is one undo step.
ed_replace_all:
	CALL undo_begin_group
	CALL ed_replace_all_body
	PUSH AF
	PUSH HL
	CALL undo_end_group
	POP HL
	POP AF
	RET

ed_replace_all_body:
	PUSH IX
	PUSH BC
	PUSH DE
	LD HL,0
	LD (ra_count),HL
	LD A,(srch_len)
	OR A
	LD A,ERR_INVALID_PARAMETER
	JP Z,ed_replace_all_ret
	LD (li_count),HL
	LD A,(repl_len)
	OR A
	JR Z,ed_replace_all_start
	LD C,A
	LD B,0
	LD HL,repl_buf
	CALL doc_insert_prepare
	OR A
	JP NZ,ed_replace_all_ret
ed_replace_all_start:
	LD IX,cur_it
	CALL iter_seek_end
	LD HL,(doc_newlines)
	LD (ra_line),HL
ed_replace_all_loop:
	LD A,(srch_len)			; a match must end at or before the current position
	DEC A
	JR Z,ed_replace_all_search
	LD B,A
ed_replace_all_step:
	CALL iter_prev
	JR C,ed_replace_all_end
	CALL ra_note_char
	DJNZ ed_replace_all_step
ed_replace_all_search:
	CALL sr_reset
	CALL search_back
	JP NZ,ed_replace_all_end
	LD HL,(ra_line)
	LD DE,(sr_lines)
	OR A
	SBC HL,DE
	LD (ra_line),HL
	LD (ul_line),HL
	CALL pieces_room
	JR Z,ed_replace_all_room
	CALL doc_try_compact		; out of pieces: compact, then carry on from the same spot
	LD A,ERR_NO_MORE_ENTRIES
	JP NZ,ed_replace_all_fail
	LD A,(repl_len)			; the shared copy of the replacement was released
	OR A
	JR Z,ed_replace_all_room
	LD C,A
	LD B,0
	LD HL,repl_buf
	CALL doc_insert_prepare
	OR A
	JP NZ,ed_replace_all_fail
ed_replace_all_room:
	LD A,(srch_len)
	LD C,A
	LD B,0
	CALL doc_delete
	JP NZ,ed_replace_all_fail
	LD A,(repl_len)
	OR A
	JR Z,ed_replace_all_next
	CALL doc_insert_desc
	OR A
	JP NZ,ed_replace_all_fail
	LD A,(repl_len)
	LD B,A
ed_replace_all_back:
	CALL iter_prev			; back to where the replaced text starts
	CALL ra_note_char
	DJNZ ed_replace_all_back
ed_replace_all_next:
	LD HL,(ra_count)
	INC HL
	LD (ra_count),HL
	JR ed_replace_all_loop
ed_replace_all_end:
	XOR A
ed_replace_all_fail:
ed_replace_all_ret:
	PUSH AF
	CALL cur_doc_start
	POP AF
	LD HL,(ra_count)
	OR A
	POP DE
	POP BC
	POP IX
	RET
