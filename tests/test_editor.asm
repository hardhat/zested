; zested - Phase 2 (editor operations) tests. Run with `make test`.
	include "zos_sys.asm"
	include "zos_err.asm"
	include "defs.asm"

	org 0x4000

test_start:
	CALL DbgSerialOpen
	CALL t_init
	CALL bank_init
	CALL ed_init
	CALL t_free_banks
	LD (tv_base),A
	LD IX,t_iter
	CALL test_cursor
	CALL test_edit
	CALL test_lines
	CALL test_line_index
	CALL test_scroll
	CALL test_delete
	CALL test_delete_big
	CALL test_editor_files
	CALL doc_close
	CALL t_free_banks
	LD HL,tv_base
	LD B,(HL)
	CALL t_eq8
	DB "no OS pages leaked",0
	JP t_finish

	include "debug.asm"
	include "bank.asm"
	include "piece.asm"
	include "iter.asm"
	include "doc.asm"
	include "docedit.asm"
	include "undo.asm"
	include "line.asm"
	include "editor.asm"
	include "undoed.asm"
	include "harness.asm"
	include "edhelpers.asm"

; ---------------------------------------------------------------- helpers

; HL = n (< 1000) -> t_lbuf = "Line NNN" + newline
t_fmt_line:
	PUSH BC
	PUSH DE
	PUSH HL
	LD (tv_fmt),HL
	LD HL,s_linepfx
	LD DE,t_lbuf
	LD BC,5
	LDIR
	LD HL,(tv_fmt)
	LD BC,-100
	CALL t_dig
	LD (t_lbuf + 5),A
	LD BC,-10
	CALL t_dig
	LD (t_lbuf + 6),A
	LD A,L
	ADD A,'0'
	LD (t_lbuf + 7),A
	LD A,10
	LD (t_lbuf + 8),A
	POP HL
	POP DE
	POP BC
	RET
t_dig:
	LD A,'0' - 1
t_dig_loop:
	INC A
	ADD HL,BC
	JR C,t_dig_loop
	SBC HL,BC
	RET

; HL = n: builds n lines "Line NNN" at the end of an empty document.
t_build_lines:
	LD (tv_n),HL
	LD HL,0
	LD (tv_ptr),HL
t_build_lines_loop:
	LD HL,(tv_ptr)
	CALL t_fmt_line
	LD HL,t_lbuf
	LD BC,9
	CALL ed_insert
	CALL t_zero
	DB "build line",0
	LD HL,(tv_ptr)
	INC HL
	LD (tv_ptr),HL
	LD DE,(tv_n)
	OR A
	SBC HL,DE
	JR C,t_build_lines_loop
	RET

; HL = n: goes to line n and expects "Line NNN" there.
t_goto_expect:
	LD D,H
	LD E,L
; HL = line, DE = the number its text shows.
t_goto_text:
	LD (tv_n),HL
	LD (tv_ptr),DE
	LD A,L
	LD (t_ctx),A
	CALL cur_goto_line
	CALL t_zero
	DB "goto line",0
	LD HL,(tv_ptr)
	CALL t_fmt_line
	LD DE,t_lbuf
	LD BC,8
	CALL t_at_cursor
	DB "line text",0
	LD BC,(tv_n)
	CALL t_line_is
	DB "cursor line number",0
	LD A,0xFF
	LD (t_ctx),A
	RET

; HL = piece index -> DE = its length
t_piece_len:
	CALL piece_addr
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	RET

s_linepfx:	DB "Line "
s_t1:		DB "ab",10,"cd",10,10,"ef"
s_sticky:	DB "abcdef",10,"x",10,"abcdefgh"
s_abc:		DB "abc"
s_x:		DB "X"
s_xabc:		DB "Xabc"
s_x_nl_abc:	DB "X",10,"abc"
s_xbc:		DB "Xbc"
s_ab_nl_cd:	DB "ab",10,"cd"
s_abcd:		DB "abcd"
s_l0123:	DB "l0",10,"l1",10,"l2",10,"l3"
s_l0l3:		DB "l0",10,"l3"
s_3:		DB "3"
s_one:		DB "one",10,"two",10,"three"
s_one_x:	DB "one",10,"X",10,"two",10,"three"
s_two:		DB "two"
s_three:	DB "three"
s_one_x_three:	DB "one",10,"X",10,"three"
s_one_x_nl:	DB "one",10,"X",10
s_one_x_nlnl:	DB "one",10,"X",10,10
s_z5:		DB "ZLine 005"
s_q99:		DB "QLine 099"
s_digits:	DB "0123456789"
s_012abc:	DB "012abc3456789"
s_3456789:	DB "3456789"
s_012789:	DB "012789"
s_789:		DB "789"
s_012:		DB "012"
s_456789:	DB "456789"
s_a25:		DB "aaaaaaaaaaaaaaaaaaaaaaaaa"
s_edtxt:	DB "one",10,"two",10,"three",10
s_ed_after:	DB "one",10,"three",10

; ---------------------------------------------------------------- cursor movement

test_cursor:
	CALL t_section
	DB "cursor movement and line tracking",0
	CALL ed_init
	LD HL,s_t1
	LD BC,9
	CALL t_ins
	DB "type text",0
	LD BC,3
	CALL t_line_is
	DB "line after typing",0
	LD BC,2
	CALL t_col_is
	DB "column after typing",0
	LD BC,3
	CALL t_nl_is
	DB "newline count",0
	CALL cur_doc_start
	LD BC,0
	CALL t_line_is
	DB "doc start line",0
	LD BC,0
	CALL t_col_is
	DB "doc start column",0
	CALL cur_right
	CALL t_nc
	DB "right moves",0
	CALL cur_right
	LD BC,2
	CALL t_col_is
	DB "column after two rights",0
	CALL cur_right
	LD BC,1
	CALL t_line_is
	DB "right over a newline: line",0
	LD BC,0
	CALL t_col_is
	DB "right over a newline: column",0
	CALL cur_left
	CALL t_nc
	DB "left moves",0
	LD BC,0
	CALL t_line_is
	DB "left over a newline: line",0
	LD BC,2
	CALL t_col_is
	DB "left over a newline: column is the line length",0
	CALL cur_down
	LD BC,1
	CALL t_line_is
	DB "down: line",0
	LD BC,2
	CALL t_col_is
	DB "down: column",0
	CALL cur_down
	LD BC,2
	CALL t_line_is
	DB "down onto an empty line",0
	LD BC,0
	CALL t_col_is
	DB "empty line column",0
	CALL cur_down
	LD BC,3
	CALL t_line_is
	DB "down again",0
	LD BC,2
	CALL t_col_is
	DB "remembered column restored",0
	CALL cur_down
	CALL t_c
	DB "down on the last line is refused",0
	LD BC,3
	CALL t_line_is
	DB "still on the last line",0
	CALL cur_up
	LD BC,2
	CALL t_line_is
	DB "up: line",0
	CALL cur_up
	LD BC,1
	CALL t_line_is
	DB "up again",0
	LD BC,2
	CALL t_col_is
	DB "up: remembered column",0
	CALL cur_up
	LD BC,0
	CALL t_line_is
	DB "up to the first line",0
	CALL cur_up
	CALL t_c
	DB "up on the first line is refused",0
	CALL cur_home
	LD BC,0
	CALL t_col_is
	DB "home",0
	CALL cur_end
	LD BC,2
	CALL t_col_is
	DB "end",0
	CALL cur_doc_start
	CALL cur_left
	CALL t_c
	DB "left at the document start is refused",0
	CALL cur_doc_end
	LD BC,3
	CALL t_line_is
	DB "doc end line",0
	LD BC,2
	CALL t_col_is
	DB "doc end column",0
	CALL cur_right
	CALL t_c
	DB "right at the document end is refused",0
	LD HL,2
	CALL cur_goto_line
	CALL t_zero
	DB "goto line 2",0
	LD BC,2
	CALL t_line_is
	DB "goto line number",0
	LD HL,3
	CALL cur_goto_line
	LD DE,s_t1 + 7
	LD BC,2
	CALL t_at_cursor
	DB "goto line 3 lands on ef",0
	LD HL,4
	CALL cur_goto_line
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "goto past the last line fails",0
	LD BC,3
	CALL t_line_is
	DB "failed goto leaves the cursor",0

	; the remembered column survives shorter lines
	CALL ed_init
	LD HL,s_sticky
	LD BC,17
	CALL t_ins
	DB "type sticky text",0
	CALL cur_doc_start
	LD B,5
test_cursor_sticky:
	PUSH BC
	CALL cur_right
	POP BC
	DJNZ test_cursor_sticky
	CALL cur_down
	LD BC,1
	CALL t_col_is
	DB "short line clamps the column",0
	CALL cur_down
	LD BC,5
	CALL t_col_is
	DB "column comes back on the next long line",0
	CALL cur_doc_start
	CALL cur_end
	CALL cur_down
	CALL cur_down
	LD BC,8
	CALL t_col_is
	DB "end keeps following the line ends",0
	RET

; ---------------------------------------------------------------- character edits

test_edit:
	CALL t_section
	DB "character insertion and deletion",0
	CALL ed_init
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "type abc",0
	CALL cur_doc_start
	LD A,'X'
	CALL ed_insert_char
	CALL t_zero
	DB "insert a character",0
	LD BC,1
	CALL t_col_is
	DB "column after insert",0
	LD DE,s_xabc
	LD BC,4
	CALL t_doc_is
	DB "text after insert",0
	CALL t_doc_eof
	DB "nothing after the text",0
	LD A,10
	CALL ed_insert_char
	LD BC,1
	CALL t_line_is
	DB "newline moves to the next line",0
	LD BC,0
	CALL t_col_is
	DB "newline resets the column",0
	LD BC,1
	CALL t_nl_is
	DB "newline counted",0
	LD DE,s_x_nl_abc
	LD BC,5
	CALL t_doc_is
	DB "text after newline",0
	CALL ed_backspace
	CALL t_zero
	DB "backspace over a newline",0
	LD BC,0
	CALL t_line_is
	DB "backspace: line",0
	LD BC,1
	CALL t_col_is
	DB "backspace: column",0
	LD BC,0
	CALL t_nl_is
	DB "newline uncounted",0
	LD DE,s_xabc
	LD BC,4
	CALL t_doc_is
	DB "lines joined",0
	CALL ed_delete_char
	CALL t_zero
	DB "delete a character",0
	LD BC,1
	CALL t_col_is
	DB "delete keeps the column",0
	LD DE,s_xbc
	LD BC,3
	CALL t_doc_is
	DB "text after delete",0
	CALL cur_doc_start
	CALL ed_backspace
	CALL t_zero
	DB "backspace at the start does nothing",0
	LD DE,s_xbc
	LD BC,3
	CALL t_doc_is
	DB "text unchanged",0
	CALL cur_doc_end
	CALL ed_delete_char
	CALL t_zero
	DB "delete at the end does nothing",0
	LD DE,s_xbc
	LD BC,3
	CALL t_doc_is
	DB "text unchanged at the end",0

	; delete forward over a newline
	CALL ed_init
	LD HL,s_ab_nl_cd
	LD BC,5
	CALL t_ins
	DB "type two lines",0
	CALL cur_doc_start
	CALL cur_end
	CALL ed_delete_char
	CALL t_zero
	DB "delete a newline",0
	LD BC,0
	CALL t_nl_is
	DB "newline count after deleting it",0
	LD BC,0
	CALL t_line_is
	DB "cursor line unchanged",0
	LD BC,2
	CALL t_col_is
	DB "cursor column unchanged",0
	LD DE,s_abcd
	LD BC,4
	CALL t_doc_is
	DB "joined text",0

	; a multi-line range
	CALL ed_init
	LD HL,s_l0123
	LD BC,11
	CALL t_ins
	DB "type four lines",0
	LD HL,1
	CALL cur_goto_line
	CALL cur_right
	LD BC,6
	CALL ed_delete
	CALL t_zero
	DB "delete across lines",0
	LD BC,1
	CALL t_nl_is
	DB "two newlines removed",0
	LD BC,1
	CALL t_line_is
	DB "cursor line",0
	LD BC,1
	CALL t_col_is
	DB "cursor column",0
	LD DE,s_l0l3
	LD BC,5
	CALL t_doc_is
	DB "text after range delete",0
	LD DE,s_3
	LD BC,1
	CALL t_at_cursor
	DB "cursor sits before the rest",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- line insert / delete

test_lines:
	CALL t_section
	DB "line insertion and deletion",0
	CALL ed_init
	LD HL,s_one
	LD BC,13
	CALL t_ins
	DB "type three lines",0
	LD HL,1
	CALL cur_goto_line
	LD HL,s_x
	LD BC,1
	CALL ed_insert_line
	CALL t_zero
	DB "insert a line",0
	LD DE,s_one_x
	LD BC,15
	CALL t_doc_is
	DB "text after line insert",0
	LD BC,2
	CALL t_line_is
	DB "cursor stays on its line",0
	LD BC,0
	CALL t_col_is
	DB "cursor at column 0",0
	LD DE,s_two
	LD BC,3
	CALL t_at_cursor
	DB "cursor still on two",0
	LD BC,3
	CALL t_nl_is
	DB "three newlines",0
	CALL ed_delete_line
	CALL t_zero
	DB "delete a line",0
	LD DE,s_one_x_three
	LD BC,11
	CALL t_doc_is
	DB "text after line delete",0
	LD BC,2
	CALL t_nl_is
	DB "newline count after line delete",0
	LD DE,s_three
	LD BC,5
	CALL t_at_cursor
	DB "cursor on the following line",0
	CALL ed_delete_line
	CALL t_zero
	DB "delete the last line (no newline)",0
	LD DE,s_one_x_nl
	LD BC,6
	CALL t_doc_is
	DB "text after deleting the last line",0
	LD BC,2
	CALL t_nl_is
	DB "newline count unchanged",0
	LD HL,s_x
	LD BC,0
	CALL ed_insert_line
	CALL t_zero
	DB "insert a blank line",0
	LD DE,s_one_x_nlnl
	LD BC,7
	CALL t_doc_is
	DB "text with a blank line",0
	LD BC,3
	CALL t_line_is
	DB "cursor line after blank line",0
	CALL ed_delete_line
	CALL t_zero
	DB "delete on the empty last line does nothing",0
	LD DE,s_one_x_nlnl
	LD BC,7
	CALL t_doc_is
	DB "text unchanged",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- sparse line index

test_line_index:
	CALL t_section
	DB "sparse line index",0
	CALL ed_init
	LD HL,300
	CALL t_build_lines
	LD BC,1
	CALL t_count_is
	DB "typed lines coalesce into one piece",0
	LD BC,300
	CALL t_nl_is
	DB "300 newlines",0
	LD HL,0
	CALL t_goto_expect
	LD HL,1
	CALL t_goto_expect
	LD HL,15
	CALL t_goto_expect
	LD HL,16
	CALL t_goto_expect
	LD HL,17
	CALL t_goto_expect
	LD HL,299
	CALL t_goto_expect
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "index built up to entry 18",0
	LD HL,31
	CALL t_goto_expect
	LD HL,32
	CALL t_goto_expect
	LD HL,100
	CALL t_goto_expect
	LD HL,300
	CALL cur_goto_line
	CALL t_zero
	DB "the empty last line exists",0
	LD HL,301
	CALL cur_goto_line
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "line 301 does not",0

	; editing invalidates the index from the edit line on
	LD HL,5
	CALL cur_goto_line
	LD A,'Z'
	CALL ed_insert_char
	LD DE,(li_count)
	LD BC,0
	CALL t_eq16
	DB "edit on line 5 empties the index",0
	LD HL,5
	CALL cur_goto_line
	LD DE,s_z5
	LD BC,9
	CALL t_at_cursor
	DB "inserted character is there",0
	LD HL,250
	CALL t_goto_expect
	LD DE,(li_count)
	LD BC,15
	CALL t_eq16
	DB "index rebuilt lazily",0
	LD HL,5
	CALL cur_goto_line
	LD A,10
	CALL ed_insert_char
	CALL t_zero
	DB "split line 5",0
	LD HL,251
	LD DE,250
	CALL t_goto_text
	LD HL,6
	CALL cur_goto_line
	LD DE,s_z5
	LD BC,9
	CALL t_at_cursor
	DB "line 6 is the split-off text",0
	LD HL,299
	CALL cur_goto_line
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "index rebuilt to entry 18",0
	LD HL,100
	CALL cur_goto_line
	LD A,'Q'
	CALL ed_insert_char
	LD DE,(li_count)
	LD BC,6
	CALL t_eq16
	DB "edit on line 100 keeps entries below it",0
	LD HL,299
	CALL cur_goto_line
	LD HL,298
	CALL t_fmt_line
	LD DE,t_lbuf
	LD BC,8
	CALL t_at_cursor
	DB "line 299 after the edits",0
	LD HL,10
	CALL cur_goto_line
	CALL ed_delete_line
	CALL t_zero
	DB "delete line 10",0
	LD BC,300
	CALL t_nl_is
	DB "newline count after delete",0
	LD DE,(li_count)
	LD BC,0
	CALL t_eq16
	DB "delete empties the index",0
	LD HL,250
	CALL t_goto_expect
	LD HL,99
	CALL cur_goto_line
	LD DE,s_q99
	LD BC,9
	CALL t_at_cursor
	DB "line 99 carries the Q",0
	LD HL,100
	CALL t_goto_expect
	RET

; ---------------------------------------------------------------- scrolling

test_scroll:
	CALL t_section
	DB "scrolling",0
	LD A,10
	LD (view_rows),A
	LD A,20
	LD (view_cols),A
	CALL cur_doc_start
	CALL ed_scroll
	LD DE,(view_top)
	LD BC,0
	CALL t_eq16
	DB "top at the start",0
	LD HL,25
	CALL cur_goto_line
	CALL ed_scroll
	LD DE,(view_top)
	LD BC,16
	CALL t_eq16
	DB "scrolling down keeps the cursor on the last row",0
	LD HL,20
	CALL cur_goto_line
	CALL ed_scroll
	LD DE,(view_top)
	LD BC,16
	CALL t_eq16
	DB "cursor inside the view does not scroll",0
	LD HL,3
	CALL cur_goto_line
	CALL ed_scroll
	LD DE,(view_top)
	LD BC,3
	CALL t_eq16
	DB "scrolling up puts the cursor on the first row",0
	CALL ed_page_down
	LD BC,13
	CALL t_line_is
	DB "page down moves a window height",0
	LD DE,(view_top)
	LD BC,4
	CALL t_eq16
	DB "page down scrolls to follow",0
	CALL ed_page_up
	LD BC,3
	CALL t_line_is
	DB "page up moves back",0
	LD DE,(view_top)
	LD BC,3
	CALL t_eq16
	DB "page up scrolls to follow",0
	LD HL,20
	CALL cur_goto_line
	CALL ed_scroll
	LD IX,t_iter
	CALL ed_top_iter
	CALL t_zero
	DB "iterator at the top line",0
	LD HL,11
	CALL t_fmt_line
	LD DE,t_lbuf
	LD BC,8
	CALL t_iter_eq
	DB "top line text",0
	LD HL,295
	CALL cur_goto_line
	CALL ed_page_down
	LD BC,300
	CALL t_line_is
	DB "page down stops at the last line",0
	LD DE,(view_top)
	LD BC,291
	CALL t_eq16
	DB "view shows the last line",0
	; horizontal
	CALL cur_doc_start
	CALL cur_end
	LD HL,s_a25
	LD BC,25
	CALL t_ins
	DB "make a long line",0
	CALL ed_scroll
	LD DE,(view_left)
	LD BC,14
	CALL t_eq16
	DB "scrolled right to keep the cursor visible",0
	CALL cur_home
	CALL ed_scroll
	LD DE,(view_left)
	LD BC,0
	CALL t_eq16
	DB "scrolled back left",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- piece-level deletion

test_delete:
	CALL t_section
	DB "range deletion",0
	CALL ed_init
	LD HL,s_digits
	LD BC,10
	CALL t_ins
	DB "type digits",0
	CALL cur_doc_start
	CALL cur_right
	CALL cur_right
	CALL cur_right
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "insert abc in the middle",0
	LD BC,3
	CALL t_count_is
	DB "three pieces",0
	LD DE,s_012abc
	LD BC,13
	CALL t_doc_is
	DB "text with abc",0
	CALL cur_left
	CALL cur_left
	CALL cur_left
	LD BC,3
	CALL ed_delete
	CALL t_zero
	DB "delete abc again",0
	LD BC,1
	CALL t_count_is
	DB "pieces merge back into one",0
	LD DE,s_digits
	LD BC,10
	CALL t_doc_is
	DB "digits restored",0
	LD BC,3
	CALL t_col_is
	DB "cursor column",0
	LD DE,s_3456789
	LD BC,7
	CALL t_at_cursor
	DB "cursor is where the deletion was",0
	LD BC,4
	CALL ed_delete
	CALL t_zero
	DB "delete 4 bytes",0
	LD BC,2
	CALL t_count_is
	DB "two pieces",0
	LD DE,s_012789
	LD BC,6
	CALL t_doc_is
	DB "text after the middle delete",0
	LD DE,s_789
	LD BC,3
	CALL t_at_cursor
	DB "cursor before 789",0
	LD BC,100
	CALL ed_delete
	CALL t_zero
	DB "delete past the end",0
	LD DE,s_012
	LD BC,3
	CALL t_doc_is
	DB "clamped at the end",0
	CALL t_doc_eof
	DB "nothing left after 012",0
	LD BC,5
	CALL ed_delete
	CALL t_zero
	DB "delete at the end does nothing",0
	; start of a piece
	CALL ed_init
	LD HL,s_digits
	LD BC,10
	CALL t_ins
	DB "type digits again",0
	CALL cur_doc_start
	LD BC,4
	CALL ed_delete
	CALL t_zero
	DB "delete at the start of a piece",0
	LD BC,1
	CALL t_count_is
	DB "one piece",0
	LD DE,s_456789
	LD BC,6
	CALL t_doc_is
	DB "text after front delete",0
	CALL cur_doc_start
	LD BC,100
	CALL ed_delete
	CALL t_zero
	DB "delete everything",0
	LD BC,0
	CALL t_count_is
	DB "no pieces left",0
	LD BC,0
	CALL t_nl_is
	DB "no newlines left",0
	LD BC,0
	CALL t_doc_is
	DB "empty document reads nothing",0
	CALL t_doc_eof
	DB "empty document",0
	LD A,'k'
	CALL ed_insert_char
	CALL t_zero
	DB "typing into the emptied document works",0
	LD BC,1
	CALL t_count_is
	DB "one piece again",0
	CALL doc_close
	RET

test_delete_big:
	CALL t_section
	DB "range deletion across banks",0
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_delete_big_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_delete_big_build
	LD BC,1
	CALL t_count_is
	DB "one piece",0
	LD BC,160
	CALL t_nl_is
	DB "160 newlines",0
	LD IX,cur_it
	LD HL,0
	LD DE,16000
	CALL iter_seek
	LD BC,1000
	CALL doc_delete
	CALL t_zero
	DB "delete 1000 bytes over a bank boundary",0
	LD BC,2
	CALL t_count_is
	DB "the piece is split in two",0
	LD BC,156
	CALL t_nl_is
	DB "four newlines removed",0
	LD HL,0
	CALL t_piece_len
	LD BC,16000
	CALL t_eq16
	DB "first piece length",0
	LD HL,1
	CALL t_piece_len
	LD BC,23160
	CALL t_eq16
	DB "second piece length",0
	LD IX,t_iter
	LD HL,0
	LD DE,15990
	CALL iter_seek
	LD DE,t_blk + 177
	LD BC,10
	CALL t_iter_eq
	DB "bytes before the hole",0
	LD DE,t_blk + 183
	LD BC,10
	CALL t_iter_eq
	DB "bytes after the hole",0
	; the cursor iterator was left at the deletion point
	LD DE,t_blk + 183
	LD BC,10
	CALL t_at_cursor
	DB "iterator left at the deletion point",0
	LD IX,cur_it
	CALL iter_init
	LD BC,0xFFFF
	CALL doc_delete
	CALL t_zero
	DB "delete a 64K-1 range",0
	LD BC,0
	CALL t_count_is
	DB "the whole document is gone",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- files

f_ed:		DB "H:/zested_ed.txt",0
f_ed_big:	DB "H:/zested_ed_big.bin",0

test_editor_files:
	CALL t_section
	DB "editor load and save",0
	CALL ed_init
	LD HL,s_edtxt
	LD BC,14
	CALL t_ins
	DB "type a file",0
	LD BC,f_ed
	CALL ed_save
	CALL t_zero
	DB "save",0
	LD BC,f_ed
	CALL ed_load
	CALL t_zero
	DB "load",0
	LD BC,3
	CALL t_nl_is
	DB "newlines counted while loading",0
	LD BC,0
	CALL t_line_is
	DB "cursor reset to the start",0
	LD HL,2
	CALL cur_goto_line
	LD DE,s_three
	LD BC,5
	CALL t_at_cursor
	DB "goto in a loaded file",0
	LD HL,1
	CALL cur_goto_line
	CALL ed_delete_line
	CALL t_zero
	DB "delete a line of the loaded file",0
	LD DE,s_ed_after
	LD BC,10
	CALL t_doc_is
	DB "edited loaded text",0
	LD BC,f_ed
	CALL ed_save
	CALL t_zero
	DB "save the edit",0

	; a multi-bank file: newlines are counted across banks
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_editor_files_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_editor_files_build
	LD BC,f_ed_big
	CALL ed_save
	CALL t_zero
	DB "save the big file",0
	LD BC,f_ed_big
	CALL ed_load
	CALL t_zero
	DB "load the big file",0
	LD BC,160
	CALL t_nl_is
	DB "newlines counted over three banks",0
	LD HL,100
	CALL cur_goto_line
	CALL t_zero
	DB "goto line 100 in the loaded file",0
	LD BC,100
	CALL t_line_is
	DB "line number",0
	; line 100 starts right after the 100th newline: block 99 (index 9 of it) + 1
	LD DE,t_blk + 10
	LD BC,20
	CALL t_at_cursor
	DB "line 100 text",0
	CALL doc_close
	RET

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
