; zested - benchmarks. `make bench` runs this in zeal-native; the emulator's semihost counters
; report the t-states each measured region took.
	include "zos_sys.asm"
	include "zos_err.asm"
	include "defs.asm"

	org 0x4000

	JP test_start

bench_start:
	PUSH AF
	PUSH HL
	LD L,0
	LD A,8			; semihost COUNTER_START, counter 0
	OUT (0x10),A
	POP HL
	POP AF
	RET

bench_stop:
	PUSH AF
	PUSH HL
	LD L,0
	LD A,9			; semihost COUNTER_STOP
	OUT (0x10),A
	POP HL
	POP AF
	RET

test_start:
	CALL DbgSerialOpen
	CALL t_init
	CALL bank_init
	CALL ed_init
	LD IX,t_iter
	CALL bench_banks
	CALL bench_iter
	CALL bench_cursor
	CALL bench_typing
	CALL bench_search
	CALL bench_misc
	CALL doc_close
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

t_pat:
	CALL search_set
	JP t_zero

; 160 copies of t_blk (40160 bytes) typed into an empty document.
t_build_big:
	CALL t_fill_blk
	LD A,160
	LD (tv_a),A
t_build_big_loop:
	LD HL,t_blk
	LD BC,251
	CALL t_ins
	DB "build",0
	LD HL,tv_a
	DEC (HL)
	JR NZ,t_build_big_loop
	RET

; tv_ptr = iterations of: move 5, insert '#', delete 2 (about 2 pieces each).
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
	LD BC,2
	CALL ed_delete
	LD HL,(tv_ptr)
	DEC HL
	LD (tv_ptr),HL
	LD A,H
	OR L
	JR NZ,t_fragment_loop
	RET

s_miss1:	DB 255,1
s_miss2:	DB 1,255
s_hit:		DB 67,68,69,70,71,72
s_x:		DB "x"

; ---------------------------------------------------------------- bank switching

bench_banks:
	CALL DbgMsg
	DB "BENCH bank_select x200 (alternating banks)",13,10,0
	LD A,BANK_TEMP
	CALL bank_alloc
	LD A,B
	LD (tv_banks),A
	LD A,BANK_TEMP
	CALL bank_alloc
	LD A,B
	LD (tv_banks + 1),A
	CALL bench_start
	LD B,100
bench_banks_loop:
	PUSH BC
	LD A,(tv_banks)
	CALL bank_select
	LD A,(tv_banks + 1)
	CALL bank_select
	POP BC
	DJNZ bench_banks_loop
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH bank_select x200 (same bank)",13,10,0
	CALL bench_start
	LD B,100
bench_banks_same:
	PUSH BC
	LD A,(tv_banks)
	CALL bank_select
	LD A,(tv_banks)
	CALL bank_select
	POP BC
	DJNZ bench_banks_same
	CALL bench_stop
	LD A,BANK_TEMP
	CALL bank_free_type
	RET

; ---------------------------------------------------------------- iteration

bench_iter:
	CALL ed_init
	CALL t_build_big
	LD IX,t_iter
	CALL iter_init
	CALL DbgMsg
	DB "BENCH iter_next over 40160 bytes",13,10,0
	CALL bench_start
bench_iter_next:
	CALL iter_next
	JR NC,bench_iter_next
	CALL bench_stop
	CALL iter_seek_end
	CALL DbgMsg
	DB "BENCH iter_prev over 40160 bytes",13,10,0
	CALL bench_start
bench_iter_prev:
	CALL iter_prev
	JR NC,bench_iter_prev
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH doc_count_all (chunks) over 40160 bytes",13,10,0
	CALL bench_start
	CALL doc_count_all
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH doc_save-style chunk walk over 40160 bytes",13,10,0
	LD IX,t_iter
	CALL iter_init
	CALL bench_start
bench_iter_chunk:
	CALL iter_chunk
	JR C,bench_iter_chunk_done
	CALL iter_skip
	JR bench_iter_chunk
bench_iter_chunk_done:
	CALL bench_stop
	RET

; ---------------------------------------------------------------- cursor

bench_cursor:
	CALL ed_init
	LD HL,100
	CALL t_build_lines
	CALL cur_doc_start
	CALL DbgMsg
	DB "BENCH cur_right x1000",13,10,0
	CALL bench_start
	LD HL,1000
bench_cursor_right:
	PUSH HL
	CALL cur_right
	POP HL
	DEC HL
	LD A,H
	OR L
	JR NZ,bench_cursor_right
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH cur_left x1000",13,10,0
	CALL bench_start
	LD HL,1000
bench_cursor_left:
	PUSH HL
	CALL cur_left
	POP HL
	DEC HL
	LD A,H
	OR L
	JR NZ,bench_cursor_left
	CALL bench_stop
	CALL cur_doc_start
	CALL DbgMsg
	DB "BENCH cur_down x50",13,10,0
	CALL bench_start
	LD B,50
bench_cursor_down:
	PUSH BC
	CALL cur_down
	POP BC
	DJNZ bench_cursor_down
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH cur_up x50",13,10,0
	CALL bench_start
	LD B,50
bench_cursor_up:
	PUSH BC
	CALL cur_up
	POP BC
	DJNZ bench_cursor_up
	CALL bench_stop
	; a long line for home/end
	CALL cur_doc_start
	CALL cur_end
	LD B,4
bench_cursor_long:
	PUSH BC
	LD HL,t_blk
	LD BC,200
	CALL ed_insert
	POP BC
	DJNZ bench_cursor_long
	CALL DbgMsg
	DB "BENCH cur_home x20 (column 800)",13,10,0
	CALL bench_start
	LD B,20
bench_cursor_home:
	PUSH BC
	CALL cur_home
	CALL cur_end
	POP BC
	DJNZ bench_cursor_home
	CALL bench_stop
	RET

; ---------------------------------------------------------------- typing

bench_typing:
	CALL ed_init
	LD A,0x5A
	CALL DbgMsg
	DB "BENCH ed_insert_char x300 at the end of an empty document",13,10,0
	CALL bench_start
	LD B,100
bench_typing_a:
	PUSH BC
	LD A,'a'
	CALL ed_insert_char
	LD A,'b'
	CALL ed_insert_char
	LD A,'c'
	CALL ed_insert_char
	POP BC
	DJNZ bench_typing_a
	CALL bench_stop
	CALL ed_init
	CALL t_build_big
	LD HL,200
	LD (tv_ptr),HL
	CALL DbgMsg
	DB "BENCH 200 scattered edits (insert+delete) in a 40K document",13,10,0
	CALL bench_start
	CALL t_fragment
	CALL bench_stop
	CALL cur_doc_start
	CALL DbgMsg
	DB "BENCH ed_insert_char x50 at the start with about 400 pieces",13,10,0
	CALL bench_start
	LD B,50
bench_typing_b:
	PUSH BC
	CALL cur_doc_start
	LD A,'q'
	CALL ed_insert_char
	POP BC
	DJNZ bench_typing_b
	CALL bench_stop
	CALL cur_doc_start
	CALL DbgMsg
	DB "BENCH ed_insert_char x50 contiguous at the start with about 400 pieces",13,10,0
	CALL bench_start
	LD B,50
bench_typing_c:
	PUSH BC
	LD A,'r'
	CALL ed_insert_char
	POP BC
	DJNZ bench_typing_c
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH ed_backspace x50 with about 400 pieces",13,10,0
	CALL bench_start
	LD B,50
bench_typing_bs:
	PUSH BC
	CALL ed_backspace
	POP BC
	DJNZ bench_typing_bs
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH ed_undo x50 with about 400 pieces",13,10,0
	CALL bench_start
	LD B,50
bench_typing_undo:
	PUSH BC
	CALL ed_undo
	POP BC
	DJNZ bench_typing_undo
	CALL bench_stop
	RET

; ---------------------------------------------------------------- search

bench_search:
	CALL ed_init
	CALL t_build_big
	LD HL,s_miss1
	LD BC,2
	CALL t_pat
	DB "p",0
	LD IX,t_iter
	CALL iter_init
	CALL sr_reset
	CALL DbgMsg
	DB "BENCH search_fwd miss over 40160 bytes",13,10,0
	CALL bench_start
	CALL search_fwd
	CALL bench_stop
	LD HL,s_miss2
	LD BC,2
	CALL t_pat
	DB "p",0
	CALL iter_init
	CALL sr_reset
	CALL DbgMsg
	DB "BENCH search_fwd miss with 160 false starts",13,10,0
	CALL bench_start
	CALL search_fwd
	CALL bench_stop
	LD HL,s_miss1
	LD BC,2
	CALL t_pat
	DB "p",0
	CALL iter_seek_end
	CALL sr_reset
	CALL DbgMsg
	DB "BENCH search_back miss over 40160 bytes",13,10,0
	CALL bench_start
	CALL search_back
	CALL bench_stop
	LD HL,s_hit
	LD BC,6
	CALL t_pat
	DB "p",0
	CALL cur_doc_start
	CALL DbgMsg
	DB "BENCH ed_find_next x20 (hit every 251 bytes)",13,10,0
	CALL bench_start
	LD B,20
bench_search_next:
	PUSH BC
	CALL ed_find_next
	POP BC
	DJNZ bench_search_next
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH ed_find_prev x20",13,10,0
	CALL bench_start
	LD B,20
bench_search_prev:
	PUSH BC
	CALL ed_find_prev
	POP BC
	DJNZ bench_search_prev
	CALL bench_stop
	RET

; ---------------------------------------------------------------- everything else

bench_misc:
	CALL ed_init
	LD HL,300
	CALL t_build_lines
	CALL DbgMsg
	DB "BENCH line_find 299 (index built on demand)",13,10,0
	LD IX,t_iter
	LD HL,299
	CALL bench_start
	CALL line_find
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH line_find 299 (index ready)",13,10,0
	LD HL,299
	CALL bench_start
	CALL line_find
	CALL bench_stop
	CALL ed_init
	CALL t_build_big
	LD HL,100
	LD (tv_ptr),HL
	CALL t_fragment
	CALL DbgMsg
	DB "BENCH doc_compact of a fragmented 40K document",13,10,0
	CALL bench_start
	CALL doc_compact
	CALL bench_stop
	CALL DbgMsg
	DB "BENCH doc_position x20 at the end",13,10,0
	LD IX,cur_it
	CALL iter_seek_end
	CALL bench_start
	LD B,20
bench_misc_pos:
	PUSH BC
	CALL doc_position
	POP BC
	DJNZ bench_misc_pos
	CALL bench_stop
	RET

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
