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

; ---- sparse line index: one entry (piece dw, offset dw) per 16 lines, entry k = start of line 16*k ----
DEFC LINE_INDEX_CAP  = 256
DEFC LINE_INDEX      = PIECE_TABLE_END
DEFC LINE_INDEX_END  = LINE_INDEX + LINE_INDEX_CAP * 4
DEFC SRCH_MAX        = 64

; bank_init clears bank_type .. bank_state_end, doc_init clears vars_start .. vars_end
DEFVARS LINE_INDEX_END
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
    doc_newlines    ds.w 1		; newline count == last line number (saturates at 65535)
    li_count        ds.w 1		; valid line index entries
    lf_line         ds.w 1
    lf_k            ds.w 1
    isl_avail       ds.w 1
    dd_len          ds.w 1
    dd_idx          ds.w 1
    dd_prev         ds.w 1
    dd_nl           ds.w 1
    dc_len          ds.w 1
    dc_count        ds.w 1
    dc_chunk        ds.w 1
    dc_iter         ds.b IT_SIZE
    di_pos_idx      ds.w 1
    di_pos_off      ds.w 1
    di_nl           ds.w 1
    tnt_tail        ds.w 1
    ei_src          ds.w 1
    ei_len          ds.w 1
    ei_k            ds.w 1
    ei_tail         ds.w 1
    ei_char         ds.b 1
    tmp_it          ds.b IT_SIZE
    cur_it          ds.b IT_SIZE	; cursor: iterator plus line/column, kept in step by the ed_/cur_ routines
    cur_line        ds.w 1
    cur_col         ds.w 1
    cur_want        ds.w 1		; column to return to when moving up/down
    view_top        ds.w 1
    view_left       ds.w 1
    sr_lines        ds.w 1		; newlines passed by the last search (forward: skipped, backward: crossed)
    sr_col          ds.w 1		; forward search: column of the match if sr_lines > 0, else columns advanced
    sr_avail        ds.w 1
    sr_addr         ds.w 1
    ra_count        ds.w 1
    find_it         ds.b IT_SIZE
    srch_it         ds.b IT_SIZE
    vars_end        ds.b 1
    view_rows       ds.b 1		; configuration: survives doc_init
    view_cols       ds.b 1
    srch_len        ds.b 1		; search pattern and replacement live in ordinary RAM and survive doc_init
    srch_pat        ds.b SRCH_MAX
    repl_len        ds.b 1
    repl_buf        ds.b SRCH_MAX
    vars_top        ds.b 0
}
