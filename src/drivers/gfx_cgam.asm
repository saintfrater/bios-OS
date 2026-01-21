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

						call 			gfx_cursor_restorebg

						call			gfx_cursor_savebg

						call 			gfx_cursor_draw
						mov 			byte [BDA_MOUSE + mouse.cur_drawing],0
.done:
						pop 			es
						pop 			ds
						popa
						ret

; ============================================================
; gfx_draw_cursor (CPU>=386, bits 16) - PAS de clamp
; x:0..639, y:0..199
; clipping droite/bas:
;   width  = min(16, 640-x)
;   height = min(16, 200-y)
; bytes_to_touch = ((off + width + 7) >> 3)  ; 1..3
;
; Requiert:
;   gfx_calc_addr (CX=x, DX=y) => DI (bank incluse)
;   sprite en GS:SI (AND[16w] puis XOR[16w] à +32)
;
; ============================================================
gfx_cursor_draw:
    push    ds
    push    es
    push    gs
    pusha

    mov     ax, BDA_DATA_SEG
    mov     ds, ax

    ; GS:SI sprite
    mov     ax, [BDA_MOUSE + mouse.cur_seg]
    mov     gs, ax
    mov     si, [BDA_MOUSE + mouse.cur_ofs]

    ; ES VRAM
    mov     ax, VIDEO_SEG
    mov     es, ax

    ; x,y
    mov     cx, [BDA_MOUSE + mouse.x]
    mov     dx, [BDA_MOUSE + mouse.y]

    ; off = x&7 -> BL
    mov     bl, cl
    and     bl, 7

    ; width = min(16, 640-x) -> AL
    mov     ax, 640
    sub     ax, cx
    cmp     ax, 16
    jbe     .w_ok
    mov     ax, 16
.w_ok:
    ; AL = width
    test    al, al
    jz      .done

    ; height = min(16, 200-y) -> DL
    mov     bp, 200
    sub     bp, dx
    cmp     bp, 16
    jbe     .h_ok
    mov     bp, 16
.h_ok:
    mov     ax, bp
    mov     dl, al                 ; DL = height
    test    dl, dl
    jz      .done

    ; bytes_to_touch = ((off + width + 7) >> 3) -> BH
    mov     ah, bl
    add     ah, al
    add     ah, 7
    shr     ah, 3
    mov     bh, ah                 ; BH=1..3

    ; clip_mask16 = 0xFFFF << (16-width) -> BP
    mov     bp, 0FFFFh
    mov     cl, 16
    sub     cl, al
    shl     bp, cl                 ; BP = clipmask

    ; DI pour (x,y)
    call    gfx_calc_addr

    ; bank_add = +0x2000 si DI<0x2000 sinon -0x2000 -> BX
    mov     bx, 02000h
    cmp     di, bx
    jl      .bank_ok
    neg     bx
.bank_ok:

    ; AL = row (0..15)
    xor     ax, ax                 ; AL=0, AH=0
    ; AH = toggle bank flag:
    ; 0 => prochaine ligne: DI += BX
    ; 1 => prochaine ligne: DI -= BX, DI += 80
    xor     ah, ah

.line_loop:
    push    ax                     ; préserver row(AL) + toggle(AH) (draw_line_masked détruit AX)

    ; charge AND'/XOR' clippés pour row=AL -> CX/DX
    call    .load_andxor_clipped

    ; dessine la ligne: ES:DI, BL=off, BH=bytes, CX=AND', DX=XOR'
    call    draw_line_masked

    pop     ax                     ; restore row/toggle

    ; next line
    inc     al
    dec     dl
    jz      .done

    ; alternance banks et stride CGA
    test    ah, ah
    jnz     .to_base

    ; vers autre bank
    add     di, bx
    mov     ah, 1
    jmp     .line_loop

.to_base:
    sub     di, bx
    add     di, CGA_STRIDE
    xor     ah, ah
    jmp     .line_loop

.done:
    popa
    pop     gs
    pop     es
    pop     ds
    ret


; ------------------------------------------------------------
; .load_andxor_clipped
; Entrées:
;   AL = row (0..15)
;   GS:SI = base sprite
;   BP = clipmask16
; Sorties:
;   CX = AND' , DX = XOR'
; Détruit:
;   AX, DI (DI restauré)
; ------------------------------------------------------------
.load_andxor_clipped:
    push    di
    xor     ah, ah
    shl     ax, 1                  ; AX = row*2

    mov     di, si
    add     di, ax
    mov     cx, [gs:di]            ; AND
    add     di, 32
    mov     dx, [gs:di]            ; XOR

    ; AND' = AND | (~clipmask)
    ; XOR' = XOR & clipmask
    mov     ax, bp
    not     ax
    or      cx, ax
    and     dx, bp

    pop     di
    ret


; ============================================================
; draw_line_masked (NASM bits16, CPU 386+ ok, pas de bpl/sil)
;
; Entrées:
;   ES:DI = adresse b0
;   BL    = off (0..7)
;   BH    = bytes_to_touch (1..3)
;   CX    = AND'
;   DX    = XOR'
;
; Détruit: AX,BP,SI,CL,DL,DH,AH
; (ok car caller recharge CX/DX à chaque ligne)
; ============================================================
draw_line_masked:
    push    si
    push    bp

    ; w0 = (b0<<8)|b1 dans SI
    mov     al, [es:di]
    mov     ah, [es:di+1]
    xchg    al, ah
    mov     si, ax

    ; seg in AX
    mov     ax, si
    test    bl, bl
    jz      .seg_ready

    cmp     bh, 3
    jne     .seg_no_b2

    ; BP = w1 = (b1<<8)|b2
    mov     al, [es:di+1]
    mov     ah, [es:di+2]
    xchg    al, ah
    mov     bp, ax

    mov     ax, si                 ; AX=w0
    mov     cl, bl
    shl     ax, cl
    mov     cl, 8
    sub     cl, bl
    shr     bp, cl
    or      ax, bp
    jmp     .seg_ready

.seg_no_b2:
    mov     cl, bl
    shl     ax, cl

.seg_ready:
    ; newseg in BP
    and     ax, cx
    xor     ax, dx
    mov     bp, ax

    test    bl, bl
    jz      .write_aligned

    ; -------- b0 partiel --------
    ; val0 = newseg >> (8+off) dans AL
    mov     ax, bp
    mov     cl, bl
    add     cl, 8
    shr     ax, cl                 ; AL=val0

    ; mask0 = (1<<(8-off))-1 dans AH
    mov     cl, 8
    sub     cl, bl
    mov     ah, 1
    shl     ah, cl
    dec     ah

    ; b0 = (b0 & ~mask0) | (val0 & mask0)
    mov     dl, [es:di]
    mov     dh, ah
    not     dh
    and     dl, dh
    not     dh
    and     al, dh
    or      dl, al
    mov     [es:di], dl

    cmp     bh, 1
    je      .ret

    ; -------- b1 complet --------
    mov     ax, bp
    mov     cl, bl
    shr     ax, cl                 ; AL=b1
    mov     [es:di+1], al

    cmp     bh, 2
    je      .ret

    ; -------- b2 partiel --------
    mov     ax, bp                 ; AL=newseg low

    ; lowmask = (1<<off)-1 dans DL
    mov     dl, 1
    mov     cl, bl
    shl     dl, cl
    dec     dl
    and     al, dl                 ; lowbits

    mov     cl, 8
    sub     cl, bl
    shl     al, cl                 ; part2

    ; mask2 = 0xFF << (8-off) dans DL
    mov     dl, 0FFh
    shl     dl, cl

    ; b2 = (b2 & ~mask2) | (part2 & mask2)
    mov     ah, [es:di+2]
    mov     dh, dl
    not     dh
    and     ah, dh
    not     dh
    and     al, dh
    or      ah, al
    mov     [es:di+2], ah
    jmp     .ret

.write_aligned:
    ; aligned: BP=(b0'<<8)|b1'
    mov     ax, bp
    xchg    al, ah                 ; AL=b0', AH=b1'
    mov     [es:di], al
    cmp     bh, 1
    je      .ret
    mov     [es:di+1], ah

.ret:
    pop     bp
    pop     si
    ret


; ------------------------------------------------------------
; Dessine le curseur 16x16 AND/XOR à [mouse.x,mouse.y]
;
; sprite (AND[16] suivi de XOR[16] à +32 bytes)
; ------------------------------------------------------------
gfx___cursor_draw:
            ; pusha

            mov       ax, BDA_DATA_SEG
            mov       ds, ax

            mov       ax, VIDEO_SEG
            mov       es, ax

						mov				ax, word [BDA_MOUSE + mouse.cur_ofs]
						mov				si, ax

						mov 			ax, word [BDA_MOUSE + mouse.cur_seg]
						mov 			gs, ax

            mov       cx, word [BDA_MOUSE + mouse.x]
            mov       dx, word [BDA_MOUSE + mouse.y]

						mov		 		word [BDA_MOUSE + mouse.cur_x], cx		; sauvegarde la nouvelle position
						mov		 		word [BDA_MOUSE + mouse.cur_y], dx

            ; calcule offset et bytes/ligne (2 ou 3)
            call      gfx_cursor_calc_align
						mov       bl, byte [BDA_MOUSE + mouse.cur_bit_ofs]; 0..7

            ; calcule DI de départ (attention: gfx_calc_addr modifie CL)
            push      cx
            call      gfx_calc_addr               ; DI ok, AH ignoré
            pop       cx
            ; dxbank = +0x2000 si DI < 0x2000, sinon dxbank = -0x2000
            mov       bp, 02000h
            cmp       di, bp
            jl        .bank_ok
            neg       bp                           ; bp = -0x2000
.bank_ok:
            ; on va dessiner 16 lignes: 8 paires (ligne dans bank courant + ligne dans autre bank)
            mov       bh, 0                        ; row index (0..15)
            mov       dh, 8
.pair:
            ; ----- ligne row (bank courant) -----
;            push      di
;            push      si
            call      .draw_line                   ; utilise DI, row=BX
;            pop       si
;            pop       di

            ; ----- ligne row+1 (autre bank) -----
            add       di, bp
            inc       bh
;            push      di
;            push      si
            call      .draw_line
;            pop       si
;            pop       di
            sub       di, bp

            ; avancer de 2 lignes (dans le bank courant): +80 bytes
            add       di, CGA_STRIDE

            inc       bh
            dec       dh
            jnz       .pair

            ; popa
            ret

; ------------------------------------------------------------
; .draw_line (8086 safe)
;
; BH = row (0..15)
; BL = bit offset (0..7)
; ES:DI = adresse b0
; GS:SI = base sprite
;
; détruit AX,CX,DX,BP
; préserve BX,SI,DI
; ------------------------------------------------------------
.draw_line:
    ; --- BP = row*2 ---
    xor     bp, bp
    mov     bl, bh
    shl     bl, 1
    mov     bp, bx            ; BP = row*2

    ; --- charger AND / XOR ---
    mov     cx, [gs:si + bp]       ; AND
    mov     dx, [gs:si + bp + 32]  ; XOR

    ; --- w0 = (b0<<8)|b1 ---
    mov     al, [es:di]
    mov     ah, [es:di+1]          ; AX = w0

    test    bl, bl
    jz      .aligned

    ; --- w1 = (b1<<8)|b2 ---
    mov     bp, ax                 ; BP = w0
    mov     al, [es:di+2]
    mov     ah, bh                 ; AH = b1
    xchg    al, ah                 ; BP = w1

    ; --- seg = (w0<<off)|(w1>>(8-off)) ---
    mov     cl, bl
    shl     ax, cl
    mov     cl, 8
    sub     cl, bl
    shr     bp, cl
    or      ax, bp                 ; AX = seg

    ; --- newseg ---
    and     ax, cx
    xor     ax, dx

    ; --- write unaligned ---
    ; b0
    mov     bp, ax
    mov     cl, bl
    add     cl, 8
    shr     bp, cl                 ; BP = val0
    mov     dl, 1
    mov     cl, 8
    sub     cl, bl
    shl     dl, cl
    dec     dl                     ; mask0
    mov     dh, [es:di]
    not     dl
    and     dh, dl
    not     dl
    or      dh, bl
    mov     [es:di], dh

    ; b1
    mov     cl, bl
    shr     ax, cl
    mov     [es:di+1], al

    ; b2
    mov     ax, bp
    mov     cl, bl
    ; and     al, (1<<cl)-1
    mov     cl, 8
    sub     cl, bl
    shl     al, cl
    mov     dl, 0FFh
    shl     dl, cl
    mov     dh, [es:di+2]
    not     dl
    and     dh, dl
    not     dl
    or      dh, al
    mov     [es:di+2], dh
    ret

.aligned:
    and     ax, cx
    xor     ax, dx
    mov     [es:di], ah
    mov     [es:di+1], al
    ret

; ------------------------------------------------------------
; Sauvegarde le background (24x16) sous le curseur
;
; utilise les variables du BDA pour stocker
; ------------------------------------------------------------
gfx___cursor_savebg:
						cmp 			byte [BDA_MOUSE + mouse.bkg_saved], 0
						jne 	  	.done																	; ne pas sauver tant qu'il y a une image

						mov		 		byte [BDA_MOUSE + mouse.bkg_saved], 1	; image saved

						mov				cx, [BDA_MOUSE + mouse.x]							;
						mov				dx, [BDA_MOUSE + mouse.y]

						call    	gfx_calc_addr   		        					; ES:DI = byteaddr pour (X,Y)
						mov 			dx,0x2000															; offset pour lignes impaire
						cmp		 		di,dx
						jl      	.no_odd_bank
						neg		 		dx																		; Y est déja une ligne impaire, on retire l'offset

.no_odd_bank:
						mov       ax, di																; préserver l'address de départ
						mov       word [BDA_MOUSE + mouse.cur_addr_start],ax
						mov			  word [BDA_MOUSE + mouse.cur_bank_add], dx

						mov 			ax, BDA_MOUSE + mouse.bkg_buffer
						mov     	si, ax																; DS:SI = buffer de sauvegarde
						mov     	bx, 8

.row:				; sauve 3 bytes/ligne
						; ligne 'y', peut etre paire ou impaire
						mov     	ax, word [es:di]											; charge first word
						mov     	word [ds:si], ax											; sauvegarde
						mov		 		al, byte [es:di+2]										; charge 3ème byte
						mov     	byte [ds:si+2], al
						add		 		si, 3

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx																; charge first word other bank (+0x2000 ou -0x2000)
						mov     	ax, word [es:di]
						mov     	word [ds:si], ax
						mov		 		al, byte [es:di+2]
						mov     	byte [ds:si+2], al
						add		 		si, 3
						sub		 		di, dx
						add 			di, CGA_STRIDE * 2
						dec     	bx
						jnz     	.row
.done:
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


; ------------------------------------------------------------
; restore le background (24x16)
;
; utilise les variables du BDA pour stocker
; ------------------------------------------------------------
gfx___cursor_restorebg:
						cmp 			byte [BDA_MOUSE + mouse.bkg_saved], 0		; pas de background sauvé
						je 		  	.done

						mov		 		cx,word [BDA_MOUSE + mouse.cur_x]				; restore de la position
						mov		 		dx,word [BDA_MOUSE + mouse.cur_y]
						mov		 		byte [BDA_MOUSE + mouse.bkg_saved], 0		; le background a été restauré

						mov 			ax, word [BDA_MOUSE + mouse.cur_addr_start]
						mov				di,ax
						mov				dx, word [BDA_MOUSE + mouse.cur_bank_add]

						mov 			ax, BDA_MOUSE + mouse.bkg_buffer
						mov     	si, ax																	; DS:SI = buffer de sauvegarde
						mov     	bx, 8																		; 16 lignes, mais nous traitons "en une fois" les paire/impaires

.row:			; restore en 3 bytes/ligne
						; ligne 'y', peut etre paire ou impaire
						mov     	ax,word [ds:si]													; recupère le 1er word
						mov     	word [es:di],ax
						mov     	al,byte [ds:si+2]												; charge 3ème byte
						mov		 		byte [es:di+2],al
						add		 		si, 3

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx											; autre banque mémoire
						mov     	ax,word [ds:si]							; recupère le 1er word
						mov     	word [es:di],ax
						mov     	al,byte [ds:si+2]						; charge 3ème byte
						mov		 		byte [es:di+2],al
						add		 		si, 3

						sub		 		di, dx											; destination - bank
						add 			di, CGA_STRIDE * 2					; desination+=160 (on vient de faire 2 lignes)
						dec     	bx
						jnz     	.row
.done:
;						popa
						ret

