; zested - Phase 3 (search and replace) tests. Run with `make test`.
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
	CALL test_find
	CALL test_find_lines
	CALL test_find_pieces
	CALL test_find_banks
	CALL test_replace
	CALL test_replace_all
	CALL test_replace_all_big
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
	include "line.asm"
	include "editor.asm"
	include "search.asm"
	include "harness.asm"
	include "edhelpers.asm"

; ---------------------------------------------------------------- helpers

; HL = pattern, BC = length: search_set, expecting success. Inline message.
t_pat:
	CALL search_set
	JP t_zero

; HL = text, BC = length: replace_set, expecting success. Inline message.
t_rep:
	CALL replace_set
	JP t_zero

; BC = expected line, then column in the following t_col_is; convenience for both at once.
; Expects the cursor at line BC / column DE (inline message shared by both checks).
t_cursor_is:
	POP HL
	LD (t_msg),HL
	CALL t_skip
	LD (t_ret),HL
	LD HL,(cur_line)
	OR A
	SBC HL,BC
	JR NZ,t_cursor_bad
	LD HL,(cur_col)
	OR A
	SBC HL,DE
	JR NZ,t_cursor_bad
	CALL t_count
	LD HL,(t_ret)
	PUSH HL
	RET
t_cursor_bad:
	CALL t_count
	LD HL,(t_msg)
	CALL t_failhdr
	LD HL,t_s_got
	CALL DbgStr
	LD HL,(cur_line)
	CALL DbgHL
	LD A,','
	CALL DbgSerial
	LD HL,(cur_col)
	CALL DbgHL
	LD HL,t_s_exp
	CALL DbgStr
	CALL DbgBC
	LD A,','
	CALL DbgSerial
	CALL DbgDE
	CALL t_nl
	LD HL,(t_ret)
	PUSH HL
	RET

; A = expected error code: the last search must have failed with it. Inline message.
t_not_found:
	LD B,ERR_NO_SUCH_ENTRY
	JP t_eq8

; The count ed_replace_all returned in HL was saved in tv_n; BC = expected.
t_repl_count:
	LD DE,(tv_n)
	JP t_eq16

; IX = t_iter, counts the bytes of the whole document into DE.
t_doc_length:
	CALL iter_init
	LD DE,0
t_doc_length_loop:
	CALL iter_next
	RET C
	INC DE
	JR t_doc_length_loop

s_doc1:		DB "one two three two one"
s_two:		DB "two"
s_one:		DB "one"
s_aaaab:	DB "aaaab"
s_aab:		DB "aab"
s_long:		DB "one two three two one and more"
s_doc2:		DB "alpha",10,"beta",10,"gamma",10,"delta beta",10
s_beta:		DB "beta"
s_a_nl_b:	DB "a",10,"b"
s_nl_ge:	DB 10,"ga"
s_nl:		DB 10
s_mov:		DB "MOV HL,zzzz"
s_1234:		DB "1234"
s_tail:		DB " ; end"
s_hl1234:	DB "HL,1234"
s_l12:		DB "L,12"
s_edited:	DB "MOV HL,99 ; end"
s_99:		DB "HL,99"
s_bpat:		DB 67,68,69,70,71,72
s_200:		DB 200
s_foo_bar_foo:	DB "foo bar foo"
s_foo:		DB "foo"
s_quux:		DB "quux"
s_quux_bar_foo:	DB "quux bar foo"
s_quux_bar_quux:DB "quux bar quux"
s_bar_sp:	DB "bar "
s_bar:		DB "bar"
s_foo_sp:	DB "foo "
s_bar_sp2:	DB "bar "
s_quux_quux:	DB "quux quux"
s_x_nl_y:	DB "x",10,"y"
s_x_nl_y_quux:	DB "x",10,"y quux"
s_a_nl_b_only:	DB "a",10,"b"
s_a_sp_b:	DB "a b"
s_foo3:		DB "foo bar foo baz foo"
s_X:		DB "X"
s_x_bar_x_baz_x:DB "X bar X baz X"
s_aaa:		DB "aaa"
s_aa:		DB "aa"
s_b:		DB "b"
s_ab:		DB "ab"
s_lines3:	DB "a",10,"b",10,"c",10
s_lines3_sp:	DB "a b c "
s_sp:		DB " "
s_xaxbx:	DB "xaxbx"
s_x:		DB "x"
s_yy:		DB "yy"
s_bar_sp_a:	DB "a"

; ---------------------------------------------------------------- basic searching

test_find:
	CALL t_section
	DB "search: forward and backward",0
	CALL ed_init
	LD HL,s_doc1
	LD BC,21
	CALL t_ins
	DB "type text",0
	CALL cur_doc_start
	LD HL,s_two
	LD BC,3
	CALL t_pat
	DB "set pattern",0
	CALL ed_find
	CALL t_zero
	DB "find",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "first two",0
	CALL ed_find
	CALL t_zero
	DB "find again from a match",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "find does not skip the match under the cursor",0
	CALL ed_find_next
	CALL t_zero
	DB "find next",0
	LD BC,0
	LD DE,14
	CALL t_cursor_is
	DB "second two",0
	CALL ed_find_next
	CALL t_not_found
	DB "no third two",0
	LD BC,0
	LD DE,14
	CALL t_cursor_is
	DB "failed search leaves the cursor",0
	CALL ed_find_prev
	CALL t_zero
	DB "find previous",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "back at the first two",0
	CALL ed_find_prev
	CALL t_not_found
	DB "nothing before the first two",0
	CALL cur_doc_end
	CALL ed_find_prev
	CALL t_zero
	DB "find previous from the end",0
	LD BC,0
	LD DE,14
	CALL t_cursor_is
	DB "last two",0
	LD HL,s_one
	LD BC,3
	CALL t_pat
	DB "pattern one",0
	CALL cur_doc_start
	CALL ed_find
	CALL t_zero
	DB "find one at the start",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "match at position 0",0
	CALL ed_find_next
	LD BC,0
	LD DE,18
	CALL t_cursor_is
	DB "match ending at the last byte",0
	CALL ed_find_next
	CALL t_not_found
	DB "no more ones",0
	LD HL,s_long
	LD BC,30
	CALL t_pat
	DB "pattern longer than the text",0
	CALL cur_doc_start
	CALL ed_find
	CALL t_not_found
	DB "too long to match",0
	LD HL,s_one
	LD BC,0
	CALL search_set
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "empty pattern rejected",0
	LD HL,s_one
	LD BC,SRCH_MAX + 1
	CALL search_set
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "over-long pattern rejected",0
	; false starts
	CALL ed_init
	LD HL,s_aaaab
	LD BC,5
	CALL t_ins
	DB "type aaaab",0
	CALL cur_doc_start
	LD HL,s_aab
	LD BC,3
	CALL t_pat
	DB "pattern aab",0
	CALL ed_find
	CALL t_zero
	DB "overlapping first bytes",0
	LD BC,0
	LD DE,2
	CALL t_cursor_is
	DB "aab found at column 2",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- line and column tracking

test_find_lines:
	CALL t_section
	DB "search: line and column tracking",0
	CALL ed_init
	LD HL,s_doc2
	LD BC,28
	CALL t_ins
	DB "type lines",0
	CALL cur_doc_start
	LD HL,s_beta
	LD BC,4
	CALL t_pat
	DB "pattern beta",0
	CALL ed_find
	LD BC,1
	LD DE,0
	CALL t_cursor_is
	DB "beta on line 1",0
	CALL ed_find_next
	LD BC,3
	LD DE,6
	CALL t_cursor_is
	DB "beta on line 3",0
	CALL ed_find_prev
	LD BC,1
	LD DE,0
	CALL t_cursor_is
	DB "back to line 1",0
	CALL cur_doc_end
	CALL ed_find_prev
	LD BC,3
	LD DE,6
	CALL t_cursor_is
	DB "backwards from the end",0
	LD HL,s_a_nl_b
	LD BC,3
	CALL t_pat
	DB "pattern spanning a newline",0
	CALL cur_doc_start
	CALL ed_find
	CALL t_zero
	DB "find a<newline>b",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "match starts on line 0",0
	LD HL,s_nl_ge
	LD BC,3
	CALL t_pat
	DB "pattern starting with a newline",0
	CALL cur_doc_start
	CALL ed_find
	CALL t_zero
	DB "find <newline>ge",0
	LD BC,1
	LD DE,4
	CALL t_cursor_is
	DB "the newline ends line 1",0
	LD HL,s_nl
	LD BC,1
	CALL t_pat
	DB "pattern newline",0
	CALL cur_doc_start
	CALL ed_find
	LD BC,0
	LD DE,5
	CALL t_cursor_is
	DB "first newline",0
	CALL ed_find_next
	LD BC,1
	LD DE,4
	CALL t_cursor_is
	DB "second newline",0
	CALL ed_find_next
	LD BC,2
	LD DE,5
	CALL t_cursor_is
	DB "third newline",0
	CALL ed_find_next
	LD BC,3
	LD DE,10
	CALL t_cursor_is
	DB "fourth newline",0
	CALL ed_find_next
	CALL t_not_found
	DB "no fifth newline",0
	CALL cur_doc_end
	CALL ed_find_prev
	LD BC,3
	LD DE,10
	CALL t_cursor_is
	DB "last newline, backwards",0
	CALL ed_find_prev
	LD BC,2
	LD DE,5
	CALL t_cursor_is
	DB "previous newline",0
	CALL ed_find_prev
	CALL ed_find_prev
	LD BC,0
	LD DE,5
	CALL t_cursor_is
	DB "back to the first newline",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- pieces

test_find_pieces:
	CALL t_section
	DB "search: across pieces",0
	CALL ed_init
	LD HL,s_mov
	LD BC,11
	CALL t_ins
	DB "type MOV HL,zzzz",0
	CALL cur_left
	CALL cur_left
	CALL cur_left
	CALL cur_left
	LD BC,4
	CALL ed_delete
	CALL t_zero
	DB "delete zzzz",0
	LD HL,s_1234
	LD BC,4
	CALL t_ins
	DB "type 1234 elsewhere in the add store",0
	LD HL,s_tail
	LD BC,6
	CALL t_ins
	DB "type the tail",0
	LD BC,2
	CALL t_count_is
	DB "two pieces",0
	CALL cur_doc_start
	LD HL,s_hl1234
	LD BC,7
	CALL t_pat
	DB "pattern HL,1234",0
	CALL ed_find
	CALL t_zero
	DB "find across the piece boundary",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "column 4",0
	CALL cur_doc_end
	CALL ed_find_prev
	CALL t_zero
	DB "find backwards across the piece boundary",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "column 4 again",0
	CALL cur_doc_start
	LD HL,s_l12
	LD BC,4
	CALL t_pat
	DB "pattern L,12",0
	CALL ed_find
	LD BC,0
	LD DE,5
	CALL t_cursor_is
	DB "match straddling the join",0
	; replace across the pieces
	LD HL,s_hl1234
	LD BC,7
	CALL t_pat
	DB "pattern HL,1234 again",0
	LD HL,s_99
	LD BC,5
	CALL t_rep
	DB "replacement HL,99",0
	CALL cur_doc_start
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace across pieces",0
	LD DE,s_edited
	LD BC,15
	CALL t_doc_is
	DB "text after replace",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- banks

test_find_banks:
	CALL t_section
	DB "search: across banks",0
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_find_banks_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_find_banks_build
	LD IX,t_iter
	LD HL,0
	LD DE,16370
	CALL iter_seek
	LD HL,s_bpat
	LD BC,6
	CALL t_pat
	DB "pattern straddling the bank boundary",0
	CALL sr_reset
	CALL search_fwd
	CALL t_zero
	DB "forward search finds it",0
	CALL iter_offset
	EX DE,HL
	LD BC,16381
	CALL t_eq16
	DB "match starts 3 bytes before the boundary",0
	LD DE,s_bpat
	LD BC,6
	CALL t_iter_eq
	DB "match bytes",0
	LD HL,0
	LD DE,16382
	CALL iter_seek
	CALL sr_reset
	CALL search_fwd
	CALL t_zero
	DB "search from just after the match",0
	CALL iter_offset
	EX DE,HL
	LD BC,16632
	CALL t_eq16
	DB "next match is one block later",0
	LD HL,0
	LD DE,16390
	CALL iter_seek
	CALL sr_reset
	CALL search_back
	CALL t_zero
	DB "backward search across the boundary",0
	CALL iter_offset
	EX DE,HL
	LD BC,16381
	CALL t_eq16
	DB "backward match position",0
	CALL cur_doc_start
	CALL ed_find
	CALL t_zero
	DB "cursor search in a big document",0
	LD BC,1
	LD DE,56
	CALL t_cursor_is
	DB "first match line and column",0
	CALL ed_find_next
	LD BC,2
	LD DE,56
	CALL t_cursor_is
	DB "second match line and column",0
	CALL cur_doc_end
	CALL ed_find_prev
	CALL t_zero
	DB "backwards from the end",0
	LD BC,160
	LD DE,56
	CALL t_cursor_is
	DB "last match line and column",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- replace

test_replace:
	CALL t_section
	DB "replace at the cursor",0
	CALL ed_init
	LD HL,s_foo_bar_foo
	LD BC,11
	CALL t_ins
	DB "type foo bar foo",0
	CALL cur_doc_start
	LD HL,s_foo
	LD BC,3
	CALL t_pat
	DB "pattern foo",0
	LD HL,s_quux
	LD BC,4
	CALL t_rep
	DB "replacement quux",0
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace the first foo",0
	LD DE,s_quux_bar_foo
	LD BC,12
	CALL t_doc_is
	DB "text after first replace",0
	LD BC,0
	LD DE,4
	CALL t_cursor_is
	DB "cursor after the replacement",0
	CALL ed_replace
	CALL t_not_found
	DB "not on a match: nothing to replace",0
	LD DE,s_quux_bar_foo
	LD BC,12
	CALL t_doc_is
	DB "text untouched",0
	CALL ed_find
	CALL t_zero
	DB "find the second foo",0
	CALL ed_replace
	CALL t_zero
	DB "replace it",0
	LD DE,s_quux_bar_quux
	LD BC,13
	CALL t_doc_is
	DB "text after second replace",0
	; empty replacement deletes
	LD HL,s_quux
	LD BC,4
	CALL t_pat
	DB "pattern quux",0
	LD HL,s_quux
	LD BC,0
	CALL t_rep
	DB "empty replacement",0
	CALL cur_doc_start
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "delete a match",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cursor stays where the match was",0
	; replacement with a newline
	CALL ed_init
	LD HL,s_quux_quux
	LD BC,9
	CALL t_ins
	DB "type quux quux",0
	LD HL,s_quux
	LD BC,4
	CALL t_pat
	DB "pattern quux again",0
	LD HL,s_x_nl_y
	LD BC,3
	CALL t_rep
	DB "replacement with a newline",0
	CALL cur_doc_start
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace with a newline",0
	LD BC,1
	LD DE,1
	CALL t_cursor_is
	DB "cursor after a multi-line replacement",0
	LD BC,1
	CALL t_nl_is
	DB "newline counted",0
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace the second one too",0
	LD BC,2
	CALL t_nl_is
	DB "two newlines",0
	; a pattern that contains a newline
	CALL ed_init
	LD HL,s_a_nl_b_only
	LD BC,3
	CALL t_ins
	DB "type a b on two lines",0
	LD HL,s_nl
	LD BC,1
	CALL t_pat
	DB "pattern newline",0
	LD HL,s_sp
	LD BC,1
	CALL t_rep
	DB "replacement space",0
	CALL cur_doc_start
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace a newline",0
	LD BC,0
	CALL t_nl_is
	DB "newline uncounted",0
	LD DE,s_a_sp_b
	LD BC,3
	CALL t_doc_is
	DB "lines joined",0
	CALL doc_close
	RET

test_replace_all:
	CALL t_section
	DB "replace all",0
	CALL ed_init
	LD HL,s_foo3
	LD BC,19
	CALL t_ins
	DB "type foo bar foo baz foo",0
	LD HL,s_foo
	LD BC,3
	CALL t_pat
	DB "pattern foo",0
	LD HL,s_X
	LD BC,1
	CALL t_rep
	DB "replacement X",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace all",0
	LD BC,3
	CALL t_repl_count
	DB "three replacements",0
	LD DE,s_x_bar_x_baz_x
	LD BC,13
	CALL t_doc_is
	DB "text after replace all",0
	CALL t_doc_eof
	DB "nothing left over",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cursor at the start",0
	; overlapping matches: the last one wins, replaced text is not searched again
	CALL ed_init
	LD HL,s_aaa
	LD BC,3
	CALL t_ins
	DB "type aaa",0
	LD HL,s_aa
	LD BC,2
	CALL t_pat
	DB "pattern aa",0
	LD HL,s_b
	LD BC,1
	CALL t_rep
	DB "replacement b",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace overlapping matches",0
	LD BC,1
	CALL t_repl_count
	DB "one replacement",0
	LD DE,s_ab
	LD BC,2
	CALL t_doc_is
	DB "ab",0
	; newlines in the pattern
	CALL ed_init
	LD HL,s_lines3
	LD BC,6
	CALL t_ins
	DB "type three lines",0
	LD HL,s_nl
	LD BC,1
	CALL t_pat
	DB "pattern newline",0
	LD HL,s_sp
	LD BC,1
	CALL t_rep
	DB "replacement space",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace all newlines",0
	LD BC,3
	CALL t_repl_count
	DB "three newlines replaced",0
	LD BC,0
	CALL t_nl_is
	DB "no newlines left",0
	LD DE,s_lines3_sp
	LD BC,6
	CALL t_doc_is
	DB "joined text",0
	LD HL,s_sp
	LD BC,1
	CALL t_pat
	DB "pattern space",0
	LD HL,s_nl
	LD BC,1
	CALL t_rep
	DB "replacement newline",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace all spaces",0
	LD BC,3
	CALL t_nl_is
	DB "newlines counted again",0
	LD DE,s_lines3
	LD BC,6
	CALL t_doc_is
	DB "restored text",0
	; empty replacement
	CALL ed_init
	LD HL,s_xaxbx
	LD BC,5
	CALL t_ins
	DB "type xaxbx",0
	LD HL,s_x
	LD BC,1
	CALL t_pat
	DB "pattern x",0
	LD HL,s_x
	LD BC,0
	CALL t_rep
	DB "empty replacement",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "delete every x",0
	LD BC,3
	CALL t_repl_count
	DB "three deletions",0
	LD DE,s_ab
	LD BC,2
	CALL t_doc_is
	DB "text without x",0
	CALL t_doc_eof
	DB "nothing left over",0
	; no match
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace all with no match",0
	LD BC,0
	CALL t_repl_count
	DB "zero replacements",0
	; one shared copy of the replacement
	CALL ed_init
	LD A,50
	LD (tv_a),A
test_replace_all_build:
	LD HL,s_foo_sp
	LD BC,4
	CALL t_ins
	DB "build",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_replace_all_build
	LD HL,s_foo
	LD BC,3
	CALL t_pat
	DB "pattern foo",0
	LD HL,s_bar
	LD BC,3
	CALL t_rep
	DB "replacement bar",0
	LD A,(add_off)
	LD (tv_a + 1),A
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace fifty",0
	LD BC,50
	CALL t_repl_count
	DB "fifty replacements",0
	LD A,(tv_a + 1)
	ADD A,3
	LD B,A
	LD A,(add_off)
	CALL t_eq8
	DB "the add store grew by one copy of the replacement",0
	LD A,50
	LD (tv_a),A
	LD IX,t_iter
	CALL iter_init
test_replace_all_check:
	LD DE,s_bar_sp
	LD BC,4
	CALL t_iter_eq
	DB "bar bar bar",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_replace_all_check
	; piece table limit
	CALL ed_init
	LD HL,300
	LD (tv_ptr),HL
test_replace_all_fill:
	LD HL,s_x
	LD BC,1
	CALL t_ins
	DB "fill",0
	LD HL,s_sp
	LD BC,1
	CALL t_ins
	DB "fill",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_replace_all_fill
	LD HL,s_x
	LD BC,1
	CALL t_pat
	DB "pattern x",0
	LD HL,s_yy
	LD BC,2
	CALL t_rep
	DB "replacement yy",0
	CALL ed_replace_all
	LD (tv_n),HL
	LD B,ERR_NO_MORE_ENTRIES
	CALL t_eq8
	DB "running out of pieces is reported",0
	LD HL,(tv_n)
	LD DE,50
	OR A
	SBC HL,DE
	CALL t_nc
	DB "a good number were replaced first",0
	LD IX,t_iter
	CALL t_doc_length
	LD HL,(tv_n)
	LD BC,600
	ADD HL,BC
	LD B,H
	LD C,L
	CALL t_eq16
	DB "no replacement was left half done",0
	CALL doc_close
	RET

test_replace_all_big:
	CALL t_section
	DB "replace all across banks",0
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_replace_all_big_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_replace_all_big_build
	LD HL,t_blk
	LD BC,3
	CALL t_pat
	DB "pattern 1,2,3",0
	LD HL,s_200
	LD BC,1
	CALL t_rep
	DB "replacement 200",0
	CALL ed_replace_all
	LD (tv_n),HL
	CALL t_zero
	DB "replace 160 matches",0
	LD BC,160
	CALL t_repl_count
	DB "160 replacements",0
	LD BC,160
	CALL t_nl_is
	DB "newline count unchanged",0
	LD IX,t_iter
	CALL iter_init
	LD A,160
	LD (tv_a),A
test_replace_all_big_check:
	LD DE,s_200
	LD BC,1
	CALL t_iter_eq
	DB "replacement byte",0
	LD DE,t_blk + 3
	LD BC,248
	CALL t_iter_eq
	DB "rest of the block",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_replace_all_big_check
	CALL iter_peek
	CALL t_c
	DB "document ends after 160 blocks",0
	CALL doc_close
	RET

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
