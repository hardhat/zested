; zested - serial debug output.
; Buffers passed to syscalls must live in virtual page 1 or 2, so all state here is in the code page.

DbgSerialOpen:
	LD BC,SerialPortName
	LD H, O_WRONLY
	OPEN
	LD (SerialPort),A ; File handle to serial port or error if negative.
	RET

DbgSerial:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH AF
	LD (SerialMsg),A
	LD A,(SerialPort)
	LD H,A
	LD DE,SerialMsg
	LD BC,1
	WRITE
	POP AF
	POP HL
	POP DE
	POP BC
	RET

DbgA:
	PUSH AF
	RRCA
	RRCA
	RRCA
	RRCA
	AND 15
	CP 10
	JR C,DbgA1
	ADD A,7
DbgA1:
	ADD A,48	;'0'
	CALL DbgSerial
	POP AF
	PUSH AF
	AND 15
	CP 10
	JR C,DbgA2
	ADD A,7
DbgA2:
	ADD A,48	;'0'
	CALL DbgSerial
	POP AF
	RET

DbgHL:
	PUSH HL
	PUSH AF
	LD A,H
	CALL DbgA
	LD A,L
	CALL DbgA
	POP AF
	POP HL
	RET

DbgBC:
	PUSH BC
	PUSH AF
	LD A,B
	CALL DbgA
	LD A,C
	CALL DbgA
	POP AF
	POP BC
	RET

DbgDE:
	PUSH DE
	PUSH AF
	LD A,D
	CALL DbgA
	LD A,E
	CALL DbgA
	POP AF
	POP DE
	RET

; Print the NUL-terminated string that follows the CALL.
DbgMsg:
	EX (SP),HL
	PUSH AF
DbgMsgLoop:
	LD A,(HL)
	INC HL
	OR A
	JR Z,DbgMsgDone
	CALL DbgSerial
	JR DbgMsgLoop
DbgMsgDone:
	POP AF
	EX (SP),HL
	RET

; HL = NUL-terminated string. Returns with HL just past the NUL. Preserves BC, DE.
DbgStr:
	PUSH AF
DbgStrLoop:
	LD A,(HL)
	INC HL
	OR A
	JR Z,DbgStrDone
	CALL DbgSerial
	JR DbgStrLoop
DbgStrDone:
	POP AF
	RET

SerialPortName:
	DB "#SER0", 0
SerialPort:
	DB 0
SerialMsg:
	DB 0
