; zested - Phase 4 (undo and redo) tests. Run with `make test`.
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
	CALL test_undo_insert
	CALL test_undo_delete
	CALL test_undo_lines
	CALL test_undo_group
	CALL test_undo_sequence
	CALL test_undo_limits
	CALL test_undo_big
	CALL test_positions
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

t_redo_none:
	CALL ed_redo
	LD B,ERR_NO_SUCH_ENTRY
	JP t_eq8

t_pat:
	CALL search_set
	JP t_zero

t_rep:
	CALL replace_set
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

; HL = pos: doc_locate then doc_position must give the same offset back. Inline message.
t_roundtrip:
	LD (tv_n),HL
	LD IX,t_iter
	XOR A
	CALL doc_locate
	CALL doc_position
	EX DE,HL
	LD BC,(tv_n)
	JP t_eq16

s_hello:	DB "hello"
s_hello_world:	DB "hello world"
s_world:	DB " world"
s_h:		DB "h"
s_e:		DB "e"
s_l:		DB "l"
s_o:		DB "o"
s_ab:		DB "ab"
s_axb:		DB "aXb"
s_x:		DB "X"
s_l0123:	DB "l0",10,"l1",10,"l2",10,"l3"
s_l0l3:		DB "l0",10,"l3"
s_abc:		DB "abc"
s_c:		DB "c"
s_one3:		DB "one",10,"two",10,"three"
s_one_three:	DB "one",10,"three"
s_two:		DB "two"
s_foo_bar_foo:	DB "foo bar foo"
s_foo:		DB "foo"
s_quux:		DB "quux"
s_quux_bar_foo:	DB "quux bar foo"
s_foo3:		DB "foo bar foo baz foo"
s_X:		DB "X"
s_X3:		DB "X bar X baz X"
s_lines3:	DB "a",10,"b",10,"c",10
s_lines3_sp:	DB "a b c "
s_nl:		DB 10
s_sp:		DB " "
s_a_nl_b:	DB "a",10,"b"
s_b:		DB "b"
s_a:		DB "a"
s_a_x:		DB "aX"
s_Xabc:		DB "Xabc"
s_Xab:		DB "Xab"
s_Xb:		DB "Xb"
s_Xb_bang:	DB "Xb!"
s_bang:		DB "!"
s_xy:		DB "xy"
s_yy:		DB "yy"
s_x1:		DB "x"
s_xsp:		DB "x "
s_q:		DB "q"
s_123:		DB "1",10,"2",10,"3"
s_digits:	DB "0123456789"
s_abc3:		DB "abc"
s_012abc:	DB "012abc3456789"
s_06789:	DB "06789"
s_line_a:	DB "AA"
s_line_b:	DB "BB"
s_line_c:	DB "CC"
s_bbaacc:	DB "BBAACC"
s_stuff:	DB "stuff",10
s_ed:		DB "H:/zested_undo.txt",0

; ---------------------------------------------------------------- inserts

test_undo_insert:
	CALL t_section
	DB "undo and redo of insertions",0
	CALL ed_init
	LD HL,s_hello
	LD BC,5
	CALL t_ins
	DB "type hello",0
	CALL ed_undo
	CALL t_zero
	DB "undo the typing",0
	LD HL,s_hello
	LD BC,0
	CALL t_doc_exact
	DB "empty after undo",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cursor back at the start",0
	CALL ed_redo
	CALL t_zero
	DB "redo",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello is back",0
	LD BC,0
	LD DE,5
	CALL t_cursor_is
	DB "cursor after the redone text",0
	CALL t_redo_none
	DB "nothing more to redo",0
	CALL ed_undo
	CALL t_undo_none
	DB "nothing more to undo",0

	; typing a character at a time is one undo step
	CALL ed_init
	LD A,'h'
	CALL ed_insert_char
	LD A,'e'
	CALL ed_insert_char
	LD A,'l'
	CALL ed_insert_char
	LD A,'l'
	CALL ed_insert_char
	LD A,'o'
	CALL ed_insert_char
	CALL ed_undo
	CALL t_zero
	DB "undo a typed word",0
	LD HL,s_hello
	LD BC,0
	CALL t_doc_exact
	DB "the whole word went",0
	CALL t_undo_none
	DB "it was a single step",0

	; an insertion elsewhere is a separate step
	CALL ed_init
	LD HL,s_ab
	LD BC,2
	CALL t_ins
	DB "type ab",0
	CALL cur_left
	LD HL,s_x
	LD BC,1
	CALL t_ins
	DB "type X between",0
	CALL ed_undo
	CALL t_zero
	DB "undo X",0
	LD HL,s_ab
	LD BC,2
	CALL t_doc_exact
	DB "ab remains",0
	LD BC,0
	LD DE,1
	CALL t_cursor_is
	DB "cursor where X was",0
	CALL ed_undo
	CALL t_zero
	DB "undo ab",0
	LD HL,s_ab
	LD BC,0
	CALL t_doc_exact
	DB "empty",0
	CALL ed_redo
	CALL ed_redo
	CALL t_zero
	DB "redo both",0
	LD HL,s_axb
	LD BC,3
	CALL t_doc_exact
	DB "aXb",0

	; a new edit discards the redo history
	CALL ed_init
	LD HL,s_a
	LD BC,1
	CALL t_ins
	DB "type a",0
	CALL ed_undo
	LD HL,s_b
	LD BC,1
	CALL t_ins
	DB "type b instead",0
	CALL t_redo_none
	DB "redo history dropped",0
	LD HL,s_b
	LD BC,1
	CALL t_doc_exact
	DB "only b",0

	; text with a newline
	CALL ed_init
	LD HL,s_a_nl_b
	LD BC,3
	CALL t_ins
	DB "type a newline b",0
	LD BC,1
	CALL t_nl_is
	DB "one newline",0
	CALL ed_undo
	LD BC,0
	CALL t_nl_is
	DB "newline uncounted by undo",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cursor at the start",0
	CALL ed_redo
	LD BC,1
	CALL t_nl_is
	DB "newline counted by redo",0
	LD BC,1
	LD DE,1
	CALL t_cursor_is
	DB "cursor after the redone text on line 1",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- deletes

test_undo_delete:
	CALL t_section
	DB "undo and redo of deletions",0
	CALL ed_init
	LD HL,s_hello_world
	LD BC,11
	CALL t_ins
	DB "type hello world",0
	CALL cur_doc_start
	LD B,5
test_undo_delete_move:
	PUSH BC
	CALL cur_right
	POP BC
	DJNZ test_undo_delete_move
	LD BC,6
	CALL ed_delete
	CALL t_zero
	DB "delete world",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello",0
	CALL ed_undo
	CALL t_zero
	DB "undo the delete",0
	LD HL,s_hello_world
	LD BC,11
	CALL t_doc_exact
	DB "hello world restored",0
	LD BC,0
	LD DE,5
	CALL t_cursor_is
	DB "cursor at the restored text",0
	LD DE,s_world
	LD BC,6
	CALL t_at_cursor
	DB "restored text follows the cursor",0
	CALL ed_redo
	CALL t_zero
	DB "redo the delete",0
	LD HL,s_hello
	LD BC,5
	CALL t_doc_exact
	DB "hello again",0
	CALL ed_undo
	CALL ed_undo
	CALL t_zero
	DB "undo the delete and the typing",0
	LD HL,s_hello
	LD BC,0
	CALL t_doc_exact
	DB "empty",0

	; a delete over several lines
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
	LD BC,1
	CALL t_nl_is
	DB "newlines after the delete",0
	CALL ed_undo
	CALL t_zero
	DB "undo the multi-line delete",0
	LD HL,s_l0123
	LD BC,11
	CALL t_doc_exact
	DB "four lines back",0
	LD BC,3
	CALL t_nl_is
	DB "newlines restored",0
	LD BC,1
	LD DE,1
	CALL t_cursor_is
	DB "cursor line and column",0
	CALL ed_redo
	LD BC,1
	CALL t_nl_is
	DB "redo removes the newlines again",0
	LD HL,s_l0l3
	LD BC,5
	CALL t_doc_exact
	DB "text after redo",0

	; backspace
	CALL ed_init
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "type abc",0
	CALL ed_backspace
	CALL t_zero
	DB "backspace",0
	LD HL,s_ab
	LD BC,2
	CALL t_doc_exact
	DB "ab",0
	CALL ed_undo
	CALL t_zero
	DB "undo backspace",0
	LD HL,s_abc
	LD BC,3
	CALL t_doc_exact
	DB "abc",0
	LD DE,s_c
	LD BC,1
	CALL t_at_cursor
	DB "cursor before the restored c",0

	; a delete that spans several pieces
	CALL ed_init
	LD HL,s_digits
	LD BC,10
	CALL t_ins
	DB "type digits",0
	CALL cur_doc_start
	CALL cur_right
	CALL cur_right
	CALL cur_right
	LD HL,s_abc3
	LD BC,3
	CALL t_ins
	DB "insert abc",0
	CALL cur_doc_start
	CALL cur_right
	LD BC,8
	CALL ed_delete
	CALL t_zero
	DB "delete across three pieces",0
	LD HL,s_06789
	LD BC,5
	CALL t_doc_exact
	DB "text after the delete",0
	CALL ed_undo
	CALL t_zero
	DB "undo it",0
	LD HL,s_012abc
	LD BC,13
	CALL t_doc_exact
	DB "all pieces are back",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- lines

test_undo_lines:
	CALL t_section
	DB "undo of line operations",0
	CALL ed_init
	LD HL,s_one3
	LD BC,13
	CALL t_ins
	DB "type three lines",0
	LD HL,1
	CALL cur_goto_line
	CALL ed_delete_line
	CALL t_zero
	DB "delete a line",0
	LD HL,s_one_three
	LD BC,9
	CALL t_doc_exact
	DB "line gone",0
	CALL ed_undo
	CALL t_zero
	DB "undo the line delete",0
	LD HL,s_one3
	LD BC,13
	CALL t_doc_exact
	DB "line restored",0
	LD BC,2
	CALL t_nl_is
	DB "newlines restored",0
	LD BC,1
	LD DE,0
	CALL t_cursor_is
	DB "cursor at the restored line",0
	CALL ed_redo
	LD HL,s_one_three
	LD BC,9
	CALL t_doc_exact
	DB "redo the delete",0
	; inserting a line is one step
	CALL ed_init
	LD HL,s_one_three
	LD BC,9
	CALL t_ins
	DB "type two lines",0
	LD HL,1
	CALL cur_goto_line
	LD HL,s_two
	LD BC,3
	CALL ed_insert_line
	CALL t_zero
	DB "insert a line",0
	LD HL,s_one3
	LD BC,13
	CALL t_doc_exact
	DB "three lines",0
	CALL ed_undo
	CALL t_zero
	DB "undo the line insert",0
	LD HL,s_one_three
	LD BC,9
	CALL t_doc_exact
	DB "back to two lines",0
	CALL ed_redo
	LD HL,s_one3
	LD BC,13
	CALL t_doc_exact
	DB "redo the line insert",0
	; replace at the cursor is one step
	CALL ed_init
	LD HL,s_foo_bar_foo
	LD BC,11
	CALL t_ins
	DB "type foo bar foo",0
	LD HL,s_foo
	LD BC,3
	CALL t_pat
	DB "pattern foo",0
	LD HL,s_quux
	LD BC,4
	CALL t_rep
	DB "replacement quux",0
	CALL cur_doc_start
	CALL ed_find
	CALL ed_replace
	CALL t_zero
	DB "replace",0
	LD HL,s_quux_bar_foo
	LD BC,12
	CALL t_doc_exact
	DB "quux bar foo",0
	CALL ed_undo
	CALL t_zero
	DB "undo the replace",0
	LD HL,s_foo_bar_foo
	LD BC,11
	CALL t_doc_exact
	DB "one undo restores foo",0
	LD BC,0
	LD DE,0
	CALL t_cursor_is
	DB "cursor at the match",0
	CALL ed_redo
	LD HL,s_quux_bar_foo
	LD BC,12
	CALL t_doc_exact
	DB "redo the replace",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- groups

test_undo_group:
	CALL t_section
	DB "grouped operations",0
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
	CALL t_zero
	DB "replace all",0
	LD HL,s_X3
	LD BC,13
	CALL t_doc_exact
	DB "replaced",0
	CALL ed_undo
	CALL t_zero
	DB "one undo",0
	LD HL,s_foo3
	LD BC,19
	CALL t_doc_exact
	DB "all three replacements undone",0
	CALL ed_redo
	CALL t_zero
	DB "one redo",0
	LD HL,s_X3
	LD BC,13
	CALL t_doc_exact
	DB "all three replacements redone",0
	CALL ed_undo
	CALL ed_undo
	CALL t_zero
	DB "undo the replacements and the typing",0
	LD HL,s_foo3
	LD BC,0
	CALL t_doc_exact
	DB "empty",0

	; replace-all over newlines keeps the newline count right
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
	LD BC,0
	CALL t_nl_is
	DB "no newlines",0
	CALL ed_undo
	LD BC,3
	CALL t_nl_is
	DB "undo brings the newlines back",0
	LD HL,s_lines3
	LD BC,6
	CALL t_doc_exact
	DB "lines restored",0
	CALL ed_redo
	LD BC,0
	CALL t_nl_is
	DB "redo removes them",0
	LD HL,s_lines3_sp
	LD BC,6
	CALL t_doc_exact
	DB "joined again",0

	; explicit groups, nested
	CALL ed_init
	CALL undo_begin_group
	LD HL,s_line_a
	LD BC,2
	CALL t_ins
	DB "first insert",0
	CALL undo_begin_group
	CALL cur_doc_start
	LD HL,s_line_b
	LD BC,2
	CALL t_ins
	DB "second insert",0
	CALL undo_end_group
	CALL cur_doc_end
	LD HL,s_line_c
	LD BC,2
	CALL t_ins
	DB "third insert",0
	CALL undo_end_group
	CALL ed_undo
	CALL t_zero
	DB "undo the group",0
	LD HL,s_line_a
	LD BC,0
	CALL t_doc_exact
	DB "all three inserts undone",0
	CALL t_undo_none
	DB "one step only",0
	CALL ed_redo
	CALL t_zero
	DB "redo the group",0
	LD HL,s_bbaacc
	LD BC,6
	CALL t_doc_exact
	DB "BBAACC",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- longer histories

s_history:	DB "Xb!"

test_undo_sequence:
	CALL t_section
	DB "undo and redo through a history",0
	CALL ed_init
	LD HL,s_abc
	LD BC,3
	CALL t_ins
	DB "e1: type abc",0
	CALL cur_doc_start
	LD HL,s_x
	LD BC,1
	CALL t_ins
	DB "e2: insert X",0
	CALL cur_doc_end
	CALL ed_backspace
	CALL t_zero
	DB "e3: backspace",0
	CALL cur_doc_start
	CALL cur_right
	LD BC,1
	CALL ed_delete
	CALL t_zero
	DB "e4: delete a",0
	CALL cur_doc_end
	LD HL,s_bang
	LD BC,1
	CALL t_ins
	DB "e5: append !",0
	LD HL,s_Xb_bang
	LD BC,3
	CALL t_doc_exact
	DB "final text",0
	CALL ed_undo
	LD HL,s_Xb
	LD BC,2
	CALL t_doc_exact
	DB "after undoing e5",0
	CALL ed_undo
	LD HL,s_Xab
	LD BC,3
	CALL t_doc_exact
	DB "after undoing e4",0
	CALL ed_undo
	LD HL,s_Xabc
	LD BC,4
	CALL t_doc_exact
	DB "after undoing e3",0
	CALL ed_undo
	LD HL,s_abc
	LD BC,3
	CALL t_doc_exact
	DB "after undoing e2",0
	CALL ed_undo
	LD HL,s_abc
	LD BC,0
	CALL t_doc_exact
	DB "after undoing e1",0
	CALL ed_redo
	LD HL,s_abc
	LD BC,3
	CALL t_doc_exact
	DB "after redoing e1",0
	CALL ed_redo
	LD HL,s_Xabc
	LD BC,4
	CALL t_doc_exact
	DB "after redoing e2",0
	CALL ed_redo
	LD HL,s_Xab
	LD BC,3
	CALL t_doc_exact
	DB "after redoing e3",0
	CALL ed_redo
	LD HL,s_Xb
	LD BC,2
	CALL t_doc_exact
	DB "after redoing e4",0
	CALL ed_redo
	LD HL,s_Xb_bang
	LD BC,3
	CALL t_doc_exact
	DB "after redoing e5",0
	CALL t_redo_none
	DB "history is used up",0
	LD A,(doc_dirty)
	LD B,1
	CALL t_eq8
	DB "undo and redo mark the document dirty",0
	CALL doc_close
	RET

test_undo_limits:
	CALL t_section
	DB "bounded history",0
	; 300 separate one-character edits do not fit the log: the oldest are dropped
	CALL ed_init
	LD HL,300
	LD (tv_ptr),HL
test_undo_limits_fill:
	CALL cur_doc_start
	LD HL,s_x1
	LD BC,1
	CALL t_ins
	DB "edit",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_undo_limits_fill
	LD HL,0
	LD (tv_n),HL
test_undo_limits_undo:
	CALL ed_undo
	JR NZ,test_undo_limits_counted
	LD HL,(tv_n)
	INC HL
	LD (tv_n),HL
	JR test_undo_limits_undo
test_undo_limits_counted:
	LD HL,(tv_n)
	LD DE,50
	OR A
	SBC HL,DE
	CALL t_nc
	DB "a good number of steps were kept",0
	LD DE,(tv_n)
	LD HL,300
	OR A
	SBC HL,DE
	CALL t_nz
	DB "but not all of them",0
	LD IX,t_iter
	CALL t_doc_length
	LD HL,(tv_n)
	ADD HL,DE
	LD B,H
	LD C,L
	LD DE,300
	CALL t_eq16
	DB "the steps that were dropped stay applied",0

	; a group larger than the log is not recorded at all
	CALL ed_init
	LD HL,300
	LD (tv_ptr),HL
test_undo_limits_big:
	LD HL,s_xsp
	LD BC,2
	CALL t_ins
	DB "fill",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_undo_limits_big
	LD HL,s_x1
	LD BC,1
	CALL t_pat
	DB "pattern x",0
	LD HL,s_yy
	LD BC,2
	CALL t_rep
	DB "replacement yy",0
	CALL ed_replace_all
	LD IX,t_iter
	CALL t_doc_length
	LD (tv_n),DE
	CALL t_undo_none
	DB "an oversized group is not undoable",0
	LD IX,t_iter
	CALL t_doc_length
	LD BC,(tv_n)
	CALL t_eq16
	DB "and the text is left as it was",0
	LD HL,s_q
	LD BC,1
	CALL t_ins
	DB "later edits are recorded again",0
	CALL ed_undo
	CALL t_zero
	DB "undo the later edit",0
	LD IX,t_iter
	CALL t_doc_length
	LD BC,(tv_n)
	CALL t_eq16
	DB "back to the same length",0

	; loading a file starts a new history
	CALL ed_init
	LD HL,s_stuff
	LD BC,6
	CALL t_ins
	DB "type stuff",0
	LD BC,s_ed
	CALL ed_save
	CALL t_zero
	DB "save",0
	LD BC,s_ed
	CALL ed_load
	CALL t_zero
	DB "load",0
	CALL t_undo_none
	DB "no history after loading",0
	LD HL,s_q
	LD BC,1
	CALL t_ins
	DB "edit the loaded file",0
	CALL ed_undo
	CALL t_zero
	DB "undo works on a loaded file",0
	LD HL,s_stuff
	LD BC,6
	CALL t_doc_exact
	DB "loaded text intact",0
	CALL doc_close
	RET

test_undo_big:
	CALL t_section
	DB "undo over multi-bank text",0
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_undo_big_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_undo_big_build
	CALL ed_undo
	CALL t_zero
	DB "undo 40160 typed bytes",0
	LD BC,0
	CALL t_count_is
	DB "no pieces left",0
	LD BC,0
	CALL t_nl_is
	DB "no newlines left",0
	CALL ed_redo
	CALL t_zero
	DB "redo them",0
	LD BC,160
	CALL t_nl_is
	DB "160 newlines back",0
	LD IX,t_iter
	CALL iter_init
	LD A,160
	LD (tv_a + 1),A
test_undo_big_check:
	LD DE,t_blk
	LD BC,251
	CALL t_iter_eq
	DB "restored blocks",0
	LD HL,tv_a + 1
	DEC (HL)
	JR NZ,test_undo_big_check
	; delete over a bank boundary, then undo it
	LD IX,cur_it
	LD HL,0
	LD DE,16000
	CALL iter_seek
	LD BC,1000
	CALL ed_delete
	CALL t_zero
	DB "delete 1000 bytes over a bank boundary",0
	LD IX,t_iter
	CALL t_doc_length
	LD BC,39160
	CALL t_eq16
	DB "shorter by 1000",0
	CALL ed_undo
	CALL t_zero
	DB "undo the delete",0
	LD IX,t_iter
	CALL t_doc_length
	LD BC,40160
	CALL t_eq16
	DB "full length again",0
	LD BC,160
	CALL t_nl_is
	DB "newlines restored",0
	LD IX,t_iter
	CALL iter_init
	LD A,160
	LD (tv_a + 1),A
test_undo_big_check2:
	LD DE,t_blk
	LD BC,251
	CALL t_iter_eq
	DB "blocks intact after the undo",0
	LD HL,tv_a + 1
	DEC (HL)
	JR NZ,test_undo_big_check2
	CALL doc_close
	RET

; ---------------------------------------------------------------- offsets

test_positions:
	CALL t_section
	DB "document offsets",0
	CALL ed_init
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
test_positions_build:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_positions_build
	LD IX,cur_it
	LD HL,0
	LD DE,16000
	CALL iter_seek
	LD BC,1000
	CALL ed_delete
	CALL t_zero
	DB "make a two-piece document",0
	LD HL,0
	CALL t_roundtrip
	DB "offset 0",0
	LD HL,250
	CALL t_roundtrip
	DB "offset 250",0
	LD HL,15999
	CALL t_roundtrip
	DB "offset 15999 (last byte of the first piece)",0
	LD HL,16000
	CALL t_roundtrip
	DB "offset 16000 (start of the second piece)",0
	LD HL,30000
	CALL t_roundtrip
	DB "offset 30000",0
	LD HL,39159
	CALL t_roundtrip
	DB "offset 39159 (last byte)",0
	LD HL,39160
	CALL t_roundtrip
	DB "offset 39160 (end of the document)",0
	LD HL,50000
	CALL t_roundtrip_end
	DB "past the end clamps to the end",0
	CALL doc_close
	RET

; Like t_roundtrip but the offset comes back as the document length (39160).
t_roundtrip_end:
	LD IX,t_iter
	XOR A
	CALL doc_locate
	CALL doc_position
	EX DE,HL
	LD BC,39160
	JP t_eq16

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
