; zested - Phase 6 (optimization) tests. Run with `make test`.
; Covers the backward iteration primitives, the line scanner, the chunked search_back and
; cursor movement, the typing and backspace fast paths, and the undo log squeezing.
	include "zos_sys.asm"
	include "zos_err.asm"
	include "defs.asm"

	org 0x4000

DEFC T_TOTAL = 17571		; length of the document built by test_back

test_start:
	CALL DbgSerialOpen
	CALL t_init
	CALL bank_init
	CALL ed_init
	CALL t_free_banks
	LD (tv_base),A
	LD IX,t_iter
	CALL t_fill_blk
	CALL test_typing
	CALL test_tail_delete
	CALL test_log_squeeze
	CALL test_back
	CALL test_long_line
	CALL test_search_back
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
	include "compact.asm"
	include "line.asm"
	include "editor.asm"
	include "undoed.asm"
	include "search.asm"
	include "harness.asm"
	include "edhelpers.asm"

; ---------------------------------------------------------------- helpers

t_reset:
	CALL doc_close
	JP ed_init

t_undo:
	CALL ed_undo
	JP t_zero

t_redo:
	CALL ed_redo
	JP t_zero

t_undo_none:
	CALL ed_undo
	LD B,ERR_NO_SUCH_ENTRY
	JP t_eq8

t_pat:
	CALL search_set
	JP t_zero

; HL = text, BC = length: the document must be exactly this text. Inline message.
t_doc_exact:
	LD (tv_ptr),HL
	LD (tv_n),BC
	LD IX,t_iter
	CALL iter_init
	LD DE,(tv_ptr)
	LD BC,(tv_n)
	CALL t_iter_eq
	DB "document text",0
	CALL iter_peek
	JP t_c

; B = number of 200-byte blocks of 'x' inserted at the cursor.
t_xblocks:
	LD A,B
	LD (tv_a + 3),A
t_xblocks_loop:
	LD HL,t_xs
	LD BC,200
	CALL ed_insert
	CALL t_zero
	DB "x block",0
	LD HL,tv_a + 3
	DEC (HL)
	JR NZ,t_xblocks_loop
	RET

; HL = position: puts the cursor iterator there (the line/column bookkeeping is not updated).
t_goto:
	PUSH IX
	LD IX,cur_it
	XOR A
	CALL doc_locate
	POP IX
	RET

; DE = length of the document.
t_length:
	LD IX,t_iter
	JP t_doc_length

; HL = checksum of the document text.
t_sum:
	LD IX,t_iter
	CALL iter_init
	LD HL,0
t_sum_loop:
	CALL iter_next
	RET C
	LD D,H
	LD E,L
	ADD HL,HL
	ADD HL,DE
	LD E,A
	LD D,0
	ADD HL,DE
	JR t_sum_loop

s_hello:	DB "hello"
s_hel:		DB "hel"
s_hell:		DB "hell"
s_helo:		DB "helo"
s_hellp:	DB "hellp"
s_abc:		DB "abc"
s_aXYbc:	DB "aXYbc"
s_heXlloY:	DB "heXlloY"
s_heXllo:	DB "heXllo"
s_a_nl_b:	DB "a",10,"b"
s_ab_nl_cd:	DB "ab",10,"cd"
s_ab:		DB "ab"
s_tail:		DB "tail"
s_needle:	DB "needle"
s_xn:		DB "xn"
s_nl:		DB 10
s_end:		DB "end"
s_XY:		DB "XY"
s_xs_hdr:	DB 0
t_xs:		DEFS 200,'x'

; ---------------------------------------------------------------- typing

test_typing:
	CALL t_section
	DB "typing grows the previous piece",0
	CALL t_reset
	LD A,200
	LD (tv_a),A
test_typing_loop:
	LD A,'k'
	CALL ed_insert_char
	CALL t_zero
	DB "type a character",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_typing_loop
	LD BC,1
	CALL t_count_is
	DB "200 typed characters are one piece",0
	CALL t_length
	LD BC,200
	CALL t_eq16
	DB "200 characters in the document",0
	LD BC,0
	LD DE,200
	CALL t_cursor_is
	DB "cursor after the typing",0
	CALL t_undo
	DB "undo the typing",0
	CALL t_length
	LD BC,0
	CALL t_eq16
	DB "one undo removes all of it",0
	CALL t_undo_none
	DB "nothing else to undo",0
	CALL t_redo
	DB "redo the typing",0
	CALL t_length
	LD BC,200
	CALL t_eq16
	DB "all characters are back",0
	LD BC,1
	CALL t_count_is
	DB "and in one piece",0

	; typing in the middle of a piece
	CALL t_reset
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "type abc",0
	CALL cur_left
	CALL cur_left
	LD A,'X'
	CALL ed_insert_char
	CALL t_zero
	DB "type X",0
	LD A,'Y'
	CALL ed_insert_char
	CALL t_zero
	DB "type Y",0
	LD HL,s_aXYbc
	LD BC,5
	CALL t_doc_exact
	DB "aXYbc",0
	LD BC,3
	CALL t_count_is
	DB "split into three pieces",0
	CALL t_undo
	DB "undo XY",0
	LD HL,s_abc
	LD BC,3
	CALL t_doc_exact
	DB "XY went in one step",0
	CALL t_undo
	DB "undo abc",0
	CALL t_length
	LD BC,0
	CALL t_eq16
	DB "empty",0
	CALL t_redo
	DB "redo abc",0
	CALL t_redo
	DB "redo XY",0
	LD HL,s_aXYbc
	LD BC,5
	CALL t_doc_exact
	DB "aXYbc again",0

	; typing a newline and text after it
	CALL t_reset
	LD A,'a'
	CALL ed_insert_char
	LD A,10
	CALL ed_insert_char
	LD A,'b'
	CALL ed_insert_char
	LD HL,s_a_nl_b
	LD BC,3
	CALL t_doc_exact
	DB "a newline b",0
	LD BC,1
	CALL t_nl_is
	DB "one newline counted",0
	LD BC,1
	LD DE,1
	CALL t_cursor_is
	DB "cursor on line 1",0
	CALL t_undo
	DB "undo the typing",0
	LD BC,0
	CALL t_nl_is
	DB "no newline left",0
	CALL t_undo_none
	DB "one step",0

	; typing a run, moving away and typing again are two steps
	CALL t_reset
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "type abc",0
	CALL cur_doc_start
	LD A,'X'
	CALL ed_insert_char
	LD A,'Y'
	CALL ed_insert_char
	CALL cur_doc_end
	LD A,'Z'
	CALL ed_insert_char
	CALL t_undo
	DB "undo Z",0
	CALL t_undo
	DB "undo XY",0
	LD HL,s_abc
	LD BC,3
	CALL t_doc_exact
	DB "abc remains",0
	CALL t_undo
	DB "undo abc",0
	CALL t_undo_none
	DB "three steps in total",0

	; text added elsewhere in between: the add store is not contiguous any more
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL cur_left
	CALL cur_left
	CALL cur_left
	LD A,'X'
	CALL ed_insert_char
	CALL t_zero
	DB "type X inside",0
	CALL cur_doc_end
	LD A,'Y'
	CALL ed_insert_char
	CALL t_zero
	DB "type Y at the end",0
	LD HL,s_heXlloY
	LD BC,7
	CALL t_doc_exact
	DB "heXlloY",0
	CALL t_undo
	DB "undo Y",0
	LD HL,s_heXllo
	LD BC,6
	CALL t_doc_exact
	DB "heXllo",0
	CALL t_undo
	DB "undo X",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- tail deletion

test_tail_delete:
	CALL t_section
	DB "deleting the end of a piece",0
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL ed_backspace
	CALL t_zero
	DB "backspace",0
	CALL ed_backspace
	CALL t_zero
	DB "backspace again",0
	LD HL,s_hel
	LD BC,3
	CALL t_doc_exact
	DB "hel",0
	LD BC,1
	CALL t_count_is
	DB "still one piece",0
	LD BC,0
	LD DE,3
	CALL t_cursor_is
	DB "cursor at the end",0
	CALL t_undo
	DB "undo one backspace",0
	LD HL,s_hell
	LD BC,4
	CALL t_doc_exact
	DB "hell",0
	CALL t_undo
	DB "undo the other",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello again",0
	CALL t_redo
	DB "redo",0
	CALL t_redo
	DB "redo",0
	LD HL,s_hel
	LD BC,3
	CALL t_doc_exact
	DB "hel again",0

	; typing after a backspace does not join the old add text
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL ed_backspace
	LD A,'p'
	CALL ed_insert_char
	LD HL,s_hellp
	LD BC,5
	CALL t_doc_exact
	DB "hellp",0
	CALL t_undo
	DB "undo p",0
	LD HL,s_hell
	LD BC,4
	CALL t_doc_exact
	DB "hell",0
	CALL t_undo
	DB "undo the backspace",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0

	; forward delete of the last character of a piece
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL cur_left
	CALL ed_delete_char
	CALL t_zero
	DB "delete the o",0
	LD HL,s_hell
	LD BC,4
	CALL t_doc_exact
	DB "hell",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "cursor stays",0
	CALL t_undo
	DB "undo",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0

	; a deletion that runs past the end of the piece
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL cur_left
	CALL cur_left
	LD BC,10
	CALL ed_delete
	CALL t_zero
	DB "delete past the end",0
	LD HL,s_hel
	LD BC,3
	CALL t_doc_exact
	DB "hel",0
	CALL t_undo
	DB "undo",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0

	; a deletion in the middle of a piece
	CALL t_reset
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL cur_left
	CALL cur_left
	CALL cur_left
	CALL ed_delete_char
	CALL t_zero
	DB "delete a middle l",0
	LD HL,s_helo
	LD BC,4
	CALL t_doc_exact
	DB "helo",0
	LD BC,2
	CALL t_count_is
	DB "split in two",0
	CALL t_undo
	DB "undo",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0

	; newlines in the deleted tail
	CALL t_reset
	LD HL,s_ab_nl_cd
	LD BC,5
	CALL t_ins
	DB "type ab newline cd",0
	CALL ed_backspace
	CALL ed_backspace
	CALL ed_backspace
	LD HL,s_ab
	LD BC,2
	CALL t_doc_exact
	DB "ab",0
	LD BC,0
	CALL t_nl_is
	DB "no newline left",0
	LD BC,0
	LD DE,2
	CALL t_cursor_is
	DB "cursor at the end of line 0",0
	CALL t_undo
	DB "undo",0
	CALL t_undo
	DB "undo",0
	CALL t_undo
	DB "undo",0
	LD HL,s_ab_nl_cd
	LD BC,5
	CALL t_doc_exact
	DB "text restored",0
	LD BC,1
	CALL t_nl_is
	DB "newline restored",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- undo log squeezing

test_log_squeeze:
	CALL t_section
	DB "undo history beyond the log size",0
	CALL t_reset
	LD HL,300
	LD (tv_ptr),HL
test_log_fill:
	CALL cur_doc_start
	LD A,(tv_ptr)
	AND 15
	ADD A,'a'
	CALL ed_insert_char
	CALL t_zero
	DB "separate insertion",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_log_fill
	CALL t_length
	LD BC,300
	CALL t_eq16
	DB "300 characters",0
	CALL t_sum
	LD (tv_ck),HL
	LD HL,0
	LD (tv_n),HL
test_log_undo:
	CALL ed_undo
	OR A
	JR NZ,test_log_undone
	LD HL,(tv_n)
	INC HL
	LD (tv_n),HL
	JR test_log_undo
test_log_undone:
	LD B,ERR_NO_SUCH_ENTRY
	CALL t_eq8
	DB "history ends",0
	LD HL,(tv_n)
	LD DE,60
	OR A
	SBC HL,DE
	CALL t_nc
	DB "at least 60 steps were kept",0
	LD HL,(tv_n)
	LD DE,300
	OR A
	SBC HL,DE
	CALL t_c
	DB "older steps were dropped",0
	CALL t_length
	LD HL,300
	LD BC,(tv_n)
	OR A
	SBC HL,BC
	LD B,H
	LD C,L
	CALL t_eq16
	DB "the document matches the steps undone",0
	LD HL,(tv_n)
	LD (tv_ptr),HL
test_log_redo:
	CALL t_redo
	DB "redo",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_log_redo
	CALL t_sum
	EX DE,HL
	LD HL,(tv_ck)
	LD B,H
	LD C,L
	CALL t_eq16
	DB "with the same content",0
	CALL t_length
	LD BC,300
	CALL t_eq16
	DB "everything is back",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- backward iteration

; HL = position P: from the end, iter_back(T_TOTAL - P) must land exactly on P.
t_back_check:
	LD (tv_ptr),HL
	LD IX,t_iter
	CALL iter_seek_end
	LD HL,T_TOTAL
	LD DE,(tv_ptr)
	OR A
	SBC HL,DE
	LD B,H
	LD C,L
	CALL iter_back
	CALL t_nc
	DB "iter_back reaches the target",0
	CALL doc_position
	EX DE,HL
	LD BC,(tv_ptr)
	CALL t_eq16
	DB "iter_back lands on the right offset",0
	CALL iter_peek
	LD (tv_a),A
	LD IX,find_it
	LD HL,(tv_ptr)
	XOR A
	CALL doc_locate
	CALL iter_peek
	LD B,A
	LD A,(tv_a)
	CALL t_eq8
	DB "byte at the landing offset",0
	RET

test_back:
	CALL t_section
	DB "backward iteration",0
	CALL t_reset
	LD A,70
	LD (tv_a + 2),A
test_back_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build",0
	LD HL,tv_a + 2
	DEC (HL)
	JR NZ,test_back_build
	; fragment it: +2 at 1000, -3 at 9000, +2 at 16000
	LD HL,1000
	CALL t_goto
	LD HL,s_ab
	LD BC,2
	CALL t_ins
	DB "insert at 1000",0
	LD HL,9000
	CALL t_goto
	LD BC,3
	CALL ed_delete
	CALL t_zero
	DB "delete at 9000",0
	LD HL,16000
	CALL t_goto
	LD HL,s_XY
	LD BC,2
	CALL t_ins
	DB "insert at 16000",0
	CALL t_length
	LD BC,T_TOTAL
	CALL t_eq16
	DB "document length",0
	LD HL,0
	CALL t_back_check
	LD HL,1
	CALL t_back_check
	LD HL,250
	CALL t_back_check
	LD HL,999
	CALL t_back_check
	LD HL,1000
	CALL t_back_check
	LD HL,1001
	CALL t_back_check
	LD HL,1002
	CALL t_back_check
	LD HL,8000
	CALL t_back_check
	LD HL,9000
	CALL t_back_check
	LD HL,15999
	CALL t_back_check
	LD HL,16000
	CALL t_back_check
	LD HL,16001
	CALL t_back_check
	LD HL,16002
	CALL t_back_check
	LD HL,17000
	CALL t_back_check
	LD HL,17570
	CALL t_back_check
	; around the 16 KB bank boundary of the add store
	LD HL,16370
	LD (tv_n),HL
test_back_bank:
	LD HL,(tv_n)
	CALL t_back_check
	LD HL,(tv_n)
	INC HL
	LD (tv_n),HL
	LD DE,16400
	OR A
	SBC HL,DE
	JR C,test_back_bank

	; more than is there: stops at the start
	LD IX,t_iter
	CALL iter_seek_end
	LD BC,T_TOTAL + 1
	CALL iter_back
	CALL t_c
	DB "iter_back past the start reports it",0
	CALL doc_position
	EX DE,HL
	LD BC,0
	CALL t_eq16
	DB "and stays at the start",0
	LD IX,t_iter
	CALL iter_seek_end
	LD BC,0
	CALL iter_back
	CALL t_nc
	DB "moving back nothing",0
	CALL iter_peek
	CALL t_c
	DB "still at the end",0

	; iter_chunk_back
	LD IX,t_iter
	LD HL,499
	XOR A
	CALL doc_locate
	CALL iter_peek
	LD (tv_a),A
	LD IX,find_it
	LD HL,500
	XOR A
	CALL doc_locate
	CALL iter_chunk_back
	PUSH AF
	LD A,(HL)
	LD (tv_a + 1),A
	LD (tv_n),BC
	POP AF
	CALL t_nc
	DB "chunk_back inside a piece",0
	LD A,(tv_a + 1)
	LD B,A
	LD A,(tv_a)
	CALL t_eq8
	DB "chunk_back points at the previous byte",0
	LD HL,(tv_n)
	LD A,H
	OR L
	CALL t_nz
	DB "chunk_back is not empty",0
	LD HL,(tv_n)
	LD DE,501
	OR A
	SBC HL,DE
	CALL t_c
	DB "chunk_back stays inside the piece",0
	LD IX,find_it
	LD HL,1000
	XOR A
	CALL doc_locate
	CALL iter_chunk_back
	CALL t_c
	DB "no chunk at a piece start",0
	CALL iter_seek_end
	CALL iter_chunk_back
	CALL t_c
	DB "no chunk at the end",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- lines and cursor movement

test_long_line:
	CALL t_section
	DB "scanning long lines",0
	CALL t_reset
	LD B,100
	CALL t_xblocks
	LD HL,s_nl
	LD BC,1
	CALL t_ins
	DB "newline",0
	LD HL,s_tail
	LD BC,4
	CALL t_ins
	DB "tail",0
	CALL cur_doc_start
	CALL cur_end
	LD BC,0
	LD DE,20000
	CALL t_cursor_is
	DB "cur_end on a 20000 column line",0
	CALL cur_home
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cur_home comes back",0
	CALL cur_down
	LD BC,1
	LD DE,0
	CALL t_cursor_is
	DB "down to line 1",0
	CALL cur_end
	LD BC,1
	LD DE,4
	CALL t_cursor_is
	DB "end of tail",0
	CALL cur_doc_end
	CALL cur_up
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "up keeps the wanted column",0
	CALL cur_end
	CALL cur_down
	LD BC,1
	LD DE,4
	CALL t_cursor_is
	DB "down clamps to the short line",0
	CALL cur_home
	CALL cur_left
	LD BC,0
	LD DE,20000
	CALL t_cursor_is
	DB "left over the newline finds the column",0
	LD IX,cur_it
	LD BC,10
	CALL iter_scan_line
	LD A,H
	OR L
	CALL t_z
	DB "scan stops at a newline",0

	; limits
	CALL cur_doc_start
	LD IX,cur_it
	LD BC,300
	CALL iter_scan_line
	EX DE,HL
	LD BC,300
	CALL t_eq16
	DB "scan honours the limit",0
	LD BC,0xFFFF
	CALL iter_scan_line
	EX DE,HL
	LD BC,19700
	CALL t_eq16
	DB "scan runs to the newline",0
	LD BC,5
	CALL iter_scan_line
	LD A,H
	OR L
	CALL t_z
	DB "nothing more before the newline",0
	CALL cur_doc_end
	LD IX,cur_it
	LD BC,5
	CALL iter_scan_line
	LD A,H
	OR L
	CALL t_z
	DB "nothing at the end of the document",0

	; the same through a fragmented line
	LD HL,5000
	CALL t_goto
	LD HL,s_ab
	LD BC,2
	CALL ed_insert
	CALL t_zero
	DB "insert in the long line",0
	LD HL,12000
	CALL t_goto
	LD BC,1
	CALL ed_delete
	CALL t_zero
	DB "delete in the long line",0
	CALL cur_doc_start
	CALL cur_end
	LD BC,0
	LD DE,20001
	CALL t_cursor_is
	DB "cur_end on the fragmented line",0
	CALL cur_home
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cur_home on the fragmented line",0
	CALL cur_doc_end
	CALL cur_home
	CALL cur_left
	LD BC,0
	LD DE,20001
	CALL t_cursor_is
	DB "column found across pieces",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- search backwards

test_search_back:
	CALL t_section
	DB "searching backwards through big documents",0
	CALL t_reset
	LD HL,s_needle
	LD BC,6
	CALL t_ins
	DB "first needle",0
	LD B,81
	CALL t_xblocks
	LD HL,t_xs
	LD BC,175
	CALL t_ins
	DB "x run",0
	LD HL,s_needle
	LD BC,6
	CALL t_ins
	DB "second needle, across the bank boundary",0
	LD B,15
	CALL t_xblocks
	LD HL,s_nl
	LD BC,1
	CALL t_ins
	DB "newline",0
	LD HL,s_end
	LD BC,3
	CALL t_ins
	DB "end",0
	; split the x run into several pieces
	LD HL,8000
	CALL t_goto
	LD HL,s_XY
	LD BC,2
	CALL ed_insert
	CALL t_zero
	DB "split the x run",0
	LD BC,2
	CALL ed_delete
	CALL t_zero
	DB "and remove two x after it",0
	CALL cur_doc_end
	LD HL,s_needle
	LD BC,6
	CALL t_pat
	DB "pattern",0
	CALL ed_find_prev
	CALL t_zero
	DB "find the second needle",0
	LD BC,0
	LD DE,16381
	CALL t_cursor_is
	DB "it is on line 0, column 16381",0
	CALL ed_find_prev
	CALL t_zero
	DB "find the first needle",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "it is at the start",0
	CALL ed_find_prev
	LD B,ERR_NO_SUCH_ENTRY
	CALL t_eq8
	DB "no needle before the first",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "the cursor did not move",0

	; many false starts: every x is a candidate for "xn"
	CALL cur_doc_end
	LD HL,s_xn
	LD BC,2
	CALL t_pat
	DB "pattern xn",0
	CALL ed_find_prev
	CALL t_zero
	DB "find xn",0
	LD BC,0
	LD DE,16380
	CALL t_cursor_is
	DB "it is just before the second needle",0
	CALL ed_find_prev
	LD B,ERR_NO_SUCH_ENTRY
	CALL t_eq8
	DB "there is no other xn",0

	; the newline count is right when the match is on an earlier line
	CALL t_reset
	LD HL,s_needle
	LD BC,6
	CALL t_ins
	DB "needle",0
	LD HL,s_nl
	LD BC,1
	CALL t_ins
	DB "newline",0
	LD B,3
	CALL t_xblocks
	LD HL,s_nl
	LD BC,1
	CALL t_ins
	DB "newline",0
	CALL cur_doc_end
	LD HL,s_needle
	LD BC,6
	CALL t_pat
	DB "pattern",0
	CALL ed_find_prev
	CALL t_zero
	DB "find across lines",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "line 0 column 0",0

	; the newline right behind the match region is counted
	CALL t_reset
	LD HL,s_needle
	LD BC,6
	CALL t_ins
	DB "needle",0
	LD HL,s_nl
	LD BC,1
	CALL t_ins
	DB "newline",0
	LD HL,t_xs
	LD BC,1
	CALL t_ins
	DB "x",0
	CALL cur_doc_end
	LD HL,s_needle
	LD BC,6
	CALL t_pat
	DB "pattern",0
	CALL ed_find_prev
	CALL t_zero
	DB "find on the line above",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "line 0 column 0 again",0
	CALL doc_close
	RET
