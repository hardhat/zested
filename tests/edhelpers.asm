; Test helpers shared by the suites that include the editor.

t_line_is:
	LD DE,(cur_line)
	JP t_eq16

t_col_is:
	LD DE,(cur_col)
	JP t_eq16

t_nl_is:
	LD DE,(doc_newlines)
	JP t_eq16

; HL = text, BC = length -> ed_insert, expects success; inline message.
t_ins:
	CALL ed_insert
	JP t_zero

; DE = expected text, BC = length; the whole document must start with it. Inline message.
t_doc_is:
	LD IX,t_iter
	CALL iter_init
	JP t_iter_eq

; Follows t_doc_is: the document must end there. Inline message.
t_doc_eof:
	LD IX,t_iter
	CALL iter_peek
	JP t_c

; DE = expected text, BC = length; must appear at the cursor (the cursor does not move).
t_at_cursor:
	PUSH BC
	PUSH DE
	LD HL,cur_it
	LD DE,t_iter
	LD BC,IT_SIZE
	LDIR
	POP DE
	POP BC
	LD IX,t_iter
	JP t_iter_eq

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

; IX = t_iter, counts the bytes of the whole document into DE.
t_doc_length:
	CALL iter_init
	LD DE,0
t_doc_length_loop:
	CALL iter_next
	RET C
	INC DE
	JR t_doc_length_loop

