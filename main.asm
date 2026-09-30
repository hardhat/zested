; zested - Z80 asm code for the main game loop
	include "zos_sys.asm"
	include "zos_err.asm"
	include "zos_keyboard.asm"
	include "zos_video.asm"
	include "defs.asm"

	org 0x4000
    DEFC VID_IO_CTRL_STAT      = 0x90
    DEFC IO_CTRL_STATUS_REG    = VID_IO_CTRL_STAT + 0xd

Start:
	CALL DbgSerialOpen

	CALL DbgMsg
	db "Starting zested.asm", 13, 10, 0
	CALL bank_init
	CALL ed_init

	; Early exit for debugging purposes
	;LD A,0
	;LD L,5
	;OUT (0x10),A
	;Exits zeal-native and displays "[SEMIHOST] EXIT(5)" to the wsl console.

InitKeyboard:
	; Initialize the keyboard here if necessary.  For now, we just read from it each frame in the main loop.
	; Initialize the keyboard by setting it to raw and non-blocking
    ;void* arg = (void*) (KB_READ_NON_BLOCK | KB_MODE_RAW);
	LD DE,KB_READ_NON_BLOCK | KB_MODE_RAW
	LD H,DEV_STDIN
	LD C,KB_CMD_SET_MODE
    ;ioctl(DEV_STDIN, KB_CMD_SET_MODE, arg);
	IOCTL
MainLoop:
	CALL ReadKeyboard
	; Main game loop goes here
	JR MainLoop

QuitGame:
	LD DE,ThanksForPlayingMessage
	LD BC,ThanksForPlayingMessageLen
	S_WRITE1 DEV_STDOUT

	CALL doc_close

	LD A,(SerialPort)
	LD H,A
	CLOSE

	LD H,0
	EXIT

ThanksForPlayingMessage:
	DB "Thanks for playing!", 13, 10
ThanksForPlayingMessageLen EQU $-ThanksForPlayingMessage

    ; Wait for the FPGA to be initialized, read the status register and wait for VBlank
wait_for_vblank:
    in a, (IO_CTRL_STATUS_REG)
    and 2
    jr z, wait_for_vblank
    ret

wait_end_vblank:
    in a, (IO_CTRL_STATUS_REG)
    and 2
    jr nz, wait_end_vblank
    ret


PrintDecAt:	; Print a 16-bit number in HL to the screen at the specified position in DE
	LD (Cursor),DE
	JR PrintDec
PrintDec16:
	LD BC,-10000
	CALL SubCount
	LD BC,-1000
	CALL SubCount

PrintDec:	; Print a 16-bit number in HL to the screen at the current cursor position
	LD BC,-100
	CALL SubCount
PrintDec99:	; Only 2 digit output
	LD BC,-10
	CALL SubCount
	LD BC,-1
	CALL SubCount
	RET
SubCount:
	XOR A
SubCountLoop:
	INC A
	ADD HL,BC
	JR C,SubCountLoop
	OR A	;Clear the carry flag.
	SBC HL,BC
	;Note: "0123456789:/" is the character set used, so '0' is tile 192.
PrintDigit:
	LD DE,(Cursor)
	ADD A,192-1
	LD (DE),A
	INC DE
	LD (Cursor),DE
	RET

ReadKeyboard:
	LD DE,keyboard_buffer
	LD BC,16
	S_READ1 DEV_STDIN

	OR A	; Check for err success=0
	JR NZ,ReadKeyboardError

	LD B,C	; Number of characters in B
	LD A,B
	OR A
	RET Z	; No keyboard input
ReadKeyboardLoop:
	LD HL,keyboard_buffer
	LD A,(HL)
	LD C,A
	CP KB_RELEASED
	JR Z,ReadRelease
	CP KB_ESC
	CALL Z,HandleEsc
	; Handle other keys here
	INC HL
	DJNZ ReadKeyboardLoop
	RET
ReadRelease:
	DEC B
	RET Z	; No more keys to read
	INC HL
	LD A,(HL)
	;CP KB_UP_ARROW
	;CALL Z,HandleUpRelease
	; Handle other key releases here
	INC HL
	DJNZ ReadKeyboardLoop

	RET

ReadKeyboardError:
	LD DE,keyboard_error_message
	LD BC,keyboard_error_message_len
	S_WRITE1 DEV_STDOUT

	RET

HandleEsc:
	; Handle escape key press by quitting the game.
	JP QuitGame

keyboard_buffer:
	DS 16

keyboard_error_message:
	DB "Keyboard read error",0
keyboard_error_message_len	EQU $-keyboard_error_message

EndOfLine:
	DB 13,10,0
	EndOfLineLen	EQU $-EndOfLine

Cursor:
	DB 0,0
CursorLen	EQU $-Cursor

	include "debug.asm"
	include "bank.asm"
	include "piece.asm"
	include "iter.asm"
	include "doc.asm"
	include "docedit.asm"
	include "line.asm"
	include "editor.asm"

; Code must stay below the bank window at 0x8000.
code_end:
	ASSERT(code_end <= 0x8000)
