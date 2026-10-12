; CGA15 - put a VGA card into 80x25 text with CGA timing (15.7 kHz / 60 Hz)
; Uses only standard VGA registers: 25.175 MHz clock halved (12.59 MHz),
; 8-dot characters, 100 characters per line, 262 lines per frame,
; 200 visible, 8x8 font.
;
; Usage: CGA15        80x25 with 15.73 kHz / 60.0 Hz
;        CGA15 /R     back to normal VGA mode 3
; Diagnostic switches, combinable:
;        /N           no clock halving: 25.175 MHz, 200 characters per line,
;                     same 15.73 kHz but the picture uses only the left part
;        /P           sync polarity as VGA mode 3 (H negative, V positive)
;                     instead of CGA polarity (both positive)
;        /K           change the clock without sequencer reset
;
; Build: nasm -f bin -o CGA15.COM cga15.asm
; Untested on real hardware.

        cpu     8086
        org     100h

%define VERSION '0.2.0'

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
        cmp     al, 'N'
        jne     .not_n
        mov     byte [seq_clock], 01h   ; 8-dot characters, full dot clock
        mov     word [htable], crtc_full
        mov     word [s_variant], s_full
        jmp     .scan
.not_n:
        cmp     al, 'P'
        jne     .not_p
        mov     byte [misc], 63h        ; 25.175 MHz, H negative, V positive
        mov     word [s_sync], s_sync_bios
        jmp     .scan
.not_p:
        cmp     al, 'K'
        jne     .usage
        mov     byte [keep_seq], 1
        jmp     .scan
.usage:
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
        mov     dx, SEQ
        cmp     byte [keep_seq], 0
        jne     .clock
        mov     ax, 0100h               ; synchronous reset while the clock changes
        out     dx, ax
.clock:
        mov     dx, MISC_W
        mov     al, [misc]
        out     dx, al
        mov     dx, SEQ
        mov     al, 01h
        mov     ah, [seq_clock]
        out     dx, ax
        mov     ax, 0300h               ; sequencer running
        out     dx, ax
        sti

        mov     dx, CRTC
        mov     ax, 0011h               ; clear write protect of R0-R7
        out     dx, ax
        mov     si, [htable]
        mov     cx, htable_count
        call    load_pairs
        mov     si, crtc_vertical
        mov     cx, vertical_count
        call    load_pairs

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
        call    print
        mov     dx, [s_variant]
        call    print
        mov     dx, [s_sync]
        call    print
        mov     dx, s_restore_hint
quit_msg:
        call    print
        mov     ax, 4C00h
        int     21h

print:
        mov     ah, 09h
        int     21h
        ret

; load_pairs - write cx index/value pairs from si to the CRTC at dx
load_pairs:
        lodsw
        out     dx, ax
        loop    load_pairs
        ret

; CRTC index (low byte), value (high byte).
; Halved clock: one character = 16 periods of 25.175 MHz, 100 characters
; = 1600 periods = 15.73 kHz, 80 of them visible.
crtc_half:
        db      00h, 100 - 5            ; horizontal total 100
        db      01h, 79                 ; display end, 80 characters
        db      02h, 80                 ; start horizontal blanking
        db      03h, 80h | (98 & 1Fh)   ; end horizontal blanking 98
        db      04h, 85                 ; start horizontal retrace
        db      05h, 80h | (94 & 1Fh)   ; end retrace 94 (5.7 us), blanking bit 5
        db      13h, 40                 ; offset, 80 characters per row
htable_count equ ($ - crtc_half) / 2

; Full clock: one character = 8 periods, 200 characters = the same 15.73 kHz.
crtc_full:
        db      00h, 200 - 5            ; horizontal total 200
        db      01h, 79                 ; display end, 80 characters
        db      02h, 80                 ; start horizontal blanking
        db      03h, 80h | (198 & 1Fh)  ; end horizontal blanking 198
        db      04h, 170                ; start horizontal retrace
        db      05h, 188 & 1Fh          ; end retrace 188 (5.7 us), blanking bit 5 = 0
        db      13h, 40                 ; offset, 80 characters per row

crtc_vertical:
        db      06h, (262 - 2) & 0FFh   ; vertical total 262 lines
        db      07h, 11h                ; overflow: VT bit 8, line compare bit 8
        db      08h, 00h                ; preset row scan
        db      09h, 47h                ; 8 scan lines per character row
        db      0Ah, 06h                ; cursor start
        db      0Bh, 07h                ; cursor end
        db      10h, 224                ; vertical retrace start (CGA row 28)
        db      12h, 199                ; vertical display end, 200 lines
        db      15h, 200                ; start vertical blanking
        db      16h, 261 & 0FFh         ; end vertical blanking
        db      11h, 03h                ; retrace end 227, keeps R0-R7 writable
vertical_count equ ($ - crtc_vertical) / 2

misc:       db 23h                      ; 25.175 MHz, colour I/O, positive syncs
seq_clock:  db 09h                      ; 8-dot characters, dot clock / 2
keep_seq:   db 0
htable:     dw crtc_half
s_variant:  dw s_half
s_sync:     dw s_sync_cga

s_done:     db 'CGA15 ', VERSION, ': 80x25, 15.73 kHz / 60.0 Hz', 13, 10, '$'
s_half:     db 'Clock 25.175 MHz / 2, 100 characters per line', 13, 10, '$'
s_full:     db 'Clock 25.175 MHz, 200 characters per line (/N)', 13, 10, '$'
s_sync_cga: db 'Sync H+ V+', 13, 10, '$'
s_sync_bios: db 'Sync H- V+ (/P)', 13, 10, '$'
s_restore_hint: db 'CGA15 /R restores VGA.', 13, 10, '$'
s_restored: db 'VGA mode 3 restored.', 13, 10, '$'
s_usage:    db 'Usage: CGA15 [/N] [/P] [/K] | CGA15 /R', 13, 10, '$'
