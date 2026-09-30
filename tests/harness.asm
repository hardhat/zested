; zested - minimal unit-test harness.
; Results go to the serial console. The process exit code (semihost EXIT) is the number of
; failed checks, so zero means success. Assertion routines take an inline NUL-terminated
; message right after the CALL; they clobber HL and flags-dependent state as noted.

DEFVARS vars_end
{
	t_checks	ds.w 1
	t_fails		ds.w 1
	t_ctx		ds.b 1		; 0xFF = none, otherwise shown as [ctx] on failures
	t_dir		ds.b 1
	t_tmp		ds.w 1
	t_msg		ds.w 1
	t_ret		ds.w 1
	t_idx		ds.w 1
	t_iter		ds.b IT_SIZE
	tv_banks	ds.b 8
	tv_a		ds.b 8
	tv_ptr		ds.w 1
	tv_base		ds.b 1
	t_blk		ds.b 256
}

t_init:
	LD HL,0
	LD (t_checks),HL
	LD (t_fails),HL
	LD A,0xFF
	LD (t_ctx),A
	RET

t_count:
	PUSH HL
	LD HL,(t_checks)
	INC HL
	LD (t_checks),HL
	POP HL
	RET

; HL = string -> HL just past its NUL. Preserves AF.
t_skip:
	PUSH AF
t_skip_loop:
	LD A,(HL)
	INC HL
	OR A
	JR NZ,t_skip_loop
	POP AF
	RET

; HL = message. Prints "FAIL: message [ctx]", counts the failure, leaves HL past the message.
t_failhdr:
	PUSH AF
	PUSH HL
	LD HL,(t_fails)
	INC HL
	LD (t_fails),HL
	LD HL,t_s_fail
	CALL DbgStr
	POP HL
	CALL DbgStr
	LD A,(t_ctx)
	CP 0xFF
	JR Z,t_failhdr_ret
	PUSH HL
	LD HL,t_s_ctx
	CALL DbgStr
	CALL DbgA
	LD HL,t_s_rb
	CALL DbgStr
	POP HL
t_failhdr_ret:
	POP AF
	RET

t_nl:
	PUSH AF
	PUSH HL
	LD HL,t_s_nl
	CALL DbgStr
	POP HL
	POP AF
	RET

; Flag assertions: t_c (carry set), t_nc, t_z, t_nz. Flags and A are preserved.
t_c:
	POP HL
	JR C,t_ok
	JR t_bad
t_nc:
	POP HL
	JR NC,t_ok
	JR t_bad
t_z:
	POP HL
	JR Z,t_ok
	JR t_bad
t_nz:
	POP HL
	JR NZ,t_ok
t_bad:
	CALL t_count
	CALL t_failhdr
	CALL t_nl
	PUSH HL
	RET
t_ok:
	CALL t_count
	CALL t_skip
	PUSH HL
	RET

; A must be zero. Preserves BC, DE.
t_zero:
	POP HL
	OR A
	JR Z,t_ok
	LD (t_tmp),A
	CALL t_count
	CALL t_failhdr
	PUSH HL
	LD HL,t_s_got
	CALL DbgStr
	LD A,(t_tmp)
	CALL DbgA
	CALL t_nl
	POP HL
	LD A,(t_tmp)
	PUSH HL
	RET

; A = actual, B = expected. Preserves BC, DE.
t_eq8:
	POP HL
	CP B
	JR Z,t_ok
	LD (t_tmp),A
	LD A,B
	LD (t_tmp + 1),A
	CALL t_count
	CALL t_failhdr
	PUSH HL
	LD HL,t_s_got
	CALL DbgStr
	LD A,(t_tmp)
	CALL DbgA
	LD HL,t_s_exp
	CALL DbgStr
	LD A,(t_tmp + 1)
	CALL DbgA
	CALL t_nl
	POP HL
	LD A,(t_tmp)
	PUSH HL
	RET

; DE = actual, BC = expected (16 bit). Preserves BC, DE.
t_eq16:
	POP HL
	LD A,D
	CP B
	JR NZ,t_eq16_bad
	LD A,E
	CP C
	JR Z,t_ok
t_eq16_bad:
	CALL t_count
	CALL t_failhdr
	PUSH HL
	LD HL,t_s_got
	CALL DbgStr
	CALL DbgDE
	LD HL,t_s_exp
	CALL DbgStr
	CALL DbgBC
	CALL t_nl
	POP HL
	PUSH HL
	RET

; HL = expected bytes, DE = actual bytes, BC = length. Clobbers A, BC, DE, HL.
t_mem_eq:
	LD (t_tmp),HL
	POP HL
	LD (t_msg),HL
	CALL t_skip
	LD (t_ret),HL
	LD HL,(t_tmp)
t_mem_eq_loop:
	LD A,B
	OR C
	JR Z,t_mem_eq_ok
	LD A,(DE)
	CP (HL)
	JR NZ,t_mem_eq_bad
	INC HL
	INC DE
	DEC BC
	JR t_mem_eq_loop
t_mem_eq_ok:
	CALL t_count
	LD HL,(t_ret)
	PUSH HL
	RET
t_mem_eq_bad:
	LD (t_tmp),A
	LD A,(HL)
	LD (t_tmp + 1),A
	CALL t_count
	LD HL,(t_msg)
	CALL t_failhdr
	LD HL,t_s_got
	CALL DbgStr
	LD A,(t_tmp)
	CALL DbgA
	LD HL,t_s_exp
	CALL DbgStr
	LD A,(t_tmp + 1)
	CALL DbgA
	CALL t_nl
	LD HL,(t_ret)
	PUSH HL
	RET

; IX = iterator, DE = expected bytes, BC = length. Reads forward with iter_next.
; Clobbers A, BC, DE, HL.
t_iter_eq:
	XOR A
	LD (t_dir),A
	JR t_iter_run
; IX = iterator, DE = expected bytes END (one past), BC = length. Reads backward with iter_prev.
t_iter_eq_rev:
	LD A,1
	LD (t_dir),A
t_iter_run:
	POP HL
	LD (t_msg),HL
	CALL t_skip
	LD (t_ret),HL
	LD HL,0
	LD (t_idx),HL
t_iter_loop:
	LD A,B
	OR C
	JR Z,t_iter_ok
	LD A,(t_dir)
	OR A
	JR NZ,t_iter_back
	CALL iter_next
	JR C,t_iter_eof
	LD H,A
	LD A,(DE)
	INC DE
	JR t_iter_cmp
t_iter_back:
	CALL iter_prev
	JR C,t_iter_eof
	LD H,A
	DEC DE
	LD A,(DE)
t_iter_cmp:
	CP H
	JR NZ,t_iter_bad
	DEC BC
	LD HL,(t_idx)
	INC HL
	LD (t_idx),HL
	JR t_iter_loop
t_iter_ok:
	CALL t_count
	LD HL,(t_ret)
	PUSH HL
	RET
t_iter_bad:
	LD (t_tmp + 1),A	; expected
	LD A,H
	LD (t_tmp),A		; got
	CALL t_count
	LD HL,(t_msg)
	CALL t_failhdr
	LD HL,t_s_at
	CALL DbgStr
	LD HL,(t_idx)
	CALL DbgHL
	LD HL,t_s_got
	CALL DbgStr
	LD A,(t_tmp)
	CALL DbgA
	LD HL,t_s_exp
	CALL DbgStr
	LD A,(t_tmp + 1)
	CALL DbgA
	CALL t_nl
	LD HL,(t_ret)
	PUSH HL
	RET
t_iter_eof:
	CALL t_count
	LD HL,(t_msg)
	CALL t_failhdr
	LD HL,t_s_early
	CALL DbgStr
	LD HL,(t_idx)
	CALL DbgHL
	CALL t_nl
	LD HL,(t_ret)
	PUSH HL
	RET

; Prints "== name" for the NUL-terminated string after the CALL.
t_section:
	POP HL
	PUSH HL
	LD HL,t_s_sec
	CALL DbgStr
	POP HL
	CALL DbgStr
	CALL t_nl
	PUSH HL
	RET

; Prints the summary and exits through the semihost interface with the failure count.
t_finish:
	LD HL,t_s_sum
	CALL DbgStr
	LD HL,(t_checks)
	CALL DbgHL
	LD HL,t_s_fails
	CALL DbgStr
	LD HL,(t_fails)
	CALL DbgHL
	CALL t_nl
	LD HL,(t_fails)
	LD A,H
	OR L
	JR NZ,t_finish_bad
	LD HL,t_s_pass
	CALL DbgStr
	XOR A
	JR t_finish_exit
t_finish_bad:
	LD HL,t_s_bad
	CALL DbgStr
	LD HL,(t_fails)
	LD A,H
	OR A
	LD A,L
	JR Z,t_finish_exit
	LD A,255
t_finish_exit:
	LD L,A
	XOR A			; semihost command 0 = exit, status in L
	OUT (0x10),A
t_halt:
	JR t_halt

t_s_fail:	DB "FAIL: ",0
t_s_ctx:	DB " [ctx=",0
t_s_rb:		DB "]",0
t_s_got:	DB " got=",0
t_s_exp:	DB " exp=",0
t_s_at:		DB " at=",0
t_s_early:	DB " (early EOF) at=",0
t_s_sec:	DB "== ",0
t_s_sum:	DB "checks=",0
t_s_fails:	DB " fails=",0
t_s_pass:	DB "ALL TESTS PASSED",13,10,0
t_s_bad:	DB "TESTS FAILED",13,10,0
t_s_nl:		DB 13,10,0
