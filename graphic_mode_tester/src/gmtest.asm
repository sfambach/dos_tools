; GMTEST - Graphic Mode Tester for IBM PC/XT/AT (MDA, CGA, EGA)
; Cycles through every video mode the installed adapter supports and shows
; a static test image: white border, mode, resolution, scan frequencies,
; colour bars. Any key = next mode, ESC = quit.
;
; Build: nasm -f bin -o GMTEST.COM gmtest.asm
; Runs on an 8088, so only 8086 instructions are used.

        cpu     8086
        org     100h

%define VERSION '0.2.0'

T_TEXT  equ     0
T_CGA   equ     1               ; interleaved CGA graphics (modes 4-6)
T_EGA   equ     2               ; planar EGA graphics (modes 0Dh-10h)

; mode descriptor layout
D_MODE  equ     0               ; byte  BIOS mode number
D_TYPE  equ     1               ; byte  T_TEXT / T_CGA / T_EGA
D_SEG   equ     2               ; word  video segment
D_COLS  equ     4               ; byte  text columns or bytes per pixel row
D_WHITE equ     5               ; byte  colour for border and text
D_ROWS  equ     6               ; word  pixel rows (graphics only)
D_EDGEL equ     8               ; byte  left border bit pattern (graphics)
D_EDGER equ     9               ; byte  right border bit pattern (graphics)
D_BARN  equ     10              ; byte  number of colour bars
D_BARS  equ     11              ; word  bar table
D_TEXT  equ     13              ; word  three zero-terminated info lines

%macro MODEDESC 11
        db      %1, %2
        dw      %3
        db      %4, %5
        dw      %6
        db      %7, %8, %9
        dw      %10, %11
%endmacro

SEQ_INDEX equ   3C4h
SEQ_MAPMASK equ 2

start:
        mov     ah, 0Fh
        int     10h
        mov     [oldmode], al

        call    detect                  ; -> si = mode list, [cardname]

next_mode:
        lodsw
        or      ax, ax
        jnz     .have
        mov     si, [listhead]
        jmp     next_mode
.have:
        push    si
        mov     bp, ax
        call    show_mode
        pop     si
        xor     ah, ah
        int     16h
        cmp     al, 1Bh
        jne     next_mode

        xor     ah, ah
        mov     al, [oldmode]
        int     10h
        mov     ax, 4C00h
        int     21h

; --------------------------------------------------------------------------
; detect - pick the mode list for the installed adapter
; out: si = list, [listhead] = list, [cardname] = adapter name
detect:
        mov     ax, 1A00h               ; VGA: read display combination
        int     10h
        cmp     al, 1Ah
        jne     .no_vga
        cmp     bl, 08h                 ; VGA with analog colour monitor
        jne     .no_vga
        mov     si, list_vga
        mov     word [cardname], s_vga
        jmp     .done
.no_vga:
        mov     ah, 12h                 ; EGA: get configuration
        mov     bl, 10h
        int     10h
        cmp     bl, 10h
        je      .no_ega
        or      bh, bh
        jnz     .ega_mono
        and     cl, 0Fh                 ; switch settings: 3/9 = enhanced monitor
        cmp     cl, 3
        je      .ega_ecd
        cmp     cl, 9
        je      .ega_ecd
        mov     si, list_ega_cga
        mov     word [cardname], s_ega_cga
        jmp     .done
.ega_ecd:
        mov     si, list_ega_ecd
        mov     word [cardname], s_ega_ecd
        jmp     .done
.ega_mono:
        mov     si, list_ega_mono
        mov     word [cardname], s_ega_mono
        jmp     .done
.no_ega:
        int     11h                     ; equipment word, bits 5-4 = 11b: mono
        and     al, 30h
        cmp     al, 30h
        jne     .cga
        mov     si, list_mda
        mov     word [cardname], s_mda
        jmp     .done
.cga:
        mov     si, list_cga
        mov     word [cardname], s_cga
.done:
        mov     [listhead], si
        ret

; --------------------------------------------------------------------------
; show_mode - set mode bp points to and draw the test image
show_mode:
        xor     ah, ah
        mov     al, [bp+D_MODE]
        int     10h
        mov     ah, 01h                 ; hide cursor
        mov     cx, 2000h
        int     10h

        mov     es, [bp+D_SEG]
        cld
        cmp     byte [bp+D_TYPE], T_TEXT
        jne     .gfx
        call    draw_text
        jmp     .labels
.gfx:
        call    draw_gfx
.labels:
        mov     bl, [bp+D_WHITE]
        mov     dx, 0303h
        mov     si, s_title
        call    print
        mov     si, [bp+D_TEXT]
        mov     dh, 5
        call    print
        inc     dh
        call    print
        inc     dh
        call    print
        mov     dh, 9
        mov     si, s_card
        call    print
        mov     si, [cardname]
        call    print_here
        push    es
        mov     ax, 40h
        mov     es, ax
        mov     dh, [es:84h]            ; last text row, EGA/VGA BIOS only
        pop     es
        cmp     dh, 24                  ; CGA/MDA BIOS leave it unset
        jae     .rows
        mov     dh, 24
.rows:
        sub     dh, 2
        mov     dl, 3
        mov     si, s_keys
        call    print
        ret

; --------------------------------------------------------------------------
; draw_text - double-line frame and colour bars straight into text memory
draw_text:
        mov     cl, [bp+D_COLS]
        xor     ch, ch
        mov     dx, cx
        shl     dx, 1                   ; dx = bytes per text row

        xor     di, di
        mov     ax, 0FC9h
        mov     bx, 0FCDh
        mov     si, 0FBBh
        call    text_hline
        mov     cx, 23
.side:
        push    cx
        mov     ax, 0FBAh
        stosw
        mov     cl, [bp+D_COLS]
        xor     ch, ch
        sub     cx, 2
        add     di, cx
        add     di, cx
        stosw
        pop     cx
        loop    .side
        mov     ax, 0FC8h
        mov     bx, 0FCDh
        mov     si, 0FBCh
        call    text_hline

        call    bar_geometry            ; ah = bar width, al = first column
        mov     dh, 15                  ; bars on text rows 15-20
.row:
        mov     al, dh
        mul     byte [bp+D_COLS]
        shl     ax, 1
        mov     di, ax
        mov     al, [first]
        xor     ah, ah
        shl     ax, 1
        add     di, ax
        mov     si, [bp+D_BARS]
        mov     cl, [bp+D_BARN]
        xor     ch, ch
.bar:
        push    cx
        lodsw                           ; al = char, ah = attribute
        mov     cl, [width]
        rep     stosw
        pop     cx
        loop    .bar
        inc     dh
        cmp     dh, 21
        jb      .row
        ret

; text_hline - ax = left corner, bx = line, si = right corner, di = start
text_hline:
        stosw
        mov     cl, [bp+D_COLS]
        xor     ch, ch
        sub     cx, 2
        mov     ax, bx
        rep     stosw
        mov     ax, si
        stosw
        ret

; bar_geometry - centre D_BARN bars in D_COLS-4 cells/bytes
; out: [width], [first]
bar_geometry:
        mov     al, [bp+D_COLS]
        xor     ah, ah
        sub     ax, 4
        div     byte [bp+D_BARN]
        mov     [width], al
        mul     byte [bp+D_BARN]
        mov     cl, [bp+D_COLS]
        xor     ch, ch
        sub     cx, ax
        shr     cx, 1
        mov     [first], cl
        ret

; --------------------------------------------------------------------------
; draw_gfx - 1-pixel white frame and colour bars, CGA or EGA memory layout
draw_gfx:
        mov     al, [bp+D_WHITE]
        call    set_planes

        xor     dx, dx                  ; top line
        call    row_addr
        mov     al, 0FFh
        call    fill_row
        mov     dx, [bp+D_ROWS]         ; bottom line
        dec     dx
        call    row_addr
        mov     al, 0FFh
        call    fill_row

        mov     dx, 1                   ; left and right edge
.edge:
        call    row_addr
        mov     al, [bp+D_EDGEL]
        mov     [es:di], al
        mov     bl, [bp+D_COLS]
        xor     bh, bh
        mov     al, [bp+D_EDGER]
        mov     [es:di+bx-1], al
        inc     dx
        mov     ax, [bp+D_ROWS]
        dec     ax
        cmp     dx, ax
        jb      .edge

        call    bar_geometry
        mov     ax, [bp+D_ROWS]         ; bars from 60 % to 85 % of the height
        mov     cx, 3
        mul     cx
        mov     cx, 5
        div     cx
        mov     [bar_top], ax
        mov     ax, [bp+D_ROWS]
        mov     cx, 17
        mul     cx
        mov     cx, 20
        div     cx
        mov     [bar_end], ax

        mov     si, [bp+D_BARS]
        mov     cl, [bp+D_BARN]
        xor     ch, ch
        mov     bl, [first]
        xor     bh, bh
.bar:
        push    cx
        lodsb
        mov     ah, al                  ; CGA: table holds the pixel pattern
        cmp     byte [bp+D_TYPE], T_EGA
        jne     .rows
        call    set_planes              ; EGA: colour selects planes, data all set
        mov     ah, 0FFh
.rows:
        mov     dx, [bar_top]
.row:
        push    ax
        call    row_addr
        add     di, bx
        mov     al, ah
        mov     cl, [width]
        xor     ch, ch
        rep     stosb
        pop     ax
        inc     dx
        cmp     dx, [bar_end]
        jb      .row
        add     bl, [width]
        pop     cx
        loop    .bar

        mov     al, 0Fh
        jmp     set_planes

; set_planes - EGA sequencer map mask = al (no-op on CGA)
set_planes:
        cmp     byte [bp+D_TYPE], T_EGA
        jne     .ret
        push    dx
        mov     ah, al
        mov     al, SEQ_MAPMASK
        mov     dx, SEQ_INDEX
        out     dx, ax
        pop     dx
.ret:
        ret

; row_addr - dx = pixel row -> di = offset of its first byte
row_addr:
        push    ax
        push    dx
        cmp     byte [bp+D_TYPE], T_CGA
        jne     .linear
        mov     di, dx                  ; CGA: odd rows live at 2000h
        and     di, 1
        mov     cl, 13
        shl     di, cl
        shr     dx, 1
        mov     al, [bp+D_COLS]
        xor     ah, ah
        mul     dx
        add     di, ax
        jmp     .done
.linear:
        mov     al, [bp+D_COLS]
        xor     ah, ah
        mul     dx
        mov     di, ax
.done:
        pop     dx
        pop     ax
        ret

; fill_row - fill one pixel row at di with al
fill_row:
        mov     cl, [bp+D_COLS]
        xor     ch, ch
        rep     stosb
        ret

; --------------------------------------------------------------------------
; print - zero-terminated string si at row dh, column dl, colour bl
; out: si behind the terminator
print:
        mov     ah, 02h
        xor     bh, bh
        int     10h
print_here:
.next:
        lodsb
        or      al, al
        jz      .end
        mov     ah, 0Eh
        xor     bh, bh
        int     10h
        jmp     .next
.end:
        ret

; --------------------------------------------------------------------------
; mode descriptors
;          mode type   seg    cols white rows edgeL edgeR barn bars       text
m00:    MODEDESC 00h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, t00
m01:    MODEDESC 01h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, t01
m02:    MODEDESC 02h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, t02
m03:    MODEDESC 03h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, t03
e00:    MODEDESC 00h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, te00
e01:    MODEDESC 01h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, te01
e02:    MODEDESC 02h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, te02
e03:    MODEDESC 03h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, te03
m04:    MODEDESC 04h, T_CGA, 0B800h, 80, 03h, 200, 0C0h, 03h, 4, bars_cga4, t04
m05:    MODEDESC 05h, T_CGA, 0B800h, 80, 03h, 200, 0C0h, 03h, 4, bars_cga4, t05
m06:    MODEDESC 06h, T_CGA, 0B800h, 80, 01h, 200, 80h, 01h, 4, bars_cga2, t06
m07:    MODEDESC 07h, T_TEXT, 0B000h, 80, 0Fh, 0, 0, 0, 5, bars_mono, t07
m0D:    MODEDESC 0Dh, T_EGA, 0A000h, 40, 0Fh, 200, 80h, 01h, 16, bars_ega16, t0D
m0E:    MODEDESC 0Eh, T_EGA, 0A000h, 80, 0Fh, 200, 80h, 01h, 16, bars_ega16, t0E
m0F:    MODEDESC 0Fh, T_EGA, 0A000h, 80, 05h, 350, 80h, 01h, 4, bars_egamono, t0F
m10:    MODEDESC 10h, T_EGA, 0A000h, 80, 0Fh, 350, 80h, 01h, 16, bars_ega16, t10
; VGA runs every mode at 31.5 kHz, 200-line modes are double scanned
v00:    MODEDESC 00h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, tv00
v01:    MODEDESC 01h, T_TEXT, 0B800h, 40, 0Fh, 0, 0, 0, 16, bars_text, tv01
v02:    MODEDESC 02h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, tv02
v03:    MODEDESC 03h, T_TEXT, 0B800h, 80, 0Fh, 0, 0, 0, 16, bars_text, tv03
v04:    MODEDESC 04h, T_CGA, 0B800h, 80, 03h, 200, 0C0h, 03h, 4, bars_cga4, tv04
v05:    MODEDESC 05h, T_CGA, 0B800h, 80, 03h, 200, 0C0h, 03h, 4, bars_cga4, tv05
v06:    MODEDESC 06h, T_CGA, 0B800h, 80, 01h, 200, 80h, 01h, 4, bars_cga2, tv06
v0D:    MODEDESC 0Dh, T_EGA, 0A000h, 40, 0Fh, 200, 80h, 01h, 16, bars_ega16, tv0D
v0E:    MODEDESC 0Eh, T_EGA, 0A000h, 80, 0Fh, 200, 80h, 01h, 16, bars_ega16, tv0E
v10:    MODEDESC 10h, T_EGA, 0A000h, 80, 0Fh, 350, 80h, 01h, 16, bars_ega16, tv10
v12:    MODEDESC 12h, T_EGA, 0A000h, 80, 0Fh, 480, 80h, 01h, 16, bars_ega16, tv12

list_cga:       dw m00, m01, m02, m03, m04, m05, m06, 0
list_mda:       dw m07, 0
list_ega_cga:   dw m00, m01, m02, m03, m04, m05, m06, m0D, m0E, 0
list_ega_ecd:   dw e00, e01, e02, e03, m04, m05, m06, m0D, m0E, m10, 0
list_ega_mono:  dw m07, m0F, 0
list_vga:       dw v00, v01, v02, v03, v04, v05, v06, v0D, v0E, v10, v12, 0

; text bars: character, attribute
bars_text:
%assign c 0
%rep 16
        db      0DBh, c
%assign c c+1
%endrep
bars_mono:      db 0DBh, 07h, 0DBh, 0Fh, 0B1h, 07h, 'U', 01h, 'B', 87h
; CGA bars: pixel pattern byte
bars_cga4:      db 00h, 55h, 0AAh, 0FFh
bars_cga2:      db 00h, 88h, 0AAh, 0FFh
; EGA bars: colour number
bars_ega16:     db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
bars_egamono:   db 0, 1, 4, 5

%define F_CGA '15.7 kHz / 60 Hz'
%define F_MDA '18.4 kHz / 50 Hz'
%define F_ECD '21.8 kHz / 60 Hz'
%define F_V70 '31.5 kHz / 70 Hz'
%define F_V60 '31.5 kHz / 60 Hz'

t00:    db 'Mode 00h  Text 40x25', 0, '320x200  16 colours, b/w', 0, F_CGA, 0
t01:    db 'Mode 01h  Text 40x25', 0, '320x200  16 colours', 0, F_CGA, 0
t02:    db 'Mode 02h  Text 80x25', 0, '640x200  16 colours, b/w', 0, F_CGA, 0
t03:    db 'Mode 03h  Text 80x25', 0, '640x200  16 colours', 0, F_CGA, 0
te00:   db 'Mode 00h  Text 40x25', 0, '320x350  16 colours', 0, F_ECD, 0
te01:   db 'Mode 01h  Text 40x25', 0, '320x350  16 colours', 0, F_ECD, 0
te02:   db 'Mode 02h  Text 80x25', 0, '640x350  16 colours', 0, F_ECD, 0
te03:   db 'Mode 03h  Text 80x25', 0, '640x350  16 colours', 0, F_ECD, 0
t04:    db 'Mode 04h  Graphics', 0, '320x200  4 colours', 0, F_CGA, 0
t05:    db 'Mode 05h  Graphics', 0, '320x200  4 colours, b/w', 0, F_CGA, 0
t06:    db 'Mode 06h  Graphics', 0, '640x200  2 colours', 0, F_CGA, 0
t07:    db 'Mode 07h  Text 80x25', 0, '720x350  mono', 0, F_MDA, 0
t0D:    db 'Mode 0Dh  Graphics', 0, '320x200  16 colours', 0, F_CGA, 0
t0E:    db 'Mode 0Eh  Graphics', 0, '640x200  16 colours', 0, F_CGA, 0
t0F:    db 'Mode 0Fh  Graphics', 0, '640x350  mono', 0, F_MDA, 0
t10:    db 'Mode 10h  Graphics', 0, '640x350  16 colours', 0, F_ECD, 0
tv00:   db 'Mode 00h  Text 40x25', 0, '360x400  16 colours, b/w', 0, F_V70, 0
tv01:   db 'Mode 01h  Text 40x25', 0, '360x400  16 colours', 0, F_V70, 0
tv02:   db 'Mode 02h  Text 80x25', 0, '720x400  16 colours, b/w', 0, F_V70, 0
tv03:   db 'Mode 03h  Text 80x25', 0, '720x400  16 colours', 0, F_V70, 0
tv04:   db 'Mode 04h  Graphics', 0, '320x200  4 col., 400 lines', 0, F_V70, 0
tv05:   db 'Mode 05h  Graphics', 0, '320x200  4 col., 400 lines', 0, F_V70, 0
tv06:   db 'Mode 06h  Graphics', 0, '640x200  2 col., 400 lines', 0, F_V70, 0
tv0D:   db 'Mode 0Dh  Graphics', 0, '320x200  16 col., 400 lines', 0, F_V70, 0
tv0E:   db 'Mode 0Eh  Graphics', 0, '640x200  16 col., 400 lines', 0, F_V70, 0
tv10:   db 'Mode 10h  Graphics', 0, '640x350  16 colours', 0, F_V70, 0
tv12:   db 'Mode 12h  Graphics', 0, '640x480  16 colours', 0, F_V60, 0

s_title:        db 'GMTEST ', VERSION, 0
s_card:         db 'Card: ', 0
s_cga:          db 'CGA', 0
s_mda:          db 'MDA', 0
s_ega_cga:      db 'EGA, CGA monitor', 0
s_ega_ecd:      db 'EGA, EGA monitor', 0
s_ega_mono:     db 'EGA, mono monitor', 0
s_vga:          db 'VGA (all modes 31.5 kHz)', 0
s_keys:         db 'Key: next   ESC: quit', 0

oldmode:        db 0
width:          db 0
first:          db 0
cardname:       dw 0
listhead:       dw 0
bar_top:        dw 0
bar_end:        dw 0
