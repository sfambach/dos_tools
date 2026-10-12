; ENHKB - mark the keyboard as enhanced (101/102 keys) in the BIOS data area
; Sets bit 4 of 40:96h so that keyboard drivers such as KEYB use their
; 102-key table (the <> key, scan code 56h) even when the BIOS or an
; AT-to-XT converter does not report an enhanced keyboard.
; Run it before KEYB in AUTOEXEC.BAT.
;
; Usage: ENHKB        set the flag
;        ENHKB /U     clear the flag again
;
; Build: nasm -f bin -o ENHKB.COM enhkb.asm

        cpu     8086
        org     100h

%define VERSION '0.1.0'

start:
        mov     ax, 40h
        mov     es, ax
        mov     si, 81h
.scan:
        lodsb
        cmp     al, 0Dh
        je      .set
        cmp     al, '/'
        jne     .scan
        lodsb
        and     al, 0DFh
        cmp     al, 'U'
        jne     .usage
        and     byte [es:96h], 0EFh
        mov     dx, s_cleared
        jmp     quit
.usage:
        mov     dx, s_usage
        jmp     quit
.set:
        or      byte [es:96h], 10h
        mov     dx, s_set
quit:
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

s_set:      db 'ENHKB ', VERSION, ': enhanced keyboard flag set (40:96h bit 4)', 13, 10, '$'
s_cleared:  db 'ENHKB ', VERSION, ': enhanced keyboard flag cleared', 13, 10, '$'
s_usage:    db 'Usage: ENHKB [/U]', 13, 10, '$'
