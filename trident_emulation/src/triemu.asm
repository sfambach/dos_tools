; TRIEMU - switch the emulation mode of a Trident TVGA8800/8900 card
; Replacement for Trident's SVM.EXE. Writes bits 0-2 of the Old Mode
; Control 2 register (3C4h index 0Dh): 0 = VGA, 3 = EGA, 5 = CGA/MDA/Hercules.
; Register description: vgadoc TRIDENT.TXT.
;
; Usage: TRIEMU            show chip ID, emulation and switch settings
;        TRIEMU VGA        back to VGA (BIOS mode 3)
;        TRIEMU EGA        EGA emulation, 80x25 with EGA timing (21.8 kHz)
;        TRIEMU CGA        CGA emulation, 80x25 with CGA timing (15.5 kHz)
;        TRIEMU MDA        MDA emulation, 80x25 with MDA timing (18.4 kHz)
;        /F                skip the Trident check
;
; Build: nasm -f bin -o TRIEMU.COM triemu.asm
; Untested on real hardware.

        cpu     8086
        org     100h

%define VERSION '0.2.0'

SEQ     equ     3C4h
REG_ID  equ     0Bh                     ; chip version, also old/new mode select
REG_MC2 equ     0Dh                     ; old mode control 2: emulation bits 0-2
REG_MC1 equ     0Eh                     ; old mode control 1
REG_PUM equ     0Fh                     ; power-up mode 2: switch settings

EMU_VGA equ     0
EMU_EGA equ     3
EMU_CGA equ     5

BDA     equ     40h

start:
        mov     dx, s_banner
        call    puts
        call    parse_args
        call    detect
        jnc     .trident
        cmp     byte [force], 0
        jne     .trident
        mov     dx, s_no_trident
        call    puts
        mov     ax, 4C01h
        int     21h
.trident:
        mov     al, [target]
        cmp     al, 0FFh
        je      .status
        mov     bx, [action]
        call    bx
.status:
        call    show_status
        mov     ax, 4C00h
        int     21h

; --------------------------------------------------------------------------
; parse_args - first word of the command line selects the target,
; /F anywhere sets [force]. Unknown word: print usage and quit.
parse_args:
        mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch
        mov     di, word_buf
.next:
        jcxz    .end
        lodsb
        dec     cx
        cmp     al, 'a'
        jb      .upper
        cmp     al, 'z'
        ja      .upper
        sub     al, 20h
.upper:
        cmp     al, '/'
        jne     .not_switch
        jcxz    .end
        lodsb
        dec     cx
        and     al, 0DFh
        cmp     al, 'F'
        jne     .usage
        mov     byte [force], 1
        jmp     .next
.not_switch:
        cmp     al, ' '
        jbe     .next
        cmp     di, word_buf + 3
        jae     .usage
        stosb
        jmp     .next
.end:
        cmp     di, word_buf
        je      .done
        cmp     di, word_buf + 3
        jne     .usage
        mov     si, targets
.find:
        cmp     byte [si], 0
        je      .usage
        mov     ax, [si]
        cmp     ax, [word_buf]
        jne     .skip
        mov     al, [si+2]
        cmp     al, [word_buf+2]
        jne     .skip
        mov     al, [si+3]
        mov     [target], al
        mov     ax, [si+4]
        mov     [action], ax
.done:
        ret
.skip:
        add     si, 6
        jmp     .find
.usage:
        mov     dx, s_usage
        call    puts
        mov     ax, 4C02h
        int     21h

; --------------------------------------------------------------------------
; detect - read chip ID, CF set if no Trident (TRIDENT.TXT "ID Trident VGA")
detect:
        call    old_mode
        mov     dx, SEQ
        mov     al, REG_ID
        out     dx, al
        inc     dx
        in      al, dx                  ; reading selects new mode registers
        mov     [chip_id], al
        call    old_mode
        mov     al, [chip_id]
        or      al, al
        jz      .unknown
        cmp     al, 0FFh
        je      .unknown
        mov     si, chips
.find:
        cmp     byte [si], 0
        je      .unknown
        cmp     al, [si]
        je      .found
        add     si, 3
        jmp     .find
.found:
        mov     ax, [si+1]
        mov     [chip_name], ax
        clc
        ret
.unknown:
        mov     word [chip_name], s_unknown
        stc
        ret

; old_mode - select the old mode registers: write index 0Bh as two byte writes
old_mode:
        mov     dx, SEQ
        mov     al, REG_ID
        out     dx, al
        inc     dx
        xor     al, al
        out     dx, al
        ret

; read_seq - al = index -> al = value
read_seq:
        mov     dx, SEQ
        out     dx, al
        inc     dx
        in      al, dx
        ret

; set_emulation - al = emulation value, keeps bits 3-7
set_emulation:
        mov     ah, al
        call    old_mode
        mov     al, REG_MC2
        call    read_seq                ; dx = 3C5h
        and     al, 0F8h
        or      al, ah
        out     dx, al
        ret

; unlock_crtc - clear VGA CRTC write protect (index 11h bit 7) at base dx
unlock_crtc:
        mov     al, 11h
        out     dx, al
        inc     dx
        in      al, dx
        and     al, 7Fh
        out     dx, al
        dec     dx
        ret

; --------------------------------------------------------------------------
; targets

to_vga:
        call    set_equipment_color
        mov     dx, 3D4h
        call    unlock_crtc
        mov     al, EMU_VGA
        call    set_emulation
        mov     ax, 0003h
        int     10h
        ret

to_ega:
        call    set_equipment_color
        mov     ax, 0003h
        int     10h
        mov     ax, 1111h               ; 8x14 font
        xor     bl, bl
        int     10h
        mov     dx, 3D4h
        call    unlock_crtc
        mov     al, EMU_EGA
        call    set_emulation
        mov     si, timing_ega
        call    retime
        mov     ax, 0B800h
        mov     bx, 3D4h
        mov     cx, 0329h
        jmp     text_done

; CGA: VGA mode 3 with 8x8 font, emulation bits, then CGA timing
to_cga:
        call    set_equipment_color
        mov     ax, 0003h
        int     10h
        mov     ax, 1112h               ; 8x8 font
        xor     bl, bl
        int     10h
        mov     dx, 3D4h
        call    unlock_crtc
        mov     al, EMU_CGA
        call    set_emulation
        mov     si, timing_cga
        call    retime
        mov     ax, 0B800h
        mov     bx, 3D4h
        mov     cx, 0329h
        jmp     text_done

to_mda:
        call    set_equipment_mono
        mov     ax, 0007h
        int     10h
        mov     ax, 1111h               ; 8x14 font
        xor     bl, bl
        int     10h
        mov     dx, 3B4h
        call    unlock_crtc
        mov     al, EMU_CGA             ; 5 covers CGA, MDA and Hercules
        call    set_emulation
        mov     si, timing_mda
        call    retime
        mov     ax, 0B000h
        mov     bx, 3B4h
        mov     cx, 0729h
        jmp     text_done

; retime - program clock, character width and CRTC from a timing record
; in: si = timing record (see timing_cga)
; The 6845 values of the original cards mean nothing to the VGA CRTC and the
; emulation bits do not change the clock (measured 2026-10-12: 31 kHz stayed),
; so the timing is built from standard VGA registers instead.
retime:
        cli
        mov     dx, SEQ                 ; synchronous reset while the clock changes
        mov     ax, 0100h
        out     dx, ax
        mov     dx, 3C2h
        lodsb                           ; miscellaneous output
        out     dx, al
        mov     dx, SEQ
        mov     al, 01h
        mov     ah, [si]                ; clocking mode
        inc     si
        out     dx, ax
        mov     ax, 0300h
        out     dx, ax
        sti
        lodsw                           ; CRTC base
        mov     dx, ax
        lodsb
        mov     bl, al                  ; character height
        lodsb
        mov     cl, al                  ; number of CRTC pairs
        xor     ch, ch
        mov     ax, 0011h               ; clear write protect of R0-R7
        out     dx, ax
.crtc:
        lodsw
        out     dx, ax
        loop    .crtc
        push    dx
        add     dx, 6                   ; input status 1: reset attribute flip-flop
        in      al, dx
        mov     dx, 3C0h
        mov     al, 33h                 ; horizontal panning 0, video on
        out     dx, al
        xor     al, al
        out     dx, al
        pop     dx
        push    es
        mov     ax, BDA
        mov     es, ax
        mov     [es:85h], bl
        mov     byte [es:86h], 0
        pop     es
        ret

; text_done - clear screen at segment ax, update the BIOS data area
; bx = CRTC base, ch = BIOS mode, cl = mode register value
text_done:
        push    es
        mov     es, ax
        xor     di, di
        mov     ax, 0720h
        push    cx
        mov     cx, 2000
        cld
        rep     stosw
        pop     cx
        mov     ax, BDA
        mov     es, ax
        mov     [es:49h], ch            ; current mode
        mov     word [es:4Ah], 80       ; columns
        mov     word [es:4Ch], 4096     ; page size
        mov     word [es:4Eh], 0        ; page offset
        mov     word [es:50h], 0        ; cursor page 0
        mov     [es:63h], bx            ; CRTC base
        mov     [es:65h], cl            ; mode register
        mov     byte [es:84h], 24       ; rows - 1
        pop     es
        ret

set_equipment_color:
        push    es
        mov     ax, BDA
        mov     es, ax
        and     byte [es:10h], 0CFh
        or      byte [es:10h], 20h      ; 80x25 colour
        pop     es
        ret

set_equipment_mono:
        push    es
        mov     ax, BDA
        mov     es, ax
        or      byte [es:10h], 30h      ; 80x25 mono
        pop     es
        ret

; --------------------------------------------------------------------------
show_status:
        mov     dx, s_chip
        call    puts
        mov     al, [chip_id]
        call    puthex
        mov     dx, s_space
        call    puts
        mov     dx, [chip_name]
        call    puts

        call    old_mode
        mov     dx, s_emu
        call    puts
        mov     al, REG_MC2
        call    read_seq
        and     al, 7
        mov     bl, al
        call    puthex
        mov     dx, s_space
        call    puts
        mov     dx, s_emu_other
        cmp     bl, EMU_VGA
        jne     .not_vga
        mov     dx, s_emu_vga
.not_vga:
        cmp     bl, EMU_EGA
        jne     .not_ega
        mov     dx, s_emu_ega
.not_ega:
        cmp     bl, EMU_CGA
        jne     .not_cga
        mov     dx, s_emu_cga
.not_cga:
        call    puts

        mov     dx, s_switch
        call    puts
        mov     al, REG_PUM
        call    read_seq
        and     al, 0Fh
        mov     cx, 4
        mov     bl, al
.bit:
        mov     dl, '0'
        test    bl, 8
        jz      .zero
        inc     dl
.zero:
        mov     ah, 02h
        int     21h
        shl     bl, 1
        loop    .bit

        ; TELLSET.EXE (VC415) names the emulation from new mode index 0Fh
        mov     dx, s_type
        call    puts
        mov     al, REG_ID              ; reading index 0Bh selects new mode
        call    read_seq
        mov     al, REG_PUM
        call    read_seq
        mov     bl, al
        call    old_mode
        mov     al, bl
        call    puthex
        cmp     bl, 3
        ja      .done
        mov     dx, s_space
        call    puts
        xor     bh, bh
        shl     bx, 1
        mov     dx, [type_names + bx]
        call    puts
.done:
        mov     dx, s_crlf
        jmp     puts

; puthex - al as two hex digits plus 'h'
puthex:
        push    ax
        mov     cl, 4
        shr     al, cl
        call    .digit
        pop     ax
        and     al, 0Fh
        call    .digit
        mov     dl, 'h'
        mov     ah, 02h
        int     21h
        ret
.digit:
        add     al, '0'
        cmp     al, '9'
        jbe     .out
        add     al, 7
.out:
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret

puts:
        mov     ah, 09h
        int     21h
        ret

; --------------------------------------------------------------------------
; Timing records: misc output, clocking mode, CRTC base, character height,
; pair count, then CRTC index (low byte) / value (high byte) pairs.
; Overflow 1Fh carries bit 8 of every vertical value, 11h ends retrace and
; keeps R0-R7 writable.
; CGA: 28.322 MHz / 2, 114 characters, 262 lines -> 15.53 kHz / 59.3 Hz
timing_cga:
        db      27h, 09h
        dw      3D4h
        db      8, (timing_cga_end - $ - 2) / 2
        db      00h, 114 - 5, 01h, 79, 02h, 80, 03h, 80h | (112 & 1Fh)
        db      04h, 90, 05h, 80h | (100 & 1Fh), 13h, 40
        db      06h, (262 - 2) & 0FFh, 07h, 11h, 08h, 00h, 09h, 47h
        db      0Ah, 06h, 0Bh, 07h, 10h, 224, 12h, 199
        db      15h, 200, 16h, 261 & 0FFh, 11h, 03h
timing_cga_end:

; EGA 350 lines: 25.175 MHz, 144 characters, 364 lines -> 21.85 kHz / 60.0 Hz
timing_ega:
        db      0A3h, 01h
        dw      3D4h
        db      14, (timing_ega_end - $ - 2) / 2
        db      00h, 144 - 5, 01h, 79, 02h, 80, 03h, 80h | (140 & 1Fh)
        db      04h, 96, 05h, (110 & 1Fh), 13h, 40
        db      06h, (364 - 2) & 0FFh, 07h, 1Fh, 08h, 00h, 09h, 4Dh
        db      0Ah, 0Bh, 0Bh, 0Ch, 10h, 352 & 0FFh, 12h, 349 & 0FFh
        db      15h, 350 & 0FFh, 16h, (364 - 2) & 0FFh, 11h, 03h
timing_ega_end:

; MDA: 28.322 MHz / 2, 96 characters, 370 lines -> 18.44 kHz / 49.8 Hz
timing_mda:
        db      0A6h, 09h
        dw      3B4h
        db      14, (timing_mda_end - $ - 2) / 2
        db      00h, 96 - 5, 01h, 79, 02h, 80, 03h, 80h | (94 & 1Fh)
        db      04h, 83, 05h, (95 & 1Fh), 13h, 40
        db      06h, (370 - 2) & 0FFh, 07h, 1Fh, 08h, 00h, 09h, 4Dh
        db      0Ah, 0Bh, 0Bh, 0Ch, 10h, 352 & 0FFh, 12h, 349 & 0FFh
        db      15h, 350 & 0FFh, 16h, (370 - 2) & 0FFh, 11h, 0Eh
timing_mda_end:

; name (3 chars), emulation value, handler
targets:        db 'VGA', EMU_VGA
                dw to_vga
                db 'EGA', EMU_EGA
                dw to_ega
                db 'CGA', EMU_CGA
                dw to_cga
                db 'MDA', EMU_CGA
                dw to_mda
                db 'HGC', EMU_CGA
                dw to_mda
                db 0

; chip ID, name (3C4h index 0Bh)
chips:          db 01h
                dw s_8800br
                db 02h
                dw s_8800cs
                db 03h
                dw s_8900b
                db 04h
                dw s_8900c
                db 13h
                dw s_8900c
                db 23h
                dw s_9000
                db 33h
                dw s_8900cl
                db 43h
                dw s_9000i
                db 0

s_8800br:       db 'TVGA8800BR$'
s_8800cs:       db 'TVGA8800CS$'
s_8900b:        db 'TVGA8900B$'
s_8900c:        db 'TVGA8900C$'
s_9000:         db 'TVGA9000$'
s_8900cl:       db 'TVGA8900CL/D or 9000C$'
s_9000i:        db 'TVGA9000i$'
s_unknown:      db 'not a known Trident chip$'

s_banner:       db 'TRIEMU ', VERSION, ' - Trident emulation switch', 13, 10, '$'
s_usage:        db 'Usage: TRIEMU [VGA|EGA|CGA|MDA|HGC] [/F]', 13, 10
                db '  no argument  show status', 13, 10
                db '  /F           skip the Trident check', 13, 10, '$'
s_no_trident:   db 'No Trident chip found, use /F to force.', 13, 10, '$'
s_chip:         db 'Chip ID:    $'
s_emu:          db 13, 10, 'Emulation:  $'
s_emu_vga:      db 'VGA$'
s_emu_ega:      db 'EGA$'
s_emu_cga:      db 'CGA/MDA/Hercules$'
s_emu_other:    db 'undocumented$'
s_switch:       db 13, 10, 'Switches:   $'
s_space:        db ' $'
s_type:         db 13, 10, 'New 0Fh:    $'
s_type_vga:     db 'VGA$'
s_type_ega:     db 'EGA$'
s_type_cga:     db 'CGA$'
s_type_herc:    db 'HERC$'
type_names:     dw s_type_vga, s_type_ega, s_type_cga, s_type_herc
s_crlf:         db 13, 10, '$'

target:         db 0FFh
force:          db 0
action:         dw 0
chip_id:        db 0
chip_name:      dw 0
word_buf:       db 0, 0, 0
