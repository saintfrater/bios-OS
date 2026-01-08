; =============================================================================
;  Project  : Custom BIOS / ROM
;  File     : gfx_cgam.asm
;  Author   : frater
;  Created  : 06 jan 2026
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
%define BG16_SIZE     48


; ------------------------------------------------------------
; initialise le mode graphique (via l'int 10h)
; 
; ce mode est entrelacé, un bit/pixel, 8 pixels par octet
; ------------------------------------------------------------
gfx_init:
						; init graphics mode
						mov 			ah, 0x00     			; AH=00h set video mode
						mov				al, GFX_MODE
						int 			0x10

						call			gfx_background

						ret

; ------------------------------------------------------------
; Dessine un pixel, accès VRAM direct.
;
; In:
;   CX = x (0..639)
;   DX = y (0..199)
;   AL = color (0=black, !=0=white)
;
; ------------------------------------------------------------
gfx_putpixel:
						push	    bx
						push  	  di
						push    	es

						mov	     ax, VIDEO_SEG
						mov 	    es, ax

						; DI = (y>>1)*80 + (x>>3) + (y&1)*0x2000
						mov 	    bx, dx
						and   	  bx, 1                      ; BX = y&1

						mov	  	  ax, dx
						shr	    	ax, 1                      ; AX = y>>1
						mov 	   	di, ax
						mov 	    ax, di
						mov   	  di, CGA_STRIDE
						mul     	di                         ; DX:AX = (y>>1)*80
						mov 	    di, ax

						test  	  bx, 1
						jz      	.bank_ok
						add  		  di, CGA_ODD_BANK
.bank_ok:
						mov  		  ax, cx
						shr  		  ax, 3                      ; AX = x>>3
						add  		  di, ax

						; masque bit = 0x80 >> (x&7)
						mov     	bl, cl
						and     	bl, 7                      ; BL = x&7
						mov     	ah, 080h
						mov     	cl, bl
						shr     	ah, cl                     ; AH = bitmask

						; write
						cmp  	   	al, 0
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
						pop     	bx
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
