; zested - editor cursor, editing operations and scrolling.
; The cursor is an iterator (cur_it) plus line, column and a remembered column (cur_want).
; Moving costs O(1) per character; edits re-seat the iterator through doc_insert/doc_delete.
; Lines and columns count bytes; the display layer decides how wide a tab is.

DEFC ED_DEFAULT_ROWS = 39
DEFC ED_DEFAULT_COLS = 80

; Resets the document and the cursor.
ed_init:
	CALL doc_init
	LD A,ED_DEFAULT_ROWS
	LD (view_rows),A
	LD A,ED_DEFAULT_COLS
	LD (view_cols),A
	JR cur_reset

; Puts the cursor and the view at the start of the document.
cur_reset:
	PUSH IX
	LD IX,cur_it
	CALL iter_init
	POP IX
	LD HL,0
	LD (cur_line),HL
	LD (cur_col),HL
	LD (cur_want),HL
	LD (view_top),HL
	LD (view_left),HL
	LD A,1
	LD (undo_enabled),A
	RET

; BC = path. Replaces the current document with the file. Returns A = error (0 = ok).
ed_load:
	CALL doc_close
	CALL doc_load
	PUSH AF
	CALL cur_reset
	POP AF
	OR A
	RET

; BC = path. Returns A = error (0 = ok).
ed_save:
	JP doc_save

; ---------------------------------------------------------------- movement primitives
; These assume IX = cur_it and keep line/column in step. They leave cur_want alone.

cs_set_want:
	LD HL,(cur_col)
	LD (cur_want),HL
	RET

; One byte forward. Carry set at EOF.
cs_right:
	CALL iter_next
	RET C
	CP 10
	JR Z,cs_right_nl
	LD HL,(cur_col)
	INC HL
	LD (cur_col),HL
	OR A
	RET
cs_right_nl:
	LD HL,(cur_line)
	INC HL
	LD (cur_line),HL
	LD HL,0
	LD (cur_col),HL
	OR A
	RET

; One byte back. Carry set at the start of the document.
cs_left:
	CALL iter_prev
	RET C
	CP 10
	JR Z,cs_left_nl
	LD HL,(cur_col)
	DEC HL
	LD (cur_col),HL
	OR A
	RET
cs_left_nl:
	LD HL,(cur_line)
	DEC HL
	LD (cur_line),HL
	CALL cs_line_len
	LD (cur_col),HL
	OR A
	RET

; HL = bytes between the previous newline (or the document start) and the cursor.
; Works on a copy of the cursor. Preserves BC, DE.
cs_line_len:
	PUSH BC
	PUSH DE
	PUSH IX
	PUSH IX
	POP HL
	LD DE,tmp_it
	LD BC,IT_SIZE
	LDIR
	LD IX,tmp_it
	LD BC,0
cs_line_len_loop:
	CALL iter_prev
	JR C,cs_line_len_done
	CP 10
	JR Z,cs_line_len_done
	INC BC
	JR cs_line_len_loop
cs_line_len_done:
	POP IX
	LD H,B
	LD L,C
	POP DE
	POP BC
	RET

; Back to column 0.
cs_home:
	LD BC,(cur_col)
cs_home_loop:
	LD A,B
	OR C
	JR Z,cs_home_done
	CALL iter_prev
	DEC BC
	JR cs_home_loop
cs_home_done:
	LD HL,0
	LD (cur_col),HL
	RET

; Forward to the end of the line (before its newline).
cs_end:
	CALL iter_peek
	RET C
	CP 10
	RET Z
	PUSH BC
	LD BC,1
	CALL iter_skip
	POP BC
	LD HL,(cur_col)
	INC HL
	LD (cur_col),HL
	JR cs_end

; From column 0, forward up to cur_want columns without leaving the line.
cs_to_want:
	LD BC,(cur_want)
cs_to_want_loop:
	LD A,B
	OR C
	RET Z
	CALL iter_peek
	RET C
	CP 10
	RET Z
	CALL cs_right
	DEC BC
	JR cs_to_want_loop

; ---------------------------------------------------------------- cursor movement
; Movement routines return carry set when the cursor could not move.

cur_right:
	PUSH IX
	LD IX,cur_it
	CALL cs_right
	CALL NC,cs_set_want
	POP IX
	RET

cur_left:
	PUSH IX
	LD IX,cur_it
	CALL cs_left
	CALL NC,cs_set_want
	POP IX
	RET

cur_home:
	PUSH IX
	LD IX,cur_it
	CALL cs_home
	CALL cs_set_want
	OR A
	POP IX
	RET

; Moves to the end of the line; the remembered column becomes "end of line".
cur_end:
	PUSH IX
	LD IX,cur_it
	CALL cs_end
	LD HL,0xFFFF
	LD (cur_want),HL
	OR A
	POP IX
	RET

cur_down:
	PUSH IX
	LD IX,cur_it
	LD HL,(cur_line)
	LD DE,(doc_newlines)
	OR A
	SBC HL,DE
	JR NC,cur_down_last
	CALL cs_end
	CALL cs_right
	CALL cs_to_want
	OR A
	POP IX
	RET
cur_down_last:
	SCF
	POP IX
	RET

cur_up:
	PUSH IX
	LD IX,cur_it
	LD HL,(cur_line)
	LD A,H
	OR L
	JR Z,cur_up_first
	CALL cs_home
	CALL cs_left
	CALL cs_home
	CALL cs_to_want
	OR A
	POP IX
	RET
cur_up_first:
	SCF
	POP IX
	RET

cur_doc_start:
	PUSH IX
	LD IX,cur_it
	CALL iter_init
	LD HL,0
	LD (cur_line),HL
	LD (cur_col),HL
	LD (cur_want),HL
	POP IX
	RET

cur_doc_end:
	PUSH IX
	LD IX,cur_it
	CALL iter_seek_end
	LD HL,(doc_newlines)
	LD (cur_line),HL
	CALL cs_line_len
	LD (cur_col),HL
	LD (cur_want),HL
	POP IX
	RET

; HL = line number. Returns A = error (line does not exist), Z on success.
cur_goto_line:
	PUSH IX
	LD IX,cur_it
	PUSH HL
	CALL line_find
	POP HL
	OR A
	JR NZ,cur_goto_line_ret
	LD (cur_line),HL
	LD HL,0
	LD (cur_col),HL
	LD (cur_want),HL
cur_goto_line_ret:
	POP IX
	RET

; ---------------------------------------------------------------- editing at the cursor

; HL = text, BC = length (> 0), outside BANK_WINDOW. Inserts at the cursor and moves the cursor
; past the text. Returns A = error (0 = ok).
ed_insert:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	LD IX,cur_it
	LD (ei_src),HL
	LD (ei_len),BC
	CALL text_nl_tail
	LD (ei_k),DE
	LD (ei_tail),HL
	LD HL,(cur_line)
	LD (ul_line),HL
	CALL line_index_trim
	LD HL,(ei_src)
	LD BC,(ei_len)
	CALL doc_insert
	OR A
	JR NZ,ed_insert_ret
	LD DE,(ei_k)
	LD A,D
	OR E
	JR NZ,ed_insert_nl
	LD HL,(cur_col)
	LD BC,(ei_len)
	ADD HL,BC
	LD (cur_col),HL
	JR ed_insert_want
ed_insert_nl:
	LD HL,(cur_line)
	ADD HL,DE
	LD (cur_line),HL
	LD HL,(ei_tail)
	LD (cur_col),HL
ed_insert_want:
	CALL cs_set_want
	XOR A
ed_insert_ret:
	OR A
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; A = character to insert at the cursor.
ed_insert_char:
	PUSH HL
	PUSH BC
	LD (ei_char),A
	LD HL,ei_char
	LD BC,1
	CALL ed_insert
	POP BC
	POP HL
	RET

; BC = bytes to delete after the cursor (clamped at EOF). The cursor does not move.
ed_delete:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	LD IX,cur_it
	LD (ei_len),BC
	LD HL,(cur_line)
	LD (ul_line),HL
	CALL line_index_trim
	LD BC,(ei_len)
	CALL doc_delete
	OR A
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; Deletes the character under the cursor.
ed_delete_char:
	PUSH BC
	LD BC,1
	CALL ed_delete
	POP BC
	RET

; Deletes the character before the cursor.
ed_backspace:
	PUSH BC
	CALL cur_left
	JR C,ed_backspace_start
	LD BC,1
	CALL ed_delete
	POP BC
	RET
ed_backspace_start:
	XOR A
	POP BC
	RET

; HL = text (may be empty, BC = 0). Inserts a new line above the cursor line; the cursor stays
; on the line it was on, which is now one line further down.
ed_insert_line:
	CALL undo_begin_group
	CALL ed_insert_line_body
	PUSH AF
	CALL undo_end_group
	POP AF
	RET

ed_insert_line_body:
	PUSH BC
	PUSH HL
	CALL cur_home
	POP HL
	POP BC
	LD A,B
	OR C
	JR Z,ed_insert_line_nl
	CALL ed_insert
	OR A
	RET NZ
ed_insert_line_nl:
	LD A,10
	JP ed_insert_char

; Deletes the cursor line including its newline. The cursor ends at the start of the next line.
ed_delete_line:
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH HL
	CALL cur_home
	LD HL,cur_it
	LD DE,tmp_it
	LD BC,IT_SIZE
	LDIR
	LD IX,tmp_it
	LD BC,0
ed_delete_line_scan:
	CALL iter_next
	JR C,ed_delete_line_len
	INC BC
	CP 10
	JR NZ,ed_delete_line_scan
ed_delete_line_len:
	LD A,B
	OR C
	JR Z,ed_delete_line_ret
	CALL ed_delete
ed_delete_line_ret:
	OR A
	POP HL
	POP DE
	POP BC
	POP IX
	RET

; ---------------------------------------------------------------- scrolling

; Adjusts view_top / view_left so the cursor is inside the view_rows x view_cols window.
ed_scroll:
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,(view_rows)
	OR A
	JR NZ,ed_scroll_rows
	INC A
ed_scroll_rows:
	LD C,A
	LD B,0
	LD HL,(cur_line)
	LD DE,(view_top)
	OR A
	SBC HL,DE
	JR C,ed_scroll_up
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR C,ed_scroll_cols		; already inside
	LD HL,(cur_line)
	OR A
	SBC HL,BC
	INC HL
	LD (view_top),HL
	JR ed_scroll_cols
ed_scroll_up:
	LD HL,(cur_line)
	LD (view_top),HL
ed_scroll_cols:
	LD A,(view_cols)
	OR A
	JR NZ,ed_scroll_cols_ok
	INC A
ed_scroll_cols_ok:
	LD C,A
	LD B,0
	LD HL,(cur_col)
	LD DE,(view_left)
	OR A
	SBC HL,DE
	JR C,ed_scroll_left
	PUSH HL
	OR A
	SBC HL,BC
	POP HL
	JR C,ed_scroll_done
	LD HL,(cur_col)
	OR A
	SBC HL,BC
	INC HL
	LD (view_left),HL
	JR ed_scroll_done
ed_scroll_left:
	LD HL,(cur_col)
	LD (view_left),HL
ed_scroll_done:
	POP HL
	POP DE
	POP BC
	RET

; Moves the cursor a window height down/up and scrolls to follow.
ed_page_down:
	PUSH BC
	LD A,(view_rows)
	LD C,A
ed_page_down_loop:
	PUSH BC
	CALL cur_down
	POP BC
	JR C,ed_page_down_done
	DEC C
	JR NZ,ed_page_down_loop
ed_page_down_done:
	CALL ed_scroll
	POP BC
	RET

ed_page_up:
	PUSH BC
	LD A,(view_rows)
	LD C,A
ed_page_up_loop:
	PUSH BC
	CALL cur_up
	POP BC
	JR C,ed_page_up_done
	DEC C
	JR NZ,ed_page_up_loop
ed_page_up_done:
	CALL ed_scroll
	POP BC
	RET

; IX = iterator -> positioned at the first line of the view (for the renderer).
; Returns A = error (0 = ok).
ed_top_iter:
	PUSH HL
	LD HL,(view_top)
	CALL line_find
	POP HL
	RET
