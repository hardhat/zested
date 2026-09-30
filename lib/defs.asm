; zested - shared constants and editor RAM layout.
; Requires zos_sys.asm / zos_err.asm to be included first.

; ---- banks: 16KB physical RAM pages, one at a time mapped into virtual page 2 ----
DEFC BANK_WINDOW     = 0x8000
DEFC BANK_SIZE       = 0x4000
DEFC PAGES_PER_BANK  = 64
DEFC BANK_TABLE_SIZE = 64          ; bank ids are OS RAM page indexes and must be < 64

DEFC BANK_FREE       = 0
DEFC BANK_ORIGINAL   = 1
DEFC BANK_ADD        = 2
DEFC BANK_METADATA   = 3
DEFC BANK_TEMP       = 4
DEFC BANK_POOL       = 5           ; owned from the OS but unused, handed out again by bank_alloc

; ---- pieces ----
DEFC SRC_ORIGINAL    = 0
DEFC SRC_ADD         = 1

DEFC PIECE_SIZE      = 6
DEFC PIECE_CAP       = 512
DEFC P_SRC           = 0
DEFC P_BANK          = 1
DEFC P_PAGE          = 2
DEFC P_OFF           = 3
DEFC P_LEN           = 4           ; 16-bit, little endian

; ---- text iterator (caller-allocated, IT_SIZE bytes, addressed through IX) ----
DEFC IT_PIDX         = 0           ; dw piece index (== piece count at EOF)
DEFC IT_PPTR         = 2           ; dw address of the piece descriptor
DEFC IT_REM          = 4           ; dw bytes left in the current piece (0 only at EOF)
DEFC IT_BANK         = 6
DEFC IT_PAGE         = 7
DEFC IT_OFF          = 8
DEFC IT_SIZE         = 9

; ---- RAM layout: everything lives in virtual page 3 ----
DEFC PIECE_TABLE     = 0xC000
DEFC PIECE_TABLE_END = PIECE_TABLE + PIECE_CAP * PIECE_SIZE

; bank_init clears bank_type .. bank_state_end, doc_init clears vars_start .. vars_end
DEFVARS PIECE_TABLE_END
{
    bank_type       ds.b BANK_TABLE_SIZE
    bank_next       ds.b BANK_TABLE_SIZE
    bank_prev       ds.b BANK_TABLE_SIZE
    bank_current    ds.b 1
    bank_tmp        ds.b 1
    bank_state_end  ds.b 1
    vars_start      ds.b 0
    doc_piece_count ds.w 1
    doc_dirty       ds.b 1
    add_bank        ds.b 1
    add_page        ds.b 1
    add_off         ds.b 1
    aa_src          ds.w 1
    aa_len          ds.w 1
    aa_chunk        ds.w 1
    aa_sbank        ds.b 1
    aa_spage        ds.b 1
    aa_soff         ds.b 1
    pi_src          ds.w 1
    pi_idx          ds.w 1
    ps_idx          ds.w 1
    ps_off          ds.w 1
    ps_rest         ds.w 1
    ps_desc         ds.b PIECE_SIZE
    pm_idx          ds.w 1
    pm_sum          ds.w 1
    pd_desc         ds.b PIECE_SIZE
    di_idx          ds.w 1
    di_len          ds.w 1
    di_desc         ds.b PIECE_SIZE
    fio_fd          ds.b 1
    fio_prev        ds.b 1
    fio_cur         ds.b 1
    fio_filled      ds.w 1
    fio_iter        ds.b IT_SIZE
    vars_end        ds.b 1
}
