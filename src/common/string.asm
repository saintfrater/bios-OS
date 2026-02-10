; -----------------------------------------------------------------------------
; strcpy
; Copie une chaine ASCIIZ
; -----------------------------------------------------------------------------
%define .dest_seg word [bp+4]
%define .dest_ofs word [bp+6]
%define .src_seg  word [bp+8]
%define .src_ofs  word [bp+10]
strcpy:
	push    bp
	mov     bp, sp
	push    ds
	push    es
	push    si
	push    di

	mov     ax, .src_seg
	mov     ds, ax
	mov     si, .src_ofs

	mov     ax, .dest_seg
	mov     es, ax
	mov     di, .dest_ofs

.loop:
	lodsb
	stosb
	test    al, al
	jnz     .loop

	pop     di
	pop     si
	pop     es
	pop     ds
	leave
	ret
%undef .dest_seg
%undef .dest_ofs
%undef .src_seg
%undef .src_ofs


; -----------------------------------------------------------------------------
; strlen
; Calcule la longueur d'une chaine [es:di]
; Out: CX = Length
; -----------------------------------------------------------------------------
%define .str_seg word [bp+4]
%define .str_ofs word [bp+6]
strlen:
    push    bp
	mov     bp, sp
    push    ax
    push    es
    push    di
	xor     cx, cx
    mov     ax, .str_seg
    mov     es, ax
    mov     di, .str_ofs

.loop:
	cmp     byte [es:di], 0
	je      .done
	inc     cx
	inc     di
	jmp     .loop

.done:
	pop     di
    pop     es
    pop     ax
	leave
	ret
%undef .str_seg
%undef .str_ofs
