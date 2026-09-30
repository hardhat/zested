; zested - Phase 1 (core document) tests. Run with `make test`.
	include "zos_sys.asm"
	include "zos_err.asm"
	include "defs.asm"

	org 0x4000

test_start:
	CALL DbgSerialOpen
	CALL t_init
	CALL bank_init
	CALL doc_init
	CALL t_free_banks
	LD (tv_base),A
	LD IX,t_iter
	CALL test_bank
	CALL test_addr
	CALL test_add_store
	CALL test_pieces
	CALL test_iter
	CALL test_iter_big
	CALL test_insert
	CALL test_fileio
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
	include "harness.asm"

; ---------------------------------------------------------------- helpers

; A = bank -> A = its type.
t_type_of:
	PUSH HL
	PUSH DE
	LD E,A
	LD D,0
	LD HL,bank_type
	ADD HL,DE
	LD A,(HL)
	POP DE
	POP HL
	RET

; A = index into tv_banks -> A = bank id.
t_bank_id:
	PUSH HL
	PUSH DE
	LD E,A
	LD D,0
	LD HL,tv_banks
	ADD HL,DE
	LD A,(HL)
	POP DE
	POP HL
	RET

; HL = piece index, DE = expected 6-byte descriptor; inline message.
t_piece_is:
	CALL piece_addr
	EX DE,HL
	LD BC,PIECE_SIZE
	JP t_mem_eq

; IX = 6-byte descriptor (source, bank, page, offset, length) -> piece_append.
t_pa:
	LD A,(IX+0)
	LD B,(IX+1)
	LD D,(IX+2)
	LD E,(IX+3)
	LD L,(IX+4)
	LD H,(IX+5)
	JP piece_append

; HL = text, BC = length -> add to the add store and append a piece for it. Returns A = error.
t_addpiece:
	PUSH BC
	CALL add_append
	POP HL
	OR A
	RET NZ
	LD A,SRC_ADD
	JP piece_append

; Consumes one byte of the add store without creating a piece (breaks contiguity).
t_gap:
	LD HL,t_blk
	LD BC,1
	JP add_append

; Chains fake banks 40..43 so piece arithmetic can be tested without real pages.
t_fake_chain:
	CALL t_fake_unchain
	LD A,40
	LD B,41
	CALL bank_link
	LD A,41
	LD B,42
	CALL bank_link
	LD A,42
	LD B,43
	JP bank_link

; Removes the fake chain so the ids can be handed out as real banks later.
t_fake_unchain:
	LD HL,bank_next + 40
	LD DE,bank_next + 41
	LD BC,3
	LD (HL),0
	LDIR
	LD HL,bank_prev + 40
	LD DE,bank_prev + 41
	LD BC,3
	LD (HL),0
	LDIR
	RET

; Builds the document "12ab345" through edits (typing, mid-piece insert, insert that merges).
t_build_edit:
	CALL doc_init
	LD IX,t_iter
	CALL iter_seek_end
	LD HL,s_12345
	LD BC,5
	CALL doc_insert
	CALL t_zero
	DB "build: insert 12345",0
	LD HL,0
	LD DE,2
	CALL iter_seek
	CALL t_zero
	DB "build: seek",0
	LD HL,s_a
	LD BC,1
	CALL doc_insert
	CALL t_zero
	DB "build: insert a",0
	LD HL,2
	LD DE,0
	CALL iter_seek
	CALL t_zero
	DB "build: seek 2",0
	LD HL,s_b
	LD BC,1
	CALL doc_insert
	CALL t_zero
	DB "build: insert b",0
	RET

; Adds A whole copies of t_blk (251 bytes each) to the end of the document.
t_build_blocks:
	LD (tv_a + 1),A
t_build_blocks_loop:
	LD HL,t_blk
	LD BC,251
	CALL t_addpiece
	CALL t_zero
	DB "build blocks",0
	LD HL,tv_a + 1
	DEC (HL)
	JR NZ,t_build_blocks_loop
	RET

; IX = iterator, tv_a+1 = block count: expects that many t_blk copies from the current position.
t_expect_blocks:
t_expect_blocks_loop:
	LD DE,t_blk
	LD BC,251
	CALL t_iter_eq
	DB "iterate blocks",0
	LD HL,tv_a + 1
	DEC (HL)
	JR NZ,t_expect_blocks_loop
	RET

; ---------------------------------------------------------------- bank allocator

test_bank:
	CALL t_section
	DB "bank allocator",0
	CALL doc_init
	LD A,BANK_ORIGINAL
	CALL bank_alloc
	LD A,B
	LD (tv_banks),A
	CP BANK_TABLE_SIZE
	CALL t_c
	DB "bank id < 64",0
	LD A,(tv_banks)
	OR A
	CALL t_nz
	DB "bank id != 0",0
	LD A,(tv_banks)
	CALL t_type_of
	LD B,BANK_ORIGINAL
	CALL t_eq8
	DB "type table records ORIGINAL",0
	LD A,BANK_ADD
	CALL bank_alloc
	CALL t_zero
	DB "alloc second bank",0
	LD A,B
	LD (tv_banks + 1),A
	LD A,(tv_banks)
	LD C,A
	LD A,B
	CP C
	CALL t_nz
	DB "banks are distinct",0
	; each bank keeps its own contents when switching
	LD A,(tv_banks)
	CALL bank_select
	LD A,0x11
	LD (BANK_WINDOW),A
	LD A,0x22
	LD (BANK_WINDOW + 0x3FFF),A
	LD A,0x33
	LD (BANK_WINDOW + 0x1234),A
	LD A,(tv_banks + 1)
	CALL bank_select
	LD A,0xAA
	LD (BANK_WINDOW),A
	LD A,0xBB
	LD (BANK_WINDOW + 0x3FFF),A
	LD A,0xCC
	LD (BANK_WINDOW + 0x1234),A
	LD A,(tv_banks)
	CALL bank_select
	LD A,(BANK_WINDOW)
	LD B,0x11
	CALL t_eq8
	DB "bank1 first byte",0
	LD A,(BANK_WINDOW + 0x3FFF)
	LD B,0x22
	CALL t_eq8
	DB "bank1 last byte",0
	LD A,(BANK_WINDOW + 0x1234)
	LD B,0x33
	CALL t_eq8
	DB "bank1 middle byte",0
	LD A,(tv_banks + 1)
	CALL bank_select
	LD A,(BANK_WINDOW)
	LD B,0xAA
	CALL t_eq8
	DB "bank2 first byte",0
	LD A,(BANK_WINDOW + 0x3FFF)
	LD B,0xBB
	CALL t_eq8
	DB "bank2 last byte",0
	; chaining
	LD A,(tv_banks)
	LD B,A
	LD A,(tv_banks + 1)
	LD C,A
	LD A,B
	LD B,C
	CALL bank_link
	LD A,(tv_banks + 1)
	LD B,A
	LD A,(tv_banks)
	CALL bank_get_next
	CALL t_eq8
	DB "next(bank1) == bank2",0
	LD A,(tv_banks)
	LD B,A
	LD A,(tv_banks + 1)
	CALL bank_get_prev
	CALL t_eq8
	DB "prev(bank2) == bank1",0
	LD A,(tv_banks + 1)
	CALL bank_get_next
	CALL t_zero
	DB "next(bank2) == none",0
	; release
	LD A,BANK_ADD
	CALL bank_free_type
	LD A,(tv_banks + 1)
	CALL t_type_of
	LD B,BANK_POOL
	CALL t_eq8
	DB "released bank goes to the pool",0
	LD A,(tv_banks)
	CALL bank_get_next
	CALL t_zero
	DB "freeing a bank unlinks its predecessor",0
	LD A,(tv_banks)
	CALL t_type_of
	LD B,BANK_ORIGINAL
	CALL t_eq8
	DB "ORIGINAL bank untouched",0
	; exhaust the OS pool
	XOR A
	LD (tv_a),A
test_bank_exhaust:
	LD A,BANK_TEMP
	CALL bank_alloc
	OR A
	JR NZ,test_bank_exhausted
	LD HL,tv_a
	INC (HL)
	JR test_bank_exhaust
test_bank_exhausted:
	LD B,ERR_NO_MORE_MEMORY
	CALL t_eq8
	DB "alloc fails cleanly when out of memory",0
	LD A,(tv_a)
	CP 8
	CALL t_nc
	DB "at least 8 banks were available",0
	LD A,BANK_TEMP
	CALL bank_free_type
	LD A,BANK_TEMP
	CALL bank_alloc
	CALL t_zero
	DB "alloc works again after freeing",0
	LD A,BANK_TEMP
	CALL bank_free_type
	CALL doc_close
	CALL bank_trim
	CALL t_free_banks
	LD HL,tv_base
	LD B,(HL)
	CALL t_eq8
	DB "bank_trim keeps every page accounted for",0
	RET

; ---------------------------------------------------------------- address arithmetic

; Row: in bank index, in page, in offset, delta (16), expect carry, out bank index, out page, out offset
addr_rows:
	DB 0, 0, 0
	DW 10
	DB 0, 0, 0, 10
	DB 0, 63, 250
	DW 10
	DB 0, 1, 0, 4
	DB 0, 0, 0
	DW 0x4000
	DB 0, 1, 0, 0
	DB 0, 63, 255
	DW 1
	DB 0, 1, 0, 0
	DB 3, 63, 255
	DW 1
	DB 1, 0, 0, 0
	DB 0, 0, 0
	DW 0xFFFF
	DB 0, 3, 63, 255
	DB 0, 10, 20
	DW 0
	DB 0, 0, 10, 20
	DB 1, 5, 5
	DW 0x8000
	DB 0, 3, 5, 5
	DB 2, 0, 0
	DW 0xC000
	DB 1, 0, 0, 0
	DB 0, 63, 0
	DW 0x100
	DB 0, 1, 0, 0
	DB 0xFF

test_addr:
	CALL t_section
	DB "address arithmetic across banks",0
	CALL doc_init
	XOR A
	LD (tv_a),A
test_addr_alloc:
	LD A,BANK_ORIGINAL
	CALL bank_alloc
	CALL t_zero
	DB "alloc chain bank",0
	LD A,(tv_a)
	LD E,A
	LD D,0
	LD HL,tv_banks
	ADD HL,DE
	LD (HL),B
	OR A
	JR Z,test_addr_first
	DEC HL
	LD A,(HL)
	CALL bank_link
test_addr_first:
	LD HL,tv_a
	INC (HL)
	LD A,(HL)
	CP 4
	JR NZ,test_addr_alloc
	XOR A
	LD (t_ctx),A
	LD IX,addr_rows
test_addr_row:
	LD A,(IX+0)
	CP 0xFF
	JP Z,test_addr_done
	CALL t_bank_id
	LD D,(IX+1)
	LD E,(IX+2)
	LD L,(IX+3)
	LD H,(IX+4)
	CALL addr_add
	LD (tv_a + 4),A
	LD A,D
	LD (tv_a + 5),A
	LD A,E
	LD (tv_a + 6),A
	LD A,0
	RLA				; A = carry
	LD B,(IX+5)
	CALL t_eq8
	DB "addr_add carry flag",0
	LD A,B
	OR A
	JR NZ,test_addr_next
	LD A,(IX+6)
	CALL t_bank_id
	LD B,A
	LD A,(tv_a + 4)
	CALL t_eq8
	DB "addr_add bank",0
	LD A,(tv_a + 5)
	LD B,(IX+7)
	CALL t_eq8
	DB "addr_add page",0
	LD A,(tv_a + 6)
	LD B,(IX+8)
	CALL t_eq8
	DB "addr_add offset",0
test_addr_next:
	LD BC,9
	ADD IX,BC
	LD HL,t_ctx
	INC (HL)
	JP test_addr_row
test_addr_done:
	LD A,0xFF
	LD (t_ctx),A
	LD IX,t_iter
	CALL doc_close
	RET

; ---------------------------------------------------------------- add store

s_hello:	DB "Hello"
s_world:	DB " World"
s_digits:	DB "0123456789"
s_lower:	DB "abcdef"
s_xyz:		DB "XYZ"
s_all:		DB "0123456789abcdefXYZ"
s_tail:		DB "defXYZ"
s_tail2:	DB "abcdefXYZ"
s_12345:	DB "12345"
s_12ab345:	DB "12ab345"
s_a:		DB "a"
s_b:		DB "b"
s_xy:		DB "XY"
s_front:	DB ">>"
s_edited:	DB ">>HeXYllo"
s_hexyllo:	DB "HeXYllo"
s_z:		DB "Z"

test_add_store:
	CALL t_section
	DB "add store",0
	CALL doc_init
	LD HL,s_hello
	LD BC,5
	CALL add_append
	CALL t_zero
	DB "append Hello",0
	LD A,B
	LD (tv_a),A			; first add bank
	LD A,D
	LD B,0
	CALL t_eq8
	DB "first append starts at page 0",0
	LD A,E
	LD B,0
	CALL t_eq8
	DB "first append starts at offset 0",0
	LD HL,s_world
	LD BC,6
	CALL add_append
	CALL t_zero
	DB "append World",0
	LD A,(tv_a)
	LD C,A
	LD A,B
	CP C
	CALL t_z
	DB "second append uses the same bank",0
	LD A,E
	LD B,5
	CALL t_eq8
	DB "second append follows the first",0
	LD A,(tv_a)
	CALL bank_select
	LD HL,s_hello
	LD DE,BANK_WINDOW
	LD BC,11
	CALL t_mem_eq
	DB "Hello World stored contiguously",0
	; a 600-byte append crosses two page boundaries
	LD HL,0x4000
	LD BC,600
	CALL add_append
	CALL t_zero
	DB "append 600 bytes",0
	LD A,D
	LD B,0
	CALL t_eq8
	DB "600-byte append starts at page 0",0
	LD A,E
	LD B,11
	CALL t_eq8
	DB "600-byte append starts at offset 11",0
	LD A,(tv_a)
	CALL bank_select
	LD HL,0x4000
	LD DE,BANK_WINDOW + 11
	LD BC,600
	CALL t_mem_eq
	DB "600 bytes copied across pages",0
	LD A,(add_page)
	LD B,2
	CALL t_eq8
	DB "add_page after 611 bytes",0
	LD A,(add_off)
	LD B,99
	CALL t_eq8
	DB "add_off after 611 bytes",0
	; one append that crosses a bank boundary
	LD HL,0x4000
	LD BC,0x4000
	CALL add_append
	CALL t_zero
	DB "append 16KB",0
	LD A,(tv_a)
	LD B,A
	LD A,(add_bank)
	CP B
	CALL t_nz
	DB "add store moved to a second bank",0
	LD A,(add_bank)
	LD B,A
	LD A,(tv_a)
	CALL bank_get_next
	CALL t_eq8
	DB "banks of the add store are chained",0
	LD A,(tv_a)
	CALL bank_select
	LD HL,0x4000
	LD DE,BANK_WINDOW + 611
	LD BC,BANK_SIZE - 611
	CALL t_mem_eq
	DB "16KB append: part in first bank",0
	LD A,(add_bank)
	CALL bank_select
	LD HL,0x4000 + BANK_SIZE - 611
	LD DE,BANK_WINDOW
	LD BC,611
	CALL t_mem_eq
	DB "16KB append: part in second bank",0
	LD A,(add_page)
	LD B,2
	CALL t_eq8
	DB "add_page after crossing",0
	LD A,(add_off)
	LD B,99
	CALL t_eq8
	DB "add_off after crossing",0
	LD BC,0
	CALL add_append
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "zero-length append is rejected",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- piece table

pd_a:	DB SRC_ORIGINAL, 40, 0, 0
	DW 100
pd_b:	DB SRC_ORIGINAL, 40, 0, 100
	DW 50
pd_ab:	DB SRC_ORIGINAL, 40, 0, 0
	DW 150
pd_c:	DB SRC_ORIGINAL, 40, 1, 0
	DW 10
pd_d:	DB SRC_ADD, 40, 1, 10
	DW 5
pd_e:	DB SRC_ORIGINAL, 40, 63, 200
	DW 56
pd_f:	DB SRC_ORIGINAL, 41, 0, 0
	DW 10
pd_ef:	DB SRC_ORIGINAL, 40, 63, 200
	DW 66
pd_g:	DB SRC_ORIGINAL, 40, 0, 0
	DW 0xFFF0
pd_h:	DB SRC_ORIGINAL, 43, 63, 240
	DW 0x20
pd_split1:	DB SRC_ORIGINAL, 40, 0, 0
	DW 30
pd_split2:	DB SRC_ORIGINAL, 40, 0, 30
	DW 70
pd_x:	DB SRC_ADD, 40, 5, 200
	DW 150
pd_x1:	DB SRC_ADD, 40, 5, 200
	DW 100
pd_x2:	DB SRC_ADD, 40, 6, 44
	DW 50
pd_y:	DB SRC_ORIGINAL, 40, 63, 250
	DW 20
pd_y1:	DB SRC_ORIGINAL, 40, 63, 250
	DW 10
pd_y2:	DB SRC_ORIGINAL, 41, 0, 4
	DW 10
pd_new:	DB SRC_ORIGINAL, 40, 9, 9
	DW 9
pd_zero:	DB SRC_ORIGINAL, 40, 0, 0
	DW 0

test_pieces:
	CALL t_section
	DB "piece table: append and merge",0
	CALL doc_init
	CALL t_fake_chain
	LD IX,pd_a
	CALL t_pa
	CALL t_zero
	DB "append first piece",0
	LD BC,1
	CALL t_count_is
	DB "one piece",0
	LD IX,pd_b
	CALL t_pa
	CALL t_zero
	DB "append contiguous piece",0
	LD BC,1
	CALL t_count_is
	DB "contiguous pieces merge",0
	LD HL,0
	LD DE,pd_ab
	CALL t_piece_is
	DB "merged descriptor",0
	LD IX,pd_c
	CALL t_pa
	LD BC,2
	CALL t_count_is
	DB "non-contiguous piece is kept separate",0
	LD IX,pd_d
	CALL t_pa
	LD BC,3
	CALL t_count_is
	DB "different source never merges",0
	LD IX,pd_e
	CALL t_pa
	LD IX,pd_f
	CALL t_pa
	LD BC,4
	CALL t_count_is
	DB "piece ending at a bank end merges with next bank",0
	LD HL,3
	LD DE,pd_ef
	CALL t_piece_is
	DB "cross-bank merged descriptor",0
	LD IX,pd_g
	CALL t_pa
	LD IX,pd_h
	CALL t_pa
	LD BC,6
	CALL t_count_is
	DB "merge is refused when length would overflow 16 bits",0
	CALL doc_init
	CALL t_fake_chain
	LD IX,pd_zero
	CALL t_pa
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "zero-length piece is rejected",0
	LD BC,0
	CALL t_count_is
	DB "rejected piece not stored",0

	CALL t_section
	DB "piece table: split, insert, remove",0
	CALL doc_init
	CALL t_fake_chain
	LD IX,pd_a
	CALL t_pa
	LD HL,0
	LD DE,30
	CALL piece_split
	CALL t_zero
	DB "split at 30",0
	LD BC,2
	CALL t_count_is
	DB "split creates a second piece",0
	LD HL,0
	LD DE,pd_split1
	CALL t_piece_is
	DB "first half",0
	LD HL,1
	LD DE,pd_split2
	CALL t_piece_is
	DB "second half",0
	LD HL,1
	LD DE,0
	CALL piece_split
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "split at offset 0 rejected",0
	LD HL,1
	LD DE,70
	CALL piece_split
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "split at length rejected",0
	LD HL,1
	LD DE,71
	CALL piece_split
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "split past length rejected",0
	LD BC,2
	CALL t_count_is
	DB "rejected splits change nothing",0
	LD IX,pd_x
	CALL t_pa
	LD HL,2
	LD DE,100
	CALL piece_split
	CALL t_zero
	DB "split across a page boundary",0
	LD HL,2
	LD DE,pd_x1
	CALL t_piece_is
	DB "page split: first",0
	LD HL,3
	LD DE,pd_x2
	CALL t_piece_is
	DB "page split: second",0
	LD IX,pd_y
	CALL t_pa
	LD HL,4
	LD DE,10
	CALL piece_split
	CALL t_zero
	DB "split across a bank boundary",0
	LD HL,4
	LD DE,pd_y1
	CALL t_piece_is
	DB "bank split: first",0
	LD HL,5
	LD DE,pd_y2
	CALL t_piece_is
	DB "bank split: second",0
	LD BC,6
	CALL t_count_is
	DB "six pieces after splitting",0
	LD HL,1
	CALL piece_remove
	CALL t_zero
	DB "remove piece 1",0
	LD BC,5
	CALL t_count_is
	DB "count after remove",0
	LD HL,1
	LD DE,pd_x1
	CALL t_piece_is
	DB "later pieces shift down",0
	LD HL,4
	LD DE,pd_y2
	CALL t_piece_is
	DB "last piece shifts down",0
	LD HL,5
	CALL piece_remove
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "remove past the end rejected",0
	LD HL,1
	LD DE,pd_new
	CALL piece_insert
	CALL t_zero
	DB "insert in the middle",0
	LD HL,1
	LD DE,pd_new
	CALL t_piece_is
	DB "inserted piece in place",0
	LD HL,2
	LD DE,pd_x1
	CALL t_piece_is
	DB "later pieces shift up",0
	LD HL,7
	LD DE,pd_new
	CALL piece_insert
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "insert beyond the end rejected",0

	CALL t_section
	DB "piece table: capacity",0
	CALL doc_init
	CALL t_fake_chain
test_pieces_fill:
	LD HL,(doc_piece_count)
	LD DE,PIECE_CAP - 2
	OR A
	SBC HL,DE
	JR Z,test_pieces_filled
	LD HL,(doc_piece_count)
	LD DE,pd_c
	CALL piece_insert
	CALL t_zero
	DB "fill piece table",0
	JR test_pieces_fill
test_pieces_filled:
	LD HL,0
	LD DE,pd_new
	CALL piece_insert
	CALL t_zero
	DB "insert at front of a large table",0
	LD BC,PIECE_CAP - 1
	CALL t_count_is
	DB "count near capacity",0
	LD HL,0
	LD DE,pd_new
	CALL t_piece_is
	DB "front piece",0
	LD HL,1
	LD DE,pd_c
	CALL t_piece_is
	DB "second piece shifted",0
	LD HL,PIECE_CAP - 2
	LD DE,pd_c
	CALL t_piece_is
	DB "last piece shifted",0
	LD HL,0
	LD DE,pd_c
	CALL piece_insert
	CALL t_zero
	DB "insert into the last free slot",0
	LD HL,0
	LD DE,pd_c
	CALL piece_insert
	LD B,ERR_NO_MORE_ENTRIES
	CALL t_eq8
	DB "full piece table reports an error",0
	LD BC,PIECE_CAP
	CALL t_count_is
	DB "count stays at capacity",0
	CALL doc_init
	CALL t_fake_unchain
	RET

; ---------------------------------------------------------------- iterator

test_iter:
	CALL t_section
	DB "iterator: pieces and seeking",0
	CALL doc_init
	LD HL,s_digits
	LD BC,10
	CALL t_addpiece
	CALL t_zero
	DB "add piece 0",0
	CALL t_gap
	LD HL,s_lower
	LD BC,6
	CALL t_addpiece
	CALL t_zero
	DB "add piece 1",0
	CALL t_gap
	LD HL,s_xyz
	LD BC,3
	CALL t_addpiece
	CALL t_zero
	DB "add piece 2",0
	LD BC,3
	CALL t_count_is
	DB "three separate pieces",0
	LD IX,t_iter
	CALL iter_init
	LD DE,s_all
	LD BC,19
	CALL t_iter_eq
	DB "forward over piece boundaries",0
	CALL iter_peek
	CALL t_c
	DB "peek at EOF sets carry",0
	CALL iter_next
	CALL t_c
	DB "next at EOF sets carry",0
	LD DE,s_all + 19
	LD BC,19
	CALL t_iter_eq_rev
	DB "backward over piece boundaries",0
	CALL iter_prev
	CALL t_c
	DB "prev at start sets carry",0
	LD HL,1
	LD DE,3
	CALL iter_seek
	CALL t_zero
	DB "seek (1,3)",0
	LD DE,s_tail
	LD BC,6
	CALL t_iter_eq
	DB "read after seek",0
	LD HL,0
	LD DE,10
	CALL iter_seek
	CALL t_zero
	DB "seek to end of piece 0",0
	LD DE,s_tail2
	LD BC,9
	CALL t_iter_eq
	DB "end of piece == start of next",0
	LD HL,1
	LD DE,100
	CALL iter_seek
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "seek beyond piece rejected",0
	LD HL,2
	LD DE,0
	CALL iter_seek
	CALL iter_prev
	LD B,'f'
	CALL t_eq8
	DB "prev from a piece start reaches the previous piece",0
	CALL iter_seek_end
	CALL iter_peek
	CALL t_c
	DB "seek_end is EOF",0
	CALL iter_prev
	LD B,'Z'
	CALL t_eq8
	DB "prev from EOF",0
	CALL iter_init
	CALL iter_chunk
	CALL t_nc
	DB "chunk not at EOF",0
	LD D,B
	LD E,C
	LD BC,10
	CALL t_eq16
	DB "chunk is bounded by the piece",0
	CALL iter_init
	CALL iter_chunk
	EX DE,HL
	LD HL,s_digits
	LD BC,10
	CALL t_mem_eq
	DB "chunk points at the text",0
	CALL iter_init
	LD BC,10
	CALL iter_skip
	CALL iter_chunk
	LD D,B
	LD E,C
	LD BC,6
	CALL t_eq16
	DB "skip moves to the next piece",0
	CALL iter_seek_end
	CALL iter_chunk
	CALL t_c
	DB "chunk at EOF sets carry",0
	CALL doc_close
	; empty document
	CALL iter_init
	CALL iter_peek
	CALL t_c
	DB "empty document is EOF",0
	CALL iter_prev
	CALL t_c
	DB "empty document has no previous byte",0
	RET

test_iter_big:
	CALL t_section
	DB "iterator: text spanning banks",0
	CALL doc_init
	CALL t_fill_blk
	LD A,160
	CALL t_build_blocks
	LD BC,1
	CALL t_count_is
	DB "contiguous add-store text is one piece",0
	LD HL,0
	CALL piece_addr
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD BC,40160
	CALL t_eq16
	DB "piece length",0
	LD IX,t_iter
	CALL iter_init
	LD A,160
	LD (tv_a + 1),A
	CALL t_expect_blocks
	CALL iter_seek_end
	LD A,160
	LD (tv_a + 1),A
t_big_rev:
	LD DE,t_blk + 251
	LD BC,251
	CALL t_iter_eq_rev
	DB "backward over banks",0
	LD HL,tv_a + 1
	DEC (HL)
	JR NZ,t_big_rev
	; bank boundary at 16384 (block offset 69) and 32768 (block offset 138)
	LD HL,0
	LD DE,16384
	CALL iter_seek
	CALL t_zero
	DB "seek to first bank boundary",0
	CALL iter_prev
	LD HL,t_blk + 68
	LD B,(HL)
	CALL t_eq8
	DB "last byte of bank 1",0
	CALL iter_next
	LD HL,t_blk + 68
	LD B,(HL)
	CALL t_eq8
	DB "read last byte of bank 1",0
	CALL iter_next
	LD HL,t_blk + 69
	LD B,(HL)
	CALL t_eq8
	DB "first byte of bank 2",0
	CALL iter_prev
	CALL iter_prev
	LD HL,t_blk + 68
	LD B,(HL)
	CALL t_eq8
	DB "prev back over the boundary",0
	LD HL,0
	LD DE,32768
	CALL iter_seek
	CALL iter_prev
	LD HL,t_blk + 137
	LD B,(HL)
	CALL t_eq8
	DB "last byte of bank 2",0
	CALL iter_next
	CALL iter_next
	LD HL,t_blk + 138
	LD B,(HL)
	CALL t_eq8
	DB "first byte of bank 3",0
	LD HL,0
	LD DE,16000
	CALL iter_seek
	CALL iter_chunk
	LD D,B
	LD E,C
	LD BC,384
	CALL t_eq16
	DB "chunk stops at the bank end",0
	LD HL,0
	LD DE,16384
	CALL iter_seek
	CALL iter_chunk
	LD D,B
	LD E,C
	LD BC,16384
	CALL t_eq16
	DB "chunk covers a whole bank",0
	LD HL,0
	LD DE,32768
	CALL iter_seek
	CALL iter_chunk
	LD D,B
	LD E,C
	LD BC,7392
	CALL t_eq16
	DB "chunk stops at the piece end",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- insertion

test_insert:
	CALL t_section
	DB "insertion",0
	CALL doc_init
	LD IX,t_iter
	CALL iter_init
	LD HL,s_z
	LD BC,1
	CALL doc_insert
	CALL t_zero
	DB "insert into an empty document",0
	LD BC,1
	CALL t_count_is
	DB "one piece",0
	CALL doc_close
	LD A,(doc_dirty)
	CALL t_zero
	DB "document starts clean",0
	; typing one character at a time
	LD HL,s_hello
	LD (tv_ptr),HL
	LD A,5
	LD (tv_a),A
test_insert_type:
	CALL iter_seek_end
	LD HL,(tv_ptr)
	LD BC,1
	CALL doc_insert
	CALL t_zero
	DB "type a character",0
	LD HL,(tv_ptr)
	INC HL
	LD (tv_ptr),HL
	LD HL,tv_a
	DEC (HL)
	JR NZ,test_insert_type
	LD BC,1
	CALL t_count_is
	DB "typed characters coalesce into one piece",0
	CALL iter_init
	LD DE,s_hello
	LD BC,5
	CALL t_iter_eq
	DB "typed text",0
	LD A,(doc_dirty)
	LD B,1
	CALL t_eq8
	DB "insert marks the document dirty",0
	LD HL,0
	LD DE,2
	CALL iter_seek
	CALL t_zero
	DB "seek into the middle",0
	LD HL,s_xy
	LD BC,2
	CALL doc_insert
	CALL t_zero
	DB "insert in the middle",0
	LD BC,3
	CALL t_count_is
	DB "middle insert splits the piece",0
	CALL iter_init
	LD DE,s_hexyllo
	LD BC,7
	CALL t_iter_eq
	DB "text after middle insert",0
	CALL iter_init
	LD HL,s_front
	LD BC,2
	CALL doc_insert
	CALL t_zero
	DB "insert at the start",0
	LD BC,4
	CALL t_count_is
	DB "piece count after front insert",0
	CALL iter_init
	LD DE,s_edited
	LD BC,9
	CALL t_iter_eq
	DB "text after front insert",0
	LD DE,s_edited + 9
	LD BC,9
	CALL iter_seek_end
	CALL t_iter_eq_rev
	DB "backward over edited text",0
	LD HL,s_z
	LD BC,0
	CALL doc_insert
	LD B,ERR_INVALID_PARAMETER
	CALL t_eq8
	DB "empty insert rejected",0
	CALL doc_close
	CALL t_build_edit
	LD BC,3
	CALL t_count_is
	DB "insert next to earlier insert merges into it",0
	LD IX,t_iter
	CALL iter_init
	LD DE,s_12ab345
	LD BC,7
	CALL t_iter_eq
	DB "edited text",0
	CALL doc_close
	RET

; ---------------------------------------------------------------- files

f_small:	DB "H:/zested_small.txt",0
f_big:		DB "H:/zested_big.bin",0
f_bank:		DB "H:/zested_bank.bin",0
f_empty:	DB "H:/zested_empty.bin",0
f_missing:	DB "H:/zested_missing.bin",0

test_fileio:
	CALL t_section
	DB "file save and load",0
	CALL t_build_edit
	LD BC,f_small
	CALL doc_save
	CALL t_zero
	DB "save edited document",0
	LD A,(doc_dirty)
	CALL t_zero
	DB "save clears dirty",0
	CALL doc_close
	LD BC,f_small
	CALL doc_load
	CALL t_zero
	DB "load it back",0
	LD BC,1
	CALL t_count_is
	DB "loaded file is one piece",0
	LD IX,t_iter
	CALL iter_init
	LD DE,s_12ab345
	LD BC,7
	CALL t_iter_eq
	DB "loaded contents",0
	LD A,(doc_dirty)
	CALL t_zero
	DB "loaded document is clean",0
	CALL doc_close

	; multi-bank file, built in the add store then saved
	CALL doc_init
	CALL t_fill_blk
	LD A,160
	CALL t_build_blocks
	LD BC,f_big
	CALL doc_save
	CALL t_zero
	DB "save 40160-byte document",0
	CALL doc_close
	LD BC,f_big
	CALL doc_load
	CALL t_zero
	DB "load 40160-byte file",0
	LD BC,1
	CALL t_count_is
	DB "banks of the original store merge into one piece",0
	LD HL,0
	CALL piece_addr
	LD DE,P_LEN
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD BC,40160
	CALL t_eq16
	DB "loaded length",0
	LD IX,t_iter
	CALL iter_init
	LD A,160
	LD (tv_a + 1),A
	CALL t_expect_blocks
	CALL iter_peek
	CALL t_c
	DB "EOF after loaded data",0
	; the loaded copy can be saved again
	LD BC,f_bank
	CALL doc_save
	CALL t_zero
	DB "save a loaded document",0
	CALL doc_close

	; file that fills exactly one bank
	CALL doc_init
	LD A,65
	CALL t_build_blocks
	LD HL,t_blk
	LD BC,69
	CALL t_addpiece
	CALL t_zero
	DB "build 16384 bytes",0
	LD BC,f_bank
	CALL doc_save
	CALL t_zero
	DB "save exactly one bank",0
	CALL doc_close
	LD BC,f_bank
	CALL doc_load
	CALL t_zero
	DB "load exactly one bank",0
	LD BC,1
	CALL t_count_is
	DB "one bank, one piece",0
	LD IX,t_iter
	CALL iter_init
	LD A,65
	LD (tv_a + 1),A
	CALL t_expect_blocks
	LD DE,t_blk
	LD BC,69
	CALL t_iter_eq
	DB "tail of the one-bank file",0
	CALL iter_peek
	CALL t_c
	DB "EOF after one-bank file",0
	CALL doc_close

	; empty document
	CALL doc_init
	LD BC,f_empty
	CALL doc_save
	CALL t_zero
	DB "save empty document",0
	LD BC,f_empty
	CALL doc_load
	CALL t_zero
	DB "load empty file",0
	LD BC,0
	CALL t_count_is
	DB "empty file has no pieces",0
	CALL doc_close

	; missing file
	LD BC,f_missing
	CALL doc_load
	OR A
	CALL t_nz
	DB "loading a missing file fails",0
	LD BC,0
	CALL t_count_is
	DB "failed load leaves an empty document",0
	RET

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
