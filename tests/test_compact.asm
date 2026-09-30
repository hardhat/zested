; zested - Phase 5 (maintenance) tests. Run with `make test`.
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
	CALL test_metrics
	CALL test_compact_full
	CALL test_compact_steps
	CALL test_compact_nomem
	CALL test_compact_auto
	CALL test_policy
	CALL test_line_rebuild
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
	include "metrics.asm"
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

t_undo_none:
	CALL ed_undo
	LD B,ERR_NO_SUCH_ENTRY
	JP t_eq8

t_pat:
	CALL search_set
	JP t_zero

t_rep:
	CALL replace_set
	JP t_zero

; Two 16-bit sums over the document in tv_ck: a plain sum and a sum of running sums.
t_checksum:
	LD IX,t_iter
	CALL iter_init
	LD HL,0
	LD DE,0
t_checksum_loop:
	CALL iter_next
	JR C,t_checksum_done
	LD C,A
	LD B,0
	ADD HL,BC
	EX DE,HL
	ADD HL,DE
	EX DE,HL
	JR t_checksum_loop
t_checksum_done:
	LD (tv_ck),HL
	LD (tv_ck + 2),DE
	RET

t_sum_save:
	CALL t_checksum
	LD HL,tv_ck
	LD DE,tv_ck2
	LD BC,4
	LDIR
	RET

; The document must have the checksum saved by t_sum_save. Inline message.
t_sum_same:
	CALL t_checksum
	LD HL,tv_ck2
	LD DE,tv_ck
	LD BC,4
	JP t_mem_eq

; Saves the cursor line, column, the newline count and the document length in tv_save.
t_state_save:
	LD HL,(cur_line)
	LD (tv_save),HL
	LD HL,(cur_col)
	LD (tv_save + 2),HL
	LD HL,(doc_newlines)
	LD (tv_save + 4),HL
	LD IX,t_iter
	CALL t_doc_length
	LD (tv_save + 6),DE
	RET

; Copies the 8 bytes under the cursor to t_lbuf.
t_save_cursor_text:
	LD HL,cur_it
	LD DE,t_iter
	LD BC,IT_SIZE
	LDIR
	LD IX,t_iter
	LD B,8
	LD HL,t_lbuf
t_save_cursor_text_loop:
	CALL iter_next
	LD (HL),A
	INC HL
	DJNZ t_save_cursor_text_loop
	RET

; tv_ptr = iterations. Scatters edits near the start: move 5, insert '#', delete 2 bytes.
t_fragment:
	CALL cur_doc_start
t_fragment_loop:
	LD B,5
t_fragment_move:
	PUSH BC
	CALL cur_right
	POP BC
	DJNZ t_fragment_move
	LD A,'#'
	CALL ed_insert_char
	CALL t_zero
	DB "fragment: insert",0
	LD BC,2
	CALL ed_delete
	CALL t_zero
	DB "fragment: delete",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,t_fragment_loop
	RET

; 160 copies of t_blk (40160 bytes) typed into an empty document.
t_build_big:
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
t_build_big_loop:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build blocks",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,t_build_big_loop
	RET

; Expected 24-bit values, little endian.
e_zero:		DB 0,0,0
e_40160:	DB 0xE0,0x9C,0x00
e_39160:	DB 0xF8,0x98,0x00
e_39662:	DB 0xEE,0x9A,0x00
e_40662:	DB 0xD6,0x9E,0x00
e_1000:		DB 0xE8,0x03,0x00
e_502:		DB 0xF6,0x01,0x00
s_yysp:		DB "yy "
s_x:		DB "x"
s_xsp:		DB "x "
s_yy:		DB "yy"
s_z:		DB "Z"
f_cmp:		DB "H:/zested_cmp.bin",0

; ---------------------------------------------------------------- metrics

test_metrics:
	CALL t_section
	DB "fragmentation metrics",0
	CALL ed_init
	CALL t_build_big
	LD BC,f_cmp
	CALL ed_save
	CALL t_zero
	DB "save",0
	LD BC,f_cmp
	CALL ed_load
	CALL t_zero
	DB "load",0
	CALL doc_metrics
	LD HL,e_40160
	LD DE,mt_live
	LD BC,3
	CALL t_mem_eq
	DB "live bytes of a fresh file",0
	LD HL,e_40160
	LD DE,mt_store
	LD BC,3
	CALL t_mem_eq
	DB "store bytes of a fresh file",0
	LD HL,e_zero
	LD DE,mt_waste
	LD BC,3
	CALL t_mem_eq
	DB "no waste yet",0
	LD HL,e_zero
	LD DE,mt_addstore
	LD BC,3
	CALL t_mem_eq
	DB "add store unused",0
	LD BC,1
	CALL t_count_is
	DB "one piece",0
	LD IX,cur_it
	LD HL,0
	LD DE,16000
	CALL iter_seek
	LD BC,1000
	CALL ed_delete
	CALL t_zero
	DB "delete 1000 bytes",0
	CALL doc_metrics
	LD HL,e_39160
	LD DE,mt_live
	LD BC,3
	CALL t_mem_eq
	DB "live bytes after the delete",0
	LD HL,e_1000
	LD DE,mt_waste
	LD BC,3
	CALL t_mem_eq
	DB "1000 bytes of waste",0
	LD BC,2
	CALL t_count_is
	DB "two pieces",0
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "type 251 bytes",0
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "type 251 more",0
	CALL doc_metrics
	LD HL,e_39662
	LD DE,mt_live
	LD BC,3
	CALL t_mem_eq
	DB "live bytes after typing",0
	LD HL,e_502
	LD DE,mt_addstore
	LD BC,3
	CALL t_mem_eq
	DB "add store holds what was typed",0
	LD HL,e_502
	LD DE,mt_addlive
	LD BC,3
	CALL t_mem_eq
	DB "all of it is live",0
	LD HL,e_40662
	LD DE,mt_store
	LD BC,3
	CALL t_mem_eq
	DB "total stored bytes",0
	LD HL,e_1000
	LD DE,mt_waste
	LD BC,3
	CALL t_mem_eq
	DB "waste unchanged by typing",0
	LD HL,(mt_undo)
	LD A,H
	OR L
	CALL t_nz
	DB "undo history uses memory",0
	LD HL,100
	CALL cur_goto_line
	CALL doc_metrics
	LD DE,(mt_li)
	LD BC,24
	CALL t_eq16
	DB "line index: 6 entries of 4 bytes",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- compaction

test_compact_full:
	CALL t_section
	DB "compaction",0
	CALL ed_init
	CALL t_build_big
	LD HL,60
	LD (tv_ptr),HL
	CALL t_fragment
	LD HL,50
	CALL cur_goto_line
	CALL cur_right
	CALL cur_right
	CALL cur_right
	CALL t_save_cursor_text
	CALL t_state_save
	CALL t_sum_save
	LD HL,(doc_piece_count)
	LD DE,100
	OR A
	SBC HL,DE
	CALL t_nc
	DB "the document is fragmented",0
	CALL doc_metrics
	LD A,(mt_waste)
	OR A
	CALL t_nz
	DB "the deletes left waste behind",0
	CALL doc_compact
	CALL t_nc
	DB "compact",0
	LD BC,1
	CALL t_count_is
	DB "one piece after compaction",0
	CALL t_sum_same
	DB "same text",0
	LD IX,t_iter
	CALL t_doc_length
	LD BC,(tv_save + 6)
	CALL t_eq16
	DB "same length",0
	LD BC,(tv_save + 4)
	CALL t_nl_is
	DB "same newline count",0
	LD BC,(tv_save)
	LD DE,(tv_save + 2)
	CALL t_cursor_is
	DB "cursor keeps its line and column",0
	LD DE,t_lbuf
	LD BC,8
	CALL t_at_cursor
	DB "cursor keeps its place in the text",0
	CALL t_undo_none
	DB "history ended",0
	CALL doc_metrics
	LD HL,e_zero
	LD DE,mt_waste
	LD BC,3
	CALL t_mem_eq
	DB "no waste",0
	LD HL,e_zero
	LD DE,mt_addstore
	LD BC,3
	CALL t_mem_eq
	DB "add store released",0
	LD HL,mt_live
	LD DE,mt_store
	LD BC,3
	CALL t_mem_eq
	DB "stored bytes equal live bytes",0
	LD A,(doc_piece_count)
	LD B,1
	CALL t_eq8
	DB "piece count",0
	LD HL,s_z
	LD BC,1
	CALL t_ins
	DB "edit after compaction",0
	CALL ed_undo
	CALL t_zero
	DB "undo after compaction",0
	CALL t_sum_same
	DB "text as before the edit",0
	LD HL,100
	CALL cur_goto_line
	CALL t_zero
	DB "goto line in the compacted document",0
	CALL doc_close
	RET

test_compact_steps:
	CALL t_section
	DB "incremental compaction",0
	CALL ed_init
	CALL t_build_big
	LD HL,40
	LD (tv_ptr),HL
	CALL t_fragment
	CALL t_sum_save
	CALL compact_begin
	CALL t_zero
	DB "begin",0
	CALL compact_begin
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "already running",0
	LD HL,0
	LD (tv_n),HL
test_compact_steps_loop:
	LD BC,1000
	CALL compact_step
	CALL t_nc
	DB "step",0
	LD HL,(tv_n)
	INC HL
	LD (tv_n),HL
	OR A
	JR Z,test_compact_steps_loop
	LD HL,(tv_n)
	LD DE,30
	OR A
	SBC HL,DE
	CALL t_nc
	DB "it took many small steps",0
	LD BC,1
	CALL t_count_is
	DB "one piece at the end",0
	CALL t_sum_same
	DB "same text",0
	LD A,(cmp_active)
	CALL t_zero
	DB "no longer active",0
	; an edit in between makes it give up
	CALL t_state_save
	CALL compact_begin
	CALL t_zero
	DB "begin again",0
	LD BC,1000
	CALL compact_step
	CALL t_nc
	DB "one step",0
	LD B,0
	CALL t_eq8
	DB "more to do",0
	LD A,'Z'
	CALL ed_insert_char
	CALL t_zero
	DB "edit while compacting",0
	LD BC,1000
	CALL compact_step
	CALL t_c
	DB "the next step notices",0
	LD B,ERR_FAILURE
	CALL t_eq8
	DB "reports a failure",0
	LD A,(cmp_active)
	CALL t_zero
	DB "and stops",0
	LD IX,t_iter
	CALL t_doc_length
	LD HL,(tv_save + 6)
	INC HL
	LD B,H
	LD C,L
	CALL t_eq16
	DB "the edit is in the document",0
	CALL doc_compact
	CALL t_nc
	DB "a full compaction afterwards",0
	LD IX,t_iter
	CALL t_doc_length
	LD HL,(tv_save + 6)
	INC HL
	LD B,H
	LD C,L
	CALL t_eq16
	DB "length preserved",0
	LD BC,100
	CALL compact_step
	CALL t_c
	DB "stepping with nothing pending fails",0
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "as an invalid request",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- out of memory

test_compact_nomem:
	CALL t_section
	DB "compaction without enough memory",0
	CALL ed_init
	CALL t_build_big
	LD HL,30
	LD (tv_ptr),HL
	CALL t_fragment
	CALL t_sum_save
	LD HL,(doc_piece_count)
	LD (tv_n),HL
	XOR A
	LD (tv_a),A
test_compact_nomem_grab:
	LD A,BANK_METADATA
	CALL bank_alloc
	OR A
	JR NZ,test_compact_nomem_grabbed
	LD A,B
	LD (tv_a),A
	JR test_compact_nomem_grab
test_compact_nomem_grabbed:
	LD A,(tv_a)
	LD B,A
	CALL bank_release		; leave exactly one bank free
	CALL doc_compact
	CALL t_c
	DB "compaction fails",0
	LD B,ERR_NO_MORE_MEMORY
	CALL t_eq8
	DB "for lack of memory",0
	LD A,(cmp_active)
	CALL t_zero
	DB "nothing is left pending",0
	CALL t_sum_same
	DB "the document is untouched",0
	LD DE,(doc_piece_count)
	LD BC,(tv_n)
	CALL t_eq16
	DB "including its pieces",0
	LD A,BANK_METADATA
	CALL bank_free_type
	CALL doc_compact
	CALL t_nc
	DB "works once memory is back",0
	CALL t_sum_same
	DB "text preserved",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- automatic compaction

test_compact_auto:
	CALL t_section
	DB "automatic compaction",0
	CALL ed_init
	LD HL,700
	LD (tv_ptr),HL
test_compact_auto_loop:
	CALL cur_doc_start
	LD HL,s_x
	LD BC,1
	CALL t_ins
	DB "insert with a nearly full piece table",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_compact_auto_loop
	LD IX,t_iter
	CALL t_doc_length
	LD BC,700
	CALL t_eq16
	DB "all 700 inserts landed",0
	LD HL,(doc_piece_count)
	LD DE,PIECE_CAP
	OR A
	SBC HL,DE
	CALL t_c
	DB "the table never overflowed",0

	; replace all keeps going across compactions
	CALL ed_init
	LD HL,300
	LD (tv_ptr),HL
test_compact_auto_fill:
	LD HL,s_xsp
	LD BC,2
	CALL t_ins
	DB "fill",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_compact_auto_fill
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
	CALL t_zero
	DB "replace all",0
	LD DE,(tv_n)
	LD BC,300
	CALL t_eq16
	DB "all 300 replaced",0
	LD IX,t_iter
	CALL iter_init
	LD HL,300
	LD (tv_ptr),HL
test_compact_auto_check:
	LD DE,s_yysp
	LD BC,3
	CALL t_iter_eq
	DB "yy yy yy",0
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,test_compact_auto_check
	CALL iter_peek
	CALL t_c
	DB "nothing after the last yy",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- policy

test_policy:
	CALL t_section
	DB "compaction policy",0
	CALL ed_init
	CALL t_build_big
	CALL doc_needs_compaction
	CALL t_zero
	DB "a tidy document needs nothing",0
	LD HL,200
	LD (tv_ptr),HL
	CALL t_fragment
	LD HL,(doc_piece_count)
	LD DE,PIECE_SOFT + 1
	OR A
	SBC HL,DE
	CALL t_nc
	DB "more pieces than the soft limit",0
	CALL doc_needs_compaction
	LD B,1
	CALL t_eq8
	DB "too many pieces is reason 1",0
	CALL t_sum_save
	XOR A
	LD (tv_a + 2),A
test_policy_loop:
	CALL doc_maintain
	CALL t_nc
	DB "maintain",0
	LD HL,tv_a + 2
	INC (HL)
	CP MAINT_DONE
	JR NZ,test_policy_loop
	LD A,(tv_a + 2)
	CP 5
	CALL t_nc
	DB "it worked in slices",0
	CALL t_sum_same
	DB "same text",0
	CALL doc_needs_compaction
	CALL t_zero
	DB "tidy again",0
	CALL doc_maintain
	CALL t_zero
	DB "idle when there is nothing to do",0

	; waste
	CALL ed_init
	CALL t_build_big
	LD HL,10
	LD (cmp_waste_pages),HL
	CALL doc_needs_compaction
	CALL t_zero
	DB "no waste yet",0
	CALL cur_doc_start
	LD BC,3000
	CALL ed_delete
	CALL t_zero
	DB "delete 3000 bytes",0
	CALL doc_needs_compaction
	LD B,2
	CALL t_eq8
	DB "waste over the threshold is reason 2",0
	CALL t_sum_save
test_policy_loop2:
	CALL doc_maintain
	CALL t_nc
	DB "maintain again",0
	CP MAINT_DONE
	JR NZ,test_policy_loop2
	CALL t_sum_same
	DB "same text after the waste was dropped",0
	CALL doc_metrics
	LD HL,e_zero
	LD DE,mt_waste
	LD BC,3
	CALL t_mem_eq
	DB "no waste",0
	LD HL,128
	LD (cmp_waste_pages),HL
	CALL doc_close
	RET

; ---------------------------------------------------------------- line index

test_line_rebuild:
	CALL t_section
	DB "line index rebuild",0
	CALL ed_init
	LD HL,300
	CALL t_build_lines
	CALL line_index_rebuild
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "rebuilt: 18 entries",0
	LD HL,7
	LD (doc_newlines),HL
	CALL line_index_rebuild
	LD BC,300
	CALL t_nl_is
	DB "rebuild recounts the newlines",0
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "still 18 entries",0
	LD HL,299
	CALL t_goto_expect
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "lookups use the prebuilt entries",0
	; building in slices
	LD HL,0
	LD (li_count),HL
	LD B,5
	CALL line_index_step
	CALL t_nc
	DB "first slice",0
	LD DE,(li_count)
	LD BC,5
	CALL t_eq16
	DB "5 entries",0
	LD B,5
	CALL line_index_step
	LD B,5
	CALL line_index_step
	LD DE,(li_count)
	LD BC,15
	CALL t_eq16
	DB "15 entries after three slices",0
	LD B,5
	CALL line_index_step
	CALL t_c
	DB "the last slice reaches the end",0
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "18 entries",0
	LD B,5
	CALL line_index_step
	CALL t_c
	DB "nothing more to add",0
	; compaction invalidates it, a rebuild fixes it
	CALL doc_compact
	CALL t_nc
	DB "compact",0
	LD DE,(li_count)
	LD BC,0
	CALL t_eq16
	DB "compaction empties the index",0
	CALL line_index_rebuild
	LD DE,(li_count)
	LD BC,18
	CALL t_eq16
	DB "rebuilt on the new pieces",0
	LD HL,250
	CALL t_goto_expect
	LD HL,17
	CALL t_goto_expect
	CALL doc_close
	RET

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
