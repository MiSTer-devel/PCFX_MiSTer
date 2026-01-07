;;; Trivial memory test
;;;
;;; Copyright (c) 2025 David Hunter
;;;
;;; This program is GPL licensed. See COPYING for the full license.


;;; This program tests the entire 2MB RAM by writing and verifying a
;;; decreasing value.  32-bit accesses are used.  On test failure, the
;;; program halts.  On test success, it begins again.
;;;
;;; This program replaces the usual ROM BIOS.
;;;

; upper half of a 32 bit word:
hiword          function x,(x>>16)&65535
; the same for the lower half:
loword          function x,x&65535

;; Read/write size: 1=byte, 2=half, 4=word
rwsize  equ 4

    cpu 70732
    page 0

    org 0FFF00000h

entry:
    ;; Initialize and enable instruction cache (I$)
    mov #1, r1
    movhi #1, r1, r1
    ldsr r1, #24                ; Set CHCW.CEN=0, .CEC=256, .ICC=1
    mov #2, r1
    ldsr r1, #24                ; Set CHCW.ICE

    mov #-1, r16                ; r16 = initial test value
    mov r0, r8                  ; r8 = RAM start
    movhi #20h, r0, r9          ; r9 = RAM end + 1

    ;; r10 = data mask (because ld.b/h do sign extension)
    if rwsize == 1
        ori #000ffh, r0, r10
    elseif rwsize == 2
        ori #0ffffh, r0, r10
    endif

    ;; Write RAAM
    mov r16, r1                 ; r1 = current test value
    mov r8, r2                  ; r2 = current address

write_loop:
    if rwsize == 1
        st.b r1, 0[r2]
    elseif rwsize == 2
        st.h r1, 0[r2]
    else
        st.w r1, 0[r2]
    endif
    addi #rwsize, r2, r2
    addi #-1, r1, r1
    cmp r2, r9
    bne write_loop

    ;; Read RAM and verify
    mov r16, r1                 ; r1 = current test value
    mov r8, r2                  ; r2 = current address

verify_loop:
    if rwsize == 1
        ld.b 0[r2], r3
        mov r1, r4
        and r10, r3
        and r10, r4
    elseif rwsize == 2
        ld.h 0[r2], r3
        mov r1, r4
        and r10, r3
        and r10, r4
    else
        ld.w 0[r2], r3
        mov r1, r4
    endif
    addi #rwsize, r2, r2
    cmp r3, r4
    bne verify_fail
    addi #-1, r1, r1
    cmp r2, r9
    bne verify_loop

    br entry

verify_fail:
    halt

;;; Interrupt / exception vectora table

    org 0FFFFFFF0h
    movea #loword(entry), r0, r31
    movhi #hiword(entry), r31, r31
    jmp r31
