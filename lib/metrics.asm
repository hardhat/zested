; zested - fragmentation metrics, compaction policy and incremental line-index building.

; HL = 24-bit variable, DE = 24-bit variable: (HL) += (DE). Preserves all registers.
add24v:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD B,3
	OR A
add24v_loop:
	LD A,(DE)
	ADC A,(HL)
	LD (HL),A
	INC HL
	INC DE
	DJNZ add24v_loop
	POP HL
	POP DE
	POP BC
	POP AF
	RET

; HL = 24-bit variable, DE = 24-bit variable: (HL) -= (DE). Carry set if it went negative.
; Preserves all registers except the flags.
sub24v:
	PUSH BC
	PUSH DE
	PUSH HL
	LD B,3
	OR A
sub24v_loop:
	LD A,(HL)
	EX DE,HL
	SBC A,(HL)
	EX DE,HL
	LD (HL),A
	INC HL
	INC DE
	DJNZ sub24v_loop
	POP HL
	POP DE
	POP BC
	RET

; HL = 24-bit variable. Sets it to zero. Preserves all registers.
clr24:
	PUSH AF
	PUSH HL
	XOR A
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD (HL),A
	POP HL
	POP AF
	RET

; Measures the document into mt_live (bytes in the document), mt_addlive (of which from the
; add store), mt_addstore (bytes the add store has used), mt_store (original + add store bytes),
; mt_waste (stored bytes the document no longer uses), mt_undo (bytes of undo/redo history)
; and mt_li (bytes of line index). The piece count is doc_piece_count. Preserves all registers.
doc_metrics:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD HL,mt_live
	CALL clr24
	LD HL,mt_addlive
	CALL clr24
	LD IY,PIECE_TABLE
	LD BC,(doc_piece_count)
doc_metrics_loop:
	LD A,B
	OR C
	JR Z,doc_metrics_store
	LD E,(IY+P_LEN)
	LD D,(IY+P_LEN+1)
	LD HL,mt_live
	CALL add24
	LD A,(IY+P_SRC)
	OR A
	JR Z,doc_metrics_next
	LD HL,mt_addlive
	CALL add24
doc_metrics_next:
	LD DE,PIECE_SIZE
	ADD IY,DE
	DEC BC
	JR doc_metrics_loop
doc_metrics_store:
	LD HL,mt_addstore
	CALL clr24
	LD HL,bank_type
	LD B,BANK_TABLE_SIZE
	LD C,0
doc_metrics_banks:
	LD A,(HL)
	CP BANK_ADD
	JR NZ,doc_metrics_bnext
	INC C
doc_metrics_bnext:
	INC HL
	DJNZ doc_metrics_banks
	LD A,C
	OR A
	JR Z,doc_metrics_total
	DEC A
	LD C,A				; full banks before the current one
	AND 3
	RRCA
	RRCA
	LD D,A				; (banks mod 4) * 16384
	LD E,0
	LD HL,mt_addstore
	CALL add24
	LD A,(add_page)
	LD D,A
	LD A,(add_off)
	LD E,A
	CALL add24
	LD A,C
	SRL A
	SRL A
	LD HL,mt_addstore + 2
	ADD A,(HL)
	LD (HL),A
doc_metrics_total:
	LD HL,orig_bytes
	LD DE,mt_store
	LD BC,3
	LDIR
	LD HL,mt_store
	LD DE,mt_addstore
	CALL add24v
	LD HL,mt_store
	LD DE,mt_waste
	LD BC,3
	LDIR				; mt_waste = mt_store
	LD HL,mt_waste
	LD DE,mt_live
	CALL sub24v
	JR NC,doc_metrics_hist
	LD HL,mt_waste			; shared replacement text counts more than once in the document
	CALL clr24
doc_metrics_hist:
	LD HL,(ulog_desc+2)
	LD DE,(ulog_desc)
	OR A
	SBC HL,DE
	PUSH HL
	LD HL,(rlog_desc+2)
	LD DE,(rlog_desc)
	OR A
	SBC HL,DE
	POP DE
	ADD HL,DE
	LD (mt_undo),HL
	LD HL,(li_count)
	ADD HL,HL
	ADD HL,HL
	LD (mt_li),HL
	POP IY
	POP HL
	POP DE
	POP BC
	POP AF
	RET

; Returns A = 0 if the document is fine, 1 if it has too many pieces (more than PIECE_SOFT),
; 2 if too much of the stored text is unused (cmp_waste_pages or more).
doc_needs_compaction:
	PUSH BC
	PUSH DE
	PUSH HL
	LD HL,(doc_piece_count)
	LD DE,PIECE_SOFT + 1
	OR A
	SBC HL,DE
	JR C,doc_needs_waste
	LD A,1
	JR doc_needs_ret
doc_needs_waste:
	CALL doc_metrics
	LD HL,(mt_waste + 1)		; waste in 256-byte pages
	LD DE,(cmp_waste_pages)
	OR A
	SBC HL,DE
	LD A,2
	JR NC,doc_needs_ret
	XOR A
doc_needs_ret:
	OR A
	POP HL
	POP DE
	POP BC
	RET

; One slice of background upkeep for an idle editor: continues a pending compaction, or starts
; one when doc_needs_compaction says so. Returns A = MAINT_IDLE / MAINT_BUSY (call again) /
; MAINT_DONE, carry clear; or carry set with A = error (a compaction that an edit interrupted
; is simply started again by the next call).
doc_maintain:
	PUSH BC
	LD A,(cmp_active)
	OR A
	JR NZ,doc_maintain_step
	CALL doc_needs_compaction
	OR A
	JR Z,doc_maintain_idle
	CALL compact_begin
	OR A
	JR NZ,doc_maintain_err
doc_maintain_step:
	LD BC,4096
	CALL compact_step
	JR C,doc_maintain_err
	OR A
	LD A,MAINT_BUSY
	JR Z,doc_maintain_ret
	LD A,MAINT_DONE
	JR doc_maintain_ret
doc_maintain_idle:
	LD A,MAINT_IDLE
	JR doc_maintain_ret
doc_maintain_err:
	SCF
	POP BC
	RET
doc_maintain_ret:
	OR A
	POP BC
	RET
