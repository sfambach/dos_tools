; LFNDEL - list or remove VFAT long file name entries on a FAT12/FAT16 drive
; Target: 8088, DOS 3.x and later. Build: nasm -f bin -o LFNDEL.COM LFNDEL.ASM
;
; Usage: LFNDEL d:        list files that carry a long name
;        LFNDEL d: /D     list, ask, then mark all LFN slots as deleted
;
; Works on raw sectors via INT 25h/26h, so DOS never sees the LFN slots it
; does not understand. The 8.3 entries are left untouched.

        cpu     8086
        org     100h

SECSIZE equ     512
PATHLEN equ     80
QENTRY  equ     2+PATHLEN
QMAX    equ     400

start:
        cld
        mov     di,bss_start
        mov     cx,bss_end-bss_start
        xor     al,al
        rep     stosb
        mov     si,81h
        call    skipsp
        lodsb
        and     al,0DFh
        cmp     al,'A'
        jb      usage
        cmp     al,'Z'
        ja      usage
        mov     [rootpath],al
        sub     al,'A'
        mov     [drive],al
        lodsb
        cmp     al,':'
        jne     usage
.opt:   call    skipsp
        lodsb
        cmp     al,0Dh
        je      .go
        cmp     al,'/'
        jne     usage
        lodsb
        and     al,0DFh
        cmp     al,'D'
        jne     usage
        mov     byte [wantdel],1
        jmp     .opt

.go:    mov     ah,0Dh                  ; flush DOS buffers before raw access
        int     21h
        call    readboot
        mov     byte [delmode],0
        call    scan

        mov     dx,msg_names
        call    puts
        mov     ax,[cntnames]
        call    putdec
        mov     dx,msg_slots
        call    puts
        mov     ax,[cntslots]
        call    putdec
        call    crlf
        cmp     byte [qoverflow],0
        je      .noovf
        mov     dx,msg_qovf
        call    puts
.noovf:
        cmp     byte [wantdel],0
        je      .done
        cmp     word [cntslots],0
        je      .done

        mov     dx,msg_ask1
        call    puts
        mov     ax,[cntslots]
        call    putdec
        mov     dx,msg_ask2
        call    puts
        mov     dl,[rootpath]
        call    putc
        mov     dx,msg_ask3
        call    puts
        mov     ah,08h
        int     21h
        and     al,0DFh
        push    ax
        mov     dl,al
        call    putc
        call    crlf
        pop     ax
        cmp     al,'Y'
        je      .del
        cmp     al,'J'
        jne     .done
.del:   mov     ah,0Dh
        int     21h
        mov     byte [delmode],1
        call    scan
        mov     ah,0Dh
        int     21h
        mov     dx,msg_deleted
        call    puts
        mov     ax,[cntslots]
        call    putdec
        mov     dx,msg_reboot
        call    puts
.done:  mov     ax,4C00h
        int     21h

usage:  mov     dx,msg_usage
        call    puts
        mov     ax,4C02h
        int     21h

fail:   ; dx = message
        call    puts
        mov     ax,4C02h
        int     21h

skipsp: lodsb
        cmp     al,' '
        je      skipsp
        cmp     al,9
        je      skipsp
        dec     si
        ret

; ---------------------------------------------------------------- boot sector

readboot:
        xor     ax,ax
        xor     dx,dx
        mov     cx,1
        mov     bx,secbuf
        mov     byte [useold],0
        call    rawread
        jnc     .ok
        mov     byte [useold],1
        xor     ax,ax
        xor     dx,dx
        mov     cx,1
        mov     bx,secbuf
        call    rawread
        jnc     .ok
        mov     dx,msg_readerr
        jmp     fail
.ok:    mov     dx,msg_nofat
        cmp     word [secbuf+0Bh],SECSIZE
        jne     fail
        mov     al,[secbuf+0Dh]
        xor     ah,ah
        or      ax,ax
        jz      fail
        mov     [spc],ax
        mov     ax,[secbuf+16h]         ; 0 = FAT32
        or      ax,ax
        jz      fail
        mov     [spf],ax
        mov     ax,[secbuf+0Eh]
        mov     [fatstart],ax
        mov     al,[secbuf+10h]
        xor     ah,ah
        mul     word [spf]
        add     ax,[fatstart]
        mov     [rootstart],ax
        mov     ax,[secbuf+11h]
        add     ax,15                   ; 16 entries per sector
        mov     cl,4
        shr     ax,cl
        mov     [rootsecs],ax
        add     ax,[rootstart]
        mov     [datastart],ax
        mov     ax,[secbuf+13h]
        xor     dx,dx
        or      ax,ax
        jnz     .tot
        mov     ax,[secbuf+20h]
        mov     dx,[secbuf+22h]
.tot:   sub     ax,[datastart]
        sbb     dx,0
        mov     bx,dx                   ; quotient must fit 16 bits
        cmp     bx,[spc]
        jae     fail
        div     word [spc]
        inc     ax                      ; highest valid cluster number
        mov     [maxclus],ax
        cmp     ax,4085+1
        jae     .f16
        mov     byte [fat16],0
        ret
.f16:   mov     byte [fat16],1
        ret

; ---------------------------------------------------------------- traversal

scan:
        xor     ax,ax
        mov     [cntnames],ax
        mov     [cntslots],ax
        mov     [qhead],ax
        mov     [qtail],ax
        mov     [qcount],ax
        mov     [lfnpend],al
        mov     word [fatcached],0FFFFh
        mov     si,rootpath
        mov     di,curpath
        call    strcpy

        mov     ax,[rootstart]
        mov     [cursec],ax
        mov     word [cursec+2],0
        mov     cx,[rootsecs]
.root:  push    cx
        call    dosector
        pop     cx
        jc      .queue
        add     word [cursec],1
        adc     word [cursec+2],0
        loop    .root

.queue: cmp     word [qcount],0
        je      .end
        mov     ax,[qhead]
        mov     bx,QENTRY
        mul     bx
        add     ax,queue
        mov     si,ax
        lodsw
        mov     [curclus],ax
        mov     di,curpath
        call    strcpy
        mov     ax,[qhead]
        inc     ax
        cmp     ax,QMAX
        jb      .h
        xor     ax,ax
.h:     mov     [qhead],ax
        dec     word [qcount]
        mov     byte [lfnpend],0
        mov     word [chainguard],0

.clus:  mov     ax,[curclus]
        cmp     ax,2
        jb      .queue
        cmp     ax,[maxclus]
        ja      .queue
        sub     ax,2
        mul     word [spc]
        add     ax,[datastart]
        adc     dx,0
        mov     [cursec],ax
        mov     [cursec+2],dx
        mov     cx,[spc]
.sec:   push    cx
        call    dosector
        pop     cx
        jc      .queue
        add     word [cursec],1
        adc     word [cursec+2],0
        loop    .sec
        inc     word [chainguard]
        mov     ax,[chainguard]
        cmp     ax,[maxclus]
        ja      .queue
        mov     ax,[curclus]
        call    fatnext
        mov     [curclus],ax
        jmp     .clus
.end:   ret

; Process one directory sector at [cursec]. CF=1 when the end marker was hit.
dosector:
        mov     ax,[cursec]
        mov     dx,[cursec+2]
        mov     cx,1
        mov     bx,secbuf
        call    rawread
        jnc     .rd
        mov     dx,msg_readerr
        jmp     fail
.rd:    mov     byte [dirty],0
        mov     bx,secbuf
.ent:   mov     al,[bx]
        or      al,al
        jz      .eod
        cmp     al,0E5h
        je      .clrp
        mov     ah,[bx+0Bh]
        cmp     ah,0Fh
        je      .lfn
        test    ah,08h                  ; volume label
        jnz     .clrp
        cmp     byte [lfnpend],0
        je      .nolfn
        mov     byte [lfnpend],0
        inc     word [cntnames]
        cmp     byte [delmode],0
        jne     .nolfn
        call    shownames
.nolfn: test    byte [bx+0Bh],10h
        jz      .next
        cmp     byte [bx],'.'
        je      .next
        call    enqueue
        jmp     .next
.lfn:   inc     word [cntslots]
        cmp     byte [delmode],0
        je      .collect
        mov     byte [bx],0E5h
        mov     byte [dirty],1
        jmp     .next
.collect:
        call    lfnpart
        jmp     .next
.clrp:  mov     byte [lfnpend],0
.next:  add     bx,32
        cmp     bx,secbuf+SECSIZE
        jb      .ent
        call    flush
        clc
        ret
.eod:   call    flush
        stc
        ret

flush:  cmp     byte [dirty],0
        je      .r
        mov     ax,[cursec]
        mov     dx,[cursec+2]
        mov     cx,1
        mov     bx,secbuf
        call    rawwrite
        jnc     .r
        mov     dx,msg_writeerr
        jmp     fail
.r:     ret

; Copy 13 UCS-2 characters of the LFN slot at bx into lfnbuf (low byte only).
lfnpart:
        push    bx
        mov     al,[bx]
        test    al,40h                  ; last slot comes first: new name
        jz      .keep
        push    ax
        mov     di,lfnbuf
        mov     cx,LFNMAX+1
        xor     al,al
        rep     stosb
        pop     ax
.keep:  and     al,1Fh
        jz      .out
        cmp     al,20
        ja      .out
        dec     al
        mov     ah,13
        mul     ah
        add     ax,lfnbuf
        mov     di,ax
        mov     si,lfnoffs
        mov     cx,13
.ch:    push    bx
        mov     al,[si]
        inc     si
        xor     ah,ah
        add     bx,ax
        mov     dx,[bx]
        pop     bx
        mov     al,0
        cmp     dx,0FFFFh
        je      .st
        mov     al,dl
        or      dh,dh
        jz      .st
        mov     al,'?'
.st:    stosb
        loop    .ch
        mov     byte [lfnpend],1
.out:   pop     bx
        ret

; Print "path\SHORT.EXT = long name" for the entry at bx.
shownames:
        push    bx
        mov     dx,curpath
        call    puts
        mov     di,namebuf
        call    fmt83
        mov     byte [di],0
        mov     dx,namebuf
        call    puts
        mov     dx,msg_eq
        call    puts
        mov     dx,lfnbuf
        call    puts
        call    crlf
        pop     bx
        ret

; Queue the subdirectory at bx with path curpath + NAME.EXT + '\'.
enqueue:
        push    bx
        mov     ax,[bx+1Ah]
        or      ax,ax
        jz      .out
        cmp     word [qcount],QMAX
        jb      .room
        mov     byte [qoverflow],1
        jmp     .out
.room:  push    ax
        mov     ax,[qtail]
        mov     cx,QENTRY
        mul     cx
        add     ax,queue
        mov     di,ax
        pop     ax
        stosw
        mov     [qslot],di
        mov     si,curpath
        call    strcpy
        dec     di                      ; back onto the terminator
        mov     ax,di
        sub     ax,[qslot]
        cmp     ax,PATHLEN-15           ; too deep to show: keep parent path
        ja      .full
        call    fmt83                   ; at most 12 chars
        mov     al,'\'
        stosb
        xor     al,al
        stosb
.full:
        mov     ax,[qtail]
        inc     ax
        cmp     ax,QMAX
        jb      .t
        xor     ax,ax
.t:     mov     [qtail],ax
        inc     word [qcount]
.out:   pop     bx
        ret

; Write the 8.3 name of the entry at bx to di (no terminator).
fmt83:  mov     si,bx
        mov     cx,8
        call    copytrim
        cmp     byte [bx+8],' '
        je      .r
        mov     al,'.'
        stosb
        lea     si,[bx+8]
        mov     cx,3
        call    copytrim
.r:     ret

copytrim:                               ; copy cx chars from si, drop trailing blanks
        mov     dx,di
.c:     lodsb
        stosb
        cmp     al,' '
        je      .sp
        mov     dx,di
.sp:    loop    .c
        mov     di,dx
        ret

; Next cluster of ax. Returns 0FFFFh at end of chain.
fatnext:
        cmp     byte [fat16],0
        je      .f12
        mov     bx,ax
        mov     al,ah
        xor     ah,ah                   ; sector = clus / 256
        add     ax,[fatstart]
        call    loadfat
        xor     bh,bh
        shl     bx,1
        mov     ax,[fatbuf+bx]
        cmp     ax,0FFF8h
        jb      .r
        mov     ax,0FFFFh
.r:     ret
.f12:   mov     bx,ax
        shr     bx,1
        add     bx,ax                   ; byte offset = clus * 1.5
        push    ax
        mov     ax,bx
        mov     cl,9
        shr     ax,cl
        add     ax,[fatstart]
        call    loadfat
        and     bx,1FFh
        mov     dx,[fatbuf+bx]
        pop     ax
        test    al,1
        jz      .even
        mov     cl,4
        shr     dx,cl
.even:  and     dx,0FFFh
        mov     ax,dx
        cmp     ax,0FF8h
        jb      .r
        mov     ax,0FFFFh
        ret

loadfat:                                ; ax = sector; reads two for FAT12 spans
        cmp     ax,[fatcached]
        je      .r
        push    bx
        mov     [fatcached],ax
        xor     dx,dx
        mov     cx,2
        mov     bx,fatbuf
        call    rawread
        pop     bx
        jnc     .r
        mov     dx,msg_readerr
        jmp     fail
.r:     ret

; ---------------------------------------------------------------- raw I/O
; dx:ax = sector, cx = count, bx = buffer. CF=1 on error.

rawread:
        mov     byte [rawop],25h
        jmp     rawio
rawwrite:
        mov     byte [rawop],26h
rawio:  push    si
        push    di
        push    bp
        cmp     byte [useold],0
        jne     .old
        mov     [pk_sec],ax
        mov     [pk_sec+2],dx
        mov     [pk_cnt],cx
        mov     [pk_off],bx
        mov     [pk_seg],ds
        mov     cx,0FFFFh
        mov     bx,packet
        jmp     .call
.old:   or      dx,dx
        jz      .lo
        stc
        jmp     .ret
.lo:    mov     dx,ax
.call:  mov     al,[drive]
        cmp     byte [rawop],26h
        je      .w
        int     25h
        jmp     .pop
.w:     int     26h
.pop:   pop     word [scratch]          ; INT 25h/26h leave the flags on the stack
.ret:   pop     bp
        pop     di
        pop     si
        ret

; ---------------------------------------------------------------- output

strcpy: lodsb                           ; si -> di including terminator
        stosb
        or      al,al
        jnz     strcpy
        ret

puts:   push    si
        mov     si,dx
.l:     lodsb
        or      al,al
        jz      .r
        mov     dl,al
        call    putc
        jmp     .l
.r:     pop     si
        ret

putc:   mov     ah,02h
        int     21h
        ret

crlf:   mov     dx,msg_crlf
        jmp     puts

putdec: xor     cx,cx
        mov     bx,10
.d:     xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     .d
.p:     pop     dx
        add     dl,'0'
        call    putc
        loop    .p
        ret

; ---------------------------------------------------------------- data

msg_usage   db  'LFNDEL 0.1 - list/remove long file name entries (FAT12/16)',13,10
            db  'Usage: LFNDEL d: [/D]',13,10
            db  '  /D  delete all LFN entries after confirmation',13,10,0
msg_readerr db  'Disk read error.',13,10,0
msg_writeerr db 'Disk write error.',13,10,0
msg_nofat   db  'Not a FAT12/FAT16 drive with 512-byte sectors.',13,10,0
msg_eq      db  ' = ',0
msg_names   db  13,10,'Files with long names: ',0
msg_slots   db  ', LFN entries: ',0
msg_qovf    db  'Warning: too many directories, some were skipped.',13,10,0
msg_ask1    db  'Delete ',0
msg_ask2    db  ' LFN entries on ',0
msg_ask3    db  ':? (Y/N) ',0
msg_deleted db  'Deleted LFN entries: ',0
msg_reboot  db  13,10,'Reboot now so DOS does not reuse old buffers.',13,10,0
msg_crlf    db  13,10,0

lfnoffs     db  1,3,5,7,9,14,16,18,20,22,24,28,30
rootpath    db  '?:\',0

LFNMAX      equ 20*13

section .bss
bss_start:
drive       resb 1
wantdel     resb 1
delmode     resb 1
useold      resb 1
fat16       resb 1
dirty       resb 1
lfnpend     resb 1
qoverflow   resb 1
rawop       resb 1
            alignb 2
scratch     resw 1
spc         resw 1
spf         resw 1
fatstart    resw 1
rootstart   resw 1
rootsecs    resw 1
datastart   resw 1
maxclus     resw 1
cntnames    resw 1
cntslots    resw 1
qhead       resw 1
qtail       resw 1
qcount      resw 1
curclus     resw 1
chainguard  resw 1
qslot       resw 1
fatcached   resw 1
cursec      resd 1
packet:
pk_sec      resd 1
pk_cnt      resw 1
pk_off      resw 1
pk_seg      resw 1
curpath     resb PATHLEN
namebuf     resb 14
lfnbuf      resb LFNMAX+1
secbuf      resb SECSIZE
fatbuf      resb 2*SECSIZE
queue       resb QMAX*QENTRY
bss_end:
