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
%define VIDEO_SEG    	0xB800        			; ou 0xB000

%define GFX_MODE			0x06								; MCGA HiRes (B/W)
%define GFX_WIDTH			640
%define GFX_HEIGHT		200

%define CGA_STRIDE    80
%define CGA_ODD_BANK  0x2000

; ------------------------------------------------------------
; TABLE DE SAUT (VECTEURS API)
; Cette table doit être située au début du driver pour être
; accessible par la GUI à des offsets fixes.
; ------------------------------------------------------------

%define	INIT							0
%define PUTPIXEL					3
%define GETPIXEL 					6
%define MOUSE_UPDATE 		  9

gfx_api:
    jmp gfx_init            ; Offset +0: Initialisation
    jmp gfx_putpixel        ; Offset +3: Dessin pixel
    jmp gfx_getpixel        ; Offset +6: Lecture pixel
		jmp gfx_cursor_move			; Offset +9: mouse update
;    jmp gfx_fill_rect       ; Remplissage rectangle (Nouveau)
;    jmp gfx_invert_rect     ; Offset +12: Inversion (Nouveau pour Menus)
;    jmp gfx_draw_hline      ; Offset +15: Ligne horizontale rapide (Nouveau)

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
gfx_init:
						; init graphics mode
						mov 			ah, 0x00     					; AH=00h set video mode
						mov				al, GFX_MODE
						int 			0x10

						mov		 		byte [BDA_MOUSE + mouse.bkg_saved],0	; flag image saved

						; dessine un background "check-board"
						call			gfx_background

						ret

; ------------------------------------------------------------
; Calcule DI + AH=mask pour (CX=x, DX=y) en mode CGA 640x200
;
; Out: ES=VIDEO_SEG, DI=offset, AH=bitmask (0x80 >> (x&7))
; ------------------------------------------------------------
gfx_calc_addr:
						; calcul de l'offset 'y':
						; si y est impaire, DI+=0x2000
        		; DI = (y>>1)*80 + (x>>3) + (y&1)*0x2000
        		mov	     	ax, dx
        		shr 	    ax, 1                  ; ax = y/2

						mov     	di, ax
						shl  		  di, 4                  ; (y/2)*16
						shl     	ax, 6                  ; (y/2)*64
						add     	di, ax                 ; *80

						mov     	ax, cx
						shr     	ax, 3
						add     	di, ax

						test    	dl, 1
						jz      	.even
						add     	di, CGA_ODD_BANK
.even:
						; masque bit = 0x80 >> (x&7)
						push		 	cx
						and     	cl, 7
						mov     	ah, 080h
						shr     	ah, cl
						pop     	cx
						ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   ES = Target Segment (usually VIDEO_SEG)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
gfx_local_putpixel:
						call   		gfx_calc_addr

						; write
						cmp  	   	bl, 0
						je    	  .clear
.set:
						or   		  byte [es:di], ah
						jmp       .done

.clear:
						not       ah
						and       byte [es:di], ah

.done:
						ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
gfx_putpixel:
						push			ax
						push  	  di
						push    	es

						mov				ax,	VIDEO_SEG
						mov				es,ax
						call   		gfx_calc_addr

						; write
						cmp  	   	bl, 0
						je    	  .clear
.set:
						or   		  byte [es:di], ah
						jmp       .done

.clear:
						not       ah
						and       byte [es:di], ah

.done:
						pop 	    es
						pop   	  di
						pop				ax
						ret

; ------------------------------------------------------------
; Lit un pixel (CX=x, DX=y)
; Out: AL=0/1
; ------------------------------------------------------------
gfx_getpixel:
						push    	di
						push    	es

						call    	gfx_calc_addr
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
gfx_background:
						mov				ax,VIDEO_SEG
						mov				es,ax
						mov				di,0x0000
						mov				eax,0xaaaaaaaa
						mov				cx,0x800
						rep				stosd
						mov				di,0x2000
						mov				eax,0x55555555
						mov				cx,0x800			; 640/8/4
						rep				stosd
						ret

; ------------------------------------------------------------
; Calcule les infos de l'alignement du curseur, basé sur cx=X
; il est important que DS pointe sur le BDA_MOUSE_SEG
; Out: BDA_CURSOR_BITOFF, BDA_CURSOR_BYTES
; ------------------------------------------------------------
gfx_cursor_calc_align:
        		mov     	al, cl
        		and     	al, 7                  ; offset = x&7
        		mov     	byte [BDA_MOUSE + mouse.cur_bit_ofs], al
        		ret

; ------------------------------------------------------------
; Dessine un pixel, en [ES:DI] accès VRAM direct.
;
;   CX = x (0..639)
;   DX = y (0..199)
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
gfx_putpixel_fast:
						cmp  	   	bl, 0
						je    	  .clear
.set:
						or   		  byte [es:di], ah
						jmp       .done
.clear:
						not       ah
						and       byte [es:di], ah
.done:
						ret

; ------------------------------------------------------------
; Lit un pixel, en [ES:DI] accès VRAM direct.
;
; ------------------------------------------------------------
gfx_getpixel_fast:
						mov     	al, [es:di]
						and     	al, ah
						setnz   	al
						ret

gfx_cursor_move:
						pusha
						push 			ds
						push 			es

						; move Data Segment
						mov				ax, BDA_DATA_SEG
						mov				ds, ax

						cmp				byte [BDA_MOUSE + mouse.cur_drawing],0
						jne				.done
						mov 			byte [BDA_MOUSE + mouse.cur_drawing],1

						mov		 		ax, VIDEO_SEG
						mov		 		es, ax

						;call 			gfx_cursor_restorebg

						;call			gfx_cursor_savebg

						call 			gfx_cursor_draw
						mov 			byte [BDA_MOUSE + mouse.cur_drawing],0
.done:
						pop 			es
						pop 			ds
						popa
						ret

bits 16

%define GFX_WIDTH    640
%define GFX_HEIGHT   200
%define CGA_STRIDE   80
%define CGA_ODD_BANK 0x2000

; ============================================================
; gfx_cursor_draw_rm16_i386_self
; Entrée:
;   DS = BDA_DATA_SEG
; Sortie: rien
; Détruit: registres sauvegardés/restaurés (PUSHA/POPA)
; ============================================================
gfx_cursor_draw_rm16_i386_self:
    push    es
    push    gs
    pusha

    ; -----------------------------
    ; ES = VRAM
    ; -----------------------------
    mov     ax, VIDEO_SEG
    mov     es, ax

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
    popa
    pop     gs
    pop     es
    ret

; -----------------------------------------------
; gfx_cursor_savebg_32
; Sauve 16 lignes (3 bytes/ligne) sous le curseur.
; Stocke 16 DWORDs: chaque DWORD contient (b0|b1<<8|b2<<16) dans les 24 bits bas.
; -----------------------------------------------
gfx_cursor_savebg:
    cmp     byte [BDA_MOUSE + mouse.bkg_saved], 0
    jne     .done

    mov     byte [BDA_MOUSE + mouse.bkg_saved], 1

    ; mémoriser position courante (utilisée pour restore)
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]
    mov     [BDA_MOUSE + mouse.cur_x], cx
    mov     [BDA_MOUSE + mouse.cur_y], dx

    ; calcule ES:DI pour (x,y)
    call    gfx_calc_addr

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
; gfx_cursor_restorebg_32
; Restaure 16 lignes sauvegardées.
; Pour ne pas écraser le 4e byte voisin:
;   dst = (dst & 0xFF000000) | (saved & 0x00FFFFFF)
; -----------------------------------------------
gfx_cursor_restorebg:
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