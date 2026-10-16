; CHKCFG - fingerprint of BIOS setup (CMOS 10h-3Fh) and config files.
; Usage: CHKCFG statefile [file ...]
; ERRORLEVEL 0 = unchanged, 1 = changed or first run (statefile rewritten),
; 2 = usage or I/O error. Missing config files count as empty.
        cpu 8086
        org 100h

start:  mov si,81h
        call skipsp
        cmp byte [si],13
        je usage
        mov [statef],si
        call endtok
        mov word [crc],0FFFFh

        mov bl,10h                      ; CMOS setup area, no RTC time bytes
.cmos:  cli
        mov al,bl
        out 70h,al
        jmp short $+2
        in al,71h
        sti
        call crcbyte
        inc bl
        cmp bl,40h
        jb .cmos

.files: call skipsp
        cmp byte [si],13
        je .done
        mov dx,si
        call endtok
        push si
        mov ax,3D00h
        int 21h
        jc .next
        mov bx,ax
.read:  mov ah,3Fh
        mov cx,512
        mov dx,buf
        int 21h
        jc .close
        or ax,ax
        jz .close
        mov cx,ax
        mov di,buf
.byte:  mov al,[di]
        call crcbyte
        inc di
        loop .byte
        jmp .read
.close: mov ah,3Eh
        int 21h
.next:  pop si
        jmp .files

.done:  mov ax,[crc]
        mov di,hex
        call hexw
        mov dx,[statef]                 ; compare with stored fingerprint
        mov ax,3D00h
        int 21h
        jc .changed
        mov bx,ax
        mov ah,3Fh
        mov cx,4
        mov dx,old
        int 21h
        pushf
        mov ah,3Eh
        int 21h
        popf
        jc .changed
        mov si,old
        mov di,hex
        mov cx,4
        repe cmpsb
        jne .changed
        mov dx,msgsame
        call print
        mov ax,4C00h
        int 21h

.changed:
        mov dx,[statef]
        mov ah,3Ch
        xor cx,cx
        int 21h
        jc ioerr
        mov bx,ax
        mov ah,40h
        mov cx,6
        mov dx,hex
        int 21h
        mov ah,3Eh
        int 21h
        mov dx,msgchg
        call print
        mov ax,4C01h
        int 21h

usage:  mov dx,msguse
        mov ah,9
        int 21h
        mov ax,4C02h
        int 21h
ioerr:  mov dx,msgerr
        mov ah,9
        int 21h
        mov ax,4C02h
        int 21h

skipsp: cmp byte [si],' '
        je .s
        cmp byte [si],9
        jne .r
.s:     inc si
        jmp skipsp
.r:     ret

endtok: cmp byte [si],' '               ; zero-terminate token, SI after it
        je .z
        cmp byte [si],9
        je .z
        cmp byte [si],13
        je .e
        inc si
        jmp endtok
.z:     mov byte [si],0
        inc si
        ret
.e:     mov byte [si],0                 ; keep a CR for the caller
        mov byte [si+1],13
        inc si
        ret

crcbyte:                                ; CRC-16/CCITT, AL = byte
        push cx
        mov ah,al
        xor [crc+1],ah
        mov cx,8
.b:     shl word [crc],1
        jnc .n
        xor word [crc],1021h
.n:     loop .b
        pop cx
        ret

hexw:   mov cx,4
.h:     push cx
        mov cl,4
        rol ax,cl
        pop cx
        push ax
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe .d
        add al,7
.d:     stosb
        pop ax
        loop .h
        ret

print:  mov ah,9
        int 21h
        mov dx,hex
        mov ah,9
        int 21h
        ret

msguse  db 'CHKCFG statefile [file ...]',13,10,'$'
msgerr  db 'CHKCFG: cannot write state file',13,10,'$'
msgsame db 'CHKCFG: setup unchanged $'
msgchg  db 'CHKCFG: setup changed $'
hex     db '0000',13,10,'$'
statef  dw 0
crc     dw 0
old     db '    '
buf:
