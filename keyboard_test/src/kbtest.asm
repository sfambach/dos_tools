; KBTEST - show raw keyboard scan codes and what the BIOS makes of them
; For each key: the bytes read from port 60h by INT 09h (make, break and
; E0/E1 prefixes as the keyboard or an AT-to-XT converter sends them), then
; the scan code / ASCII pair INT 16h returns. Also shows whether the BIOS
; reports an enhanced 101/102-key keyboard (BIOS data area 40:96h bit 4).
;
; Usage: KBTEST        ESC three times in a row quits
;
; Build: nasm -f bin -o KBTEST.COM kbtest.asm

        cpu     8086
        org     100h

%define VERSION '0.1.0'

start:
        mov     dx, s_banner
        call    puts
        push    ds
        mov     ax, 40h
        mov     ds, ax
        mov     bl, [96h]
        pop     ds
        mov     dx, s_basic
        test    bl, 10h
        jz      .kind
        mov     dx, s_enhanced
.kind:
        call    puts
        mov     dx, s_help
        call    puts

        mov     ax, 3509h               ; hook INT 09h
        int     21h
        mov     [old9], bx
        mov     [old9 + 2], es
        mov     dx, int9
        mov     ax, 2509h
        int     21h

main:
        call    show_raw
        mov     ah, 01h                 ; key in the BIOS buffer?
        int     16h
        jz      main
        call    show_raw                ; raw bytes first, then the result
        xor     ah, ah
        int     16h
        mov     [key], ax
        mov     dx, s_bios
        call    puts
        mov     al, [key + 1]           ; scan code
        call    puthex
        mov     dl, '/'
        call    putc
        mov     al, [key]               ; ASCII
        call    puthex
        cmp     byte [key], 20h
        jb      .no_char
        mov     dl, ' '
        call    putc
        mov     dl, 27h
        call    putc
        mov     dl, [key]
        call    putc
        mov     dl, 27h
        call    putc
.no_char:
        mov     dx, s_crlf
        call    puts
        cmp     word [key], 011Bh               ; ESC
        jne     .not_esc
        inc     byte [esc_count]
        cmp     byte [esc_count], 3
        jb      main
        jmp     quit
.not_esc:
        mov     byte [esc_count], 0
        jmp     main

quit:
        push    ds
        lds     dx, [old9]
        mov     ax, 2509h
        int     21h
        pop     ds
        mov     ax, 4C00h
        int     21h

; show_raw - print the bytes INT 09h has collected since the last call
show_raw:
        mov     si, [tail]
        cmp     si, [head]
        je      .done
        mov     dx, s_raw
        call    puts
.next:
        mov     si, [tail]
        cmp     si, [head]
        je      .end
        mov     al, [raw + si]
        inc     si
        and     si, 63
        mov     [tail], si
        call    puthex
        mov     dl, ' '
        call    putc
        jmp     .next
.end:
        mov     dx, s_crlf
        call    puts
.done:
        ret

; int9 - copy the scan code byte, then let the BIOS handle it
int9:
        push    ax
        push    si
        in      al, 60h
        mov     si, [cs:head]
        mov     [cs:raw + si], al
        inc     si
        and     si, 63
        mov     [cs:head], si
        pop     si
        pop     ax
        jmp     far [cs:old9]

; puthex - al as two hex digits
puthex:
        push    ax
        mov     cl, 4
        shr     al, cl
        call    .digit
        pop     ax
        and     al, 0Fh
.digit:
        add     al, '0'
        cmp     al, '9'
        jbe     .out
        add     al, 7
.out:
        mov     dl, al
putc:
        mov     ah, 02h
        int     21h
        ret

puts:
        mov     ah, 09h
        int     21h
        ret

s_banner:   db 'KBTEST ', VERSION, ' - raw keyboard codes', 13, 10, '$'
s_basic:    db 'BIOS: 83/84-key keyboard (40:96h bit 4 = 0)', 13, 10, '$'
s_enhanced: db 'BIOS: enhanced 101/102-key keyboard (40:96h bit 4 = 1)', 13, 10, '$'
s_help:     db 'Press keys. ESC three times quits.', 13, 10, '$'
s_raw:      db 'Port 60h: $'
s_bios:     db '  INT 16h: $'
s_crlf:     db 13, 10, '$'

old9:       dd 0
head:       dw 0
tail:       dw 0
esc_count:  db 0
key:        dw 0
raw:        times 64 db 0
