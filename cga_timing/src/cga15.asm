; CGA15 - put a VGA card into 80x25 text with CGA timing (15.5 kHz / 59 Hz)
; Uses only standard VGA registers: 28.322 MHz clock halved (14.161 MHz),
; 8-dot characters, 114 characters per line (912 pixels as on the CGA),
; 262 lines per frame, 200 visible, 8x8 font. Sync polarity positive.
;
; Usage: CGA15        80x25 with 15.5 kHz
;        CGA15 /R     back to normal VGA mode 3
;
; Build: nasm -f bin -o CGA15.COM cga15.asm
; Untested on real hardware.

        cpu     8086
        org     100h

%define VERSION '0.1.0'

MISC_W  equ     3C2h
SEQ     equ     3C4h
CRTC    equ     3D4h
ATTR    equ     3C0h
STATUS  equ     3DAh

start:
        mov     si, 81h
.scan:
        lodsb
        cmp     al, 0Dh
        je      set15
        cmp     al, '/'
        jne     .scan
        lodsb
        and     al, 0DFh
        cmp     al, 'R'
        je      restore
        mov     dx, s_usage
        jmp     quit_msg

restore:
        mov     ax, 0003h
        int     10h
        mov     dx, s_restored
        jmp     quit_msg

set15:
        mov     ax, 0003h               ; VGA text mode, palette, attributes
        int     10h
        mov     ax, 1112h               ; 8x8 ROM font into plane 2
        xor     bl, bl
        int     10h

        cli
        mov     dx, SEQ                 ; synchronous reset while the clock changes
        mov     ax, 0100h
        out     dx, ax
        mov     dx, MISC_W
        mov     al, 27h                 ; 28.322 MHz, colour I/O, positive syncs
        out     dx, al
        mov     dx, SEQ
        mov     ax, 0901h               ; 8-dot characters, dot clock / 2
        out     dx, ax
        mov     ax, 0300h               ; end reset
        out     dx, ax
        sti

        mov     dx, CRTC
        mov     ax, 0011h               ; clear write protect of R0-R7
        out     dx, ax
        mov     si, crtc_common
        mov     cx, common_count
.common:
        lodsw
        out     dx, ax
        loop    .common
        mov     si, crtc_80
        mov     cx, mode_count
.crtc:
        lodsw
        out     dx, ax
        loop    .crtc

        mov     dx, STATUS              ; horizontal panning 0 for 8-dot chars
        in      al, dx
        mov     dx, ATTR
        mov     al, 33h                 ; index 13h, keep video on (bit 5)
        out     dx, al
        xor     al, al
        out     dx, al

        push    ds
        mov     ax, 40h
        mov     ds, ax
        mov     byte [84h], 24          ; rows - 1
        mov     word [85h], 8           ; character height
        mov     word [4Ch], 4096        ; page size
        pop     ds

        mov     ax, 0B800h              ; clear the screen
        mov     es, ax
        xor     di, di
        mov     ax, 0720h
        mov     cx, 2000
        cld
        rep     stosw
        mov     ah, 02h
        xor     bh, bh
        xor     dx, dx
        int     10h

        mov     dx, s_done
quit_msg:
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

; CRTC index (low byte), value (high byte). With the dot clock halved one
; character takes 16 periods of 28.322 MHz, so 114 characters = 1824 periods
; = 15.53 kHz, the same 114 characters as the CGA 6845 in 80 columns.
crtc_80:
        db      00h, 114 - 5            ; horizontal total 114
        db      01h, 79                 ; display end, 80 characters
        db      02h, 80                 ; start horizontal blanking
        db      03h, 80h | (112 & 1Fh)  ; end horizontal blanking 112
        db      04h, 90                 ; start horizontal retrace (CGA R2 = 5Ah)
        db      05h, 80h | (100 & 1Fh)  ; end retrace 100, blanking end bit 5
        db      13h, 40                 ; offset, 80 characters per row
mode_count equ ($ - crtc_80) / 2

crtc_common:
        db      06h, (262 - 2) & 0FFh   ; vertical total 262 lines
        db      07h, 11h                ; overflow: VT bit 8, line compare bit 8
        db      08h, 00h                ; preset row scan
        db      09h, 47h                ; 8 scan lines per character row
        db      0Ah, 06h                ; cursor start
        db      0Bh, 07h                ; cursor end
        db      10h, 224 & 0FFh         ; vertical retrace start (CGA row 28)
        db      12h, 199                ; vertical display end, 200 lines
        db      15h, 200                ; start vertical blanking
        db      16h, 261 & 0FFh         ; end vertical blanking
        db      11h, 03h                ; retrace end 227, keeps R0-R7 writable
common_count equ ($ - crtc_common) / 2

s_done:     db 'CGA15 ', VERSION, ': 80x25, 15.53 kHz / 59.3 Hz', 13, 10
            db 'CGA15 /R restores VGA.', 13, 10, '$'
s_restored: db 'VGA mode 3 restored.', 13, 10, '$'
s_usage:    db 'Usage: CGA15 [/R]', 13, 10, '$'
