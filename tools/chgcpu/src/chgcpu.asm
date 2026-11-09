; ============================================================================
;  CHGCPU.COM  -  CPU switch for MSX turbo R (Z80 / R800) under MSX-DOS
;
;  Usage:
;     CHGCPU          -> show current CPU
;     CHGCPU Z80      -> switch to the Z80
;     CHGCPU R800     -> switch to the R800 (DRAM mode, the normal one)
;     CHGCPU ROM      -> switch to the R800 in ROM mode
;     CHGCPU /?       -> help
;
;  Uses the turbo R BIOS routines CHGCPU (0180h) and GETCPU (0183h) through
;  CALSLT, never the S1990 ports directly.  Exit code (DOS2/Nextor _TERM):
;  0 = OK, 1 = error (not a turbo R / bad argument).
; ============================================================================

BDOS    equ     0005h
STROUT  equ     09h             ; BDOS: print '$'-terminated string (DE)
TERM    equ     62h             ; DOS2: terminate with error code (B)
TAILLEN equ     0080h           ; command-tail length byte
TAIL    equ     0081h           ; command-tail string

RDSLT   equ     000Ch           ; DOS keeps a copy of these in page 0 RAM
CALSLT  equ     001Ch
EXPTBL  equ     0FCC1h          ; slot of the main BIOS (bit 7 = expanded)
MSXID   equ     002Dh           ; 3 = turbo R
CHGCPU  equ     0180h
GETCPU  equ     0183h

        org     0100h

start:
        ; ---- is this a turbo R? ----
        ld      a, (EXPTBL)
        ld      hl, MSXID
        call    RDSLT
        ei
        cp      3
        ld      de, m_notr
        jp      nz, fail

        ; ---- parse the argument ----
        call    upcase_tail
        ld      hl, TAIL
sk_sp:  ld      a, (hl)
        cp      ' '
        jr      nz, sk_end
        inc     hl
        jr      sk_sp
sk_end: or      a
        jr      z, do_status    ; no argument -> show CPU
        ld      de, s_z80
        call    match
        ld      b, 80h          ; bit 7: update the LED
        jr      c, do_set
        ld      de, s_r800
        call    match
        ld      b, 82h
        jr      c, do_set
        ld      de, s_rom
        call    match
        ld      b, 81h
        jr      c, do_set
        ld      de, s_help
        call    match
        ld      de, m_help
        jr      c, show_help
        ld      de, m_bad
        jp      fail

do_set:
        ld      a, b
        ld      ix, CHGCPU
        call    bios
do_status:
        ld      de, m_cpu
        call    puts
        ld      ix, GETCPU
        call    bios
        and     3
        ld      de, c_z80
        jr      z, pr_cpu
        dec     a
        ld      de, c_rom
        jr      z, pr_cpu
        dec     a
        ld      de, c_dram
        jr      z, pr_cpu
        ld      de, c_unk
pr_cpu: call    puts
        xor     a
        jr      exit
show_help:
        call    puts
        xor     a
        jr      exit
fail:
        call    puts
        ld      a, 1
exit:
        ld      b, a
        ld      c, TERM
        call    BDOS            ; DOS2/Nextor: ends here
        ld      a, b            ; DOS1: function unknown, plain RET
        ret

; call a BIOS routine (IX) in the main BIOS slot
bios:
        ld      iy, (EXPTBL-1)  ; IYh = main BIOS slot
        call    CALSLT
        ei
        ret

; print '$'-terminated string at DE
puts:
        ld      c, STROUT
        push    ix
        push    iy
        call    BDOS
        pop     iy
        pop     ix
        ret

; uppercase the command tail in place, 0-terminate it
upcase_tail:
        ld      a, (TAILLEN)
        or      a
        jr      nz, uc_go
        ld      (TAIL), a       ; empty tail -> ensure it is 0-terminated
        ret
uc_go:
        ld      b, a
        ld      hl, TAIL
uc_lp:
        ld      a, (hl)
        cp      'a'
        jr      c, uc_nx
        cp      'z'+1
        jr      nc, uc_nx
        sub     20h
        ld      (hl), a
uc_nx:
        inc     hl
        djnz    uc_lp
        ld      (hl), 0
        ret

; match : HL = token, DE = 0-terminated word.  CF=1 if the token is exactly
; that word (followed by a space or the end).  HL kept.
match:
        push    hl
mt_lp:
        ld      a, (de)
        or      a
        jr      z, mt_end
        cp      (hl)
        jr      nz, mt_no
        inc     hl
        inc     de
        jr      mt_lp
mt_end:
        ld      a, (hl)
        or      a
        jr      z, mt_yes
        cp      ' '
        jr      nz, mt_no
mt_yes:
        pop     hl
        scf
        ret
mt_no:
        pop     hl
        or      a
        ret

s_z80:  db      "Z80", 0
s_r800: db      "R800", 0
s_rom:  db      "ROM", 0
s_help: db      "/?", 0

m_cpu:  db      "CPU: $"
c_z80:  db      "Z80", 13, 10, "$"
c_rom:  db      "R800 ROM", 13, 10, "$"
c_dram: db      "R800 DRAM", 13, 10, "$"
c_unk:  db      "unknown", 13, 10, "$"
m_notr: db      "Not a turbo R.", 13, 10, "$"
m_bad:  db      "Bad argument. Try CHGCPU /?", 13, 10, "$"
m_help: db      "CHGCPU [Z80 | R800 | ROM]", 13, 10
        db      "  no argument: show the CPU", 13, 10
        db      "  Z80   Z80 CPU", 13, 10
        db      "  R800  R800 CPU, DRAM mode", 13, 10
        db      "  ROM   R800 CPU, ROM mode", 13, 10, "$"
