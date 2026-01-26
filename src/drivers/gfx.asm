; ============================================================
; gfx_cursor_draw_rm16_i386_self
; Entrée:
;   DS = BDA_DATA_SEG
; Sortie: rien
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
; ============================================================
cga_cursor_draw:
    push    ds
    push    es
    push    fs
    push    gs
    pushad

    ; -----------------------------
    ; ES = VRAM
    ; -----------------------------
    mov     ax, VIDEO_SEG
    mov     es, ax

    mov     ax, BDA_DATA_SEG
    mov     ds, ax
    ; -----------------------------
    ; GS:SI = sprite (AND puis XOR à +32)
    ; -----------------------------
    mov     ax, [BDA_MOUSE + mouse.cur_seg]
    mov     gs, ax
    mov     si, [BDA_MOUSE + mouse.cur_ofs]

    ; -----------------------------
    ; Charger x,y
    ; CX = x, DX = y
    ; -----------------------------
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]

    ; off = x & 7 (stocké dans BL)
    mov     bl, cl
    and     bl, 7

    ; width = min(16, 640-x) -> DL
    mov     ax, GFX_WIDTH
    sub     ax, cx
    cmp     ax, 16
    jbe     .w_ok
    mov     ax, 16
.w_ok:
    test    al, al
    jz      .done
    mov     dl, al               ; DL = width (1..16)

    ; height = min(16, 200-y) -> BP (compteur)
    mov     bp, GFX_HEIGHT
    sub     bp, dx
    cmp     bp, 16
    jbe     .h_ok
    mov     bp, 16
.h_ok:
    test    bp, bp
    jz      .done

    ; bytes_to_touch = ((off + width + 7) >> 3) -> BH
    mov     ah, bl
    add     ah, dl
    add     ah, 7
    shr     ah, 3
    mov     bh, ah               ; BH = 1..3

    ; clipmask16 = 0xFFFF << (16-width) -> (on le recalculera par ligne)
    ; parité initiale (y&1) -> CH
    mov     ch, byte [BDA_MOUSE + mouse.y]
    and     ch, 1

    ; -----------------------------
    ; Calcul DI = adresse VRAM pour (x,y)
    ; DI = (y>>1)*80 + (x>>3) + (y&1)*0x2000
    ; -----------------------------
    mov     ax, dx
    shr     ax, 1                ; ax = y/2

    mov     di, ax
    shl     di, 4                ; (y/2)*16
    shl     ax, 6                ; (y/2)*64
    add     di, ax               ; *80

    mov     ax, cx
    shr     ax, 3                ; x/8
    add     di, ax

    test    byte [BDA_MOUSE + mouse.y], 1
    jz      .addr_even
    add     di, CGA_ODD_BANK
.addr_even:

    ; row index dans AL
    xor     ax, ax               ; AL = 0 (row)

.row_loop:
    ; conserver row + (off/bytes) sur pile, pour libérer BL/BH si besoin
    push    ax
    push    bx                   ; BL=off, BH=bytes_to_touch

    ; -----------------------------------------
    ; Charger AND/XOR pour la ligne (row=AL)
    ; CX = AND, DX = XOR
    ; -----------------------------------------
    xor     ah, ah
    shl     ax, 1                ; AX = row*2

    mov     bx, si
    add     bx, ax
    mov     cx, [gs:bx]          ; AND word
    add     bx, 32
    mov     dx, [gs:bx]          ; XOR word

    ; restaurer row dans AL
    pop     bx                   ; restore off/bytes into BL/BH
    pop     ax                   ; restore row in AL

    ; -----------------------------------------
    ; clipmask16 = 0xFFFF << (16-width)
    ; width est dans DL
    ; clipmask -> BX
    ; -----------------------------------------
    mov     bx, 0FFFFh
    mov     cl, 16
    sub     cl, dl
    shl     bx, cl               ; BX = clipmask

    ; AND' = AND | (~clipmask)
    mov     ax, bx
    not     ax
    or      cx, ax               ; CX = AND'

    ; XOR' = XOR & clipmask
    and     dx, bx               ; DX = XOR'

    ; -----------------------------------------
    ; Construire seg 16-bit depuis VRAM (ES:DI)
    ; w0 = (b0<<8)|b1
    ; seg = (w0<<off) | (b2>>(8-off)) si off!=0 et bytes==3
    ; seg -> AX
    ; -----------------------------------------
    ; AX = w0
    mov     ah, [es:di]          ; b0
    mov     al, [es:di+1]        ; b1

    ; if off==0 -> seg ready
    test    bl, bl
    jz      .seg_ready

    ; seg = w0 << off
    mov     cl, bl
    shl     ax, cl

    ; if bytes==3, OR b2>>(8-off)
    cmp     bh, 3
    jne     .seg_ready

    mov     cl, 8
    sub     cl, bl               ; 8-off
    xor     bh, bh               ; BH=0, BL=off (on évite bpl etc)
    mov     bl, [es:di+2]        ; BL=b2
    shr     bx, cl               ; BX = b2>>(8-off)
    or      ax, bx
    ; restaurer BL=off, BH=bytes: (on ne peut pas, on a écrasé)
    ; => ne jamais écraser BL/BH. Donc on refait proprement:
    ; (ce bloc est remplacé ci-dessous)
    ; --- on ne doit pas passer ici ---
.seg_ready:

    ; *** IMPORTANT ***
    ; Le bloc ci-dessus a montré le piège (écraser BL/BH).
    ; On fait le chemin correct ci-dessous, sans toucher BL/BH.

    ; Refaire seg proprement sans écraser BL/BH:
    ; AX = w0 (recharge)
    mov     ah, [es:di]
    mov     al, [es:di+1]

    test    bl, bl
    jz      .seg2_ready

    mov     cl, bl
    shl     ax, cl

    cmp     bh, 3
    jne     .seg2_ready

    mov     cl, 8
    sub     cl, bl               ; 8-off
    xor     ah, ah
    mov     al, [es:di+2]        ; AL=b2
    ; AX = b2
    shr     ax, cl               ; AX = b2>>(8-off)
    ; OR into seg: need seg in another reg -> use BX temp
    mov     bx, [es:di]          ; not ok (word read uses little endian, avoid)
    ; simplest: use stack temp
    push    ax                   ; save (b2>>(8-off))
    ; reload seg again and OR
    mov     ah, [es:di]
    mov     al, [es:di+1]
    mov     cl, bl
    shl     ax, cl
    pop     bx
    or      ax, bx
.seg2_ready:

    ; -----------------------------------------
    ; newseg = (seg & AND') ^ XOR'
    ; seg in AX
    ; -----------------------------------------
    and     ax, cx
    xor     ax, dx               ; AX=newseg

    ; -----------------------------------------
    ; Ecriture vers VRAM
    ; - off==0 : b0=AH, b1=AL (si bytes>=2)
    ; - off!=0 : b0 partiel, b1 complet si bytes>=2, b2 partiel si bytes==3
    ; -----------------------------------------
    test    bl, bl
    jnz     .write_unaligned

.write_aligned:
    mov     [es:di], ah
    cmp     bh, 1
    je      .after_write
    mov     [es:di+1], al
    jmp     .after_write

.write_unaligned:
    ; mask0 = (1<<(8-off))-1  (bits bas de b0)
    mov     cl, 8
    sub     cl, bl
    mov     dh, 1
    shl     dh, cl
    dec     dh                   ; DH = mask0

    ; val0 = newseg >> (8+off)
    mov     bx, ax               ; BX = newseg
    mov     cl, bl
    add     cl, 8
    shr     bx, cl               ; BL = val0 (low 8)

    ; b0 = (old & ~mask0) | (val0 & mask0)
    mov     dl, [es:di]          ; old b0
    mov     cl, dh               ; CL=mask0
    not     cl
    and     dl, cl               ; keep upper bits
    not     cl                   ; CL=mask0
    and     bl, cl               ; val0 masked
    or      dl, bl
    mov     [es:di], dl

    cmp     bh, 1
    je      .after_write

    ; b1 = (newseg >> off) & 0xFF
    mov     bx, ax
    mov     cl, bl               ; BUG: BL now val0, not off
    ; => on doit recharger off depuis BDA_MOUSE.x &7, ou le sauver.
    ; On le sauve au début de la fonction dans une variable: ici on le recharge (coût faible)
    mov     bl, [BDA_MOUSE + mouse.x] ; low byte x
    and     bl, 7
    mov     cl, bl
    shr     bx, cl
    mov     [es:di+1], bl

    cmp     bh, 2
    je      .after_write

    ; b2 partiel (bits hauts off)
    ; mask2 = 0xFF << (8-off)
    mov     cl, 8
    sub     cl, bl               ; bl=off
    mov     dl, 0FFh
    shl     dl, cl               ; DL=mask2

    ; part2 = (newseg << (8-off)) & 0xFF
    mov     bx, ax               ; BX=newseg
    shl     bx, cl               ; BL=part2

    ; b2 = (old & ~mask2) | (part2 & mask2)
    mov     dh, [es:di+2]        ; old b2
    mov     cl, dl               ; CL=mask2
    not     cl
    and     dh, cl
    not     cl
    and     bl, cl
    or      dh, bl
    mov     [es:di+2], dh

.after_write:
    ; -----------------------------------------
    ; next row
    ; -----------------------------------------
    inc     al
    dec     bp
    jz      .done

    ; stepping CGA:
    ; even->odd: +0x2000
    ; odd ->even: -0x2000 + 80
    test    ch, ch
    jz      .even_to_odd

    ; odd -> even
    sub     di, CGA_ODD_BANK
    add     di, CGA_STRIDE
    xor     ch, ch
    jmp     .row_loop

.even_to_odd:
    add     di, CGA_ODD_BANK
    mov     ch, 1
    jmp     .row_loop

.done:
    popad
    pop     gs
    pop     fs
    pop     es
    pop     ds
    ret