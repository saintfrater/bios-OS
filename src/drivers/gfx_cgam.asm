; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gfx_cgam.asm
;  Author   : frater
;
;  License  : GNU General Public License v3.0 or later (GPL-3.0+)
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
; =============================================================================

;
; graphics drivers pour carte video/mode CGA-Mono (640x200x2)
;
%define VIDEO_SEG    	0xB800        	; ou 0xB000

%define GFX_MODE		0x06			; MCGA HiRes (B/W)
%define GFX_WIDTH		640
%define GFX_HEIGHT		200

%define CGA_STRIDE      80
%define CGA_ODD_BANK    0x2000

; décommenter cette constante si vous voulez un mode aligné/non alligné différent
; sinon le code utilisé sera toujours "shifted"
; %define FULL_MODE_ALLIGNED          1

; align putch mode
%define GFX_TXT_WHITE_TRANSPARENT   0
%define GFX_TXT_BLACK_TRANSPARENT   1
%define GFX_TXT_TRANSP_ON_WHITE     2
%define GFX_TXT_WHITE_ON_BLACK      3
%define GFX_TXT_BLACK_ON_WHITE      4

%macro GFX_DRV  1
    call word [cs:graph_driver + ((%1)*2)]
%endmacro

; ------------------------------------------------------------
; TABLE DE SAUT (VECTEURS API)
; Cette table doit être située au début du driver pour être
; accessible par la GUI à des offsets fixes.
; ------------------------------------------------------------
%define	GFX_INIT		0
%define GFX_PUTPIXEL	1
%define GFX_GETPIXEL 	2
%define GFX_GOTOXY		3
%define GFX_PUTCH_MODE  4
%define GFX_PUTCH       5
%define GFX_WRITE       6
%define GFX_CRS_UPDATE  7

graph_driver:
        dw cga_init
        dw cga_putpixel
        dw cga_getpixel
        dw cga_set_charpos
        dw cga_none
        dw cga_putc
        dw cga_write
 		dw cga_cursor_move
;    jmp gfx_fill_rect       ; Remplissage rectangle (Nouveau)
;    jmp gfx_invert_rect     ; Offset +12: Inversion (Nouveau pour Menus)
;    jmp gfx_draw_hline      ; Offset +15: Ligne horizontale rapide (Nouveau)

%include "./common/cursor.asm"
%include "./common/chartable.asm"

;
;
; convert al -> AX aligned with "cl"
%macro ALING_BYTE 0
        mov     ah,al
        xor     al,al
        shr     ax,cl

        xchg    ah,al
%endmacro


%macro GFX_SET_WRTIE_MODE 1
        push    fs

        push    BDA_DATA_SEG
        pop     fs

        mov     byte [fs:BDA_GFX + gfx.cur_mode], %1

        pop     fs
        pop     ax
%endmacro

; ------------------------------------------------------------
; COMMENTAIRE SUR LA MÉTHODE D'APPEL
;
; Pour appeler une fonction du driver depuis votre GUI :
; 1. Définissez l'adresse de base du driver (ex: GFX_DRIVER_BASE)
; 2. Utilisez un call indirect via l'offset de la table.
;
; Exemple en ASM pour remplir un rectangle :
;    call [GFX_DRIVER_BASE + 9]  ; Appelle gfx_fill_rect
;
; Cette méthode isole totalement votre bibliothèque GUI du driver.
; Si vous changez le code du driver, tant que la table au début
; ne change pas d'ordre, la GUI n'a pas besoin d'être recompilée.
; ------------------------------------------------------------

; ------------------------------------------------------------
; initialise le mode graphique (via l'int 10h)
;
; ce mode est entrelacé, un bit/pixel, 8 pixels par octet
; ------------------------------------------------------------
cga_init:
    mov     ax, BDA_DATA_SEG
    mov     ds, ax

	; init graphics mode
	mov 	ah, 0x00     	                		; AH=00h set video mode
	mov		al, GFX_MODE
	int 	0x10
	mov		byte [BDA_MOUSE + mouse.bkg_saved],0	; flag image saved

    ; mov     byte [BDA_GFX + gfx.cur_mode], 1
	; dessine un background "check-board"
	call	cga_background
	ret

cga_none:
    ret


; ------------------------------------------------------------
; Calcule DI + AH=mask pour (CX=x, DX=y) en mode CGA 640x200
;
; Out: ES=VIDEO_SEG, DI=offset, AH=bitmask (0x80 >> (x&7))
; ------------------------------------------------------------
cga_calc_addr:
	; calcul de l'offset 'y':
	; si y est impaire, DI+=0x2000
	; DI = (y>>1)*80 + (x>>3) + (y&1)*0x2000
	mov	    ax, dx
	shr 	ax, 1                  ; ax = y/2
	mov     di, ax
	shl  	di, 4                  ; (y/2)*16
	shl     ax, 6                  ; (y/2)*64
	add     di, ax                 ; *80
	mov     ax, cx
	shr     ax, 3
	add     di, ax
	test    dl, 1
	jz      .even
	add     di, CGA_ODD_BANK
.even:
	; masque bit = 0x80 >> (x&7)
	push	cx
	and     cl, 7
	mov     ah, 080h
	shr     ah, cl
	pop     cx
	ret

; ---------------------------------------------------------------------------
; gfx_set_charpos
; In : CX = x (pixels), DX = y (pixels)
; Out: variables DS:GFX_CUR_*
; Notes:
;  - calcule l'offset VRAM de la scanline y: base = (y&1?2000:0) + (y>>1)*80 + (x>>3)
;  - stocke aussi shift = x&7
; ---------------------------------------------------------------------------
cga_set_charpos:
        pusha
        push    fs

        mov     ax,BDA_DATA_SEG
        mov     fs,ax

        ; store x,y en pixel
        mov     [fs:BDA_GFX + gfx.cur_x], cx
        mov     [fs:BDA_GFX + gfx.cur_y], dx

        mov     ax, cx
        and     ax, 0x07
        mov     [fs:BDA_GFX + gfx.cur_shift], al

        ; calcul de l'offset de la position 'x,y':
        ; si 'y' est paire, DI < 0x2000 & add = 0x2000
        ; si 'y' est impaire, DI> 0x2000 & add = -0x2000
        ; DI = (y>>1)*80 + (x>>3) + (y&1)*
        mov     ax, dx
        shr     ax, 1
        mov     bx, ax                          ; bx = dx>>1
        shl     bx, 4                           ; bx = bx * 16
        shl     ax, 6                           ; ax = ax * 64
        add     bx, ax
        mov     ax, cx
        shr     ax, 3                           ; ax = x/8
        add     bx, ax
        mov     ax, CGA_ODD_BANK

        test    dl, 1
        jz      .even
        add     bx, ax
        neg     ax
.even:
        mov     [fs:BDA_GFX + gfx.cur_line_ofs], ax
        mov     [fs:BDA_GFX + gfx.cur_offset], bx

        pop     fs
        popa
        ret

; ---------------------------------------------------------------------------
; get_glyph_offset
; In : AL = char (ASCII)
; Out: CS:SI -> 8 bytes
; ---------------------------------------------------------------------------
get_glyph_offset:
        cmp     al, 0x20
        jb      .qmark              ; al < 20h (' '
        cmp     al, 0x7E
        ja      .qmark              ; al > 7Eh ('~')
        sub     al, 0x20
        jmp     .ok
.qmark:
        mov     al, '?'
        sub     al, 0x20
.ok:
        xor     ah, ah
        mov     si, ax
        shl     si, 3
        add     si, font8x8
        ret

; ---------------------------------------------------------------------------
; cga_putc_aligned
; In : AL = char (ASCII)
; Uses: DS:GFX_CUR_* (baseDI, shift, etc.)
; Out: avance le curseur d'un caractère (8 pixels) sans recalcul complet
; Notes:
;  - Nécessite une font 8x8 accessible en CS (voir get_glyph8x8_cs_si)
;  - Transparent: bits 0 du glyph ne touchent pas le fond
; ---------------------------------------------------------------------------

%ifdef FULL_MODE_ALLIGNED
cga_putc_aligned:
    ; Base offset VRAM pour la scanline Y
    mov     di, [fs:BDA_GFX + gfx.cur_offset]
    mov     bx, [fs:BDA_GFX + gfx.cur_line_ofs]
    mov     dl, [fs:BDA_GFX + gfx.cur_mode]

    mov     cx,4
.row_loop:
    ; AL = byte glyph pour cette scanline
    mov     ax, [cs:si]
    add     si,2

    cmp     dl,0
    jne     .black_transparent

    ; white with transparent
    or      [es:di], al
    or      [es:di+bx], ah
    jmp     .next

.black_transparent:
    cmp     dl,1
    jne     .transparent_white

    ; black with transparent
    not      ax
    and      [es:di], al
    and      [es:di+bx], ah
    jmp     .next

.transparent_white:
    cmp     dl,2
    jne     .black_white

    ; transparent on white
    not      ax
    or      [es:di], al
    or      [es:di+bx], ah
    jmp     .next

.black_white:
    cmp     dl,3
    jne     .white_transparent

    ; white on black
    mov     [es:di], al
    mov     [es:di+bx], ah
    jmp     .next

.white_transparent:
    not      ax
    mov     [es:di], al
    mov     [es:di+bx], ah

.next:
    add     di,CGA_STRIDE

    loop    .row_loop

    ; Avancer curseur d'un caractère (8 pixels)
    inc     word [fs:BDA_GFX + gfx.cur_offset]
    add     word [fs:BDA_GFX + gfx.cur_x], 8

    ret
%endif

; ---------------------------------------------------------------------------
; cga_putc_unalign
; In : AL = char (ASCII)
; Uses: FS:BDA_GFX + gfx.cur_* (offset, add_ofs, shift, mode)
; Notes:
;   - x non aligné (x&7 != 0)
;   - écrit sur 2 bytes (di et di+1) dans chaque banque
; ---------------------------------------------------------------------------
cga_putc_unaligned:
    ; Base offset VRAM pour la scanline Y
    mov     di, [fs:BDA_GFX + gfx.cur_offset]
    mov     bx, [fs:BDA_GFX + gfx.cur_line_ofs]
    mov     ch, [fs:BDA_GFX + gfx.cur_mode]
    mov     cl, [fs:BDA_GFX + gfx.cur_shift]

    mov     bp,4
.row_loop:

    ; ligne "paire" du gylphe
    mov     al, [cs:si]
    inc     si
    ALING_BYTE
    push    ax

    ; ligne "impaire" du gylphe
    mov     al, [cs:si]
    inc     si
    ALING_BYTE
    pop     dx
    xchg    ax, dx

    cmp     ch,0
    ja     .black_transparent

; white with transparent
    or      [es:di], ax
    or      [es:di+bx], dx
    jmp     .next

.black_transparent:
;    cmp     ch,1
;    jne     .transparent_white

; black with transparent
    not      ax
    not      dx
    and      [es:di], ax
    and      [es:di+bx], dx
;    jmp     .next
.next:
    add     di,CGA_STRIDE

    dec     bp
    jnz     .row_loop

    ; Avancer curseur d'un caractère (8 pixels)
    inc     word [fs:BDA_GFX + gfx.cur_offset]
    add     word [fs:BDA_GFX + gfx.cur_x], 8

    ret

cga_putc:
    pusha
    push    fs
    push    es

    mov     bx, VIDEO_SEG
    mov     es, bx
    mov     bx, BDA_DATA_SEG
    mov     fs, bx

    call    get_glyph_offset

%ifdef FULL_MODE_ALLIGNED
    cmp     byte [fs:BDA_GFX + gfx.cur_shift], 0
    jne     .unaligned

    call    cga_putc_aligned
    jmp     .done
.unaligned:
%endif

    call    cga_putc_unaligned
.done:
    pop     es
    pop     fs
    popa
    ret

;
; write string from [DS:SI] to screen
;
cga_write:
    push    ax

.loops:
    lodsb
    cmp     al,0
    je      .done
    call    cga_putc
    jmp     .loops
.done:

    pop     ax
    ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   ES = Target Segment (usually VIDEO_SEG)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_local_putpixel:
		call   	cga_calc_addr

		; write
		cmp     bl, 0
		je    	.clear
.set:
		or      byte [es:di], ah
		jmp     .done

.clear:
		not     ah
		and     byte [es:di], ah

.done:
		ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_putpixel:
		push	ax
		push  	di
		push    es

		mov		ax,	VIDEO_SEG
		mov		es,ax
		call   	cga_calc_addr

		; write
		cmp  	bl, 0
		je    	.clear
.set:
		or   	byte [es:di], ah
		jmp     .done

.clear:
		not     ah
		and     byte [es:di], ah

.done:
		pop 	es
		pop   	di
		pop		ax
		ret

; ------------------------------------------------------------
; Lit un pixel (CX=x, DX=y)
; Out: AL=0/1
; ------------------------------------------------------------
cga_getpixel:
		push    	di
		push    	es

		call    	cga_calc_addr
		mov     	al, [es:di]
		and     	al, ah
		setnz   	al

		pop     	es
		pop     	di
		ret

; ------------------------------------------------------------
; Dessine un background "check-board", accès VRAM direct.
;
; ------------------------------------------------------------
cga_background:
		mov		ax,VIDEO_SEG
		mov		es,ax
		mov		di,0x0000
		mov		eax,0xaaaaaaaa
		mov		cx,0x800
		rep		stosd
		mov		di,0x2000
		mov		eax,0x55555555
		mov		cx,0x800			; 640/8/4
		rep		stosd
		ret

; ------------------------------------------------------------
; Calcule les infos de l'alignement du curseur, basé sur cx=X
; il est important que DS pointe sur le BDA_MOUSE_SEG
; Out: BDA_CURSOR_BITOFF, BDA_CURSOR_BYTES
; ------------------------------------------------------------
cga_cursor_calc_align:
        mov     al, cl
        and     al, 7                  ; offset = x&7
        mov     byte [BDA_MOUSE + mouse.cur_bit_ofs], al
        ret

; ------------------------------------------------------------
; Dessine un pixel, en [ES:DI] accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
cga_putpixel_fast:
		cmp  	bl, 0
		je    	.clear
.set:
		or      byte [es:di], ah
		jmp     .done
.clear:
		not     ah
		and     byte [es:di], ah
.done:
		ret

; ------------------------------------------------------------
; Lit un pixel, en [ES:DI] accès VRAM direct.
;
; ------------------------------------------------------------
cga_getpixel_fast:
		mov     al, [es:di]
		and     al, ah
		setnz   al
		ret

cga_cursor_move:
		push    ax
		push 	ds
		push 	es

		; move Data Segment
		mov		ax, BDA_DATA_SEG
		mov		ds, ax

		cmp		byte [BDA_MOUSE + mouse.cur_drawing],0
		jne		.done
		mov 	byte [BDA_MOUSE + mouse.cur_drawing],1

		mov		ax, VIDEO_SEG
		mov		es, ax

		call 	cga_cursor_restorebg

		call	cga_cursor_savebg

		call 	cga_cursor_draw
		mov 	byte [BDA_MOUSE + mouse.cur_drawing],0
.done:
		pop 	es
		pop 	ds
		pop     ax
		ret

; -----------------------------------------------
; cga_cursor_savebg_32
; Sauve 16 lignes (3 bytes/ligne) sous le curseur.
; Stocke 16 DWORDs: chaque DWORD contient (b0|b1<<8|b2<<16) dans les 24 bits bas.
; -----------------------------------------------
cga_cursor_savebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    jne     .done

    mov     byte [BDA_MOUSE + mouse.bkg_saved], 1

    ; mémoriser position courante (utilisée pour restore)
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    mov     [BDA_MOUSE + mouse.cur_x], cx
    mov     [BDA_MOUSE + mouse.cur_y], dx

    ; calcule ES:DI pour (x,y)
    call    cga_calc_addr

    ; bank_add = +0x2000 si DI<0x2000 sinon -0x2000
    mov     bx, 02000h
    cmp     di, bx
    jl      .bank_ok
    neg     bx
.bank_ok:
    mov     [BDA_MOUSE + mouse.cur_addr_start], di
    mov     [BDA_MOUSE + mouse.cur_bank_add], bx

    ; DS:SI = buffer (64 bytes)
    lea     si, [BDA_MOUSE + mouse.bkg_buffer]

    mov     bp, 8                      ; 8 itérations = 16 lignes (pair/impair via bank)
.rowpair:
    ; ---- ligne bank courant ----
    mov     eax, [es:di]               ; lit b0 b1 b2 b3
    and     eax, 00FFFFFFh             ; ne garder que 3 bytes
    mov     [ds:si], eax               ; stocke 4 bytes (le byte haut sera 0)
    add     si, 4

    ; ---- ligne bank opposé ----
    add     di, bx                     ; +0x2000 ou -0x2000
    mov     eax, [es:di]
    and     eax, 00FFFFFFh
    mov     [ds:si], eax
    add     si, 4

    sub     di, bx
    add     di, CGA_STRIDE*2           ; avance de 2 lignes dans bank courant
    dec     bp
    jnz     .rowpair

.done:
    ret

; -----------------------------------------------
; cga_cursor_restorebg_32
; Restaure 16 lignes sauvegardées.
; Pour ne pas écraser le 4e byte voisin:
;   dst = (dst & 0xFF000000) | (saved & 0x00FFFFFF)
; -----------------------------------------------
cga_cursor_restorebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    je      .done

    mov     byte [BDA_MOUSE + mouse.bkg_saved], 0

    ; restaurer depuis la dernière position sauvegardée
    mov     di, [BDA_MOUSE + mouse.cur_addr_start]
    mov     bx, [BDA_MOUSE + mouse.cur_bank_add]

    lea     si, [BDA_MOUSE + mouse.bkg_buffer]

    mov     bp, 8
.rowpair:
    ; ---- ligne bank courant ----
    mov     eax, [ds:si]               ; saved (24 bits bas)
    add     si, 4
    mov     ecx, [es:di]               ; dst actuel
    and     ecx, 0FF000000h            ; garder b3
    and     eax, 00FFFFFFh
    or      eax, ecx
    mov     [es:di], eax

    ; ---- ligne bank opposé ----
    add     di, bx
    mov     eax, [ds:si]
    add     si, 4
    mov     ecx, [es:di]
    and     ecx, 0FF000000h
    and     eax, 00FFFFFFh
    or      eax, ecx
    mov     [es:di], eax

    sub     di, bx
    add     di, CGA_STRIDE*2
    dec     bp
    jnz     .rowpair

.done:
    ret

; ============================================================
; gfx_cursor_draw_rm16_i386_self
; Entrée:
;   DS = BDA_DATA_SEG
; Sortie: rien
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
; ============================================================
cga_cursor_draw:
    pushad
    push    ds
    push    es

    mov     ax, BDA_DATA_SEG
    mov     ds, ax
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; --- CLIPPING VERTICAL ---
    mov     dx, [ds:BDA_MOUSE + mouse.y]
    cmp     dx, 200
    jae     .exit_total

    mov     bp, 16
    mov     ax, 200
    sub     ax, dx                                  ; 200-y
    cmp     bp, ax
    jbe     .y_ok                                   ; y<= 200-16

    mov     bp, ax
.y_ok:

    ; --- ADRESSAGE ---
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    call    cga_calc_addr                           ; DI = Offset VRAM

    mov     ax, [BDA_MOUSE + mouse.cur_seg]
    mov     gs, ax
    mov     si, [BDA_MOUSE + mouse.cur_ofs]

    ; --- CALCUL de l'offset entre 2 lignes +0x2000 ou -0x2000 ---
    mov     ax, 0x2000          ; Banque +1
    mov     cx, [BDA_MOUSE + mouse.y]
    test    cx, 1
    jz      .setup_done
    neg     ax                  ; banque -1
.setup_done:
    mov     cx, ax

.row_loop:
    ; --- CONSTRUCTION DES MASQUES (EAX/EBX) ---
    push    cx                  ; préserver la banque "suivante"
    mov     ch, [BDA_MOUSE + mouse.x]
    and     ch, 0x07
    mov     cl, 16
    sub     cl, ch

    mov     eax,0xffff0000
    mov     ax, [gs:si]         ; masque AND
    bswap   eax
    ror     eax, cl

    xor     ebx, ebx
    mov     bx, [gs:si+32]      ; masque XOR
    bswap   ebx
    ror     ebx, cl
    mov     edx, [es:di]        ; lecture des 16 bits a la position du curseur

    and     edx, eax            ; application du masque AND (AX)
    xor     edx, ebx            ; application du masque XOR (BX)

    mov     [es:di], edx        ; ecriture du résultat

    pop     cx
    add     di, cx              ; banque suivante
    test    cx,0x8000
    jz      .next_line
    add     di,80

.next_line:
    neg     cx                  ; prochaine banque = -banque
    add     si, 2               ; Prochaine ligne du sprite
    dec     bp
    jnz     .row_loop

.exit_total:
    pop     es
    pop     ds
    popad
    ret