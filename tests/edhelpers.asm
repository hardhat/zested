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
