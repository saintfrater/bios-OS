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
;   BL = color (0=black, !=0=white)
; ------------------------------------------------------------
gfx_putpixel:
						pusha
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
						popa
						ret

; ------------------------------------------------------------
; Lit un pixel (CX=x, DX=y)
; Out: AL=0/1
; ------------------------------------------------------------
gfx_getpixel:
						push    	ax
						push    	di
						push    	es

						call    	gfx_calc_addr
						mov     	al, [es:di]
						and     	al, ah
						setnz   	al

						pop     	es
						pop     	di
						pop     	ax
						ret

; ------------------------------------------------------------
; Dessine un background "check-board", accès VRAM direct.
;
; ------------------------------------------------------------
gfx_background:
						mov				ax,VIDEO_SEG
						mov				es,ax
						xor				di,di
						mov				ax,0xaaaa
						mov				cx,0x1000
						rep				stosw
						mov				ax,0x5555
						mov				cx,0x1000			; 640/8/2
						rep				stosw
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
        		cmp     	al, 0
        		jne     	.unaligned
        		mov     	byte [BDA_MOUSE + mouse.cur_bytes], 2
        		ret
.unaligned:
        		mov     	byte [BDA_MOUSE + mouse.cur_bytes], 3
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

; ------------------------------------------------------------
; Dessine le curseur 16x16 AND/XOR à [BDA_CURSOR_NEWX],[BDA_CURSOR_NEWY]
;
; CS:SI = base du sprite (AND[16] suivi de XOR[16] à +32 bytes)
; Uses: BDA_CURSOR_BITOFF/BDA_CURSOR_BYTES (via gfx_cursor_calc_align)
; ------------------------------------------------------------
gfx_cursor_draw:
            pusha

            mov       ax, BDA_DATA_SEG
            mov       ds, ax
            mov       ax, VIDEO_SEG
            mov       es, ax

						mov				ax, word [BDA_MOUSE + mouse.cur_ofs]
						mov				si, ax

            mov       cx, word [BDA_MOUSE + mouse.cur_newx]
            mov       dx, word [BDA_MOUSE + mouse.cur_newy]

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
            push      di
            push      si
            call      .draw_line                   ; utilise DI, row=BX
            pop       si
            pop       di

            ; ----- ligne row+1 (autre bank) -----
            add       di, bp
            inc       bh
            push      di
            push      si
            call      .draw_line
            pop       si
            pop       di
            sub       di, bp

            ; avancer de 2 lignes (dans le bank courant): +80 bytes
            add       di, CGA_STRIDE

            inc       bh
            dec       dh
            jnz       .pair

            popa
            ret

; ------------------------------------------------------------
; .draw_line: applique AND/XOR sur une ligne de 16 pixels à ES:DI
; row index dans BX (0..15)
; offset dans BL (0..7)
; sprite base CS:SI
; ------------------------------------------------------------
.draw_line:
           	push      ax
           	push      cx
           	push      dx
           	push      bp
           	push      di

           	; charger masks de la ligne: AND = [SI + row*2], XOR = [SI + 32 + row*2]
						xor			  ax, ax
           	mov       al, bh
           	shl       ax, 1                         ; row*2

						push			si
					 	add       si, ax
           	mov       cx, [cs:si]              ; AND mask
						add			  si, 32
           	mov       dx, [cs:si]     			    ; XOR mask
						pop			  si

							; lire bytes source
           	mov       al, [es:di]                    ; b0
						inc			 	di
           	mov       ah, [es:di]                  ; b1
						dec			 	di
           	; w0 = (b0<<8)|b1 dans AX déjà

           	cmp       bl, 0
           	je        .aligned

           	; unaligned: besoin b2 et w1 = (b1<<8)|b2
						add			 	di, 2
           	mov       dl, [es:di] 	                 ; b2
						sub			 	di, 2
           	mov       dh, ah                         ; b1
           	; DX = w1 (b1<<8)|b2

           	; seg = (w0<<off) | (w1>>(8-off))
           	; off = BL, rshift = (8-BL)
           	push      bx                             ; sauvegarde row/off
           	mov       cl, bl
           	shl       ax, cl                         ; AX = w0<<off

           	mov       cl, 8
           	sub       cl, bl                         ; cl = 8-off
           	shr       dx, cl                         ; DX = w1>>(8-off)

           	or        ax, dx                         ; AX = seg (16 bits alignés)
           	pop       bx

           	jmp       .apply_masks

.aligned:
            ; seg = w0 déjà dans AX
.apply_masks:
           	; newseg = (seg & AND) ^ XOR
           	and       ax, cx
           	xor       ax, dx                         ; AX = newseg

           	cmp       bl, 0
           	je        .write_aligned

           	; --- write unaligned: impact sur b0 (bas 8-off bits), b1 (tout), b2 (haut off bits) ---
           	; n = 8-off
           	mov       cl, 8
           	sub       cl, bl                         ; cl = n (1..7)

           	; val0 = newseg >> (8+off)
           	; (8+off) = 8 + BL
           	mov       dx, ax
           	mov       cl, bl
           	add       cl, 8
           	shr       dx, cl                         ; DL = val0 (0..(2^(8-off)-1))

           	; mask0 = (1<<n)-1
           	mov       cl, 8
           	sub       cl, bl                         ; cl = n
           	mov       al, 1
           	shl       al, cl
           	dec       al                              ; AL = mask0
           	; b0 = (b0 & ~mask0) | val0
           	mov       ah, [es:di]                    ; reload b0
           	not       al
           	and       ah, al
           	not       al                              ; AL back to mask0
           	or        ah, dl
           	mov       [es:di], ah

           	; b1 = (newseg >> off) & 0xFF
           	mov       dx, ax
           	mov       cl, bl
           	shr       dx, cl
						inc			 	di
           	mov       [es:di], dl
						dec			 	di

           	; b2 high off bits = (newseg & ((1<<off)-1)) << (8-off)
           	; lowbits = newseg & ((1<<off)-1)
           	mov       dx, ax
           	mov       cl, bl
           	mov       al, 1
           	shl       al, cl
           	dec       al                              ; AL=(1<<off)-1
           	and       dl, al                          ; DL = lowbits
           	mov       cl, 8
           	sub       cl, bl                          ; cl = 8-off
           	shl       dl, cl                          ; DL = bits pour b2 (dans le haut)

           	; mask2 = 0xFF << (8-off)
           	mov       al, 0FFh
           	shl       al, cl                          ; AL = mask2
						add		 		di, 2
           	mov       ah, [es:di]           	        ; b2 original
           	not       al
           	and       ah, al                          ; clear affected high bits
           	not       al
           	or        ah, dl
           	mov       [es:di], ah
						sub		 		di, 2

           	jmp       .done

.write_aligned:
            ; écrire 2 bytes seulement
            mov				[es:di], ah                     ; high
						inc			 	di
            mov       [es:di], al 	                  ; low
.done:
            pop       di
            pop       bp
            pop       dx
            pop       cx
            pop       ax
            ret


; ------------------------------------------------------------
; Sauvegarde le background (24x16) sous le curseur
;
; utilise les variables du BDA pour stocker
; ------------------------------------------------------------
gfx_cursor_savebg:
						pusha																	; sauvegarde registres

						mov				ax, BDA_DATA_SEG
						mov				ds, ax

						mov		 		ax, VIDEO_SEG
						mov		 		es, ax

						cmp 			byte [BDA_MOUSE + mouse.bkg_saved], 0
						jne 	  	.done												; déjà sauvé

						mov				cx, [BDA_MOUSE + mouse.x]
						mov				dx, [BDA_MOUSE + mouse.y]

						mov		 		byte [BDA_MOUSE + mouse.bkg_saved], 1	; flag image saved

						mov		 		word [BDA_MOUSE + mouse.cur_newx], cx	; sauvegarde la nouvelle position
						mov		 		word [BDA_MOUSE + mouse.cur_newy], dx

						call    	gfx_calc_addr   		        ; ES:DI = byteaddr pour (X,Y)
						mov 			dx,0x2000										; offset pour lignes impaire
						cmp		 		di,dx
						jl      	.no_odd_bank
						neg		 		dx													; Y est déja une ligne impaire, on retire l'offset
.no_odd_bank:
						mov 			ax, BDA_MOUSE + mouse.bkg_buffer
						mov     	si, ax						; DS:SI = buffer de sauvegarde
						mov     	bx, 8

						and				cx,0x0007										; alignement X
						jnz 			.row3

.row3:			; sauve 3 bytes/ligne
						mov		 		byte [BDA_MOUSE + mouse.cur_bytes], 3	; 3 bytes/ligne
						; ligne 'y', peut etre paire ou impaire
						mov     	ax, word [es:di]						; charge first word
						mov     	word [ds:si], ax						; sauvegarde
						mov		 		al, byte [es:di+2]					; charge 3ème byte
						mov     	byte [ds:si+2], al
						add		 		si, 3

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx											; charge first word other bank (+0x2000 ou -0x2000)
						mov     	ax, word [es:di]
						mov     	word [ds:si], ax
						mov		 		al, byte [es:di+2]
						mov     	byte [ds:si+2], al
						add		 		si, 3
						sub		 		di, dx
						add 			di, CGA_STRIDE
						dec     	bx
						jnz     	.row3
						jmp				.done

.row2:			; sauve 2 bytes/ligne
						mov		 		byte [BDA_MOUSE + mouse.cur_bytes], 2 	; par défaut
						; ligne 'y', peut etre paire ou impaire
						mov     	ax, word [es:di]						; charge first word
						mov     	word [ds:si], ax						; sauvegarde
						add		 		si, 2

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx											; charge first word other bank (+0x2000 ou -0x2000)
						mov     	ax, word [es:di]
						mov     	word [ds:si], ax
						add		 		si, 2
						sub		 		di, dx
						add 			di, CGA_STRIDE
						dec     	bx
						jnz     	.row3
.done:
						popa
						ret

; ------------------------------------------------------------
; restore le background (24x16)
;
; utilise les variables du BDA pour stocker
; ------------------------------------------------------------
gfx_cursor_restorebg:
						pusha																	; sauvegarde registres

						mov				ax, BDA_DATA_SEG
						mov				ds, ax

						mov		 		ax, VIDEO_SEG
						mov		 		es, ax

						cmp 			byte [BDA_MOUSE + mouse.bkg_saved], 0	; pas de background sauvé
						je 		  	.done

						mov		 		cx,word [BDA_MOUSE + mouse.cur_oldx]		; restore de la position
						mov		 		dx,word [BDA_MOUSE + mouse.cur_oldy]
						mov		 		byte [BDA_MOUSE + mouse.bkg_saved], 0	; le background a été restauré

						call    	gfx_calc_addr   		        ; ES:DI = byteaddr pour (X,Y)
						mov 			dx,0x2000										; offset pour lignes impaire
						cmp		 		di,dx
						jl      	.no_odd_bank
						neg		 		dx													; Y est déja une ligne impaire, on retire l'offset
.no_odd_bank:
						
						mov 			ax, BDA_MOUSE + mouse.bkg_buffer
						mov     	si, ax																; DS:SI = buffer de sauvegarde
						mov     	bx, 8

						cmp		 		byte [BDA_MOUSE + mouse.cur_bytes], 2	; si la sauvegarde est en 2 bytes/ligne
						je 				.row2

.row3:			; restore en 3 bytes/ligne
						; ligne 'y', peut etre paire ou impaire
						mov     	ax,word [ds:si]							; recupère le 1er word
						mov     	word [es:di],ax
						mov     	al,byte [ds:si+2]						; charge 3ème byte
						mov		 		byte [es:di+2],al
						add		 		si, 3

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx											; charge first word other bank (+0x2000 ou -0x2000)
						mov     	ax,word [ds:si]							; recupère le 1er word
						mov     	word [es:di],ax
						mov     	al,byte [ds:si+2]						; charge 3ème byte
						mov		 		byte [es:di+2],al
						add		 		si, 3
						sub		 		di, dx
						add 			di, CGA_STRIDE
						dec     	bx
						jnz     	.row3
						jmp				.done

.row2:			; restore en 2 bytes/ligne
						; ligne 'y', peut etre paire ou impaire
						mov     	ax,word [ds:si]							; recupère le 1er word
						mov     	word [es:di],ax
						add		 		si, 2

						; ligne 'y'+1; si paire +0x2000, si impaire -0x2000
						add		  	di, dx											; charge first word other bank (+0x2000 ou -0x2000)
						mov     	ax,word [ds:si]							; recupère le 1er word
						mov     	word [es:di],ax
						add		 		si, 2
						sub		 		di, dx
						add 			di, CGA_STRIDE
						dec     	bx
						jnz     	.row2
.done:
						popa
						ret

